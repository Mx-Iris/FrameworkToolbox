# OSToolbox 抽取设计

日期：2026-08-06

## 一句话

把 `Mutex`、`@Loggable` / `#log`、`@OSAllocatedUnfairLock` 这些直接架在 Apple `os` 模块之上的东西，从 `SwiftStdlibToolbox` 和 `FoundationToolbox` 里抽出来，组成新的底层 target `OSToolbox`，让 `ObjCRuntimeToolbox` 也能用上它们。

## 动机

`ObjCRuntimeToolbox` 原本是个孤岛——不依赖本仓库任何其它 target。它内部要做线程安全和日志，只能各自手写：`DynamicSubclass` 和 `RuntimeMethodHook` 里各有一份 `nonisolated(unsafe) static var sharedLockStorage = os_unfair_lock_s()` 加一对 `lock()` / `unlock()` 私有方法，日志则是裸的 `os_log(...)` 配一个手写的 `OSLog` 常量。

而仓库里明明已经有更好的东西：`Mutex`（把锁和被保护的值放在同一次分配里，配 `@Mutex` 宏自动生成访问器）和 `@Loggable` / `#log`（自动生成 logger、按 subsystem/category 缓存、带 macOS 11 以下的 `os_log` 回退）。它们够不着，纯粹是因为分层：`Mutex` 在 `SwiftStdlibToolbox`，`@Loggable` 在 `FoundationToolbox`，两者都在 `ObjCRuntimeToolbox` 的上方或旁边。

直接触发这次抽取的是移植 Dynamic 这个库（见 [Dynamic 移植设计](2026-08-06-dynamic-invocation-design.md)）：它原本自带一套 `print` 打印树形结构的日志，配一个永不释放的全局 logger 字典。与其把那套东西一起搬进来，不如让它用上本仓库已有的日志设施。

## 依赖链怎么变的

```
改动前：  FrameworkToolbox ← SwiftStdlibToolbox ← FoundationToolbox
          ObjCRuntimeToolbox（孤立，不依赖任何 toolbox）

改动后：  FrameworkToolbox ← OSToolbox ← SwiftStdlibToolbox ← FoundationToolbox
                                ↖ ObjCRuntimeToolbox
```

`OSToolbox` 依赖 `FrameworkToolbox`，因为 `@Loggable` 的第一个参数类型是 `AccessLevel`，而它定义在那里。`FrameworkToolbox` 本身只有 box 模式、`AccessLevel` 和一个宏，很轻。

## 搬了什么

| 类别 | 文件 | 从 | 到 |
|---|---|---|---|
| 运行时 | `Mutex.swift` | SwiftStdlibToolbox | OSToolbox |
| 运行时 | `WeakBox.swift` | SwiftStdlibToolbox/Helpers | OSToolbox |
| 运行时 | `Loggable.swift`、`LogCategory.swift` | FoundationToolbox | OSToolbox |
| 运行时 | `OSAllocatedUnfairLock+UnsafeModify.swift` | FoundationToolbox | OSToolbox |
| 宏声明 | `MutexMacro.swift` | SwiftStdlibToolbox/Macros | OSToolbox/Macros |
| 宏声明 | `LoggableMacro.swift`、`LogMacro.swift`、`OSAllocatedUnfairLockMacro.swift` | FoundationToolbox/Macros | OSToolbox/Macros |
| 宏实现 | 上述四个宏的实现 | SwiftStdlibToolboxMacros / FoundationToolboxMacros | OSToolboxMacros |
| 测试 | `MutexTests`、`MutexMacroTests`、`LoggingMacroTests`、`OSAllocatedUnfairLockMacroTests` | 各自原 target | OSToolboxTests / OSToolboxMacroTests |

没搬的：`Lock.swift`（`NSLock` / `NSRecursiveLock` 的 property wrapper，属于 Foundation 而不是 `os`），留在 `FoundationToolbox`。

## 关键设计与取舍

### 用 `@_exported import` 保证对现有使用者零破坏

