# `ObjCRuntimeToolbox` —— Design

Date: 2026-06-26
Target library: `ObjCRuntimeToolbox` (新模块)

## Motivation

起点是 AppKitPlus 仓库里的 `_NSDynamicSubclass.h/.m`——一对 ~330 行的 Objective-C 文件，提供"懒加载 swizzle"（per-instance ISA swizzling）的运行时原语：用 `objc_allocateClassPair` 给基类动态造一个子类，再用 `object_setClass` 给单个实例换 isa；目标方法的 IMP 是 C 函数，调用 super 靠 `objc_msgSendSuper` 一族 `NSP_DYNAMIC_SUPER_*` 宏。

这套模式好用，但 ObjC 端有三处痛：

1. **每个 override 都要写独立的 `_override_<sel>` C 函数 + 上下文重构**——C 函数 IMP 不能捕获，所有上下文要靠侧表/associated object 重新取出。
2. **`NSP_DYNAMIC_SUPER_VOID0`、`NSP_DYNAMIC_SUPER_VOID(arg)`、`NSP_DYNAMIC_SUPER_RETURN(...)`、`NSP_DYNAMIC_SUPER_VOID_IF_IMPL(arg)`、`NSP_DYNAMIC_SUPER_RETURN_IF_IMPL(...)` ……宏按 arity × void/return × always/if-impl 排列组合，覆盖面有限**，要超出现有形态就得手写 `objc_msgSendSuper` 调用。
3. **`_NSDynamicSubclassOverride[]` 描述符表 + selector/IMP/typeEncoding 三元组手填**，type encoding 要么显式写字符串，要么靠 reference class/protocol 在 runtime 时查表。

把它原样翻成 Swift 已经能砍掉相当一部分样板（`imp_implementationWithBlock` + `@convention(block)` 闭包能捕获上下文），但还能进一步：**用一个宏把整套 hook 收口成"一个 struct + 几个同名函数 + `callSuper()`"的 shape**，做到名字与原版一致、`self`/`base` 隐式可达、完全不污染基类。这份文档记录该模块的目标、设计选择与已知边界。

## Goals

- 提供运行时层 `DynamicSubclass` 命名空间，端到端对位 `_NSDynamicSubclass.h/.m` 的能力：subclass 缓存、ref-counted ISA swap、dealloc sentinel、override + protocol 注册、type-encoding 解析。
- 提供宏 `@DynamicSubclassHook(of:suffix:adopts:)`，把"一个 hook"折叠成一个 struct，让用户用 **隐式 `self`/`base`** 写 override，方法名与原版一致，且不在基类上新增任何 API。
- 在宏展开点生成**类型安全**的本地 `callSuper(...)` 和 `callSuperIfImplemented(...)` 辅助函数——返回类型、参数类型与用户函数签名严格匹配，编译期可验证。
- 自动派生 ObjC selector：从 Swift 函数名 + 参数 label → `name:label:` 串。
- 支持 `adopts: [Protocol.self, ...]`：动态子类声明协议、给 type encoding 查表当 fallback。
- KVO 兼容三件套：`-class` 隐藏动态子类、`-respondsToSelector:`/`-conformsToProtocol:` 路由到真实 ISA。

## Non-Goals

- **不**做 method swizzle（替换原方法 IMP）的 API。本模块只做 per-instance ISA swizzle——更安全、可关、可逐实例开关。要做 method swizzle 的人请直接用 `method_setImplementation`。
- **不**做 KVO 互操作的复杂保护。只实现"动态子类层叠到原始类之上"这一层；如果用户的代码同时跑 KVO + 这里的 hook，**KVO 在外、hook 在内**才有保障；反过来 KVO 后开 hook，本模块的 `release()` 不会破坏 KVO 状态（用 `currentClass === dynamicSubclass` 守卫）。
- **不**自动桥接 `throws` / `async`。`throws` 由宏入口 `context.diagnose(...)` 拒绝；`async` 因 ObjC continuation 桥接复杂同样拒绝。错误锚到 `throws` / `async` 关键字 token，IDE 红线落在用户源码而非展开 buffer。
- **不**自动派生 Swift `@objc` 桥接的 `<baseName>With<CapitalizedLabel>:` 形态。默认按 `baseName + 各 externalLabel + :` 朴素拼接；若首参带非 `_` label，宏在编译期 diagnose 报错，提示要么改用 `_`、要么显式传 selector：`@DynamicSubclassOverride("formatWithMessage:level:")`。

