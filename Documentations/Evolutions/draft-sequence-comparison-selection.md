# Draft - 让序列比较可以指定用哪一套排序定义

- **状态**: Implemented
- **创建日期**: 2026-09-22
- **最后更新**: 2026-09-22
- **所属愿景**: 无
- **配套文档**: [指定排序定义 —— 用法契约与陷阱](../ComparisonSelection.md)

## 摘要

`ComparableBuildable` 现在每个类型只能有一套排序规则：协议要求的 `comparableDefinition`，
`<` 和 `==` 都走它。一个类型想换个规则排序 —— 同一份 `Person` 一会儿按姓名、一会儿按年龄 ——
只能退回手写闭包，前面那套步骤 DSL 全用不上。

本提案在 `FrameworkToolbox` box 上加一组比较方法，把「用哪套规则」交给调用点决定，有两条路：

1. **选一个具名定义**：类型上除 `comparableDefinition` 之外再声明若干 `static var`，
   调用端用 metatype keyPath 选中 —— `people.box.sorted(using: \.byAge)`。
2. **直接给属性 keyPath**：`people.box.sorted(by: \.age, .descending)`，
   不要求类型遵循 `ComparableBuildable`，任意 `Sequence` 可用。

两条路都实测与手写比较器持平，但第一条有一个**不写对就慢 5.7 倍**的实现约束，见第 3 节。

顺带修掉 `FrameworkToolboxCompatible.box` 的空 setter。它让**所有**经 `.box` 调用的
mutating 方法静默无效 —— 包括本提案要加的 `sort(using:)`，以及现有 `Comparable+.swift`
里整个 `clamp` 系列。

## 方案

### 1. 额外的排序定义就是普通 static 属性

不引入新协议、不改 `ComparableBuildable` 的要求。定义端只比现状多一个 builder 标注 ——
协议要求那个由协议自带 `@ComparableBuilder<Self>`，额外声明的要自己写出来：

```swift
struct Person: ComparableBuildable {
    var name: String
    var age: Int

    static var comparableDefinition: some ComparisonStep<Self> {
        compare(\.name)
    }

    @ComparableBuilder<Person>
    static var byAge: some ComparisonStep<Person> {
        compare(\.age)
        compare(\.name)
    }
}
```

`static var` 而非 `static let` 的理由与现状一致，写在 `ComparableBuildable.swift` 的文档注释里 ——
且与第 3 节是同一条原理。

### 2. 调用端：用 metatype keyPath 选定义

新方法全部加在 `FrameworkToolbox` 上，参数是 `KeyPath<Base.Element.Type, Step>` ——
根类型是**元类型**，所以 `\.byAge` 找的是 static 成员。

| 方法 | 约束 |
|------|------|
| `sorted(using:)` | `Base: Sequence` |
| `sort(using:)` | `Base: MutableCollection & RandomAccessCollection` |
| `min(using:)` / `max(using:)` | `Base: Sequence` |
| `isSorted(using:)` | `Base: Sequence` |
| `compare(to:using:)` → `ComparisonResult` | 无约束，作用在单个值上 |
| `isLess(than:using:)` → `Bool` | 同上 |

前六个的泛型签名统一是 `<Step: ComparisonStep>(using: KeyPath<Base.Element.Type, Step>)
where Step.T == Base.Element`；后两个的根类型是 `Base.Type`。

**不需要 `Base.Element: ComparableBuildable` 约束。** 约束只落在
「这个 static 属性的类型遵循 `ComparisonStep` 且 `T` 对得上」，所以一个既不遵循
`ComparableBuildable`、也因此不必被迫成为 `Comparable` 的类型，同样可以声明定义并被这组方法使用。

### 3. 硬约束：keyPath 必须在比较闭包**内部**应用

两种写法编译结果一样、行为一样，性能差 5.7 倍：

