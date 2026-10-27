# 0010 - `@Equatable` 不再弄丢经由细化协议得到的 `Hashable`

- **状态**: Implemented
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **实现分支**: `feature/equatable-refined-hashable`

## 摘要

类型经由一个细化 `Hashable` 的协议得到 `Hashable` 时（`protocol Record: Hashable {}`，`@Equatable struct Note: Record`），
加上 `@Equatable` 就编不过：`type 'Note' does not conform to protocol 'Hashable'`。成员全是可哈希的类型也一样，
`Record` 写在类型上还是写在 extension 里也一样。

原因在宏的声明。`@Equatable` 把 `Hashable` 列进 `conformances:`，为的是让编译器经 `conformingTo:` 告诉它类型是否已经
`Hashable`。编译器在展开之前，先给这个列表里的每个协议记一条「宏将要添加」的占位遵循；而占位遵循在场时，经由细化协议
隐含得到的遵循根本不会被记录（`ConformanceLookupTable::addProtocol` 对 `Implied` 一类遇到 `PreMacroExpansion` 时直接放弃）。
宏随后并不添加 `Hashable`，类型就此失去了这个遵循。这也解释了上一轮记下的现象「`conformingTo:` 不含经由细化协议隐含的遵循」
（[0009](0009-macro-diagnostics-at-call-site.md) 因此撤回了 `@ObjectiveCBridgeable` 的遵循检查）：不是编译器漏算，是列表本身
把它挤掉了。

本提案把 `Hashable` 从 `conformances:` 里拿掉，改由编译器在重载决议里判断类型是否 `Hashable`。

## 方案

- `@Equatable` 的声明改为 `conformances: Equatable`。`_EquatableConformanceSentinel` 只为解读 `conformingTo:` 而存在，
  与读它的 `compilerReportsHashableConformance` 一起删除。
- **类型的继承子句写了 `Hashable`**（任何拼写）：照旧直接生成 `hash(into:)`，展开结果不变。
- **没写**：生成的 `==` 上挂 `@SwiftStdlibToolbox._EquatableHashing(<类型>.self, members: ["a", "b"])`。`_EquatableHashing` 是
  两个只差 `Subject: Hashable` 约束的 peer 宏（skill 技巧 2）：类型 `Hashable` 时约束更具体的那个胜出，生成与 `==` 比较同一组
  成员、顺序相同的 `nonisolated public func hash(into:)`；否则选中不带约束的那个，什么也不生成。于是 `Hashable` 不论写在类型上、
  写在别处的 extension 里、经由细化协议、还是继承自父类，判断都出自编译器。
- 成员名以字符串字面量传入：宏只需要名字；字符串不经类型检查，不会把成员类型上的错误牵连到这个属性上。
- memberAttribute 角色不变：它拿不到遵循信息，仍只按继承子句在 `_HashableMemberCheck` 与 `_EquatableMemberCheck` 之间选。
  经由细化协议得到 `Hashable` 的类型，成员按 `Equatable` 检查；某个成员只遵循 `Equatable` 时，错误落在生成的 `hash(into:)` 里。
- 回归测试：上一轮实测失败的两种写法（细化协议写在类型上、写在 extension 里）进 `EquatableHashingConsistencyTests`，
  并断言 `==` 判等的两个值哈希也相等；改动前先确认它们编不过。

没有询问就采用的假设：

- **条件遵循**（`extension Pair: Hashable where First: Hashable`）时，`==` 所在的 extension 没有这些约束，`Pair: Hashable` 不成立，
  宏不生成 `hash(into:)`，由编译器按全部存储属性合成；有被忽略的成员时哈希与 `==` 不一致。改动前宏在这种情况下生成的
  `hash(into:)` 处在无约束的 extension 里，本来就编不过。记为已知限制，写进文档注释。

### 源码兼容性

- 继承子句写了 `Hashable` 的类型：展开不变。
- 其余类型：展开出的 `==` 多一个属性，比较与哈希行为不变；没有 `Hashable` 的类型不会多出任何成员。
- 经由细化协议得到 `Hashable` 的类型：从编不过变为能编译，`hash(into:)` 与 `==` 一致。
- 在别处 extension 里声明 `Hashable` 的类型：结果与改动前相同，只是判断改由重载决议做出。
- 删除的 `_EquatableConformanceSentinel` 带下划线、文档隐藏，不算公开 API。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 上一轮宏审视时发现：类型经由细化协议得到 `Hashable` 时 `@Equatable` 编不过，在改动前的 main 上同样失败，当时作为既有问题留下 |
| 2026-10-27 | 用户批准，开始实现 | 用户决定修复 |
| 2026-10-27 | 判断交给重载决议，不加宏参数让调用方声明 | 让调用方写 `@Equatable(hashable: true)` 也能修，但那是又一个让调用方代替编译器回答的问题，答错仍是编译失败或哈希不一致；编译器本来就知道答案 |
| 2026-10-27 | 回归测试先红后绿 | 改动前，`EquatableHashingConsistencyTests` 里三个经由细化协议得到 `Hashable` 的类型（写在类型上、写在 extension 里、一个 final class）编不过：`type 'RefinedHashableHandle' does not conform to protocol 'Hashable'`、`generic struct 'Set' requires that 'RefinedHashableNote' conform to 'Hashable'`。改动后编译通过，`==` 判等的两个值哈希相等 |
| 2026-10-27 | 重载在真实编译器里选对了 | 用 `-dump-macro-expansions` 看 `DefaultMainActorIsolationClient` 的展开：经由细化协议 `Hashable` 的 `LedgerEntry` 由 `_EquatableHashing` 生成了只 combine 被比较成员的 `hash(into:)`，不 `Hashable` 的 `Swatch` 什么也没生成 |
| 2026-10-27 | 默认 MainActor 隔离模块里的守卫写成 `nonisolated LedgerRecord` | 实测：那种模块里，主线程隔离的类型遵循一个细化 `Hashable` 的协议会报 `conformance … crosses into main actor-isolated code`，不挂 `@Equatable` 的同样写法报同一个错，与本宏无关；直接写 `Hashable` 则不报。调用方要像对 `Hashable` 写 `nonisolated Hashable` 那样把这个遵循移出主线程，守卫照此写，并在旁边注明 |
| 2026-10-27 | 快照随之更新 | 继承子句没写 `Hashable` 的 5 个快照，生成的 `==` 上多了 `_EquatableHashing` 一行，成员顺序与 `==` 一致；写了 `Hashable` 的快照不变。两个实现各有单独的宏测试，测试框架不做重载决议 |
| 2026-10-27 | 实现完成，待合并 | 干净重编后完整测试套件通过（706 个 swift-testing 测试、51 个 XCTest），没有新增警告。文档判断：`@Equatable` 的文档注释改写了 `Hashable` 怎么判断，并写明条件遵循这个盲区；`CLAUDE.md` 里「编译器替宏判断」一条换掉了对 `conformingTo:` 的旧解释，写成 `conformances:` 的占位遵循规则；不另写使用指南，没有新术语 |
| 2026-10-27 | Implemented，编号 0010 | 随 `feature/equatable-refined-hashable` 合入 main，与方案没有偏离，没有遗留的后续项。文档判断同上一行：`@Equatable` 的文档注释与 `CLAUDE.md` 已同步，不另写使用指南，没有新术语 |