## Architecture

### 模块布局

```
Sources/
  ObjCRuntimeToolbox/                # public runtime + macro declarations
    DynamicSubclass.swift            # runtime primitives
    DynamicSubclassHookMacro.swift   # @attached macro declarations
  ObjCRuntimeToolboxMacros/          # macro compiler plugin
    MainPlugin.swift
    DynamicSubclassHookMacro.swift   # MemberMacro + MemberAttributeMacro
    DynamicSubclassMethodBodyMacro.swift   # BodyMacro
    FunctionShape.swift              # signature parser shared by both roles
  ObjCRuntimeToolboxClient/          # manual macro expansion driver
    main.swift

Tests/
  ObjCRuntimeToolboxTests/           # behavioral PoC tests (5 scenarios)
  ObjCRuntimeToolboxMacroTests/      # placeholder for MacroTesting snapshots
```

平台条件：仅在 `canImport(ObjectiveC)` 时编译（Apple 平台）。

### 三层架构

1. **运行时层（`DynamicSubclass`）** —— 纯 Swift 包装 `objc/runtime.h` + `objc/message.h`。所有 ObjC runtime 调用都封在这里。
2. **宏层（`@DynamicSubclassHook` + `@_DynamicSubclassMethodBody`）** —— 编译期把用户写的 hook struct 折叠成"块描述符 + 注册函数 + body 改写"。
3. **用户层** —— 一个带 `@DynamicSubclassHook` 注解的 struct，内含若干同名 ObjC 方法的 Swift 实现。

### `DynamicSubclass` 运行时

`public enum DynamicSubclass` 提供四组 API：

**Subclass lifecycle**
- `getOrCreate(of:suffix:) -> AnyClass` —— 用 `objc_allocateClassPair` 创建命名为 `_ObjCRuntimeToolbox_<suffix>_<baseClassName>` 的动态子类（已存在则缓存命中）；新建时立即装好三个 baseline overrides（见下）。
- `retain(_:dynamicSubclass:)` / `release(_:)` —— ref-counted ISA swap。首次 retain 用 `object_setClass` 换 isa 并挂 dealloc sentinel；release 到 0 时只在"当前 isa 仍是我们装的动态子类"时才把 isa 还原（避免破坏中途层叠上来的 KVO）。
- `isInstalled(on:)` / `originalClass(of:) -> AnyClass` —— side table 查询。

**Override registration**
- `addOverrides(on:referenceClass:referenceProtocols:_:)` —— 幂等。`class_addMethod` 已存在的 selector 会 no-op。type encoding 解析顺序：caller-supplied → `referenceClass` 上的同 selector → `referenceProtocols` 每个的 method description（required → optional）→ fallback `v24@0:8@16`。
- `addProtocols(on:_:)` —— `class_addProtocol` 包装。

**Super dispatch**
- `resolveSuperImplementation(for:selector:) -> IMP` —— 拿到原始类的 IMP（找不到就 trap）。
- `resolveSuperImplementationIfAvailable(for:selector:) -> IMP?` —— non-trapping 版本，给 `callSuperIfImplemented` 用。

**Baseline overrides**（每个动态子类创建时自动装上）
- `-class` 覆盖：返回 `originalClass(of: instance)`，对外伪装成原始类（KVO pattern）。
- `-respondsToSelector:` 覆盖：先用真实 ISA 查 `class_respondsToSelector`（这样动态子类上加的方法能查到），不命中再 super dispatch。
- `-conformsToProtocol:` 覆盖：同上，先用真实 ISA 查 `class_conformsToProtocol`（让 `as? Protocol` 能识别 `adopts:` 添加的协议）。

**侧表存储**
- `sharedSubclassCache: [String: AnyClass]` —— 子类名 → 子类。
- `sharedSideTable: [ObjectIdentifier: SideTableEntry]` —— 对象 identity → `(originalClass, dynamicSubclass, retainCount)`。
- `sharedLock: NSLock` —— 简单锁。PoC 之外可换成 `OSAllocatedUnfairLock`（来自 `FoundationToolbox`），但要先解决 `ObjCRuntimeToolbox` ↑↓ `FoundationToolbox` 的依赖方向问题。
- `DynamicSubclassSentinel: NSObject` —— 装在每个被 hook 的实例上（`objc_setAssociatedObject` `.OBJC_ASSOCIATION_RETAIN_NONATOMIC`），`deinit` 时清理 side table 条目。

