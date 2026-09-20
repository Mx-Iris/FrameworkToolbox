# 五个枚举宏 —— 用法契约与实现决策

`SwiftStdlibToolbox` 提供五个围绕枚举的宏，从 [ordo-one/lexic](https://github.com/ordo-one/lexic)
（Apache-2.0）搬入并按本仓库规则重写，搬运决策见提案
[把 lexic 的五个枚举宏并入 SwiftStdlibToolbox](Evolutions/draft-lexic-enum-macros.md)。

| 宏 | 贴在哪 | 生成什么 |
|----|--------|----------|
| `@Bijection` | 枚举里的计算属性 | 把 getter 里「枚举 → 值」的 switch 反过来，生成 `init?` |
| `@CaseTag` | 带 payload 的枚举 | 旁边生成只留分支名的 `原名Tag`，宿主里加 `var tag` |
| `@MirroredCases` | 外层的标签枚举 | 把内层 `@CaseTag(by:)` 枚举的分支名抄到自己身上 |
| `@DefaultedCases` | 枚举 | 给「参数全部可选或全部有默认值」的 case 生成零参数静态属性 |
| `@Projection` | 枚举 | 为每个被 `@ProjectionFunction` 标记的 `static func` 生成一个属性，把各分支的 payload 投影成同一个类型 |
| `@ProjectionFunction` | 枚举里的 `static func` | 什么也不生成，只是告诉 `@Projection` 「用我」；属性名就取这个函数的名字 |

上游名称与本仓库名称的对照（读上游文档或 issue 时需要）：

| 上游 | 本仓库 | 为什么改 |
|------|--------|----------|
| `@Discriminated` | `@CaseTag` | 原名是类型论术语 "discriminated union"，且与下一行几乎同形却做相反的事 |
| `@Discriminant` | `@MirroredCases` | 同上；新名字说的是它的实际动作——把嵌套枚举的分支镜像过来 |
| `@ambient` | `@DefaultedCases` | "ambient" 指「不用显式传、在上下文里自然可得」，猜不出来 |
| `XxxType` / `var type` | `XxxTag` / `var tag` | `Type` 在 Swift 里过于泛，`value.type` 读起来像在问「它是什么类型」 |

| `@Projection(through: "id")` | `@Projection` + `@ProjectionFunction` | 上游用字符串指向函数，函数改名时字符串不会跟着改；改成贴在函数上的标记后没有字符串了 |

`@Bijection` 与 `@Projection` 沿用上游名称。

## 一条统摄性的前提：宏看的是拼写，不是类型

宏在类型检查之前运行，手上只有语法树，**没有类型解析能力**。下面多条陷阱都是这一条的推论：

- `Optional<Int>` 与 `Int?` 在宏眼里是两个不同的东西。`@DefaultedCases` 和 `@Projection`
  只认带 `?` 的写法，遇到长写法会发警告并跳过该 case，而不是默默当成非可选。
- `@CaseTag(by: TooltipKind.self)` 的校验只比较**名字**，比较的是 `@MirroredCases` 所在枚举的
  声明名与 `by:` 里最后一段标识符是否相同。`by: Wrong.self` 会报错，但一个恰好同名、实际指向
  别处的类型不会被识破。
- `@Projection` 能看到被 `@ProjectionFunction` 标记的函数的完整签名（名字、参数个数、参数标签
  全是语法），但**看不出这些参数类型能不能接住每个 case 的 payload**——那要等编译器。所以宏按
  关联值的**个数**匹配，类型对不上的报错会落在展开之后。

## `@Bijection`

**getter 必须是一个 switch，且每个 case 体是单个表达式、省略 `return`。** 这不是风格要求——
宏要把这张表反过来读，多一条语句它就不知道哪个是「值」。写成 `{ switch ... }` 或
`{ get { switch ... } }` 都可以。

**`where:` 收的是协议名字符串，不是类型。** `@Bijection(where: "StringProtocol")` 生成
`init?(_ $value: borrowing some StringProtocol)`，于是传 `Substring` 不必先转成 `String`。

**生成的 `init?` 有两处所有权标注是刻意的，改动前先读这段**：

- 参数是 `borrowing`。`init` 的参数默认 `__owned`，对 `String` 这类带堆分配的类型意味着一次
  多余的 retain。
- `switch` 的操作数只在指定了 `where:` 时才写成 `copy $value`。**两头都是坑**：无条件发
  `copy`，在值类型是元组时会让编译器崩溃；泛型情况下不发，又会以另一种方式崩。中间这条窄路是
  上游踩出来的，见 [swiftlang/swift#86208](https://github.com/swiftlang/swift/issues/86208)。
  仓库里 `Tests/SwiftStdlibToolboxTests/EnumMacroTests.swift` 的 `TrafficLight` 同时覆盖元组
  与泛型两条路径，正是为了让这个崩溃在升级工具链时能被撞出来。

**宏不校验你给的映射是不是真的一一对应。** 两个 case 映到同一个值时，生成的 switch 里会出现两个
相同的模式，运行时先匹配的那个胜出——反向映射会静默丢掉后一个 case。

生成的 `init?` 镜像属性自身的修饰符，并带上 `@available` / `@backDeployed` / `@inlinable` /
`@inline` / `@usableFromInline`（如果属性上有）。

## `@CaseTag` 与 `@MirroredCases`

两个宏是同一件事的两种排布。标签枚举当配角、生成在旁边，用 `@CaseTag`；标签枚举当主角、payload
枚举嵌在它里面，用 `@MirroredCases` + 内层的 `@CaseTag(by:)`。后者的用途是标签必须是一个顶层
单名字的场合，例如给别的语言生成绑定。

**生成的 `原名Tag` 不继承宿主的任何 conformance。** 宿主写着 `: Equatable`、`: CaseIterable`
或自定义协议，标签枚举都不会跟着有——只有 `backing:` 给的 raw value 类型会写进去。由于标签枚举
没有 payload，`Equatable` / `Hashable` 由编译器自动合成，但 `CaseIterable` 之类需要自己补一条
extension。

**`indirect` 不会被带到生成物上。** 它描述的是宿主自己的存储，对标签枚举和 `tag` 属性都没有意义。

`@MirroredCases` 的两条规则：**必须恰好有一个**被 `@CaseTag` 标注的嵌套枚举（零个或多个都报错），
没标注的嵌套类型被忽略；内层的 `@CaseTag(by:)` 必须指回外层，否则报错。

宿主是 `public` 或 `package` 时，生成的 `tag` 属性会带上 `@inlinable`。

## `@DefaultedCases`

**最容易踩的一条：生成的静态属性与 case 同名，没有期待类型时引用它是有歧义的。**

```swift
@DefaultedCases enum ScheduledTask {
    case recurring(interval: Int = 60, tag: String? = nil)
}

let task: ScheduledTask = .recurring   // 可以：期待类型定了是哪个
_ = ScheduledTask.recurring            // 报错：ambiguous use of 'recurring'
```

后一行的两个候选是生成的 `static var recurring: Self` 和 case 本身被当作未应用的函数值
`(Int, String?) -> ScheduledTask`。这个宏的用途本来就是恢复 `.recurring` 这种点语法，而点语法
天然带着期待类型，所以正常用法不受影响。

跳过规则：没有关联值的 case（本来就能写 `.quick`）跳过；含有既非可选、又没有默认值的参数的 case
跳过——没有东西可以拿来填它。参数有默认值就用默认值，只是可选就填 `nil`。

## `@Projection`

`@Projection` 贴在枚举上，`@ProjectionFunction` 贴在要用的 `static func` 上，属性名取这个函数的
名字。**标记几个函数就生成几个属性**，`@Projection` 本身只贴一次。没有被标记的静态函数会被完全
忽略。

`@ProjectionFunction` 自己负责校验它贴对了地方（必须是 `static`、必须有返回类型），因为它手里就是
那个函数声明，诊断能精确指到 token 上；`@Projection` 遇到不合格的标记函数静默跳过，不重复报同一个
错。整个枚举一个标记函数都没有时，`@Projection` 会报错。

**匹配规则看的是关联值的个数**：宏读投影函数有几个参数，只投影关联值个数相同的 case，其余落到
`default: nil`。零个也算——一个 `static func placeholder() -> String` 会匹配所有不带关联值的
case。多个关联值时绑定名是 `payload1`、`payload2`……，实参标签取自**投影函数**的参数标签（`_`
则不带标签），因为 case 和函数各自命名自己的值，两边不必一致。

payload 是可选时，宏在模式里用 `let payload?` 解包，所以投影函数不必对可选性做泛型。

**`default: nil` 只在 switch 真的不穷尽时才生成**，否则编译器会对着调用方源码里不存在的那一行报
`default will never be executed`。判定穷尽有两个条件，第二个容易漏：每个 case 的关联值个数都对得
上，**且**没有任何一个 case 用到了可选解包——`case .first(let payload?)` 并不匹配 `.first(nil)`。
漏掉第二条会生成一个编译不过的 switch，比原来的警告严重得多。

即使 switch 穷尽，**属性类型仍然是可选的**。这是刻意的：让类型随着无关的 case 增减而变，意味着
加一个新 case 就要改所有调用点。

`flatten` 默认 `true`，写在**标记上**（`@ProjectionFunction(flatten: false)`）而不是
`@Projection` 上，所以同一个枚举里每个投影可以各管各的：投影函数自己返回可选时，属性类型默认不会
变成 `String??`；需要区分「没有匹配到 case」和「匹配到了但投影出 nil」时传 `flatten: false`。

### 为什么不是闭包或函数引用

这是最容易被重新提起的一个想法：既然要指向一个函数，为什么不直接把函数传进去，让编译器做类型检查？
实测过，同时撞上两个**互相独立**的硬障碍：

1. **引用宿主自己的成员会循环**——`circular reference resolving attached macro`。宏参数要先过类型
   检查，而检查 `Target.id` 得先知道 `Target` 有哪些成员，那正是这个宏在改的东西。
2. **泛型函数不能作为函数值传递**——`generic parameter 'some CustomStringConvertible' could not be
   inferred`。把变量分离开验证过：非泛型函数、定义在别的类型上，编译通过；只要函数是泛型的，哪怕
   定义在别处也失败。而投影函数的全部价值就在于它是泛型的。闭包更不行，Swift 的闭包不能有自己的
   泛型参数。

还有一条更根本的：**即使传得进去，宏也一无所获**。宏跑在类型检查之前，手上只有语法树，`Target.id`
在它眼里就是个成员访问表达式，取出来的仍然是名字。强类型的收益全落在编译器那一侧。

标记宏绕开了全部三条：全程只看语法。

## 实现决策

**宏参数走 `MacroToolbox` 的解码机制，不再手写链式解包。** 每个宏的 `Configuration` 声明一个
`ArgumentKey` 枚举（raw value 就是参数标签），再从 `ExpressionListDecoder` 里取值。仓库里既有的
宏是手写 `.as(MemberAccessExprSyntax.self)?.declName.baseName.text ?? ""` 这类链，写错的参数会被
静默吞掉；这套机制会指着出错的那个参数报诊断。既有宏没有跟着改写，那是另一件事。

**与上游有三处刻意的偏离**，都不影响展开结果：

1. `@CaseTag` 贴在非枚举上时只报一次错。它有 peer 与 member 两个角色，两个角色每次都会运行，
   上游两边各报一次，同一个错误出现两遍；现在由 peer 角色独家负责这条消息。
2. 上游 `MetatypeExpression` 在遇到不是 `X.self` 的成员表达式时 `fatalError`，那会让宏插件进程
   直接崩掉、给调用方一个无从下手的错误。这里改成抛出正常的诊断。
3. `Optional<T>` 的警告措辞改了：上游说「不会被优化」，实际情况是宏根本不认这种拼写。

**没有搬上游的 `TypeSyntax.contains(symbol:)` 那套类型遍历工具**——五个宏一个都没用到，搬进来
就是死代码。

**展开产物不指名标准库以外的任何模块**，所以调用方不 `import Foundation` 也能用（这是本仓库对宏的
硬要求，见 `CLAUDE.md` 里那条「宏不得展开出调用方没 import 的模块」）。
