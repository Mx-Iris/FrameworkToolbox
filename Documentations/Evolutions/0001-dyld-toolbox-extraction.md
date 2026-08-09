# 0001 - 把 dyld interposing 抽成独立的 DyldToolbox

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-08
- **最后更新**: 2026-08-08
- **所属愿景**: 无
- **关联提案**: 无
- **实现分支 / PR**: `main`（直接落地）
- **配套文档**: 无单独成篇 —— 判断理由见「落地结果」一节

## 摘要

把 `@DyldInterpose` / `@DyldDynamicInterpose` 这一整套 dyld interposing 能力，从
`SwiftStdlibToolbox` / `SwiftStdlibToolboxMacros` 里搬到新的 `DyldToolbox` /
`DyldToolboxMacros` 两个 target，并新增一个 `DyldToolbox` library product。
`SwiftStdlibToolbox` 通过 `@_exported import DyldToolbox` 把它再导出去，
所以现有调用点（`import SwiftStdlibToolbox` 或 `import FoundationToolbox` 后直接用宏）
一行都不用改。

纯搬迁：不改任何 API 签名，不改任何宏展开结果。

## 动机

`SwiftStdlibToolbox` 现在装着两类完全不相干的东西：

1. **真正的 Swift 标准库扩展与通用宏** —— `ArrayBuilder`、`ComparableBuildable`、
   `Collection`/`Sequence` 扩展、`@Equatable`、`@AssociatedValue`、`@CaseCheckable`、
   `@AvailableNonMutating`、`@AddAsync` 系列。这些跟平台无关，纯语言层。
2. **dyld interposing** —— `Sources/SwiftStdlibToolbox/DyldInterpose/` 下的 5 个运行时文件、
   `Macros/` 下的 2 个宏声明、`SwiftStdlibToolboxMacros/` 下的 3 个宏实现文件。
   这些是 Mach-O / dyld 专属的二进制层能力，跟「Swift 标准库」没有任何关系。

具体证据：

- **依赖被拖到了不该在的层。** `Package.swift:75` 让 `SwiftStdlibToolbox` 依赖
  C target `PointerAuthenticationSupport`。这个 C target 存在的唯一理由是给
  `DyldDynamicInterpose` 提供 arm64e 的指针签名/剥离 intrinsic
  （`Package.swift:78-83` 的注释写得很清楚）。结果是：任何只想用 `@Equatable` 的使用方，
  也被迫链上一个 arm64e pointer-authentication 的 C shim。
- **这一坨代码跟宿主 target 零耦合，说明它本来就不属于这里。** 实测：
  `Sources/SwiftStdlibToolbox/DyldInterpose/*.swift` 的 import 只有
  `Darwin` / `MachO` / `os.lock` / `PointerAuthenticationSupport`
  （见「前期调研」的实测结果），完全没有用到 `SwiftStdlibToolbox` 自己的任何东西，
  也没用到经 `OSToolbox` re-export 过来的 `@Mutex` / `@Loggable`。
  宏实现侧同理：3 个 Dyld 宏实现文件只 import `swift-syntax` 的四个模块，
  连共享的 `MacroToolbox` 都没用。
- **平台适用面不同。** stdlib 扩展在任何 Swift 平台都成立；dyld interposing 是
  Apple 平台专有，宏展开体整个包在 `#if canImport(Darwin)` 里。把两者塞进同一个 product，
  等于让 product 的语义变成「Swift 扩展，外加一个只在 Apple 平台生效的二进制 hook 子系统」。
- **无法单独依赖。** 现在想只要 dyld interposing（例如一个纯粹的注入 dylib 项目），
  必须 `import SwiftStdlibToolbox`，连带把 `OSToolbox`、`FrameworkToolbox`、`os` 全拉进来
  —— 这正是 `OSToolbox` 抽取（`Specs/2026-08-06-ostoolbox-extraction-design.md`）
  当初要解决的同一类问题，只是方向相反：那次是让上层能只要 `os` 那部分，这次是让使用方能只要
  dyld 那部分。

## 前期调研

### 现状代码怎么走的

**运行时（5 个文件，全部在 `Sources/SwiftStdlibToolbox/DyldInterpose/`）**