### 宏：`@DynamicSubclassHook`

宏在 `Sources/ObjCRuntimeToolbox/DynamicSubclassHookMacro.swift` 声明：

```swift
@attached(member, names: named(base), named(init), named(install),
                          named(uninstall), named(dynamicSubclass),
                          named(installOverridesIfNeeded))
public macro DynamicSubclassHook<BaseClass: NSObject>(
    of baseClass: BaseClass.Type,
    suffix: String,
    adopts adoptedProtocols: [Any.Type] = []
) = #externalMacro(module: "ObjCRuntimeToolboxMacros", type: "DynamicSubclassHookMacro")

@attached(body)
public macro DynamicSubclassOverride(_ explicitSelector: String? = nil) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "DynamicSubclassOverrideMacro"
)
```

**MemberMacro 角色**——给 hook struct 注入：
- `let base: BaseClass` 和 `init(base:)`——储存当前调用的实例。Box pattern：`self.base` 就是原始 AppKit/Foundation 实例。
- `static func install(on:)` / `static func uninstall(from:)` —— 用户入口；委托给 `DynamicSubclass.retain/release`。`install` 处理 `getOrCreate` 失败时（`AllocationError`）早退。
- `static func dynamicSubclass(for:) -> AnyClass?` —— `try DynamicSubclass.getOrCreate(...)`；失败转 `os_log .fault` 经 `logAllocationFailure(...)` 输出后返回 `nil`。
- `private static func installOverridesIfNeeded(on:)` —— 由 `claimOverrideInstallation(on:hookIdentifier:)` once-guard 守卫，确保每个 `(dynamicSubclass, hookTypeName)` 只装载一次（同 suffix 多 hook 仍各自 claim，互不干扰）。仅为带 `@DynamicSubclassOverride` 标记的方法生成 `@convention(block)` 闭包；闭包变量命名 `block_<baseName>_<index>` 避免 baseName 重载冲突。

**Opt-in `@DynamicSubclassOverride`**——hook struct 内只有显式标注此 attribute 的方法会被注册为 ObjC override；未标注方法保持纯 Swift helper。可选第一个字符串参数覆盖 selector 自动派生。

### 宏：`@DynamicSubclassOverride`（公开标记 + body 改写）

BodyMacro 改写每个用户方法的 body：把原 statements 前面插入两个本地辅助函数，签名严格匹配用户方法。

**`callSuper(args...) -> Ret`**——通过 `resolveSuperImplementation` 拿到原始 IMP，`unsafeBitCast` 到具体的 `@convention(c)` 函数指针，直接调用。

**`callSuperIfImplemented(...)`**——两种 shape：
- void 函数：`callSuperIfImplemented(args...)`，原始类没实现就 return。
- returning 函数：`callSuperIfImplemented(default: ReturnType, args...) -> ReturnType`，没实现就返回 `defaultValue`。

展开示例（用户函数 `func greet() -> String { let result = callSuper(); return result.uppercased() + "!" }`）：

```swift
func greet() -> String {
    func callSuper() -> String {
        let originalImplementation = ObjCRuntimeToolbox.DynamicSubclass.resolveSuperImplementation(
            for: self.base, selector: Selector(("greet"))
        )
        let dispatchFunction = unsafeBitCast(
            originalImplementation,
            to: (@convention(c) (AnyObject, Selector) -> String).self
        )
        return dispatchFunction(self.base, Selector(("greet")))
    }
    func callSuperIfImplemented(default defaultValue: String) -> String {
        guard let originalImplementation = ObjCRuntimeToolbox.DynamicSubclass
            .resolveSuperImplementationIfAvailable(for: self.base, selector: Selector(("greet")))
        else {
            return defaultValue
        }
        let dispatchFunction = unsafeBitCast(
            originalImplementation,
            to: (@convention(c) (AnyObject, Selector) -> String).self
        )
        return dispatchFunction(self.base, Selector(("greet")))
    }
    let result = callSuper()
    return result.uppercased() + "!"
}
```

