# Draft - 用 @_rawLayout 把 Mutex 的锁与值内联（暂不采纳）

- **状态**: Deferred
- **作者**: JH
- **创建日期**: 2026-09-16
- **最后更新**: 2026-09-16
- **所属愿景**: 无
- **关联提案**: [0003](0003-objc-runtime-toolbox-self-contained-leaf.md) —— 其前期调研已记录 `Mutex` 在 `ObjCRuntimeToolbox` 的零使用
- **实现分支 / PR**: 无 —— 本提案不落地代码
- **配套文档**: 无 —— 结论与实测数据全在本文

## 摘要

标准库 `Synchronization.Mutex` 把锁和被保护的值**内联**在结构体自身里，零堆分配；
`OSToolbox` 的 `Mutex`（`Sources/OSToolbox/Mutex.swift`）做不到，只能退而求其次：
一次堆分配，把 `os_unfair_lock` 和值并排放进同一块缓冲区，结构体里只留一个指针。
差距是 `Mutex<Int>` 24 字节（8 字节指针 + 16 字节堆块）对 16 字节。

本提案调研了「把标准库那份实现整份移植进 `OSToolbox`」的可行性。结论分两半：

- **技术上完全可行**，且移植后的内存布局与标准库**逐字节一致**（已实测）。
- **但暂不采纳。** 代价是把一个被 7 个项目依赖的基础库，钉死在三个**没有任何 Swift Evolution
  提案**的下划线编译器特性上，并让 `var mutex = ...` 从合法变成编译错误；而当前用量下的收益是
  24 字节和进程启动时的一次 `malloc`。

本文记录可行性证据、性能实测数据，以及**什么条件下应该翻案**，避免下次再想起这件事时从零重测。

## 动机

### 现状

`Sources/OSToolbox/Mutex.swift` 的 `Mutex<Value>` 只有一个存储属性：

```swift
@usableFromInline
internal let _buffer: UnsafeMutableRawPointer
```

`init` 里算出 `[os_unfair_lock | padding | Value]` 的总大小，`allocate` 一块，分别初始化；
`deinit` 里 `deinitialize` 再 `deallocate`。也就是**每个 `Mutex` 实例一次 `malloc` / `free`**。

### 为什么不能直接用标准库的

`Synchronization.Mutex` 全体成员标着 `@available(SwiftStdlib 6.0, *)`，实际门槛是
macOS 15 / iOS 18。本包的 floor 是 `Package.swift:9` 的 macOS 10.15 / iOS 13，差了整整九个大版本。
这正是当初要自己写一份的原因。

### 为什么这次会重新提起

标准库的实现是公开源码，Apache-2.0 加运行时库例外，照搬在许可上没有障碍。问题只在于它依赖了
几个未公开的编译器能力——而这些能力在正式发布的工具链里其实是可用的。值不值得用，就是本提案要回答的。

## 前期调研

### 一、标准库靠什么做到内联，以及为什么我们「做不到」

关键不是 `import Builtin`，是 `@_rawLayout`。

`swift/stdlib/public/Synchronization/Cell.swift`：

```swift
import Builtin

@frozen
@_rawLayout(like: Value, movesAsLike)
public struct _Cell<Value: ~Copyable>: ~Copyable {
    @_transparent
    public var _address: UnsafeMutablePointer<Value> {
        UnsafeMutablePointer<Value>(Builtin.addressOfRawLayout(self))
    }
    // init / deinit 省略
}
```

`Mutex` 本身（`Synchronization/Mutex/Mutex.swift`）与 Darwin 的锁句柄
（`Synchronization/Mutex/DarwinImpl.swift`）各自持有一个 `_Cell`：
`_Cell<os_unfair_lock>` 放锁，`_Cell<Value>` 放值，两者都内联。

**为什么必须是 raw layout，不能是普通存储属性**：`withLock` 是 `borrowing func`——只读借用。
Swift 的独占性检查不允许从只读借用里拿到存储属性的可变指针，而加锁之后要改的正是那个值。
`@_rawLayout` 开出的那块存储**不是**正式存储属性，不受这条约束，
`Builtin.addressOfRawLayout(self)` 因此可以在 `borrowing` 上下文里交出可变指针。

