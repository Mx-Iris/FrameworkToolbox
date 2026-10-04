# `NotificationCenter.Backport` —— 类型化通知消息的用法契约与陷阱

Foundation 在 macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 给 `NotificationCenter` 加了一套类型化、
带并发隔离的消息 API。`FoundationToolbox` 把它搬到了本库支持的全部系统上：类型挪进
`NotificationCenter.Backport`，方法名、参数标签、默认值、投递语义都与原生一致。

为什么这么搬、苹果的私有入口换成了什么、哪几处必须偏离，见提案
[把 swift-foundation 的类型化通知 API 搬到老系统](Evolutions/draft-notification-center-backport.md)；
Foundation 预置的系统消息是怎么逆向、怎么核对的，见提案
[把 Foundation 预置的系统通知消息搬进 `NotificationCenter.Backport`](Evolutions/draft-notification-center-backport-foundation-messages.md)。
这篇只讲怎么用，以及有哪些**签名上看不出来、违反了就出事**的约定。

## 先判断该用哪一个

- **部署目标已经是 26**：直接用 Foundation 原生的 `NotificationCenter.MainActorMessage` 一套，不要用这个。
- **部署目标低于 26**：用这个。等部署目标升上去，按文末的步骤换回原生，基本就是删掉 `Backport.`。
- **要观察 Foundation 自己发的系统通知**（撤销管理器、时区变化、文件句柄读完之类）：用现成的，见
  「Foundation 预置的系统消息」一节。
