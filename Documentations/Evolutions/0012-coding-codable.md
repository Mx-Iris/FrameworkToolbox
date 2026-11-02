# 0012 - `CodingCodable`：只遵循 `NSCoding` 的类也能走 Codable，并补全归档错误信息

- **状态**: Implemented
- **创建日期**: 2026-11-02
- **最后更新**: 2026-11-02

## 摘要

`SecureCodingCodable` 让遵循 `NSSecureCoding` 的 `NSObject` 子类以一份 `NSKeyedArchiver` 归档（存为单个 `Data`）参与 Codable。
这次新增它的上层协议 `CodingCodable`，覆盖只遵循 `NSCoding` 的类，`SecureCodingCodable` 改为细化它。

新协议的初版能编码、却解码不回来：解码用的 `NSKeyedUnarchiver.unarchivedObject(ofClass:from:)` 在 Swift 里只要求 `NSCoding`，
所以编译通过；但它背后的 Objective-C 方法总是开启 secure coding，运行时拒绝所有不支持 secure coding 的类，而这正是
`CodingCodable` 要服务的类型。数据写得进去、读的时候才失败，比编译不过更糟。

本提案修好这条解码路径，顺带修正 `SecureCodingCodable` 在编码与解码两头对 `supportsSecureCoding` 处理不一致的旧问题，
并把失败时抛出的错误换成带编码路径和 Foundation 原因说明的 `EncodingError` / `DecodingError`。

## 方案

- `CodingCodable` 与 `SecureCodingCodable` 各自提供 `encode(to:)` 与 `init(from:)`，共用一个以 `requiringSecureCoding` 为参数的私有实现。
  `CodingCodable` 两头都关掉 secure coding；`SecureCodingCodable` 两头都跟随类的 `supportsSecureCoding`。
  细化协议上的实现更具体，编译器为 `SecureCodingCodable` 的遵循者选它。
  `encode(to:)` 写在两个协议各自的扩展里；`init(from:)` 只能写在 `extension Decodable where Self: …` 上，
  因为类约束协议的扩展里不能给 `self` 赋值（见决策日志）。
- 解码改用 `NSKeyedUnarchiver(forReadingFrom:)`，按参数设置 `requiresSecureCoding`，再用 `decodeTopLevelObject(of:forKey:)` 取根对象。
  关掉 secure coding 时 Foundation 不再校验类（`NSCoder.h`：「the class argument is ignored」），根对象的类型由 `as? Self` 检查。
- 错误一律带上编码路径（`codingPath`）：

  | 失败的地方 | 抛出 | 附带的信息 |
  |------|------|------|
  | 归档失败 | `EncodingError.invalidValue` | 类型名、`requiringSecureCoding`、Foundation 的 `NSDebugDescription`、原错误 |
  | 存的值不是 `Data` | `DecodingError.typeMismatch` | 原说明前加一句「此类型存为一份归档 `Data`」 |
  | 解档失败 | `DecodingError.dataCorrupted` | 类型名、字节数、`requiresSecureCoding`、Foundation 的 `NSDebugDescription`、原错误 |
  | 归档里没有根对象 | `DecodingError.dataCorrupted` | 期望的类型名 |
  | 根对象的类不对 | `DecodingError.typeMismatch` | 实际的类名与期望的类名 |

  Foundation 归档错误的 `localizedDescription` 只有一句「格式不正确」，真正的原因在 `NSDebugDescription` 里（有时在下层错误上），
  所以要取出来写进说明。
- 新增 `CodingCodableTests`：两个协议各自往返一次、`supportsSecureCoding` 为 false 的类往返一次，以及上表的每种失败。
- 文档：两个协议的文档注释写明存储格式和 `CodingCodable` 的安全前提；`CLAUDE.md` 记下 `unarchivedObject(ofClass:from:)`
  能编译、运行时却强制 secure coding 的坑。

没有询问就采用的假设：

- **名字沿用 `CodingCodable`。** 它与 Apple 自己的 `NSCoding` / `NSSecureCoding` 一一对应：不安全的一方用平常的名字，
  安全的一方带 `Secure`。不另加 `Insecure` 前缀，危险写在文档注释里。
- **错误用标准库的 `EncodingError` / `DecodingError`，不另设公开错误类型。** Codable 的调用方本来就按这两类处理错误，
  `JSONDecoder` 也原样转抛协议实现抛出的错误。