现行实现之所以必须堆分配，就是在绕开这一点：值放在堆上，结构体里只存一个指针，
指针本身只读也无所谓。**这是整个差距的唯一来源**，不是实现粗糙。

### 二、三个开关与最低工具链（均查证自 `/Volumes/SwiftProjects/swift-project/swift` 的完整 git 历史）

| 开关 | 首次可用 | 备注 |
|------|---------|------|
| `BuiltinModule` | Swift 5.9 | commit `c21899ee0ff`（2023-03-28，PR swiftlang/swift#64673）。更早的等价前端旗标 `-enable-builtin-module` 是 2023-02-16 的 `023c40c809d`，同样 5.9 才发布 |
| `RawLayout` | Swift 5.10 | `@_rawLayout` 属性 |
| `StaticExclusiveOnly` | Swift 6.0 | `@_staticExclusiveOnly`，禁止把该类型声明成 `var` |
| `Builtin.addressOfRawLayout` | Swift 6.0 | 在 `Features.def` 里登记为 `BASELINE_LANGUAGE_FEATURE`，随 `BuiltinModule` 一起可用 |

综合最低要求 **Swift 6.0**。本包 `swift-tools-version: 6.2`，本机 6.3.3 / Xcode 26.6，都够。

三个特性在 `include/swift/Basic/Features.def` 里的第二个参数都是 `true`
（`EXPERIMENTAL_FEATURE(RawLayout, true)` 等），意思是**正式发布的工具链里就能开**，
不需要 development snapshot。

**但三者都没有 Swift Evolution 提案**（`RawLayout` 只停在论坛 pitch 阶段）。已在
swift-evolution 全文检索确认无对应条目。

### 三、实测：移植后与标准库逐字节一致

在 `/tmp/claude/mutex-probe/` 写了一份精简移植版（`RawCell` + `InlineMutex`，结构照抄标准库），
用以下命令编译：

```
xcrun swiftc -swift-version 6 -target arm64-apple-macos10.15 \
  -enable-experimental-feature BuiltinModule \
  -enable-experimental-feature RawLayout \
  -enable-experimental-feature StaticExclusiveOnly \
  VendoredMutex.swift main.swift
```

验证结论：

- **编译通过，且目标可以定到 macOS 10.15**——这正是要的东西。Swift 5 与 Swift 6 两种语言模式都过
  （本包用 Swift 5 语言模式）。
- **布局与标准库一致**：`InlineMutex<Int>` 是 16/16/8（size/stride/alignment），
  三个 `Int` 的结构体是 32/32/8；同机用 macOS 15 目标编译的真·`Synchronization.Mutex`
  给出完全相同的数字。
- **调用方不需要开任何 flag**：把移植版编成独立模块（`-emit-module -emit-library`），
  再用一个完全没加 flag 的客户端 import 它、加锁、读 `MemoryLayout`，一切正常，拿到的仍是 16 字节。
  也就是说 flag 只需写在本包的 `swiftSettings` 里，不会传染给使用方。
- **各种持有方式都正常**：全局 `let`、`static let`、类的存储属性都能用；持有 `InlineMutex<Int>`
  的类实例是 32 字节（16 字节对象头 + 16 字节内联锁），确认没有额外分配。
- **并发正确**：8 线程各加锁 1 万次，计数恰为 80000。
- **`@_staticExclusiveOnly` 的约束是真的会拦人**：`var mutable = InlineMutex<Int>(0)` 直接报
  `variable of type 'InlineMutex<Int>' must be declared with a 'let'`。

### 四、实测：性能差异只在创建路径上

两份实现编进同一个二进制对比，`-O -wmo`，重复三次结果稳定（Apple Silicon，macOS 26）：

