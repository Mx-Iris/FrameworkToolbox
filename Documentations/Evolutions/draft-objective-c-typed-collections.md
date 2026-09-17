# Draft - 给被类型擦除的 NS 集合类补回 Swift 泛型

- **状态**: Implemented
- **创建日期**: 2026-09-16
- **最后更新**: 2026-09-16
- **所属愿景**: 无
- **配套文档**: [类型化的 NS 集合句柄 —— 用法契约与实现决策](../TypedObjectiveCCollections.md)

## 摘要

`NSArray` / `NSDictionary` / `NSSet` 以及它们的 mutable 版本在 Swift 里是**非泛型**的。
这不是导入器能力不足，而是 clang importer 主动抑制的结果：
`shouldSuppressGenericParamsImport`（`swift/lib/ClangImporter/ImportDecl.cpp:781`）
对 Foundation 里的 `NSArray` / `NSDictionary` / `NSSet` / `NSOrderedSet` /
`NSEnumerator` / `NSMeasurement` **及其全部子类**一律丢弃 ObjC 轻量泛型参数；
Foundation 的 API notes 里 `SwiftBridge:` 与 `SwiftImportAsNonGeneric: true`
永远成对出现，判据就是「这个类有没有桥接到 Swift 原生类型」。

对绝大多数调用点这是对的——泛型参数没有丢失，而是转移到了 `[String]` 身上。
但有一类场景拿不到这份转移：**当引用语义、对象身份或 KVO 是必需的时候**，
必须直接持有那个 `NSArray` / `NSMutableArray` 实例而不是它的 Swift 副本
（`mutableArrayValue(forKey:)`、把可变集合交给 ObjC 侧后双方继续读写、
`NSInvocation` 实参、逆向时从 ObjC API 手里接过的容器）。此时元素类型信息全丢，
每取一个元素写一次 `as!`。

本提案在 `FoundationToolbox` 新增六个泛型 struct 给这些类套上类型，
并实现 `_ObjectiveCBridgeable`，使它们在 `as` / `as?` 以及传给 `Any` / `AnyObject`
形参时自动还原成真正的 NS 集合对象，而不是被包进 `_SwiftValue` 盒子。

## 方案

### 六个类型

| 新类型 | 包装 |
|--------|------|
| `NSArrayOf<Element>` | `NSArray` |
| `NSMutableArrayOf<Element>` | `NSMutableArray` |
| `NSDictionaryOf<Key, Value>` | `NSDictionary` |
| `NSMutableDictionaryOf<Key, Value>` | `NSMutableDictionary` |
| `NSSetOf<Element>` | `NSSet` |
| `NSMutableSetOf<Element>` | `NSMutableSet` |

落点 `Sources/FoundationToolbox/ObjectiveCCollections/`，整体包在
`#if canImport(ObjectiveC)` 里（与本目标现有 16 处守卫一致）。

### 必须是 struct，不能是泛型 class

`_ObjectiveCBridgeable` 在运行时**只对值类型生效**，这是整个方案骨架的来源：

- `swift/stdlib/public/runtime/DynamicCast.cpp:2610` —— 只在
  `srcKind == Struct || srcKind == Enum` 时才尝试 `tryCastFromObjCBridgeableToClass`。
- 同文件 `:2641` —— 反向的 `tryCastFromClassToObjCBridgeable` 只在**目标**是
  struct/enum 时尝试。
- `_bridgeAnythingToObjectiveC` 的文档直说：「If `T` is a class type, it is always
  bridged verbatim, the function returns `x`」。

做成泛型 class 去实现这个协议，协议会被完全绕过。**这一条不容变更。**

顺带确认了另一件事：和 `Array` 抢同一个 `_ObjectiveCType = NSArray` 不冲突。
两个方向的 witness 都按 Swift 侧类型查找，运行时没有「一个 ObjC 类只能对应一个
Swift 类型」的全局表。本仓 `CoreFoundationToolbox/Cast/_CFConvertible.swift`
已经在用这个协议，路子是通的。

### 引用语义 typed handle，变更方法不标 mutating

struct 只是给**同一个** NS 集合实例套一层类型，`rawValue` 直接持有它：

- 复制这个 struct 共享底层对象，`_bridgeToObjectiveC()` 交回去的就是原对象，
  **对象身份守恒** —— KVO、`mutableArrayValue(forKey:)`、传回 ObjC 后双方继续
  读写，全部照常。这正是这套封装存在的理由，值语义 CoW 会把它毁掉。
