# Draft - `@AddCompletionHandler` 可选地把 completion 标成 `@Sendable`

- **状态**: In Progress
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **实现分支**: `feature/add-completion-handler-sendable`

## 摘要

`@AddCompletionHandler` 给一个 `async` 函数生成带 completion 参数的同步版本：函数体用 `_Concurrency.Task { … }` 调用原函数，
再把结果交给 completion。completion 的类型是 `@escaping (Swift.Result<T, any Swift.Error>) -> Void`，不是 `@Sendable`；
而 `Task` 的闭包参数是 `sending` 的，捕获一个非 `Sendable` 的参数就是把它送进另一个并发域。所以在 Swift 6 语言模式下，
`nonisolated` 的类型或函数上用这个宏，生成的代码编不过（`passing closure as a 'sending' parameter risks causing data races`），
报错落在调用方没写过的展开代码里。

把 completion 直接改成 `@Sendable` 能修好这一处，但实测代价落在现有调用方身上：在主线程上写的 completion 里改主线程状态，
连 Swift 5 下都成了错误（见源码兼容性一节）。所以本提案给宏加一个参数 `sendable:`，默认 `false`，生成的签名与过去完全相同；
需要在 Swift 6 下用于 `nonisolated` 类型的调用方写 `sendable: true`，自己承担这份代价。

## 方案

- 宏声明改为 `AddCompletionHandler(sendable: Bool = false)`。默认时生成的参数仍是
  `@escaping (Swift.Result<T, any Swift.Error>) -> Void`，展开与改动前逐字相同；`sendable: true` 时是
  `@escaping @Sendable (…) -> Void`。函数体不变。
- 参数只收布尔字面量，照 `@ObjectiveCBridgeable(inlinable:)` 的先例：`@Sendable` 是生成签名的一部分，展开时就要有答案。
  不是字面量时在参数上报错，并按 `false` 继续展开。
- 守卫放在 `DefaultMainActorIsolationClient`（Swift 6 语言模式、默认 MainActor 隔离），一正一反：`nonisolated` 的
  `ReceiptLoader` 写 `sendable: true`，不写就编不过；主线程隔离的 `ReceiptStore` 用默认值，调用方在主线程上写的 completion
  里改主线程状态，写了 `sendable: true` 就编不过。
- 宏测试：默认展开不变；`sendable: true` 与显式的 `sendable: false` 各一例；非字面量报错一例。
- 宏的文档注释写明何时该用、代价是什么，以及 completion 在哪个并发域被调用；`CLAUDE.md` 里记着「待决定」的那一条改为结论。

没有询问就采用的假设：

- **选用 `sendable: true` 时只改 completion 一处。** 被转发的参数或 `self` 本身不是 `Sendable` 时（例如一个普通 class 的实例
  方法），生成的 `Task` 捕获它们，Swift 6 下照样报同一个错。手写同样的代码结果也一样，这属于调用方类型的并发设计，宏不替它
  绕开；文档注释写明。
- **参数名 `sendable:`**：与 `@ObjectiveCBridgeable(inlinable:)` 一样，以它在生成代码上加的那个属性命名。

### 源码兼容性

默认值保持原签名，现有调用点的展开一字不变，不受影响。`sendable: true` 是新写法，选用它的调用方，传给 completion 的闭包按
`@Sendable` 检查，各种写法实测如下（Swift 5 一列用本包的 `SwiftStdlibToolboxClient`，Swift 6 一列用默认 MainActor 隔离的
`DefaultMainActorIsolationClient`）：

| 调用方写法 | Swift 5 | Swift 6 |
|------|------|------|
| 在 `@MainActor` 的代码里传闭包，闭包里改主线程隔离的状态 | **错误** | 错误 |
| 闭包里修改捕获的局部 `var` | 警告 | 错误 |
| 传入一个已有的、非 `@Sendable` 的函数值 | 警告 | 错误 |
| 闭包捕获非 `Sendable` 的类实例 | 无诊断 | 错误 |

