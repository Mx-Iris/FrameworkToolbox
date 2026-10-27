# Draft - `@Equatable` 让编译器检查每个成员能否比较

- **状态**: In Progress
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **实现分支**: `feature/macro-patterns`

## 摘要

`@Equatable` 生成的 `==` 逐个比较存储属性。只要有一个成员的类型不遵循 `Equatable`——一个普通的 class、
`[String: Any]`、写成 typealias 或带了 `@Sendable` / `@MainActor` 的闭包——编译器报的就是展开代码里的
`binary operator '==' cannot be applied to two 'X' operands`：指向一段调用方没写过的代码，也不告诉他该怎么办。
宏自己判断不了一个类型遵不遵循协议，它只认拼写：现有的闭包检测认得 `() -> Void`，认不得
`@Sendable () -> Void`、`Optional<() -> Void>` 和 typealias 出来的闭包。

本提案让编译器替宏判断：每个参与比较的成员挂一个检查宏，这个宏按「成员类型是否遵循 `Equatable`」重载；
不遵循时在用户写的那个属性上报错，并给出「加 `@EquatableIgnored`」的一键修复。

## 方案

- **`@Equatable` 增加 memberAttribute 角色**，给每个会参与比较的存储属性加上
  `@SwiftStdlibToolbox._EquatableMemberCheck(type: T.self)`；没写类型注解时传初始值本身，
  `(initialValue: <初始值>)`，由编译器推断它的类型。不加的：已被跳过的成员（`@EquatableIgnored`、
  `@EquatableIgnoredUnsafeClosure`、SwiftUI 的属性包装器）、已被现有闭包检测拦下的成员、`static` 与计算属性、
  一次绑定多个变量的声明，以及没写类型注解的 `lazy` 属性（它的初始值可以引用 `self`，搬进属性参数里就不合法了）。
- **`_EquatableMemberCheck` 是一组只差泛型约束的 peer 宏**（skill 技巧 2，出处 structured-queries 的 `ColumnCheck`）：
  `<Member: Equatable>` 那个指向空实现，不带约束的那个指向报错实现。编译器像对普通函数那样做重载决议：
  两个都满足时约束更具体的胜出，类型不遵循时只剩报错那一个。检查宏不生成任何代码，没有运行时成本。
- **类型声明了 `Hashable` 时改挂 `_HashableMemberCheck`**：`@Equatable` 生成的 `hash(into:)` 要对每个成员
  `hasher.combine`，这时成员要满足的是 `Hashable`。判断依据是类型声明自己的继承子句：memberAttribute 角色拿不到
  编译器算好的遵循列表，所以在别处 extension 里声明的 `Hashable` 这里看不见，那种类型仍按 `Equatable` 检查。
- **两种参数用不同标签**（`type:` 与 `initialValue:`）。不用标签时，`Int.self` 这个元类型值也能匹配按值传的重载，
  白白多出一组需要靠排序规则消歧的组合。
- **报错落在用户的属性上**（skill 技巧 6）：检查宏是挂在用户声明上的 peer 宏，拿到的 `declaration` 就是用户写的
  那个属性，诊断和 Fix-It 直接作用于它。Fix-It 在属性的属性列表里加 `@EquatableIgnored`；构造替换内容时先滤掉
  生成的检查属性本身——编译器传进来的 `declaration` 不含它，测试框架传进来的含它，滤掉之后两边结果一致。
- **报错措辞**按参数形态区分：传类型时说出类型名（`'[String: Any]' is not Equatable…`），传初始值时只能说属性名。

- **只检查直接声明在类型体里的成员。** 编译器对活动的 `#if` 分支里的成员同样套用 memberAttribute，而 `==` 只比较直接
  声明的成员；不加区分就会报出一个根本不参与比较的成员（实测，见决策日志）。

**展开代码里的原报错仍然在。** 检查宏只增加一条落在成员上的报错，生成的 `==` 照旧逐个比较，所以
`binary operator '=='`（以及 Hashable 类型的 `combine requires … Hashable`）还会跟着出现在 `@Equatable` 那一行。要压掉它，
得让 `==` 对检查过的成员改走一个「类型不遵循时静默放行」的重载辅助函数——但只要两个角色对「哪些成员被检查」的判断出现
一次分歧，`==` 就会悄无声息地给出错误结果。用一条噪音换掉一类静默错误不划算，所以不做。应用 Fix-It 之后两条报错一起消失。

### 源码兼容性

能编译的类型，展开结果多出若干检查属性，比较行为不变。原来编译失败的类型（有成员不能比较）仍是错误，只是多出一条落在
成员上的说明和 Fix-It。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 按 `swift-macro-patterns` skill 的技巧审视全部宏时发现：`@Equatable` 判断成员能否比较只能看拼写，漏判时错误落在展开代码里 |
| 2026-10-27 | 用户批准，开始实现 | 审视结论中的各项改进经用户同意全部实施 |
| 2026-10-27 | Fix-It 只提供 `@EquatableIgnored`，不提供 `@EquatableIgnoredUnsafeClosure` | 后者自己也按拼写判断「是不是闭包」，typealias 出来的闭包会被它拒绝；而检查宏无法从类型判断出「这是闭包」 |
| 2026-10-27 | Hashable 类型的判断只看继承子句 | memberAttribute 角色拿不到编译器的遵循信息；在别处声明 `Hashable` 的类型退回 `Equatable` 检查，最坏情况是错误仍落在 `hash(into:)` 的展开里，与改动前一样 |
| 2026-10-27 | 元组与元类型成员不加检查 | 二者都不遵循 `Equatable`，但 `==` 能通过标准库重载比较它们；加检查就是误报 |
| 2026-10-27 | 真实编译验证了重载选择 | 通过的一侧（带类型、字面量推断、条件遵循、泛型参数、可选、隐式解包）常驻在 `SwiftStdlibToolboxClient/EquatableMemberChecks.swift`；报错的一侧（`[String: Any]`、推断出的普通 class、Hashable 类型里只遵循 Equatable 的成员）必然编不过，用临时文件编译一次核对后删除：每个成员都在自己那一行收到对应的报错 |
| 2026-10-27 | 只检查直接声明的成员 | 实测：编译器对 `#if DEBUG` 里的成员也套用了 memberAttribute，报出一个 `==` 并不比较的成员；守卫 `ConditionalMemberCheckCoverage` 在去掉这条判断时变红 |
| 2026-10-27 | 不压掉展开代码里的原报错 | 压掉需要一个对不遵循类型静默放行的比较函数，两个角色的判断一旦分歧就会静默算错；理由见方案一节 |
| 2026-10-27 | 实现完成，待合并 | 宏测试、真实编译守卫与完整测试套件全部通过 |
