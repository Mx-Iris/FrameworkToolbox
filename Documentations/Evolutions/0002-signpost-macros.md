# 0002 - 仿 @Loggable / #log 实现 os_signpost：@Signpostable 与 #signpost

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-17
- **最后更新**: 2026-08-17
- **所属愿景**: 无
- **关联提案**: 无
- **实现分支 / PR**: `main`（直接落地）
- **配套文档**: [`SignpostMacros.md`](../SignpostMacros.md) —— 用法契约与实现决策

## 摘要

在 `OSToolbox` 里新增一对 signpost 宏，与既有的 `@Loggable` / `#log` 并列：

- **`@Signpostable`** —— 附加宏，给类型 / 协议生成 signpost 基础设施
  （`_signpostLog`、`signposter`、`makeSignpostID()`，以及按 `LogCategory` 取用的变体）。
- **`#signpost`** —— 独立表达式宏，展开为版本检查过的 signpost 发射代码。三种调用形态：
  单点事件 `.event`、分离式 `.begin` / `.end`、作用域式 `#signpostInterval(_:) { ... }`。

`@Loggable` 一个字节都不改 —— 两个宏可以同时标注在一个类型上，生成的成员名不重叠。

同时修掉一个在调研中发现的既有缺陷：`#log` 的 legacy 分支展开成
`os_log(..., "%{public}@", "\(expr)")`，而 `String: CVarArg` 这条 conformance 由 Foundation 提供，
所以**只要消息带插值、且调用方文件没有 `import Foundation`，`#log` 就编译不过**。
新的 signpost legacy 路径与修好的 `#log` legacy 路径统一改用 `"%{public}s"` + `String.withCString`
传 `UnsafePointer<CChar>` —— 两者都是标准库自带的，不碰 Foundation。

## 动机

### 1. 现在这套能力完全不存在，手写一次要写三处样板

全仓库对 `signpost` 的搜索零命中（`grep -rniI "signpost" . --exclude-dir=.git --exclude-dir=.build`
无输出）。今天要在本库任何一层里量一段代码的耗时，只能在调用点手写：

```swift
// 手写版本，每个调用点都要重复这三件事
let signpostLog = OSLog(subsystem: "SyncService", category: "SyncService")   // ① subsystem/category 又写一遍
if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {            // ② 版本分支
    let signposter = OSSignposter(logHandle: signpostLog)
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("fetch", id: signpostID)           // ③ 新旧 API 的 interval 状态类型不同
    defer { signposter.endInterval("fetch", state) }
    …
} else {
    let signpostID = OSSignpostID(log: signpostLog)
    os_signpost(.begin, log: signpostLog, name: "fetch", signpostID: signpostID)
    defer { os_signpost(.end, log: signpostLog, name: "fetch", signpostID: signpostID) }
    …   // ← 被测代码在这里出现第二遍
}
```

这三件事分别对应 `@Loggable` / `#log` 已经吃掉的三件事，只是 signpost 一件都没吃掉。
其中 ③ 是最难手写的一环，见下条。

### 2. 版本跨度是真实的，而且两条路径的 interval 状态类型不兼容

本库声明的最低平台是 iOS 13 / macOS 10.15 / watchOS 6 / tvOS 13（`Package.swift`），
而 `OSSignposter` 要 macOS 12 / iOS 15 / watchOS 8 / tvOS 15。也就是说**中间整整隔着两个大版本**，
fallback 不是理论问题。

麻烦在于两条路径的"区间凭据"类型不一样：

| 路径 | begin 返回什么 | end 需要什么 |
|---|---|---|
| `OSSignposter`（macOS 12+） | `OSSignpostIntervalState`（class，本身被 `@available` 门控在 macOS 12） | 那个 state 对象 |
| `os_signpost`（macOS 10.14+） | 什么都不返回 | 调用方自己留住的 `OSSignpostID` |

于是手写代码想把 begin 和 end 拆到两个函数里（异步流程、delegate 回调、`Task` 前后）时，
用来保存的那个属性**没有类型可写** —— `OSSignpostIntervalState` 在 macOS 12 以下不可见，
不能作为存储属性类型出现。这和 `@AvailableNonMutating` / `@AvailableMutating`
（`Documentations/Specs/2026-04-14-available-storage-macros-design.md`）解决的是同一类问题，
本提案用同一个思路解决：库自己提供一个无版本门控的凭据类型。

### 3. signpost 用的就是 log 的那对 subsystem / category

Apple 的说法是 signpost "record ... using the same subsystems and categories that you use for
logging"（`OSSignposter` 文档 Overview）。`@Loggable` 已经把这对字符串的样板收敛掉了，
signpost 却要用户再写一遍 —— 这正是两个宏应该并列存在、共用 `LogCategory` 概念的理由。

### 4. 顺带发现的 `#log` 缺陷（有复现）

调研时实测（无 Foundation，`swiftc -typecheck -target arm64-apple-macos10.15`）：

```swift
import os                                    // 没有 import Foundation
func probe(log: OSLog) {
    let value = 42
    os_log(.debug, log: log, "value %{public}@", "\(value)")
}
// error: argument type 'String' does not conform to expected type 'CVarArg'
```

`String: CVarArg` 是 Foundation 加的，标准库没有。而
`Sources/OSToolboxMacros/LogMacro.swift:112` 生成的正是 `"\(valueExpr)"` 这个 `String` 实参。
所以现有 `#log` 只要消息带插值、调用方文件又没 `import Foundation`，就会在**用户从未写过的生成代码上**
报一个 `CVarArg` 错误 —— 正是 `CLAUDE.md` 里「宏不得展开出调用方没导入的模块」那条规矩要防的事故，
只是这次不是 `cannot find 'Bundle' in scope` 而是一条 conformance 缺失。

