# 0004 - 给 @Loggable / @Signpostable 加启用开关，并解除泛型类型的限制

- **状态**: Implemented
- **创建日期**: 2026-09-04
- **最后更新**: 2026-09-04
- **所属愿景**: 无
- **配套文档**: [关掉日志与埋点 —— `isEnabled:` 与运行时开关](../LoggingSwitches.md)

## 摘要

`@Loggable` 和 `@Signpostable` 目前没有关闭手段：贴上宏、写下 `#log` / `#signpost`，
这条日志就永远会发出。实际使用中有一大批调试日志和性能监控埋点，输出量很大，平时是纯噪音，
只有在专门测试对应功能时才想看到它们。现在只能靠注释掉调用点或者事后用 `log stream` 的
谓词过滤，两种都不好使。

本提案给两个宏各加一个 `isEnabled:` 参数（默认 `true`），并配上一个运行时控制入口，
让「关掉哪些日志」既能写死在注解上，也能在运行时按类型、按 category 或者一把总闸切换。

**顺带解除一条长期限制。** 实现开关必须重塑生成的句柄成员，而两个宏至今贴不到泛型类型上，
正是因为它们生成 `static let`——Swift 不允许泛型类型有 static 存储属性。同一批改动一并处理，
泛型类型今后可以直接贴，不必再声明一个协议、把宏贴在协议上再让它遵循。这两件事改的是同一段
生成代码，拆成两份提案会让两份都不权威，因此合并为一次改动。

## 方案

### 开关做在日志句柄上，不做在调用点上

`#log` / `#signpost` 是 freestanding 宏，展开时看不到类型上 `@Loggable(...)` 写了什么参数
—— 宏之间没有通信渠道。它们唯一能引用的就是 `Self.logger` / `Self._signpostLog` 这些由
member macro 生成的成员。所以开关只作用在**这些成员返回什么句柄**上，所有调用点自动生效，
`LogMacro.swift` 和 `SignpostMacro.swift` 一行都不用改，连使用方手写的
`Self.logger.debug(…)` 也一并静音。

关闭状态用系统自带的空句柄表达：`OSLog.disabled`、`Logger.disabled`（macOS 11+）、
`OSSignposter.disabled`（macOS 12+）。

**这不是「照常干活只是不落盘」**，插值参数一次都不会求值。在 macOS 26 SDK 的
`os.swiftinterface` 里核对过两条内部实现：

- `osLogInternal` 的 `guard logObject.isEnabled(type:) else { return }` 排在
  `argumentClosures.forEach { … }` 之前；
- `osSignpost` 的 `guard log.signpostsEnabled else { return }` 同样排在参数闭包求值之前。

而 `OSLogInterpolation.appendInterpolation` 的参数是 `@autoclosure`，所以
`#log(.debug, "\(self.expensiveDescription)")` 在句柄禁用后，`expensiveDescription`
根本不会被调用。这是选「句柄禁用」而不是「在调用点包一层 `if`」的主要依据 —— 后者要给
`#log` 加展开逻辑、给协议加新 requirement，换来的只是省掉一次函数调用。

`OSSignposter` 的行为完全由它的 `logHandle` 决定（`emitEvent` / `beginInterval` /
`endInterval` 都是直接 `osSignpost(log: logHandle, …)`），所以
`OSSignposter(logHandle: .disabled)` 与 `OSSignposter.disabled` 等价，`#signpost` 现有的
`os.OSSignposter(logHandle: signpostLog)` 写法不用动。

### 三层开关，与运算

最终是否输出 = **类型级** && **全局** && **category 级**。

**第一层，类型级（宏参数）**

```swift
@Loggable(isEnabled: false)                   // 编译期关死
@Loggable(isEnabled: DebugFlags.syncLogging)  // 交给自己的一个标志
@Signpostable(isEnabled: false)               // 同形
```

宏看语法树分两种情况生成，使用方不需要学两套语法：

- **写字面量 `false`** —— 生成 `static var logger: os.Logger { .disabled }`，是编译期常量，
  优化器能把整条日志路径连同字符串一起消掉。全局开关也打不开它，这是「关死」。
- **写字面量 `true` 或不写** —— 走运行时查询路径（见下）。
- **写任意表达式** —— 表达式与运行时查询做与运算，转写进生成代码。表达式落在使用方自己的
  文件里，遵守「宏展开不得命名调用者未 import 的模块」那条规则：宏本身不引入任何新模块。

