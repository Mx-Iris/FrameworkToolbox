# Draft - 把宏展开里的类型错误指回调用方源码

- **状态**: In Progress
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **实现分支**: `feature/macro-patterns`

## 摘要

有些错误只有编译器能发现，却发生在宏生成的代码里：`@DyldInterpose` 的替换函数与被替换函数签名不一致时，
类型错误落在生成的 `(replacement, replacee)` 元组上；`@Projection` 的某个 case 的关联值不满足投影函数的约束时，
错误落在生成的 `switch` 分支上。报错位置是 `macro expansion @DyldInterpose:9:114` 这样的展开缓冲区，调用方得自己
从附注里找回源码。本提案在生成代码里加 `#sourceLocation`，让这两种错误报在调用方写的那一行上（skill 技巧 6）。

## 方案

- 用 `context.location(of:at:filePathMode:)` 取出被映射节点在用户文件里的位置，生成
  `#sourceLocation(file:line:)` … `#sourceLocation()` 包住出错的那一行。这个指令设置的是**紧随其后那一行**的行号，
  所以被包住的代码必须独占指令后的那一行。拿不到位置（上下文给不出）时照旧生成，不带指令。
- **`@DyldInterpose` / `@DyldDynamicInterpose`**：映射到属性所在的行，也就是写着被替换函数的那一行。原来元组的
  `@section` / `@used` 属性写在 `#if compiler(>=6.3)` 里、声明在 `#if` 之外，跨了好几行；改为每个分支各写一行完整的
  「属性 + 声明」，指令紧贴在前。
- **`@Projection`**：每个分支的投影调用映射到对应 case 所在的行，错误直接指向需要改的那个 case。指令放在 case 的分支体里
  （`switch` 的 case 列表里不允许出现它），调用独占一行；实测分支仍可作为 `switch` 表达式的单表达式分支。

### 源码兼容性

能编译的代码展开结果多出指令行，行为不变。编译失败的代码，错误位置从展开缓冲区移到调用方源码。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 按 `swift-macro-patterns` skill 的技巧审视全部宏时发现：两处只能由编译器发现的类型错误落在展开代码里 |
| 2026-10-27 | 用户批准，开始实现 | 审视结论中的各项改进经用户同意全部实施 |
| 2026-10-27 | 实测通过 | 用临时文件各制造一次错误：`@DyldInterpose(getpid)` 配一个返回 `Int64` 的函数，错误从 `macro expansion @DyldInterpose:9:114` 移到用户文件第 5 行（属性所在行）；`@Projection` 里一个 `case count(Int)` 不满足 `some Identifiable<String>`，错误从 `macro expansion @Projection:6:14` 移到该 case 所在的第 11 行。临时文件随后删除 |
| 2026-10-27 | 撤回 `@ObjectiveCBridgeable` 的遵循检查 | 原计划把 `ObjectiveCRepresentable` 列进宏的 `conformances:`，由编译器传回的 `conformingTo:` 判断类型是否遵循，不遵循时给一条清楚的错误代替展开里的一串连锁错误。实测编译器传回的列表**不含经由细化协议隐含得到的遵循**：包内六个句柄都通过 `ObjectiveCCollectionHandle` 遵循，全部被误报为缺少 `ObjectiveCRepresentable`。这个信号对本宏最常见的用法不可靠，改动整体撤回，行为保持原样 |
| 2026-10-27 | 实现完成，待合并 | 完整测试套件通过 |
