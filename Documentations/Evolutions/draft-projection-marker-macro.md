# Draft - 把 @Projection 的字符串参数换成标记宏

- **状态**: Implemented
- **创建日期**: 2026-09-20
- **最后更新**: 2026-09-20

## 摘要

`@Projection(through: "id")` 用一个字符串指向宿主里的 `static func`。字符串是魔法值：函数改名
时它不会跟着改，写错了只能由宏在展开时报错。本提案把它换成一对配合使用的宏——`@Projection` 贴在
枚举上，`@ProjectionFunction` 贴在投影函数上——名字由函数声明本身提供，没有字符串。

```swift
@Projection enum Target {
    case user(User)
    case session(Session?)
    case anonymous

    @ProjectionFunction
    static func id(_ value: some Identifiable<String>) -> String { value.id }

    @ProjectionFunction(flatten: false)
    static func tag(_ value: some CustomStringConvertible) -> String? { ... }
}
```

旧的 `@Projection(through:flatten:)` **移除**，不保留、不废弃过渡。

## 方案

### 为什么不是闭包或函数引用

这是本提案存在的理由，实测结论记在这里，免得以后再走一遍：

把参数改成 `through: (Payload) -> Projected` 并在调用点写 `Target.id`，会同时撞上两个**互相独立**
的硬障碍。实测（用一个临时探针宏，跑完即删）：

1. **引用宿主自己的成员会循环。** `error: circular reference resolving attached macro`。宏参数
   要先过类型检查，而要检查 `Target.id` 就得先知道 `Target` 有哪些成员，可那正是这个宏在改的东西。
2. **泛型函数不能作为函数值传递。** `error: generic parameter 'some CustomStringConvertible'
   could not be inferred`。把变量分离开验证过：非泛型函数、定义在别的类型上 → 编译通过；只要函数
   是泛型的，哪怕定义在别处也失败。而投影函数的全部价值就在于它是泛型的——一个函数接住各种不同的
   payload 类型。闭包更走不通，Swift 的闭包不能有自己的泛型参数。

还有一条更根本的：**即使传得进去，宏也一无所获**。宏运行在类型检查之前，手上只有语法树；
`Target.id` 在它眼里是一个成员访问表达式，能取出来的仍然是字符串 `"id"`。强类型的收益全部落在
编译器那一侧，宏那一侧一个比特都没多。

标记宏绕开了全部三条：它全程只看语法，不需要类型检查，也不需要把函数当值传。

### 谁校验什么

`@ProjectionFunction` 自己校验它贴对了地方（必须是 `static func`，必须有返回类型），因为它手里
就是那个函数声明，诊断能精确指过去。`@Projection` 只负责收集**合格的**标记函数，不合格的静默
跳过——重复诊断同一个错误没有意义，这条规矩上一批搬运时已经在 `@CaseTag` 上立过一次。

`@Projection` 找不到任何标记函数时报错，那是调用方真正的错误。

### 顺带变好的三件事

1. **多个投影只贴一个 `@Projection`**，不再叠 N 个 `@Projection(through:)`。
2. **`flatten:` 挪到每个函数上**，各自独立控制。原来它是宏的参数，多个投影叠加时每个都要重复写。
3. **函数改名，属性名自动跟着改**，不会再出现字符串与函数对不上的中间状态。

### 投影规则不变

匹配仍然按关联值个数，绑定名、实参标签、可选解包、`default` 的穷尽判定全部沿用上一份提案的结论。
这次改的只是「宏怎么知道该调用哪个函数」。

### 源码兼容性

`@Projection(through:flatten:)` 被移除，所有调用点都要改写。**影响面是零**：这五个宏尚未提交，
也没有任何调用方。这是唯一一个可以无痛换 API 的时间窗口；留着两套做同一件事的 API，以后就永远
是两套。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-20 | Created as Draft | 用户提出把 `through:` 改成强类型形态；实测闭包与函数引用都不可行，标记宏是能达成同一诉求的可行路径 |
| 2026-09-20 | 移除旧的 `@Projection(through:)` 而不是废弃 | 这批宏从未提交过，替换成本为零；两套 API 做同一件事是长期负担 |
| 2026-09-20 | `flatten:` 从宏参数挪到标记上 | 多个投影叠加时，原来的形态要求每个都重复写一遍 |
| 2026-09-20 | 校验分工：标记宏报错，`@Projection` 静默跳过 | 两个宏都报同一个错会让调用方看到重复诊断，与 `@CaseTag` 那次同因 |
| 2026-09-20 | 状态 Draft → Implemented | 全部调用点迁移完毕，行为测试 28 项、展开快照 29 项、全套 585 项通过，构建零警告 |