现有的编译期守卫 `Sources/OSToolboxClient/LoggableWithoutFoundation.swift` 没抓到，
因为它两个用例的消息都不带插值（`#log(.debug, "struct default subsystem, no Foundation import")`），
恰好走的是无实参的 `os_log` 重载。

signpost 的 legacy 路径要发射带 message 的 signpost，会撞上完全同一条 conformance；
照抄 `#log` 现有做法等于把缺陷复制一份，所以本提案一并修掉，并把守卫补成带插值的。

## 前期调研

### SDK 事实（全部读自 `$(xcrun --show-sdk-path)`）

`usr/lib/swift/os.swiftmodule/arm64e-apple-macos.swiftinterface`：

```swift
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer = #dsohandle, log: OSLog,
                        name: StaticString, signpostID: OSSignpostID = .exclusive)
@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer = #dsohandle, log: OSLog,
                        name: StaticString, signpostID: OSSignpostID = .exclusive,
                        _ format: StaticString, _ arguments: any CVarArg...)

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public struct OSSignpostID: Sendable {
    public static let exclusive: OSSignpostID
    public init(log: OSLog)
    public init(log: OSLog, object: AnyObject)
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public typealias SignpostMetadata = OSLogMessage
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct OSSignposter: @unchecked Sendable {
    public init(logHandle: OSLog)
    public init(logger: Logger)
    public var isEnabled: Bool { get }
    public func makeSignpostID() -> OSSignpostID
    public func makeSignpostID(from object: AnyObject) -> OSSignpostID
    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: SignpostMetadata)
    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: SignpostMetadata) -> OSSignpostIntervalState
    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: SignpostMetadata)
    public func withIntervalSignpost<T>(_ name: StaticString, id: OSSignpostID = .exclusive, around task: () throws -> T) rethrows -> T
}
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public class OSSignpostIntervalState: Codable, @unchecked Sendable {
    public static func beginState(id: OSSignpostID) -> OSSignpostIntervalState
}
```

`usr/include/os/signpost.h:316,332,346` —— 三个有特殊语义的 category 字符串常量：

```c
#define OS_LOG_CATEGORY_POINTS_OF_INTEREST     "PointsOfInterest"      // Instruments 默认显示
#define OS_LOG_CATEGORY_DYNAMIC_TRACING        "DynamicTracing"        // 默认关闭，只在录制时启用
#define OS_LOG_CATEGORY_DYNAMIC_STACK_TRACING  "DynamicStackTracing"   // 额外抓 backtrace，更贵
```

Swift 侧 `OSLog.Category` 只暴露了 `pointsOfInterest` 一个；另外两个在 Swift 里没有符号，
只能靠字符串。这是本库能顺手补上的一块。

### `os_signpost` 并没有被弃用 —— 文档页面会误导

Apple 文档把 `os_signpost` 归到 "Legacy Signpost Symbols"，`OSSignpostType` 的文档页更直接标了
Deprecated，读起来像是不该再用。**但 SDK 里没有任何 deprecation 注解**：
`grep -n "deprecated" …/os.swiftmodule/arm64e-apple-macos.swiftinterface` 对 signpost 相关声明零命中，
C 头文件 `os/signpost.h` 也只有 `API_AVAILABLE`。

结论：legacy 分支不会产生弃用警告，`#log` 那套"新 API + 旧 API fallback"的结构可以照搬。
这条要记下来，否则下次有人看文档页会以为 fallback 分支需要 `@available(*, deprecated)` 消音。

### 实测过什么（探针都在 scratchpad，`swiftc -typecheck`，target `arm64-apple-macos10.15`）

1. **`StaticString` 可以从变量 / 属性传给 `OSSignposter`。** 这条最关键 —— 它决定分离式
   `.begin` / `.end` 能不能做。`beginInterval(name, id:)` 与 `endInterval(box.name, state)`
   传变量都通过了，尽管这些方法带 `@_transparent @_semantics("constant_evaluable")`。
   （被证伪的假设：原以为 `constant_evaluable` 会要求 name 必须是字面量。不要求。）
2. **`String: CVarArg` 由 Foundation 提供**（见「动机 4」的复现）。
3. **`"%{public}s"` + `String.withCString` 这条路无 Foundation 可编译**，且多段插值靠嵌套
   `withCString` 能保住 per-segment privacy：

   ```swift
   "\(name)".withCString { argument0 in
       "\(count)".withCString { argument1 in
           os_signpost(.event, log: log, name: "multi", signpostID: .exclusive,
                       "%{public}s -> %{private}s", argument0, argument1)
       }
   }
   ```
4. **无版本门控的 interval 凭据可行，且在 Swift 6 语言模式下 Sendable 干净**。
   `AnyObject?` 承载会报 "non-Sendable type 'AnyObject'"；换成 `(any Sendable)?` 后
   `-swift-version 6` 下零警告（`OSSignpostIntervalState` 自己就是 `@unchecked Sendable`）。
5. **三种形态的展开体全部编译通过，且全程没有 `import Foundation`** —— 见「详细设计」里给出的
   展开示例，那些代码块就是探针原文。作用域式的 sync / throwing / async / Void 四种 body 都验过。
6. **`MacroExpansionExprSyntax` 有 `trailingClosure` 与 `additionalTrailingClosures` 子节点**
   （swift-syntax 603.0.2 `Sources/SwiftSyntax/generated/ChildNameForKeyPath.swift:2213,2217`），
   所以 `#signpostInterval("name") { ... }` 这种尾闭包写法在语法层面成立。

### 本仓库现状代码怎么走的

- `Sources/OSToolbox/Macros/LoggableMacro.swift` —— `@Loggable` 的两个重载声明。
- `Sources/OSToolboxMacros/LoggableMacro.swift` —— 实现。`buildConcreteMembers`
  生成 `category` / `subsystem` / `_osLog` / `logger`，`buildCategoryAccessorMembers`
  生成 `_osLog(for:)` / `logger(for:)`；协议路径另走 `buildProtocolRequirements` +
  `buildProtocolDefaultImplementations`。