- 因此 mutable 三兄弟的变更方法（`append` / `insert` / `remove` / 下标 setter）
  **一律不标 `mutating`**，下标 setter 写 `nonmutating set`。`let` 声明的句柄
  照样能改，语义和 `NSMutableArray` 本身一致，不会诱导使用方把它当值类型。
- 代价是它**不是值语义**，两份拷贝互相可见。这必须在类型文档注释和配套指南里说死。
- 同样因为这一点，mutable 三兄弟**不实现 `Hashable`**（内容会变，进 `Set` 就是 bug），
  只实现 `Equatable`（走 `isEqual:`，内容比较，是纯读操作）。

### 元素类型不做约束

`Element` / `Key` / `Value` 不约束为 `AnyObject`，`NSArrayOf<String>` 可以写出来。
存入走 Foundation 自带的 `Any` 形参桥接（`String` → `NSString`），
取出写 `as! Element` 桥回来。

已知代价：不可桥接的 Swift 值类型（自定义 struct）会被静默包进 `_SwiftValue`。
**Swift ↔ Swift 往返是安全的**（盒子能原样拆回），只有 ObjC 侧看到的是不透明对象。
这条写进文档，不加运行时检查——加了也只能在 debug 下报警，且会给每次写入加一次
动态转换。

### 桥接样板收进一个共享协议

六个类型 × 四个桥接方法的样板由一个协议 + 默认实现承担，仿本仓
`_CFConvertible` 的既有形状：

```swift
public protocol ObjectiveCCollectionHandle: _ObjectiveCBridgeable
where _ObjectiveCType: NSObject {
    init(_ rawValue: _ObjectiveCType)
    init()                                  // 空集合，给 nil 来源兜底
    var rawValue: _ObjectiveCType { get }
    static func containsOnlyExpectedElementTypes(_ source: _ObjectiveCType) -> Bool
}
```

各类型只需提供 `containsOnlyExpectedElementTypes`（Array / Set 遍历元素，
Dictionary 遍历键与值），四个 `_bridge…` 方法由默认实现给出。

### `as?` 做完整的元素类型校验

协议要求 `_conditionallyBridgeFromObjectiveC` 必须当场完成检查、不得推迟，
所以 `nsArray as? NSArrayOf<String>` 会逐元素验证，O(n)，和
`nsArray as? [String]` 的成本一致。`_forceBridgeFromObjectiveC`（`as!` 路径）
按协议允许推迟检查，不验证。

**这层类型安全是编译期的，不是运行时的**：校验通过之后，ObjC 侧仍可往同一个
可变集合里塞别的类型。ObjC 的轻量泛型本身就是这个不健全程度，我们不比它更强，
也不假装更强。

### 本批不做的

- **NSOrderedSet / NSMutableOrderedSet / NSCountedSet**：前者在 Swift 里没有原生
  对应物也没有既有桥接，语义要单独设计；后者是多重集，`count(for:)` 那套 API 要
  单独建模。都留到后续提案。
- **NSHashTable / NSMapTable / NSCache**：不在编译器那份名单里，Swift 保留了它们的
  泛型参数，不需要封装。

### 源码兼容性与守卫

纯新增，不改动任何既有符号，无源码破坏。`FoundationToolbox` 是 re-export 链的顶端，
不会向下游传导。新增的六个顶层类型名进入 `import FoundationToolbox` 的命名空间。

按本仓惯例补两处守卫：

- `Sources/FoundationToolboxSoleImportClient/` 加一个文件，钉住「只 `import
  FoundationToolbox` 就能声明并使用这些类型」。
- `Tests/FoundationToolboxTests/ObjectiveCCollectionsTests.swift`，必须覆盖：
  双向桥接、**对象身份守恒**（`bridge` 回去和原对象 `===`）、
  **传给 `Any` 形参后是真 `NSArray` 而非 `_SwiftValue`**（这是整个提案的核心价值，
  没有它这套东西就只是个语法糖）、引用语义下两份拷贝互见、`as?` 的元素校验
  成功与失败两路、`String` ↔ `NSString` 自动桥接、字面量构造。

### 未问就定下的假设

