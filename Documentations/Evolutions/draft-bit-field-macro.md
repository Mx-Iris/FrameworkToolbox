# Draft - `@BitField`：按位的范围生成 flag word 的访问器

- **状态**: In Progress
- **创建日期**: 2026-11-05
- **最后更新**: 2026-11-05
- **实现分支**: `feature/bit-field-macro`
- **配套文档**: [使用指南 `BitField.md`](../BitField.md)

## 摘要

很多 flag word 在一个整数里同时装着单个的标志位和占好几位的字段（kind、计数、版本号）。读一个字段要先移位、再掩码、再转成目标类型，三步里漏一步编译器不会报。`@FlagSet` 只管「每个选项占一位、可以自由组合」的 OptionSet，装不下多位字段。

MachOSwiftSection 的 ABI 层照着 Swift 运行时的 C++ 头文件（`swift/ABI/MetadataValues.h`）手写了 24 个 flag word 类型，其中 17 个是位和多位字段混排的。这 17 个的写法有四种，三个访问器把位读错了：

- `ExistentialTypeFlags.classConstraint` 只掩码、不移位，读到 `Any` 这类不限定 class 的 existential 就崩（仓库里的测试支撑代码专门注明要绕开它）。
- `ProtocolDescriptorFlags.classConstraint` 同样漏了移位，那一位是 1 时就崩。
- `FunctionTypeFlags.convention` 既不掩码也不移位，把整个 flag word 直接转成 `UInt8`：不超过 255 时读到的是参数个数那几位，超过 255 就崩。

C++ 那边每个访问器只写一行：`FLAGSET_DEFINE_FLAG_ACCESSORS(BIT, GETTER, SETTER)` 读单个位，`FLAGSET_DEFINE_FIELD_ACCESSORS(BIT, WIDTH, TYPE, GETTER, SETTER)` 读一段位（`swift/Basic/FlagSet.h`，`MetadataValues.h` 里用了 51 次）。`@BitField` 是它在 Swift 里的对应物：贴在属性上，只写位的范围，取值、移位、掩码和类型转换都由宏和编译器生成。

新增一个宏，放在 `SwiftStdlibToolbox`，与 `@FlagSet` 并列，不改动任何已有宏的展开。

```swift
public struct ProtocolContextDescriptorFlags: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    @BitField(bits: 1)
    public var isResilient: Bool

    /// The special protocol this descriptor stands for, or `nil` for a value
    /// this reader does not know.
    @BitField(bits: 2..<8)
    public var specialProtocolKind: SpecialProtocolKind?
}

public struct ContextDescriptorFlags: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0..<5, default: ContextDescriptorKind.unknown)
    public var kind: ContextDescriptorKind

    @BitField(bits: 8..<16)
    public var version: UInt8
}

public struct FunctionTypeFlags<IntType: FixedWidthInteger & Sendable>: RawRepresentable, Sendable {
    public let rawValue: IntType

    public init(rawValue: IntType) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0..<16)
    public var numberOfParameters: IntType
}
```

`specialProtocolKind` 展开为（`#sourceLocation` 从略，辅助函数的名字实现时再定）：

```swift
public var specialProtocolKind: SpecialProtocolKind? {
    get {
        _BitFieldAccess.value(of: rawValue, bits: 2..<8, as: SpecialProtocolKind?.self)
    }
}
```

## 方案

以下都是未经询问就采用的假设，错了在批准前指出即可。

**写法**

- `@BitField` 贴在 `var` 上。属性必须写类型、不带初始值；宿主要有一个叫 `rawValue` 的整数存储（任意 `FixedWidthInteger`，`let` 或 `var` 都行，泛型参数也行）。
- `bits:` 收单个位置（`bits: 5`）或半开区间（`bits: 2..<8`），一律写整数字面量。照 C++ 的表格翻写时，起始位加宽度就是区间：`SpecialProtocolKind = 2` 与 `SpecialProtocolKind_width = 6` 写成 `bits: 2..<8`。
- 宏只生成 `get`。文档注释、`@available`、访问级别都是调用方自己写在属性上的，原样留在那里——这一点和 `@FlagSet` 不同，那边要把 case 上的注释搬到生成的 static 上，这里没有东西要搬。

**转换按属性的类型决定，交给编译器选**

宏只看得到拼写，认不出 `typealias RawValue = UInt32`、泛型参数 `IntType` 背后是整数。所以宏不去分辨属性是什么类型：生成的 getter 把属性的类型原样传给一组带下划线、不进文档的公开函数重载，由重载决议选出转换。这是 `CLAUDE.md` 里「宏看不到的，交给编译器」那条的做法，`_EquatableMemberCheck` 也是这样。