| 文件 | 内容 |
|------|------|
| `DyldDynamicInterpose.swift` | `public enum DyldDynamicInterpose`，`applyAll` / `apply` / `revertAll` / `registeredTuples` |
| `DyldDynamicInterposeTuple.swift` | `public struct DyldDynamicInterposeTuple`，internal `enum DyldDynamicInterposeRegistry`（用 `getsectiondata` 读回 `__DATA,__dyn_interpose`） |
| `DyldDynamicInterposeTargetImages.swift` | `public struct DyldDynamicInterposeTargetImages`（`.allImages` / `.mainExecutable` / `.image(_:)` / `.imagesWithPath(...)`） |
| `DyldDynamicInterposeReport.swift` | `public struct DyldDynamicInterposeReport` 及其 `RewrittenSlot` / `SkippedSlot` |
| `MachOImageScanner.swift` | internal `LoadedMachOImage` / `SymbolPointerSection` / `MachOImageScanner` |

**宏声明（2 个文件，在 `Sources/SwiftStdlibToolbox/Macros/`）**

- `DyldInterposeMacro.swift` —— `public macro DyldInterpose(_ target: Any)`，
  `#externalMacro(module: "SwiftStdlibToolboxMacros", type: "DyldInterposeMacro")`
- `DyldDynamicInterposeMacro.swift` —— 同上，指向 `DyldDynamicInterposeMacro`

**宏实现（3 个文件，在 `Sources/SwiftStdlibToolboxMacros/`）**

- `DyldInterposeMacro.swift`、`DyldDynamicInterposeMacro.swift`、`DyldInterposeSupport.swift`
  （后者持有全部解析、校验与代码生成，两个宏只差一个 `DyldInterposeExpansionConfiguration`）
- 注册点：`SwiftStdlibToolboxMacros/MainPlugin.swift:14-15`

**C target**

- `Sources/PointerAuthenticationSupport/`（`.c` + `include/*.h`），
  现挂在 `SwiftStdlibToolbox` 的依赖上（`Package.swift:75`）

**测试（3 个文件）**

- `Tests/SwiftStdlibToolboxTests/DyldDynamicInterposeTests.swift` —— 用了
  `@testable import SwiftStdlibToolbox`，并在文件顶层写了一个 `@DyldDynamicInterpose(getppid)`
- `Tests/SwiftStdlibToolboxMacroTests/DyldInterposeMacroTests.swift`
- `Tests/SwiftStdlibToolboxMacroTests/DyldDynamicInterposeMacroTests.swift`
  （后两者用 `@testable import SwiftStdlibToolboxMacros`）

### 验证过什么

- **实测：运行时零耦合宿主 target。**
  `grep -n "^import" Sources/SwiftStdlibToolbox/DyldInterpose/*.swift` 的完整输出只有
  `Darwin`、`MachO`、`PointerAuthenticationSupport`、`os.lock` 四个，
  没有一个文件 import 或引用 `SwiftStdlibToolbox` / `OSToolbox` / `FrameworkToolbox` 的符号。
  注意它是**直接** `import os.lock`，而不是靠 `OSToolbox` 的 `@_exported import os` —— 
  所以搬走之后不需要给 `DyldToolbox` 加 `OSToolbox` 依赖。
- **实测：宏实现零耦合 `MacroToolbox`。**
  `grep -n "MacroToolbox\|LockMacroProtocol\|LockPropertyParser" Sources/SwiftStdlibToolboxMacros/Dyld*.swift`
  无任何命中。三个 Dyld 宏实现文件的 import 只有 `SwiftDiagnostics` / `SwiftSyntax` /
  `SwiftSyntaxBuilder` / `SwiftSyntaxMacros`。
- **`#dsohandle` 是默认参数，在调用点求值，不在 `DyldToolbox` 内求值。**
  `DyldDynamicInterpose.swift:52` 与 `:74` 把它写成
  `declaredIn declaringImage: UnsafeRawPointer = #dsohandle`。Swift 的默认参数表达式在
  **调用方**展开，所以它指向调用方所在的 image，而不是定义 `DyldDynamicInterpose` 的 image。
  这意味着搬 target 不会改变「读哪个 image 的 `__DATA,__dyn_interpose`」这一语义 ——
  这一点必须验证，因为如果它是在函数体内求值的，把代码搬到另一个 module 就会静默读错 image。