1. 目录名 `ObjectiveCCollections/`、属性名 `rawValue`（与 `CFStringKey` 一致）。
2. `NSArrayOf` 实现 `RandomAccessCollection`；`NSSetOf` / `NSDictionaryOf` 只实现
   `Sequence`（NSSet / NSDictionary 没有可用的整数索引）。mutable 版本因为变更方法
   非 mutating，**不**实现 `RangeReplaceableCollection`。
3. 一律实现 `ExpressibleByArrayLiteral` / `ExpressibleByDictionaryLiteral`、
   `CustomStringConvertible`、`CustomDebugStringConvertible`。
4. 不标 `Sendable`，也不标 `@unchecked Sendable`。
5. 提供 `copy()` / `mutableCopy()` 做真复制，以及 mutable → immutable 的零成本
   同底层构造器。

## 实现中的发现

方案没有预见、实现时才暴露出来的两件事。

### `as?` 会在每个调用点报一条 “always succeeds”

写 `someNSArray as? NSArrayOf<String>` 时，只要源的静态类型正好是被包装的那个类，
编译器就报：

```
warning: conditional cast from 'NSArray' to 'NSArrayOf<String>' always succeeds
```

它把这次转换归类成了无条件的 bridging coercion。**行为上它是错的** —— debug 与 release
两种构建下都验证过，`_conditionallyBridgeFromObjectiveC` 确实被调用、元素校验确实执行、
不匹配时确实返回 `nil`（`ObjectiveCCollectionBridgingTests` 钉住了这两种构建）。
但它指出的事实是对的：语言层面并没有承诺这种 cast 会走条件路径。

两个问题因此一起解决：使用方不该为了用一个正常 API 而被迫消警告，行为也不该取决于将来的
编译器怎么归类这次转换。协议扩展新增

```swift
public init?(validating rawValue: _ObjectiveCType)
```

六个类型全部免费获得，是文档推荐的入口。`as?` 仍然可用且校验有效，只是不再是首选写法。

### 逐平台验证只覆盖了三个平台

`swift build` 只覆盖 macOS，本目录又整体包在 `#if canImport(ObjectiveC)` 里，
所以按惯例逐平台构建。**iOS、macOS、Mac Catalyst 通过；tvOS、watchOS、visionOS 无法验证**
—— 本机只装了这三个平台的 SDK 存根，平台组件本身没装，`xcodebuild` 直接拒绝
（`tvOS 26.5 is not installed`）。

风险评估：这批代码没有任何平台特定 API，用到的 `NSArray` / `NSDictionary` / `NSSet` /
`NSCopying` / KVC 代理在所有 Apple 平台都存在，`canImport(ObjectiveC)` 在六个平台上一律为真。
但没验证就是没验证，装上组件后应当补跑。

### 桥接方法补上标准库那三个属性，但优化并未因此生效（已由下一节解决）

标准库在自己的 `_ObjectiveCBridgeable` 实现上带 `@_semantics("convertToObjectiveC")`
与 `@_effects(readonly)`，本批照做，并补上了**配对的第三个**
`@_semantics("bridgeFromObjectiveC")` —— 少了它前一个就是死标记：
消费这些标记的 `objc-bridging-optimization` pass 要同时认出往返的两半才会动手，
其作用是把「桥到 Swift 又立刻桥回 Objective-C」改写成直接复用原对象。

（`bridgeFromObjectiveC` 没有登记在编译器的 `SemanticAttrs.def` 里，
那里只收编译器自己以常量形式引用的名字，而 `hasSemanticsAttribute` 接受任意字符串。
Foundation 至今两个都没标注，所以那个 pass 还硬编码着 `String` 和 `Array` 的
mangled name 作为兜底。）

**读优化后的 SIL 核对了结果，分两半：**

- **属性确实附上了**，且跨模块序列化后仍在：
  `sil [readonly] [_semantics "bridgeFromObjectiveC"] @…`。
- **但那个 pass 不会触发**，原因是结构性的。pass 要求
  `arguments.count == 2` 且首参约定为 `.directGuaranteed`，
  而协议扩展里的默认实现其 `Self` 是不透明泛型参数，只能按地址传递
  —— 实测得到的是 `@out` 与 `@in_guaranteed`，三个参数。
  那两个条件是照着 `String` / `Array` 这类在调用点已具体化的类型写的。

**`@_effects(readonly)` 不受此影响**，它不经过那个 pass，是通用的 effects 信息，
优化器直接使用。

保留这三个属性的理由是：它们陈述的事实为真（而且比对 `Array` 更严格——句柄包的就是
交给它的那个对象），零成本，且结构将来可能变。

