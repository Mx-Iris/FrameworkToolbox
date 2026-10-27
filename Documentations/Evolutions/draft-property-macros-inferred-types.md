# Draft - 属性宏不再强制写类型注解

- **状态**: In Progress
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **实现分支**: `feature/macro-patterns`

## 摘要

`@Mutex`、`@OSAllocatedUnfairLock`、`@Keychain`、`@UserDefault` 共用的属性解析器要求属性必须写类型注解，
所以 `@UserDefault(key: "launchCount") var launchCount = 0` 会被宏拒绝（`requires an explicit type annotation`）。
这四个宏本身就是 accessor 宏：挂上之后，编译器把用户写的初始值当成「只用于推断类型、不执行」的表达式，
属性自己的类型编译器已经推得出来。宏非写出类型不可的，只有它自己生成的那几处代码。本提案把这几处也交给
编译器推断，类型注解变成可选。

## 方案

**属性本身什么都不用做。** accessor 宏给属性添加了 getter、且属性没有 init accessor 时，编译器把初始值标为
subsumed：不生成执行代码，但照样做类型检查，属性类型由它推断。「计算属性必须写类型」是解析阶段对源码里写出的
accessor 块做的检查，宏事后添加的 accessor 不经过它。依据见全局 `swift-macro-patterns` skill 的
`references/compiler-rules.md`（`TypeCheckMacros.cpp` 中把初始值标为 subsumed 的一段，以及 `getExecutableInit`）。
宏要做的只是不再拒绝。

**宏生成的代码改成不写类型：**

- backing storage 是存储属性，存储属性本来就能由初始值推断类型。写成 `OSToolbox.Mutex(<初始值>)`、
  `os.OSAllocatedUnfairLock(initialState: <初始值>)`、`FoundationToolbox.KeychainStorage(…, defaultValue: <初始值>)`、
  `FoundationToolbox.UserDefaultStorage(…, defaultValue: <初始值>)`，泛型参数由编译器推出。
- setter 里写死的闭包参数类型 `(value: inout T) -> Void` 改用 `$0`。
- `@Keychain` / `@UserDefault` 的 `var $name: some Combine.Publisher<T, Never>` 是唯一绕不开类型的地方：计算属性在
  解析阶段就必须写类型。改成生成一个带初始值的属性，再挂 accessor 宏 `@FoundationToolbox._StoragePublisherProjection`
  把它变成 getter，于是 `$name` 成了类型靠推断、不占存储的计算属性（skill 技巧 3，出处是 SwiftUI `@Entry` 生成的
  `@__EntryDefaultValue`）：

  ```swift
  @FoundationToolbox._StoragePublisherProjection
  var $launchCount = FoundationToolbox.UserDefaultStorage(key: "launchCount", defaultValue: 0).publisher.eraseToAnyPublisher()
  // 展开为
  var $launchCount { get { _launchCount.publisher.eraseToAnyPublisher() } }
  ```

  这里有两条编译器规则，各自决定了一处写法（实测得出，见决策日志）：
  - **初始值按属性初始值的上下文做类型检查，`self` 还不存在**，所以实例属性的初始值里不能写 `_launchCount.publisher`。
    初始值改成一个类型相同、不碰 `self` 的原型——用同样的参数新建一个 storage；它从不执行，没有开销。getter 运行时
    有 `self`，读的是真正的 storage，名字由 `$launchCount` 推出 `_launchCount`（借用 structured-queries
    `_PrimaryKeyDefault` 的变体：初始值只定类型，getter 返回别的）。
  - **属性的推断类型不能是别的声明的 `some` 返回类型**，而 storage 的 `publisher` 正声明为 `some Publisher<Value, Never>`。
    所以省略类型时 `$name` 是 `eraseToAnyPublisher()` 之后的 `AnyPublisher<Value, Never>`：具体类型，同样不暴露
    `PassthroughSubject` 的 `send`，每次读多一次装箱。写了类型注解时仍是原来的 `some Publisher<T, Never>`。

**写了类型注解时展开结果保持原样**，只有省略类型时才走上面的写法。已有调用点展开出的代码一个字都不变。

**仍然要求写类型注解的**：`weak` 属性——宏要拼出 `WeakBox<T>`，而 `weak var owner = object` 推断出的是
`Object?`，宏没法从语法拿到 `Object`；以及没有初始值的属性，这时本来就无从推断。

**不放宽 `@AvailableNonMutating` / `@AvailableMutating`**：它们的默认值通常写在宏参数里
（`@AvailableNonMutating(WindowController())`），而那个参数的类型是 `Any?`，推断不出属性类型；只为「初始值写在属性上」
这一种写法改动收益太小。

### 源码兼容性

纯放宽。写了类型注解的调用点展开结果不变；原来被宏拒绝的写法现在能编译。`_StoragePublisherProjection` 是新增的
下划线宏，标 `@_documentation(visibility: private)`，不算公开 API。两种写法下 `$name` 的静态类型不同（`some Publisher`
与 `AnyPublisher`），但都是 `Output == Value`、`Failure == Never` 的 `Publisher`，调用方的用法没有差别。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 按 `swift-macro-patterns` skill 的技巧审视全部宏时发现：四个属性宏要求类型注解，只是因为它们自己生成的代码写出了类型，而这些代码都可以交给编译器推断 |
| 2026-10-27 | 用户批准，开始实现 | 审视结论中的各项改进经用户同意全部实施 |
| 2026-10-27 | 写了类型注解时保留原来的展开结果 | 已有调用点的展开不变，现有快照也不必重录；新写法只服务省略类型的属性 |
| 2026-10-27 | `weak` 属性仍要求类型注解 | `WeakBox<T>` 要的是去掉可选之后的类型，推断结果给不出这个拼写 |
| 2026-10-27 | 不放宽 `@AvailableNonMutating` / `@AvailableMutating` | 默认值多写在 `Any?` 类型的宏参数里，推断不出属性类型，收益不抵改动 |
| 2026-10-27 | `$name` 的初始值改用原型 storage，getter 按名字读真正的 storage | 最初写成 `var $name = _name.publisher`，编译报 `cannot use instance member '_name' within property initializer; property initializers run before 'self' is available`：被吸收的初始值虽不执行，仍按属性初始值的上下文检查 |
| 2026-10-27 | 省略类型时 `$name` 擦除为 `AnyPublisher` | 推断成 `publisher` 的类型时编译报 `property definition has inferred type 'some Publisher<Double, Never>', involving the 'some' return type of another declaration`。改 storage 的 `publisher` 为具体类型也能绕开，但那是公开 API 的改动；擦除只影响新写法 |
| 2026-10-27 | 实现完成，待合并 | 快照测试、运行时测试（`InferredStoragePropertyTests`）与客户端编译守卫全部通过 |