### Selector 派生规则

`FunctionShape` 实现，集中在 `Sources/ObjCRuntimeToolboxMacros/FunctionShape.swift`：

- 0 参数：selector = baseName。
- N 参数：selector = baseName + 第 1 参数标签（`_` 则省略）+ `:` + 第 2 参数标签 + `:` + ……
  - `func layout()` → `layout`
  - `func draggingEntered(_ sender: NSDraggingInfo)` → `draggingEntered:`
  - `func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int)` → `tableView:viewFor:row:`

**首参非 `_` label 当前不会派生成 Swift 实际的 `@objc` selector**（应当是 `<baseName>With<CapitalizedLabel>:`，目前实现简单拼接，会得到错误 selector）。约定使用 `_`；后续可加 `@selector("...")` 覆盖属性。

## 关键架构决定

### 为什么是 box pattern + 隐式 `base`，而不是 `self`

考虑过四种 hook 写法，对比矩阵：

| 形态 | 名字一致 | 隐式 self | 污染 base class | 工程复杂度 |
|---|---|---|---|---|
| static func + 显式 `instance` 参数 | ✅ | ❌ (`instance.x`) | ✅ 无 | 低 |
| extension 上 + `_swz_` 前缀方法 | ❌（前缀） | ✅ | ⚠️ fileprivate 内可见 | 中 |
| extension 上 + 同名方法 | ❌（Swift 直接报 redeclaration） | — | — | 不可行 |
| **box struct + `base`** | ✅ | "半隐式"（`base.x`） | ✅ 无 | 中 |

box struct 是综合最优：方法名与 ObjC 端原版一致、用户写 `base.x`（和 `FrameworkToolbox<Base>.base` 心智一致）、基类一行不动。

### 为什么 `callSuper` 不在 runtime 写成泛型

最初版本 runtime 里有：

```swift
public static func callSuperReturn<ReturnValue>(
    _ instance: AnyObject, _ selector: Selector, as: ReturnValue.Type
) -> ReturnValue {
    let imp = ...
    let function = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector) -> ReturnValue).self)
    return function(instance, selector)
}
```

编译器报 `'(AnyObject, Selector) -> ReturnValue' is not representable in Objective-C, so it cannot be used with '@convention(c)'`。原因：Swift 的 `@convention(c)` 在类型层面要求所有参数/返回类型都是 ObjC representable，而泛型参数 `ReturnValue` 在泛型边界无法被证明。

绕开方式（标准 trick）：**把 `unsafeBitCast` 推到宏展开点用具体类型**。runtime 只暴露 `resolveSuperImplementation(for:selector:) -> IMP`，由宏在编译期把用户函数签名读出来，生成带具体类型的 `@convention(c)` 函数指针 cast。

这个转折反过来是好事：

- runtime 不再需要为 arity × void/return × ifImpl 写一堆重载——所有组合在宏展开点统一生成。
- super 调用的类型安全完全由宏保证（用户写的返回类型是什么，cast 就是什么，编译期校验）。
- arity 没有人为天花板。**类型范围有边界**：`@convention(c)` 只能桥接 Objective-C representable 的 Swift 类型 —— `@objc` class、`Bool` / `Int` 系 / `Float` / `Double` / `CGFloat`、`String`（桥到 `NSString`）、`Selector`、`AnyClass`、`Optional<class>`、`Void`。`inout` / 元组返回 / 非 class 的 `Optional` / 裸 Swift 闭包 / 命中外层泛型参数的类型都由宏在编译期通过 `context.diagnose(...)` 拒绝，错误直接锚到用户的 `TypeSyntax`。

### 为什么 BodyMacro 而不是 PreambleMacro

`swift-syntax` 在 603.0.2 里有两个候选：

- `BodyMacro`（stable）—— 返回 `[CodeBlockItemSyntax]` 整体替换函数体；但能通过 `declaration.body` 读到用户原 body 后拼回去。
- `PreambleMacro`（`@_spi(ExperimentalLanguageFeature)`）—— 只往函数体前面插入代码，不替换原 body。