**若目标就是那个优化本身，`@inlinable` 才是有效杠杆，且力度大得多。** 同样实测过：
加上之后整个往返塌缩成一次 `struct_extract`，两个桥接调用全部消失，不经过任何 pass。
但它把函数体变成兼容性承诺，属于独立的 API 决策，未在本批采纳。

### 把 witness 从协议默认实现挪到具体类型，优化才真正生效

上一节的结论是「属性标对了，pass 仍不触发」。补了一组对照实验，三种配置读优化后的 SIL：

| witness 位置 | `@_semantics` | 往返是否消除 |
|---|---|---|
| 协议扩展默认实现 | 有 | **否** |
| 具体类型 | 无 | **否** |
| 具体类型 | 有 | **是**，塌缩成 `return %0` |

**两个条件缺一不可**，这是本批最值得记住的一条。协议扩展里的 `Self` 是不透明泛型参数，
只能按地址传递（`@out` / `@in_guaranteed`），而 pass 要求 `.directGuaranteed`；
挪到具体类型修好了调用约定，但没有 `@_semantics`，pass 根本不认识这两个函数是桥接函数。

于是四个 witness 必须逐类型生成。**用宏，不手写**：六个类型 × 四个方法，
正确性全落在三个下划线属性上，漏标一个则优化静默归零，编译器不给任何提示。
这正是宏该干的活。新增 `@ObjectiveCBridgeable`（公开），
从 `rawValue` 的类型标注读出 `_ObjectiveCType`，生成 typealias 与四个带属性的方法，
访问级别跟随被贴的类型。

**协议随之改形**：`ObjectiveCCollectionHandle` 不再 refine `_ObjectiveCBridgeable`，
也不再提供任何桥接默认实现——留着的话，某个类型忘了贴宏仍然能编译，
只是悄悄退回没有优化的版本。现在协议只描述形状（`rawValue` / 两个 `init` /
元素校验），宏负责性能敏感的具体 witness，一份实现，没有二义。

宏对外公开，使用方可以拿它包第三方 ObjC 库的泛型集合类，
`NSOrderedSet` / `NSCountedSet` 将来也只是贴一行的事。
展开结果由 `ObjectiveCBridgeableMacroTests` 的六条快照逐字钉住——
包括三个属性的位置，这是防止它们被顺手删掉的唯一手段。

### 宏与协议再拆一层：转换逻辑归用户，宏只管 witness

第一版宏把集合语义焊死在了里面——它读 `rawValue`、调用
`containsOnlyExpectedElementTypes(in:)`、拿 `Self()` 兜底 nil，
也就是说它只能给「包着一个 ObjC 集合的 struct」用。这不对：
`_ObjectiveCBridgeable` 跟集合毫无关系。

拆成两层：

- **`ObjectiveCRepresentable`（新增，公开）** —— 转换逻辑住在这里，是普通的、
  有文档的、不带下划线的 API。两个必须实现的成员
  （`makeObjectiveCRepresentation()` 与 `init?(objectiveCRepresentation:)`）
  加两个带默认实现的（`init(uncheckedObjectiveCRepresentation:)` 走完整校验，
  `substituteForMissingObjectiveCRepresentation` 默认 trap）。
  **不假设包装、不假设集合、不假设有存储属性**：
  实现者可以现造一个 ObjC 对象、回来时解析它，也可以像句柄那样原样包住。
- **`@ObjectiveCBridgeable`（改造）** —— 现在对被贴的类型零假设：
  不读属性、不需要被告知 ObjC 类是什么（`_ObjectiveCType` 直接写成协议的关联类型
  `ObjectiveCRepresentation`，由编译器在具体类型上下文里解析），
  四个生成的方法全部只是转发。它唯一贡献的东西是**优化器能看穿的 witness**，
  也就是前一节测出来的那件协议扩展做不到的事。顺带支持 enum——
  `_ObjectiveCBridgeable` 对所有值类型生效，第一版限定 struct 是没必要的。

`ObjectiveCCollectionHandle` 随之变成 `ObjectiveCRepresentable` 的 refinement，
把四个转换成员在自己的扩展里填好（包括覆盖 `init(unchecked:)` 走廉价路径——
元素校验是 O(n)，而 `as!` 本就获准推迟）。六个类型一行没改。

**重新测过 SIL，优化仍然生效**（`return %0`）。多出来的这层转发不影响：
那个 pass 基于 `@_semantics` 属性做信任，根本不看函数体。

