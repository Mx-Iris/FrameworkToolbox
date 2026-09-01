# 0003 - 把 ObjCRuntimeToolbox 恢复为自包含的 `.dynamic` 叶子

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-01
- **最后更新**: 2026-09-01
- **所属愿景**: 无
- **关联提案**: 无（前因见 `Specs/2026-08-06-ostoolbox-extraction-design.md`，本提案撤销其中「ObjCRuntimeToolbox 依赖 OSToolbox」的一步）
- **实现分支 / PR**: `main`（直接落地）
- **配套文档**: 无 —— 判断见决策日志

## 摘要

解除 `ObjCRuntimeToolbox` target 对 `OSToolbox` 的运行时依赖，使其回到 0.9.0 的形态：
一个除宏 target 外零依赖的自包含 `.dynamic` 叶子。`DynamicInvocation/` 下两个文件的
`@Loggable` / `#log` 改写为 target 内其余文件既有的静态 `OSLog` + `os_log` 风格；
新增一个 `swift package dump-package` 守卫测试，断言该 target 的依赖恒为宏-only，防止
传染在将来悄悄回归。完成后以 **0.11.0** 发布，RuntimeViewer 解锁其临时的 0.9.0 exact 锁。

## 动机

RuntimeViewer v3.0.0-beta.2 的 SMAppService daemon（嵌在 app bundle
`Contents/Library/LaunchServices/` 里的可执行文件）在 dyld 阶段崩溃循环：
`Library not loaded: @rpath/FrameworkToolbox.framework`。机制链条（RuntimeViewer 侧
runtimeviewer-c3 会话实测并交接，本仓库侧已核实前三步）：

1. `ObjCRuntimeToolbox` 产品声明为 `.dynamic`（`Package.swift` 注释写明理由：
   isa-swizzling 的 side table、subclass cache 与 associated-object sentinel key
   要求全进程单份，见「前期调研」的完整清单）。
2. 0.10.0 给该 target 加了 `OSToolbox` 运行时依赖（初衷：用上 `Mutex` / `@Loggable`）。
3. Xcode 会把 `.dynamic` 产品的**传递 target** 一并建成共享动态 framework——于是
   `OSToolbox`、`FrameworkToolbox` 也变成了动态 framework，workspace 里**所有**客户端
   （包括根本不用 `ObjCRuntimeToolbox` 的 daemon）都改为 @rpath 动态链接它们。
4. app 主可执行有 `@executable_path/../Frameworks` rpath 所以没事；daemon 这类嵌套可执行
   没有 rpath，直接崩。0.9.0 的拓扑（`ObjCRuntimeToolbox` 自包含、无运行时 target 依赖）
   没有这个问题。

用户授权在两个候选方案（A：自包含叶子；B：静态化 + runtime 级去重）中自选其一，
经调研后选定 A，理由见「替代方案考量」。

## 前期调研

均为本仓库内实测核实，标注出处；唯一来自外部的事实（Xcode 传染行为）已注明来源。

- **0.9.0 → 0.10.0 的拓扑变化**（`git show 0.9.0:Package.swift` / `0.10.0:Package.swift`）：
  0.9.0 时 `ObjCRuntimeToolbox` target 只依赖 `ObjCRuntimeToolboxMacros`——宏 target 是
  编译期插件，不进产品的链接闭包，所以 `.dynamic` 不传染任何东西。0.10.0 加了 `OSToolbox`，
  传染自此开始。
- **`OSToolbox` 的实际使用面远小于分层初衷**：整个 target 只有
  `DynamicInvocation/RuntimeInvocation.swift`（1 处 `@Loggable` + 3 处 `#log`）和
  `DynamicInvocation/DynamicObject.swift`（1 处 `@Loggable` + 8 处 `#log`）import 了
  `OSToolbox`。`Mutex` / `WeakBox` / `AccessLevel` / `FrameworkToolboxCompatible`：**零使用**。
- **「为了 Mutex」的预期从未兑现，而且是刻意的**：`DynamicSubclass.swift:864-868` 与
  `RuntimeMethodHook.swift:376-377` 的注释都写明选择 `os_unfair_lock` 是为了守住
  macOS 10.15 floor 并避免依赖（`OSAllocatedUnfairLock` 有 macOS 13 门槛）。
