# Draft - `@AddCompletionHandler` 生成的 completion 改为 `@Sendable`

- **状态**: Accepted
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **实现分支**: `feature/add-completion-handler-sendable`

## 摘要

`@AddCompletionHandler` 给一个 `async` 函数生成带 completion 参数的同步版本：函数体用 `_Concurrency.Task { … }` 调用原函数，
再把结果交给 completion。completion 的类型是 `@escaping (Swift.Result<T, any Swift.Error>) -> Void`，不是 `@Sendable`；
而 `Task` 的闭包参数是 `sending` 的，捕获一个非 `Sendable` 的参数就是把它送进另一个并发域。所以在 Swift 6 语言模式下，
`nonisolated` 的类型或函数上用这个宏，生成的代码编不过（`passing closure as a 'sending' parameter risks causing data races`），
报错落在调用方没写过的展开代码里。本提案把生成的 completion 参数改为 `@escaping @Sendable (…) -> Void`。

## 方案

- 生成的参数类型改为 `@escaping @Sendable (Swift.Result<T, any Swift.Error>) -> Void`，函数体不变。
- 在 `DefaultMainActorIsolationClient`（Swift 6 语言模式、默认 MainActor 隔离）加一个守卫：`nonisolated` 类型上的
  `@AddCompletionHandler`。改动前它编不过，改动后能编译。
- 宏的文档注释写明 completion 是 `@Sendable` 的、会在哪个并发域被调用；`CLAUDE.md` 里记着「待决定」的那一条改为结论。

没有询问就采用的假设：

- **只改 completion 一处。** 被转发的参数或 `self` 本身不是 `Sendable` 时（例如一个普通 class 的实例方法），生成的 `Task`
  捕获它们，Swift 6 下照样报同一个错。手写同样的代码结果也一样，这属于调用方类型的并发设计，宏不替它绕开；文档注释写明。
- 不提供保留旧签名的开关。

### 源码兼容性

展开出的公开签名变了，按源码破坏对待：

- 传给 completion 的闭包从此按 `@Sendable` 检查，例如在闭包里修改捕获的局部 `var` 会被拒绝。不同语言模式下各报什么，
  实现时实测并记入决策日志。
- 原来在 Swift 6 下编不过的 `nonisolated` 用法变为可以编译。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 按 `swift-macro-patterns` skill 审视全部宏时发现：Swift 6 语言模式下 `nonisolated` 类型上的 `@AddCompletionHandler` 编不过，原因是生成的 completion 不是 `@Sendable`；要不要改生成的签名当时留给用户决定 |
| 2026-10-27 | 用户批准，开始实现 | 用户决定把 completion 改为 `@Sendable`，接受它给调用点带来的限制 |
