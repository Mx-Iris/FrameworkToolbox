# Draft - 把 swift-foundation 的类型化通知 API 搬到老系统：`NotificationCenter.Backport`

- **状态**: Implemented
- **创建日期**: 2026-10-03
- **最后更新**: 2026-10-03
- **所属愿景**: 无
- **配套文档**: [`NotificationCenter.Backport` —— 类型化通知消息的用法契约与陷阱](../NotificationCenterBackport.md)

## 摘要

Swift 6.2 的 Foundation 给 `NotificationCenter` 加了一套类型化、带并发隔离的消息 API
（swift-foundation 提案 [SF-0011 Concurrency-Safe Notifications](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0011-concurrency-safe-notifications.md)）。
消息是普通的 Swift 类型，遵循 `MainActorMessage`（在主线程同步投递）或 `AsyncMessage`（任意隔离、异步投递）；
观察返回 `ObservationToken`，token 一释放观察就结束；异步消息还能用 `messages(of:for:)` 当 `AsyncSequence` 消费。
它在苹果平台上标着 macOS / iOS / tvOS / watchOS / visionOS **26**，而本库的底线是 macOS 10.15 / iOS 13 一档。

本提案把 swift-foundation `Sources/FoundationEssentials/NotificationCenter/`（revision `3b9d8f4`）的实现搬进
`FoundationToolbox`。五个公开类型挪进 `NotificationCenter.Backport` 子命名空间；方法名、参数标签、默认值、
投递语义、与 `Notification` 的互通，都与苹果一致。将来部署目标升到 26，删掉 `Backport.` 就换回了原生 API。

## 方案

### 公开 API

| 苹果（macOS 26+） | 本库 |
|---|---|
| `NotificationCenter.MainActorMessage` | `NotificationCenter.Backport.MainActorMessage` |
| `NotificationCenter.AsyncMessage` | `NotificationCenter.Backport.AsyncMessage` |
| `NotificationCenter.MessageIdentifier` | `NotificationCenter.Backport.MessageIdentifier` |
| `NotificationCenter.BaseMessageIdentifier<MessageType>` | `NotificationCenter.Backport.BaseMessageIdentifier<MessageType>` |
| `NotificationCenter.ObservationToken` | `NotificationCenter.Backport.ObservationToken` |
| `messages(of:for:bufferSize:)` 返回 `some AsyncSequence<Message, Never> & Sendable` | 返回 `NotificationCenter.Backport.AsyncMessageSequence<Message>`（见「必须偏离的三处」） |

`addObserver(of:for:using:)`（MainActor 与 Async 各三个重载）、`post(_:subject:)` / `post(_:)`、
`messages(of:for:bufferSize:)`、`removeObserver(_:)` 名字不变，靠泛型约束里的协议与苹果的重载区分。
已用 MainActor 消息的几种调用点实测：部署目标设为 macOS 26、苹果的重载全部可用时，
`center.addObserver(of: event, for: .didStart)` 不产生歧义。

### 搬哪条实现路径

swift-foundation 里有两套实现。`FOUNDATION_FRAMEWORK` 用于苹果平台：架在 `NSNotificationCenter` 之上，
消息塞进 `userInfo` 投递，能与 `Notification` 双向互通。`!FOUNDATION_FRAMEWORK` 用于 Linux 等平台：
一个纯 Swift 的注册表，不互通。**搬前者**——苹果平台上用户实际拿到的就是它，而
`name` / `makeMessage(_:)` / `makeNotification(_:)` 这三个互通要求也只存在于这条路径。

### 苹果私有入口的公开替代

这条路径用了 `NSNotificationCenter` 的四个私有入口，已在 macOS 27.0 的 Foundation（5027.0.69）里逐个反汇编核对：

| 私有入口 | 它实际做什么 | 替代 |
|---|---|---|
| `_addObserver:object:usingBlock:` | 直接向 CoreFoundation 注册 block，不创建 `__NSObserver`，返回整数 token。在当前线程同步投递，name 按字符串、object 按指针匹配，与公开 API 相同；**不持有通知中心** | `addObserver(_:selector:name:object:)`，观察者是一个只负责转发到 block 的内部对象 |
| `_removeObserver:` | 按 token 注销；在子类上改发 `removeObserver:`，让子类的 override 看得到 | `removeObserver(_:)`，传那个转发对象 |
| `_getActorQueueManager` | 在锁内懒建异步投递队列，存进中心的 ivar，中心 dealloc 时释放 | 用 associated object 挂在中心上，生命周期相同 |
| `_NSRuntimeIssuesLog()` | `os_log_create("com.apple.runtime-issues", "Foundation")`，并以 Foundation 自己的 Mach-O 头作 `dso`，Xcode 据此显示紫色 runtime issue | `@Loggable` + `#log(.fault, …)`；紫色标记不复刻 |

