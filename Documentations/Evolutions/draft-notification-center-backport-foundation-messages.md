# Draft - 把 Foundation 预置的系统通知消息搬进 `NotificationCenter.Backport`

- **状态**: Implemented
- **创建日期**: 2026-10-04
- **最后更新**: 2026-10-04
- **所属愿景**: 无
- **配套文档**: [`NotificationCenter.Backport` —— 类型化通知消息的用法契约与陷阱](../NotificationCenterBackport.md)（新增「Foundation 预置的系统消息」一节）

## 摘要

Foundation 的 26 SDK 不只提供类型化通知的通用机制，还给 16 个自家类型预置了 32 个消息类型和对应的标识符。
例如 `UndoManager.DidUndoChangeMessage` 配 `.didUndoChange`，`ProcessInfo.ThermalStateDidChangeMessage`
配 `.thermalStateDidChange`。它们同样要求 26 系统。
上一份提案（[把 swift-foundation 的类型化通知 API 搬到老系统](draft-notification-center-backport.md)）只搬了通用机制，
预置消息留给使用方自己定义。本提案把 Foundation 的这一批也搬过来。
AppKit / UIKit 的预置消息不归本库，由 UIFoundation 按同一套约定搬。

## 方案

### 清单

以 Xcode 27.0 的 SDK 为准。与 Xcode 26.6、27.2 beta 2 的 SDK 逐个比对过，五个平台上完全一致。
表中省略了类型名统一的 `Message` 后缀。标识符名是类型名去掉 `Message`、首字母小写，例如 `.calendarDayChanged`、`.checkpoint`。

| 主题类型 | 消息 | 种类 |
|---|---|---|
| `UndoManager` | `WillUndoChange`、`DidUndoChange`\*、`WillRedoChange`、`DidRedoChange`\*、`Checkpoint`、`DidOpenUndoGroup`、`DidCloseUndoGroup`\*、`WillCloseUndoGroup` | MainActor |
| `HTTPCookieStorage` | `CookiesChanged` | Async |
| `NSMetadataQuery` | `DidFinishGathering`、`DidStartGathering` | Async |
| `Calendar` | `CalendarDayChanged` | Async |
| `Date` | `SystemClockDidChange` | MainActor |
| `TimeZone` | `SystemTimeZoneDidChange`\* | MainActor |
| `ProcessInfo` | `PowerStateDidChange`、`ThermalStateDidChange` | Async |
| `FileHandle` | `ConnectionAccepted`\*、`DataAvailable`、`ReadToEndOfFileCompletion`\*、`ReadCompletion`\* | Async |
| `Bundle` | `DidLoad` | Async |
| `UserDefaults` | `DidChange`（Async）、`SizeLimitExceeded`（MainActor） | — |
| `Process` | `DidTerminate`（只在 macOS） | Async |
| `Port` | `DidBecomeInvalid` | Async |
| `Locale` | `CurrentLocaleDidChange` | MainActor |
| `FileManager` | `UbiquityIdentityDidChange` | MainActor |
| `NSBundleResourceRequest` | `LowDiskSpace`（macOS 上没有） | Async |
| `NSExtensionContext` | `DidBecomeActive`、`DidEnterBackground`、`WillEnterForeground`、`WillResignActive` | MainActor |

带 \* 的 7 个有属性，其余 25 个是空结构体。

### 命名

类型放进主题类型下的 `Backport` 子命名空间，例如 `UndoManager.Backport.DidUndoChangeMessage`。
标识符挂在 `NotificationCenter.Backport.MessageIdentifier` 上，名字与苹果相同（`.didUndoChange`）。
迁回原生 API 的规则不变：删掉 `Backport.`。

### 标识符标 `@_disfavoredOverload`

简写 `.didUndoChange` 会同时匹配苹果和本库的 `addObserver` 重载。编译探针的实测结果：

- **部署目标低于 26，且不在 `#available` 块里**：无歧义，解析到本库。
  原因是苹果那个重载此处可能不可用，编译器会给它扣分。
- **部署目标为 26，或在 `if #available(macOS 26, *)` 块里**：两边都可用，报 `ambiguous use of 'didUndoChange'`。
  也就是说，使用方只要 import 了本库，**连苹果原生的简写都编译不过**。
- **给本库的标识符加 `@_disfavoredOverload` 之后**：两种情况都无歧义。
  原生 API 可用的地方解析到苹果的，不可用的地方解析到本库的。
  想在 26 的上下文里强制用本库，写出消息类型名即可（`for: UndoManager.Backport.DidUndoChangeMessage.self`）。

