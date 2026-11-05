# `@BitField` —— 用法契约与陷阱

`@BitField` 贴在属性上，让它从所在类型的 `rawValue` 里读出某几位。它是 C++ `FLAGSET_DEFINE_FLAG_ACCESSORS` / `FLAGSET_DEFINE_FIELD_ACCESSORS`（`swift/Basic/FlagSet.h`）在 Swift 里的对应物。手写这种访问器要移位、掩码、转换三步，漏掉一步照样编译通过；用了宏，每个访问器只剩「占哪几位」和「是什么类型」两样。设计与取舍见提案 [`@BitField`：按位的范围生成 flag word 的访问器](Evolutions/0015-bit-field-macro.md)。

```swift
public struct ContextDescriptorFlags: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0..<5, default: ContextDescriptorKind.unknown)
    public var kind: ContextDescriptorKind

    @BitField(bits: 7)
    public var isGeneric: Bool

    @BitField(bits: 8..<16)
    public var version: UInt8

    /// The protocol flags of a protocol descriptor, or `nil` for a value this
    /// reader does not know.
    @BitField(bits: 16..<32)
    public var protocolFlags: ProtocolContextDescriptorFlags?
}
```

宏只生成 getter。属性上的文档注释、`@available`、`@inlinable` 与访问级别都由调用方照常写在属性上，原样保留。

## 契约

**宿主要有一个叫 `rawValue` 的存储属性，类型是任意 `FixedWidthInteger`。** `let` 或 `var` 都行，泛型参数也行。宏生成的 getter 读的是 `self.rawValue`，名字固定。

**`bits:` 只收整数字面量：单个位置，或半开区间。** bit 0 是最低位。照 C++ 的表格翻写时，起始位加宽度就是区间：`SpecialProtocolKind = 2` 与 `SpecialProtocolKind_width = 6` 写成 `bits: 2..<8`；照掩码翻写时，`(rawValue & 0x3F00_0000) >> 24` 写成 `bits: 24..<30`。常量（`Bits.kindShift..<…`）、闭区间 `2...7` 与 `16...` 都不收。

**属性的类型决定怎么读。** 宏不分辨类型——它只看得到拼写，认不出 typealias 背后是什么——而是把类型交给编译器，由重载决议选出转换：

| 属性的类型 | 读出来的值 |
|---|---|
| `Bool` | 那一位是不是 1 |
| 整数类型（含 typealias 与泛型参数） | 这几位移到最低位，按 `init(truncatingIfNeeded:)` 转换 |
| 遵循 `OptionSet`、raw value 是整数的类型 | 用这几位构造的集合 |
| `T?`，`T` 是 raw value 为整数的 `RawRepresentable` | 认得的值得到对应的 case，认不得的得到 `nil` |
| `T` 并写了 `default:` | 认不得时取 `default:` 给的值 |

**非可选的 `RawRepresentable` 必须写 `default:`。** 没写就编译不过，错误报在属性那一行，消息里写出两种改法：声明成可选，或者写 `default:`。认不得的值没有「崩溃」这一档：flag word 多半来自程序外面——文件、另一个进程、更新的编译器——一个没见过的值不该让读取它的程序崩溃。

**`default:` 要写全名。** 写 `default: ContextDescriptorKind.unknown`，不写 `.unknown`。宏参数在展开之前按宏的声明做类型检查，而声明里没有属性的类型可供推断，所以 `.unknown` 编译不过（`cannot infer contextual base`）。

**转成 raw value 用精确转换。** 一个 16 位的字段装进 raw value 为 `UInt8` 的枚举时，`0x0101` 读成 `nil`，不会被截成 `0x01`、误读成一个合法的 case。

## 陷阱

### 越界的位只在运行时拦下

宏看不到宿主的其他成员（accessor macro 拿到的 `lexicalContext` 里，外层类型的成员列表是空的），所以不知道 `rawValue` 有多宽。区间超出 `rawValue` 的位宽时，第一次读取这个属性就会 `precondition` 失败、程序停下。整数类型比区间窄、而它的拼写又认不出来（typealias、泛型参数）时也一样。这是声明写错，不随数据变化，所以**每个 flag word 至少要有一条测试把每个属性读一遍**。

拼写认得出来的在展开时就报：`Bool` 配了多位区间、`UInt8` 配了 16 位的区间。`Int` / `UInt` 按 64 位检查（arm64_32 的 watchOS 上它们是 32 位），与 `@FlagSet` 一致。

### 字段之间的重叠不查

两个属性的区间重叠不会报错，原因同上：宏看不到兄弟成员。有时重叠是有意的——同一段位按两种方式解读——所以照 C++ 的表格翻写时自己核对。

### 默认 MainActor 隔离的模块

宏只给属性加 getter，改不了属性的隔离：留在主线程上的类型，它的 bit field 也只能在主线程上读，与手写的计算属性一样——从 `nonisolated` 函数里读会报 `main actor-isolated property … can not be referenced from a nonisolated context`。要在后台读，把类型标成 `nonisolated`。它读出来的枚举可以留在主线程上：带 raw value 的枚举对 `RawRepresentable` 的遵循不被隔离（实测）。`DefaultMainActorIsolationClient` 里两种写法都钉住了。

### 宏参数里引用不到宿主的成员

`bits:` 写不成 `Self.kindShift..<…`：一来宏要在展开时就拿到数字，二来挂在声明上的宏的参数里，名字查找引用宿主自己的成员会形成循环（`@Projection` 实测为 circular reference）。所以位置只能写字面量，`Bits` 那一套常量迁移时就删掉。

## 与 `@FlagSet` 一起用

每个选项占一位、可以自由组合的，用 `@FlagSet`；一个字里分段存着不同东西的，用 `@BitField`。两者可以用在同一个类型上：`@FlagSet` 生成的 `rawValue` 正好是 `@BitField` 读的存储。

```swift
@FlagSet
public struct ValueWitnessFlags: Hashable, Sendable {
    public enum Flag: UInt32, Sendable {
        case isNonPOD = 16
        case isNonInline = 17
        case hasSpareBits = 19
    }

    /// The alignment of the type, minus one.
    @BitField(bits: 0..<8)
    public var alignmentMask: UInt8
}
```

## 从手写版迁移

1. 每个访问器改成 `@BitField(bits: …) var 名字: 类型`，删掉 getter。
2. 原先 `Kind(rawValue: …)!` 强制解包的，改成可选或加 `default:`。这会改变公开属性的类型，下游对它的穷举 `switch` 要补 `nil` 分支。
3. 删掉不再用的掩码与位置常量。
4. 补一条把每个属性读一遍的测试，越界的区间只有这样才会被发现。