`PreambleMacro` 语义上更贴近需求，但 SPI 标记意味着 API 不稳、需要开启实验性 feature。BodyMacro 用"读 original body + prepend + 返回"的方式能做完全等价的事，所以选 BodyMacro。

### 协议 type encoding 查表为什么 try required 再 optional

`protocol_getMethodDescription(proto, sel, isRequired, isInstance)`——传 `isRequired = true` 只查 `@required` 部分，传 `false` 只查 `@optional` 部分。两次都试一遍，覆盖率最大。这点和 AppKitPlus 的 C 实现一致。

### 为什么 sentinel 不用 weak ref

`DynamicSubclassSentinel` 存的是 `ObjectIdentifier`（指针整数），不持有目标对象引用。装在目标对象上用 `OBJC_ASSOCIATION_RETAIN_NONATOMIC`，对象 dealloc 时 sentinel 被 release → `deinit` 清侧表。

不用 weak ref 是因为 ObjC weak associated object 在 dealloc 时可能已经被置 nil，反查不出 identity。直接存 identity（值类型）+ 让 sentinel 跟着 host 一起死，最稳。

## Examples

### Scenario 1：return 值 + 0 参数

```swift
@objc(Greeter)
final class Greeter: NSObject {
    @objc dynamic func greet() -> String { "Hello" }
}

@DynamicSubclassHook(of: Greeter.self, suffix: "Loud")
struct LoudGreeterHook {
    @DynamicSubclassOverride
    func greet() -> String {
        let originalGreeting = callSuper()
        return originalGreeting.uppercased() + "!"
    }
}

let greeter = Greeter()
LoudGreeterHook.install(on: greeter)
greeter.greet()  // "HELLO!"
LoudGreeterHook.uninstall(from: greeter)
greeter.greet()  // "Hello"
```

### Scenario 2：多 arg + return

```swift
@objc(Formatter)
final class Formatter: NSObject {
    @objc dynamic func format(_ name: String, age: Int) -> String { "\(name) is \(age)" }
}

@DynamicSubclassHook(of: Formatter.self, suffix: "Capitalized")
struct CapitalizedFormatterHook {
    @DynamicSubclassOverride
    func format(_ name: String, age: Int) -> String {
        callSuper(name, age).uppercased()
    }
}
```

Selector：`format:age:`。

### Scenario 3：多 arg + void + 副作用

```swift
@objc(NotificationLogger)
final class NotificationLogger: NSObject {
    @objc dynamic var lastMessage: String = ""
    @objc dynamic var lastLevel: Int = 0
    @objc dynamic func log(_ message: String, level: Int) {
        lastMessage = message; lastLevel = level
    }
}

@DynamicSubclassHook(of: NotificationLogger.self, suffix: "Prefixed")
struct PrefixedLoggerHook {
    @DynamicSubclassOverride
    func log(_ message: String, level: Int) {
        callSuper("[hooked] " + message, level)
    }
}
```

### Scenario 4：协议适配 + ifImplemented 取 default

```swift
@objc(Greetable)
protocol Greetable {
    func greetingPrefix() -> String
}

@objc(BareSpeaker)
final class BareSpeaker: NSObject {
    // 不声明 Greetable 协议
    @objc dynamic func speak() -> String { "hello" }
}

@DynamicSubclassHook(of: BareSpeaker.self, suffix: "Polite", adopts: [Greetable.self])
struct PoliteSpeakerHook {
    @DynamicSubclassOverride
    func greetingPrefix() -> String {
        // 原始类无 IMP，callSuperIfImplemented 走 default 分支
        callSuperIfImplemented(default: "Mx. ")
    }
}

let speaker = BareSpeaker()
PoliteSpeakerHook.install(on: speaker)
((speaker as AnyObject) as? Greetable)?.greetingPrefix()  // "Mx. "
```

`as? Greetable` 能成立是因为 `-conformsToProtocol:` 覆盖让 Swift 的 `@objc` protocol 桥接看到动态子类上声明的协议。

### Scenario 5：ifImplemented 命中 super 分支

```swift
@DynamicSubclassHook(of: BareSpeaker.self, suffix: "Logging")
struct LoggingSpeakerHook {
    @DynamicSubclassOverride
    func speak() -> String {
        // speak 在 BareSpeaker 上存在，callSuperIfImplemented 透传
        let originalUtterance = callSuperIfImplemented(default: "<no impl>")
        return "[log] " + originalUtterance
    }
}
```