**不用 block 版的 `addObserver(forName:object:queue:using:)`。** 它创建的 `__NSObserver` 由 Foundation
自己持有到注销为止，而这个对象持有通知中心——用它，只要还有 token 活着，自建的 `NotificationCenter()`
就释放不掉。苹果的私有入口没有这层持有；selector 版对观察者是弱引用，也不持有中心，与苹果一致。

**token 的注销要加锁。** 苹果的 token 是个整数，两个线程同时注销是良性的竞争（CoreFoundation 会忽略过期的
token）。这里换成了对象引用，同样的竞争会变成对同一个强引用并发读写，可能过度释放而崩溃。用 `Mutex`
保护起来，行为上与苹果相同，只是不会崩。

### 必须偏离的三处

这三处本身就要求新系统，以 macOS 10.15 / iOS 13 为部署目标实测编译都会报错：

1. **`messages(of:for:)` 的返回类型。** `some AsyncSequence<Message, Never>` 里的 `Never` 填的是
   `AsyncSequence` 的 `Failure` 关联类型（序列可能抛出的错误类型），它 macOS 15 / iOS 18 才有；只写一个参数的
   `some AsyncSequence<Message>` 不被允许。改为把苹果内部那个 sequence 类型公开出来，即
   `NotificationCenter.Backport.AsyncMessageSequence<Message>`。迭代器保持苹果的引用语义（`final class`，
   复制出来的迭代器共享同一份缓冲）。`for await message in …` 的写法不变；在 macOS 15 以上它的 `Failure`
   推断为 `Never`（已实测），能当 `some AsyncSequence<Message, Never>` 用。
2. **异步观察者的投递队列。** 苹果的 worker 用 `withDiscardingTaskGroup`（macOS 14 / iOS 17）：每条消息开一个
   子任务，跑完的结果自动丢弃。普通的 `withTaskGroup` 会一直攒着跑完的子任务，直到有人来取结果，长寿的中心会无界增长。
   改为把「等新工作」本身也做成一个子任务，worker 循环只做 `group.next()`：取到「来了新工作」就开执行子任务、
   再补一个等待子任务；取到「执行完了」就丢掉。取消语义不变：中心释放 → 取消 worker → 子任务全部被取消。
   **所有系统版本走这一条路径，不按 `#available` 分叉**——分叉的话，老系统那一支恰恰是本机（macOS 27）上的测试
   永远跑不到的。`State.waitForWork` 与 `enqueue` 逐字保留。
3. **`Deque`。** 它来自 swift-collections，本包没有这个依赖。缓冲只用到尾部追加、头部取出、计数、清空四个操作，
   写一个内部的小 FIFO 缓冲代替，不给包新增依赖。

另有两处是同功能替换：`Synchronization.Mutex`（macOS 15+）换成 `OSToolbox` 的 `Mutex`，接口一致；
`os.Logger`（macOS 11+）换成 `#log`。

### 源码兼容性

纯增量。ABI 兼容性：不适用——本库以 SPM 源码分发，使用方每次重新编译。`FoundationToolbox` 是 re-export
链的最顶层，没有别的 target re-export 它，影响面止于直接依赖它的调用方。新增的公开名字都在
`NotificationCenter.Backport` 之下，外加 `NotificationCenter` 上的若干方法重载。

### 测试与验证

- swift-foundation 自带的 `NotificationCenterMessageTests` 改名后搬进 `Tests/FoundationToolboxTests/`，
  包括只在 `FOUNDATION_FRAMEWORK` 下编译的 `Notification` 互通测试。几处因可用性要改写：`Atomic`（macOS 15）
  换成 `Mutex`；`Task.sleep(for:)`（macOS 13）换成纳秒版；`center.isEmpty()` 与 override `_removeObserver`
  是私有入口，改用一个记录 `addObserver` / `removeObserver` 调用的 `NotificationCenter` 子类，观察同一件事。
- 为偏离之处补测试：观察期间自建的中心能被释放；中心释放后投递队列随之释放、worker 结束；FIFO 缓冲的溢出与清空；
  `AsyncMessageSequence` 在 macOS 15+ 能当 `some AsyncSequence<Message, Never>` 用。
- 按 `Specs/2026-08-06-dynamic-invocation-design.md` 里的循环，把 iOS / tvOS / watchOS / visionOS /
  Mac Catalyst 都编一遍——`swift build` 只覆盖 macOS，可用性问题只在编译期暴露。
- **做不到的**：本机是 macOS 27，测试跑不到老系统的运行时。最要紧的一点——在主线程、Task 之外调用
  `MainActor.assumeIsolated` 不会误判——已从 Swift 运行时源码确认：`swift_task_isCurrentExecutor` 自 5.5
  起就会把「在主线程上」认作在主执行器上。但这只是读源码的结论，没有在老系统上实际跑过；如需实测，可另起
  一台 macOS 13 虚拟机跑测试。

### 文档

