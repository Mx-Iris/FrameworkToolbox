# `@DyldDynamicInterpose` —— Design

Date: 2026-08-06
Target library: `SwiftStdlibToolbox`（与既有 `@DyldInterpose` 并列），新增 C target `PointerAuthenticationSupport`

> **归档提示（2026-08-08 补记，正文保持原貌）**
>
> 本文描述的机制全部仍然成立，但**代码位置已变更**：提案
> [`Evolutions/0001-dyld-toolbox-extraction.md`](../Evolutions/0001-dyld-toolbox-extraction.md)
> 已把整套 dyld interposing 从 `SwiftStdlibToolbox` / `SwiftStdlibToolboxMacros`
> 迁到独立的 `DyldToolbox` / `DyldToolboxMacros`，`PointerAuthenticationSupport`
> 也改挂在 `DyldToolbox` 之下。`SwiftStdlibToolbox` re-export `DyldToolbox`，
> 所以下文出现的所有 `import SwiftStdlibToolbox` 用法依然有效。
> 阅读下文时把文件路径里的 `SwiftStdlibToolbox` 换成 `DyldToolbox` 即可。

## Motivation

`@DyldInterpose` 复刻的是 `<mach-o/dyld-interposing.h>` 里的 `DYLD_INTERPOSE` 宏：往 `__DATA,__interpose` 里塞一个 `(replacement, replacee)` 二元组，dyld 在加载期读走并改写所有镜像的导入槽位。它有两条硬约束：

- **只能从 dylib 生效。** dyld 不看主可执行文件的 `__interpose` 段。现有 demo 必须拆成 `DyldInterposeDemoLib` + `DyldInterposeDemoHost` 两个包，就是被这条逼的。
- **生效时机不可选，且不可撤销。** 加载即生效，之后再也拿不回来。

dyld 本来还有第二条路 —— `dyld_dynamic_interpose`，声明在 `<mach-o/dyld_priv.h>`：

```c
struct dyld_interpose_tuple {
    const void* replacement;
    const void* replacee;
};
extern void dyld_dynamic_interpose(const struct mach_header* mh,
                                   const struct dyld_interpose_tuple array[],
                                   size_t count);
```

**这个函数从 dyld4 起就是空实现。** dyld-1378 `libdyld/libdyldGlue.cpp:555`：

```cpp
void dyld_dynamic_interpose(const mach_header* mh, const dyld_interpose_tuple array[], size_t count)
{
    checkTPROState();
    // <rdar://74287303> (Star 21A185 REG: Adobe Photoshop 2021 crash on launch)
    return;
}
```

符号还在导出（`dlsym(RTLD_DEFAULT, "dyld_dynamic_interpose")` 能拿到 `/usr/lib/system/libdyld.dylib` 里的地址），调了不报错，什么也不会发生 —— 这是最坏的一种失败方式。

旧实现在同一份仓库的 git 历史里（dyld-940 之前），做的事情非常朴素，见 `src/ImageLoaderMachOClassic.cpp` 的 `dynamicInterpose`：遍历镜像的每个 `S_NON_LAZY_SYMBOL_POINTERS` / `S_LAZY_SYMBOL_POINTERS` section，逐槽位比对当前值，等于 `replacee` 就写成 `replacement`。dyld2 的 compressed 分支（`ImageLoaderMachOCompressed::dynamicInterposeAt`）走的是绑定操作码，但判定条件完全一样：读槽位当前值，值相等就改写。

**这套逻辑不需要待在 dyld 里，进程内自己就能做完。** 本次就是把它搬进 Swift。

## 现状取证（2026-08-06 于 macOS 26 / Apple Silicon 实测）

设计里的每条取舍都基于下面这四条实测结论，不是推测：

| # | 结论 | 怎么测的 |
|---|---|---|
| 1 | 核心手法有效：改写主程序 `__DATA_CONST,__got` 里的 `puts` 槽位后，调用被成功重定向 | C 原型 |
| 2 | `__DATA_CONST` / `__AUTH_CONST` 都能 `mprotect` 成可写（私有 COW 映射），写完可恢复 | C 原型 |
| 3 | **共享缓存里的系统库基本 hook 不到。** 347 个已加载镜像中只有 3 个槽位引用 `malloc`，且全部在 libsystem_malloc 自身内部 —— 缓存内部的跨 dylib 调用是直接跳转，不走 GOT | 全镜像扫描 |
| 4 | arm64 进程里，共享缓存镜像的 `__auth_got` 槽位存的是**未签名裸指针**；且这些镜像的 section 类型位被缓存构建器改写过（按 `SECTION_TYPE` 匹配不到 `__DATA_CONST,__got`，按名字才能匹配到） | PAC strip 对比扫描 |

结论 3 是本特性最重要的期望管理：**能影响的实际上只有你自己编译出来的镜像。**

## Goals

