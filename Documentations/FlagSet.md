# `@FlagSet` —— 用法契约与陷阱

`@FlagSet` 贴在结构体上，把它变成一个 `OptionSet`：选项就是嵌套枚举 `Flag` 的各个 case，每个 case 的
原始值是它那一位的位置。手写这种选项集合时，每加一个标志要改两处（case 与 static），两处对不上不会报错；
用了宏，枚举就是唯一的定义处。设计与取舍见提案
[`@FlagSet`：由嵌套的 `Flag` 枚举生成 OptionSet](Evolutions/0014-flag-set-macro.md)。

```swift
@FlagSet
public struct Permissions: Codable, Hashable, Sendable {
    public enum Flag: Int, CaseIterable, Sendable {
        /// The holder can read the resource.
        case read = 0
        case write = 1
        case execute = 2
    }
}

let permissions: Permissions = [.read, .execute]   // rawValue 5
let fromFlag = Permissions(.write)                   // rawValue 2
```

宏生成 `rawValue`、`init(rawValue:)`、`init(_ flag: Flag)`，以及每个 case 一个同名的 `static let`；结构体
没写 `OptionSet` 时再补上这个遵循（写了也无妨，宏不会重复添加）。

## 契约

**`Flag` 必须在结构体体内直接声明，名字固定，原始类型写在第一位。** 写在 extension 里、或叫别的名字，
宏都找不到它，会在结构体名上报错。原始类型必须是整数类型：没写、或第一个继承项是 `CaseIterable` 这类协议时，
宏在 `Flag` 上报错并给出补 `Int` 的 Fix-It；写成 `String`、`Double` 时报在那个类型上。`rawValue` 的类型照抄
这个原始类型，所以 `enum Flag: UInt8` 得到的是 `UInt8` 存储的集合。

**文档注释写在 case 上。** 生成的 static 带着同一段文档注释（从客户端模块抽出的符号图里实测可见，DocC 读的
就是它），`case a, b` 共用一段注释时两个 static 都带上。case 上的 `@available` 与包着它的 `#if` 一并带到它的
static 上；`Flag` 自己的 `@available` 加到 `init(_:)` 与每个 static 上。

**`Codable`、`Hashable`、`Sendable` 由调用方自己写。** 宏只加 `OptionSet`。声明了 `Codable` 的集合走
`RawRepresentable` 的默认实现，编码成一个整数（`[.read, .execute]` 编成 `5`）。

**`init(_:)` 的可见范围不超过 `Flag`。** `public` 结构体里的 `private enum Flag` 得到 `private init(_:)`，
static 与 `rawValue` 仍是 `public`——标志只能经 static 取用，枚举对外隐藏。

## 陷阱

### 持久化的位：位置就是格式

集合的原始值写进磁盘、或发给另一个构建的进程时，每个 case 的位置就成了格式的一部分：

- **每个 case 都显式写原始值。** 隐式原始值从上一个 case 加一，在中间插入一个 case，后面所有标志的位都会
  悄悄后移。宏不报这个，因为它不知道这些位会不会被持久化。
- **退役的位置不再复用。** 不用的标志可以留着 case、标上 `@available(*, deprecated)`，它的 static 跟着弃用。
- **用一条测试把发布过的位值写成字面量钉住**，期望值不要从 `Flag` 推算。写这条测试时注意下一节。

### 挂在声明上的宏，参数里看不到生成的成员

```swift
@Test(arguments: [(Permissions.read, 1), (.write, 2)])   // ❌ type 'Permissions' has no member 'read'
```

编译器在宏参数里做名字查找时，一律不展开别的宏、也不取已展开的结果（`lib/AST/NameLookupRequests.cpp`，
为了不让宏展开互相依赖成环）。所以凡是 `@FlagSet` 生成的东西——static、`init(_:)`、`init(rawValue:)`——
在 `@Test(arguments:)` 这类参数里都找不到。宏这边绕不过去。改传调用方自己写的 `Flag` case，在函数体里
再造集合：

```swift
@Test(arguments: [(Permissions.Flag.read, 1), (.write, 2)])
func flagKeepsItsBit(flag: Permissions.Flag, rawValue: Int) {
    #expect(Permissions(flag).rawValue == rawValue)
}
```

函数体不受影响：实测测试函数体里的 `#expect(Permissions.read == Permissions(.read))` 照常编译。

### 越界的位置会让标志变成空集

`1 << 64` 与 `1 << -1` 在 Swift 里都是 `0`，这样的标志是一个空集合，`contains` 对任何集合都成立。所以宏在
case 上报两种错：位置为负，或不小于原始类型的位宽。位宽按拼写判断——`Int8` 到 `UInt128` 各按其宽度，
`Int` / `UInt` 按 64；typealias 等认不出的拼写不检查，`#if` 之后、各分支走完位置不同的隐式值也不检查。

**arm64_32 的 watchOS 上 `Int` 只有 32 位。** 宏不知道调用方为哪个平台编译，按 64 位放行；位置 32 到 63 在
那里会静默变成空集。要支持那个平台，原始类型用 `Int64` / `UInt64`，或者不超过 31。

### 默认 MainActor 隔离的模块里不用额外处理

新建 App target 的默认设置会把一切未标注的声明隔离在主线程上，宏生成的也不例外。生成的成员都标了
`nonisolated`，留在主线程上的集合也能从 `nonisolated` 代码里用（`DefaultMainActorIsolationClient` 里钉住），
结构体本身不必再标 `nonisolated`。

## 从手写版迁移

1. 结构体上加 `@FlagSet`。
2. 删掉 `rawValue`、`init(rawValue:)`、`init(_:)` 与每个 static。
3. 把每个 static 上的文档注释挪到同名的 case 上。
4. 检查有没有在 `@Test(arguments:)` 之类的宏参数里写 static 的地方，按上一节改写。

`OptionSet` 写在结构体头上的可以留着。
