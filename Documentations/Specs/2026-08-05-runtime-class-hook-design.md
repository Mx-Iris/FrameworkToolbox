# `@RuntimeClassHook` / `@RuntimeClassProxy` —— Design

Date: 2026-08-05
Target library: `ObjCRuntimeToolbox`（在既有模块内新增，与 `DynamicSubclass` 并列）

## Motivation

`@DynamicSubclassHook`（见 [2026-06-26 设计文档](2026-06-26-objc-runtime-toolbox-design.md)）解决的是"我手里有实例、类在编译期存在"的场景。代码注入类的项目不满足这两条中的任何一条：

- **目标类在编译期不存在。** 注入 Dock、Finder、系统守护进程时，目标类没有头文件，只能靠 `objc_getClass("Tile")` 按名字取。`@DynamicSubclassHook(of: BaseClass.Type)` 的 `BaseClass: NSObject` 约束写不出来。
- **实例不由自己创建，而且要覆盖尚不存在的实例。** Dock 的 tile 由 Dock 自己创建，随用户启动 App 不断新增。per-instance ISA swizzle 要求逐个 `retain()`，接不住未来的实例；要接住就得 hook 创建路径，那本身又是类级 hook。

这类项目现在的写法（以 DockIconOverride 为样本）真正的脆弱点**不是**字符串多，而是**三样东西必须一致，但只有两样被写下来，且互不校验**：

| | 是什么 | 谁写的 | 被校验吗 |
|---|---|---|---|
| ① | 目标方法真实的 ABI | 操作系统 | — |
| ② | `expectedTypeEncoding` 字符串 | 人手写 | 和 ① 比对 ✓ |
| ③ | `@convention(block)` / `@convention(c)` 的 Swift 签名 | 人手写 | **谁都不比** |

②和③相隔几十行、各写各的。把 `Bool` 手滑写成 `Int`，安装校验完整通过，然后宿主进程在调用时按新形状塞寄存器——崩的是别人的进程。**这才是要消灭的 bug 类别。**

所以本次的核心不是"少写字符串"，是**让 ② 从 ③ 编译期推导出来**：手写的东西只剩一样，运行时那次比对才第一次成为真正的断言。

## Goals

- 提供 `@RuntimeClassHook("ClassName")` + `@RuntimeMethodReplacement`：按类名替换方法实现，selector 与 type encoding 全部从 Swift 签名推导，生成 `@convention(block)` trampoline 和类型正确的 `callOriginal(...)`。
- 提供 `@RuntimeClassProxy("ClassName")`：挂在 protocol 上，生成一个签名校验过的类型化调用器，取代手写的 `perform(_:)` / `unsafeBitCast`。
- 提供运行时层 `RuntimeMethodHook`：描述符、签名校验、**全有或全无**的批量安装。
- 编译期 Swift 类型 → ObjC 编码映射器，白名单 + 未知标识符按对象处理（猜错必被运行时校验拦下，代价是 hook 不装，不是宿主崩）。

## Non-Goals

- **不**提供卸载。`method_setImplementation` 是进程级且不可逆的；要可关、可逐实例开关的，用 `DynamicSubclass`。
- **不**取代 `DynamicSubclass`。两者面向不同场景，见下表。
- **不**在编码推导上做"猜不出来就用兜底串"。推不出的类型走显式 `typeEncoding:` 逃生舱，或者装不上并报错——绝不注册一个可能错的编码。

## 与 `DynamicSubclass` 的关系

2026-06-26 那份文档的 Non-Goals 写着「**不**做 method swizzle 的 API……要做的人请直接用 `method_setImplementation`」。本次推翻了这条，理由是：

> 「直接用 `method_setImplementation`」正是产生上面那张三方不一致表的写法。把它挡在库外，并没有让这件事变安全，只是把危险留给了每个调用方各自重写一遍。库能提供的价值恰恰在这里——**编码从签名推导 + 安装前比对 + 批量原子性**，这三件事没有一个是调用方顺手能做对的。

选型：

| | `@DynamicSubclassHook` | `@RuntimeClassHook` |
|---|---|---|
| 目标类 | 编译期存在的 `NSObject` 子类 | 只有名字，`objc_getClass` 解析 |
| 作用域 | 单个实例（ISA swizzle） | 整个类（进程级） |
| 覆盖未来实例 | 否 | 是 |
| 可卸载 | 是（引用计数） | 否 |
| type encoding | 运行时从 reference class 读 | **编译期从 Swift 签名推导，安装前比对** |