- 新增使用指南 `Documentations/NotificationCenterBackport.md`：怎么定义消息、与 `Notification` 互通的契约、
  与苹果原生 API 的差异清单、日后迁回原生 API 的步骤，以及沿袭自苹果的几处陷阱。
- 新增 `LICENSES/swift-foundation-LICENSE`（Apache 2.0 with Runtime Library Exception）；搬来的文件保留原版权头，
  并注明做过改动。
- `CLAUDE.md` 的 `FoundationToolbox` 一行与 Key Patterns 各补一条；两份文档索引同步。

### 未问就定下的假设

- 放进 `FoundationToolbox`，不新开 target 或 product。
- 只搬通用机制。苹果 SDK 里预置的系统消息（`UndoManager.WillUndoChangeMessage`、
  `HTTPCookieStorage.CookiesChangedMessage` 等）遵循的是苹果的协议，这里用不上；需要时由使用方按
  `name` + `makeMessage(_:)` 自行定义。
- 不与苹果原生 API 互相桥接。macOS 26+ 上两者共存、各管各的；一个类型若同时遵循两边的协议，调用点会产生歧义。
- 苹果实现里那些不显眼的行为原样保留、不顺手「修」，写进指南的陷阱一节：token 注销后与其它已注销的 token
  相等、哈希值随之改变；sequence 只弱持有 subject，subject 若在 `makeAsyncIterator()` 之前释放，迭代器会退化为
  观察所有 subject。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-03 | Created as Draft | 用户要求「把 Swift 新版 Notification 接口搬过来，改一下名字，其他都一样」，因为苹果平台上它要求的系统版本太高 |
| 2026-10-03 | 公开类型挪进 `NotificationCenter.Backport`，方法名不变 | 用户选定。内部名字一个不改，迁回原生 API 时删掉 `Backport.` 即可；方法靠协议约束与苹果的重载区分，macOS 26 目标下实测无歧义。备选的「模块顶层短名」会与使用方自己的 `AsyncMessage` 之类撞名，「方法也走 `.box`」会让调用点与苹果不同 |
| 2026-10-03 | 搬 `FOUNDATION_FRAMEWORK` 路径 | 苹果平台上实际运行的是它；与 `Notification` 的互通只存在于这条路径 |
| 2026-10-03 | 观察者注册用 selector 版 `addObserver(_:selector:name:object:)`，不用 block 版 | 反汇编确认苹果的私有入口不持有通知中心，而 block 版的 `__NSObserver` 会持有到注销为止 |
| 2026-10-03 | token 的注销加锁 | 苹果的整数 token 并发注销是良性的；换成对象引用后同样的竞争可能过度释放 |
| 2026-10-03 | `messages(of:for:)` 返回具名的公开类型 | `AsyncSequence` 的 `Failure` 关联类型 macOS 15 才有，底线上写不出苹果的不透明返回类型 |
| 2026-10-03 | 投递 worker 不按 `#available` 分两支 | `withDiscardingTaskGroup` 只在 macOS 14+；分叉后老系统那一支在本机永远测不到，而老系统正是这次移植的目的 |
| 2026-10-03 | 不引入 swift-collections，内部写 FIFO 缓冲 | 只用到四个操作，不值得给所有使用方加一个包依赖 |
| 2026-10-03 | runtime issue 降级为普通 fault 日志 | 紫色标记要以系统镜像的 `dso` 记日志，等于冒充 Foundation |
| 2026-10-03 | 状态 Draft → Accepted | 用户批准（「开工」），实现开始 |
| 2026-10-03 | 迭代器改为 struct 包住上游的 class | 实现时发现：直接公开 class 的话，照苹果写法 `var iterator` 会报 never mutated；`AsyncStream.Iterator` 就是这个形状，复制仍共享缓冲 |
| 2026-10-03 | 测试套件的 `.timeLimit(.minutes(1))` 只在 macOS 13+ 加上 | 它要求 macOS 13，硬加会把整个套件挡在老系统之外；它也救不了不响应取消的等待，worker 那条测试另用非结构化任务自带 10 秒超时 |
| 2026-10-03 | 并发注销测试跑 100 轮 | 不加锁时单轮约九成仍能通过、20 轮时五次里仍有一次通过；100 轮下不加锁 8/8 红、加锁 5/5 绿 |
| 2026-10-03 | 三条关键偏离测试都看着变红过 | 改回 block 版注册 → 两条不持有中心的测试红；去掉锁 → 并发注销测试红；去掉 worker 取消 → worker 测试 10.66 秒报失败 |
| 2026-10-03 | 配套使用指南：写；术语表：不新增 | 有签名上看不出的契约（主线程假定、token 生命周期、序列缓冲与弱持有 subject）；项目尚无 `Glossary.md`，`Backport` 是普通英文词，不值得为它新建 |
| 2026-10-03 | 状态 Accepted → Implemented | 上游 38 个测试全部移植 + 10 个偏离测试通过；iOS / tvOS / watchOS / visionOS / Mac Catalyst 构建 0 错误 0 警告 |