## Test Coverage

`Tests/ObjCRuntimeToolboxTests/ObjCRuntimeToolboxTests.swift` 9 个测试覆盖：

| 测试 | 覆盖 |
|---|---|
| `testGreeterIsNotHookedByDefault` | 默认未安装时行为不变 |
| `testGreeterHookReplacesPerInstance` | per-instance 隔离 |
| `testGreeterUninstallRestoresOriginalBehavior` | ISA 复原 |
| `testGreeterClassOverrideHidesDynamicSubclass` | `type(of:)` 经 `-class` 路由，`object_getClass` 看到真实 ISA |
| `testFormatterMultiArgReturn` | arity=2 + return |
| `testLoggerMultiArgVoid` | arity=2 + void + 副作用 |
| `testProtocolAdoptionExposesNewMethod` | `adopts:` + `as? Protocol` + `conforms(to:)` + 协议方法 dispatch |
| `testRespondsToSelectorReportsHookedMethods` | `-respondsToSelector:` 路由真实 ISA |
| `testCallSuperIfImplementedDispatchesWhenSuperExists` | ifImplemented 命中 super 分支 |
| `testSharedSuffixComposesOverridesAcrossHooks` | 同 suffix 多 hook 共享 dynamic subclass、各自的 IMP 注册不互相覆盖 |
| `testUntaggedHookMethodIsNotRegistered` | 未标注 `@DynamicSubclassOverride` 的 helper 方法不会被注册为 ObjC override |
| `testInstallIsRefCounted` | install / uninstall 是 ref-counted，N 次 install 需 N 次 uninstall 才完整复原 |
| `testSentinelClearsSideTableOnDealloc` | `DynamicSubclassSentinel` 跟随宿主 dealloc，side table 条目被自动清理 |
| `testConcurrentInstallUninstallOnDistinctInstances` | `DispatchQueue.concurrentPerform` × 200 iteration 并发压测，无 crash / 状态损坏 |

`Tests/ObjCRuntimeToolboxMacroTests/DynamicSubclassMacroTests.swift` 用 MacroTesting `assertMacro` 锁定 8 个诊断快照：`throws` / `async` / `@MainActor` / `inout` / 非 `_` 首参 label / `enum` 容器 / 缺 `suffix:` / baseline selector 冲突。expansion 全文快照因 macro 输出对空白敏感被刻意省略，行为正确性由上面的端到端用例锁定。

## Known Limitations / Future Work

> **2026-06-26 集中修复**：以下 7 条 PoC 期 Known Limitations 全部按设计文档列出的方向收敛了一遍。当前剩余的边界与未做项见 "Remaining / Future" 段。

1. **首参非 `_` label 的 selector 推导 — resolved**
   `FunctionShape.selectorString(explicitSelector:)` 现在接受可选 explicit selector。`@DynamicSubclassOverride("formatWithMessage:level:")` 允许在 Swift `@objc` 桥接产物与朴素拼接不一致时手动指定。未传 explicit 时，宏入口对非 `_` 首参 label 通过 `context.diagnose(...)` 抛错并下划线到该 label token，杜绝运行时静默不命中。

2. **`throws` / `async` 修饰符 — resolved（拒绝）**
   `FunctionShape.init` 已读取 `signature.effectSpecifiers`，`DynamicSubclassOverrideMacro` 在 expansion 入口对 `throws` / `async` / `@MainActor` / `mutating` / actor 隔离修饰符通过 `context.diagnose(...)` 抛错并精确锚到 token（IDE 红线落在 `throws` / `async` 关键字本身）。`throws` 的 IMP 桥接重写仍未做（保持拒绝语义），`async` 同因 ObjC continuation 桥接复杂被显式拒绝；用户得到的是清晰的编译期错误而非运行时崩溃或晦涩的展开 buffer 报错。