最后一行是两者最实质的差别。`DynamicSubclass.resolveTypeEncoding` 读活编码去注册，读到什么用什么——它注册的是**新**编码，而 block 还是**旧**形状，这个组合在 `class_addMethod` 这条路上不会被发现。`RuntimeMethodHook` 反过来：编码来自 block 自己的签名，和活方法比对不上就整批拒装。

## Architecture

### 三层，和既有模块一致

```
Sources/ObjCRuntimeToolboxMacros/     编译期
  ObjCTypeEncoding.swift              Swift 类型文本 → ObjC 编码
  RuntimeClassHookMacro.swift         MemberMacro：descriptors() / install()
  RuntimeMethodReplacementMacro.swift BodyMacro：注入 callOriginal
  RuntimeClassProxyMacro.swift        PeerMacro：生成 <Protocol>Implementation
  MacroStringHelpers.swift            纯 stdlib 字符串工具

Sources/ObjCRuntimeToolbox/           运行时
  RuntimeMethodHook.swift             描述符 + 校验 + 原子安装 + 编码归一化
  RuntimeClassProxySupport.swift      proxy 的校验与 IMP 解析
  RuntimeClassHookMacro.swift         宏声明 + 文档
  RuntimeClassProxyMacro.swift        宏声明 + 文档
```

### 编码推导：只发裸形式

宏产出 `v@:@B`，不产出 `v28@0:8@16B24`。帧偏移是类型的函数，比对时两边都剥数字，所以偏移不携带任何比对用得上的信息。不去算它，就不必重新实现运行时的帧布局规则——那套规则不属于任何稳定契约。

对现有六个签名验算过（见 `RuntimeMethodHookTests.testDerivedEncodingsMatchTheLiveMethods`，直接拿活进程的编码比对）：

| Swift 签名 | 推导 | 运行时实际 | 剥数字后 |
|---|---|---|---|
| `(AnyObject?, Bool) -> Void` | `v@:@B` | `v28@0:8@16B24` | ✓ |
| `(AnyObject?, Int) -> Void` | `v@:@q` | `v32@0:8@16q24` | ✓ |
| `() -> AnyObject?` | `@@:` | `@16@0:8` | ✓ |
| `() -> Void` | `v@:` | `v16@0:8` | ✓ |
| `() -> Int` | `q@:` | `q16@0:8` | ✓ |

### 未知类型按对象处理

映射表覆盖 Void / 对象 / 整数 / 浮点 / 指针 / 常见 CG 结构体。表里没有的**标识符**一律按 `@` 处理。这是安全方向的默认：hook 签名里出现的类型绝大多数是类（`NSView`、`CGImage`、宿主私有类），而猜错必然被拦——结构体编码长成 `{CGRect=…}`，永远不可能等于 `@`，安装前比对直接失败并把两个编码都打进日志。**猜错的代价是 hook 不装，不是宿主进程崩。**

真正推不出来的（表外结构体）走 `@RuntimeMethodReplacement(typeEncoding: "...")` 逃生舱。

### `Bool` 的两种拼法

arm64 上 `BOOL` 是 `bool`（`B`），x86_64 上是 `signed char`（`c`）。Swift `Bool` 在两个架构上都桥接正确，所以归一化时把 `c` 折成 `B`，接受任一都对。副作用是 `Int8` 和 `Bool` 变得不可区分——两者同宽同传参规则，对调用没有歧义。

## 关键设计决定

### 为什么 proxy 挂在 protocol 上

`@attached(body)` 要求声明本身带函数体，于是用户得写一堆占位 `{}` 或 `{ nil }`，既丑又要解释。protocol requirement 天生没有函数体，声明保持纯 Swift，什么都不用桩。生成的 `struct <ProtocolName>Implementation` 反过来 conform 它。

### 为什么 proxy 的返回值一律是 optional

对一个运行时解析出来的类做调用，随时可能失败，而"方法不在"没有诚实的默认值可编。返回 optional 把失败留在调用点可见（想要兜底就写 `?? 0`），而不是藏在一次 trap 或一个凭空捏造的零后面。非 optional 返回类型编译期报错。

### 为什么对象返回值走 `Unmanaged`

`@convention(c) -> AnyObject?` 的所有权语义要靠推断，而 ObjC getter 返回的是 +0 autoreleased。走 `Unmanaged` 再按 ObjC 方法族显式消费——`alloc` / `new` / `copy` / `mutableCopy` 开头的是 +1 用 `takeRetainedValue()`，其余 +0 用 `takeUnretainedValue()`——是手写 proxy 过度释放的经典位置，所以由宏推导而不是留给调用点。族判定要求前缀后的字符不是小写字母，所以 `copyright` 不会被误判成 `copy` 族。