老系统上本库为什么仍然胜出：Swift 源码 `include/swift/Sema/Score.h` 里，「可能不可用」的扣分
（`SK_Unavailable`）比「disfavored」的扣分（`SK_DisfavoredOverload`）优先级高。
「可能不可用」是按调用点所在的可用性上下文判断的（`ConstraintSystem::isDeclUnavailable`），所以 `#available` 块会改变结果。

### 行为

来源是 macOS 27.0 的 Foundation 5027.0.69：成员地址取自 RuntimeViewer 导出，在 IDA 里反编译，并逐个核对了汇编。

- **`name`**：全部直接返回对应的系统通知常量。有几处与直觉不同，都照抄：
  - `TimeZone` 用的是 `kCFTimeZoneSystemTimeZoneDidChangeNotification`。
  - `Locale` 用的是 `kCFLocaleCurrentLocaleDidChangeNotification`。
  - `UserDefaults.SizeLimitExceededMessage` 的值是 `com.apple.CFPreferences.byteCountLimitReached`。
- **25 个空结构体的 `makeMessage(_:)`**：无条件返回 `Self()`，不看 name、object、userInfo。
  其中 24 个在二进制里是跳到同一个函数的跳板。它们都不实现 `makeNotification(_:)`，走协议默认实现。
  **注意：协议默认的 `makeMessage(_:)` 返回 `nil`**，所以本库必须逐个显式实现。
  漏掉一个，系统发出的那条通知就永远到不了观察者。
- **`UndoManager` 的三个带属性消息**（`DidUndoChange` / `DidRedoChange` / `DidCloseUndoGroup`）：
  - `makeMessage(_:)` 取 `userInfo["NSUndoManagerGroupIsDiscardableKey"] as? Bool`，取不到就是 `false`，从不返回 `nil`。
  - `makeNotification(_:)` 把 `NSNumber(value: groupIsDiscardable)` 写进同一个键，false 时也写。object 为 `nil`。
- **`TimeZone.SystemTimeZoneDidChangeMessage`**：`previousTimeZone` 取 `notification.object as? TimeZone`，从不返回 `nil`。
- **`FileHandle` 的三个带属性消息**：
  - `makeMessage(_:)` 先查 `"NSFileHandleError"`。若是 `NSNumber`，且值是合法的 `POSIXErrorCode`，返回 `.failure(POSIXError(code))`。
  - 否则查数据键：`ConnectionAccepted` 查 `NSFileHandleNotificationFileHandleItem`，取 `FileHandle`；两个读完成消息查 `NSFileHandleNotificationDataItem`，取 `Data`。取到就返回 `.success`。
  - 两个键都取不到，返回 `nil`。
  - `makeNotification(_:)` 在成功时写数据键，`Data` 以 Swift 的 `Data` 存，不是 `NSData`。失败时写 `NSNumber(value: error.errorCode)`。object 为 `nil`。

### 可用性

跟底层通知常量走，不照抄苹果标的 26：

- `ProcessInfo.Backport.PowerStateDidChangeMessage` 在 macOS 上要求 12，因为常量本身就是 macOS 12 才有。
- `Process.Backport.DidTerminateMessage` 只在 macOS 上有。Mac Catalyst 上也没有，与苹果相同。
- `NSBundleResourceRequest.Backport.LowDiskSpaceMessage` 在 macOS 上不可用，其余平台从 27 起标废弃，
  提示语照抄苹果的 "Use Background Assets instead."。
- 有几个消息苹果在某个平台上提供了，SDK 却不公开它底层的常量：macOS 上的 `NSExtensionContext` 四个和
  `UserDefaults.SizeLimitExceededMessage`。这些在该平台上直接写苹果 getter 返回的字符串。

其余消息在本库支持的最低系统上都能用。

### 测试

- **与 Foundation 对照**：在 macOS 26+ 上运行（本机是 27），老系统上跳过。每个消息比三样：
  - `name` 与苹果的相同；
  - 同一组构造出来的 `Notification` 分别交给两边的 `makeMessage(_:)`，结果一致；
  - 两边 `makeNotification(_:)` 产出的 name、object、`userInfo` 一致，包括键、值和值的类型。
- **端到端**：用真实的 `UndoManager` 做撤销和重做，确认本库的观察者能收到系统发出的通知，`groupIsDiscardable` 也正确。
  这条在任何系统上都能跑。
- **编译期守卫**：在 `FoundationToolboxClient` 的 `if #available(macOS 26, *)` 块里用一次简写。
  以后谁去掉 `@_disfavoredOverload`，这里会因歧义编译失败。
  同一个 target 用普通 import 把每个公开类型和标识符都引用一遍，防止漏写 `public`。
- **确认测试能变红**：分别做三处破坏——改错一个 userInfo 键、删掉一个 `makeMessage(_:)` 显式实现、去掉 `@_disfavoredOverload`——每次都要看到对应的测试或守卫失败。
- iOS / tvOS / watchOS / visionOS / Mac Catalyst 各编一遍。