**第二层，全局总开关**

```swift
LoggingControl.isEnabled = false      // 一行关掉整个进程的 @Loggable 输出
SignpostingControl.isEnabled = false  // 埋点独立一个闸，可以只留日志不留埋点
```

日志和埋点分成两个开关，因为「想看日志但不想要 Instruments 埋点」和反过来都是真实需求。

**第三层，按 category**

```swift
LoggingControl.setEnabled(false, for: .network)
SignpostingControl.setEnabled(false, for: .pointsOfInterest)
```

`@Loggable` 不带 `category:` 时默认 category 就是类型名，所以按 category 关同时也就是
按类型关的运行时版本 —— `LoggingControl.setEnabled(false, for: LogCategory("SyncService"))`
能关掉 `SyncService` 的默认句柄，不必去改注解重新编译。这正是「平时关掉，测这个功能时打开」
最省事的用法。

### 快速路径：默认情况下是两次 Bool 读

生成代码调用的统一入口：

```swift
LoggableMacro._isLoggingEnabled(category: <category 表达式>)   // @autoclosure
```

内部结构：

```swift
public enum LoggingControl {
    nonisolated(unsafe) private static var _isEnabled = true
    nonisolated(unsafe) private static var _hasDisabledCategories = false
    private static let disabledCategoryNames = Mutex<Set<String>>([])
}
```

判定顺序是：总开关关了直接 `false`；没有任何被禁用的 category 直接 `true`。**只有真的用了
按 category 禁用，才会付加锁查表的钱**。`category` 参数必须是 `@autoclosure` —— 协议那一支
的 `category` 是 `String(describing: self)`，构造字符串不便宜，快速路径不能碰它。

两个 `Bool` 用 `nonisolated(unsafe)` 而不是 `Mutex`：单字节读写在所有 Apple 平台上不会撕裂，
而每条日志加一次 `os_unfair_lock` 在热路径上不合算。代价是开关的写入与并发日志调用之间没有
顺序保证——设置意在启动早期或调试时进行，这个语义要写进文档。

### 生成代码的形状变化

以贴在具体类型上、不带 `isEnabled:` 为例，`static let logger` 变成 `static var logger`，
真句柄挪到一个新的私有存储属性里缓存：

```swift
// 现在
private nonisolated static let _osLog = os.OSLog(subsystem: subsystem, category: category)
@available(…) private nonisolated static let logger = os.Logger(subsystem: subsystem, category: category)

// 改后
private nonisolated static let _enabledOSLog = os.OSLog(subsystem: subsystem, category: category)
private nonisolated static var _osLog: os.OSLog {
    LoggableMacro._isLoggingEnabled(category: category) ? _enabledOSLog : .disabled
}
@available(…) private nonisolated static let _enabledLogger = os.Logger(_enabledOSLog)
@available(…) private nonisolated static var logger: os.Logger {
    LoggableMacro._isLoggingEnabled(category: category) ? _enabledLogger : .disabled
}
```

顺带修掉一处既有的小问题：`_enabledLogger` 改由 `os.Logger(_enabledOSLog)` 构造，让
`logger` 和 `_osLog` 落在同一个底层句柄上。现在这两者是各自 `init(subsystem:category:)`
出来的两个独立句柄——对日志无影响，但和 `@Signpostable` 那边「一个 subsystem/category 对只
应有一个句柄」的既有原则不一致（那条原则写在 `SignpostableMacroSupport.swift` 的注释里，
是为了让 begin 和 end 配得上）。

新增的成员名（`_enabledOSLog` / `_enabledLogger` 与 `_enabledSignpostLog` /
`_enabledSignposter`）要加进两个宏的 `@attached(member, names:)` 列表，且照例两个宏之间一个
都不许撞名——撞了就是 `invalid redeclaration`。

协议那一支不需要新增 requirement：它的 `logger` / `_osLog` 本来就是走
`_sharedLogger(for:)` 缓存的 computed 属性，加一层判断即可。

### 顺带解除泛型类型的限制

上面那个 `_enabledOSLog` 私有缓存仍然是 static 存储属性，所以**只把 `logger` 换成
`static var` 并不足以让泛型类型能用**。要拿到这个收益，泛型那一支必须整支不含 static 存储。

实测确认了限制的边界（`swiftc -typecheck`）：

