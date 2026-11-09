# Draft - 让 ObjCRuntimeToolbox 的多份副本共用一份运行时状态

- **状态**: Accepted
- **创建日期**: 2026-11-09
- **最后更新**: 2026-11-09
- **实现分支 / PR**: `feature/objc-runtime-shared-state-across-copies`

## 摘要

`ObjCRuntimeToolbox-Static` 让必须自包含的二进制不必经 rpath 加载 framework，代价是一条限制：同一个进程里只能有一个二进制嵌入它。原因是 `DynamicSubclass` 与 `RuntimeMethodHook` 的共享状态放在 Swift 全局变量里，每嵌入一次就多一份互不相识的状态。本提案把这些状态挪进 ObjC 运行时——运行时在进程里只有一个，selector 与类按名字全进程唯一——让任意多份副本（静态、动态混用也一样）读写同一份状态，从而去掉这条限制。

## 方案

### 现在有哪些状态

全部在 `Sources/ObjCRuntimeToolbox/` 下，其余文件没有可变的进程级状态。

| 状态 | 位置 | 有两份副本时会怎样 |
|------|------|------|
| `sharedSideTable`：对象 → 原始类、动态子类、引用计数、代号 | `DynamicSubclass` | 副本 B 看不到 A 装过的对象，会把 A 的动态子类当成「原始类」再叠一层；A 装在共享子类上的 `-class` 覆写只查 A 的表 |
| `sharedSubclassCache` | `DynamicSubclass` | 只是 `objc_getClass` 的缓存，本身无害 |
| `sharedInstalledOverrides`：每个（动态子类，hook）只装一次 | `DynamicSubclass` | 各副本各判一次 |
| `nextGeneration`、`DynamicSubclassSentinel`、`sentinelAssociationKey` | `DynamicSubclass` | 哨兵的关联对象 key 是各副本私有变量的地址，两份就是两个 key |
| `sharedInstalledMethods` | `RuntimeMethodHook` | 同一个方法能被两份副本各 hook 一次，`alreadyInstalled` 失效 |
| 两把 `os_unfair_lock` | 上述两处 | 不同副本之间互不排斥 |

### 怎么改

1. **先造复现环境，看它变红。** 仿照 `Examples/DyldInterposeDemoLib` + `DyldInterposeDemoHost` 建两个包：一个出 `.dynamic` 库，库里静态嵌入 `ObjCRuntimeToolbox-Static`；另一个包的可执行文件同样静态嵌入它，并链接那个库。宿主对上表每一行做检查，任一失败就以非零退出码结束。在现有代码上确认它失败之后再改。预计放不进 `swift test`（同一个包里 SwiftPM 不会把 product 链成独立的 dylib），这一点在本步实测确认。
2. **单个对象的状态挂到对象自己身上。** 原始类、动态子类、引用计数改用关联对象存，key 是按固定名字注册的 selector（`sel_registerName`，名字里带格式版本，如 `_ObjCRuntimeToolbox_v1_…`）。selector 按名字全进程唯一，每份副本拿到的是同一个 key。
   - 值只用运行时与 Foundation 自带的类型（类对象、`NSNumber`、`NSMutableSet`），**不用本库定义的任何类型**：副本 A 的 Swift 类型在副本 B 看来是另一个类型，转换必然失败。
   - 对象释放时关联对象随之释放，所以外部表、`DynamicSubclassSentinel` 与代号计数器整个删掉。它们存在只是因为状态放在对象之外，得处理对象死后的清理和地址被复用（ABA）的问题。
   - 原始类单独占一个 key。类对象不会被释放，`-class` 覆写读它不必加锁。
3. **动态子类缓存改为直接查 `objc_getClass`**，查找与创建在全进程锁内一次完成。
4. **两种「只装一次」的记录挂到类对象上。** `claimOverrideInstallation` 记在动态子类上，`RuntimeMethodHook` 记在被 hook 的类上，值是 `NSMutableSet<NSString>`。
5. **一把全进程锁。** 第一次使用时，在 `objc_sync_enter(NSObject.self)` 保护下查 `NSObject` 类对象上固定 key 的关联对象，没有就放一个 `NSLock` 上去；之后各副本缓存这个引用，`@synchronized` 只在初始化那一次碰。顺带让 `RuntimeMethodHook.installAtomically` 的检查与替换在同一次持锁内完成——现在两步之间没有锁，单副本下并发安装同一个方法也会漏判。
6. **格式不同的副本主动报错，而不是静默各管各的。** 对象当前类名以 `_ObjCRuntimeToolbox_` 开头、却找不到本格式的状态，说明是另一种格式的副本装的；`retain` 拒绝叠加，处理方式与现在叠两个不同 hook 时的 `precondition` 一致。
7. **`@DynamicSubclassHook` 的 hook 标识改为带模块名**（`String(reflecting:)` 一类）。现在只用 hook 类型的源码名；状态共享之后，两个模块里同名的 hook 会撞上，后装的被静默跳过。这会改变宏展开结果，`DynamicSubclassMacroTests` 的快照随之更新；手写调用 `claimOverrideInstallation` 的代码，标识要求从「模块内唯一」变为「进程内唯一」，写进该方法的文档。
8. **基准。** `-class` 覆写在热路径上（KVO 与大量框架代码都会调），对比改前改后 `originalClass(of:)` 的耗时，数字写回本提案。明显变慢就先回到提案讨论，不硬推。
9. **文档。** 删掉 `Package.swift` 注释与项目 `CLAUDE.md` 产品表里「同一进程只能有一份」的限制，改写为新机制的说明；`DynamicSubclass.swift` 头部关于共享状态的说明同步更新。

### 没有询问就采用的假设

- 两个 product 都保留，`.dynamic` 不动——已有使用方依赖它。
- 公开 API 不变（`retain`、`release`、`isInstalled(on:)`、`originalClass(of:)`、`claimOverrideInstallation`、`RuntimeMethodHook.isInstalled`），只有一份副本时行为与现在一致。
- 多份副本里的 Swift 类（`DynamicObject`、`RuntimeInvocation`）启动时预计仍会打印 "Class … is implemented in both"。各副本直接使用自己的类型元数据，不影响行为，本提案不处理；跨副本传递本库的 Swift 类型实例也不在范围内。第 1 步实测确认警告是否出现。
- 嵌有副本的二进制不会被真正卸载（含 ObjC 元数据的镜像 `dlclose` 后仍常驻），所以一份副本装到共享类上的 IMP 不会悬空。实现时到 `/Volumes/AppleOSS` 的 dyld 源码核对。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-09 | Created as Draft | 新增的 `ObjCRuntimeToolbox-Static` 带着「同一进程只能有一份」的限制，用户需要自包含的静态链接，希望去掉这条限制 |
| 2026-11-09 | 共享状态放进 ObjC 运行时，不采用「第一个加载的副本当主、其余副本转发给它」 | 转发要把整套 API（含 Swift 闭包与泛型）变成跨副本的约定；放进运行时只需约定几个 key 的名字与值的形状 |
| 2026-11-09 | 走轻量档 | 不改公开 API，只改内部存储方式与一处宏展开 |
| 2026-11-09 | 用户批准，开始实现 | — |
