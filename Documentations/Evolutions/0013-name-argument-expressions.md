# 0013 - `@Loggable` / `@Signpostable` 的 subsystem 与 category 接受任意 `String` 表达式

- **状态**: Implemented
- **创建日期**: 2026-11-03
- **最后更新**: 2026-11-03

## 摘要

两个宏的 `subsystem:` 与 `category:` 原先声明为 `StaticString?`，实现只认字符串字面量：一个模块想让所有类型共用一个
subsystem，只能在每个类型上重抄同一串字面量；传一个 `StaticString` 常量能通过类型检查，却被悄悄换回类型名。改为
`String?`，参数表达式原样搬进生成的 getter——宏本来就只是把字面量放进那个计算属性，换成常量照样能工作。一个模块
声明一个常量（如 `let loggingSubsystem = "com.example.app"`），每个类型写 `@Loggable(subsystem: loggingSubsystem)` 即可。

## 方案

- 宏声明：两个宏、各两个重载的 `subsystem:` / `category:` 由 `StaticString? = nil` 改为 `String? = nil`。
- 宏实现：`extractStringLiteral(labeled:from:)` 换成 `extractNameExpression`，取参数表达式的源码原样放进 getter，与
  `isEnabled:` 的做法一致；参数缺省或写 `nil` 字面量时仍退回类型名。
- 新增一条报错：参数是一个裸名字，且恰好是宏自己生成的名字属性（`@Loggable` 的 `subsystem` / `category`，
  `@Signpostable` 的 `signpostSubsystem` / `signpostCategory`）时，报在参数上。getter 里的裸名字先找类型自己的成员，
  `subsystem: subsystem` 会让 getter 无限调用自己，`subsystem: category` 会读到生成的 category 而不是同名常量。
- 测试：两个宏各加常量表达式、协议分支与报错三个展开快照，`@Loggable` 另加 `nil` 字面量一个；`OSToolboxTests` 加
  `NameArgumentTests`，经真实编译确认 getter 返回常量的值；`DefaultMainActorIsolationClient` 加一个用模块常量命名的类型。
- 文档：两个宏声明上的参数说明、`AGENTS.md` 的 Logging 一节、随库发布的 `loggable-and-log` skill。

没问就定下的假设：

- 声明成 `String?` 而不是不带可选的 `String`：保留「不写或写 `nil` 就是类型名」的语义，改动最小。
- 只拒绝宏自己生成的名字，不管两个宏之间互相的名字：同一个类型上同时贴两个宏、又把一个宏的名字传给另一个，实在少见。
- 默认 MainActor 隔离的模块里，模块级的 `String` 常量不必写 `nonisolated`：在 Swift 6 语言模式的
  `DefaultMainActorIsolationClient` 里实测编得过，生成的 `nonisolated` getter 能直接读它。
- 源码兼容：传字面量的调用照旧编译，展开结果逐字不变，原有快照一个没改。唯一会编不过的是传 `StaticString` 类型常量的
  调用——它原本就被悄悄换回了类型名，现在改为在调用处报类型不符。
- 随 0.16.0 发布。顺带改正 `loggable-and-log` skill 里早已过时的说法：默认 subsystem 是类型名，不是 bundle identifier。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-03 | Created as Draft | 用户要让一个模块用一个常量统一提供 subsystem，而宏只认字面量 |
| 2026-11-03 | 参数改为 `String?`，表达式原样放进 getter | 用户指定的做法：宏本来就只是把参数放进计算属性，换成常量依然能工作 |
| 2026-11-03 | 拒绝与生成属性同名的裸名字参数 | 最顺手的常量名就是 `subsystem`，而它在 getter 里解析成 getter 自己，运行时无限递归 |
| 2026-11-03 | 落地，编号 0013，状态改为 Implemented | 全量构建与测试通过；随 0.16.0 发布，XCOrganizer 是第一个用上它的调用方 |
| 2026-11-03 | 更正「默认 MainActor 隔离下常量不必写 `nonisolated`」这条假设：必须写 | XCOrganizer 的壳（Swift 5、默认 MainActor 隔离）每个类型报一条警告。普通源文件里的全局 `let` 在这种模块里被推断成 MainActor 隔离，生成的 `nonisolated` getter 读它在 Swift 5 下是警告、Swift 6 下是错误；当初的实测把常量写在 `main.swift`，那里的顶层 `let` 不受这条推断影响，所以看不出来。编译用例挪进单独的文件 `UploadLogging.swift` 并写上 `nonisolated`，去掉它时确认会编不过 |