- **要观察 AppKit / UIKit 发的系统通知**（`NSWindow.didBecomeKeyNotification` 之类）：用 UIFoundation 的
  `UIFoundationToolbox`。它按同一套约定，把 AppKit 的 137 个、UIKit 的 71 个预置消息搬到了老系统上
  （例如 `NSWindow.Backport.DidBecomeKeyMessage`），见它的指南
  [`NotificationMessages.md`](https://github.com/Mx-Iris/UIFoundation/blob/main/Documentations/NotificationMessages.md)。
- **两边都没有预置的系统通知**：自己定义一个消息，用 `name` 对上系统通知名、用 `makeMessage(_:)` 从 `userInfo`
  取值即可（见「与 `Notification` 互通」）。

## 两种消息怎么选

| | `MainActorMessage` | `AsyncMessage` |
|---|---|---|
| 投递时机 | `post` 时**同步**投递，在主线程上 | `post` 之后**异步**投递，观察者在独立的任务里运行 |
| 谁能 `post` | 只能在 MainActor 上 | 任意线程、任意隔离 |
| 多个观察者 | 在 `post` 的调用栈里依次调用 | 并发运行，不保证顺序 |
| 消息类型的要求 | 无需 `Sendable` | 必须 `Sendable` |
| 适合 | 观察者必须在某个动作发生之前收到的事件 | 不赶时间的事件，或发送方不在主线程 |

## 定义与使用

```swift
import FoundationToolbox

final class Event {}

// 1. 消息：一个普通类型，声明它关联的 Subject。
struct EventDidStart: NotificationCenter.Backport.MainActorMessage {
    typealias Subject = Event
    var startedAt: Date
}

// 2. 可选的标识符，让调用点能写 `.didStart`。
extension NotificationCenter.Backport.MessageIdentifier
where Self == NotificationCenter.Backport.BaseMessageIdentifier<EventDidStart> {
    static var didStart: Self { .init() }
}

// 3. 观察：只看某一个 subject、看这一类的所有 subject，或者不用标识符直接写消息类型。
let event = Event()
let token = NotificationCenter.default.addObserver(of: event, for: .didStart) { message in
    // 在主 actor 上运行
}
let anyEventToken = NotificationCenter.default.addObserver(of: Event.self, for: .didStart) { message in }
let sameAsAbove = NotificationCenter.default.addObserver(for: EventDidStart.self) { message in }

// 4. 发送（必须在 MainActor 上）。
NotificationCenter.default.post(EventDidStart(startedAt: Date()), subject: event)

// 5. 停止观察：释放 token，或者显式移除。
NotificationCenter.default.removeObserver(token)
```

`AsyncMessage` 的写法完全对称，只是观察闭包是 `@Sendable (Message) async -> Void`。它还能当异步序列消费：

```swift
struct DownloadDidFinish: NotificationCenter.Backport.AsyncMessage {
    typealias Subject = Downloader
    var url: URL
}

for await message in NotificationCenter.default.messages(of: downloader, for: DownloadDidFinish.self) {
    print(message.url)
}
```

## 与 `Notification` 互通

消息通过 `NotificationCenter` 本身投递，所以和老式的 `Notification` 可以互相看见：

| 发送的是 | 观察的是 | 结果 |
|---|---|---|
| 消息 | `Notification` | 观察者收到 `makeNotification(_:)` 的结果；没实现的话，`userInfo` 里只有一个内部键 |
| `Notification` | 消息 | 观察者收到 `makeMessage(_:)` 的结果；没实现或返回 `nil`，观察者**不会被调用** |

```swift
struct WindowDidResize: NotificationCenter.Backport.MainActorMessage {
    typealias Subject = NSWindow
    // 对上系统通知名，才能观察到 AppKit 自己发的那条。
    static var name: Notification.Name { NSWindow.didResizeNotification }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }
}
```

`name` 默认是消息类型的完整限定名（例如 `MyApp.EventDidStart`）。只在新代码之间互发时不用管它，要接上已有的
通知名时才需要覆盖。

## Foundation 预置的系统消息

Foundation 给自家 16 个类型预置了 32 个消息，这里都有，放在各自类型的 `Backport` 里，名字与 Foundation 相同，
例如 `UndoManager.Backport.DidUndoChangeMessage`。标识符也与 Foundation 同名，是类型名去掉 `Message`、首字母小写：

```swift
let token = NotificationCenter.default.addObserver(of: undoManager, for: .didUndoChange) { message in
    print(message.groupIsDiscardable)
}

for await _ in NotificationCenter.default.messages(of: ProcessInfo.processInfo, for: .thermalStateDidChange) {
    print(ProcessInfo.processInfo.thermalState)
}
```

| 主题类型 | 消息（省略 `Message` 后缀） | 种类 |
|---|---|---|
| `UndoManager` | `WillUndoChange`、`DidUndoChange`\*、`WillRedoChange`、`DidRedoChange`\*、`Checkpoint`、`DidOpenUndoGroup`、`DidCloseUndoGroup`\*、`WillCloseUndoGroup` | MainActor |
| `HTTPCookieStorage` | `CookiesChanged` | Async |
| `NSMetadataQuery` | `DidFinishGathering`、`DidStartGathering` | Async |
| `Calendar` | `CalendarDayChanged` | Async |
| `Date` | `SystemClockDidChange` | MainActor |
| `TimeZone` | `SystemTimeZoneDidChange`\*（`previousTimeZone`） | MainActor |
| `ProcessInfo` | `PowerStateDidChange`（macOS 上要 12）、`ThermalStateDidChange` | Async |
| `FileHandle` | `ConnectionAccepted`\*（`fileHandleItem`）、`DataAvailable`、`ReadToEndOfFileCompletion`\*、`ReadCompletion`\*（`dataItem`） | Async |
| `Bundle` | `DidLoad` | Async |
| `UserDefaults` | `DidChange`（Async）、`SizeLimitExceeded`（MainActor） | — |
| `Process` | `DidTerminate`（只在 macOS） | Async |
| `Port` | `DidBecomeInvalid` | Async |
| `Locale` | `CurrentLocaleDidChange` | MainActor |
| `FileManager` | `UbiquityIdentityDidChange` | MainActor |
| `NSBundleResourceRequest` | `LowDiskSpace`（macOS 上没有，27 起废弃） | Async |
| `NSExtensionContext` | `DidBecomeActive`、`DidEnterBackground`、`WillEnterForeground`、`WillResignActive` | MainActor |

带 \* 的带属性；`UndoManager` 那三个的属性都是 `groupIsDiscardable`。每个消息的名字、从通知转成消息、从消息转成通知，
都与 Foundation 自己的实现逐个对照过。用的时候要知道三件事：

1. **在 26 的上下文里，简写选的是 Foundation 原生的那个。** 部署目标为 26，或代码在 `if #available(macOS 26, *)`
   块里时，`.didUndoChange` 解析到 Foundation 的 `UndoManager.DidUndoChangeMessage`，返回的是
   `NotificationCenter.ObservationToken`，不是 `NotificationCenter.Backport.ObservationToken`。
   要在那里用本库的，写出消息类型：`for: UndoManager.Backport.DidUndoChangeMessage.self`。
   这是刻意的：两边的简写同名，若不让一步，只要 import 了本库，Foundation 原生的简写就会报
   `ambiguous use of 'didUndoChange'`。
2. **系统发出的通知一定能转成消息，只有 `FileHandle` 那三个例外。** 不带属性的消息不看通知内容，有通知就有消息；
   带属性的取不到值时用默认值（`groupIsDiscardable` 为 `false`，`previousTimeZone` 为 `nil`）。
   `FileHandle` 的三个先看 `userInfo` 里有没有合法的 POSIX 错误码，有就是 `.failure`；再看有没有数据（或新的
   file handle），有就是 `.success`；两样都没有时转不成消息，观察者不会被调用。
3. **主题是值类型的**（`Calendar`、`Date`、`TimeZone`、`Locale`）**只能按类型观察**：
   `addObserver(of: TimeZone.self, for: .systemTimeZoneDidChange)`，或者不带 subject。传实例的重载要求主题是 class，
   Foundation 的也是这样。

## 契约 —— 签名上看不出来，违反了就出事

1. **`MainActorMessage` 的观察者认定自己在主线程上被调用。** 观察者内部用 `MainActor.assumeIsolated` 进入主 actor。
   如果有人在**后台线程**用 `post(name:object:userInfo:)` 发了一条同名的 `Notification`，进程会在那里**崩溃**，
   不是丢掉这条消息。Foundation 原生实现也是这样。发送方不在主线程，就该定义成 `AsyncMessage`。
2. **token 就是观察的生命周期。** token 一释放，观察就结束。`_ = center.addObserver(...)` 等于注册完立刻注销。
   要一直观察，就把 token 存起来。
3. **`makeMessage(_:)` 返回 `nil` 时，观察者不会被调用，只记一条 fault 日志**（subsystem `FoundationToolbox`，
   category `NotificationCenterBackport`）。原生实现会在 Xcode 里显示成紫色的 runtime issue，这里**不会**。
   消息「没收到」时，先去 Console 或 `log stream` 里查这条日志。
4. **subject 按对象身份匹配，且不被持有**，与 `NotificationCenter` 一贯的行为相同。
5. **异步序列**：
   - 观察从 `makeAsyncIterator()` 开始，不是从 `messages(of:for:)` 开始。在这之前发出的消息收不到。
   - 缓冲满了（默认 10 条）会丢掉**最旧**的一条，并记一条 fault 日志。消费得慢就调大 `bufferSize:`。
   - 迭代器复制之后共享同一份缓冲，一条消息只会被其中一个副本取走。
   - 序列只**弱持有** subject。subject 若在 `makeAsyncIterator()` 之前就释放了，这个迭代器会退化为观察**所有** subject。
6. **token 注销之后，它的相等性和哈希值会变**：注销后的 token 与所有其它注销后的 token 相等。所以别先把 token 放进
   `Set`、注销、再拿它去 `Set` 里查找或删除。Foundation 原生实现也是这样，这里刻意保留。

## 与原生 API 的差异

| | Foundation（26 及以上） | 本库 |
|---|---|---|
| 类型的位置 | `NotificationCenter.MainActorMessage` 等 | `NotificationCenter.Backport.MainActorMessage` 等 |
| `messages(of:for:)` 的返回类型 | `some AsyncSequence<Message, Never> & Sendable` | `NotificationCenter.Backport.AsyncMessageSequence<Message>`；在 macOS 15 / iOS 18 以上能当前者用 |
| 手动调用 `next()` | `var iterator`，`try await iterator.next()` | `var iterator`，`await iterator.next()`（写了 `try` 也能编译，只是会多一条警告） |
| `makeMessage(_:)` 失败时的提示 | Xcode 紫色 runtime issue | fault 日志 |
| 预置的系统消息 | Foundation、AppKit、UIKit 等框架都有 | 本库只有 Foundation 的 32 个，放在 `<主题类型>.Backport` 里；AppKit / UIKit 的在 UIFoundation（见「先判断该用哪一个」） |
| 预置消息的可用性 | 26 | 跟着底层通知常量走：几乎都在本库的最低系统上就能用，`PowerStateDidChange` 在 macOS 上要 12 |

两者在 26 系统上可以并存、互不干扰。但**不要让一个类型同时遵循两边的协议**：调用点会同时匹配两套重载，
编译器报歧义。预置消息的简写两边同名，本库的那份让给了 Foundation，见上文「Foundation 预置的系统消息」。

## 迁回原生 API

1. 把部署目标升到 26 一档。
2. 全局删掉 `Backport.`：`NotificationCenter.Backport.MainActorMessage` 变成 `NotificationCenter.MainActorMessage`，
   `UndoManager.Backport.DidUndoChangeMessage` 变成 `UndoManager.DidUndoChangeMessage`。预置消息的简写调用点
   （`.didUndoChange`）不用改，部署目标一到 26，它们就会自己解析到 Foundation 的版本。
3. 手动调用迭代器 `next()` 的地方补上 `try`。
4. 如果在属性或函数签名里把序列写成了 `NotificationCenter.Backport.AsyncMessageSequence<Message>`，
   改成 `some AsyncSequence<Message, Never>`。