```swift
// ❌ 慢 5.7 倍 —— 把 keyPath 提前取出来存进局部变量
let step = Base.Element.self[keyPath: keyPath]
return base.sorted { step.compare($0, $1) == .ascending }

// ✅ 与手写持平 —— 每次比较重新应用
return base.sorted { Base.Element.self[keyPath: keyPath].compare($0, $1) == .ascending }
```

看着像是后者更费（每次比较都重新构造一遍步骤树），实际正相反：**后者会被整棵折叠掉，前者不会。**

原因在编译器里，`swift/lib/SILOptimizer/Utils/KeyPathProjector.cpp` 的 `getLiteralKeyPath`：

```cpp
keyPath = lookThroughOwnershipInsts(keyPath);
while (isa<UpcastInst>(keyPath) || isa<OpenExistentialRefInst>(keyPath)) { … }
return dyn_cast<KeyPathInst>(keyPath);
```

它只穿透所有权指令和 `upcast` / `open_existential_ref`，然后要求操作数**就是**那条 keypath
字面量指令。拿不到就返回 `nullptr`，`KeyPathProjector::create` 随之失败，
`tryOptimizeKeypathApplication`（`SILCombinerApplyVisitors.cpp`）放弃优化 ——
每次比较老老实实调一次 `swift_getAtKeyPath` 运行时函数。

keyPath 一旦被存进局部变量让闭包捕获、或者存进一个 struct 的字段再读出来，
操作数就成了 `struct_extract` / `load` / 函数参数，上面那个 `dyn_cast` 落空。
而 `ComparableBuildable` 的整棵步骤树干的正是「把 keyPath 存进 struct 字段」
（`KeyPathComparisonStep.keyPath`），所以它只有在**构造点和使用点落在同一个函数体内**
才会被折叠 —— 那时 SROA 能把 struct 拆开，`struct_extract` 折回字面量。
`comparableDefinition` 在 `<` 里被内联时发生的就是这件事，
文档注释里「`static let` 慢 5–10 倍」说的也是同一条原理。

**这正是标准库 `map(\.name)` 的形状。** 标准库没有 keyPath 版本的 `map` / `sorted` / `min`；
`\.name` 能当函数用是 SE-0249，编译器在类型检查阶段把它重写成一个闭包
（`swift/lib/Sema/CSApply.cpp`，构造 `KeyPathApplicationExpr` 那一段）：

```swift
{ [$kp$ = \Root.name] in $0[keyPath: $kp$] }
```

keyPath 以**裸值**形式进捕获列表，应用点在闭包体内。内联之后字面量仍在原地，
所以 `map(\.name)` 是零开销的。我们把 keyPath 写进比较闭包，等价于复刻这个形状。

实测（30 万元素，取 7 次最好成绩；单模块 whole-module 与跨模块 SPM release 两组数字一致，
下表取跨模块那组）：

| 调用形状 | 用时 | 相对手写 |
|------|------|------|
| 手写比较器（基线） | 23.42 ms | 1.00x |
| keyPath 在闭包内应用 | 23.33 ms | **1.00x** |
| definition 写成类型，闭包内取 | 23.26 ms | 1.00x |
| step 经 `@autoclosure` 传入 | 23.27 ms | 1.00x |
| keyPath 提前取出存局部变量 | 133.9 ms | 5.7x |
| step 作为普通值参数传入 | 131.7 ms | 5.6x |
| 属性 keyPath（单字段，对照手写 11.94 ms） | 12.08 ms | 1.01x |

两条附带结论，都实测过，不写下来必然被重新踩：

- **`@_transparent` 不能用在这些方法上。** 换成它之后同一份代码从 23 ms 掉到 272 ms ——
  mandatory 阶段就内联，打乱了后面的折叠。`@inlinable @inline(__always)` 才是对的组合。
- **给定义的 getter 加 `@inline(__always)` 没有用**，步骤树只有一层（单个
  `KeyPathComparisonStep`，没有嵌套）也没有用（仍然 6.4x）。决定性的只有「构造点与使用点是否同函数」这一条。

