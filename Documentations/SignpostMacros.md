# `@Signpostable` 与 `#signpost` —— 用法契约与实现决策

配套提案：[0002](Evolutions/0002-signpost-macros.md)。

## 背景

`@Loggable` / `#log` 已经把「一对 subsystem/category + 版本回退 + 隐私标注」的样板收敛掉了，
但 signpost（Instruments 里量耗时用的那套）一件都没收敛。Apple 的模型里 signpost 与 log
共用同一对 subsystem/category，所以这两套宏是并列关系，不是上下游。

比 `#log` 多出来的难点只有一个，但它是决定性的：**新旧两条 API 对「区间凭据」的要求不一样**。

| 路径 | begin 返回 | end 需要 |
|---|---|---|
| `OSSignposter`（macOS 12 / iOS 15 / watchOS 8 / tvOS 15 起） | `OSSignpostIntervalState` 对象 | 那个对象 |
| `os_signpost`（macOS 10.14 起，即本库全部平台） | 无 | 调用方自己留住的 `OSSignpostID` |

本库最低支持 macOS 10.15，而 `OSSignpostIntervalState` 被 `@available` 门控在 macOS 12
—— 所以想把 begin 和 end 拆到两个方法里，**那个用来保存的属性根本没有类型可写**。
这与 `@AvailableNonMutating` 解决的是同一类问题。

## 三种形态怎么选

```swift
@Loggable
@Signpostable
struct SyncService {
    // ① 作用域式 —— 首选。end 在 defer 里，任何退出路径都会关闭
    func load() throws -> Data {
        try #signpostInterval("load") { try readFromDisk() }
    }

    // ② 分离式 —— 只在 begin/end 跨方法、跨回调时用
    private var uploadInterval: SignpostInterval?
    func uploadDidStart()  { uploadInterval = #signpost(.begin, "upload", "bytes=\(byteCount)") }
    func uploadDidFinish() { if let uploadInterval { #signpost(.end, uploadInterval) } }

    // ③ 单点事件 —— 无时长的时间点
    func didTap() { #signpost(.event, category: .pointsOfInterest, "tapped") }
}
```

**默认用作用域式。** 分离式的代价是 end 可能漏掉或重复，而作用域式在语法上不可能漏。

## 必须遵守的契约（从签名看不出来的部分）

1. **一个区间只能 end 一次。** `OSSignposter` 用 interval state 的身份检测 double-end：
   debug 构建直接 trap，release 构建给闭合 signpost 挂一条错误消息。分离式里 end 完就把
   那个 `SignpostInterval?` 置 `nil`。

2. **只有 `.pointsOfInterest` 会出现在 Instruments 的默认轨道。** 其它 category 的 signpost
   要在 Instruments 里手动加 os_signpost instrument 才看得到。

3. **`.dynamicTracing` / `.dynamicStackTracing` 默认不发射**，只在 Instruments 这类工具录制时
   才启用（`.dynamicStackTracing` 还会额外抓 backtrace，更贵）。**这不是坏了**
   —— 实测中 `.dynamicTracing` 的 event 在 `log show` 里完全看不到，而 `.pointsOfInterest`
   与默认 category 的都在。第一次遇到很容易误判成宏没生效。

4. **name 必须是字面量。** 系统要 `StaticString`，且它是 Instruments 里区间的名字，不是消息。
   变动的内容放 message 里。

5. **实例方法里插值属性要写 `self.`。** 与 `#log` 同一原因：展开是立即执行闭包，
   `\(byteCount)` 编译不过，`\(self.byteCount)` 可以。

6. **`@Loggable` 与 `@Signpostable` 可以同时标注**，两者生成的成员名不重叠。这是硬约束
   （同名会 `invalid redeclaration`），由 `Sources/OSToolboxNoFoundationClient/` 里的
   `DualAnnotatedService` 在编译期钉住。

7. **`#signpost(.end, …)` 不要求所在类型是 `@Signpostable`**：凭据自带 log handle、name 与 ID。
   `.begin` / `.event` / `#signpostInterval` 则需要（它们要取 `Self._signpostLog`）。

## 实现决策 —— 看起来更简单的那几条路为什么走不通

### `SignpostInterval` 为什么要携带 `OSLog`

最初的设计只存 name + ID + state，end 时用 subsystem/category 重新取 log handle。
**这条路是错的**：系统靠 (log handle, name, signpost ID) 三元组把 begin 与 end 配对，而
`OSLog(subsystem:category:)` 每次调用都返回新对象，没有任何文档保证两个同参数对象共享同一个
底层 handle。重新取有概率得到另一个 handle，结果是 Instruments 里出现永不结束的区间。
凭据直接持有 begin 用的那个引用，这个问题就不存在了 —— 顺带让 `.end` 变成自包含的。

同一条不变式在缓存那边也踩得到：`_sharedSignposter` **必须**写成
`OSSignposter(logHandle: _sharedSignpostLog(...))`，不能用现成的
`OSSignposter(subsystem:category:)`，因为后者会自己造一个 handle，于是
`signposter(for: .x)` 与 `_signpostLog(for: .x)` 落在两个不同 handle 上。