- 提供 `@DyldDynamicInterpose(target)`：与 `@DyldInterpose` 同形、同校验，但把二元组写进 dyld 不认的私有 section。
- 提供运行时 `DyldDynamicInterpose`：按需触发、可选目标镜像、**可撤销**。
- 生效范围与失败原因全部通过 `DyldDynamicInterposeReport` 如实上报 —— 不静默成功。
- arm64e 的签名槽位在能确证签名 schema 的前提下正确改写，确证不了就跳过并上报。

## Non-Goals

- **不**做 fishhook 式的按符号名重绑定。理由见下。
- **不**尝试重放 chained fixups。理由见下。
- **不**保证能 hook 到系统库内部的调用（结论 3）。
- **不**支持 32 位。整个运行时在 `#if canImport(Darwin) && _pointerBitWidth(_64)` 之内。

## 与 `@DyldInterpose` 的关系

| | `@DyldInterpose` | `@DyldDynamicInterpose` |
|---|---|---|
| section | `__DATA,__interpose`（dyld 消费） | `__DATA,__dyn_interpose`（dyld 忽略） |
| 谁来施加 | dyld，加载期 | 程序自己，任意时刻 |
| 能从主可执行文件生效 | 否 | 是 |
| 可撤销 | 否 | 是 |
| 覆盖后续加载的镜像 | 是 | 否（需再调一次 `applyAll`） |

最后一行是动态版真正的代价：dyld 的静态 interpose 会持续作用于之后加载的镜像，动态版只在调用那一刻扫一遍。

两个宏的展开逻辑完全共用（`SwiftStdlibToolboxMacros/DyldInterposeSupport.swift`），只由 `DyldInterposeExpansionConfiguration` 区分 section 名、常量前缀、诊断里的属性名。

## Architecture

```
@DyldDynamicInterpose(puts)          ← 宏：生成 (replacement, replacee) 常量
        ↓ @section("__DATA,__dyn_interpose") @used
   声明镜像的私有 section
        ↓ getsectiondata(#dsohandle, ...)
DyldDynamicInterposeRegistry          ← 读回二元组
        ↓
DyldDynamicInterpose.applyAll         ← 选目标镜像、改写、记账
        ↓                     ↑
MachOImageScanner            revertAll
（枚举镜像 / 找符号指针 section / 开关页保护）
        ↓
PointerAuthenticationSupport（C）     ← arm64e 的 strip / sign
```

### 公开 API

```swift
DyldDynamicInterpose.registeredTuples(declaredIn: #dsohandle) -> [DyldDynamicInterposeTuple]

DyldDynamicInterpose.applyAll(
    to: DyldDynamicInterposeTargetImages = .allImages,
    excludingDeclaringImage: Bool = true,
    declaredIn: UnsafeRawPointer = #dsohandle
) -> DyldDynamicInterposeReport

DyldDynamicInterpose.apply(_ tuples: [DyldDynamicInterposeTuple], to:excludingImages:) -> Report
DyldDynamicInterpose.revertAll() -> Report
```

目标镜像选择器：`.allImages` / `.mainExecutable` / `.image(machHeader)` / `.imagesWithPath(matching:)`。

## 关键设计与取舍

### 为什么按地址值匹配，而不是按符号名（fishhook 式）

fishhook 走 `LC_DYSYMTAB` 的 indirect symbol table 按名字重绑定。它的**唯一**优势是能覆盖「还没被调用过、槽位里还是 stub binder 地址」的老式 lazy binding 槽位 —— 那种槽位没有真实地址可比。

代价是要解析 symtab/dysymtab/字符串表，多出一大块可出错的边界。而现代 chained fixups 二进制（deployment target ≥ macOS 12 / iOS 15）在加载期就把所有槽位绑定完毕 —— demo 实测里 `__DATA,__la_symbol_ptr` 槽位存的确实是真实 libc 地址而非 stub binder。dyld2 自己的 `dynamicInterposeAt` 也是纯按值判定。

**取舍：跟随 dyld2 的做法，只按地址值匹配。** 代价写进文档：老式 lazy binding 二进制里未解析的槽位抓不到。

### 为什么不重放 chained fixups

`LC_DYLD_CHAINED_FIXUPS` 精确描述了每一个绑定位置，理论上是最全的扫描依据。但 **chained fixups 是就地消耗的**：dyld 沿链走一遍，把每个槽位的「链表 next 偏移」覆盖成最终指针值，链结构在加载完成后就不存在了。`dyld_chained_starts_in_segment.page_start[]` 只保留每页第一个 fixup 的偏移，后续位置依赖已被销毁的链。

**加载后无法重建绑定位置全集**，所以扫描依据只能是 section 类型。这也解释了为什么 dyld 自己把这个 API 废掉而不是修好 —— 它在 dyld4 的世界里失去了原本的信息基础。

### 页保护如何恢复

改写 `__DATA_CONST` 必须先 `mprotect` 开写。恢复时要还原成原本的保护位，而查询「当前实际保护位」需要 `mach_vm_region` —— macOS 之外不可用。

