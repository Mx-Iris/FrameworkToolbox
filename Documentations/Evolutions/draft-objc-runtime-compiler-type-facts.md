# Draft - ObjC runtime 宏改由编译器判断 type encoding 与隔离

- **状态**: In Progress
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **实现分支**: `feature/macro-patterns`

## 摘要

`ObjCRuntimeToolbox` 的 hook 与 proxy 宏有三件事要靠类型判断，过去都按拼写猜：

1. **type encoding**（ObjC 运行时描述方法签名的字符串，如 `v@:@B`）。宏查一张表，表外的名字一律当对象 `@`。
   于是 `TimeInterval`、`NSInteger`、`pid_t` 这类 typealias，所有 NS_ENUM / NS_OPTIONS 和 `@objc enum`，以及
   `NSRect` 这种结构体的别名都会猜错：hook 在 install 时比对失败，只能手写 `typeEncoding:` 绕过；`@RuntimeClassProxy`
   没有这个参数，整个 proxy 校验失败、不可用。
2. **proxy 返回值按对象还是按值读回**。同样按表判断，表外的名字一律按对象读。单把第 1 件修对而不修这件，会把「校验
   失败、proxy 拒绝工作」这种安全的失败，变成「校验通过，再按对象去读一个 `double`」的崩溃，所以两件必须一起改。
3. **hook 容器的隔离**。运行时在任意线程上同步调用 replacement，容器不能被 actor 隔离。宏只认方法上写出来的
   `@MainActor`，看不到容器类型上的 `@MainActor`、遵循隔离协议推断来的隔离，也看不到默认 MainActor 隔离（SE-0466，
   Xcode 26 新建 App 的默认设置）。这时报错落在生成的跳板代码里（`call to main actor-isolated initializer … in a
   synchronous nonisolated context`），看不出原因。

本提案把这三件事都交给编译器（skill 技巧 2 的思路：用一组只差约束的重载，让编译器按类型选）。

## 方案

**type encoding。** 表里认得的类型照旧生成字符串字面量，已有调用点的展开一字不变；表外的名字改为生成
`ObjCRuntimeToolbox._ObjCTypeEncoding.of(T.self)`，整个签名用 `_ObjCTypeEncoding.method([…])` 拼起来。`of(_:)` 是一组重载，
由调用点的重载决议选：

- 具体类型（`Int`、`Double`、`CGFloat`、`Bool`、指针、`Selector`、`CGRect` 等结构体）各有一个非泛型重载。typealias 在
  这里被编译器自动看穿；非泛型重载胜过泛型重载，所以同时是 `_ObjectiveCBridgeable` 的 `Int` 仍编码为 `q`。
- 按类型「是什么」的泛型重载：`AnyObject`（类与 class-bound 存在类型，`@`）、`_ObjectiveCBridgeable`（`String` 等，`@`）、
  `RawRepresentable`（NS_ENUM / NS_OPTIONS / `@objc enum`，编码为原始值的类型），以及两两重叠时的交集重载。
- 新增公开协议 `ObjCTypeEncodable`：表外的结构体（如 `CATransform3D`）可以自己声明 encoding。上面那些泛型重载都标
  `@_disfavoredOverload`，所以一个类型同时满足其中某条和 `ObjCTypeEncodable` 时，以它自己声明的为准。
- 什么都不满足时落到一个兜底重载，返回 `"?"`（运行时比对必然失败，与改动前的结果相同），并用 `@available(*, deprecated)`
  在调用点给出一条说明原因和改法的警告，而不是硬错误——不让过去能编译的代码编不过。

**proxy 返回值。** 表外的返回类型同时生成两种读法——按对象（经 `Unmanaged`，处理 `nil` 和 `alloc`/`new`/`copy`/
`mutableCopy` 的所有权规则）与按值——交给 `RuntimeClassProxySupport._returnValue` 的两个重载：`Value: AnyObject` 的那个走
对象读法，另一个走按值读法。两个闭包对 ObjC 能返回的任何类型都合法（开启 ObjC 互操作时 `@convention(c)` 接受桥接类型），
没选中的那个从不执行。原计划用一个按返回类型重载的嵌套宏生成方法体，这个做法更简单，同样由编译器决定，见决策日志。

**容器隔离。** `@RuntimeClassHook` 在生成的 `descriptors()` 里、`@DynamicSubclassHook` 在 `installOverridesIfNeeded(on:)`
里，各放一个 `#_HookContainerIsolationCheck(initializer: Container.init(…))`，并用 `#sourceLocation` 映射到容器上的宏属性
那一行。容器被隔离时，它的 `init` 作为函数值带 `@MainActor`，只能匹配报错的那个重载；否则无需转换的那个胜出，什么也不生成。
报错说明原因，并提示把容器标成 `nonisolated`。

**proxy 生成的类型标 `nonisolated`。** 在默认 MainActor 隔离的模块里，`…Implementation` 结构体会被推断成主线程隔离，后台
线程连构造都不行；它的方法作为协议 requirement 的 witness，还会从被隔离的协议继承隔离，所以方法和属性也逐个标
`nonisolated`。在普通模块里它们本来就不隔离。