- **`@_exported import` 会把宏声明及其插件一并带过传递依赖。** 这不是推测，是
  `OSToolbox` 抽取时实测并写进 `Specs/2026-08-06-ostoolbox-extraction-design.md` 的结论：
  `@Mutex` / `@Loggable` 下沉到 `OSToolbox` 之后，所有 `import SwiftStdlibToolbox` 的
  旧调用点无需改动即可继续解析宏与插件。本提案完全依赖这一条成立。
- **macro target 不是 product，外部无法 import。** `Package.swift` 的 `products` 里没有任何
  `*Macros`，所以把宏实现从 `SwiftStdlibToolboxMacros` 挪到 `DyldToolboxMacros`
  对仓库外的使用方是完全不可见的 —— 唯一受影响的是本仓库内
  `@testable import SwiftStdlibToolboxMacros` 的两个测试文件。
- **`README.md` 不描述 target 分层**（全文 40 行，讲的是 Claude Code plugin marketplace），
  本次改动不需要动它。需要同步的是项目级 `CLAUDE.md` 的分层表与 re-export 链说明。

## 提议方案

新增两个 target 与一个 product，把上面清点出的 10 个源文件与 3 个测试文件原样搬过去，
再由 `SwiftStdlibToolbox` re-export。

**新的依赖图**（`←` 表示「被依赖」）：

```
FrameworkToolbox ← OSToolbox ← SwiftStdlibToolbox ← FoundationToolbox
                                      ↑
PointerAuthenticationSupport ← DyldToolbox ──┘ (@_exported)
```

`DyldToolbox` 是一个不依赖 `FrameworkToolbox` 也不依赖 `OSToolbox` 的独立底层 target，
与 `FrameworkToolbox` 平级。

**文件搬迁清单**（全部原样移动，仅改必要的一行 module 名）：

| 从 | 到 |
|----|----|
| `Sources/SwiftStdlibToolbox/DyldInterpose/*.swift`（5 个） | `Sources/DyldToolbox/DyldInterpose/` |
| `Sources/SwiftStdlibToolbox/Macros/Dyld{,Dynamic}InterposeMacro.swift`（2 个） | `Sources/DyldToolbox/Macros/` |
| `Sources/SwiftStdlibToolboxMacros/Dyld{Interpose,DynamicInterpose,InterposeSupport}*.swift`（3 个） | `Sources/DyldToolboxMacros/` |
| `Tests/SwiftStdlibToolboxTests/DyldDynamicInterposeTests.swift` | `Tests/DyldToolboxTests/` |
| `Tests/SwiftStdlibToolboxMacroTests/Dyld*MacroTests.swift`（2 个） | `Tests/DyldToolboxMacroTests/` |

**内容改动**（除搬迁外，全部改动只有这几处）：

1. 两个宏声明里的 `#externalMacro(module: "SwiftStdlibToolboxMacros", ...)`
   → `module: "DyldToolboxMacros"`
2. 新建 `Sources/DyldToolboxMacros/MainPlugin.swift`，注册两个 Dyld 宏
3. `Sources/SwiftStdlibToolboxMacros/MainPlugin.swift` 删掉那两行注册
4. `Sources/SwiftStdlibToolbox/Exported.swift` 加 `@_exported import DyldToolbox`（附注释说明理由）
5. 测试文件的 `@testable import SwiftStdlibToolbox` → `DyldToolbox`，
   `@testable import SwiftStdlibToolboxMacros` → `DyldToolboxMacros`
6. `Package.swift`：新增 product / 2 个 target / 2 个 test target /
   1 个 client；`SwiftStdlibToolbox` 的依赖里把 `PointerAuthenticationSupport`
   换成 `DyldToolbox`

### 非目标

- **不改任何 public API 签名，不改任何宏展开结果。** 现有的宏展开快照测试搬过去之后
  期望字符串一个字都不用改 —— 如果需要改，说明搬错了。