| 场景 | 现行堆分配版 | 移植内联版 |
|------|------------|-----------|
| 创建 + 销毁一个 `Mutex<Int>` | 21–22 ns | **9 ns** |
| 单把锁反复加解锁 | 7.9 ns | 7.9 ns |
| 10 万个对象各持一把锁、遍历各加锁一次 | 6.6–7.6 ns | 6.5–7.4 ns（噪声内） |

**一条被证伪的假设**：原本预期「多一次指针跳转 = 多一次缓存未命中」会让加解锁本身变慢，
实测完全没有差异——硬件预取器把顺序访问的那点局部性差异抹平了。这个理由不成立，不要再拿它论证。

唯一真实的收益是省掉每实例一次 `malloc` / `free`，约 12 ns。

### 五、当前用量：整个代码库只有一个真实实例

- 本仓库内唯一的真实使用点：
  `Sources/DyldToolbox/DyldInterpose/DyldDynamicInterpose.swift:340`
  的 `private let rewrittenSlotRecordsByApplicationOrder = Mutex<[RewrittenSlotRecord]>([])`
  ——一个全局，进程生命周期内创建一次。
- 其余出现处全是 demo 客户端（`OSToolboxClient/main.swift`、`SwiftStdlibToolboxClient/main.swift`）
  和宏展开测试（`Tests/OSToolboxMacroTests/MutexMacroTests.swift`）。
- **7 个依赖本库的项目里，`@Mutex` 与 `Mutex<...>` 的使用次数是 0**
  （CodeOrganizer、PrivateSymbols、ReverseEngineeringToolbox、XCOrganizer、StarLight、
  swift-helper-service、UIFoundation）。
- 提案 [0003](0003-objc-runtime-toolbox-self-contained-leaf.md) 的前期调研已经记录过同一现象：
  `ObjCRuntimeToolbox` 对 `Mutex` 零使用，「为了 Mutex」的分层预期从未兑现。

所以今天移植过来，省下的是 **24 字节，加上进程启动时的一次 `malloc`**。

## 提议方案

**暂不采纳（Deferred）。维持现行的单次堆分配实现不变。**

三条理由，按分量排：

1. **收益的分母是 1。** 全代码库只有一个实例，且是只创建一次的全局。
2. **唯一测得出差异的路径（创建销毁）恰好是没人走的路径。** 加解锁本身零差异，
   这是本库真正被执行的部分。
3. **代价与收益不成比例。** 一个被 7 个项目依赖的底座，最该买的是「升 Xcode 不会炸」，
   而不是 8 字节。三个无提案的下划线特性随时可能改语法或改语义；`@_staticExclusiveOnly`
   还会把 `var mutex` 从合法变成编译错误，属于源码破坏。

### 非目标

- **不做半套移植。** 见「替代方案考量」第 2 条。
- **不把 `Mutex` 的公开 API 改成需要调用方感知布局的形式。** 无论将来是否内联，
  `withLock` / `withLockIfAvailable` / `withLockUnchecked` / `_unsafeLock` 的签名都保持不变——
  `@Mutex` 宏展开依赖 `_unsafeLock()` 返回 `UnsafeMutablePointer<Value>`（`_modify` 访问器），
  这一契约不动。
- **不引入 benchmark target。** 本次测量是一次性的，数据留在本文即可。

## 替代方案考量

1. **全套移植（三个 flag，照搬标准库）** —— 技术上可行、效果已验证，见「前期调研」。
   否决理由即上述三条。这是将来翻案时该采用的形态。
2. **半套：只开 `BuiltinModule` + `RawLayout`，不加 `@_staticExclusiveOnly`** ——
   能拿到一致的布局，又不破坏 `var` 用法，少绑一个实验性特性。
   **否**：拿掉的是「锁不能在被持有时被移动」的编译期保护。内联之后锁的地址随结构体移动而变，
   若有线程正阻塞在旧地址的 ulock 等待队列上，移动后它永远醒不过来。
   （`os_unfair_lock` 本身是地址无关的——存的是持有者线程端口，解锁状态下移动安全——
   但「被持有时不许移动」仍需有人守。）而换来的 `var` 兼容性目前无人使用。
   拿安全换一个没人用的兼容性，是最差的一档。
