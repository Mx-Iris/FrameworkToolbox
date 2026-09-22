# FrameworkToolbox 文档索引

一组分层的 Swift 工具库与宏。**新增或重命名任何文档都必须同步更新这份索引。**

> **项目类型：库（源码分发）**。SPM library product，使用方每次重新编译，
> 无 ABI 约束，但**源码兼容性必须评估** —— 本库被多个项目依赖，且大量能力以宏的形式暴露，
> 宏展开结果的变化同样是源码层面的破坏。提案见 [`Evolutions/README.md`](Evolutions/README.md)。

| 目录 | 用途 |
|------|------|
| [`Evolutions/`](Evolutions/) | **提案** —— 今后所有新功能与架构改动的唯一入口 |
| [`Specs/`](Specs/) | 提案制确立前的设计文档。保留归档，不再新增 |
| [`Plans/`](Plans/) | 与 `Specs/` 配对的实现计划。保留归档，不再新增 |

## 提案（Evolutions）

- [0001 —— 把 dyld interposing 抽成独立的 DyldToolbox](Evolutions/0001-dyld-toolbox-extraction.md)（Implemented）
- [0002 —— 仿 `@Loggable` / `#log` 实现 os_signpost](Evolutions/0002-signpost-macros.md)（Implemented）
  新增 `@Signpostable` 与 `#signpost`，三种调用形态；顺带修 `#log` 带插值时依赖调用方 `import Foundation` 的缺陷。
- [0003 —— 把 `ObjCRuntimeToolbox` 恢复为自包含的 `.dynamic` 叶子](Evolutions/0003-objc-runtime-toolbox-self-contained-leaf.md)（Implemented）
  0.10.0 给它加的 `OSToolbox` 运行时依赖让 Xcode 把传递闭包整体建成共享动态 framework，压垮了 RuntimeViewer 无 rpath 的嵌套 daemon；解除依赖并加 dump-package 守卫测试。
- [0004 —— 给 `@Loggable` / `@Signpostable` 加启用开关，并解除泛型类型的限制](Evolutions/0004-logging-enable-switch.md)（Implemented）
  新增 `isEnabled:` 宏参数与 `LoggingControl` / `SignpostingControl` 运行时入口，关闭状态用 `OSLog.disabled` 一族的空句柄表达；
  同批次去掉泛型支的 static 存储属性，泛型类型不必再绕协议。
- [draft —— 给被类型擦除的 NS 集合类补回 Swift 泛型](Evolutions/draft-objective-c-typed-collections.md)（Implemented）
  `NSArray` / `NSDictionary` / `NSSet` 六个类在 Swift 里被 clang importer 主动擦除了轻量泛型参数；本提案用六个引用语义的泛型 struct 把类型套回去，并实现 `_ObjectiveCBridgeable` 保住对象身份。
- [draft —— 用 `@_rawLayout` 把 `Mutex` 的锁与值内联](Evolutions/draft-inline-mutex-raw-layout.md)（Deferred，**暂不采纳**）
  标准库 `Synchronization.Mutex` 靠 `@_rawLayout` 做到零堆分配，本库的 `Mutex` 每个实例一次 `malloc`。
  移植实测可行、布局与标准库逐字节一致，但要绑定三个无 Swift Evolution 提案的实验性编译器特性；
  当前全代码库只有一个 `Mutex` 实例，收益不抵代价。文内留有性能实测数据与翻案条件。
- [draft —— 引入 SwiftStdlib 可用性宏，收掉四平台长写法](Evolutions/draft-availability-macros.md)（Implemented）
  `@available(SwiftStdlib 5.7, *)` 取代四平台长写法，定义表照搬上游以保持同义。
  两个禁区：`@inlinable` 函数体（编译器当场拒绝）与宏展开结果（编译器**不给任何诊断**，炸在下游）。