- **只给「存的值不是 `Data`」的 `typeMismatch` 补说明。** `valueNotFound` 等其余来自外层解码器的错误原样转抛，它们的说明已经够用。

### 源码兼容性

- `SecureCodingCodable` 的要求不变（`NSObject`、`NSSecureCoding`、`Codable`），现有遵循者照常编译。
- `init(from:)` 仍声明在 `extension Decodable where Self: …` 上，调用写法不变；`Encoder` / `Decoder` 参数改写成
  `any Encoder` / `any Decoder`，是同一个类型。
- 抛出的错误变了：原来是外部无法匹配的私有类型，或 Foundation 的原始 `NSError`；现在是标准的 `EncodingError` /
  `DecodingError`，原错误保留在 `underlyingError` 里。
- `supportsSecureCoding` 返回 false 的 `SecureCodingCodable` 类：过去写进去的数据读不回来，现在能读回。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-02 | Created as Draft | 审查新增 `CodingCodable` 的重构时发现：只遵循 `NSCoding` 的类能编码、却永远解码不回来；同时要补充失败时的错误信息 |
| 2026-11-02 | 用户批准，开始实现 | 修复解码、错误换成标准类型、新增测试；`supportsSecureCoding` 为 false 时解码也跟随它；为新增的公开协议补写本精简提案 |
| 2026-11-02 | 两个解码问题先红后绿 | 改动前，`CodingCodableTests` 的两个往返测试失败，Foundation 给出的原因分别是 `This decoder will only decode classes that adopt NSSecureCoding. Class '…LegacyBookmark' does not adopt it.` 和 `Class '…OptedOutBookmark' disallows secure coding. It must return YES from supportsSecureCoding.`；改用按参数设置 `requiresSecureCoding` 的解档器后通过。这也实测了 `init(forReadingFrom:)` 之后可以把 `requiresSecureCoding` 关掉——该属性的头文件注释说一旦开启就不能关，与实际行为不符 |
| 2026-11-02 | `init(from:)` 留在 `extension Decodable where Self: …` 上 | 方案原想把它挪进两个协议的扩展，编译器报 `cannot assign to value: 'self' is immutable`：类约束协议的扩展里不能给 `self` 赋值，非类约束的 `Decodable` 的扩展里可以。原代码这样写正是为此，代码里已加注释说明 |
| 2026-11-02 | 错误信息先红后绿 | 6 个错误测试在只修了解码的代码上全部失败，抛出的是私有错误或原始 `NSError`；补上错误信息后全部通过。归档失败那一例证实：外层错误的说明只有 `The data couldn’t be written because it isn’t in the correct format.`，真正的原因在下层错误的 `NSDebugDescription` 里，所以取原因时沿 `NSUnderlyingErrorKey` 往下找 |
| 2026-11-02 | 测试同时固定两个协议实现的选择 | 安全归档拒绝不支持 secure coding 的子对象、安全解档报出 Foundation 的类检查，两例只在编译器选中 `SecureCodingCodable` 的实现时成立。两份实现一旦变得有歧义，编译器不会报错，而是改为自动合成 `Codable`（`TypeCheckProtocol.cpp` 的 `resolveWitnessViaLookup`），这两例会先失败 |
| 2026-11-02 | 实现完成，待提交 | 完整测试套件通过（717 个 swift-testing 测试、51 个 XCTest），没有新增警告。文档判断：存储格式与安全前提写在两个协议的文档注释里，实现上的三个坑写进 `CLAUDE.md`；契约已由文档注释覆盖，不另写使用指南；没有新术语 |
| 2026-11-02 | Implemented，编号 0012 | 直接在 main 上提交落地。与方案的偏离只有 `init(from:)` 的位置（见上文），没有后续项。落地前在最终代码上跑完整测试套件时，`OSToolboxTests` 的 `LoggingControlTests` 失败了一次，与本改动无关：不含本改动的 main 上只跑 `OSToolboxTests`，第 6 次就复现了同类失败。原因是这几个各自标了 `.serialized` 的测试套件彼此并行执行，却都在改同一个进程级开关。之后完整套件连跑两次均通过（717 个 swift-testing 测试、51 个 XCTest），文档判断同上一行 |
