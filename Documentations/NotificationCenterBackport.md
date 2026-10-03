# `NotificationCenter.Backport` —— 类型化通知消息的用法契约与陷阱

Foundation 在 macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 给 `NotificationCenter` 加了一套类型化、
带并发隔离的消息 API。`FoundationToolbox` 把它搬到了本库支持的全部系统上：类型挪进
`NotificationCenter.Backport`，方法名、参数标签、默认值、投递语义都与原生一致。

为什么这么搬、苹果的私有入口换成了什么、哪几处必须偏离，见提案
[把 swift-foundation 的类型化通知 API 搬到老系统](Evolutions/draft-notification-center-backport.md)。
这篇只讲怎么用，以及有哪些**签名上看不出来、违反了就出事**的约定。

## 先判断该用哪一个

- **部署目标已经是 26**：直接用 Foundation 原生的 `NotificationCenter.MainActorMessage` 一套，不要用这个。
- **部署目标低于 26**：用这个。等部署目标升上去，按文末的步骤换回原生，基本就是删掉 `Backport.`。
- **只想观察系统通知**（`NSApplication.didBecomeActiveNotification` 之类）：苹果 SDK 里预置的消息类型遵循的是
  它自己的协议，这里用不上。自己定义一个消息，用 `name` 对上系统通知名、用 `makeMessage(_:)` 从 `userInfo`
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
| 预置的系统消息 | 有 | 没有 |

两者在 26 系统上可以并存、互不干扰。但**不要让一个类型同时遵循两边的协议**：调用点会同时匹配两套重载，
编译器报歧义。

## 迁回原生 API

1. 把部署目标升到 26 一档。
2. 全局把 `NotificationCenter.Backport.` 替换成 `NotificationCenter.`。
3. 手动调用迭代器 `next()` 的地方补上 `try`。
4. 如果在属性或函数签名里把序列写成了 `NotificationCenter.Backport.AsyncMessageSequence<Message>`，
   改成 `some AsyncSequence<Message, Never>`。