### 为什么 `callOriginal` 直接打 IMP 而不发消息

`method_setImplementation` 之后，类的方法表指向的已经是替换实现。走正常消息派发会调回替换自己，无限递归。`callOriginal` 拿的是安装时保存下来的那个 IMP，绕开方法表。

### 为什么装第二次要报错而不是允许

同一个方法装两次会串成链：第二个的 "original" 是第一个的替换。这几乎从来不是本意，而且一旦发生，排查成本极高（行为正确性依赖安装顺序）。所以 `RuntimeMethodHook` 记录已安装的 (类, selector, 实例/类方法) 三元组，重复安装直接抛 `.alreadyInstalled`。

### 为什么诊断信息要带宏名

`diagnoseUnsupportedFunctionShape` 现在被两族宏共用。加了 `macroName` 参数（默认值保持 `@DynamicSubclassOverride`，既有测试逐字不变），让每族宏在报错时说自己的名字，而不是报一个用户根本没写过的兄弟宏。

## 影响面

- **既有代码零影响。** 新增文件为主；唯一改动的既有文件是 `Diagnostics.swift`（新增带默认值的参数）和 `DynamicSubclassMethodBodyMacro.swift`（`liftImplicitReturn` 从 `private` 放宽到 internal 以便复用）、`MainPlugin.swift`（注册三个新宏）。355 个 swift-testing + 47 个 XCTest 全部通过，包含全部既有 DynamicSubclass 测试。
- **`ObjCRuntimeToolbox` 是 `.dynamic` 产物**，已安装方法的注册表因此在进程内唯一，和 `DynamicSubclass` 的侧表同理。
- 宏插件不进产物二进制，所以引入这套宏**不增加注入 payload 的体积**——这对注入类项目是硬约束。

## Test Coverage

`Tests/ObjCRuntimeToolboxTests/`（XCTest，真实 ObjC 类）：

- 推导编码与活方法逐条比对；编码的精确形状
- 替换生效 + `callOriginal` 抵达宿主；参数往返（对象 / Bool / Int / 多参）
- **签名不匹配整批拒装**：声明 `Bool` 对 `NSInteger` 方法，验证抛 `.typeEncodingMismatch` 且未安装
- **原子性**：一个合法描述符和一个不匹配的同批，验证合法那个也没装上
- 类缺失 / 方法缺失 / 同批重复 / 重复安装
- proxy：支持判定、getter+setter 派生、拒绝不相干实例、void/Int/Bool/对象/多参派发
- **所有权**：1000 次对象返回后实例计数不变，宿主释放后恰好归零

`Tests/ObjCRuntimeToolboxMacroTests/`（MacroTesting 快照）：

- 编码映射器单测：Void/基本类型/对象/运行时引用/optional 各拼法/糖与限定名/结构体/未知标识符
- `@RuntimeClassHook` 诊断：enum 容器、缺类名、非字面量类名、空类名、无标记方法（warning）、throws、async、@MainActor、static、首参带 label、元组参数、重复 selector
- `@RuntimeClassHook` 展开：void 多参、返回值隐式 return 提升、显式 selector、显式 typeEncoding、类方法、未标记方法原样保留
- `@RuntimeClassProxy` 诊断：挂在 struct 上、缺类名、非 optional 返回、非 optional 属性、空 protocol（warning）
- `@RuntimeClassProxy` 展开：方法 + 属性 get/set；`copy`/`new` 族取 retained 而 `copyright` 不取

## Known Limitations / Future Work

- **编码映射表是白名单。** 表外结构体（`NSEdgeInsets`、`CATransform3D` 等）目前落到 `@`，安装时被拦下并报出活编码——可用，但要手动填 `typeEncoding:`。按需扩表即可。
- **没有卸载。** 设计如此，见 Non-Goals。
- **proxy 的签名契约取自声明类，派发走 `object_getClass`。** 子类若改了签名会绕过校验——但那种子类会破坏 ObjC 派发本身，不只是这个 proxy。
- **`isClassMethod: true` 时 `host` 是类对象**，Swift 侧方法仍需声明为实例方法（容器每次调用重建）。已有编译期诊断解释这点。

## Migration / Adoption

新增 API，无迁移负担。手写 `method_setImplementation` + 手填 type encoding 的代码可以逐个 hook 迁移——迁移的收益是把上面那张三方表压成两方，以及拿到批量原子性。

`Sources/ObjCRuntimeToolboxClient/main.swift` 里有可运行的端到端示例。