3. **提高部署目标，直接 `typealias Mutex = Synchronization.Mutex`** ——
   最干净：拿到标准库的布局，不欠任何实验性特性，本地实现整份删掉。
   **暂不可行**：需要 floor 抬到 macOS 15 / iOS 18，当前是 10.15 / 13。
   但这是**最可能让本提案自然作废的路径**，见「翻案条件」。
4. **什么都不做** —— 本次采纳。

## 影响

### 源码兼容性（source compatibility）

**不适用**——本提案不改代码。

（供将来翻案时参考：全套移植属于**有破坏**。`@_staticExclusiveOnly` 会让所有
`var mutex = Mutex(...)` 编译失败，且这类破坏**无法**用
`@available(*, deprecated, renamed:)` 做平滑过渡——它不是重命名，是声明形式被禁止。
好消息是本仓库与 7 个下游项目里目前都没有这种写法。）

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

无 —— 不改代码。

（将来翻案时需要点名：`OSToolbox` 的改动会沿 re-export 链传导到 `SwiftStdlibToolbox` 与
`FoundationToolbox`，并波及 `DyldToolbox`；仓库外的 `UIFoundation`、CodeOrganizer、
PrivateSymbols、ReverseEngineeringToolbox、XCOrganizer、StarLight、swift-helper-service
都要重新编译，尽管它们目前都不使用 `Mutex`。）

### 文档与示例

本文即全部产物。`Sources/OSToolbox/Mutex.swift` 保持原样，不加「为什么不内联」的注释——
理由在这里，代码里放一句链接不如让人来读全文。

## 翻案条件

出现下列任一情况，应重新评估：

1. **`@Mutex` 真的按设计意图大量用在实例属性上。** 宏展开的是
   `private let _foo = Mutex<T>(...)` 这样的**存储属性**，所以实例数 = 对象数 × 被注解的属性数。
   持有 `Mutex<Int>` 的对象是 40 字节（24 字节对象 + 16 字节堆块）对内联版的 32 字节，
   外加每个属性一次 `malloc`。**量级到几万个对象**时才谈得上收益。
2. **出现频繁创建销毁 `Mutex` 的热路径。** 那是唯一测得出差异的场景，每实例约 12 ns。
3. **部署目标能抬到 macOS 15 / iOS 18。** 此时应走「替代方案」第 3 条，
   直接 `typealias` 到标准库并删掉本地实现，本提案连同移植方案一起作废。
4. **`RawLayout` 或 `StaticExclusiveOnly` 转正**（进了 Swift Evolution 并被接受）。
   代价那一侧的主要理由会消失，届时可重新算账。

翻案时不必重测可行性与布局——「前期调研」三、四两节的数据可直接复用；
只需复核当时的工具链上三个 flag 是否仍然存在、语法是否变化。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-16 | Created as Deferred | 起因是查 `enableExperimentalFeature("BuiltinModule")` 的来历，进而问「能不能把标准库的 `Mutex` 整份搬过来」。调研与实测当场完成，结论是可行但不值得，直接以 `Deferred` 建档而非先 `Draft`。 |
| 2026-09-16 | 证伪一条假设 | 原以为堆分配版每次加锁多一次指针跳转会有缓存代价，实测加解锁耗时两者相同（7.9 ns），该理由作废。 |
| 2026-09-16 | 排除「半套移植」 | 只开 `BuiltinModule` + `RawLayout` 而不加 `@_staticExclusiveOnly` 看似折中，实为拿安全换一个零使用的兼容性，明确否决。 |
| 2026-09-16 | 配套文档判断 | 不写配套专题说明。本提案不产生调用方契约，也不产生「下次维护会踩」的实现决策——数据与理由一体留在本文。 |
| 2026-09-16 | 术语判断 | 不新增术语表条目。`@_rawLayout`、`@_staticExclusiveOnly`、`BuiltinModule` 均为编译器既有名词，非本项目自造。 |