```swift
struct Box<Element> {
    static let storedInGeneric = 1          // error: static stored properties not supported in generic types
    static var computedInGeneric: Int { 1 } // OK
    struct NestedInsideGeneric {            // 嵌套在泛型里的非泛型类型
        static let storedInNested = 2       // 同样报错
    }
}
```

好消息是「不含 static 存储」的那条路已经写好了——协议默认实现走的
`LoggableMacro._sharedLogger(for: self, subsystem:category:)`，按 metatype 的
`ObjectIdentifier` 缓存。泛型支直接复用，**一行新的 runtime 代码都不用加**。按 metatype 缓存
也比按 subsystem/category 字符串缓存快，key 是个指针，不必算 String 的 hash。

于是具体类型这一支按是否处在泛型上下文里分成两种生成结果：

| 情形 | 真句柄从哪来 |
|------|------------|
| 非泛型，且不嵌套在泛型内 | `private static let _enabledOSLog = …`，与现在一致，零额外成本 |
| 自身是泛型，或嵌套在泛型内 | `LoggableMacro._sharedLogger(for: self, …)`，与协议支同一条路 |

开关判断两支相同，所以 `#log` / `#signpost` 的调用点写法完全不变。

**检测方式。** 声明自身是否泛型，看语法树上的 `genericParameterClause` 即可；嵌套的情况宏从
`declaration` 上看不出来——它拿到的只是内层类型自己的语法树——要靠
`context.lexicalContext` 往上遍历外层声明，只要任何一层带泛型参数就走运行时缓存那一支。

**category 的取值不变。** `staticTypeName(from:)` 取的是语法树上的名字，所以
`Box<Element>` 的 category 是 `"Box"`，`Box<Int>` 与 `Box<String>` 共享同一个 category。
这是有意的：日志的 category 是给人写 `log stream` 谓词用的，按特化参数拆开只会让谓词难写。
需要区分就显式传 `category:`。这也保持了「贴在类型上取语法名、贴在协议上取运行时名
（`String(describing: self)`）」的既有分工——协议不可能知道 conformer 是谁。

**依赖变更。** `context.lexicalContext` 是 swift-syntax **600.0.0** 引入的（509.1.0 与
510.0.3 的 `MacroExpansionContext.swift` 里都没有，逐 tag 核对过），所以 `Package.swift` 里
swift-syntax 的区间要从 `509.1.0..<604.0.0` 收窄为 `600.0.0..<604.0.0`。实际影响很小：本包的
`swift-tools-version` 是 6.2，使用方本来就得在对应的工具链上编译，`509.1.0` 这个下限早已只是
名义上的兼容；解析到的版本仍是现在的 603.0.2。

**落地后要更新全局 agent 指令。** 全局 `CLAUDE.md` 现在写着「泛型类型上贴不了这两个宏……做法
是给该泛型类型声明一个协议、把宏贴在协议上再让它遵循」。这条规则在本提案落地后失效，需要按
`maintain-agent-config` 的流程改 `AgentInstructions/Global/Shared.md` 再渲染，并注明从哪个版本
起适用——其它项目可能仍依赖旧版本。

### 区间的完整性

`#signpost(.begin)` 把它发出时用的那个 log handle 存进 `SignpostInterval`，`.end` 用的是
存下来的那个，不重新解析。所以一个区间的开关状态在 begin 时就定死了：begin 时开关是开的，
中途关掉，end 照样发出，区间完整闭合；begin 时是关的，end 也是 no-op。两个方向都不会留下
悬空的 begin。这是既有设计白捡的性质，不需要额外处理。

### 源码兼容性

- 新增参数带默认值，调用点不改照常编译。
- `logger` / `_osLog` / `signposter` / `_signpostLog` 从 `static let` 变成
  `static var { get }`：读取语法不变，`@Loggable(.public)` 暴露出去的也仍是可读属性。
  行为差别是每次访问多两次 `Bool` 读。
- 宏展开结果变了，按索引 README 的规定这算源码破坏面：所有 `assertMacro` 快照要更新。
- ABI 兼容性不适用——本库以 SPM 源码分发，使用方每次重新编译。
- swift-syntax 依赖下限从 `509.1.0` 抬到 `600.0.0`（理由见上一节）。

### 验证

1. `LoggingControl` / `SignpostingControl` 三层与运算的单元测试。
2. **关掉后插值不求值**的测试：`#log(.debug, "\(self.sideEffectCounter)")`，断言计数没动。
   这条 pin 的是上面从 SDK 里核对出来的 guard 顺序，将来 SDK 改了会变红。