- `Sources/OSToolbox/LoggableMacroSupport.swift` —— 四个缓存与 `_sharedLogger` / `_sharedOSLog`。
  按 `ObjectIdentifier`（协议路径，每个 conformer 一份）和 subsystem/category 对（`logger(for:)`）两套键。
- `Sources/OSToolboxMacros/LogMacro.swift` —— `#log` 实现，`buildLegacyOSLogFormat` 是要改的那一处。
- `Sources/OSToolbox/LogCategory.swift` —— `LogCategory` 结构体，`Notification.Name` 式的静态成员模式。
- `Sources/OSToolboxMacros/MainPlugin.swift` —— 插件注册表，要加新宏。

## 提议方案

### `@Signpostable`

附加宏，形态与 `@Loggable` 对称（同样支持 concrete 类型与 protocol、同样的 `AccessLevel`
第一位置参数、同样的 `subsystem:` / `category:` 覆盖）：

```swift
@Signpostable
struct SyncService { }

@Signpostable(.internal, subsystem: "com.example.app", category: "Networking")
final class NetworkService { }
```

生成的成员**刻意避开 `@Loggable` 已占用的名字**，所以两个宏可以同时标注：

| `@Loggable` 生成 | `@Signpostable` 生成 |
|---|---|
| `subsystem` / `category` | `signpostSubsystem` / `signpostCategory` |
| `_osLog` / `logger` | `_signpostLog` / `signposter` |
| `_osLog(for:)` / `logger(for:)` | `_signpostLog(for:)` / `signposter(for:)` |
| — | `makeSignpostID()` / `makeSignpostID(from:)` |

这个"不重名"是硬约束，不是巧合：Swift 里两个成员宏生成同名成员会直接 `invalid redeclaration`，
而 `@Loggable` + `@Signpostable` 同时标注是主要用法（同一个类型既要打日志又要量耗时）。
落地时用 client target 的一个双标注类型把它钉住。

### `#signpost` 的三种形态

```swift
@Signpostable
struct SyncService {
    // ① 单点事件 —— 无时长的时间点标记
    func didTap() {
        #signpost(.event, "tapped")
        #signpost(.event, "tapped", "index=\(index, privacy: .public)")
        #signpost(.event, category: .pointsOfInterest, "tapped")
    }

    // ② 作用域式 —— begin/end 自动配对，无法漏掉 end
    func load() throws -> Data {
        try #signpostInterval("load") {
            try readFromDisk()
        }
    }

    // ③ 分离式 —— begin 与 end 跨函数 / 跨回调
    private var uploadInterval: SignpostInterval?
    func uploadDidStart() {
        uploadInterval = #signpost(.begin, "upload", "bytes=\(byteCount)")
    }
    func uploadDidFinish() {
        guard let uploadInterval else { return }
        #signpost(.end, uploadInterval, "ok=\(true, privacy: .public)")
    }
}
```

三种形态共用一套展开器：作用域式就是 `begin` + `defer { end }` + 用户 body，
被测 body 只出现一次（不是每个版本分支里各一份）。

### `SignpostInterval` —— 无版本门控的区间凭据

分离式要能把 begin 的结果存进属性，就需要一个在最低平台上也可见的类型：

```swift
public struct SignpostInterval: Sendable {
    public let name: StaticString
    public let signpostID: OSSignpostID
    private let intervalState: (any Sendable)?   // 实为 OSSignpostIntervalState，macOS 12 以下为 nil
}
```

`name` 存在里面，所以 `.end` 不用重写一遍名字 —— `OSSignposter.endInterval` 要求 name 与 begin
一致（不一致是运行时断言失败），让用户手抄一遍名字纯属送分题送错。

### legacy 路径的消息格式化

统一规则，`#signpost` 与修好的 `#log` 共用同一个实现：

- 每个插值段生成一个 `%{privacy}s` 说明符，值经 `"\(expr)".withCString { … }` 变成
  `UnsafePointer<CChar>`（标准库的 `CVarArg`）。多段则嵌套 `withCString`。
- privacy 映射沿用 `#log` 现有的 `mapPrivacyName`：`.public` → `public`，
  `.private` / `.sensitive` → `private`，未标注 / `.auto` → `public`。
- 字面段里的 `%` 转义成 `%%`，同现有实现。

### `LogCategory` 补三个 signpost 专用常量

```swift
extension LogCategory {
    public static let pointsOfInterest = LogCategory("PointsOfInterest")
    public static let dynamicTracing = LogCategory("DynamicTracing")
    public static let dynamicStackTracing = LogCategory("DynamicStackTracing")
}
```

复用 `LogCategory` 而不新建 `SignpostCategory`，理由见「替代方案考量」。

### 非目标

- **不改 `@Loggable` 的任何展开结果。** 唯一改动的既有展开是 `#log` 的 legacy 分支（见「影响」）。
- **不做 `beginAnimationInterval` / `OSSignpostAnimationBegin`。** 那是给 UI 动画掉帧分析用的，
  与本库的分层无关，等真有需求再单独提案。
- **不封装 `OSSignposter.isEnabled` / `OSLog.signpostsEnabled` 的短路。** 新旧 API 内部都已经先判
  enabled；宏再包一层 `if` 只会让展开体更大，而昂贵实参的构造应由调用方自己决定要不要门控。
  文档里写清这一点。
- **不为 legacy 路径做"全 public 段可合并成一个 `%s`"的优化。** 段数多时嵌套 `withCString` 会深，
  但正确性优先；真成为问题再单独提案。
- **不动 `#log` 的 privacy 默认值。** 现有实现把未标注段当 `public`，而 `os.Logger` 的 `auto`
  对字符串默认是 `private` —— 也就是说同一条 `#log` 在 macOS 11+ 与 10.15 上隐私行为不同。
  这是既有行为，本提案沿用（signpost 也按同一映射），保持两个宏一致；要改是另一个提案的事，
  因为它会改变已发布的日志内容。