第一行的报错是 `main actor-isolated property … can not be mutated from a Sendable closure`。它分两种情况：函数所在的类型
不隔离时，completion 其实在全局并发执行器上执行，闭包里改主线程状态本来就是数据竞争，这条错误抓的是真问题；函数所在的类型
本身主线程隔离时，生成的 `Task` 继承主线程，completion 确实在主线程执行，这条错误是误报。Swift 6 两种情况都实测过；
Swift 5 实测的是前一种，而这条检查只看闭包本身是 `@Sendable`、与被调用函数的隔离无关，所以后一种同样是错误，不是警告。

选用 `sendable: true` 后，原来在 Swift 6 下编不过的 `nonisolated` 用法变为可以编译，前提是 `self` 与被转发的参数都是
`Sendable`；`self` 是非 `Sendable` 的类时仍然报同一个错（实测：`closure captures 'self' which is accessible to code in the
current task`）。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 按 `swift-macro-patterns` skill 审视全部宏时发现：Swift 6 语言模式下 `nonisolated` 类型上的 `@AddCompletionHandler` 编不过，原因是生成的 completion 不是 `@Sendable`；要不要改生成的签名当时留给用户决定 |
| 2026-10-27 | 用户批准，开始实现 | 用户决定把 completion 改为 `@Sendable`，接受它给调用点带来的限制 |
| 2026-10-27 | 守卫先红后绿 | 改动前 `DefaultMainActorIsolationClient` 的 `ReceiptLoader` 编不过，报 `passing closure as a 'sending' parameter risks causing data races`，附注 `closure captures 'completion'`；改动后编译通过 |
| 2026-10-27 | 调用方写法逐项实测，结果写进源码兼容性一节 | 用两个语言模式的客户端 target 各编一次临时文件，编完删除。代价最大的是主线程隔离的调用方：Swift 5 下也是错误，并且函数本身主线程隔离时是误报 |
| 2026-10-27 | 文档注释写明 `self` 与转发参数也要 `Sendable` | 实测：`nonisolated` 的非 `Sendable` 类上，Swift 6 仍报同一个错，附注换成 `closure captures 'self'` |
| 2026-10-27 | 主线程隔离调用方的代价交用户在合并前确认 | 批准时的依据是「改成 `@Sendable` 才能修好 Swift 6 下的编译失败」，那时还没有测出 Swift 5 下的这条错误。实现按批准的方案完成；要不要以这个代价合并，留到收尾前由用户决定 |
| 2026-10-27 | 实现完成，待合并 | 干净重编后完整测试套件通过（700 个 swift-testing 测试、51 个 XCTest），没有新增警告。文档判断：用法与代价写在宏的文档注释和 `CLAUDE.md` 的异步桥接一条，异步桥接宏没有独立的使用指南，不另写；没有新术语 |
| 2026-10-27 | 方案改为由宏参数控制，默认不加 `@Sendable` | 用户看过调用方实测后决定：直接改签名，会让在主线程上写 completion 的现有调用方编不过，Swift 5 下也是；撤回，又让 Swift 6 下 `nonisolated` 类型上的用法无路可走。加参数、默认保持原签名，现有调用方不受影响，需要的调用方自己选用。上面「交用户在合并前确认」一行到此有了结论 |
| 2026-10-27 | 参数只收布尔字面量 | 照 `@ObjectiveCBridgeable(inlinable:)` 的先例：`@Sendable` 是生成签名的一部分，展开时就要有答案；不是字面量时在参数上报错，并按 `false` 继续展开。测试框架在出现错误诊断后不记录展开结果，所以报错那例的快照只有诊断 |
| 2026-10-27 | 守卫改为一正一反 | `ReceiptLoader`（`nonisolated`）写 `sendable: true`，证明选用后 Swift 6 下能编译；`ReceiptStore`（主线程隔离）用默认值、调用方闭包里改主线程状态，证明默认值保住了这种写法。两者在 Swift 6 客户端里都编译通过 |
| 2026-10-27 | 实现完成，待合并 | 改宏之后 touch 全部源文件重编，完整测试套件通过（702 个 swift-testing 测试、51 个 XCTest），没有新增警告。文档判断：参数的用法与代价写在宏的文档注释和 `CLAUDE.md` 的异步桥接一条，异步桥接宏没有独立的使用指南，不另写；没有新术语 |
