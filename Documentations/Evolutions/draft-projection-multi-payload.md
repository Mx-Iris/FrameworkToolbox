# Draft - 让 @Projection 支持多关联值的 case，并修掉展开出的 unreachable default

- **状态**: Implemented
- **创建日期**: 2026-09-20
- **最后更新**: 2026-09-20

## 摘要

`@Projection` 目前只投影**恰好一个**关联值的 case，其余一律落到 `default: nil`。这是上游
lexic 的设计取舍，不是技术限制——宏本来就拿到了投影函数的完整语法，参数个数、标签、类型全都
看得见。本提案把它放开到任意参数个数（含零个）。

同批次修一个搬进来时没发现的缺陷：展开产物**无条件**生成 `default: nil`，所以当一个枚举的所有
case 都能被投影时，编译器会报 `warning: default will never be executed`，而那一行在调用方的
源码里根本不存在。上游的测试数据每一个都恰好留了一个无 payload 的 case，把这个问题盖住了。

对外 API 一个字都不改，`@Projection(through:flatten:)` 的签名不动。

## 方案

### 参数个数从投影函数读

宏读 `static func` 的参数个数 N，然后只投影关联值个数同样是 N 的 case，其余落到 `default`。
N 可以是零：一个 `static func placeholder() -> String` 会匹配所有无关联值的 case。

绑定名：单参数时仍叫 `payload`（与现在一致，现有快照不变），多参数时 `payload1`、`payload2`……
实参标签取自**投影函数**的参数标签，`_` 则不带标签：

```swift
@Projection(through: "pair") enum Event {
    case click(Int, Int)
    case scroll(Int)
    case idle

    static func pair(_ x: Int, _ y: Int) -> String { "\(x),\(y)" }
}

// 展开:
// case .click(let payload1, let payload2): Self.pair(payload1, payload2)
// case .scroll: 参数个数对不上，跳过
// default: nil
```

每个参数独立判断可选性，可选的用 `let payloadN?` 解包——与现在的单参数行为一致。

### default 只在真的需要时生成

switch **穷尽**时不再生成 `default: nil`。判定穷尽的条件有两条，第二条是容易漏的那条：

1. 每个 case 的关联值个数都等于 N；
2. 且没有任何一个 case 用到了可选解包模式。

第二条的原因：`case .first(let payload?)` **不是**穷尽的——`.first(nil)` 不匹配它。少了这一条，
一个全是可选 payload 的枚举会生成一个编译不过的 switch，比原来的警告严重得多。

**不做**的一件事：穷尽时把属性类型从 `String?` 收窄成 `String`。看起来顺理成章，但那会让属性
类型随着无关的 case 增减而变——加一个新 case 就让所有调用点要改——是个脆弱的设计。属性类型继续
永远是可选的（`flatten:` 的行为不变）。

### 测试

- 行为测试：两参数、三参数、零参数、可选与非可选混合、参数个数对不上的 case 落到 nil。
- 展开快照：多参数的解构模式、带标签的实参、穷尽时不生成 default。
- 回归守卫：一个所有 case 都可投影的枚举放进 `SwiftStdlibToolboxClient`，它在修复前会让编译器
  发出 `default will never be executed`；那个警告是这次要消灭的东西，把它留在一个真实编译的
  target 里，比只在快照里比对文本更难失效。

### 源码兼容性

**展开结果变化，按源码破坏对待。** 原本落到 `nil` 的多关联值 case，现在会被投影——读到的值从
`nil` 变成一个实际值。影响面是零：这五个宏本次才引入，尚未提交、也没有任何调用方。这是唯一一个
可以无痛改的时间窗口。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-20 | Created as Draft | 用户提出把 `through:` 改成强类型闭包；实测那条路不通（循环引用 + 泛型函数不能当函数值），但其中「支持多参数」这一诉求与参数形态无关，可以单独实现 |
| 2026-09-20 | 穷尽判定必须同时看参数个数与可选解包 | `case .first(let payload?)` 不穷尽，漏掉这条会生成编译不过的 switch |
| 2026-09-20 | 不做属性类型收窄 | 类型会随无关的 case 增减而变，调用点跟着遭殃 |
| 2026-09-20 | 单参数的绑定名保持 `payload` | 现有展开快照不必变动，diff 只覆盖真正新增的行为 |
| 2026-09-20 | 状态 Draft → Implemented | 11 项新测试（6 项行为 + 5 项展开快照）通过，全套 581 项通过，构建零警告；`FullyCoveredProjection` 作为回归守卫留在真实编译的 client target 里 |