## 详细设计

### 文件清单

新建：

| 文件 | 内容 |
|---|---|
| `Sources/OSToolbox/SignpostInterval.swift` | `SignpostInterval` 与它的 `osSignpostIntervalState` 桥 |
| `Sources/OSToolbox/SignpostableMacroSupport.swift` | `SignpostableMacro` 命名空间、`OSSignpostType` 影子枚举、`_sharedSignpostLog` / `_sharedSignposter` 缓存 |
| `Sources/OSToolbox/Macros/SignpostableMacro.swift` | `@Signpostable` 声明（两个重载，同 `@Loggable`） |
| `Sources/OSToolbox/Macros/SignpostMacro.swift` | `#signpost` / `#signpostInterval` 声明 |
| `Sources/OSToolboxMacros/SignpostableMacro.swift` | `@Signpostable` 实现 |
| `Sources/OSToolboxMacros/SignpostMacro.swift` | `#signpost` / `#signpostInterval` 实现 |
| `Sources/OSToolboxMacros/OSLogFormatSupport.swift` | 从 `LogMacro.swift` 抽出的 legacy 格式化，`#log` 与 `#signpost` 共用 |
| `Tests/OSToolboxMacroTests/SignpostMacroTests.swift` | 展开快照 |
| `Sources/OSToolboxClient/SignpostableWithoutFoundation.swift` | 无 Foundation 的编译期守卫（这次带插值） |

改动：

| 文件 | 改什么 |
|---|---|
| `Sources/OSToolbox/LogCategory.swift` | 加三个 signpost 常量 |
| `Sources/OSToolboxMacros/LogMacro.swift` | legacy 分支改走 `withCString`；格式化逻辑挪进 `OSLogFormatSupport.swift` |
| `Sources/OSToolboxMacros/MainPlugin.swift` | 注册 `SignpostableMacro` / `SignpostMacro` / `SignpostIntervalMacro` |
| `Sources/OSToolboxClient/main.swift` | 加 signpost 用例；加 `@Loggable` + `@Signpostable` 双标注类型 |
| `Sources/OSToolboxClient/LoggableWithoutFoundation.swift` | 补一个带插值的 `#log`，堵住漏掉这个缺陷的守卫 |
| `Tests/OSToolboxMacroTests/LoggingMacroTests.swift` | `#log` legacy 展开的快照需要更新 |
| `CLAUDE.md` / `Documentations/README.md` | 同步 |

### `@Signpostable` 的宏声明

```swift
@attached(member, names: named(_signpostLog), named(signpostCategory), named(signpostSubsystem),
          named(signposter), named(makeSignpostID))
@attached(extension, names: named(_signpostLog), named(signpostCategory), named(signpostSubsystem),
          named(signposter), named(makeSignpostID))
public macro Signpostable(
    _ accessLevel: AccessLevel = .private,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
) = #externalMacro(module: "OSToolboxMacros", type: "SignpostableMacro")

/// 暴露 `asProtocolRequirement` 开关的重载，语义同 `@Loggable` 的同名重载。
@attached(member, names: named(_signpostLog), named(signpostCategory), named(signpostSubsystem),
          named(signposter), named(makeSignpostID))
@attached(extension, names: named(_signpostLog), named(signpostCategory), named(signpostSubsystem),
          named(signposter), named(makeSignpostID))
public macro Signpostable(
    _ accessLevel: AccessLevel = .private,
    asProtocolRequirement: Bool,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
) = #externalMacro(module: "OSToolboxMacros", type: "SignpostableMacro")
```

concrete 类型的展开（`@Signpostable` 加在 `struct SyncService` 上）：

```swift
private nonisolated static var signpostCategory: String { "SyncService" }
private nonisolated static var signpostSubsystem: String { "SyncService" }
private nonisolated static let _signpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private nonisolated static let signposter = os.OSSignposter(logHandle: _signpostLog)

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private nonisolated var signposter: os.OSSignposter { Self.signposter }

private nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
    SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
private nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
    SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
}

private nonisolated static func makeSignpostID() -> os.OSSignpostID { os.OSSignpostID(log: _signpostLog) }
private nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
    os.OSSignpostID(log: _signpostLog, object: object)
}
```

`makeSignpostID` 走 `OSSignpostID(log:)`（macOS 10.14+）而不是 `OSSignposter.makeSignpostID()`
（macOS 12+），这样它自己不需要 `@available` 门控 —— 两者产出的都是同一种进程内唯一 ID。

protocol 路径与 `@Loggable` 完全同构：`signpostSubsystem` / `signpostCategory` 默认
`String(describing: self)`，`_signpostLog` / `signposter` 经按 `ObjectIdentifier` 键的缓存拿，
每个 conformer 一份。

### `#signpost` 的宏声明

```swift
// ① 单点事件
@freestanding(expression)
public macro signpost(_ type: SignpostableMacro.OSSignpostType, _ name: StaticString) -> Void
@freestanding(expression)
public macro signpost(_ type: SignpostableMacro.OSSignpostType, _ name: StaticString,
                      _ message: LoggableMacro.OSLogMessage) -> Void
@freestanding(expression)
public macro signpost(_ type: SignpostableMacro.OSSignpostType, category: LogCategory,
                      _ name: StaticString) -> Void
// …以及带 message 的 category 重载

// ② 分离式：begin 返回凭据，end 消费凭据
@freestanding(expression)
public macro signpost(_ type: SignpostableMacro.BeginType, _ name: StaticString,
                      id: OSSignpostID? = nil) -> SignpostInterval
@freestanding(expression)
public macro signpost(_ type: SignpostableMacro.EndType, _ interval: SignpostInterval) -> Void

// ③ 作用域式
@freestanding(expression)
public macro signpostInterval<Result>(_ name: StaticString,
                                      around body: () throws -> Result) -> Result
```