**取舍：不查询，改为复现 dyld 自己的决策。** dyld 把 `__DATA_CONST` / `__AUTH_CONST` 映射为可写、施加 fixups、再改回只读，并用 segment 的 `SG_READ_ONLY` 标志记录这件事。运行时据此推导：带 `SG_READ_ONLY` 的段恢复成 `PROT_READ`，否则恢复成 `initprot` 与 `PROT_READ|PROT_WRITE|PROT_EXEC` 的交集。段是页对齐的，一个页只属于一个段，所以按 section 批量开关页保护不会误伤邻段。

`SG_READ_ONLY`（0x10）在 Swift 里跨 SDK 版本导入不稳定，因此在 `MachOImageScanner` 内显式写出常量并注明出处。

### arm64e 指针签名：先自校验，再改写

`__auth_got` 槽位在真正的 arm64e 进程里存的是签名指针。要改写就必须用同样的 schema 重签替换地址 —— 但加载后 schema（key / discriminator / 是否地址分散）已随 chained fixup 一起消失，只能按约定假设「指令 key IA + 地址分散 + 无额外 discriminator」，这是链接器为函数指针型 auth GOT 条目发射的形式。

**假设猜错的后果是宿主进程在调用点因认证失败而崩溃**，代价太高。因此改写前先做一次自校验：

1. `strip` 槽位当前值得到裸地址；
2. 用假设的 schema 重新签这个裸地址；
3. **签出来的比特必须和槽位原值逐位相等** —— 相等才证明假设成立，才敢用同一 schema 签替换地址；
4. 不相等就跳过该槽位，并以 `.pointerAuthenticationSchemaNotRecognized` 上报。

结论 4 说明常规 arm64 进程里根本走不到签名分支（槽位是裸指针），自校验在那里是零成本的恒等判断。C shim 在非 arm64e 编译下三个函数全部退化为恒等。

### 默认排除声明镜像

`excludingDeclaringImage` 默认 `true`。这样替换实现里直接调用被替换的函数就是**真函数**（走的是自己镜像未被改写的槽位），不会自我递归。静态版没有这个便利 —— 现有 demo 为了绕开 `printf` 的递归，只能改道 `vprintf` + 空 `va_list`。

当声明镜像就是要被 hook 的镜像时（比如从主可执行文件 hook 自己，见 `Examples/DyldDynamicInterposeDemo`），需要显式传 `false`，此时替换实现必须在 apply **之前**把原函数地址捕获到一个全局变量里，通过它调用才不会递归。

### 可撤销：dyld 当年没做的事

每次改写都记账 `(槽位指针, 原值, 写入值, 恢复用的保护位, 镜像/段/section 名)`，`revertAll()` 按后进先出还原。还原前会核对槽位当前值是否仍是我们写进去的值 —— 若已被别人改动则不还原、保留记账、以 `.slotNoLongerHoldsInterposedValue` 上报，避免把第三方的 hook 抹掉。

记账表由进程内 `os_unfair_lock` 保护。`SwiftStdlibToolbox` 是静态库，因此每个内嵌它的镜像各有一份记账表 —— 这与「谁 apply 谁 revert」的语义一致，不是缺陷。

### 并发安全

槽位写入是自然对齐的指针宽度存储，另一线程在改写期间通过该槽位调用，看到的要么是旧函数要么是新函数，不会撕裂。`mprotect` 只改保护位不改内容，不影响并发读者。记账串行化由锁保证。

## 能力边界（必读）

1. **只改间接跳转槽位。** 直接调用、内联调用、以及程序已经拷贝到别处的函数指针一律不受影响 —— dyld 自己的头文件也是这么警告的。
2. **hook 系统库基本只对自己的镜像生效**（结论 3）。
3. **老式 lazy binding 二进制里未解析的槽位抓不到**（见上文取舍）。
4. **不覆盖之后加载的镜像。** 需要再次调用 `applyAll`。
5. **32 位平台不提供该 API。**

## 影响面

- 新增 C target `PointerAuthenticationSupport`，被 `SwiftStdlibToolbox` 依赖。这是本包第一个 C target；它不属于任何 product 的 target 列表，仅随 `SwiftStdlibToolbox` 传递链接。
- `SwiftStdlibToolboxMacros/DyldInterposeMacro.swift` 被重构为薄壳，实现移入 `DyldInterposeSupport.swift`；`DyldInterposeMacroError` 各 case 新增 `attributeName` 关联值。**既有诊断文案逐字不变**，`DyldInterposeMacroTests` 的快照无需改动。
- 无对外行为破坏。

## 测试

- `Tests/SwiftStdlibToolboxMacroTests/DyldDynamicInterposeMacroTests.swift`：10 条，与静态版一一对应的展开快照与诊断。
- `Tests/SwiftStdlibToolboxTests/DyldDynamicInterposeTests.swift`：真实重定向。挑 `getppid` 作目标（进程内没有别的代码调它），只作用于测试镜像自身，串行执行；一条用例内完成「验证排除生效 → apply → 观察到替换值 → revert → 观察到原值 → 再 revert 为空」的完整闭环。
- `Examples/DyldDynamicInterposeDemo`：单可执行文件，实测输出 3 个槽位被改写（`__DATA_CONST,__got` 一个、`__DATA,__la_symbol_ptr` 两个），hook 生效，revert 完整还原。