| 属性的类型 | 读出来的值 |
|---|---|
| `Bool` | 区间里有没有一位是 1 |
| 整数类型（含 typealias 与泛型参数） | 区间里的位移到最低位，按 `init(truncatingIfNeeded:)` 转换 |
| 遵循 `OptionSet`、raw value 是整数的类型 | 用这些位构造集合 |
| `T?`，`T` 是 raw value 为整数的 `RawRepresentable` | 认得的值得到对应的 case，认不得的得到 `nil` |
| `T` 并写了 `default:` | 认不得时取 `default:` 给的值 |
| `T`（`RawRepresentable`）没写 `default:` | 编译错误，消息里写出上面两种改法 |

- **认不得的值不崩溃。** 这类位多半来自外部输入——二进制文件、另一个进程——编译器将来加的新 kind 也会落到这里。最后一行靠一个 `@available(*, unavailable, message:)` 的重载报错，再用 `#sourceLocation` 把错误指回属性那一行（`@Projection` 已经这样做）。
- **转成 raw value 用精确转换，不截断。** 先 `RawValue(exactly:)` 再 `init(rawValue:)`：一个 16 位的字段装进 raw value 为 `UInt8` 的枚举时，`0x0101` 不会被截成 `0x01`、误读成一个合法的 case。
- **`default:` 要写全名。** 标签照 `Dictionary` 的 `subscript(_:default:)`。宏参数在展开之前按宏的声明做类型检查，而声明里没有属性的类型可供推断，所以写 `default: ContextDescriptorKind.unknown`；写 `.unknown` 编译不过。

**报错落在调用方源码上**

- 贴在 `let`、计算属性、带初始值或没写类型的属性上（`let` 与初始值各带一个 Fix-It）；`bits:` 不是整数字面量，区间为空或倒置，位置为负。
- 按拼写能查的就查：类型写成 `Bool` 却给了多位区间；类型是认得的整数拼写（`UInt8` 等，`Int` / `UInt` 按 64 位，与 `@FlagSet` 一致），区间却比它宽。typealias 与泛型参数不查。
- **区间超出 `rawValue` 的位宽，宏查不到。** accessor macro 看不到宿主的其他成员——`lexicalContext` 会把外层类型的成员列表清空——所以这一条由辅助函数里的 `precondition` 在第一次读取时拦下。这是声明写错，不随输入变化，测试一跑就会撞上。整数类型比区间窄、而拼写又认不出（typealias、泛型参数）的情况也一样处理。

**不做**

- **setter。** 宏看不到 `rawValue` 是 `let` 还是 `var`，生成 `set` 需要调用方另外表态。第一个使用方只有一个可写的 flag word（MachOSwiftSection 的 `MetadataRequest`），它现在的手写版本是对的。真有需要时照 `@AvailableNonMutating` / `@AvailableMutating` 的先例另加一个 `@MutableBitField`。
- **不叫 `rawValue` 的存储。** 宏参数里引用不到宿主自己的成员（`@Projection` 实测是 circular reference，`@FlagSet` 生成的成员在宏参数里也不可见），所以写不出 `in: \.layout.flags`。
- 不连续的位（swift-mmio 支持 `bits: 0, 3`）；`a...b`、`16...` 这类区间写法；字段之间的重叠检查（同样因为看不到兄弟成员）。

**与 `@FlagSet` 的关系**

两者各管一半：每个选项占一位、可以自由组合的，用 `@FlagSet`；一个字里分段存着不同东西的，用 `@BitField`。两者可以用在同一个类型上——`@FlagSet` 生成的 `rawValue` 正好是 `@BitField` 读的存储。MachOSwiftSection 的 `ValueWitnessFlags` 就是这种形状：高位是一组标志，低 8 位是 alignment mask。

**测试与文档**

- 展开快照，每条报错一个快照。
- 行为测试覆盖上表每一行，包括认不得的值、raw value 装不下的值、泛型存储与 `OptionSet` 字段。
- `SwiftStdlibToolboxClient` 钉住公开用法；`DefaultMainActorIsolationClient` 确认展开结果在默认 MainActor 隔离的模块里不额外引入隔离。干净构建无警告。
- 宏声明上的 DocC 注释；`CLAUDE.md` 的 `SwiftStdlibToolbox` 一行与一条 Key Patterns；新建使用指南 `Documentations/BitField.md`，写契约与陷阱（`default:` 要写全名、认不得的值怎么处理、宏查不到的越界）；两份索引。