### 4. 调用端：直接给属性 keyPath

```swift
people.box.sorted(by: \.age)
people.box.sorted(by: \.age, .descending)
```

这条不受第 3 节约束 —— keyPath 直接作为实参、直接在闭包里应用，本来就是
`getLiteralKeyPath` 认得的形状（实测 12.08 ms 对手写 11.94 ms）。

需要一个表示方向的枚举。不能用 Foundation 的 `SortOrder` —— `SwiftStdlibToolbox`
整条依赖链不含 Foundation。新增：

```swift
public enum SortOrdering {
    case ascending
    case descending
}
```

降序实现成 `base.sorted { $1[keyPath: keyPath] < $0[keyPath: keyPath] }` 而不是升序后反转，
这样等值元素保持原有相对次序。

与现有 `Sequence+.swift` 的 `min(by: keyPath)` / `max(by: keyPath)` 不冲突：
参数标签 `by:` 接属性 keyPath、`using:` 接定义 keyPath，且两者根类型不同
（`Base.Element` 对 `Base.Element.Type`），重载解析没有歧义。

### 5. 给 builder 加 `buildExpression`，让裸 keyPath 直接成步骤

`compare(_:)` / `compareDescending(_:)` / `compareCustom(_:_:)` 三个工厂方法挂在
`extension ComparableBuildable` 上。一个不遵循该协议的类型写不出 `compare(\.age)`，
只能写全 `KeyPathComparisonStep(\Reading.timestamp)` —— 连 keyPath 的根类型都得手写，
因为初始化器的泛型参数推不出来（实测报 `cannot infer key path type from context`）。

给 `ComparableBuilder` 加三个 `buildExpression` 重载（普通 keyPath、可选 keyPath、透传已有步骤）后，
定义可以直接写裸 keyPath：

```swift
struct Reading {                       // 不遵循 ComparableBuildable
    var timestamp: Int
    var celsius: Double
    var note: String?

    @ComparableBuilder<Reading>
    static var byTimestamp: some ComparisonStep<Reading> {
        \.timestamp
        DescendingKeyPathComparisonStep(\Reading.celsius)
        \.note
    }
}
```

这是纯新增，现有 `compare(\.a)` 写法不受影响（已编译验证）。

### 6. 修掉 `box` 的空 setter

`FrameworkToolboxCompatible` 的默认实现是：

```swift
public var box: FrameworkToolbox<Self> {
    set {}                             // ← 空
    get { FrameworkToolbox(self) }
}
```

getter 每次返回一个新的 `FrameworkToolbox` 值，mutating 方法改的是那个临时值，
setter 又把写回丢掉。后果是经 `.box` 调用的 mutating 方法**全部静默无效**，编译无警告。
实测：

```
before clamp: 42
after  clamp: 42        // 期望 10
```

改成 `set { self = newValue.base }` 之后上述两例都正确，本提案的 `sort(using:)` 也才成立。
`where Self: AnyObject` 的那份重载保持 `set {}` —— class 的协议扩展 setter 不是 mutating，
赋不了 `self`，而引用语义下改 `base` 的属性本来就作用在同一个对象上。
`static var box` 同理保持不变，元类型没有可写回的东西。

这一条按「显而易见的 bug 修复」处理，但它改变既有行为（`clamp` 系列从无效变成生效），
所以在此登记而不是默默带过。

#### 实现时发现：同一个缺陷有第二份拷贝，且修它要改宏的 API

改完协议扩展后测试仍然全红。原因是包里真正在用的 `box` 大多**不是**那份默认实现 ——
`Sequence`、`Collection`、`BinaryInteger`、`BinaryFloatingPoint`、`Error`、`CFType`
都是通过 `@FrameworkToolboxExtension` 宏把实现**复制**进协议扩展的，而宏生成的 setter
也是 `set {}`。`Array` 与 `Int` 的 `box` 走的正是这一份，所以 `sort(using:)` 和
`clamp` 依旧无效。这是全局规则「确认为真的问题必须横向排查同类」该抓到的那一类。