`.begin` / `.end` 用**独立的单例类型**（`BeginType` / `EndType`）而不是共用
`OSSignpostType` 的 case，是为了让重载解析能按返回类型分开：`.begin` 的宏返回
`SignpostInterval`，`.end` 返回 `Void`，`.event` 返回 `Void`。如果三者同属一个枚举，
就没法在类型层面区分"这次调用有返回值"。落地时若发现重载解析仍有歧义，退路是把作用域式之外的
两种拆成 `#signpostBegin` / `#signpostEnd` 独立宏名 —— 这条待实测确认（宏声明的重载解析行为
无法在实现宏之前验证）。

### 展开结果（以下代码块均已 `swiftc -typecheck` 通过，无 Foundation）

`#signpost(.event, "tapped", "id=\(value, privacy: .public)")`：

```swift
{
    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
        Self.signposter.emitEvent("tapped", id: .exclusive, "id=\(value, privacy: .public)")
    } else {
        "\(value)".withCString { argument0 in
            os_signpost(.event, log: Self._signpostLog, name: "tapped",
                        signpostID: .exclusive, "id=%{public}s", argument0)
        }
    }
}()
```

`let interval = #signpost(.begin, "fetch", "n=\(count, privacy: .private)")`：

```swift
{
    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
        let signpostID = Self.signposter.makeSignpostID()
        let intervalState = Self.signposter.beginInterval("fetch", id: signpostID,
                                                          "n=\(count, privacy: .private)")
        return SignpostInterval(name: "fetch", signpostID: signpostID, intervalState: intervalState)
    } else {
        let signpostID = OSSignpostID(log: Self._signpostLog)
        "\(count)".withCString { argument0 in
            os_signpost(.begin, log: Self._signpostLog, name: "fetch",
                        signpostID: signpostID, "n=%{private}s", argument0)
        }
        return SignpostInterval(name: "fetch", signpostID: signpostID, intervalState: nil)
    }
}()
```

`#signpost(.end, interval)`：

```swift
{
    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
        Self.signposter.endInterval(interval.name, interval.osSignpostIntervalState)
    } else {
        os_signpost(.end, log: Self._signpostLog, name: interval.name, signpostID: interval.signpostID)
    }
}()
```

`#signpostInterval("load") { <body> }`：

```swift
{
    let interval = <上面 .begin 的整段展开>
    defer { <上面 .end 的整段展开> }
    <用户 body 的语句原样内联，只出现一次>
}()
```

**为什么把用户 body 放在版本分支外面**：如果按直觉写成"两个 `#available` 分支各跑一遍 body"，
被测代码就会在展开结果里出现两次 —— 编译两份、体积翻倍，body 里若含 `#warning` 或别的宏还会重复触发。
把版本分支收敛在 begin / end 两个立即执行闭包里，body 就只有一份。

**为什么宏自己不插入 `try` / `await`**：用户 body 是原样搬进来的，它自己的 `try` / `await`
就在里面，立即执行闭包的类型由编译器推断成 `() async throws -> Result`，
调用点写 `try await #signpostInterval(...) { ... }` 正好对上。反过来若宏擅自加 `try`，
body 不 throws 时会得到一句 "no calls to throwing functions occur within 'try' expression" 警告。
sync / throwing / async / Void 四种 body 都实测过。

### `SignpostInterval`

```swift
public struct SignpostInterval: Sendable {
    public let name: StaticString
    public let signpostID: os.OSSignpostID

    // OSSignpostIntervalState 被 @available 门控在 macOS 12，不能作为存储属性类型出现在这里。
    // `(any Sendable)?` 承载它而无需 @unchecked —— 那个 class 自己就是 @unchecked Sendable。
    private let intervalState: (any Sendable)?

    public init(name: StaticString, signpostID: os.OSSignpostID, intervalState: (any Sendable)?)

    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public var osSignpostIntervalState: os.OSSignpostIntervalState {
        if let intervalState = intervalState as? os.OSSignpostIntervalState { return intervalState }
        return os.OSSignpostIntervalState.beginState(id: signpostID)
    }
}
```

`beginState(id:)` 那条兜底路径是给"凭据是在 macOS 12 以下造出来、却在 macOS 12+ 上被 end"的
不可能情形留的形式出口（同一进程不会跨版本），也顺带覆盖了跨进程传递凭据的场景 ——
Apple 自己也是用 `beginState(id:)` 重建状态的。

### legacy 格式化的共用实现

`OSLogFormatSupport.swift` 暴露：

```swift
/// 把一个字符串插值表达式拆成 os_log / os_signpost 的 printf 格式串与 CVarArg 实参，
/// 实参一律走 `"\(expr)".withCString`，因此不依赖 Foundation 的 `String: CVarArg`。
func buildLegacyFormat(from expression: ExprSyntax) -> LegacyFormat

struct LegacyFormat {
    let formatLiteral: String          // 例：\"n=%{private}s\"
    let argumentNames: [String]        // 例：[\"argument0\"]
    let segmentExpressions: [String]   // 例：[\"count\"]
    /// 把 `call` 包进 N 层 withCString；无插值段时原样返回。
    func wrappingInCStringScopes(_ call: String) -> String
}
```

`#log` 的 legacy 分支改成：

```swift
// 改前（需要 Foundation 的 String: CVarArg）
os_log(.debug, log: Self._osLog, "value %{public}@", "\(value)")
// 改后
"\(value)".withCString { argument0 in
    os_log(.debug, log: Self._osLog, "value %{public}s", argument0)
}
```

无插值段时不生成任何 `withCString`，展开与今天一致。

## 替代方案考量

- **扩展 `@Loggable` 顺带生成 signposter，不新增宏。**
  已在决策中否掉：改变一个已发布宏的展开结果本身就是源码级破坏
  （`Documentations/Evolutions/README.md` 把这条列为本库两条特有注意事项之一），
  而且会让所有只想打日志的类型无条件多出 signpost 成员。