- **不把 `DyldToolbox` 做成 `.dynamic` product。** 保持默认的静态 library。
  理由见下面「详细设计」里的说明；这件事有真实的取舍，但不在本提案范围内。
- **不动 `PointerAuthenticationSupport` 的实现**，只改它挂在谁的依赖上。
- **不迁移 `Specs/2026-08-06-dyld-dynamic-interpose-design.md`**。它是提案制确立前的归档，
  按 `Documentations/README.md` 的既定约定「保留归档，不再新增」，保持原样；
  只在本提案里回指它。
- **不给 `DyldToolbox` 加 `OSToolbox` 依赖**，即使它内部用了 `os_unfair_lock`。
  它是直接 `import os.lock`，加依赖只会把刚拆开的层重新粘上。

## 详细设计

### Package.swift

```swift
.library(
    // dyld interposing —— `@DyldInterpose` / `@DyldDynamicInterpose` 及其运行时。
    // 独立成 product，好让只需要二进制 hook 的使用方不必连带链上
    // `SwiftStdlibToolbox` → `OSToolbox` → `FrameworkToolbox` 整条链。
    // `SwiftStdlibToolbox` re-export 本 target，所以旧调用点无需改动。
    //
    // 刻意保持静态 library（不是 `.dynamic`）：`@DyldDynamicInterpose` 的
    // 段读取以调用方 image 为准（`#dsohandle` 默认参数在调用点求值），
    // 静态嵌入正是让「谁声明、谁的段被读」这条语义成立的形态。
    name: "DyldToolbox",
    targets: ["DyldToolbox"]
),
```

```swift
.target(
    name: "DyldToolbox",
    dependencies: [
        "DyldToolboxMacros",
        "PointerAuthenticationSupport",
    ]
),
.macro(
    name: "DyldToolboxMacros",
    dependencies: [
        // 刻意不依赖 `MacroToolbox`：那里放的是锁类宏共享的
        // `LockMacroProtocol` / `LockPropertyParser`，Dyld 宏一个都不用。
        .SwiftSyntax,
        .SwiftSyntaxMacros,
        .SwiftCompilerPlugin,
        .SwiftSyntaxBuilder,
        .SwiftDiagnostics,
    ]
),
```

`SwiftStdlibToolbox` 的依赖变为：

```swift
.target(
    name: "SwiftStdlibToolbox",
    dependencies: [
        "FrameworkToolbox",
        "OSToolbox",
        "SwiftStdlibToolboxMacros",
        // 取代原先的 `PointerAuthenticationSupport`：那个 C shim 现在是
        // `DyldToolbox` 的实现细节，本 target 不再直接接触它。
        "DyldToolbox",
    ]
),
```

新增测试与 client target：

```swift
.executableTarget(name: "DyldToolboxClient", dependencies: ["DyldToolbox"]),
.testTarget(name: "DyldToolboxTests", dependencies: ["DyldToolbox"]),
.testTarget(
    name: "DyldToolboxMacroTests",
    dependencies: [
        "DyldToolboxMacros",
        .product(name: "MacroTesting", package: "swift-macro-testing"),
    ]
),
```

### `Sources/SwiftStdlibToolbox/Exported.swift`

在现有的 `@_exported import OSToolbox` 之后追加：

```swift
// dyld interposing 抽到了 `DyldToolbox`，好让只需要二进制 hook 的使用方
// 不必连带链上这一整层 Swift 扩展。Re-export 让这次拆分对调用点完全不可见：
// 一直写 `import SwiftStdlibToolbox` 然后用 `@DyldInterpose` 的代码，
// 仍然能解析到宏声明、宏插件，以及 `DyldDynamicInterpose` 运行时。
@_exported import DyldToolbox
```

### `Sources/DyldToolboxMacros/MainPlugin.swift`（新建）

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DyldInterposeMacro.self,
        DyldDynamicInterposeMacro.self,
    ]
}
```

### `DyldToolboxClient`

仓库里 6 个 library product 各自都有一个 `*Client` executable 做人工展开验证，
新 product 补齐这一惯例。它同时是 `@DyldDynamicInterpose` 唯一能被真实演示的地方 ——
`@DyldInterpose` 只在 dylib 里生效，executable 里演示不了。