### 源码兼容性

只用表内类型的 hook 与 proxy，encoding 与读法的展开不变；多出的只有容器隔离探针、`descriptors()` 里显式的 `return`，以及
proxy 上的 `nonisolated`。用到表外类型的：原来校验失败、运行时不可用的，现在可以用；完全推不出 encoding 的类型从「运行时
失败」变为「运行时失败加一条编译警告」。被隔离的容器原来就编不过（Swift 6 模式下）或在非主线程执行主 actor 代码
（Swift 5 模式下），现在多一条指向容器的明确报错。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 按 `swift-macro-patterns` skill 的技巧审视全部宏时发现：hook 与 proxy 宏把三个只有编译器知道的类型事实交给了拼写去猜 |
| 2026-10-27 | 用户批准，开始实现 | 审视结论中的各项改进经用户同意全部实施 |
| 2026-10-27 | encoding 与 proxy 返回值读法同批落地 | 只修 encoding 会让原本校验失败、被安全拒绝的 proxy 通过校验，再把标量当对象读回而崩溃 |
| 2026-10-27 | proxy 返回值改用普通函数重载，不用嵌套宏 | hook 的现有测试表明 `@convention(c)` 在开启 ObjC 互操作时接受 `String` 这类桥接类型，因此「按值读」的闭包对 ObjC 能返回的任何类型都合法；两条读法都生成、由 `_returnValue` 的重载按 `Value: AnyObject` 选，效果相同，省掉一个要解析代码片段参数的嵌套宏 |
| 2026-10-27 | 推不出 encoding 时只警告不报错 | 硬错误会让过去能编译的代码编不过；警告配合运行时比对失败（与改动前相同）已能把问题指到调用点 |
| 2026-10-27 | 隔离探针的第二个重载多一个带默认值的占位参数 | 实测：本包是 Swift 5 语言模式，两个只差 `@MainActor` 的宏声明被判为 `invalid redeclaration`；占位参数不参与重载选择 |
| 2026-10-27 | proxy 的类型与成员标 `nonisolated` | 默认 MainActor 隔离的守卫（`DefaultMainActorIsolationClient`）实测：构造 proxy 与调用其方法都报 `call to main actor-isolated … in a synchronous nonisolated context`；只给类型标还不够，witness 会从协议继承隔离 |
| 2026-10-27 | 实测通过 | 运行时测试：hook 的签名全用表外拼写（`TimeInterval`、`@objc enum`、`NSInteger`）时能安装并正确转发；proxy 的表外标量按值读回、表外的类按对象读回且 1000 次读取不多释放；`_ObjCTypeEncoding` 的重载在测试里由真实编译器选择（typealias、具体类型优先于桥接、导入的枚举、`@objc` 协议存在类型、`NSNotification.Name`、自声明的 encoding）。主线程隔离的容器用临时文件编译一次：报错落在 `@RuntimeClassHook(...)` 那一行，随后删除 |
| 2026-10-27 | `@DynamicSubclassHook` 既有的并发竞态记为后续项，不在本分支修 | 拆分提交时的一次完整测试里，`testConcurrentInstallUninstallOnDistinctInstances` 失败一次（装上 hook 后读到原实现的 `0`），重跑通过。原因在生成的 `installOverridesIfNeeded(on:)`：`claimOverrideInstallation` 先认领槽位、之后才逐个添加 override，认领比安装先对其他线程可见；并发的第二个线程认领失败后直接返回、换 isa 并调用，可能赶在 override 加进子类之前。这段逻辑在 main 上相同，本提案只在函数开头加了一个不生成代码的隔离探针，与这个竞态无关 |
| 2026-10-27 | 多平台构建 | 本提案新加了 `#if canImport(ObjectiveC)` 与 `#if os(macOS)`，按项目规定逐平台构建 `ObjCRuntimeToolbox`：macOS、iOS、Mac Catalyst 通过；本机的 Xcode 26.5 没有安装 watchOS、tvOS、visionOS 平台组件，这三个平台未能构建 |
| 2026-10-27 | `CGFloat` 一族在 arm64_32 上的 encoding 记为后续项 | 编码表把 `CGFloat` 写死为 `d`，`CGPoint` / `CGSize` / `CGRect` 写死为双精度布局，新加的 `_ObjCTypeEncoding.of(CGFloat.self)` 等重载沿用了同样的值。`CGBase.h` 只在 `__LP64__` 下把 `CGFloat` 定义为 `double`，watchOS 真机的 arm64_32 不是 LP64，那里正确的编码是 `f` 与 `{CGPoint=ff}`。后果是这类签名的 hook 在安装时校验失败、proxy 拒绝工作，属于安全的失败，与改动前相同。修法是让这几个类型也走由编译器选择的重载、按 `MemoryLayout<CGFloat>.size` 取值，但那会改变已有调用点的展开结果，留待另行决定；本机没有 watchOS 平台，未能实测 |
| 2026-10-27 | 实现完成，待合并 | 干净构建下的完整测试套件通过 |