- **作用域式用 `OSSignposter.withIntervalSignpost(_:id:around:)` 实现。**
  否。两个原因：SDK 只有 `rethrows` 的同步版本，没有 `async` 重载，
  async body 根本传不进去；而且旧路径没有对应函数，仍要手写 begin/defer/end，
  于是 body 又会在两个版本分支里各出现一次。统一走 begin/defer/end 反而更简单也更一致。

- **不做宏，只提供运行时 API（`Signposter.withInterval(name:around:)` 之类）。**
  否，而且是硬性不可行：`SignpostMetadata` 就是 `OSLogMessage`，带
  `@_semantics("constant_evaluable")`，消息必须在调用点以字面量插值的形式出现，
  不能作为参数穿过一层自己写的函数。这正是 `#log` 当初存在的同一个理由。
  （不带 message 的形态确实可以纯运行时实现，但为了两种形态写法一致，统一走宏。）

- **legacy 路径沿用 `"%{public}@"` + `String` 实参。**
  否 —— 那就是「动机 4」那个缺陷本身。

- **legacy 路径把整条消息求值成一个 `String`、只用一个 `%{public}s`。**
  否。段与段的 privacy 会被抹平，标了 `.private` 的内容会明文进日志 —— 这是隐私回归，不是简化。

- **新建 `SignpostCategory` 类型，不复用 `LogCategory`。**
  否。Apple 的模型里 signpost 与 log 共用同一对 subsystem/category，两个类型会逼用户把同一个
  category 声明两遍。代价是 `.pointsOfInterest` 这三个 signpost 专用常量挂在 `LogCategory` 上，
  拿去 `#log(category: .pointsOfInterest)` 能编译但没意义 —— 与 Apple 自己的
  `OSLog(subsystem:category: .pointsOfInterest)` 表现一致，文档注明即可。

- **把 `OSSignpostIntervalState` 直接作为分离式的凭据类型暴露出去。**
  否。它被门控在 macOS 12，用户没法在低版本可见的属性上写出这个类型 ——
  也就等于分离式在 macOS 12 以下不可用。

## 影响

### 源码兼容性（source compatibility）

**主体是纯新增**：`@Signpostable` / `#signpost` / `#signpostInterval` / `SignpostInterval`
以及 `LogCategory` 的三个静态常量，都不触碰任何现有调用点。

**有一处既有展开变化**：`#log` 的 legacy 分支。这在本库要按源码兼容性对待
（宏展开结果的变化就是源码破坏）。逐条评估：

| 变化 | 影响 |
|---|---|
| 无插值消息 | 展开完全不变 |
| 带插值消息，调用方已 `import Foundation` | 从 `"%{public}@"` + `String` 变成 `"%{public}s"` + `UnsafePointer<CChar>`。都能编译；日志文本内容相同（`%@` 走 `NSString` 描述，`%s` 走 UTF-8 C 字符串，对 `"\(expr)"` 产出的字符串是同一串字节） |
| 带插值消息，调用方无 Foundation | **从编译失败变成编译成功** —— 修复，不是破坏 |
| privacy 语义 | 不变，沿用同一套 `mapPrivacyName` 映射 |

需要用户改代码的地方：无。需要更新的是本仓库自己的 `#log` legacy 展开快照测试。

真实风险只有一条：插值段极多时嵌套 `withCString` 会很深（N 段 → N 层闭包），
理论上可能拖慢类型检查。落地时用一个 8 段插值的用例量一下编译时间，超预期就在实现说明里记下上限。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

本仓库内：

- `OSToolbox` 新增符号 → 经 `Sources/SwiftStdlibToolbox/Exported.swift` 的
  `@_exported import OSToolbox` 传到 `SwiftStdlibToolbox`
  → 再经 `FoundationToolbox` 的 `@_exported import SwiftStdlibToolbox` 传到 `FoundationToolbox`。
  也就是 `import FoundationToolbox` 一行就能拿到 `@Signpostable` / `#signpost`，
  与 `@Mutex` / `@Loggable` 今天的表现一致（`@_exported import` 会把宏声明及其插件一并带过传递依赖）。
- `CoreFoundationToolbox` / `ObjCRuntimeToolbox` / `DyldToolbox` 不受影响（不 import `OSToolbox` 的宏）。
- 重名风险：新增的 `signposter` / `signpostSubsystem` / `signpostCategory` / `_signpostLog` /
  `makeSignpostID` / `SignpostInterval` 六个名字，在本仓库内 grep 零命中，不会撞上现有符号。

下游仓库：使用方若自己已经定义了 `SignpostInterval` 或在 `LogCategory` 上扩展过
`pointsOfInterest` / `dynamicTracing` / `dynamicStackTracing`，会与本次新增撞名。
前者概率低；后者是真实风险（这三个名字很自然），但撞名表现为编译期
`invalid redeclaration`，不是静默行为变化，可发现且好改。

### 文档与示例

- `CLAUDE.md` 的 "Key Patterns" 加 signpost 一条，并把 `#log` 的 legacy 格式化改动写进去
  （包括 `String: CVarArg` 来自 Foundation 这个坑 —— 这正是那一节该记的东西）。
- `Documentations/README.md` 索引登记本提案。
- 落地时判断是否值得单独写使用指南：`@Loggable` + `@Signpostable` 双标注、
  `.begin` / `.end` 必须配对、`.pointsOfInterest` 才会出现在 Instruments 默认轨道
  —— 这三条都是"从 API 签名看不出来、违反了就出错或没效果"的契约，倾向要写。

## API 演进与废弃策略

- 没有被替代的旧 API，不需要 deprecation。
- `#log` 的展开变化不构成公开 API 变化（签名不变），不需要 semver major 跃迁；
  按新增功能走 minor。