- **target 内既有日志风格就是静态 `OSLog` + `os_log`**：`DynamicSubclass.runtimeLog`
  （`DynamicSubclass.swift:878`）、`RuntimeMethodHook.hookLog`（`RuntimeMethodHook.swift:381`），
  以及 `RuntimeClassProxySupport.swift`。改写两个 `DynamicInvocation/` 文件后全 target 风格统一。
- **全进程单份状态的完整清单**（`.dynamic` 的存在理由，比事故交接消息列的多一组）：
  - `DynamicSubclass.swift:868-876`：`sharedLockStorage`、`sharedSubclassCache`、
    `sharedSideTable`、`sharedInstalledOverrides`、`nextGeneration`；
  - `DynamicSubclass.swift:1045`：`sentinelAssociationKey`（拿变量地址当
    associated-object key）；
  - `RuntimeMethodHook.swift:378-379`：`sharedLockStorage`、`sharedInstalledMethods`
    ——事故交接消息未列出的一组，方案 B 的工程面因此比对方预估的更大。
- **解除依赖不构成 API 破坏**：`Exported.swift` 只 `@_exported import` Foundation 与
  ObjectiveC，从未 re-export `OSToolbox`；SwiftPM 的 product 边界也使得只依赖
  `ObjCRuntimeToolbox` 产品的消费者本就无法 `import OSToolbox`。
- **仓库内无连带受害者**：`ObjCRuntimeToolboxClient` / `ObjCRuntimeToolboxSoleImportClient` /
  `Tests/ObjCRuntimeToolboxTests` 均未 import 其他 toolbox 层（grep 核实，零命中）；
  repo 内也没有别的 target 依赖 `ObjCRuntimeToolbox`。
- **直接 `os_log` 在这两个文件里没有 `String: CVarArg` 顾虑**：`#log` 展开避开 CVarArg
  （改用 `String.withCString`）是为无 Foundation 的模块服务的（见 CLAUDE.md 该节）；
  这两个文件本就 `import Foundation`，且整个 target re-export Foundation，直接用
  `os_log("%{public}@", …)` 无风险。
- **Xcode 对 `.dynamic` 传递闭包的行为**：来自 RuntimeViewer 侧实测（`otool -L` 证据在
  他们仓库），0.9.0 拓扑同一 workspace 无此问题——即方案 A 的最终形态已被生产环境验证过。

## 提议方案

1. **`Package.swift`**：`ObjCRuntimeToolbox` target 的依赖回到 `["ObjCRuntimeToolboxMacros"]`。
   同步更新两处注释：`OSToolbox` 产品注释撤掉「notably `ObjCRuntimeToolbox`」的表述；
   `ObjCRuntimeToolbox` 产品注释追加硬约束——**不得添加任何运行时 target 依赖**，
   否则 Xcode 会把传递闭包整体建成共享动态 framework，workspace 内无 rpath 的嵌套可执行
   （daemon / XPC helper）会在 dyld 阶段崩溃。
2. **日志改写**：`RuntimeInvocation.swift` 与 `DynamicObject.swift` 移除 `import OSToolbox`
   与 `@Loggable`，共用一个 internal 的 `OSLog` 常量（同一对
   `subsystem: "ObjCRuntimeToolbox", category: "DynamicInvocation"`，保持既有的
   `log stream` 谓词继续覆盖整条调用路径），11 处 `#log` 改写为 `os_log`，
   privacy 标注逐处映射（`privacy: .public` → `%{public}@`；默认 private → `%@`）。
3. **防回归守卫**：`ObjCRuntimeToolboxTests` 新增一个测试，运行
   `swift package dump-package` 并断言 `ObjCRuntimeToolbox` target 的 `dependencies`
   恒等于宏-only。守卫必须**先看着它红过**：临时把 `OSToolbox` 依赖加回去确认测试失败，
   再恢复（沿用本仓库「a guard nobody has watched break is not a guard」的惯例）。
4. **文档同步**：详见「影响 → 文档与示例」。

### 非目标

- **不做方案 B**（静态化 + runtime 级去重）——评估与否决理由见「替代方案考量」。
- **不改 `.dynamic` 本身**：三组全进程单份状态的单拷贝语义原样保留。
- **不为这两个文件造私有 logging shim**：不重造 `#available` 门控的 `os.Logger` 包装
  （用户已裁决，见决策日志）。
- **不动其他层的拓扑**：`DyldToolbox`、`SwiftStdlibToolbox`、`FoundationToolbox` 的
  依赖与 re-export 链一律不碰。
- **不处理「两个 image 各静态嵌入一份」的跨拷贝一致性**——`.dynamic` 叶子本来就阻止
  这种链接形态出现。

