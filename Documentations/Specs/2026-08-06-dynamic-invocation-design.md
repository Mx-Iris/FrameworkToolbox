# Dynamic 移植设计（DynamicObject）

日期：2026-08-06

## 一句话

把 [mhdhejazi/Dynamic](https://github.com/mhdhejazi/Dynamic) 移植进 `ObjCRuntimeToolbox`，让这个库能"按名字调用没有头文件的 Objective-C 类和方法"，并顺手修掉上游的若干缺陷、换用本仓库的日志设施。

## 动机

`ObjCRuntimeToolbox` 此前覆盖的是 hook、方法替换、动态子类（isa-swizzling）、运行时代理——全都要求你**已经知道**方法签名。缺的是另一半：调一个压根没有声明的类和方法。

Dynamic 补的正是这块。它用 `@dynamicMemberLookup` + `@dynamicCallable` 把

```swift
ObjC.NSDateFormatter().stringFromDate(date)
```

翻译成运行时的 `NSMethodSignature` + `NSInvocation` 消息发送，调私有 API 时不用写任何桥接声明。

上游最后一次提交是 2021 年 10 月，之后没再维护，许可为 Apache 2.0。

## 范围

新增 `Sources/ObjCRuntimeToolbox/DynamicInvocation/`：

| 文件 | 对应上游 | 职责 |
|---|---|---|
| `DynamicObject.swift` | `Dynamic.swift` | 门面：成员查找、调用、属性读写、错误传播 |
| `DynamicObject+Unwrapping.swift` | `Dynamic.swift` 的 extension | `asString` / `asInt` / `asCGRect` 等解包访问器 |
| `RuntimeInvocation.swift` | `Invocation.swift` | 单次消息发送的组装与结果读取 |
| `RuntimeInvocationError.swift` | `InvocationError` | 失败原因 |
| `NSInvocationBridge.swift` | （新增，抽取自 `Invocation.swift`） | 对 `NSInvocation` / `NSMethodSignature` 的 runtime 调用 |
| `FoundationTypeBridging.swift` | `TypeMapping.swift` | Foundation 值类型 ↔ 对象类型互转 |

上游的 `Logger.swift` 没有对应文件——那套 `print` 日志整个删掉，改由 `DynamicObject` 和 `RuntimeInvocation` 各自的 `@Loggable` 承担（见下）。

测试：`Tests/ObjCRuntimeToolboxTests/DynamicObjectTests.swift`（swift-testing，47 个用例，9 个 suite）。

许可：`LICENSES/Dynamic-LICENSE` 存 Apache 2.0 全文与版权声明，每个移植文件头部有指向它的 attribution。

## 关键设计与取舍

### 命名：`DynamicObject`，保留 `ObjC` 别名

上游门面类型叫 `Dynamic`，但仓库里已经有 `DynamicSubclass` 和 `@DynamicSubclassHook`，同模块下两个"Dynamic"含义完全不同，读代码时容易误以为有关系。所以主类型定名 `DynamicObject`，同时保留 `public typealias ObjC = DynamicObject`——`ObjC.NSDateFormatter()` 这种写法正是这个库的招牌用法，而 `ObjC` 是 Apple 生态既定专有名词（`@objc`、`objc_msgSend`、`ObjCBool`），不属于自造缩写。

### `@Loggable` 直接标在 `DynamicObject` 上是安全的（实测结论）

`DynamicObject` 和 `RuntimeInvocation` 各标一个 `@Loggable(subsystem: "ObjCRuntimeToolbox", category: "DynamicInvocation")`，两处刻意填同一组参数，这样一条 `log stream` 谓词就能覆盖从成员访问到返回值的整条路径。

这里曾经绕过一次弯路，值得记下来。最初的顾虑是：`DynamicObject` 是 `@dynamicMemberLookup`，标上 `@Loggable` 会不会让 `logger` / `_osLog` / `subsystem` / `category` 变成无法转发给 Objective-C 的保留名——其中 `category` 恰恰是很常见的 Objective-C 属性名。于是日志一度被放在独立的 `@Loggable enum DynamicInvocationLog` 上。

**这个顾虑经实测证明是错的。** `@Loggable` 默认以 `.private` 发出它的成员，而 private 成员根本不参与动态成员查找所回退的那次名称查找。用真实的 `DynamicObject` 标上 `@Loggable` 后从另一个模块访问：

```
.category from another module -> DynamicObject: abc
.logger   from another module -> DynamicObject
```

两者都照常走了动态查找。同时 `#log` 在类型内部也能正常展开——在类型自身的成员实现里，private 成员是可见且优先的。两边同时成立，不冲突。

真正决定会不会遮蔽的是**调用方能否看见这个成员**，与成员来自哪里无关：

| 成员形态 | 从模块外访问 | 从声明所在文件访问 |
|---|---|---|
| `private` 实例成员 | 走动态查找 | 走动态查找 |
| `private` 静态成员 | 走动态查找 | 走动态查找 |
| 协议 extension（internal） | 走动态查找 | 走真实成员 |
| 协议 extension（**public**） | **走真实成员** | 走真实成员 |
| `public` 实例成员 | **走真实成员** | 走真实成员 |

顺带回答一个自然会想到的方案：**套一层协议解决不了问题**。协议扩展的成员是静态派发的，编译期就绑定，动态查找根本没机会介入；只要那个成员对调用方可见就会遮蔽。而 `@Loggable` 加在 protocol 上时会从协议声明继承访问级别，协议若是 public，反而比直接标注更容易遮蔽。

因此 `DynamicObject` 上真正无法转发的名字，只有它自己声明的那些 **public** 成员：`isError`、`debugDescription`、以及全部 `as…` 访问器。

### `#log` 在实例方法里要写显式 `self.`

`#log` 展开成一个立即执行的闭包，所以插值里引用实例属性必须写 `self.`：`\(debugDescription)` 编译不过，`\(self.debugDescription)` 才行。局部变量和参数不受影响。

### 结构信息标 `.public`，值保持 `<private>`

`os_log` 对字符串插值默认按私有处理，所以一开始抓下来的 trace 长这样，等于没写：

```
wrap class <private>
call [<private> <private>]
```

于是按内容分两类标注：**类名、selector 名、成员名标 `privacy: .public`**（它们是程序结构，不是用户数据，而且正是调试时唯一想看的东西）；**被包装对象的描述、参数值、返回值保持默认的私有**（这些可能带进任意用户数据——比如经由 `DynamicObject` 读写的 Keychain 值）。现在的输出是：

```
wrap class NSDateFormatter
call [NSDateFormatter setDateFormat:]
argument #1 = <private>
[stringFromDate:] returned <private>
```

结构完全可读，数据一律不落盘。整数插值（如 `argument #1` 的序号）在 `os_log` 里本就是公开的，不用额外标注。

### 用 `os_log` 的 debug 级别取代 `loggingEnabled` 开关

上游的日志是 `print` 打印带框线的树形结构，用 `Dynamic.loggingEnabled = true` 开启，配一个 `[ObjectIdentifier: Logger]` 的全局字典做 logger 缓存。那个字典只增不减（内存泄漏），而且键是 `ObjectIdentifier`——对象释放后地址复用会让日志串到别的对象上。

改为 `#log(.debug, ...)`。`os_log` 的 debug 级别本身就是"默认不持久化、按需开启"的设计，正是那个开关想要的效果，而且不用改代码重新编译：

```console
log stream --predicate 'subsystem == "ObjCRuntimeToolbox"' --level debug
```

于是 `loggingEnabled` 开关和整个 `Logger.swift` 一起删掉。

### `NSInvocationBridge`：把 8 处 `unsafeBitCast` 收敛到一个文件

`NSInvocation` 对 Swift 完全不可见，`NSMethodSignature` 也没有可用的 Swift 接口，所以每一次调用都得手工重建：查 `IMP`、把签名重写成 `@convention(c)` 函数类型、`unsafeBitCast` 过去。上游把这套三行模板在 8 个地方各写了一遍。

收进一个文件的价值不只是少写几行——**`unsafeBitCast` 是这段代码里唯一"签名写错不会编译报错、而会变成内存损坏"的地方**，放在一起才能对着头文件成组审查。

### 类型化抛出与 typed throws

`RuntimeInvocation.init` 声明为 `throws(RuntimeInvocationError)`，调用方不必再 `catch` 泛型 `Error`。

## 修掉的上游缺陷

| 问题 | 上游行为 | 现在 |
|---|---|---|
| 参数个数不匹配 | `for index in 0..<numberOfArguments - 2` 直接索引参数数组，数量对不上时 **trap**（Index out of range） | 先比对数量，不匹配则拒绝调用并记为 `argumentCountMismatch` 错误。回归测试 `selectorNeedingArgumentsIsRefusedInsteadOfTrapping()` |
| logger 全局字典 | 只增不减，且 `ObjectIdentifier` 地址复用会串日志 | 随 `Logger.swift` 一并删除 |
| `NSMeasurement` 映射 | `object as? Measurement` 缺泛型参数，新工具链编译不过 | 删掉该行，并在文档注释里说明为什么无法支持（`Measurement` 泛型于单位，类型擦除后无从还原） |
| Core Graphics 访问器 | 只在 `canImport(UIKit)` 下提供，macOS 上拿不到 `CGRect` / `CGSize` 等返回值 | 改为 `canImport(CoreGraphics)`，全平台可用；另补 macOS 的 `asNSEdgeInsets`（见下文平台守卫一节） |
| `returnType` 悬挂指针风险 | 保存 `NSMethodSignature` 内部的 `UnsafePointer<CChar>`，其有效期取决于签名对象是否存活 | 改为持有 `String`，需要 C 字符串时用 `withReturnTypeCString` 临时产生 |
| `returnedObject` 惰性求值 | `lazy var` 无 `isInvoked` 检查，未发送就访问会读到未定义内容 | 改为显式缓存，未发送时返回 `nil` |
| 全局可变状态并发 | `loggingEnabled`、`loggers`、`level` 全部无锁 | 开关删除；共享的 `DynamicObject.nil` 标 `nonisolated(unsafe)`，并有测试确认它永不被写入 |
| 手工堆分配 | 三处 `UnsafeMutablePointer.allocate` + `defer deallocate` | 换成 `withUnsafeTemporaryAllocation`（栈分配），`NSValue.getValue(_:)` 换成非弃用的 `getValue(_:size:)` |

## 移植期间自己踩的坑（值得记下来）

**`@convention(c)` 的返回类型必须是 C 兼容的。** 我把两处签名从上游的 `-> Any` / `-> AnyObject` 改写成了 `-> Any?`，想着"可能返回 nil，标成 Optional 更准确"。结果 `Optional<Any>` 是 32 字节的 existential container 而不是单指针，被调用方按 `id` 返回、调用方按 container 读取，第一次 `objc_retain` 就拿着垃圾指针段错误（崩溃地址 `0x320`）。

正确写法是 `-> AnyObject?`：它对应 `id _Nullable`，是单指针，nil 检测也天然正确——比上游的 `-> Any` 还更安全一些。

**`canImport(X)` 为真不等于 X 里的 API 可用。** 把平台守卫从上游的 `os(...)` 形式改写成 `canImport(...)` 时，我在两个地方踩空：

- `CATransform3D`：上游写的是 `#if !os(watchOS)`，我换成了 `canImport(QuartzCore)`。QuartzCore 在 watchOS 上能干净导入，但 `CATransform3D` 在那里被标为 unavailable，于是 watchOS 构建直接失败——这是我引入的回归，`!os(watchOS)` 携带着 `canImport` 没有的信息。现在写作 `canImport(QuartzCore) && !os(watchOS)`。
- `NSEdgeInsets`：写成 `canImport(AppKit)`。**Mac Catalyst 下 `canImport(AppKit)` 为真**（`os(macOS)` 为假），所以那段代码在 Catalyst 上确实参与编译；它当前能过，纯粹因为 `NSEdgeInsets` 恰好是 Foundation 的 C 结构体而非 AppKit 类。往同一个 extension 里加任何真正的 AppKit 类型都会立刻报 `'NSView' is unavailable in Mac Catalyst`（实测过）。现在写作 `os(macOS)`，Catalyst 调用方用 UIKit 那一节的 `asUIEdgeInsets`。

教训是：**`canImport` 回答的是"这个模块能不能导入"，不是"这个符号在这个平台上存不存在"**，而 Apple 的伞形框架在派生平台上普遍是"能导入、大部分不可用"。条件编译的回归无法用单元测试覆盖，只能靠逐平台构建，命令见下。

**类方法不要靠 `unsafeBitCast` 把 class object 伪装成 `NSObject`。** `+invocationWithMethodSignature:` 是类方法，我一开始把 class object `unsafeBitCast` 成 `NSObject` 再走实例方法那条查找路径，ARC 会去 retain 这个"对象"，同样段错误。改用 `class_getClassMethod` + `method_getImplementation` 直接问运行时要实现，完全绕开 ARC。

这两个坑都有共同点：**编译器一声不吭，错误只在运行时以内存损坏的形式出现**。这也是把所有 `unsafeBitCast` 收进 `NSInvocationBridge.swift` 一个文件的实际理由。

## 已知限制（上游未记录，现已写进 API 文档）

- **超过三个机器字的参数必须自己包成 `NSValue`。** Swift 把小值内联存在 `Any` 的 existential container 前部，这段代码传的是那块存储的地址；更大的值会被装箱到堆上，于是被调用方收到的是箱子指针而不是值本身。三个 `Int` 的结构体没问题，`CGRect` 不行。
- **`DynamicObject` 声明的成员会遮蔽同名的 Objective-C 成员。** `isError`、`debugDescription` 以及全部 `as…` 访问器都无法转发。
- **不是线程安全的。** 一个实例会在链式调用中累积状态；消息本身的线程安全性取决于接收者。

## 逐平台构建验证

`swift build` 只覆盖 macOS，而这个目录里全是条件编译，所以改动平台守卫后必须逐平台构建。Package.swift 声明的六个平台都验证过：

```bash
for DEST in "generic/platform=watchOS" "platform=macOS,variant=Mac Catalyst" \
            "generic/platform=iOS" "generic/platform=tvOS" \
            "generic/platform=visionOS" "platform=macOS"; do
  xcodebuild -scheme ObjCRuntimeToolbox -destination "$DEST" \
    -derivedDataPath /tmp/claude/DerivedData/FrameworkToolbox build 2>&1 | xcsift
done
```

## 影响面

纯新增，不改动 `ObjCRuntimeToolbox` 既有的任何 API。`ObjCRuntimeToolbox` 新增了对 `OSToolbox` 的依赖（见 [OSToolbox 抽取设计](2026-08-06-ostoolbox-extraction-design.md)）。
