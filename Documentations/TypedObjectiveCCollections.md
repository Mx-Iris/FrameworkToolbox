# 类型化的 NS 集合句柄 —— 用法契约与实现决策

`NSArrayOf` / `NSMutableArrayOf` / `NSDictionaryOf` / `NSMutableDictionaryOf` /
`NSSetOf` / `NSMutableSetOf` 六个泛型 struct，给 Swift 里被擦掉泛型参数的 NS 集合类
重新套上元素类型，并实现 `_ObjectiveCBridgeable` 与 Objective-C 互操作。

设计经过与取舍见提案
[给被类型擦除的 NS 集合类补回 Swift 泛型](Evolutions/draft-objective-c-typed-collections.md)。
这篇只讲怎么用，以及有哪些**签名上看不出来、违反了就出事**的约定。

## 先判断你是不是真的需要它

**绝大多数时候你不需要。** ObjC 的 `NSArray<NSString *> *` 导入 Swift 时直接就是
`[String]` —— 泛型参数没有丢失，它跟着桥接转移到了 Swift 原生数组身上。能用 `[Element]`
的地方就用 `[Element]`。

只有当**桥接本身是你要避开的东西**时才用这六个类型，也就是那个 NS 对象本身必须活下来：

- 从 `mutableArrayValue(forKey:)` 拿到的 KVC 代理数组，改动要写回宿主对象；
- 把可变集合交给 ObjC 侧之后，双方还要继续读写同一份数据；
- 要触发或接收 key-value observing；
- 逆向、`NSInvocation`、`userInfo` 这类手上只有一个 `NSArray` 实例的场合。

## 六个类型

| 类型 | 包装 | Hashable |
|------|------|----------|
| `NSArrayOf<Element>` | `NSArray` | 是 |
| `NSMutableArrayOf<Element>` | `NSMutableArray` | 否 |
| `NSDictionaryOf<Key, Value>` | `NSDictionary` | 是 |
| `NSMutableDictionaryOf<Key, Value>` | `NSMutableDictionary` | 否 |
| `NSSetOf<Element>` | `NSSet` | 是 |
| `NSMutableSetOf<Element>` | `NSMutableSet` | 否 |

```swift
import FoundationToolbox

// 包住已有对象，不复制
let tracks = NSMutableArrayOf<String>(rawValue: playlist.mutableArrayValue(forKey: "tracks"))
tracks.append("Blue in Green")     // 宿主对象同步可见，KVO 照常触发

// 从 Swift 值建
let names: NSArrayOf<String> = ["Ada", "Grace"]
let tempos: NSMutableDictionaryOf<String, Int> = ["Blue in Green": 120]

// 元素类型未经验证的来源
guard let verified = NSArrayOf<String>(validating: someNSArray) else { return }
```

## 六条契约

### 一、它是引用语义，复制句柄等于共享对象

句柄只是给同一个 NS 对象套了层类型，**不是**值类型集合。

```swift
let first = NSMutableArrayOf<String>()
let second = first
second.append("Ada")
first.count            // 1 —— first 也变了
```

要真正的副本用 `copy()` / `mutableCopy()`；要明确表达「我就是要共享」用
`NSArrayOf(sharing:)`。

### 二、变更方法**不是** `mutating`，`let` 句柄照样能改

这是故意的，用来诚实表达上一条。把它们标成 `mutating` 会让人以为是值语义。

```swift
let names = NSMutableArrayOf<String>()
names.append("Ada")    // 合法，和 NSMutableArray 本身一致
```

副作用是 Swift 编译器帮不了你：它不会因为句柄声明成 `let` 就拦住修改。**判断一次改动会不
会影响别人，靠的是知道谁共享了这个对象，不是靠 `let`。**

### 三、用 `init(validating:)`，不要写 `as?`

两者都会逐元素校验，运行时行为一致（debug 与 release 都有测试钉住）。但 `as?` 在源的静态
类型正好是被包装的类时，会在**每一个调用点**报一条：

```
warning: conditional cast from 'NSArray' to 'NSArrayOf<String>' always succeeds
```

这条诊断对行为的描述是错的（校验确实执行了），但它指出的事实是对的：语言层面没有承诺
这种 cast 会走条件桥接。`init(validating:)` 是普通 Swift 代码，不涉及 cast 机制，
没有警告，行为也不取决于将来的编译器怎么归类这次转换。

### 四、类型安全是编译期的，运行时守不住