## 详细设计

### 日志改写对照

共用常量（放在 `DynamicInvocation/` 下，两个文件可见）：

```swift
// One OSLog for the whole DynamicInvocation path — DynamicObject and
// RuntimeInvocation share the subsystem/category pair on purpose, so a
// single `log stream` predicate covers wrap → member lookup → invocation.
let dynamicInvocationLog = OSLog(subsystem: "ObjCRuntimeToolbox", category: "DynamicInvocation")
```

改写示例（`RuntimeInvocation.swift:70`）：

```swift
// 改前
#log(.error, "'\(className, privacy: .public)' does not recognize selector '\(selectorName, privacy: .public)'")

// 改后
os_log(.error, log: dynamicInvocationLog, "'%{public}@' does not recognize selector '%{public}@'", className, selectorName)
```

privacy 约定不变（结构性值 public、payload 默认 private，见 CLAUDE.md
「`os_log` treats string interpolations as private by default」一节）；`os_log` 的
默认 `%@` 即 private，逐处按原 `#log` 的标注映射，不得整体翻转。

`DynamicObject.swift:92-97` 那段「`@Loggable` 与 `@dynamicMemberLookup` 相容」的
doc note 随 `@Loggable` 一起移除——该结论作为宏的一般知识仍记录在 CLAUDE.md，
但本类型不再是它的实例（CLAUDE.md 对应表述同批次改写）。

### 守卫测试

```swift
@Test
func objcRuntimeToolboxTargetStaysMacroOnly() throws {
    // Walk up from #filePath to the directory containing Package.swift,
    // run `swift package dump-package` (with an isolated --scratch-path so
    // it never contends with a concurrent user build), decode the JSON,
    // and assert the "ObjCRuntimeToolbox" target's dependencies name
    // exactly ["ObjCRuntimeToolboxMacros"].
}
```

守的性质是「target 无运行时依赖」这个源头，而不是 `otool -L` 的产物表象——传染是
Xcode 对 `.dynamic` 传递闭包的行为，纯 SwiftPM 构建复现不出来，产物级断言在本仓库
CI 里没有意义；产物级验收由 RuntimeViewer 侧按其标准执行（见「落地步骤」）。

## 替代方案考量

- **方案 B：静态化 + runtime 级去重**（把产品改回 automatic/static，同时让全局状态
  不依赖链接方式保持进程唯一：associated key 改由 `sel_registerName` 派生、
  side table / subclass cache 挂到 ObjC runtime 注册的宿主上先查后建）。
  否决理由：
  1. **跨 image 共享可变状态要求所有共享值改用纯 ObjC 表示**——两个静态拷贝各有一套
     Swift 类型 metadata，拷贝 1 写入的 Swift 值不能被拷贝 2 按自己的类型读取，
     `SideTableEntry` 这类结构必须整体降级为 NSDictionary/NSNumber/Class 的组合；
  2. **schema 要跨版本永久兼容**——app 静态嵌 0.11、插件静态嵌 0.12 时共享同一宿主，
     从此每次改 side table 结构都背上兼容包袱；
  3. **静态双拷贝下 Swift 类重复注册**（`Class _TtC… is implemented in both`）的
     噪音与二义性 B 也解决不了；
  4. **工程面比事故交接消息预估的更大**（`RuntimeMethodHook.sharedInstalledMethods`
     也在清单上），且需要全新的双 dylib fixture 测试基建；
  5. RuntimeViewer 锁在 0.9.0 等发版，B 的周期不匹配。
  若将来注入场景（LookInside、DockIconOverride）真出现跨 image 单份状态的硬需求，
  以本节评估为起点另立提案。
- **保留 `#log`、在 target 内内联私有 logging shim**：自造一层只服务两个文件的抽象，
  且与 target 内其余三个文件的手写 `os_log` 风格不一致。已由用户裁决否决。
- **只把 `OSToolbox` 也声明为 `.dynamic`**：传染面反而更大（等于把中间层全部动态化），
  与验收标准背道而驰。
- **让消费端 daemon 自己加 rpath / 嵌 framework**：把库的拓扑缺陷转嫁给每一个消费者，
  且 workspace 里其他无 rpath 的嵌套可执行会继续逐个踩坑。

## 影响

### 源码兼容性（source compatibility）