目标函数沿用测试里的 `getppid`：进程里没有别的东西调用它，改写它不会干扰运行。

```swift
import Darwin
import DyldToolbox

@DyldDynamicInterpose(getppid)
func interposedGetParentProcessIdentifier() -> pid_t { 424_242 }

let report = DyldDynamicInterpose.applyAll()
print("rewrote \(report.rewrittenSlots.count) slot(s)")
print("getppid() -> \(getppid())")
DyldDynamicInterpose.revertAll()
```

### 关于「为什么不做成 `.dynamic`」

`ObjCRuntimeToolbox` 是 `.dynamic`，理由是它的运行时侧表必须是进程内唯一一份。
`DyldToolbox` 有一个形似的状态 —— `DyldDynamicInterpose` 里用于 `revertAll()` 的
`sharedState` 簿记 —— 静态链接时每个嵌入它的 image 各有一份，
于是一个 image 的 `revertAll()` 撤不掉另一个 image 发起的改写。

但这是**既有行为**（现在它在 `SwiftStdlibToolbox` 里，同样是静态的），本提案是纯搬迁，
不改变它。而且这里的取舍跟 `ObjCRuntimeToolbox` 不同：`@DyldDynamicInterpose` 的
段读取以调用方 image 为准，「谁声明、谁 apply、谁 revert」本来就是按 image 划分的，
每 image 一份簿记与这个模型是自洽的。真要改成 `.dynamic`，属于独立的行为变更，
应另开提案。

## 替代方案考量

- **只搬宏、把运行时留在 `SwiftStdlibToolbox`。** 用户原话是「把 Dyld 相关的宏抽出来」，
  字面上只涉及宏。否掉的理由：`@DyldDynamicInterpose` 的宏和它的运行时是一件东西的两半 ——
  宏往 `__DATA,__dyn_interpose` 里写 tuple，运行时把它读回来改写符号槽，
  段名这个契约由两边共同持有（宏侧在 `DyldInterposeSupport.swift`，
  运行时侧在 `DyldDynamicInterposeTuple.swift`）。把它们拆到两个 target，
  等于让一个 target 的宏依赖另一个 target 的运行时才有意义，
  而且 `PointerAuthenticationSupport` 这个纯 dyld 用途的 C shim 会继续挂在
  `SwiftStdlibToolbox` 上 —— 动机里点名的那个问题一个都没解决。
  **本提案按「dyld interposing 这件事整体搬走」处理**，如果你要的确实只是宏本身，
  这里需要一次明确的确认。
- **把 `PointerAuthenticationSupport` 并进 `DyldToolbox`（作为 C 混合源码）。**
  否掉：SPM 的 target 不支持 Swift 与 C 混排，必须是独立 target。
  保持它独立、只改依赖归属是唯一可行解。
- **让 `DyldToolbox` 依赖 `OSToolbox` 以复用 `@Mutex`。** 否掉：现有代码直接用
  `os_unfair_lock`（`import os.lock`），不需要 `@Mutex`；加这条依赖会把刚拆开的层重新粘上，
  与本提案的目的相反。
- **不 re-export，让使用方显式 `import DyldToolbox`。** 否掉：这是破坏性源码改动，
  与用户明确的「不影响外面」要求冲突。`OSToolbox` 抽取时已经确立了
  「拆层靠 re-export 对调用点隐身」的做法，本次沿用。
- **命名为 `MachOToolbox` / `InterposeToolbox`。** 否掉：`DyldToolbox` 是用户指定的名字，
  且两个宏都以 `Dyld` 开头、运行时类型也全是 `DyldDynamicInterpose*`，一致。

## 影响

### 源码兼容性（source compatibility）

**纯新增，不破坏任何现有调用点。** 逐条说明为什么：