- 若将来 `#signpost` 的 `.begin` / `.end` 重载解析被证明有歧义，退路是新增
  `#signpostBegin` / `#signpostEnd` 两个宏名并把旧形态标 deprecated ——
  这是落地阶段就要定的事，不留给用户去撞。

## 落地步骤

每一步都应能单独 `swift build` 通过。

1. **`SignpostInterval` + `SignpostableMacroSupport`**（纯运行时，无宏）。
   `OSSignpostType` 影子枚举、`BeginType` / `EndType` 单例类型、两套缓存与
   `_sharedSignpostLog` / `_sharedSignposter`。补 `Tests/OSToolboxTests/` 的往返测试。
2. **`LogCategory` 三个常量** + 断言其 `name` 与 `os/signpost.h` 的三个字符串常量逐字相同的测试
   （拼错一个字母，Instruments 就静默不显示 —— 没有测试就发现不了）。
3. **抽出 `OSLogFormatSupport.swift`**，`#log` 改用它并切到 `withCString`。
   先让现有 `LoggingMacroTests.swift` 的 legacy 快照失败、更新快照，
   再给 `LoggableWithoutFoundation.swift` 补带插值的用例 —— 这一步就是「动机 4」缺陷的复现与修复，
   补上的用例即回归测试，永久保留。
4. **`@Signpostable`**（concrete + protocol 两条路径）+ 展开快照。
5. **`#signpost` 的 `.event`**（含 `category:` 重载）+ 快照。
6. **`#signpost` 的 `.begin` / `.end`** + 快照。这一步要实测重载解析是否需要退到
   `#signpostBegin` / `#signpostEnd`，结论写进决策日志。
7. **`#signpostInterval`** + 快照。四种 body（sync / throwing / async / Void）都要有用例。
8. **client target 的编译期守卫**：`@Loggable` + `@Signpostable` 双标注类型（钉住成员名不冲突）、
   `SignpostableWithoutFoundation.swift`（带插值、无 Foundation）、
   以及 `SwiftStdlibToolboxClient` / `FoundationToolboxClient` 里各一处 re-export 用例
   （re-export 坏了不会有任何测试失败，只能这么钉）。
9. **全平台构建**：`swift build` 只覆盖 macOS，而 `#if canImport(os)` 与 `@available` 的错都是
   编译期错误，按 `Documentations/Specs/2026-08-06-dynamic-invocation-design.md` 里那个循环
   把 iOS / watchOS / tvOS / visionOS / macCatalyst 全过一遍。
10. **运行 client** 并用 `log stream` / Instruments 实地确认 signpost 真的出现
    （宏展开正确 ≠ signpost 能被采集到；`.pointsOfInterest` 是否落在默认轨道只有实测能确认）。
11. **文档同批次落地** + 提案状态推进到 `Implemented`。

## 落地结果

全部 11 步走完。三种调用形态、六种 body 形状、六个声明平台都验证过，实机确认了 signpost
真的被系统采集到（不只是编译通过）。

### 与提案的差异

提案怎么写的、实际怎么落的，逐条对照。**不回头修改上面的方案让它符合实现。**

1. **`SignpostInterval` 多了一个 `log: OSLog` 字段（提案里没有）。**
   提案的 `.end` 展开写成 `Self.signposter.endInterval(...)`，即 end 用的是**调用点所在类型**
   的 log handle。写实现时发现这不成立：系统靠 (log handle, name, signpost ID) 三元组配对
   begin 与 end，而 `.begin` 若带了 `category:`，它用的 handle 就不是类型的默认 handle。
   进一步查证发现「用 subsystem/category 在 end 时重新取 handle」也不行 ——
   `OSLog(subsystem:category:)` 每次返回新对象，没有文档保证两个同参数对象共享底层 handle。
   于是凭据直接携带 begin 用的那个引用。`OSLog` 本身是 `@unchecked Sendable`
   （SDK 第 31 行），所以 `SignpostInterval: Sendable` 依然成立。
   **附带好处**：`.end` 变成自包含，可以在非 `@Signpostable` 的类型里使用。

2. **同一条不变式牵出缓存里的一处真实 bug。** `_sharedSignposter` 最初按提案写成
   `OSSignposter(subsystem:category:)` —— 那个初始化器会自己造一个 log handle，于是
   `signposter(for: .x)` 与 `_signpostLog(for: .x)` 落在两个不同 handle 上，跨这两者的
   begin / end 永远配不上。改成 `OSSignposter(logHandle: _sharedSignpostLog(...))`。

3. **`#signpostInterval` 需要 sync 与 async 两个 body 重载**，提案只写了一个。
   宏声明按函数做类型检查，async 闭包不会绑到 `() throws -> Result` 上
   （实测错误：`cannot pass function of type '() async -> Int' to parameter expecting
   synchronous function type`）。两个重载展开体相同。

4. **提案担心的 `.begin` / `.end` 重载歧义没有出现。** 三个单值标记类型
   （`EventType` / `BeginType` / `EndType`）足够让重载按返回类型分开，
   不需要退到 `#signpostBegin` / `#signpostEnd`。这一步的退路作废，是好消息。

5. **`#log` 缺陷的触发条件比提案写的更窄，而原先的守卫因此完全失效。**
   提案说「消息带插值 + 调用方文件没 import Foundation」就编译不过。实际是
   **整个 target 都没有** 才不过 —— Swift 的 conformance 查找是模块级的，
   一处 `import Foundation` 就把 `String: CVarArg` 交给了 target 里每个文件。
   而旧守卫 `LoggableWithoutFoundation.swift` 就住在有 `import Foundation` 的
   `OSToolboxClient` 里，所以它多年来什么都没挡住。
   修法：新建 `OSToolboxNoFoundationClient` target 独占这个守卫，把文件挪过去。
   **这是本次最值得记的一条**：防「意外依赖某模块」的守卫，只有独占一个 target 才算守卫。

