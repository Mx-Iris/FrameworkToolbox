# Draft - `@FlagSet`：由嵌套的 `Flag` 枚举生成 OptionSet

- **状态**: In Progress
- **创建日期**: 2026-11-05
- **最后更新**: 2026-11-05
- **实现分支**: `feature/flag-set-macro`

## 摘要

RuntimeViewer 的 `RuntimeObject.Properties` 手写了一套 OptionSet 样板：嵌套枚举 `Flag` 的原始值是
各个标志所占位的位置，结构体里再逐个写 `rawValue`、`init(rawValue:)`、`init(_:)` 和与 case 同名的
`static let`。每加一个标志要改两处，漏写 static、或 static 取错了 case，都不会报错。`@FlagSet` 让枚举
成为唯一的定义处，其余由宏生成。新增一个宏，放在 `SwiftStdlibToolbox`，不改动任何已有宏的展开。

```swift
@FlagSet
public struct Properties: Codable, Hashable, Sendable {
    public enum Flag: Int, CaseIterable, Sendable {
        case isGeneric = 0
        /// Marks a runtime object that was produced by user-driven specialization …
        case isSpecialized = 1
    }
}
```

展开为（省略隔离与 `@inlinable` 等修饰）：

```swift
public let rawValue: Int
public init(rawValue: Int) { self.rawValue = rawValue }
public init(_ flag: Flag) { self.init(rawValue: 1 << flag.rawValue) }
public static let isGeneric = Self(.isGeneric)
/// Marks a runtime object that was produced by user-driven specialization …
public static let isSpecialized = Self(.isSpecialized)
// 调用方没有写 OptionSet 时另加：extension Properties: Swift.OptionSet {}
```

## 方案

以下都是未经询问即采用的假设，错了在批准前指出即可。

- **生成什么**：上面五样。`Codable`、`Hashable`、`Sendable` 仍由调用方自己写，与手写版一致
  （`Codable` 走 `RawRepresentable` 的默认实现，编码成 `rawValue`）。
- **找哪个枚举**：结构体体内直接声明的 `enum Flag`，名字固定；`rawValue` 的类型照抄 `Flag` 的原始类型。
- **随 case 转到 static 上的**：文档注释、`@available`，以及包着 case 的 `#if`。`Flag` 自己的
  `@available` 加到 `init(_:)` 与各个 static 上。
- **访问级别**：跟随结构体，只在 `public` / `package` 时写出；`init(_:)` 不超过 `Flag` 的访问级别。
  公开的 `init` 加 `@inlinable`，照本仓库枚举宏的惯例。
- **报错落在调用方源码上**：挂在非 struct 上；没有 `Flag`；`Flag` 没写原始类型（Fix-It 补 `: Int`）；
  某个 case 的位置为负或不小于原始类型的位宽。后者不报就是静默错误：`1 << 64` 与 `1 << -1` 都是 0，
  这个标志会变成空集，`contains` 永远为真。位宽按拼写判断：`Int8` … `UInt128` 各按其宽度，
  `Int` / `UInt` 按 64；别名等认不出的拼写不检查。
- **隔离**：照 `@Equatable` 的做法，让生成的遵循与成员在默认 MainActor 隔离的模块里也能从后台使用；
  具体加在哪几处，以 `DefaultMainActorIsolationClient` 的实测为准。
- **测试**：展开快照（含每条报错与 Fix-It）；行为测试（每个 static 的位、`Self(flag)` 与对应 static 相等、
  `Codable` 编出整数）；`SwiftStdlibToolboxClient` 与 `DefaultMainActorIsolationClient` 钉住公开用法与隔离；
  干净构建无警告。
- **实现时要实测的一点**：转到 static 上的文档注释在 Quick Help 与符号图里是否可见。不可见也不改方案
  ——文档仍写在 case 上——只在使用指南里写明。
- **文档**：宏声明上的 DocC 注释；`CLAUDE.md` 的 `SwiftStdlibToolbox` 一行与一条 Key Patterns；新建使用
  指南 `Documentations/FlagSet.md`，写契约与陷阱（持久化的位要显式写原始值并加测试钉住、越界移位、
  arm64_32 的 watchOS 上 `Int` 只有 32 位）。
- **不做**：自定义枚举名；与原始类型不同的存储类型；把集合拆回 `[Flag]` 或打印成标志名；枚举声明在
  结构体外面的写法。后者在别处还有两例——UIFoundation 的 `ScrollPocketEdges` 与 MachOSwiftSection 的
  `InvertibleProtocolSet`——要用这个宏，得把枚举挪进结构体、用 typealias 保留旧名；否则只能另做一个挂在
  枚举上的宏，它生成的类型名也无法与现有名字对上。
