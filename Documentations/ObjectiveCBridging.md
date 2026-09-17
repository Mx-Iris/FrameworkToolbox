# 让自己的类型参与 Swift ↔ Objective-C 桥接

`ObjectiveCRepresentable` 协议 + `@ObjectiveCBridgeable` 宏，让任意 Swift 值类型获得
`_ObjectiveCBridgeable` 能力：传给 `Any` / `AnyObject` 形参时变成真正的 ObjC 对象而不是
不透明的 `_SwiftValue` 盒子，`as` / `as?` 双向可用。

集合类的现成封装见[类型化的 NS 集合句柄](TypedObjectiveCCollections.md)，
那是本文这套机制的一个用例。

## 两步

```swift
import FoundationToolbox

@ObjectiveCBridgeable
struct SemanticVersion: ObjectiveCRepresentable {
    var major: Int
    var minor: Int

    // Swift -> ObjC
    func makeObjectiveCRepresentation() -> NSString {
        "\(major).\(minor)" as NSString
    }

    // ObjC -> Swift，完整校验，不能表示就返回 nil
    init?(objectiveCRepresentation source: NSString) {
        let components = (source as String).split(separator: ".")
        guard components.count == 2,
              let major = Int(components[0]),
              let minor = Int(components[1])
        else { return nil }
        self.major = major
        self.minor = minor
    }
}
```

必须实现的就这两个。另外两个协议成员有默认实现：

| 成员 | 对应 | 默认行为 |
|------|------|----------|
| `makeObjectiveCRepresentation()` | `as AnyObject` / 传给 `Any` 形参 | 必须实现 |
| `init?(objectiveCRepresentation:)` | `as?` | 必须实现 |
| `init(uncheckedObjectiveCRepresentation:)` | `as!` | 走完整校验，失败则 trap |
| `substituteForMissingObjectiveCRepresentation` | nonnull 却返回 nil | trap |

**协议不要求你包装对象。** 上面这个类型每次构造一个新 `NSString`，
往返保住的是「值」；集合句柄那种包着同一个对象的写法保住的是「身份」。两种都合法。

## 四条契约

### 一、只能贴在 struct 或 enum 上

`_ObjectiveCBridgeable` 在运行时只对值类型生效 —— class 永远原样桥接，
`_bridgeAnythingToObjectiveC` 的文档就是这么写的。贴在 class 上宏会直接报错，
而不是生成一堆永远不会被调用的成员。

### 二、`init(unchecked:)` 是允许偷懒的那一个

`as!` 走这条路径，而桥接协议**明确允许**它把校验推迟 ——
`nsArray as! [String]` 就是这么跳过逐元素检查的。默认实现老老实实跑完整校验，
对大多数类型没问题；**校验昂贵时应该覆盖它走廉价路径**，集合句柄就是这么做的。

### 三、`substituteForMissingObjectiveCRepresentation` 默认会 trap

ObjC 方法签名写了 `nonnull` 却返回 `nil`，桥接层允许这种事发生（注解会骗人）。
多数类型没有合理的空值可给，所以默认 trap 并说清楚发生了什么 ——
静默编一个值会把上游的契约违约藏起来。有自然空值的类型自己覆盖它。

### 四、关联类型有时要手写

`ObjectiveCRepresentation` 通常能从 `makeObjectiveCRepresentation()` 的返回类型推断出来。
但如果你的转换成员来自某个协议扩展的默认实现（比如遵循 `ObjectiveCCollectionHandle`），
**推断会断链** —— 泛型默认实现里没有任何具体类型可供推断。这时要显式写：

```swift
typealias ObjectiveCRepresentation = NSArray
```

报错信息是 `protocol requires nested type 'ObjectiveCRepresentation'`，
照着补一行即可。

## `inlinable:` —— 想让桥接被内联时

默认关闭。打开后宏给四个 witness 加上 `@inlinable`：

```swift
@ObjectiveCBridgeable(inlinable: true)
public struct NSArrayOf<Element>: ObjectiveCCollectionHandle { … }
```

只接受**布尔字面量**：`@inlinable` 是个属性，要不要发射必须在宏展开时定死，
传表达式会直接报错而不是被忽略。

默认关是因为 `@inlinable` 把函数体变成兼容性承诺 —— 调用方模块会内联进去，
以后再改这几行就是源码层面的变更。这不该由宏替所有人决定。
本库自己的六个句柄开了。

### 内联是链式的，少标一环就断在那一环

`@inlinable` 只让**被标注的那一层**函数体跨模块可见。桥接的调用链是：

```
调用方  handle as NSArray
  └─ _bridgeToObjectiveC()             ← 宏生成，靠 inlinable: true
       └─ makeObjectiveCRepresentation()  ← 协议扩展，要自己标
            └─ rawValue                   ← 存储属性，不用标
```

反方向还要经过 `init(rawValue:)`、`init()`、`containsOnlyExpectedElementTypes(in:)`，
以及后者调用到的 internal 辅助函数（internal 函数标 `@inlinable` 即可，
它自带跨模块可见性）。**漏标任何一环，内联就停在那一环。**

本库这六个句柄整条链都标了，实测结果：

| 场景 | 优化后 |
|------|--------|
| `handle as NSArray` | 一条 `struct_extract`，跨模块调用消失 |
| `NSArrayOf(rawValue: x)` | 直接 `return`，构造被内联 |
| 桥过去再桥回来 | `return %0`，往返整个消失 |

### 一个标了也不生效的位置

`_unconditionallyBridgeFromObjectiveC` 带着 `@_effects(readonly)`，
而 `@_effects` **无条件**阻止内联 —— 内联器在
`PerformanceInlinerUtils.cpp` 里的判断是
`if (… || Callee->hasEffectsKind()) return nullptr;`，走到别的条件之前就退出了。
所以这一个方法无论怎么标都不会被内联；宏仍然给它标上属性，
因为 effects 信息对优化器分析那次真实调用仍然有用，
生成的代码里也写明了这件事。

**但 `@_semantics` 不阻止内联**，这点与直觉相反：同一份代码里
`getSemanticFunctionLevel` 只把 array 与 fixed_storage 语义当作 `Fundamental`，
`convertToObjectiveC` 属于 `Transient`，不触发那条提前返回。

## 宏到底做了什么

只做一件事：**把四个 `_ObjectiveCBridgeable` witness 放到具体类型上，并带上三个下划线属性。**
它不读你的属性、不需要知道 ObjC 类是什么（`_ObjectiveCType` 直接写成协议的关联类型），
生成的每个方法都只是转发到你写的 `ObjectiveCRepresentable` 成员。

看起来像是能用协议扩展写一次就完事的东西。**不能**，而且代价不是可读性而是整个优化。
实测（读优化后的 SIL，对象一来一回的往返）：

| witness 位置 | `@_semantics` | 桥接往返 |
|---|---|---|
| 协议扩展默认实现 | 有 | 不消除 |
| 具体类型 | 无 | 不消除 |
| 具体类型 | 有 | **消除**，塌缩成 `return %0` |

消除往返的优化 pass 要求参数直接传递，而协议扩展里的 `Self` 是不透明泛型参数、
只能按地址传（`@out` / `@in_guaranteed`），永远匹配不上；
光挪到具体类型不带 `@_semantics`，pass 又认不出它们是桥接函数。
两个条件缺一不可，**而且缺了任何一个都没有任何提示** —— 编译照过，优化悄悄归零。

这就是为什么它是宏：这种看不见的正确性不该靠人每次都记得。
