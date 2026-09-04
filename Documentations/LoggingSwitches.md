# 关掉日志与埋点 —— `isEnabled:` 与运行时开关

配套提案：[0004 —— 给 `@Loggable` / `@Signpostable` 加启用开关，并解除泛型类型的限制](Evolutions/0004-logging-enable-switch.md)。

## 要解决的问题

调试日志和性能埋点写得越全，平时越吵。以前没有关掉的手段，只能注释掉调用点，
或者事后用 `log stream` 的谓词过滤——前者要改代码，后者管不到已经发生的开销。

现在有三层开关，**三层都开着才会输出**：

| 层 | 怎么写 | 什么时候决定 |
|---|---|---|
| 类型级 | `@Loggable(isEnabled: …)` | 传字面量是编译期，传表达式是每次调用 |
| 全局 | `LoggingControl.isEnabled` | 运行时 |
| category 级 | `LoggingControl.setEnabled(_:for:)` | 运行时 |

埋点侧完全对称，把 `LoggingControl` 换成 `SignpostingControl` 即可。两者是**独立**的开关，
因为「要日志不要埋点」和反过来都是常见需求。

## 四种典型用法

```swift
// ① 彻底关死。生成的是常量空句柄，优化器能把整条日志路径消掉，
//    运行时开关也打不开它。
@Loggable(isEnabled: false)
struct NoisyService { … }

// ② 交给自己的标志。平时是 false，要看的时候改一行重新编译——
//    或者把标志本身做成可变的，连编译都不用。
enum DiagnosticFlags {
    static let verboseLogging = false
    nonisolated(unsafe) static var performanceTracing = false
}

@Loggable(isEnabled: DiagnosticFlags.verboseLogging)
struct SyncService { … }

@Signpostable(isEnabled: DiagnosticFlags.performanceTracing)
struct RenderPipeline { … }

// ③ 一把总闸。适合在启动早期按环境决定。
LoggingControl.isEnabled = false

// ④ 只关某一类。`@Loggable` 不写 `category:` 时默认 category 就是类型名，
//    所以这一条也能当「按类型关」用，且不必重新编译。
LoggingControl.setEnabled(false, for: .network)
LoggingControl.setEnabled(false, for: LogCategory("SyncService"))
LoggingControl.enableAllCategories()   // 撤销全部 category 级禁用，不影响总闸
```

## 关掉之后，代价有多低

**插值参数一次都不会求值。** 这不是「照常算好再丢掉」：

```swift
#log(.debug, "state=\(self.expensiveDescription)")
```

关掉之后 `expensiveDescription` 根本不会被调用。原因在 `os` 模块内部——
`osLogInternal` 的 `guard logObject.isEnabled(type:)` 排在 `argumentClosures.forEach` **之前**，
而 `OSLogInterpolation.appendInterpolation` 的参数是 `@autoclosure`。
`os_signpost` 那边的 `guard log.signpostsEnabled` 位置相同。

这条顺序是整个设计的地基，所以 `DisabledLoggingSkipsInterpolationTests` 用一个求值计数器把它钉住了：
将来某个 SDK 版本挪了那个 `guard`，测试会红。

开着的时候，代价是两次 `Bool` 读加一个分支。只有真的用了 category 级禁用，才会付一次加锁查表的钱。

## 三件容易踩的事

**1. `isEnabled: false` 是编译期的，运行时打不开。**
这是有意的——它的用途就是「这批日志不该出现在这个构建里」。想要能开关的，传表达式而不是字面量。

**2. 开关作用在句柄上，不在调用点上。**
所以它同时管住 `#log`、`#signpost`，以及你手写的 `Self.logger.debug(…)`。
反过来说，如果你把 `Self.logger` 存进了一个属性，那份拷贝不会随开关变化——每次现取即可。

**3. 全局开关没有内存序保证。**
两个 `Bool` 是 `nonisolated(unsafe)` 的裸变量，不是加锁状态：每条日志都要读它们，
为此上一把 `os_unfair_lock` 不划算。代价是切换开关与并发日志之间没有顺序保证，
一条已经在途的日志仍可能发出。开关的定位是启动早期、调试菜单或调试器里设置，这个区别观察不到。

## 顺带解除的泛型限制

同一批改动去掉了具体类型分支里的 `static let`，于是**泛型类型可以直接贴这两个宏了**，
不必再声明一个协议、把宏贴在协议上再让它遵循：

```swift
@Loggable
struct Box<Element> {          // 以前编译不过
    func emit() { #log(.debug, "…") }
}

struct Outer<Element> {
    @Loggable
    struct Inner { … }         // 嵌套在泛型里的非泛型类型，以前同样编译不过
}
```

原因是 Swift 不允许泛型类型有 static 存储属性，**嵌套在泛型内部的非泛型类型也算**。
在泛型上下文里，宏改用协议分支一直在用的那个按 metatype 缓存的运行时缓存来解析句柄。
非泛型类型的生成结果没变，性能也没变。

一处要知道的取舍：`Box<Int>` 和 `Box<String>` 共享同一个 category `"Box"`，
因为默认 category 取的是语法树上的名字。这是有意的——category 是给人写 `log stream` 谓词用的，
按特化参数拆开只会让谓词难写。需要区分就显式传 `category:`。