- **RuntimeViewer 换用**：另一次改动。RuntimeViewerCore 依赖 FrameworkToolbox `from: "0.9.0"`，要等这边
  发出包含本宏的版本。

## 落地步骤

每一步各自能构建、测试通过，单独提交。

- [x] 1. 宏的声明与实现：member 与 extension 两个角色，文档注释、`@available`、`#if` 随 case 转到 static 上，
  访问级别与 `@inlinable`；注册进插件；展开快照测试。
- [x] 2. 报错与 Fix-It：非 struct、缺 `Flag`、`Flag` 没写原始类型、位置越界；每条一个快照测试。
- [ ] 3. 行为测试与客户端钉住：运行时行为测试；`SwiftStdlibToolboxClient` 与 `DefaultMainActorIsolationClient`；
  隔离与文档注释可见性的实测；干净构建无警告。
- [ ] 4. 文档：`CLAUDE.md`、使用指南 `Documentations/FlagSet.md`、文档索引。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-05 | Created as Draft | RuntimeViewer 的 `RuntimeObject.Properties` 手写了「嵌套枚举 + 逐个 static」的 OptionSet 样板，两处定义对不上不会报错；要把它抽成宏 |
| 2026-11-05 | 枚举是唯一定义处，static 由宏生成，不反过来由 static 生成枚举 | 位是 wire format，只能有一处定义；枚举还要被调用方穷举 `switch`，它遵循的协议与它自己的文档只能写在调用方声明的枚举上 |
| 2026-11-05 | 不沿用标准库的 `@OptionSet<RawType>`，也不取这个名字 | 它在 Swift 5.9 发布前就被移出标准库（swiftlang/swift 的提交「Remove OptionSet macro from the standard library.」，2023-06），实现还留在工具链的 SwiftMacros 插件里，只有编译器自己的测试在声明和使用它；它要求枚举叫 `Options`、原始类型写两遍、不生成 `init(_:)`、不转文档与可用性。形状相近而契约不同，同名会误导 |
| 2026-11-05 | 宏名 `@FlagSet` | 与固定的枚举名 `Flag` 呼应，读作「由 `Flag` 组成的集合」 |
| 2026-11-05 | 枚举名固定为 `Flag`，不提供改名参数 | 有 `CodingKeys` 与原 `@OptionSet` 的先例；宏参数引用不了宿主自己的成员（`@Projection` 时实测为 circular reference），只能传字符串，而字符串正是那次去掉的东西。确有需要时再加标记宏 |
| 2026-11-05 | 不强制每个 case 显式写原始值 | 隐式值是枚举本身的语义，宏不知道这些位会不会被持久化；持久化的场景由使用指南要求显式值与钉住位值的测试（RuntimeViewer 已有这条测试） |
| 2026-11-05 | 保持 `static let`，不改成计算属性 | 与手写版一致；编译器对 static 存储属性免除可用性限制（`lib/Sema/TypeCheckAttr.cpp`：「Globals and statics are lazily initialized」），case 上的任何 `@available` 都能原样转过去 |
| 2026-11-05 | 补上落地步骤 | 精简提案原本没有分步；按方案拆成四步，每步各自能构建、测试通过 |
| 2026-11-05 | 用户批准，开始实现 | — |
| 2026-11-05 | 「没写原始类型」的报错另认两种写法：首个继承项是常见协议（`CaseIterable`、`Sendable` 等）时同样报缺，Fix-It 在最前面补 `Int, `；首个继承项是 `String`、`Double` 这类非整数原始类型时报在那个类型上 | 原始类型必须写在第一位，宏只看得到拼写；不认出这两种，错误会落在生成代码里（`'<<' cannot be applied…`、`does not conform to 'SetAlgebra'`），调用方看不懂 |
| 2026-11-05 | 读不通结构体（不是 struct、缺 `Flag`、缺原始类型）时 extension 角色也不加 `OptionSet` 遵循 | 报错由 member 角色负责；成员没生成还加遵循，只会在宏的报错后面堆一串「不遵循协议」的错误 |
| 2026-11-05 | 位置推不出的 case 不检查：跟在 `#if` 后面、且各分支走完位置不同的隐式值，以及跟在非整数字面量原始值后面的隐式值 | 宏不知道哪个分支生效，猜错会误报；漏查只是回到没有这条检查时的状态 |
| 2026-11-05 | 构建与测试经 workspace 用本地的预编译 swift-syntax 603.0.1（MxIris-DeveloperTool/swift-syntax-builder 的 `release/603.0.1`），不从源码编译 | 用户要求。workspace 与预编译包都放在仓库外 agent 自己的目录里；Xcode 解析时会改写仓库的 `Package.resolved`，每次都还原，不提交 |