宏不能无条件生成 `self = newValue.base`：`CFType` 是 `public protocol CFType: AnyObject`，
class-bound 协议扩展里的 setter 不是 `mutating`，赋不了 `self`。而编译器**不给诊断，直接崩**：

```
error: compile command failed due to signal 5
4. While silgen emitFunction SIL function "@$s21CoreFoundationToolbox6CFTypePAAE3box09FrameworkC0AEVyxGvs"
   for setter for box (at @__swiftmacro_…_FrameworkToolboxExtensionfMm_.swift:9:12)
```

（这一崩还顺带暴露出增量构建会掩盖问题：改宏之后 `swift build` 报 success，
只因为 `CoreFoundationToolbox` 根本没被重编译。判断「有没有问题」必须清掉
agent 自己的构建目录重来。）

所以给宏加了一个参数：

```swift
@attached(member, names: arbitrary)
public macro FrameworkToolboxExtension(
    _ accessLevel: AccessLevel? = nil,
    referenceSemantics: Bool = false
)
```

`referenceSemantics: true` 时 setter 保持空 —— 引用语义下写回既不可能也不需要。
只有 `CFType` 一处要传。这是**宏 API 的扩展**，超出了提案原本的范围，
但不改就修不成，且属于纯增量（新增带默认值的参数，且是字面量参数，在展开期读取）。

### 源码兼容性

- 新增方法、新增枚举 `SortOrdering`、新增 `buildExpression` 重载，都是纯增量。
- `box` setter 的修复是行为变更，不是签名变更：原先无效的调用开始生效。
  下游若有代码依赖「`clamp` 不起作用」这一事实，行为会改变 —— 但那不是任何人会主动依赖的性质。
- 不改包拓扑，不动 re-export 链，不涉及宏展开结果。

### 测试

- `sorted` / `sort` / `min` / `max` / `isSorted` / `compare(to:using:)` 各自对
  `comparableDefinition` 与一个具名定义跑一遍，断言与手写比较器同序。
- `sort(using:)` 的原地写回 —— 这条就是 box setter 修复的回归测试，
  修复前必须失败（已确认失败）。
- 现有 `clamp` 系列补上写回断言，同一批次提交。
- 一个不遵循 `ComparableBuildable` 的类型声明定义并被 `sorted(using:)` 使用，
  钉住第 2 节那条「约束只落在 `ComparisonStep` 上」。