**第一个使用方**

MachOSwiftSection 的 ABI 层。它的迁移是那边的另一份提案，等这边发出包含本宏的版本后再写：17 个混排的 flag word 改用 `@BitField`，三个读错的访问器借这次迁移修掉（先写会崩的复现测试）；`ClassFlags` 与 `InvertibleProtocolSet` 改用 `@FlagSet`。

## 落地步骤

每一步各自能构建、测试通过，单独提交。

- [x] 1. 宏的声明与实现：`bits:` 的两种写法、`default:`、生成的 getter 与 `#sourceLocation`；运行时的重载辅助；注册进插件；展开快照测试。
- [x] 2. 报错与 Fix-It：每条一个快照测试。（与第 1 步同一个提交：快照都在 `BitFieldMacroTests.swift` 一个文件里。）
- [x] 3. 行为测试与客户端钉住：上表每一行；`SwiftStdlibToolboxClient` 与 `DefaultMainActorIsolationClient`；干净构建无警告。
- [x] 4. 文档：DocC、`CLAUDE.md`、使用指南 `Documentations/BitField.md`、两份索引。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-05 | Created as Draft | 调研 MachOSwiftSection 的 ABI 层时发现：17 个 flag word 照 C++ 头文件手写，写法四种，三个访问器把位读错；`@FlagSet` 只覆盖纯单比特的集合，装不下多位字段 |
| 2026-11-05 | 放在 FrameworkToolbox 的 `SwiftStdlibToolbox`，与 `@FlagSet` 并列，不放进 MachOSwiftSection 自己的宏 target | 用户选定。MachOObjCSection 等仓库也在解析二进制里的 flag word，放在这里都能用；代价是 MachOSwiftSection 要等这边发版 |
| 2026-11-05 | 做成宏，不只提供函数 | MachOSwiftSection 早就有一组按位读取的函数（它的 `FlagSet` 协议上的 `flag(bit:)` 与 `field(firstBit:bitWidth:fieldType:)`），17 个混排类型里只有 3 个用了，读错的三个都没用。即使用了，转成目标类型的那一步（`.init(rawValue:)!`）还得逐个手写。宏让每个访问器只剩「位的范围」和「类型」两样，转换没有手写的机会，范围写错在展开时就报 |
| 2026-11-05 | 贴在属性上的 accessor macro，不做贴在结构体上、生成全部成员的宏 | 声明留在源码里：文档注释、`@available`、访问级别照常写在属性上，只看源码的工具也看得到它（MachOSwiftSection 的覆盖率检查按语法扫描公开成员）。代价是看不到兄弟成员，查不了重叠与越界 |
| 2026-11-05 | 宏名 `@BitField`，不照 C++ 叫 `@Flag` / `@Field` | C 语言里这东西就叫 bit-field，Swift 导入 C 的 bit-field 时也是一个计算属性。`@Flag` 和 `@FlagSet` 固定的嵌套枚举名 `Flag` 撞在一起；`@Field` 太泛。swift-mmio 按寄存器的读写权限起名（`@ReadOnly` / `@ReadWrite`），这里没有那层语义 |
| 2026-11-05 | 参数标签 `bits:`，收单个位置或半开区间 | 照 Apple 的 swift-mmio：`@ReadWrite(bits: 12, as: Bool.self)`、`@ReadWrite(bits: 0..<4)`。区间只收半开一种，一种形状一种拼法；C++ 表格的「起始位 + 宽度」也正好翻成半开区间 |
| 2026-11-05 | 转换按属性的类型交给重载决议，宏不分辨类型 | 宏看不到 typealias 背后是什么。MachOSwiftSection 里就有 `RawValue`、`StoredSize`、泛型参数 `IntType` 这样的整数字段，按拼写分辨会把它们当成枚举 |
| 2026-11-05 | 认不得的值没有「崩溃」这一档：要么声明成可选，要么写 `default:` | 这些位多半来自外部输入，将来的新 kind 也会落进来。MachOSwiftSection 的 `KeyPathComponentHeader` 注释早就写明「输入是任意的二进制内容，不能强制解包」。危险要写在调用点上，不能是默认行为 |
| 2026-11-05 | 第一版不生成 setter | 宏看不到 `rawValue` 能不能改，生成 `set` 需要另外的表态；第一个使用方只有一个可写的 flag word，它的手写版是对的 |
| 2026-11-05 | 用户批准，开始实现 | — |
| 2026-11-05 | 构建与测试经 workspace 用本地预编译的 swift-syntax 603.0.1，不从源码编译 | 与 `@FlagSet` 那次一致。workspace 与预编译包都在仓库外 agent 自己的目录里；`SwiftStdlibToolboxTests` 没有 Xcode 自动生成的 scheme，所以在 workspace 里另写了测试 scheme；Xcode 解析时改写的 `Package.resolved` 每次都还原，不提交 |
| 2026-11-05 | 宏声明四个重载：`bits:` 收 `Int` 或 `Range<Int>`，各有一个带 `default:` 的版本 | 宏参数按声明做类型检查，单个位置与区间是两种类型；`default:` 是泛型参数 `Value`，由参数自身推断，因为声明里写不出属性的类型 |
| 2026-11-05 | 除方案里那条「非可选 `RawRepresentable` 没写 `default:`」之外，再加两个不可用重载：读不了的类型（raw value 不是整数的枚举、`Bool?` 等），以及把 `default:` 用在不是非可选 `RawRepresentable` 的属性上 | 不加时这两种错误是 `no exact matches in call`，指向一个调用方没写过的调用；加了以后消息直接说该怎么写，`#sourceLocation` 照样把它放到属性那一行 |
| 2026-11-05 | 生成的调用写成 `SwiftStdlibToolbox._BitFieldAccess.value(…)`，属性的类型写成 `(Type).self` | 带模块名，调用方类型里的同名成员截不走这次调用（`SwiftStdlibToolboxClient` 用一个同名的嵌套类型钉住）；类型加括号，`Kind?` 这类带后缀的类型接 `.self` 时不出错 |
| 2026-11-05 | 一次声明多个变量时，宏自己不报错 | 宏系统先报 `accessor macro can only be applied to a single variable`，轮不到宏；swift-macro-testing 的快照里看到的就是这一条 |
| 2026-11-05 | 「只能用在属性上」用贴在 subscript 上的情形来测，不用函数 | accessor macro 只能贴在属性或 subscript 上，函数在宏运行之前就被拒绝，swift-macro-testing 也不会对函数调用它；subscript 会走到宏 |
| 2026-11-05 | 属性已有 accessor（含 `willSet` / `didSet`）时报错，报在属性名上 | 宏加了 getter 之后编译器会丢掉观察器，静默丢掉比报错更糟。swift-macro-testing 把这条画在快照顶部：swift-syntax 是对改写过、已不在文件里的那份声明展开的，位置对不上文件。编译器里落在哪一行见下一步的实测 |
| 2026-11-05 | 实测报错的位置与措辞 | 在 `SwiftStdlibToolboxClient` 里临时放一个编不过的文件，读完错误即删：三条不可用重载的消息都报在属性那一行；`default: .first` 报 `cannot infer contextual base in reference to member 'first'`，在宏参数那一行；属性已有 accessor 时，宏的报错落在属性名上 |
| 2026-11-05 | 更正方案外的一处假设：在后台读取时，读出来的枚举不必标 `nonisolated` | 在默认 MainActor 隔离的模块里实测：带 raw value 的枚举对 `RawRepresentable` 的遵循不被隔离，`nonisolated` 的结构体读一个留在主线程上的枚举能编过。留在主线程上的结构体，它的 bit field 从 `nonisolated` 函数里读报 `main actor-isolated property … can not be referenced from a nonisolated context`，与手写的计算属性一样。两种写法都钉在 `DefaultMainActorIsolationClient` 里 |
| 2026-11-05 | 越界的位用 exit test 钉住 | `precondition` 只在读取时触发，exit test 确认它确实让进程以失败退出，而不是读出一个截断的值 |
| 2026-11-05 | 实现完成，待用户看过后收尾 | 完整验证在清空构建产物与编译缓存后重建跑：13 个测试 target 共 824 个测试全部通过（Swift Testing 773 个、XCTest 51 个，比 `@FlagSet` 落地时多出本次的 27 个），12 个客户端 target 全部编过，原始退出码为 0。新文件零警告；构建里另有 7 条警告，都在没改动的旧文件里（`OSLogFormatSupport.swift`、`DynamicObjectTests.swift`）。没有偏离方案、没有没做的项，实现中补充的决定见以上几行。文档：使用指南 `BitField.md` 已登记为配套文档，更新了 `CLAUDE.md` 与两份索引；不另写实现说明，实现决策都在本提案与 `CLAUDE.md` 里；没有新术语 |
