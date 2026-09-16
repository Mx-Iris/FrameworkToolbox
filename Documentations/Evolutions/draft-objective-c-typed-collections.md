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