**纯新增（无破坏）**。`ObjCRuntimeToolbox` 从未 re-export `OSToolbox`，SwiftPM product
边界下消费者也无法经由它引用 `OSToolbox` 符号，解除依赖不影响任何下游调用点。
两个文件的日志改写是库内部实现；subsystem/category 对保持不变，`log stream` /
Console 谓词行为等价。宏展开层面无变化——本提案不触碰任何宏的实现。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 仓库内：无其他 target 依赖 `ObjCRuntimeToolbox`；`ObjCRuntimeToolboxClient` /
  `ObjCRuntimeToolboxSoleImportClient` / 测试均不受影响（已核实无跨层 import）。
- **RuntimeViewer**：直接受益方。0.11.0 发布后解锁其 0.9.0 exact 锁；其验收标准
  （链接 `FoundationToolbox` / `SwiftStdlibToolbox` 的普通 executable 产物中无任何
  @rpath toolbox framework 依赖，`otool -L` 可验）由其侧执行。
- LookInside、DockIconOverride 等注入场景：拓扑回到 0.9.0 已验证形态，无行为变化。

### 文档与示例

- `CLAUDE.md`：依赖链一句（`ObjCRuntimeToolbox` 不再依赖 `OSToolbox`）、`OSToolbox`
  表格行的表述、「`@Loggable` on a `@dynamicMemberLookup` type」一节的现状陈述、
  「Dynamic invocation」一节中两类型携带 `@Loggable` 的表述。
- `Documentations/README.md`：「OSToolbox 抽取」Spec 条目下追加一行拓扑变更注记
  （沿用 0001 / 0002 的「已变更」注记先例），并登记本提案。
- `Documentations/Evolutions/README.md`：登记本提案。
- `LoggableCategories.md` / `SignpostMacros.md`：核实无涉及（未登记 DynamicInvocation
  的 subsystem/category 对），不改。

## API 演进与废弃策略

- 无 public API 增删，无 deprecation 需求。
- 版本号：**0.11.0**（minor）。链接拓扑变化 + 产品不再携带 `OSToolbox` 模块，按 0.x
  惯例用 minor 表达「有行为变化，请留意」；无 API 破坏，不需要 major。

## 落地步骤

1. `Package.swift`：解除依赖 + 两处注释更新；`swift build` 通过。
2. 两个文件的日志改写（含 doc note 处理）；`swift build` + `swift test` 通过。
3. 守卫测试：先临时加回 `OSToolbox` 依赖看着它红，再恢复绿；随代码同批次提交。
4. 文档同步批次（CLAUDE.md、两份 README、本提案状态推进与编号分配）。
5. 发布 0.11.0，通知 runtimeviewer-c3 解锁升级；RuntimeViewer 侧执行 `otool -L` 产物验收。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 待落地时判断；倾向不需要（决策与契约本提案已完整承载）。
- **有没有引入新术语** —— 待落地时判断；倾向没有。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-01 | Created as Draft | RuntimeViewer daemon 崩溃事故交接（runtimeviewer-c3 会话），用户授权在方案 A / B 中自选，经完整档澄清提问（1 轮 4 题）后选定方案 A |
| 2026-09-01 | 日志替代定为静态 `OSLog` + `os_log` | 用户确认：对齐 target 内既有风格，零新增机器；否决私有 shim 变体 |
| 2026-09-01 | 守卫定为 dump-package 测试 + `Package.swift` 注释 | 用户确认：守「target 无运行时依赖」的源头性质；产物级 `otool` 验收留在 RuntimeViewer 侧 |
| 2026-09-01 | 发版定为 0.11.0 | 用户确认：minor 表达拓扑变化，无 API 破坏不需要 major |
| 2026-09-01 | 方案 B 评估留档于本提案「替代方案考量」段 | 用户确认：遵循「一次改动一份提案」，将来有跨 image 需求再另立提案 |
| 2026-09-01 | Draft → Accepted → In Progress | 用户批准提案并随即开始实施 |
| 2026-09-01 | 实施完成 | Package.swift 解除依赖并更新三处注释；两文件 11 处 `#log` → `os_log`（共享 `dynamicInvocationLog` 常量）；守卫测试先红（`inserted ["OSToolbox"]`，退出码 1）后绿；全量 494 测试通过（原始退出码 0） |
| 2026-09-01 | In Progress → Implemented，编号 0003 | fetch origin 后全局最大编号 0002，+1 落地。收尾判断：**不需要**配套专题文章（调用方契约与维护决策本提案已完整承载，Package.swift 与守卫测试的注释覆盖现场）；**没有**引入新术语 |