3. 更新 `assertMacro` 快照。
4. `OSToolboxNoFoundationClient` 补 `isEnabled: false` 与 `isEnabled: <表达式>` 两种用例,
   守住展开不碰 Foundation。
5. `@Loggable` + `@Signpostable` 同贴一个类型的用例（`DualAnnotatedService`）要覆盖到新成员，
   守住不撞名。
6. 泛型三种形态各一个编译期用例：泛型类型直接贴、嵌套在泛型内部的类型贴、非泛型照旧。
   这类回归只有编译能抓到，写进 client target 而不是单元测试。
7. 落地时同批次更新根目录 `CLAUDE.md` 的 **Logging** 与 **Signposting** 两段——两段现在都没有
   任何关于开关的描述，读到那里的人会以为日志无法关闭；泛型可用一事也要写进去。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-04 | Created as Draft | 用户提出「LoggableMacro 和 SignpostableMacro 要加一个开关，默认开启，但是可以指定关闭」 |
| 2026-09-04 | 开关做在句柄上，不在调用点包 `if` | `#log` / `#signpost` 看不见类型上的宏参数；且句柄禁用已经能保证插值参数不求值（SDK 里 guard 排在参数闭包求值之前），包 `if` 只多省一次函数调用，却要改两个 freestanding 宏并给协议加 requirement |
| 2026-09-04 | 三层粒度全做：类型级 + 全局 + category 级 | 用户明确三个都要。默认 category 即类型名，所以 category 级顺带就是「不重新编译也能开关某个类型」 |
| 2026-09-04 | 关闭只做到「句柄禁用」，不追求字符串不进二进制 | 用户选定。要做到字符串也不进二进制只有 `#if` 编译条件一条路，得引入另一套机制 |
| 2026-09-04 | 字面量走编译期常量，表达式走运行时查询 | 用户的首要场景是「Release 剥掉」，需要编译期定死的零开销路径；但「测这个功能时才打开」又需要不改注解就能切换，两条路各自成立，靠语法树分型，使用方只学一种写法 |
| 2026-09-04 | 全局开关用 `nonisolated(unsafe) var Bool` 而非 `Mutex` | 每条日志加一次 `os_unfair_lock` 在热路径上不合算；单字节读写不会撕裂，开关本就意在启动早期或调试时设置 |
| 2026-09-04 | 日志与埋点各自独立的全局开关 | 「只留日志不留埋点」与反过来都是真实需求，合成一个闸会逼人二选一 |
| 2026-09-04 | 合并解除泛型限制，不另开提案 | 用户指出 `static let` → `static var` 顺带能让泛型类型直接用宏。两件事改的是同一段生成代码，拆开会让两份提案都不权威 |
| 2026-09-04 | 泛型支复用协议支的 metatype 运行时缓存，非泛型支保持 `static let` | 不让现有使用方为一个新能力付性能税；复用已有 runtime helper，不新增代码 |
| 2026-09-04 | 用 `context.lexicalContext` 覆盖「嵌套在泛型内部」的情况 | 用户在知悉代价后选定。备选是全部走运行时缓存（一支到底但所有人变慢）或不处理嵌套（留一个说不清的坑） |
| 2026-09-04 | 接受 swift-syntax 下限抬到 600.0.0 | 原以为是 510，逐 tag 核对后是 600.0.0。本包 `swift-tools-version` 已是 6.2，旧下限本就只是名义兼容 |
| 2026-09-04 | Accepted，开始实现 | 用户批准；并确认不必再兼容 swift-syntax 509 / 510，其宏项目已全部升级 |
| 2026-09-04 | 实现完成，状态置为 Implemented | 478 个测试通过；六个声明平台各构建一次通过；开关的运行时测试做过变异验证——把 `_isEnabled` 短接成恒 `true` 后 12 个断言变红，且存活的四个恰好是不该受影响的（默认值、`enableAllCategories` 自身、编译期常量那条路） |
| 2026-09-04 | 配套写一份专题说明而非只留 CLAUDE.md | CLAUDE.md 面向维护者、提案面向决策，都不回答使用方的「我平时想关掉、调试时想打开该怎么写」。登记为 `Documentations/LoggingSwitches.md` |
| 2026-09-04 | 未新增术语，不动术语表 | `LoggingControl` / `SignpostingControl` 是类型名不是术语；「运行时缓存分支」只在本仓库的实现说明里出现，且项目目前没有术语表 |