| 现有写法 | 搬迁后 | 为什么仍然成立 |
|---------|--------|--------------|
| `import SwiftStdlibToolbox` + `@DyldInterpose(...)` | 不变 | `SwiftStdlibToolbox` `@_exported import DyldToolbox`，宏声明与插件随之传递 |
| `import FoundationToolbox` + `DyldDynamicInterpose.applyAll()` | 不变 | `FoundationToolbox` → `SwiftStdlibToolbox` → `DyldToolbox`，re-export 链走通 |
| 宏展开出的代码 | 不变 | 展开体只引用调用方自己的函数与 `Darwin` 符号，不提任何 toolbox module；段名、`@convention(c)` tuple 布局、`#if` 条件全部原样 |
| `@testable import SwiftStdlibToolboxMacros` | **需改** | 仅本仓库两个宏测试文件；`*Macros` 不是 product，仓库外无法 import |
| `@testable import SwiftStdlibToolbox` 后触碰 `MachOImageScanner` 等 internal 符号 | **需改** | 仅本仓库一个测试文件；这些符号 internal，仓库外本就不可见 |

需要 `@available(*, deprecated, renamed:)` 过渡的地方：**没有**。
没有任何 public 符号改名或移除，只是换了定义它的 module，而 re-export 让这一点不可观测。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

**本仓库内受影响的 target：**

- `SwiftStdlibToolbox` —— 少 7 个源文件，依赖表里 `PointerAuthenticationSupport` 换成 `DyldToolbox`，`Exported.swift` 多一行
- `SwiftStdlibToolboxMacros` —— 少 3 个源文件，`MainPlugin` 少 2 行注册
- `SwiftStdlibToolboxTests` / `SwiftStdlibToolboxMacroTests` —— 各少若干测试文件
- `FoundationToolbox` / `FoundationToolboxClient` —— 无源码改动，但传递依赖多一层（经 re-export 拿到 `DyldToolbox`）
- 其余 target（`FrameworkToolbox`、`OSToolbox`、`CoreFoundationToolbox`、`ObjCRuntimeToolbox`）—— 无影响

**跨仓库：** 下游只要还是 `import SwiftStdlibToolbox` / `import FoundationToolbox`，
零改动。用了 `@testable import` 深入 internal 符号的下游会受影响，
但那本来就不是受支持的用法。

### 文档与示例

- `CLAUDE.md`（项目级）—— **必须更新**：分层表新增 `DyldToolbox` 一行；
  「Dependency chain」补上新分支；「Re-export chain」补上 `SwiftStdlibToolbox` re-export `DyldToolbox`；
  `PointerAuthenticationSupport` 那句「backing `@DyldDynamicInterpose`」改成挂在 `DyldToolbox` 下；
  「Interposing macros」条目里的文件路径全部更新
- `Documentations/README.md` —— Specs 索引里 `@DyldDynamicInterpose` 那条补一句
  「实现已于提案 0001 迁至 `DyldToolbox`」，并指向本提案
- `Documentations/Evolutions/README.md` —— 提案索引由「尚无提案」改为表格，登记本提案
- `Documentations/Specs/2026-08-06-dyld-dynamic-interpose-design.md` —— **不改内容**（归档保持原貌），
  只在开头加一行指向本提案的「实现位置已变更」提示
- `README.md` —— 不需要改（不描述 target 分层）

## API 演进与废弃策略

- 没有 API 被替代或废弃，无需 `@available(*, deprecated)`。
- 不需要 semver major 跃迁：对所有受支持的用法都是源码兼容的。

## 落地步骤

每一步都应能单独 `swift build` 通过。

1. **建 `DyldToolboxMacros`** —— 搬 3 个宏实现文件，新建 `MainPlugin.swift`；
   `Package.swift` 加 `.macro` target；从 `SwiftStdlibToolboxMacros/MainPlugin.swift`
   删掉两行注册。
2. **建 `DyldToolbox`** —— 搬 5 个运行时文件 + 2 个宏声明文件，
   把宏声明里的 `#externalMacro(module:)` 改成 `"DyldToolboxMacros"`；
   `Package.swift` 加 target、product，并把 `PointerAuthenticationSupport`
   从 `SwiftStdlibToolbox` 的依赖移到 `DyldToolbox`。
3. **接上 re-export** —— `SwiftStdlibToolbox/Exported.swift` 加
   `@_exported import DyldToolbox`（带注释），`Package.swift` 里 `SwiftStdlibToolbox`
   依赖加 `DyldToolbox`。
