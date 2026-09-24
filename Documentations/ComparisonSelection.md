# 指定排序定义 —— 用法契约与陷阱

`ComparableBuildable` 让一个类型用步骤 DSL 描述自己的顺序，但协议只要求一个
`comparableDefinition`，`<` 和 `==` 都走它。一个类型想按第二种规则排序，以前只能退回手写闭包。

这篇讲两件事：怎么给一个类型声明多套排序规则并在调用点选用，以及怎么直接按某个属性排序。
设计过程与被否掉的方案见提案[《让序列比较可以指定用哪一套排序定义》](Evolutions/draft-sequence-comparison-selection.md)。

完整的可运行示例在 [`Sources/SwiftStdlibToolboxClient/ComparisonSelection.swift`](../Sources/SwiftStdlibToolboxClient/ComparisonSelection.swift)，
`swift run SwiftStdlibToolboxClient` 即可看到输出：同一份文件列表按 Finder「排序方式」菜单里的名称、大小、种类、
最近打开时间各排一遍，外加一个根本不是 `Comparable` 的类型（窗口按阅读顺序排）。

## 声明额外的排序定义

额外定义就是普通的 `static var`，写法和 `comparableDefinition` 一样，只多一个 builder 标注：

```swift
struct Employee: ComparableBuildable {
    var name: String
    var department: String
    var salary: Int

    // 协议要求的这一个自带 @ComparableBuilder<Self>，不用写
    static var comparableDefinition: some ComparisonStep<Self> {
        compare(\.name)
    }

    // 额外声明的要自己写出来。泛型参数写 Self 即可，不必写具体类型名
    @ComparableBuilder<Self>
    static var bySalaryDescending: some ComparisonStep<Self> {
        compareDescending(\.salary)
        compare(\.name)
    }
}
```

**必须是 `static var`，不能是 `static let`。** 这条和 `comparableDefinition` 的要求同源：
步骤树只有在每次比较时就地构造，字面 keyPath 才留在编译器视线内，整棵树才会被折叠成直接的成员访问。
存进 `static let` 会让每次比较都走泛型 keyPath 查表，慢 5–10 倍。
写成 `let` 不会报错，也不会有警告，只是慢。

## 调用端

全部挂在 `.box` 上。选定义用 `using:` 加一个根类型是**元类型**的 keyPath：

```swift
staff.box.sorted(using: \.bySalaryDescending)
staff.box.min(using: \.bySalaryDescending)
staff.box.max(using: \.bySalaryDescending)
staff.box.isSorted(using: \.bySalaryDescending)

var mutableStaff = staff
mutableStaff.box.sort(using: \.bySalaryDescending)

// 两个值直接比
carol.box.compare(to: alice, using: \.bySalaryDescending)   // -> ComparisonResult
carol.box.isLess(than: alice, using: \.bySalaryDescending)  // -> Bool
```

`\.comparableDefinition` 也能选，它同样是个 static 属性。

直接按属性排序用 `by:`，不涉及任何定义：

```swift
staff.box.sorted(by: \.salary)
staff.box.sorted(by: \.name, .descending)

var mutableStaff = staff
mutableStaff.box.sort(by: \.salary)
```

降序是把比较的两边对调，不是把升序结果倒过来，所以**相等的元素保持原有相对次序**。

## 四条契约

### 一、类型不必遵循 `ComparableBuildable`

约束只落在「那个 static 属性的类型是一个 `ComparisonStep`，且元素类型对得上」。
一个没有单一自然顺序、因而**不该**是 `Comparable` 的类型，照样可以带定义：

```swift
struct SensorReading {                 // 不遵循任何协议
    var timestamp: Int
    var celsius: Double
    var note: String?

    @ComparableBuilder<Self>
    static var byTimestamp: some ComparisonStep<Self> {
        \.timestamp
        DescendingKeyPathComparisonStep(\Self.celsius)
        \.note
    }
}

readings.box.sorted(using: \.byTimestamp)
```

### 二、不遵循 `ComparableBuildable` 时写裸 keyPath，不要写 `compare(_:)`

`compare(_:)` / `compareDescending(_:)` / `compareCustom(_:_:)` 是
`extension ComparableBuildable` 上的工厂方法，不遵循该协议就够不着。

这时直接写裸 keyPath（`\.timestamp`），builder 会把它变成步骤。
**不要**改写成 `KeyPathComparisonStep(\.timestamp)` —— 那会报
`cannot infer key path type from context`，因为初始化器的泛型参数要从 keyPath 推，
而 keyPath 的根类型要从泛型参数推。写全 `KeyPathComparisonStep(\Self.timestamp)` 能过，
但没必要。

降序和自定义比较器没有裸写法，用 `DescendingKeyPathComparisonStep(\Self.property)` 或
`CustomKeyPathComparisonStep(\Self.property) { … }`。根类型要写出来，但写 `Self` 就行。

裸 keyPath 在遵循 `ComparableBuildable` 的类型上同样可用，和 `compare(\.x)` 等价。

### 三、两元素直接比较要求元素类型遵循 `FrameworkToolboxCompatible`

`compare(to:using:)` 和 `isLess(than:using:)` 走的是**元素自己的** `.box`，所以：

```swift
struct Employee: ComparableBuildable, FrameworkToolboxCompatible { … }
```

序列上的那几个方法没有这个要求 —— 那里的 `.box` 是集合的，`Array` 一族早就有了。

### 四、`by:` 和 `using:` 不能互换

- `by:` 收的是**属性** keyPath（`\.salary`，根类型是元素本身）
- `using:` 收的是**定义** keyPath（`\.bySalaryDescending`，根类型是元素的元类型）

两者根类型不同，写错了编译不过，不会静默取错东西。
现有的 `min(by:)` / `max(by:)` 属于前一组，语义没变。

## 性能

和手写比较器持平。30 万元素、跨模块 SPM release 构建实测：

| | 用时 |
|---|---|
| 手写比较器 | 23.42 ms |
| `sorted(using: \.someDefinition)` | 23.33 ms |
| `sorted(by: \.property)`（对照手写 11.94 ms） | 12.08 ms |

前提是上面那条「必须是 `static var`」。`ComparableBuildableBenchmarks` 里的
`sorted(using:) 100k Int-triples` 一项会把这个落差打印出来。

## 改这套东西之前要知道的

实现里每个方法都在比较闭包**内部**应用 keyPath，而不是先取出来存进局部变量。
两种写法编译结果一样、行为一样、没有任何诊断，但后者慢 5.7 倍。
原因写在 `Sources/SwiftStdlibToolbox/ComparisonSelection.swift` 的注释里，
连着 `@_transparent` 为什么不能用一起。