6. **`@Loggable` / `@Signpostable` 的属性解析辅助抽成了
   `OSToolboxMacros/DeclarationAttributeSupport.swift`**（提案未提）。
   这些辅助原是 `LoggableMacro.swift` 里的 `private` 函数，而 Swift 的 `private` 是文件作用域，
   `@Signpostable` 从自己文件里够不到；复制一份会留下两个各自漂移的属性解析器。纯搬迁，
   无行为变化，由 `@Loggable` 的既有快照测试保证。

7. **`#log` 的 legacy 展开缩进需要显式处理。** `\(raw:)` 插入的多行文本只有第一行会获得
   插入点的缩进，其余行保持原样。`LegacyOSLogFormat.wrappingInCStringScopes` 因此多了一个
   `continuationIndent` 参数。纯格式问题，但快照会记录它，所以值得一提。

8. **visionOS 无法用 SwiftPM 交叉编译**（`swift build --triple arm64-apple-xros1.0` 与
   `arm64-apple-visionos1.0` 都以 `Fatal error: Cannot create dynamic libraries for unknown os`
   崩在 SwiftPM 自己的 `Triple+Basics.swift:152`），且本机没装 watchOS / tvOS / visionOS
   的平台组件，`xcodebuild -destination` 用不了。见下面的验证结果，用两条替代路径覆盖了。

### 验证结果

| 项目 | 方式 | 结果 |
|---|---|---|
| 全量构建 | `swift build`（agent 专属 scratch path） | 通过，**零警告** |
| 全量测试 | `swift test`，**以退出码为准** | 446 个测试 / 51 个 suite 通过，退出码 0 |
| `#log` 缺陷复现 | 独占 target 构建 | 修复前退出码 1，报 `argument type 'String' does not conform to expected type 'CVarArg'`，位置 `macro expansion #log`；修复后退出码 0 |
| 展开快照 | 30 个新快照 + 19 个 `#log` 快照更新 | 通过；`#log` 快照的 diff 只落在 legacy 分支，新 API 分支一字未动（已逐行核对） |
| macOS | `swift build` + `xcodebuild` + 实际运行 | 通过 |
| Mac Catalyst | `xcodebuild -destination "platform=macOS,variant=Mac Catalyst"` | 通过 |
| iOS 13 / tvOS 13 / watchOS 6 | `swift build --triple … --sdk …`（`OSToolbox`） | 通过 |
| watchOS 6 的**宏展开** | 同上，但 target 是 `OSToolboxNoFoundationClient` | 通过 —— 展开本身在 watchOS 上编译 |
| visionOS 1.0 | 把最终展开原文（取自快照）单独 `swiftc -typecheck` | 通过；同一 probe 在 watchOS / tvOS / iOS / macOS 下也过 |
| 实机采集 | 运行 client + `/usr/bin/log show --signpost` | 见下 |

实机采集的证据（`/usr/bin/log show --last 5m --signpost`，注意 `log` 是 zsh 内建命令，
必须写全路径）：

- **每个 begin 都有配对的 end，signpost ID 一致**（spid `0x2`…`0xb` 全部成对）——
  这直接验证了「begin/end 同 handle」这条不变式。
- `.pointsOfInterest` 的 signpost 确实落在 `[SignpostGuardService:PointsOfInterest]`。
- **抛错的 body 也关闭了区间**（`scoped, throwing` 的第二次调用 spid `0xb` begin+end 齐全），
  `defer` 生效。
- message 正确附着：`separate: bytes=1024`、`ok=true`、`index=7`。
- `makeSignpostID(from:)` 产出对象派生的 ID（`0xa0b982716fc28000`），而非顺序号。
- **`.dynamicTracing` 的 event 在 `log show` 里完全不出现** —— 那个 category 默认禁用，
  只在 Instruments 录制时启用，与 `os/signpost.h` 的说明一致。这是行为正确的证据，
  但第一次遇到极易误判成宏没生效，所以写进了专题文档与 `CLAUDE.md`。

### 收尾判断

- **配套专题文章：写了一篇** —— [`SignpostMacros.md`](../SignpostMacros.md)。判据成立：
  既有「从 API 签名看不出来、违反了就出错或没效果」的调用方契约（区间只能 end 一次；
  只有 `.pointsOfInterest` 进 Instruments 默认轨道；`.dynamicTracing` 默认不发射），
  也有「下次维护会踩、代码本身看不出来」的实现决策（凭据为什么带 handle；
  为什么不用 `withIntervalSignpost`；守卫为什么需要独占 target）。
  按项目现状放在 `Documentations/` 顶层（`LoggableCategories.md` / `StorageLayer.md` 同级），
  而非全局默认规则的 `Guides/` + `Internal/` 两篇 —— 项目既有约定优先。
- **新术语：无需新增术语表。** 本次引入的名词（signpost、interval、points of interest）
  都是 Apple 的既有术语，不是项目自造词；`SignpostInterval` 的含义在专题文档与代码文档注释里
  已有完整解释。项目目前也还没有 `Glossary.md`，不为这一条新建。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-17 | Created as Draft | 用户要求「仿照 `@Loggable` 和 `#log` 实现 os_signpost」。三处方向由用户当场裁定：① 新增独立 `@Signpostable` 而非扩展 `@Loggable`；② 三种调用形态（作用域式 / 分离式 / 单点事件）全做；③ legacy 路径用 `%s` + `withCString` 避开 Foundation，并顺带修 `#log` 的同一缺陷 |
| 2026-08-17 | Accepted → In Progress | 用户批准，开始实现。按「落地步骤」的 11 步推进 |
| 2026-08-17 | In Progress → Implemented | 11 步走完。与提案有 8 处差异，逐条记在「与提案的差异」；其中两处是提案方案里的真实错误（`.end` 的 log handle、缓存 signposter 的构造方式），一处是提案对 `#log` 缺陷触发条件的判断偏窄（conformance 查找是模块级的，旧守卫因此完全失效）。配套文档写了一篇，术语表判定无需新增 |