### 关联类型推断会在协议扩展处断链

改造后六个类型全部编译失败：`protocol requires nested type 'ObjectiveCRepresentation'`。

原因值得记一笔：Swift 从**直接满足协议要求的成员**推断关联类型，
而这六个类型的转换成员全部来自 `ObjectiveCCollectionHandle` 的扩展，
泛型默认实现里没有任何具体类型可供推断。于是必须显式写
`typealias ObjectiveCRepresentation = NSArray`。

直接遵循 `ObjectiveCRepresentable` 的类型不受影响——
`makeObjectiveCRepresentation() -> NSString` 是直接 witness，推断照常工作。
`ObjectiveCRepresentableTests` 里那个非集合类型就故意不写 typealias，钉住这个差别。

### `@inlinable`：宏参数 + 整条链

`@_semantics` 那套只管「桥过去又桥回来」的往返消除。**单向桥接**——
把句柄交给一个 ObjC API，或者从 ObjC 拿到对象包成句柄——不在那个 pass 的射程内，
实测是一次实打实的跨模块函数调用。

给宏加 `inlinable:` 参数（默认 `false`，只接受布尔字面量，
因为 `@inlinable` 是属性、必须在展开期定死），六个句柄开启，
并把桥接链上的每一环都标上：协议扩展的四个转换成员、
句柄的 `init(rawValue:)` / `init()` / 元素校验，以及校验用到的 internal 辅助函数。

**内联是链式的**，漏标一环就断在那一环——这不是推测，是中途只标了协议扩展那一层时
实测到的：调用方看到的 `_bridgeToObjectiveC` 不可内联，它内部调什么都无所谓。

实测结果（读优化后的 SIL）：

| 场景 | 优化后 |
|------|--------|
| `handle as NSArray` | 一条 `struct_extract` |
| `NSArrayOf(rawValue: x)` | 直接 `return`，构造被内联 |
| 往返 | `return %0`（与之前一致，没被破坏） |

默认关闭是因为 `@inlinable` 把函数体变成兼容性承诺，
这种决定不该由宏替使用方做。

**两条从编译器源码读出来的规则，一条与直觉相反：**

- `@_effects` **无条件**阻止内联（`PerformanceInlinerUtils.cpp` 里
  `if (… || Callee->hasEffectsKind()) return nullptr;`），
  所以带 `@_effects(readonly)` 的 `_unconditionallyBridgeFromObjectiveC`
  标了 `@inlinable` 也不会被内联。属性仍然保留——effects 信息对那次真实调用仍有价值——
  生成的代码里写明了原因。
- `@_semantics` **不**阻止内联。`getSemanticFunctionLevel` 只把 array 与
  fixed_storage 语义判为 `Fundamental`，其余一律 `Transient`，不触发提前返回。
  实测也确认带 `@_semantics` 的 witness 照样被内联。