### 文档

- 指南 `NotificationCenterBackport.md`：
  - 加一节「Foundation 预置的系统消息」，写清单，以及简写在 26 的上下文里会自动解析到原生 API；
  - 删掉差异表里的「预置的系统消息：没有」；
  - 改掉开头「只想观察系统通知就自己定义」的说法。
- `CLAUDE.md` 的 `NotificationCenter.Backport` 一条补两点：为什么要 `@_disfavoredOverload`，以及为什么必须显式实现 `makeMessage(_:)`。
- 两份文档索引同步更新。

### 未问就定下的假设

- 代码放在 `FoundationToolbox`。源文件按主题类型拆分，放在 `NotificationCenterBackport/FoundationMessages/` 下。
- 只搬 SDK 里有的这 32 个，不额外补。例如苹果没给 `NSMetadataQuery` 的 `DidUpdate`，这里也不给。
- 实现是照着 SDK 接口和反汇编结论重写的，没有复制源码，所以不需要额外的许可证头。

### 与 UIFoundation 的关系

UIFoundation 依赖本库的版本要求是 `from: "0.12.0"`，当前锁定在 0.13.0。`NotificationCenter.Backport` 还没进任何 tag。
UIFoundation 要用它，得先发一个包含它的版本。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-04 | Created as Draft | 用户要求「把现在 SDK 有的通知适配一下」：本库只适配 Foundation，AppKit / UIKit 交给 UIFoundation |
| 2026-10-04 | 推翻上一份提案「预置消息由使用方自定义」的假设 | 用户要求 |
| 2026-10-04 | 类型放进 `<主题类型>.Backport`，标识符与苹果同名 | 沿用用户为上一份提案选定的 `Backport` 子命名空间，迁回规则保持「删掉 `Backport.`」 |
| 2026-10-04 | 标识符标 `@_disfavoredOverload` | 编译探针表明：不标的话，部署目标 26 或 `#available` 块里连苹果原生的简写都会报歧义 |
| 2026-10-04 | 可用性跟底层通知常量，不照抄苹果标的 26 | 26 是苹果这套 API 本身的门槛，不是这些通知的门槛；常量更晚才有的（macOS 上的 `PowerStateDidChange`）照常量标注 |
| 2026-10-04 | 状态 Draft → Accepted | 用户批准（「开工」），实现开始 |
| 2026-10-04 | 编译期守卫覆盖全部 31 个 macOS 上可用的标识符，且每次调用的结果都直接丢弃 | 只守一个标识符，抓不住以后新加的消息漏标属性；若把结果收进有类型的数组，参数类型会替编译器选好重载、掩盖歧义，守卫就失效了 |
| 2026-10-04 | 端到端测试写出消息类型，不用简写 | 简写在 Foundation 原生可用处解析到原生 API；若测试目标的部署目标将来升到 26，用简写的测试会悄悄改测 Foundation 而不是本库 |
| 2026-10-04 | 客户端里 macOS 12 的那个消息放进 `@available(macOS 12, *)` 函数，不写 `#available` | Xcode 27 实际以 macOS 12 编译库和客户端（测试是 14），`#available(macOS 12, *)` 会报「不必要的检查」警告 |
| 2026-10-04 | iOS 一系平台上 `NSExtensionHost…` 写成 `.NSExtensionHostDidBecomeActive` 这类成员 | 实现时发现：全局常量已改名为 `NSNotification.Name` 的成员，旧写法报错；`swift build` 只编 macOS，靠逐平台构建才暴露 |
| 2026-10-04 | 测试都亲眼看着变红过 | 改错 FileHandle 的错误键、删掉 `CheckpointMessage.makeMessage`、换掉 `Bundle` 消息的名字 → 对应三条对照测试与端到端测试红；`groupIsDiscardable` 缺省改成 `true`、TimeZone 丢掉旧时区 → 两条对照测试红；去掉 `.didUndoChange` 的 `@_disfavoredOverload` → 客户端在守卫处报 `ambiguous use of 'didUndoChange'` |
| 2026-10-04 | 配套文档：更新已有的使用指南，不另写；术语表：不新增 | 简写在 26 的上下文里改选原生 API、FileHandle 三个消息会返回 `nil`、值类型主题只能按类型观察，都是签名上看不出的约定，归入已有指南；项目尚无 `Glossary.md`，这次也没有引入新术语 |
| 2026-10-04 | 状态 Accepted → Implemented | 5 个新测试与整个测试套件通过（原始退出码 0）；macOS、iOS、tvOS、watchOS、visionOS、Mac Catalyst 构建 0 错误 0 警告 |