3. **MacroTesting expansion 快照测试 — resolved（诊断集）**
   `Tests/ObjCRuntimeToolboxMacroTests/DynamicSubclassMacroTests.swift` 用 MacroTesting `assertMacro` 覆盖 8 个诊断快照：`throws` / `async` / `@MainActor` / `inout` / 非 `_` 首参 / `enum` 容器 / 缺 `suffix:` / baseline selector 冲突。expansion 全文快照因 macro 输出对空白敏感被刻意省略 —— 行为正确性由 `Tests/ObjCRuntimeToolboxTests/` 14 个端到端用例锁定（含 `Scenario 6` shared-suffix 复合、`Scenario 7` 未标注 helper 不被注册、ref-counted install、sentinel 自动清理、`DispatchQueue.concurrentPerform` × 200 的并发压测）。

4. **`OSAllocatedUnfairLock` vs `NSLock` — resolved**
   `NSLock` 换成裸 `os_unfair_lock_s`（iOS 10 / macOS 10.12 起可用，与现有 platforms 完全兼容）。不引入 `FoundationToolbox` 依赖、也不需要 16/13 版本门控，热路径成本最低。

5. **并发压力 / dealloc-time race — resolved**
   - `SideTableEntry` 加 monotonic `generation: UInt64`；`DynamicSubclassSentinel` 捕获生成时 generation；`cleanupSideTableEntry` 在锁内做 generation 匹配后才 `removeValue`，关掉 "老 sentinel deinit 删掉新 install" 的 ABA 窗口。
   - `retain` 的 sentinel 构造在锁内、`objc_setAssociatedObject` 在锁外（避免与关联对象内部锁嵌套）；`release` 的 sentinel 解绑同样在锁外，并由 generation 守卫保护。
   - 新增 `testConcurrentInstallUninstallOnDistinctInstances` × 200 iteration 压测覆盖 `DispatchQueue.concurrentPerform` 路径。

6. **多 hook 共享同一 dynamic subclass — resolved**
   `claimOverrideInstallation(on:hookIdentifier:)` 现在以 `(ObjectIdentifier(dynamicSubclass), hookIdentifier)` 为 key，每个 hook 独立 claim 一次。同 suffix 多 hook 仍共享 dynamic subclass、各自的 IMP 注册不互相覆盖。专项测试 `testSharedSuffixComposesOverridesAcrossHooks` 锁定该路径。反面情况 —— 同实例尝试用**不同 suffix** 叠加两个 hook —— 由 `retain(_:dynamicSubclass:)` 的 existing-entry 分支检测 `dynamicSubclass !== existing.dynamicSubclass` 时 `preconditionFailure`，把曾经的静默丢弃升级为可观察失败。

7. **错误诊断质量 — resolved**
   `DynamicSubclassMacroDiagnostic` 与 `MacroExpansionContext.emit(_:at:)` 把所有错误改成 `context.diagnose(...)`：缺 `of:` / `suffix:` 下划线落到 attribute 节点、未知 label 下划线落到具体实参、`adopts:` 非 `<Type>.self` 形态下划线落到具体元素、enum / actor / extension / protocol 容器下划线落到 attribute 本身、`throws` / `async` / `mutating` / `@MainActor` / `inout` 下划线落到具体修饰符 token、非 `_` 首参 label 下划线落到 label token、baseline selector 冲突下划线落到方法名、selector 重复或 baseName 索引冲突下划线落到方法名。`DynamicSubclassMethodBodyMacroError.notAFunctionDeclaration` 也真正 throw 了。

### Resolved beyond the original 7

集中修复期间另外关闭的 audit 项（节选；完整 finding 列表见 audit 输出）：