`SwiftStdlibToolbox` 新增 `Exported.swift` 写 `@_exported import OSToolbox`，`FoundationToolbox` 通过它已有的 `@_exported import SwiftStdlibToolbox` 链式拿到。于是原来写 `import SwiftStdlibToolbox` 然后用 `@Mutex`、写 `import FoundationToolbox` 然后用 `@Loggable` / `#log` 的代码，一行都不用改。

**这件事动手前是先实测过的**，因为仓库里此前从来没有跨模块使用宏的先例，`@_exported import` 能不能传递宏声明、宏插件在传递依赖处是否自动可用，都不是想当然的事。验证方式是搭一个最小包：`CoreLib` 声明宏 → `MidLib` 只写 `@_exported import CoreLib` → `TopLib` 只依赖 `MidLib`。结论是类型、`#freestanding` 宏、`@attached` 宏三者都能穿透，SwiftPM 也会把宏插件传给传递依赖者。

仓库里现成的三个 client target 正好覆盖了三条路径，构建通过即验证：

- `OSToolboxClient` —— 直接 `import OSToolbox`
- `SwiftStdlibToolboxClient` —— 一级 re-export
- `FoundationToolboxClient` —— 两级 re-export

### `WeakBox` 必须一起搬，不是可选项

`@Mutex` 和 `@OSAllocatedUnfairLock` 展开 `weak var` 时，生成的代码里带模块限定名 `SwiftStdlibToolbox.WeakBox<...>`。如果只搬锁不搬 `WeakBox`，`ObjCRuntimeToolbox` 里一写 `@Mutex weak var` 就编译失败——它并不依赖 `SwiftStdlibToolbox`。所以 `WeakBox` 跟着走，两个宏生成的限定名同步改成 `OSToolbox.WeakBox`。

顺带补了一个回归测试 `MutexMacroTests.weakProperty()`。`weak` 是唯一一种展开结果里带跨文件模块限定名的形状，也就是唯一一种会因为这类搬迁而失效的形状，而它此前完全没有快照覆盖。

### `AccessLevel` 从三份收敛成一份

改动前 `AccessLevel` 在 `FrameworkToolbox`、`SwiftStdlibToolbox`、`FoundationToolbox` 各定义了一份完全相同的 enum，靠 re-export 链叠在一起。这是既有隐患，不是这次引入的，但搬 `@Loggable` 绕不开它（它的参数类型就是 `AccessLevel`），所以顺手删掉后两份，只留 `FrameworkToolbox` 那份，由 `OSToolbox` re-export 出去。

### 删掉 `Loggable` 协议

`Loggable` 协议（`var logger`、`static var subsystem/category` 那一套）是 `@Loggable` 宏出现之前的产物，宏生成的是直接成员、不要求任何协议遵循。全仓库无人遵循它，已删除。

这是一处 **breaking change**：外部若有 `struct Foo: Loggable {}` 这样的代码，改为在类型上标 `@Loggable` 即可，能力完全覆盖（还多了 `logger(for:)` 分类支持）。

### `OSToolbox` 不依赖 Foundation

删掉 `Loggable` 协议后，`OSToolbox` 源码里对 Foundation 的唯一使用点（协议默认实现里的 `Bundle(for: BundleClass.self)`）也随之消失，于是这个最底层的 target 得以只依赖 `os` 和标准库。目前每个文件的 import：

| 文件 | import |
|---|---|
| `Exported.swift` | `@_exported import FrameworkToolbox`、`@_exported import os` |
| `LoggableMacroSupport.swift` | `os.log` |
| `Mutex.swift` | `os.lock` |
| `OSAllocatedUnfairLock+UnsafeModify.swift` | `os` |
| `Macros/LogMacro.swift` | `ObjectiveC` |
| `Macros/LoggableMacro.swift` | `os.log`、`FrameworkToolbox` |
| `LogCategory.swift`、`WeakBox.swift` | 无 |

顺带修掉一处隐式依赖：`Macros/LogMacro.swift` 用了 `NSObject` 却一行 import 都没写，靠的是 `Exported.swift` 里的 `@_exported import os`——**`@_exported import` 与普通 import 不同，它在当前模块内是全模块可见的**，很容易被无意中依赖。现已显式写 `import ObjectiveC`（`NSObject` 的实际归属模块，比 Foundation 轻得多），并实测：把 `@_exported import os` 注释掉后 `OSToolbox` 仍能独立编译。