`init(validating:)` 通过之后，持有同一个对象的 ObjC 代码照样能往里塞任何东西。真塞了，
读取时会带一条说明信息 trap，而不是静默返回错值。

ObjC 自己的轻量泛型就是这个不健全程度 —— 它纯粹是编译期注解，运行时没有任何信息。
**这六个类型不比它更强，也不假装更强。**

### 五、不可桥接的 Swift 值类型会变成不透明盒子

`Element` 不限制为 `AnyObject`，所以 `NSArrayOf<String>` 写得出来 —— `String` 存进去是
`NSString`，取出来是 `String`。但一个没有 ObjC 对应物的自定义 struct 会被装进
`_SwiftValue`：

```swift
let items = NSMutableArrayOf<MyStruct>()
items.append(MyStruct())    // 静默装箱
items[0]                    // 正常取回，Swift 侧往返是安全的
```

**Swift ↔ Swift 往返没问题**，箱子会原样拆开。只有 ObjC 侧看到的是个不认识的对象。
要交给 ObjC 处理的数据，元素类型请选可桥接的。

### 六、可变句柄不是 `Hashable`

内容会变，而 hash 不会跟着变。放进 `Set` 或当字典键会静默出错，所以三个可变类型直接不提供
`Hashable`。要放进去，先 `copy()` 成不可变的那个。

它们仍然是 `Equatable`，走 `NSArray.isEqual(_:)` 比内容，是纯读操作。

## 给自己的集合类做同样的封装

`@ObjectiveCBridgeable` 与 `ObjectiveCRepresentable` 都是公开的，
拿它们可以给第三方 ObjC 库的泛型集合类、或是本批没做的 `NSOrderedSet` / `NSCountedSet`
做同样的封装：

```swift
@ObjectiveCBridgeable
public struct NSOrderedSetOf<Element>: ObjectiveCCollectionHandle {
    public typealias ObjectiveCRepresentation = NSOrderedSet   // 见下方说明，这行不能省
    public let rawValue: NSOrderedSet

    public init(rawValue: NSOrderedSet) { self.rawValue = rawValue }
    public init() { self.init(rawValue: NSOrderedSet()) }

    public static func containsOnlyExpectedElementTypes(in rawValue: NSOrderedSet) -> Bool {
        rawValue.allSatisfy { $0 is Element }
    }
}
```

遵循 `ObjectiveCCollectionHandle` 就拿到了全部四个转换成员的默认实现，
只需提供 `rawValue`、两个 `init` 和元素校验。**`typealias` 那行不能省**：
转换成员来自协议扩展，泛型默认实现里没有具体类型可供推断关联类型。

不是集合、不包装对象的类型，直接遵循 `ObjectiveCRepresentable` 自定义转换 ——
两个协议、宏的契约、以及为什么这些 witness 必须逐类型生成，
都在[让自己的类型参与 Swift ↔ Objective-C 桥接](ObjectiveCBridging.md)。

## 两条实现决策

**为什么是 struct 而不是泛型 class。** `_ObjectiveCBridgeable` 在运行时只对值类型生效：
`DynamicCast.cpp` 里 `tryCastFromObjCBridgeableToClass` 只在源是 struct/enum 时尝试，
反方向的 `tryCastFromClassToObjCBridgeable` 只在目标是 struct/enum 时尝试，而
`_bridgeAnythingToObjectiveC` 的文档直说 class 类型「永远原样桥接」。做成泛型 class，
整个协议会被绕过，句柄传给 `Any` 形参时就变成一个 `_SwiftValue` 盒子而不是 `NSArray`。

**为什么 Swift 里本来没有泛型。** 不是导入器做不到，是 clang importer 主动抑制的：
`shouldSuppressGenericParamsImport`（`lib/ClangImporter/ImportDecl.cpp`）对
`NSArray` / `NSDictionary` / `NSSet` / `NSOrderedSet` / `NSEnumerator` / `NSMeasurement`
及其全部子类丢弃轻量泛型参数，Foundation 的 API notes 里 `SwiftBridge:` 与
`SwiftImportAsNonGeneric: true` 成对出现。判据就是有没有桥接到 Swift 原生类型。
完整理由（桥接在类型系统上的死结、协变方向相反、`AnyObject` 约束会毁掉最常见写法）
见提案。

顺带一提：`NSHashTable` / `NSMapTable` / `NSCache` **不在**那份名单里，Swift 保留了它们的
泛型参数，不需要这里的封装。