4. **搬测试** —— 建 `Tests/DyldToolboxTests` 与 `Tests/DyldToolboxMacroTests`，
   改 `@testable import` 的 module 名，`Package.swift` 加两个 test target。
   **宏展开的期望字符串必须一个字都不改**；改了就说明搬迁不是等价的。
5. **加 `DyldToolboxClient`** —— 补齐「每个 library product 配一个 client」的惯例。
6. **验证** —— `swift build 2>&1 | xcsift` 与 `swift test 2>&1 | xcsift` 全绿；
   另外单独构建 `DyldToolbox` 单 target，确认它不需要 `FrameworkToolbox` / `OSToolbox`；
   并写一个只 `import SwiftStdlibToolbox` 就用 `@DyldInterpose` 的编译期用例
   （放进 `SwiftStdlibToolboxClient` 或测试），把「re-export 让旧调用点仍然成立」
   钉成编译期保证，而不是靠人记得。
7. **同步文档** —— 按上面「文档与示例」逐条更新，与代码进同一个 commit。

**收尾判断：**

- **要不要配套实现说明** —— 倾向不写。本次是等价搬迁，没有引入
  「下次维护会踩、代码本身看不出来」的新决策；两个值得记的判断
  （`#dsohandle` 在调用点求值、为何不做成 `.dynamic`）已经分别落在
  `Package.swift` 注释和本提案里。落地时若发现有第三条这样的坑，再补一篇。
- **有没有引入新术语** —— 无。`interpose`、`__DATA,__interpose`、`symbol pointer slot`
  等术语在 `Specs/2026-08-06-dyld-dynamic-interpose-design.md` 中已解释。
  本仓库目前没有 `Documentations/Glossary.md`；是否新建不由本提案决定。

## 落地结果

### 与提案的差异

**一、`DyldToolbox` 最终依赖了 `OSToolbox`，改用 `Mutex` 取代手写的 `os_unfair_lock`
（推翻了提案的「非目标」与「替代方案考量」两处结论）。**

上文「非目标」写着「不给 `DyldToolbox` 加 `OSToolbox` 依赖」，「替代方案考量」也把
「依赖 `OSToolbox` 以复用锁」列为否掉的方案，理由是「会把刚拆开的层重新粘上」。
落地当天用户明确要求反过来做。**按上级决定执行，原文保留不改**（提案是决策快照，
不回头修改让它符合实现）。

改法：`DyldDynamicInterpose.swift` 里那个手搓的 `DyldDynamicInterposeState`
—— 一个 `final class` 加一个手动 `allocate` 的 `UnsafeMutablePointer<os_unfair_lock>`，
外带两个 `os_unfair_lock_lock` / `unlock` 配对的方法 —— 整个删掉，
换成一行 `private let rewrittenSlotRecordsByApplicationOrder = Mutex<[RewrittenSlotRecord]>([])`。
`OSToolbox` 的 `Mutex` 把锁和被保护的值放进同一块分配里，正是原代码在手工重复的东西。
净减约 20 行，`import os.lock` 也随之换成 `import OSToolbox`。

**后果，需要如实记下来：** 提案动机里「让只想要 dyld hook 的使用方不必链上整条链」
这一条被削弱了 —— `DyldToolbox` 现在会带上 `OSToolbox` 和（经其 re-export 的）
`FrameworkToolbox`。仍然成立的部分是：
- 使用方不必再链上 `SwiftStdlibToolbox` / `FoundationToolbox` 这两层 Swift 扩展；
- **反向那一半完全没受影响**，而且它才是动机里更硬的那条 —— 只想用 `@Equatable` 的人
  不再被迫链上 arm64e 的 pointer-authentication C shim，因为
  `PointerAuthenticationSupport` 已经改挂在 `DyldToolbox` 之下。

**二、`SwiftStdlibToolboxClient/main.swift` 末尾新增了一段 re-export 编译期探针。**