### 作用域式为什么不用 `withIntervalSignpost`

SDK 只有 `rethrows` 的同步版本，没有 `async` 重载 —— async body 传不进去。
而且旧路径没有对应函数，仍要手写 begin/defer/end，那样被测 body 会在两个 `#available`
分支里各出现一次（编译两份、体积翻倍，body 里若有别的宏还会重复触发）。
统一走「begin + defer(end) + body 内联一次」，版本分支收在 begin 与 end 内部。

### 宏为什么不替用户插入 `try` / `await`

body 是原样搬进展开体的，它自己的 `try` / `await` 就在里面，编译器据此推断出立即执行闭包的
效果标注，调用点照 body 的需要写 `try await` 即可。反过来若宏擅自加 `try`，非 throws 的 body
会得到一句 "no calls to throwing functions occur within 'try' expression" 警告。

代价是 `#signpostInterval` 需要 sync 与 async 两个 body 重载：宏声明按函数做类型检查，
async 闭包不会绑到 sync 那个上。展开体两者相同。

### `.begin` / `.end` / `.event` 为什么是三个类型而不是一个枚举的三个 case

重载解析要按**返回类型**区分：`.begin` 返回 `SignpostInterval`，另两个返回 `Void`。
一个枚举做不到这件事。所以有 `SignpostableMacro.BeginType` / `EndType` / `EventType`
三个单值类型。提案里担心的重载歧义没有出现，四种形态一次通过。

### legacy 路径为什么是 `%{public}s` + `withCString`

`String: CVarArg` 这条 conformance 由 Foundation 提供，标准库没有。`#log` 原先展开成
`os_log(…, "%{public}@", "\(值)")`，于是带插值的消息在没 import Foundation 的模块里编译不过，
错误还落在用户从未写过的生成代码上。改用 `"\(值)".withCString { … }` 传
`UnsafePointer<CChar>` —— 两者都是标准库的。多段插值嵌套 `withCString`，per-segment privacy
因此保住（合并成一段会把 `.private` 的内容明文写进日志，那是隐私回归而不是简化）。

**顺带修掉了 `#log` 的同一缺陷**，见下一节。

### 为什么守卫需要一整个 target

`Sources/OSToolboxNoFoundationClient/` 是一个专门用来「不 import Foundation」的 target。
之前的守卫文件住在 `OSToolboxClient` 里，而同 target 的 `main.swift` 第一行就是
`import Foundation` —— **Swift 的 conformance 查找是模块级的，不是文件级的**，一处 import
就把 `String: CVarArg` 交给了 target 里每个文件。所以那个守卫多年来看着有效，实际什么都没挡住：
它的两个用例恰好都用无插值消息，连缺陷的触发条件都没碰到。

这条比 signpost 本身更值得记：**防「意外依赖某个模块」的守卫，只有独占一个 target 才算守卫。**

## 影响面

- 纯新增；唯一改变的既有展开是 `#log` 的 legacy 分支（无插值消息展开不变；带插值的从
  `%{public}@` + `String` 变成 `%{public}s` + C 字符串，日志文本相同）。
- `OSToolbox` 新增的六个名字（`SignpostInterval`、`signposter`、`signpostSubsystem`、
  `signpostCategory`、`_signpostLog`、`makeSignpostID`）经 re-export 链传到
  `SwiftStdlibToolbox` 与 `FoundationToolbox`。下游若自己在 `LogCategory` 上扩展过
  `pointsOfInterest` 等同名成员会撞名，表现为编译期 `invalid redeclaration`，可发现好改。

## 相关文件

| 文件 | 内容 |
|---|---|
| `Sources/OSToolbox/SignpostInterval.swift` | 区间凭据 |
| `Sources/OSToolbox/SignpostableMacroSupport.swift` | 命名空间、三个标记类型、共享缓存 |
| `Sources/OSToolbox/LogCategory.swift` | 三个系统 category 常量 |
| `Sources/OSToolbox/Macros/SignpostableMacro.swift` | `@Signpostable` 声明 |
| `Sources/OSToolbox/Macros/SignpostMacro.swift` | `#signpost` / `#signpostInterval` 声明 |
| `Sources/OSToolboxMacros/SignpostableMacro.swift` | `@Signpostable` 实现 |
| `Sources/OSToolboxMacros/SignpostMacro.swift` | `#signpost` / `#signpostInterval` 实现 |
| `Sources/OSToolboxMacros/OSLogFormatSupport.swift` | legacy 格式化，`#log` 与 `#signpost` 共用 |
| `Sources/OSToolboxMacros/DeclarationAttributeSupport.swift` | `@Loggable` / `@Signpostable` 共用的属性解析 |
| `Sources/OSToolboxNoFoundationClient/` | 无 Foundation 守卫 + 三种形态的编译与运行验证 |
| `Tests/OSToolboxMacroTests/SignpostMacroTests.swift` | 展开快照 |
| `Tests/OSToolboxTests/SignpostSupportTests.swift` | 凭据往返、category 字符串、缓存 |
