# FrameworkToolbox 文档索引

一组分层的 Swift 工具库与宏。**新增或重命名任何文档都必须同步更新这份索引。**

> **项目类型：库（源码分发）**。SPM library product，使用方每次重新编译，
> 无 ABI 约束，但**源码兼容性必须评估** —— 本库被多个项目依赖，且大量能力以宏的形式暴露，
> 宏展开结果的变化同样是源码层面的破坏。提案见 [`Evolutions/README.md`](Evolutions/README.md)。

| 目录 | 用途 |
|------|------|
| [`Evolutions/`](Evolutions/) | **提案** —— 今后所有新功能与架构改动的唯一入口 |
| [`Specs/`](Specs/) | 提案制确立前的设计文档。保留归档，不再新增 |
| [`Plans/`](Plans/) | 与 `Specs/` 配对的实现计划。保留归档，不再新增 |

## 提案（Evolutions）

- [0001 —— 把 dyld interposing 抽成独立的 DyldToolbox](Evolutions/0001-dyld-toolbox-extraction.md)（Implemented）
- [0002 —— 仿 `@Loggable` / `#log` 实现 os_signpost](Evolutions/0002-signpost-macros.md)（Implemented）
  新增 `@Signpostable` 与 `#signpost`，三种调用形态；顺带修 `#log` 带插值时依赖调用方 `import Foundation` 的缺陷。
- [0003 —— 把 `ObjCRuntimeToolbox` 恢复为自包含的 `.dynamic` 叶子](Evolutions/0003-objc-runtime-toolbox-self-contained-leaf.md)（Implemented）
  0.10.0 给它加的 `OSToolbox` 运行时依赖让 Xcode 把传递闭包整体建成共享动态 framework，压垮了 RuntimeViewer 无 rpath 的嵌套 daemon；解除依赖并加 dump-package 守卫测试。
- [0004 —— 给 `@Loggable` / `@Signpostable` 加启用开关，并解除泛型类型的限制](Evolutions/0004-logging-enable-switch.md)（Implemented）
  新增 `isEnabled:` 宏参数与 `LoggingControl` / `SignpostingControl` 运行时入口，关闭状态用 `OSLog.disabled` 一族的空句柄表达；
  同批次去掉泛型支的 static 存储属性，泛型类型不必再绕协议。

## 专题说明

- [`LogCategory` 与 `#log(category:)` 多 Category 支持](LoggableCategories.md) —— `@Loggable` / `#log` 从「一个类型一个 category」扩展为支持多 category 的经过。
- [`@Signpostable` 与 `#signpost` 用法契约与实现决策](SignpostMacros.md) —— 三种调用形态怎么选、区间凭据为什么要自带 log handle、为什么防 Foundation 依赖的守卫必须独占一个 target。
- [关掉日志与埋点 —— `isEnabled:` 与运行时开关](LoggingSwitches.md) —— 三层开关怎么用、关掉之后为什么连插值都不求值、泛型限制怎么顺带解除的。
- [存储层重构与 `@UserDefault` 宏](StorageLayer.md) —— `@Keychain` 宏发布后，运行时与编码协议都是 Keychain 专用的；这篇记录如何把存储层抽象出来以容纳 `@UserDefault`。

## 设计文档（Specs，归档）

按时间倒序。有配套实现计划的并列给出。

- **`@DyldDynamicInterpose`**（2026-08-06）—— [设计](Specs/2026-08-06-dyld-dynamic-interpose-design.md)
  复活 dyld4 之后已成空函数的 `dyld_dynamic_interpose`：写入私有的 `__DATA,__dyn_interpose` 段，运行时自行读回并改写符号指针槽。可从主执行文件发起、可撤销。
  **代码位置已变更**：这套东西已由提案 [0001](Evolutions/0001-dyld-toolbox-extraction.md) 从 `SwiftStdlibToolbox` 迁至独立的 `DyldToolbox`；这篇设计文档描述的机制不变，但里面写的文件路径是旧的。
- **Dynamic 移植（DynamicObject）**（2026-08-06）—— [设计](Specs/2026-08-06-dynamic-invocation-design.md)
  基于 `NSInvocation` 的 `@dynamicMemberLookup` + `@dynamicCallable` 调用无头文件的类与方法。**含一条要命的约定**：对象返回值必须写成 `AnyObject?`，写成 `Any?` 能编译但会破坏内存。
  **日志实现已变更**：文中的 `@Loggable` / `#log` 方案（含「`#log` 要写显式 `self.`」一节）已由提案
  [0003](Evolutions/0003-objc-runtime-toolbox-self-contained-leaf.md) 改为共享的手写 `dynamicInvocationLog` 常量 + `os_log` ——
  `ObjCRuntimeToolbox` 不得在运行时依赖 `OSToolbox`。`@Loggable` 与 `@dynamicMemberLookup` 相容性的实测结论仍然成立，只是本模块不再是它的用例。
- **OSToolbox 抽取**（2026-08-06）—— [设计](Specs/2026-08-06-ostoolbox-extraction-design.md)
  分层与 re-export 链的调整。`@_exported import` 会把宏声明及其插件一并带过传递依赖，这是宏能下沉一层而不破坏调用点的原因。
  **守卫位置已变更**：文中的 `Sources/OSToolboxClient/LoggableWithoutFoundation.swift` 已由提案 [0002](Evolutions/0002-signpost-macros.md)
  移入独占的 `OSToolboxNoFoundationClient` target —— 它原先与一个 `import Foundation` 的 `main.swift` 同 target，
  而 Swift 的 conformance 查找是模块级的，那个守卫因此并不成立。
  **拓扑已再次变更**：文中「让 `ObjCRuntimeToolbox` 用上 OSToolbox」的一步已由提案
  [0003](Evolutions/0003-objc-runtime-toolbox-self-contained-leaf.md) 撤销 ——
  `.dynamic` 产品的运行时 target 依赖会被 Xcode 连同传递闭包一起建成共享动态 framework。
- **`@RuntimeClassHook` / `@RuntimeClassProxy`**（2026-08-05）—— [设计](Specs/2026-08-05-runtime-class-hook-design.md)
- **`ObjCRuntimeToolbox`**（2026-06-26）—— [设计](Specs/2026-06-26-objc-runtime-toolbox-design.md)
- **`@Keychain` 宏**（2026-06-24）—— [设计](Specs/2026-06-24-keychain-macro-design.md)
- **`#Selector` 字符串字面量宏**（2026-04-15）—— [设计](Specs/2026-04-15-selector-string-literal-macro-design.md) · [计划](Plans/2026-04-15-selector-string-literal-macro.md)
- **Available Storage 宏**（2026-04-14）—— 让「后备存储本身无法被 `@available` 门控」的属性也能对外暴露。
  [设计](Specs/2026-04-14-available-storage-macros-design.md) · [计划](Plans/2026-04-14-available-storage-macros.md)