### 默认 subsystem 去掉 bundle identifier 兜底

`@Loggable` 不指定 `subsystem:` 时，原先展开成 `Bundle.main.bundleIdentifier ?? "TypeName"`（类走 `Bundle(for: self)`）。这段代码落在**调用方**文件里，所以调用方必须 `import Foundation`，否则报 `cannot find 'Bundle' in scope`——而报错位置指向宏展开，源码里根本看不到 `Bundle` 字样。`OSToolbox` 不再 re-export Foundation 之后，这个坑就暴露了。

值得单独记一笔的是：**在生成的代码里加 `#if canImport(Foundation)` 并不能解决**，实测确认过。`canImport` 问的是"这个模块**能不能**被导入"，在 Apple 平台上对 Foundation 永远为真，与当前文件是否 import 过它无关——守卫通过，展开照样失败。

最终的处理是**不兜底**：未指定 `subsystem:` 就用类型名，与 category 的默认值同一个字符串。

```swift
@Loggable
struct MyService {}

// 展开：
// static var category: String { "MyService" }
// static var subsystem: String { "MyService" }
```

理由是 bundle identifier 这个默认值本身价值有限——它对同一个 App 里的所有类型都是同一个字符串，起不到区分作用，而真想按模块分组的人本来就会显式传 `subsystem:`。去掉之后收获是实打实的：`OSToolbox` 彻底不依赖 Foundation，宏展开也不再对调用方提出任何隐藏的 import 要求。命令行工具这类没有 bundle identifier 的进程，此前会静默落到 `?? "TypeName"` 分支，行为与现在完全一致。

顺带删掉了因此变成死代码的 `ConcreteStyle` 枚举与 `resolveConcreteStyle`——它们唯一的用途就是区分 class 走 `Bundle(for:)`、其余走 `Bundle.main`。

回归防护是编译期的：`Sources/OSToolboxClient/LoggableWithoutFoundation.swift` 刻意不写 `import Foundation`，一旦默认值再次引用 Foundation 的任何东西就会编译失败。

### `@_exported import os` 跟着 `@Loggable` 走

`@Loggable` 和 `#log` 展开出的代码会写 `os.Logger`、`OSLog`、`os_log`，所以每个使用点都得有 `os` 在作用域里。这个 re-export 原本在 `FoundationToolbox/Exported.swift`；宏搬到 `OSToolbox` 之后，re-export 也跟到 `OSToolbox/Exported.swift`，否则在 `ObjCRuntimeToolbox` 里标一个 `@Loggable` 就会得到一堆"cannot find 'os' in scope"——而报错位置在宏展开里，源码上根本看不出缺了什么。

## 影响面

- **对现有使用者：无。** 三条 import 路径都验证过，全量测试从 402 个增长到 441 个且全部通过（增量来自新增的 Dynamic 测试和 `weak` 快照测试，没有测试被删）。
- **`ObjCRuntimeToolbox` 是 `.dynamic` product。** 静态的 `OSToolbox` 会被嵌进那个 dylib，所以 `Loggable` 的 logger 缓存字典在 dylib 和主程序里各存在一份。后果仅仅是多创建几个 `os.Logger` 实例——`os.Logger` 本身无状态，不影响正确性。`Mutex` 是 `@_alwaysEmitIntoClient` 的 header-only 实现，完全不受影响。
- **`ObjCRuntimeToolbox` 内部尚未改造。** `DynamicSubclass` 和 `RuntimeMethodHook` 里手写的 `os_unfair_lock` 和裸 `os_log` 现在**可以**换成 `@Mutex` 和 `@Loggable` 了，但这次没动——那是独立的一次重构，改动面和风险都跟本次无关，不该混在一起。新写的 `DynamicInvocation` 目录直接用了新设施。

## 迁移注意事项

新代码建议直接 `import OSToolbox`，而不是绕道 `SwiftStdlibToolbox` / `FoundationToolbox`——依赖关系更准确，也不会顺带拉进用不上的层。旧代码不用改。