- [draft —— 把 lexic 的五个枚举宏并入 `SwiftStdlibToolbox`](Evolutions/draft-lexic-enum-macros.md)（Implemented）
  从 [ordo-one/lexic](https://github.com/ordo-one/lexic) 搬入五个枚举宏：`@Bijection`、`@CaseTag`、`@MirroredCases`、`@DefaultedCases`、`@Projection`
  （后三个是上游 `@Discriminated` / `@Discriminant` / `@ambient` 的改名，原名是不可读的类型论术语）。
  顺带把上游那套宏参数解码机制放进 `MacroToolbox`。不新增 target，不改包拓扑。
- [draft —— 让 `@Projection` 支持多关联值的 case，并修掉展开出的 unreachable default](Evolutions/draft-projection-multi-payload.md)（Implemented）
  投影匹配从「恰好一个关联值」放开到任意个数（含零个）；同批次修掉无条件生成 `default: nil` 导致的
  `default will never be executed` —— 那一行在调用方源码里并不存在，上游的测试数据恰好每个都留了一个
  无 payload 的 case，把它盖住了。
- [draft —— 把 `@Projection` 的字符串参数换成标记宏](Evolutions/draft-projection-marker-macro.md)（Implemented）
  `@Projection(through: "id")` 换成 `@Projection` + 贴在函数上的 `@ProjectionFunction`，魔法字符串消失。
  文内留有「为什么不能改成闭包或函数引用」的实测结论：引用宿主成员会 circular reference，泛型函数不能当函数值传，
  且即使传得进去宏也只能拿到名字。
- [draft —— 让序列比较可以指定用哪一套排序定义](Evolutions/draft-sequence-comparison-selection.md)（Implemented）
  `ComparableBuildable` 目前一个类型只有一套排序规则；本提案让调用点选规则 ——
  `sorted(using: \.byAge)` 选类型上的具名定义，`sorted(by: \.age, .descending)` 直接按属性排。
  含一条不写对就慢 5.7 倍、却不产生任何诊断的实现约束：keyPath 必须在比较闭包内部应用。
  顺带修 `FrameworkToolboxCompatible.box` 的空 setter —— 它让所有经 `.box` 的 mutating 方法静默无效。

## 专题说明

- [`LogCategory` 与 `#log(category:)` 多 Category 支持](LoggableCategories.md) —— `@Loggable` / `#log` 从「一个类型一个 category」扩展为支持多 category 的经过。
- [`@Signpostable` 与 `#signpost` 用法契约与实现决策](SignpostMacros.md) —— 三种调用形态怎么选、区间凭据为什么要自带 log handle、为什么防 Foundation 依赖的守卫必须独占一个 target。
- [关掉日志与埋点 —— `isEnabled:` 与运行时开关](LoggingSwitches.md) —— 三层开关怎么用、关掉之后为什么连插值都不求值、泛型限制怎么顺带解除的。
- [让自己的类型参与 Swift ↔ Objective-C 桥接](ObjectiveCBridging.md) —— `ObjectiveCRepresentable` 协议与 `@ObjectiveCBridgeable` 宏；四条契约，以及为什么那四个 witness 必须逐类型生成而不能写进协议扩展。
- [类型化的 NS 集合句柄 —— 用法契约与实现决策](TypedObjectiveCCollections.md) —— 六个泛型 struct 给 `NSArray` / `NSDictionary` / `NSSet` 一族补回元素类型；引用语义、变更方法为什么不是 `mutating`、为什么用 `init(validating:)` 而不是 `as?`。
- [五个枚举宏 —— 用法契约与实现决策](EnumMacros.md) —— `@Bijection` / `@CaseTag` / `@MirroredCases` / `@DefaultedCases` / `@Projection` 各自的契约与陷阱；为什么宏只认 `Int?` 不认 `Optional<Int>`，`@Bijection` 的 `borrowing` 与条件性 `copy` 绕的是哪个编译器崩溃，以及 `.recurring` 在没有期待类型时为什么有歧义。
- [指定排序定义 —— 用法契约与陷阱](ComparisonSelection.md) —— 一个类型怎么带多套排序规则、调用点怎么选；为什么必须是 `static var`、什么时候写裸 keyPath、`by:` 与 `using:` 的分工。
- [存储层重构与 `@UserDefault` 宏](StorageLayer.md) —— `@Keychain` 宏发布后，运行时与编码协议都是 Keychain 专用的；这篇记录如何把存储层抽象出来以容纳 `@UserDefault`。

## 设计文档（Specs，归档）

按时间倒序。有配套实现计划的并列给出。

- **`@DyldDynamicInterpose`**（2026-08-06）—— [设计](Specs/2026-08-06-dyld-dynamic-interpose-design.md)
  复活 dyld4 之后已成空函数的 `dyld_dynamic_interpose`：写入私有的 `__DATA,__dyn_interpose` 段，运行时自行读回并改写符号指针槽。可从主执行文件发起、可撤销。
  **代码位置已变更**：这套东西已由提案 [0001](Evolutions/0001-dyld-toolbox-extraction.md) 从 `SwiftStdlibToolbox` 迁至独立的 `DyldToolbox`；这篇设计文档描述的机制不变，但里面写的文件路径是旧的。
- **Dynamic 移植（DynamicObject）**（2026-08-06）—— [设计](Specs/2026-08-06-dynamic-invocation-design.md)
  基于 `NSInvocation` 的 `@dynamicMemberLookup` + `@dynamicCallable` 调用无头文件的类与方法。**含一条要命的约定**：对象返回值必须写成 `AnyObject?`，写成 `Any?` 能编译但会破坏内存。
  **日志实现已变更**：文中的 `@Loggable` / `#log` 方案（含「`#log` 要写显式 `self.`」一节）已由提案
  [0003](Evolutions/0003-objc-runtime-toolbox-self-contained-leaf.md) 改为共享的手写 `dynamicInvocationLog` 常量 + `os_log` ——
  `ObjCRuntimeToolbox` 不得在运行时依赖 `OSToolbox`。`@Loggable` 与 `@dynamicMemberLookup` 相容性的实测结论仍然成立，只是本模块不再是它的用例。
- **OSToolbox 抽取**（2026-08-06）—— [设计](Specs/2026-08-06-ostoolbox-extraction-design.md)
  分层与 re-export 链的调整。`@_exported import` 会把宏声明及其插件一并带过传递依赖，这是宏能下沉一层而不破坏调用点的原因。
  **守卫位置已变更**：文中的 `Sources/OSToolboxClient/LoggableWithoutFoundation.swift` 已由提案 [0002](Evolutions/0002-signpost-macros.md)
  移入独占的 `OSToolboxNoFoundationClient` target —— 它原先与一个 `import Foundation` 的 `main.swift` 同 target，
  而 Swift 的 conformance 查找是模块级的，那个守卫因此并不成立。
  **拓扑已再次变更**：文中「让 `ObjCRuntimeToolbox` 用上 OSToolbox」的一步已由提案
  [0003](Evolutions/0003-objc-runtime-toolbox-self-contained-leaf.md) 撤销 ——
  `.dynamic` 产品的运行时 target 依赖会被 Xcode 连同传递闭包一起建成共享动态 framework。
- **`@RuntimeClassHook` / `@RuntimeClassProxy`**（2026-08-05）—— [设计](Specs/2026-08-05-runtime-class-hook-design.md)
- **`ObjCRuntimeToolbox`**（2026-06-26）—— [设计](Specs/2026-06-26-objc-runtime-toolbox-design.md)
- **`@Keychain` 宏**（2026-06-24）—— [设计](Specs/2026-06-24-keychain-macro-design.md)
- **`#Selector` 字符串字面量宏**（2026-04-15）—— [设计](Specs/2026-04-15-selector-string-literal-macro-design.md) · [计划](Plans/2026-04-15-selector-string-literal-macro.md)
- **Available Storage 宏**（2026-04-14）—— 让「后备存储本身无法被 `@available` 门控」的属性也能对外暴露。
  [设计](Specs/2026-04-14-available-storage-macros-design.md) · [计划](Plans/2026-04-14-available-storage-macros.md)
