# Draft - 把 lexic 的五个枚举宏并入 SwiftStdlibToolbox

- **状态**: Implemented
- **创建日期**: 2026-09-20
- **最后更新**: 2026-09-20
- **配套文档**: [五个枚举宏 —— 用法契约与实现决策](../EnumMacros.md)

## 摘要

[ordo-one/lexic](https://github.com/ordo-one/lexic)（Apache-2.0）提供五个围绕枚举的 Swift 宏。
本提案把它们搬进本仓库，按本仓库的命名规则与测试惯例重写。上游名称是数学与类型论术语，其中三个
改名（见下），两个保留：

| 本仓库 | 上游 | 做什么 |
|--------|------|--------|
| `@Bijection` | 同名 | 从「枚举 → 值」的 switch 反推出 `init?`。名字取自「双射」——正因为这张表是一一对应的，逆映射才存在 |
| `@CaseTag` | `@Discriminated` | 在带 payload 的枚举旁边生成一个只留 case 名的平行枚举 `原名Tag`，并给原枚举加 `var tag` |
| `@MirroredCases` | `@Discriminant` | 同一件事的反向排布：标签枚举写在外层当主角，payload 枚举嵌在它里面 |
| `@DefaultedCases` | `@ambient` | 给「参数全部可选或全部带默认值」的 case 生成零参数静态属性，恢复 `.recurring` 这样的点语法 |
| `@Projection` | 同名 | 把各 case 的单参数 payload 经一个 `static func` 投影成同一个类型。名字取自数学与 SQL 的「投影」——从复合结构里取出一个分量 |

这五个宏与 `SwiftStdlibToolbox` 现有的 `@AssociatedValue` / `@CaseCheckable` 是同一类东西——零
运行时、纯编译期、只吃标准库——但覆盖的是后两者没碰的方向：反向构造、判别标签、零参数构造、跨
case 投影。不新增 target，不新增 library product，不改变包拓扑。`Assert` 与 `FileContent`
两个 target 不搬。

## 方案

### 落点

| 上游 | 本仓库 |
|------|--------|
| `Sources/{Bijection,Discriminated,Ambient,Projection}/`（宏声明） | `Sources/SwiftStdlibToolbox/Macros/` |
| `Sources/LexicMacros/`（宏实现） | `Sources/SwiftStdlibToolboxMacros/`，注册进现有的 `MainPlugin.swift` |
| `Sources/Lexic/`（swift-syntax 工具库） | `Sources/MacroToolbox/` |

选这个落点是因为三件事都已经有主：五个宏全是 stdlib 层的枚举宏，和 `@AssociatedValue` /
`@CaseCheckable` 同层同类；`MacroToolbox` 的既定职责就是「宏实现的共用工具」（现在只住着
`LockMacroProtocol` / `LockPropertyParser`）；而 `SwiftStdlibToolboxMacros` 已经依赖
`MacroToolbox`，不新增任何依赖边，`PackageTopologyGuardTests` 不受影响。

`SwiftStdlibToolbox` 被 `FoundationToolbox` re-export，所以 `import FoundationToolbox` 同样
能拿到这五个宏——这是既有 re-export 链的自然结果，不需要新增导出。

### 搬进 MacroToolbox 的是什么

上游 `Lexic` 的主体是一套**把宏参数从 `AttributeSyntax` 解码成 Swift 值**的机制
（`ExpressionDecodable` / `ExpressionListDecoder` / `ExpressionListDecodingError`），加一组
syntax 扩展（`TypeSyntax.isOptional`、`AttributeListSyntax` 的属性镜像、
`MacroExpansionContext` 的诊断下标）。本仓库现有的宏是手写
`.as(MemberAccessExprSyntax.self)?.declName.baseName.text ?? ""` 这类链式解包，一路静默吞掉
错误；这套机制把它变成声明式的、带诊断的解码。整块搬（含 `Int` / `Bool` / `Array` / `Set` 等
一行式 conformance），因为机制的价值正在于下一个宏能直接复用；**但不去改写现有宏的解析代码**，
那是另一件事，不在本次范围内。

### 命名：改三个，连带改展开产物

上游用的是学术词汇，其中三个对调用方不可读，改掉：

- `@ambient` → **`@DefaultedCases`**。"ambient" 指「不用显式传、在上下文里自然可得」，完全猜不出来。
- `@Discriminated` → **`@CaseTag`**，`@Discriminant` → **`@MirroredCases`**。这对原名长得几乎
  一样，贴的位置和产出却相反（一个贴内层生成旁边的标签枚举，一个贴外层把内层 case 抄上来），
  是真会用错的一组。两个新名字不再长得像，是有意的——它们本来就不是同一个动作；配对关系由
  `@CaseTag(by:)` 的参数在调用点显式写明，不靠名字暗示。

`@Bijection` 与 `@Projection` 保留：解释一次就懂，且名字精确描述了前提（映射可逆）与操作（取分量）。

**连带改的是展开产物，这一项影响比宏名大**：上游 `@Discriminated` 生成枚举 `原名Type` 与属性
`var type`，调用点写 `value.type`。`Type` 在 Swift 里过于泛，`value.type` 读起来像在问「它是
什么类型」，而它问的其实是「它是哪个分支」。既然宏已叫 `@CaseTag`，改为生成 `原名Tag` 与
`var tag`，调用点写 `value.tag`。

**参数名与默认值一字不改**：`label:` / `where:` / `by:` / `backing:` / `through:` /
`flatten:`，语义与上游完全一致。

### 必须改的（不是风格偏好，是编译不过或违反硬规则）

1. **去掉 `public import` 的访问修饰符**。上游用 SE-0409 的访问级 import，本包是
   `swiftLanguageModes: [.v5]`，不认。
2. **去掉 `@frozen`**。`MacroToolbox` 不是 resilient 模块，这个属性在这里没有意义。
3. **全部标识符改成不缩写的完整名**：`decl` → `declaration`、`config` → `configuration`、
   `$0`/`$1` → 具名参数、泛型参数 `T` → 描述性名。其中一处需要特别处理：上游把
   `ExpressionListDecodable` 的 associatedtype 叫 `CodingKey`，与标准库的 `CodingKey` 协议
   同名会造成遮蔽，改叫 `ArgumentKey`。
4. **许可证归档**：新增 `LICENSES/lexic-LICENSE`（Apache-2.0 原文），每个搬来的文件头部按现有
   `Dynamic` / `SwiftCF` 的做法注明出处。

### 刻意保持不变的

**展开结果的语义与上游逐字一致**，包括三处看上去像是可以「顺手改掉」的地方：

- `@Bijection` 生成的 `init?` 参数写成 `borrowing`（`init` 默认 `__owned`，对 `String` 这类
  带分配的类型有意义）。
- 只在指定了 `where:` 泛型约束时才发 `copy`。无条件发会撞上编译器崩溃
  [swiftlang/swift#86208](https://github.com/swiftlang/swift/issues/86208)，而对元组类型发又会
  以另一种方式崩——两头都是坑，上游选的是中间那条窄路。
- 生成的成员**镜像宿主声明的修饰符与属性**（`@available` / `@inlinable` / `@usableFromInline` /
  `nonisolated`），而不是像现有的 `@AssociatedValue` 那样要求调用方传一个 `AccessLevel`。

另外保留上游对 `Optional<T>` 长写法的警告（展开时提醒改用 `?`，因为长写法不会被优化）。

### 不搬的

- `Assert`——一个靠 `-D ASSERT` 开关的断言宏，与 Swift 自带 `assert` 重复，且要求消费者改构建设置。
- `FileContent`——给代码生成器拼源码文本用的缩进构建器，与本库定位无关。
- 上游对 `ordo-one/dollup` 的依赖（只有它的 CI 用到）。

### 版本与平台

swift-syntax 对得上：上游要 `603+`，本包锁的正是 `603.0.2`（范围 `600..<604`）。上游
`Package.swift` 写着 macOS 15 / iOS 18，但五个宏**没有一行运行时代码**，展开产物只用到
`borrowing` 这类纯编译期特性，本包的 macOS 10.15 底线扛得住——这一条会在实现时用真实构建验证，
不靠推断。展开产物也不指名任何模块（全是标准库与调用方自己写的类型），不触发 CLAUDE.md 里
「宏不得展开出调用方没 import 的模块」那条。

### 测试与文档

- `Tests/SwiftStdlibToolboxMacroTests/` 用 swift-macro-testing 加五组展开断言，场景照搬上游测试
  覆盖的分支（`@Bijection` 的 getter/accessor 两种写法、`@CaseTag` 的三种 backing 与嵌套、
  `@MirroredCases` 的单个/多个候选、`@DefaultedCases` 的跳过规则、`@Projection` 的 flatten 与
  可选 payload）。
- `Sources/SwiftStdlibToolboxClient/` 加编译期使用点——上游那些 `*Tests` target 本质上就是
  「展开出来的代码能不能编译」的守卫，这个价值要保住。
- `Tests/SwiftStdlibToolboxTests/` 加行为测试：`@Bijection` 生成的 `init?` 真能往返，
  `@Projection` 真能取到值。
- 新增 `Documentations/EnumMacros.md`（面向调用者的使用指南，含上游名称到本仓库名称的对照表，
  这样上游文档与 issue 仍然可读），更新 `CLAUDE.md` 的 `SwiftStdlibToolbox` 一行与
  Key Patterns，更新 `Documentations/README.md` 索引。

### 源码兼容性

纯新增。不改任何既有声明、既有宏的展开结果或 re-export 链，对现有调用方零影响。唯一的新符号是
五个宏名与 `MacroToolbox` 内部的解码机制，而 `MacroToolbox` 不是 library product，对外不可见。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-20 | Created as Draft | 用户要求把 `ordo-one/lexic` 搬进本仓库 |
| 2026-09-20 | 只搬五个枚举宏，不搬 `Assert` 与 `FileContent` | `Assert` 与 Swift 自带 `assert` 重复且要求消费者改构建设置；`FileContent` 是代码生成器的工具，与本库定位无关 |
| 2026-09-20 | 并入 `SwiftStdlibToolbox` / `MacroToolbox`，不新开 target | 五个宏与现有枚举宏同层同类，`MacroToolbox` 本就是宏实现共用工具的位置；不新增依赖边，包拓扑与 `PackageTopologyGuardTests` 不受影响 |
| 2026-09-20 | 按本仓库规则重写标识符命名 | 「任何缩写都不允许」是硬规则；代价是日后跟上游对齐要手工做，接受 |
| 2026-09-20 | 三个宏改名：`@ambient` → `@DefaultedCases`、`@Discriminated` → `@CaseTag`、`@Discriminant` → `@MirroredCases` | 用户反馈上游的数学/类型论术语不可读。`ambient` 完全猜不出；`Discriminated` 与 `Discriminant` 长得几乎一样却干相反的事，是会用错的一组。`@Bijection` 与 `@Projection` 保留——解释一次就懂且名字精确 |
| 2026-09-20 | 连带把展开产物从 `原名Type` / `var type` 改为 `原名Tag` / `var tag` | 宏已叫 `@CaseTag`，产物得自洽；且 `Type` 在 Swift 里过泛，`value.type` 像在问「它是什么类型」而非「它是哪个分支」 |
| 2026-09-20 | 外层宏最终定名 `@MirroredCases`，弃用过渡名 `@CaseTagHost` | `Host` 的方向是反的——外层枚举不是「承载标签的宿主」，它自己就是标签枚举，被承载的是内层那个带 payload 的枚举。`MirroredCases` 说的是实际机制：我的 case 是内层枚举的镜像 |
| 2026-09-20 | 展开结果的其余语义逐字保持上游 | `borrowing` / 条件性 `copy` / 属性镜像三处都是上游踩过坑换来的，改动等于重新踩 |
| 2026-09-20 | 状态 Draft → Accepted | 用户批准，实现开始 |
| 2026-09-20 | 不搬上游的 `TypeSyntax.contains(symbol:)` 与两个泛型语法辅助 | 实地确认五个宏一个都没用到，搬进来就是死代码。解码机制本身整块搬，因为它的价值在于可复用 |
| 2026-09-20 | `@CaseTag` 贴在非枚举上时只报一次错，由 peer 角色独家负责 | peer 与 member 两个角色每次都会运行，上游两边各报一次，同一个错误出现两遍 |
| 2026-09-20 | `MetatypeExpression` 遇到非 `X.self` 表达式时改为抛诊断，不再 `fatalError` | 上游那条路径会让宏插件进程崩掉，调用方只看到一个无从下手的错误 |
| 2026-09-20 | `Optional<T>` 警告措辞改为「宏不认这种拼写」，辅助属性去掉 `is` 前缀（`unsugaredOptionalDiagnostic`） | 上游说「不会被优化」，与实情不符——宏匹配的是拼写；返回 `String?` 的属性不该以 `is` 开头 |
| 2026-09-20 | 平台假设已证实 | macOS 10.15 底线下五个宏与其展开产物全部构建通过，提案里那条「待实测」成立，无需抬高平台底线 |
| 2026-09-20 | 不新增项目术语表 | 本次唯一的新术语 `tag` 已在配套文档里当场解释；项目尚无 `Glossary.md`，为一个词新建一份不值得 |
| 2026-09-20 | 在 `FoundationToolboxSoleImportClient` 里加了一条 re-export + 无外部 import 的守卫，并实测它会红 | 把 `@_exported import SwiftStdlibToolbox` 降级成普通 `import` 后，该文件五个宏全部 `unknown attribute`（18 条错误）——没人看着它红过的守卫不算守卫 |
| 2026-09-20 | 状态 Accepted → Implemented | 代码、测试、文档同批次落地：42 项新测试（22 项行为 + 20 项展开快照）通过，全套 570 项测试通过 |
