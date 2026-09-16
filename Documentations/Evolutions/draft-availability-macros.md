# Draft - 引入 SwiftStdlib 可用性宏，收掉四平台长写法

- **状态**: Implemented
- **创建日期**: 2026-09-16
- **最后更新**: 2026-09-16
- **所属愿景**: 无
- **配套文档**: 无 —— 约束已写进 `CLAUDE.md` 与 `Package.swift` 注释

## 摘要

本库有 24 处 `@available(macOS N, iOS N, watchOS N, tvOS N, *)` 形式的长写法，
而且平台顺序还有两种（`macOS iOS watchOS tvOS` 与 `macOS iOS tvOS watchOS`）。
编译器的 `AvailabilityMacro` 实验性特性允许给一组平台版本起个名字，
于是这类标注可以写成 `@available(SwiftStdlib 5.7, *)`。

定义表逐字照搬上游（标准库、swift-foundation、swift-testing 都在用同一份映射），
这是有意的：`SwiftStdlib 5.7` 在这里的含义与在标准库里完全一致，
从 `.swiftinterface` 读到一个版本号可以直接拿来用，不必重新推导它对应哪四个平台版本。

## 方案

`Package.swift` 顶部定义 `availabilityMacros`，尾部用一个循环注入全部 39 个 target
（`PointerAuthenticationSupport` 除外，它是 C target，没有 Swift 要编译）。

**注入用循环而不是逐个 target 写 `swiftSettings:`**：39 个 target，一个「每次加 target
都要记得带上」的设置就是一个迟早会被忘掉的设置。`PackageDescription.Target` 是 class，
`package.targets` 拿到的是引用，循环里赋值即可生效。

### 实际替换了 9 处

全库能对上 `SwiftStdlib` 版本线的只有 `macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0`
这一组，即 `SwiftStdlib 5.7`，共 10 处，替换了其中 9 处。

**剩下的 19 处长写法不是本提案能收的** —— 它们是 SDK 能力的可用性
（`os.Logger` 在 macOS 11、`OSSignposter` 在 macOS 12），与标准库版本线无关。
要收掉它们需要另立本项目自己的语义宏（`_loggerAPI` / `_signposterAPI`，
swift-testing 就是这么做的），那是另一件事，本提案不做。

### 两个禁区

`AvailabilityMacro` 是 **per-target 的编译设置**。凡是「这段代码会在别人的编译单元里
被重新编译」的地方，都不能用它 —— 那里没有这个设置。

1. **`@inlinable` / `@_transparent` 函数体内不能用。**
   `FrameworkToolbox<String>.filePathURL` 就踩到了，编译器直接拒绝：
   `availability macro cannot be used in an '@inlinable' function`。
   该处已保留长写法并就地注明原因。
2. **宏的展开结果里不能用。** `LoggableMacro.loggerAvailability` 与
   `SignpostableMacro.signposterAvailability` 是两个生成 `@available(...)` 文本的
   常量，必须继续把平台版本写全。

**两者的危险程度不同。** 第一种编译器有诊断，当场就拦住了；
**第二种编译器不会提醒任何人** —— 本包编译得好好的，炸在下游使用方的编译单元里，
错误还指向一段他们源码里根本不存在的生成代码。这与 `CLAUDE.md` 里那条
「宏不得展开出调用方没有 import 的模块」是同一个失效模式，换了层皮。

### 与「暂不采纳 @_rawLayout」那份提案的关系

同一天里一份提案因为「不该把基础库钉死在没有 Swift Evolution 提案的实验性特性上」
被 Deferred，另一份提案却引入了一个实验性特性，这需要解释。

差别在**失效时的代价**，不在特性的实验性程度：

- `@_rawLayout` 那组改的是内存布局与移动语义，赌错了是内存安全级别的问题，
  且回退意味着重写实现、恢复堆分配。
- `AvailabilityMacro` 只影响编译期把 `@available` 展开成什么，
  不进入生成代码，不影响 ABI，对使用方完全不可见。
  特性哪天没了，`sed` 回长写法就行，是机械操作，影响面就是这 9 处。

再加一条旁证：标准库自己、swift-foundation、swift-testing 都在长期依赖它。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-16 | 引入 `AvailabilityMacro`，定义表照搬上游 | 名字与标准库同义，`.swiftinterface` 上读到的版本号可直接使用，不必重新推导 |
| 2026-09-16 | 用循环注入而非逐 target 声明 | 39 个 target，需要每次记得带上的设置必然被遗忘 |
| 2026-09-16 | `@inlinable` 处保留长写法 | 编译器拒绝：`availability macro cannot be used in an '@inlinable' function` |
| 2026-09-16 | 宏展开结果继续写全平台版本 | 展开发生在调用方编译单元，那里没有这个设置；且编译器不会就此给出任何诊断 |
| 2026-09-16 | 不收那 19 处 `os.Logger` / `OSSignposter` 长写法 | 它们属于 SDK 能力可用性，与标准库版本线无关，要收需另立语义宏，属另一件事 |
| 2026-09-16 | 状态置为 Implemented | macOS / iOS / Mac Catalyst 构建通过，完整测试套件原始退出码 0，零警告 |