- **Critical**: `objc_allocateClassPair` 返回 `nil` 时 `getOrCreate` 抛 `AllocationError`，宏生成的 `install(on:)` 早退，不再静默退化为全局 method swizzle；`addOverrides` 加 `precondition(dynamicSubclass !== referenceClass)` 防线。
- **High**: `addOverrides` 在 `class_addMethod` 返回 false 时 `imp_removeBlock` 回收 trampoline；`claimOverrideInstallation` once-guard 让 `installOverridesIfNeeded` 真正幂等，重复 install 不再泄漏。
- **High**: `@DynamicSubclassHook` 不再 `MemberAttributeMacro` 自动给每个 func 挂 body —— 改为显式 opt-in `@DynamicSubclassOverride` 标记。未标注 func 完全是普通 Swift helper，避免 "private helper 被静默 swizzle" 的 footgun。
- **High**: block 名从 `block_<baseName>` 改为 `block_<baseName>_<index>`，消除 baseName 重载冲突；selector 重复在宏入口 diagnose。
- **High**: `Package.swift` 把 `ObjCRuntimeToolbox` library 标 `type: .dynamic`，强制单一进程内拷贝，避免多 dylib 静态嵌入下 `sharedSideTable` / `sentinelAssociationKey` 各成一份。
- **High**: 宏泛型 `BaseClass: AnyObject` 收紧为 `BaseClass: NSObject`。
- **High**: `FunctionShape` / `DynamicSubclassOverrideMacro` 入口对 `inout` / `borrowing` / `consuming` 修饰符、Swift 元组返回、裸 Swift 闭包参数都 diagnose。
- **Medium**: `retain` 检测 `NSKVONotifying_` 前缀（KVO 已激活的对象）→ `os_log .fault` + `assertionFailure` 并拒绝 install；`getOrCreate` / `retain` 对 `class_isMetaClass` 守卫。
- **Medium**: `getOrCreate` 命中既有同名类时沿 `class_getSuperclass` 校验 `baseClass` 在祖先链中，否则 throw；命中分支也无条件重装 baseline overrides（`class_addMethod` 幂等）。
- **Medium**: `installBaselineOverrides` 改用 `class_getInstanceMethod(NSObject.self, sel)` + `method_getTypeEncoding` 读取真实 BOOL 编码，兼容 x86_64 macOS / Mac Catalyst 的 `signed char` ABI。
- **Medium**: `resolveTypeEncoding` fallback 分支 `os_log .info` 警告 + Debug `assertionFailure`，不再静默生效。
- **Medium**: `release(_:)` 在缺 entry 分支 `assertionFailure`，over-release 在 Debug 早暴露。
- **Medium**: `resolveSuperImplementation` fatalError 文案附使用建议（建议改用 `callSuperIfImplemented(default:)`）。
- **Low**: 死代码 `FunctionShape.dispatchArgumentList` 与 `"PoC: missing default value"` fallback 移除。
- **Low**: `PlaceholderTests.swift` 删除，由真实 MacroTesting 用例替换；客户端扩展到 5 个 Scenario。
- **Low**: 宏生成代码改用 `NSSelectorFromString(...)` 而非 `Selector((...))`，消除编译器 `#selector` 建议警告。

### Remaining / Future

- **`throws` 桥接**：当前选择是 diagnose 拒绝。若未来需要支持，需要 `callSuper` 透传 `try`、IMP cast 加 `throws` 标记、生成 do/try/catch 路径。`async` 因 ObjC continuation 桥接复杂仍计划维持拒绝。
- **expansion 全文快照**：因宏输出对空白敏感而省略；如要补，需要先对 emission 做 indent-stable 规范化。
- **`adopts:` 协议非 `@objc` 的运行时校验**：当前在宏入口做语法形态校验（必须是 `.self`），运行时层依赖 Swift 类型系统 `[Protocol]` 形参把非 `@objc` 协议挡住；未来可在 `addProtocols` / `addOverrides` 多加一道 `class_conformsToProtocol` 探测以输出更具语义的错误。
- **重新引入 `@_AdoptedProtocolMethod` 或类似显式标记**：让 body macro 对 adopts 协议方法只 emit `callSuperIfImplemented` 不生成 `callSuper`，避免用户误用 `callSuper()` 在 informal-protocol 上触发 fatalError。当前文档与 fatalError 文案里已提示，但缺编译期保护。

## Migration / Adoption

适合用本模块的场景：

- 已有的 ObjC `_NSDynamicSubclass` 用例（AppKitPlus 里 5 处）
- 需要"逐实例 hook AppKit/Foundation 方法、不影响其他实例"的场景：NSView 单点装 drop interaction、单个 NSViewController 跟踪 transition state、UIView 对接 SwiftUI bridge 等。
- 替换 `NSObject` 子类化 + override 的场景，当 override 是动态决定的（运行时根据配置开/关），ISA swizzle 比子类化更灵活。

**不适合**的场景：

- 全局 method swizzle（影响全类所有实例）。本模块不做这个；直接用 `method_setImplementation` 或写 +load 即可。
- 非 ObjC runtime 的目标（纯 Swift class 不带 `@objc dynamic` 的方法不会进 ObjC dispatch table，本模块覆盖不了）。