提案的落地步骤 6 只写了「写一个编译期用例」，没定位置。实际选在 client 而不是测试里，
理由是安全性：test bundle 是 dylib，dyld **会**消费其中的 `__DATA,__interpose`，
在那里放 `@DyldInterpose` 等于让测试进程真的被 interpose；executable 里 dyld 不看这个段，
所以两个宏都能安全地只做编译验证。探针里的 `@DyldDynamicInterpose` 同样无副作用 ——
不调 `applyAll()` 就什么都不发生。

其余全部按提案执行，无偏差。

### 验证结果

- `swift build` / `swift test` 全绿：**454 个测试通过，0 warning、0 error**。
- 搬过去的 Dyld 测试单独跑：**23 个测试、3 个 suite 全过**
  （`swift test --filter DyldToolbox`）。
- **宏展开快照的期望字符串一个字都没改，测试仍然通过** —— 这是「等价搬迁」最直接的证据。
  提案里预先声明过「要是需要改期望字符串，就说明搬错了」，结果是不需要改。
- **分层实测：** 从**干净的** scratch path 单独构建 `swift build --target DyldToolbox` 成功。
  搬迁刚完成时它连 `FrameworkToolbox` / `OSToolbox` 都不编，是彻底的叶子；
  加上 `Mutex` 依赖之后（见「与提案的差异」第一条），
  它编 `DyldToolboxMacros`、`DyldToolbox`、`PointerAuthenticationSupport`、`OSToolbox`、
  `FrameworkToolbox` 与 swift-syntax，**仍然不碰** `SwiftStdlibToolbox` / `FoundationToolbox`。
  动机里点名的「只想用 `@Equatable` 却被迫链上 arm64e C shim」这个反向问题不受影响，
  已彻底解决。
- **`DyldToolboxClient` 实跑通过：** 从主执行文件 `applyAll()` 改写 1 个符号槽，
  `getppid()` 由真实 ppid 变为 `424242`，`revertAll()` 恢复 1 个槽、返回值变回真实 ppid。
  这条路径（主执行文件发起 + 可撤销）正是 `@DyldDynamicInterpose` 相对 `@DyldInterpose`
  的全部意义所在，现在有了一个能直接 `swift run` 的活体演示。

### 收尾判断

- **配套专题文章：不写。** 判据是「有没有引入下次维护会踩、代码本身看不出来的新决策」。
  本次是等价搬迁，没有新增这类决策。两个确实值得记的判断已各就各位：
  `#dsohandle` 在调用点求值、以及由此决定的「不做成 `.dynamic`」，写进了 `Package.swift`
  的 product 注释和项目 `CLAUDE.md` 的「Interposing macros」条目；
  re-export 靠 client 探针钉住这一模式，也写进了 `CLAUDE.md` 的 re-export 链一节。
  单独写一篇只会是把这些重复一遍。
- **新术语：无。** `interpose`、`__DATA,__interpose`、symbol pointer slot 等术语在
  `Specs/2026-08-06-dyld-dynamic-interpose-design.md` 中已有解释，本次未引入新词。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-08 | Created as Draft | 调研完成：确认 dyld interposing 与宿主 target 零耦合、宏实现不依赖 `MacroToolbox`、`#dsohandle` 在调用点求值。方案定为「整体搬迁 + re-export 隐身」 |
| 2026-08-08 | Accepted → In Progress | 用户确认按「整个 dyld 子系统」搬迁（而非只搬宏声明与实现），并确认补 `DyldToolboxClient`。开始实施 |
| 2026-08-08 | In Progress → Implemented | 13 个文件全部以 `git mv` 搬迁（历史保留）。454 个测试通过，宏展开快照期望值未作任何修改。干净环境下单独构建 `DyldToolbox` 确认不牵连 `FrameworkToolbox` / `OSToolbox`。re-export 探针改放 client 而非测试，理由见「与提案的差异」 |
| 2026-08-08 | 落地后修订：加 `OSToolbox` 依赖 | 用户要求 `DyldToolbox` 依赖 `OSToolbox` 并去掉手写的 `os_unfair_lock`，推翻了本提案「非目标」与「替代方案考量」中的对应结论。原文保留不改，反转与后果记入「与提案的差异」第一条。454 个测试仍全部通过 |
