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

## 专题说明

- [`LogCategory` 与 `#log(category:)` 多 Category 支持](LoggableCategories.md) —— `@Loggable` / `#log` 从「一个类型一个 category」扩展为支持多 category 的经过。
- [存储层重构与 `@UserDefault` 宏](StorageLayer.md) —— `@Keychain` 宏发布后，运行时与编码协议都是 Keychain 专用的；这篇记录如何把存储层抽象出来以容纳 `@UserDefault`。

## 设计文档（Specs，归档）

按时间倒序。有配套实现计划的并列给出。

- **`@DyldDynamicInterpose`**（2026-08-06）—— [设计](Specs/2026-08-06-dyld-dynamic-interpose-design.md)
  复活 dyld4 之后已成空函数的 `dyld_dynamic_interpose`：写入私有的 `__DATA,__dyn_interpose` 段，运行时自行读回并改写符号指针槽。可从主执行文件发起、可撤销。
- **Dynamic 移植（DynamicObject）**（2026-08-06）—— [设计](Specs/2026-08-06-dynamic-invocation-design.md)
  基于 `NSInvocation` 的 `@dynamicMemberLookup` + `@dynamicCallable` 调用无头文件的类与方法。**含一条要命的约定**：对象返回值必须写成 `AnyObject?`，写成 `Any?` 能编译但会破坏内存。
- **OSToolbox 抽取**（2026-08-06）—— [设计](Specs/2026-08-06-ostoolbox-extraction-design.md)
  分层与 re-export 链的调整。`@_exported import` 会把宏声明及其插件一并带过传递依赖，这是宏能下沉一层而不破坏调用点的原因。
- **`@RuntimeClassHook` / `@RuntimeClassProxy`**（2026-08-05）—— [设计](Specs/2026-08-05-runtime-class-hook-design.md)
- **`ObjCRuntimeToolbox`**（2026-06-26）—— [设计](Specs/2026-06-26-objc-runtime-toolbox-design.md)
- **`@Keychain` 宏**（2026-06-24）—— [设计](Specs/2026-06-24-keychain-macro-design.md)
- **`#Selector` 字符串字面量宏**（2026-04-15）—— [设计](Specs/2026-04-15-selector-string-literal-macro-design.md) · [计划](Plans/2026-04-15-selector-string-literal-macro.md)
- **Available Storage 宏**（2026-04-14）—— 让「后备存储本身无法被 `@available` 门控」的属性也能对外暴露。
  [设计](Specs/2026-04-14-available-storage-macros-design.md) · [计划](Plans/2026-04-14-available-storage-macros.md)