过程中有一次假阴性值得记下来：第一次测「宏生成的 witness 加 `@inlinable`」时结论是无效，
实为 swiftmodule 构建缓存未更新。**读 SIL 前要确认产物是新的。**

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-16 | Created as Draft | 用户要求：封装 ObjC 侧有泛型、Swift 侧被擦除的集合类型，并实现 `_ObjectiveCBridgeable` 做互操作 |
| 2026-09-16 | 封装类型用 struct，排除泛型 class | `DynamicCast.cpp:2610`/`:2641` 两个方向都只对 struct/enum 尝试桥接；class 永远 verbatim 桥接，协议会被绕过 |
| 2026-09-16 | 取引用语义 typed handle，弃值语义 CoW | 对象身份守恒是这套封装的全部价值（KVO、`mutableArrayValue(forKey:)`、交回 ObjC 后继续读写）；CoW 会把它毁掉，且那样它和 `[Element]` 的区别就只剩底层存储 |
| 2026-09-16 | 变更方法不标 `mutating`，下标 `nonmutating set` | 诚实表达引用语义，避免使用方误以为是值类型 |
| 2026-09-16 | `Element` 不约束 `AnyObject` | `NSArrayOf<String>` 是最常见的写法，约束掉就废了一半用例；代价是不可桥接类型静默进 `_SwiftValue`，仅影响 ObjC 侧观感，Swift 往返安全 |
| 2026-09-16 | 本批只做 Array / Dictionary / Set 六个类型 | Set 与 Array 高度同构，增量极小；OrderedSet 与 CountedSet 语义要单独设计，另行提案 |
| 2026-09-16 | 命名取 `NSArrayOf` 一族 | 与被包装的类一一对应，搜索时能直接命中 NS 前缀 |
| 2026-09-16 | mutable 三兄弟不实现 `Hashable` | 内容可变则 hash 可变，放进 `Set` / 字典键必然出错 |
| 2026-09-16 | 用户批准，状态置为 Accepted，开始实现 | 方案与四项澄清答复一致，无待决问题 |
| 2026-09-16 | 新增 `init?(validating:)`，作为取代 `as?` 的推荐入口 | 编译器对 `as?` 报 “always succeeds”，会落到每个使用方的调用点上；且语言未承诺这种 cast 走条件路径 |
| 2026-09-16 | 不新建 `Documentations/Glossary.md` | 本次只引入「类型化句柄」一个概念，提案与配套指南里都已完整解释，为它单开一份术语表不划算 |
| 2026-09-16 | 状态置为 Implemented | 六个类型、守卫与 37 个测试全部落地；完整测试套件原始退出码 0，构建零警告 |
| 2026-09-17 | 桥接方法补上 `@_semantics("convertToObjectiveC")` / `@_semantics("bridgeFromObjectiveC")` / `@_effects(readonly)` | 与标准库实现对齐；前两个必须成对，只标一个则完全无效 |
| 2026-09-17 | 如实记录那个 pass 当前不触发，而非默认它生效 | 读优化后 SIL 核对：属性在，但协议扩展默认实现的 `Self` 按地址传递，不满足 pass 的参数个数与约定条件 |
| 2026-09-17 | 不在本批采纳 `@inlinable` | 实测它能真正消除往返且优于那个 pass，但它把函数体变成兼容性承诺，属于独立的 API 决策 |
| 2026-09-17 | 四个桥接 witness 改为逐类型生成，不再走协议默认实现 | 对照实验：协议扩展的 `Self` 按地址传递，永远不满足 pass 的 `.directGuaranteed` 要求；挪到具体类型后往返被完全消除 |
| 2026-09-17 | 用宏生成而非手写六份 | 正确性系于三个下划线属性，漏标一个则优化静默归零且无任何诊断；六处靠人保持一致不可持续 |
| 2026-09-17 | 协议删去 `_ObjectiveCBridgeable` refine 与全部桥接默认实现 | 保留默认实现意味着「忘记贴宏」仍能编译、只是悄悄变慢，正是要消除的静默失效 |
| 2026-09-17 | `@ObjectiveCBridgeable` 对外公开 | 使用方可用它封装第三方 ObjC 泛型集合类；后续补 `NSOrderedSet` / `NSCountedSet` 也只需贴一行 |
| 2026-09-17 | 拆出 `ObjectiveCRepresentable`，宏对被贴类型零假设 | 第一版宏把集合语义焊死（读 `rawValue`、调元素校验、`Self()` 兜底），而 `_ObjectiveCBridgeable` 与集合无关；转换逻辑应归用户，宏只贡献优化器能看穿的 witness |
| 2026-09-17 | 宏同时支持 enum | `_ObjectiveCBridgeable` 对所有值类型生效，第一版限定 struct 属于无谓收窄 |
| 2026-09-17 | 六个句柄显式声明 `typealias ObjectiveCRepresentation` | 关联类型推断只看直接 witness；这些类型的转换成员来自协议扩展，泛型默认实现无具体类型可推 |
| 2026-09-17 | 改造后重测 SIL 确认优化未失效 | 多一层协议转发不影响：pass 基于 `@_semantics` 信任，不分析函数体 |
| 2026-09-17 | 宏加 `inlinable:` 参数，默认 `false`，只接受布尔字面量 | `@inlinable` 把函数体变成兼容性承诺，不该由宏替使用方决定；而属性必须在展开期定死，表达式无处求值 |
| 2026-09-17 | 六个句柄开启，并标注桥接链上每一环 | 内联是链式的，只标一层时实测无效；全链标注后单向桥接塌缩成一条 `struct_extract` |
| 2026-09-17 | 带 `@_effects(readonly)` 的 witness 仍标 `@inlinable`，并注明其不生效 | `@_effects` 无条件阻止内联（编译器源码），但 effects 信息对真实调用仍有价值；不注明就会变成又一个「看着像优化实则无效」的标注 |