- `sorted(by:)` 降序的稳定性：等值元素保持原有相对次序。
- **第 3 节的 5.7 倍落差要进 `ComparableBuildableBenchmarks`**：加一组
  `sorted(using:)` 对手写的基准。这是一条没有测试能抓住的性质 —— 写错了照样编译、照样正确，
  只是慢 5.7 倍，和 re-export 一样属于「坏了也没有东西会失败」的那类。

  已落地为 `sorted(using:) 100k Int-triples`，同时跑正确写法与 hoist 写法（后者以
  `sortedWithHoistedStep` 保留在基准文件里，专为此对照而存在）。
  `swift test -c release --filter ComparableBuildableBenchmarks` 实测：

  ```
  === sorted(using:) 100k Int-triples (best of 3 runs) ===
    manual                   7.442 ms   [ 1.00x vs manual]
    in-closure key path      7.088 ms   [ 0.95x vs manual]
    hoisted key path        42.611 ms   [ 5.73x vs manual]
  ```

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-22 | Created as Draft | 用户要求：`ComparableBuildable` 目前只有一个默认 definition，希望扩展 Sequence/Array 的比较方法，可以指定类型上的某一个 definition，并支持 keyPath 指定 |
| 2026-09-22 | 「keyPath 指定」同时做两件事：选定义 + 按属性排序 | 用户在澄清提问中选择「两个都要」；两者互不依赖，后者不要求遵循 `ComparableBuildable` |
| 2026-09-22 | 选定义用 metatype keyPath，不引入类型擦除容器 | 用户选择。实测三种写法都能编译：传值、metatype keyPath、leading dot。leading dot 只在参数是**具体类型**时成立 —— 参数写成泛型 `Step: ComparisonStep` 时编译器报 `type 'ComparisonStep' has no member 'byAge'`，因为 leading dot 只在协议自身的扩展里查找。要支持 `.byAge` 就必须引入一个持有闭包的 `ComparisonDefinition<T>` 容器，那会把步骤树的具体类型擦掉一层 |
| 2026-09-22 | 不引入 `ComparisonDefinition<T>` 容器，附带避开一处命名冲突 | 该容器自身必须遵循 `ComparisonStep`，于是它的扩展里 `compare(\.age)` 会解析到协议要求的 `compare(_:_:)` 实例方法上，报 `cannot convert value of type 'KeyPath<Root, Value>'`；定义端被迫写 `Person.compare(\.age)`。工厂方法与协议要求同名是这个冲突的根源 |
| 2026-09-22 | 方向枚举新建 `SortOrdering`，不复用 `ComparisonResult` | `ComparisonResult` 带 `.equal`，作为排序方向是非法输入；Foundation 的 `SortOrder` 用不了，这条依赖链不含 Foundation |
| 2026-09-22 | 把 `box` 的空 setter 修复纳入同一批次 | `sort(using:)` 不修它就不成立；同一个缺陷正让现有 `clamp` 系列全部静默失效 |
| 2026-09-22 | 状态置为 Accepted，开始实现 | 用户批准 |
| 2026-09-22 | 属性 keyPath 版补一个原地的 `sort(by:_:)` | 第 2 节的定义版已有 `sort(using:)`，只给 `sorted(by:)` 不给 `sort(by:)` 会不对称。小且显然 |
| 2026-09-22 | 给 `@FrameworkToolboxExtension` 加 `referenceSemantics:` 参数 | 空 setter 的第二份拷贝在宏里，而 `CFType` 是 class-bound，无条件写回会让编译器在 SILGen 崩溃（不是报错，是崩）。详见第 6 节 |
| 2026-09-22 | 先写红：修复前六个写回测试全部失败 | 过程中抓到一个假阳性 —— fixture 的声明顺序恰好等于期望结果，`sort(using:)` 那条在缺陷仍在时也能通过。已把 fixture 的声明顺序调成与每一种定义的结果都不同 |
| 2026-09-22 | keyPath 一律在比较闭包内应用，禁止 hoist 到局部变量；禁用 `@_transparent` | 一度测出 metatype keyPath 慢 5.7 倍并准备劝退这个语法，实为实现写法所致。顺着「标准库 `map(\.name)` 怎么做到零开销」查进编译器源码后定位到 `getLiteralKeyPath` 的 `dyn_cast<KeyPathInst>`，改成闭包内应用即回到 1.00x，跨模块同样成立。写法差异不改变行为、不产生诊断，所以必须写成硬约束并配基准 |
| 2026-09-22 | 状态置为 Implemented | 全量测试 611 项通过（原始退出码 0），干净构建零警告，release 基准确认 0.95x / 5.73x |
| 2026-09-22 | 配套文档：写了一篇用法说明；不新建术语表 | 这套 API 有四条签名里看不见的契约（`static var` 而非 `let`、不必遵循 `ComparableBuildable`、两元素比较要 `FrameworkToolboxCompatible`、`by:` 与 `using:` 的分工），够一篇 guide。新术语只有「排序定义 / comparison definition」一个，且本项目至今没有 `Glossary.md`，不为一个词新建 |
| 2026-09-22 | 保留 `draft-` 前缀，不分配编号 | 跟随项目现状：已 Implemented 的 `draft-objective-c-typed-collections` 等五份都保持 draft 前缀 |
