# Draft - `LogCategory` 可以让 `#log` 在消息开头标出 `[Category]`

- **状态**: In Progress
- **创建日期**: 2026-11-11
- **最后更新**: 2026-11-11
- **实现分支**: `feature/log-category-message-prefix`

## 摘要

`#log(category:)` 把日志打进指定的 os_log category，但消息文字本身不带 category。使用方于是在消息里手写标签：
RuntimeViewer、LyricsX、LookInside 里有近五十条 `#log(.debug, "[EngineMirroring] …")` 这样的写法，标签逐条手抄。
本提案让 `LogCategory` 在声明时选择给消息加前缀：用 `LogCategory("EngineMirroring", prefixesMessages: true)` 声明的
category，经 `#log(category:)` 打出的每条消息都以 `[EngineMirroring] ` 开头。前缀只改消息文字，不改 os_log 的 category；
没有打开前缀的 category，以及不写 `category:` 的 `#log`，输出都不变。

## 方案

调用点：

```swift
extension LogCategory {
    static let engineMirroring = LogCategory("EngineMirroring", prefixesMessages: true)
}

#log(.debug, category: .engineMirroring, "requesting engine list from \(name, privacy: .public)")
// [EngineMirroring] requesting engine list from …
```

- **`LogCategory`**：新增 `public let prefixesMessages: Bool` 与 `init(_ name: String, prefixesMessages: Bool)`。原有的
  `init(_ name: String)` 保留为独立的构造器，不改成默认参数：`["a", "b"].map(LogCategory.init)` 这类把构造器当函数值用的
  写法，多一个带默认值的参数就编不过。前缀文字 `"[name] "` 在构造时算好、存在一个 internal 属性里——category 通常是
  `static let`，只算一次，而不是每条日志拼一次字符串。
- **运行时入口**：`LoggableMacro._messagePrefix(for:)` 返回这段文字（没打开前缀时是空串），由 `#log` 的展开调用，
  与 `_isEnabled`、`_sharedLogger` 放在一起。
- **`#log(category:)` 的展开**：
  - category 表达式成为外层闭包的实参，绑定到参数 `selectedLogCategory`（类型写作 `OSToolbox.LogCategory`，leading-dot
    照常解析）；句柄与前缀都读它，表达式仍只求值一次。名字照 `legacyArgument0` 的先例取固定的可读名，不用
    `makeUniqueName`。
  - `os.Logger` 分支：在消息字面量开头插入
    `\(OSToolbox.LoggableMacro._messagePrefix(for: selectedLogCategory), privacy: .public)`。宏只看得到 `.network` 这几个
    字符，名字要到运行时才知道，所以前缀只能是一个插值；必须标 `public`，否则脱离调试器时会被打码成 `<private>`。
    raw 字符串（`#"…"#`）里插入的插值要带同样的 `#`；多行字符串里插入的插值接过结束符 `"""` 的缩进，原第一行让出自己的
    缩进，否则那一行缩进不足、编译不过；空的多行字符串没有可开的行，改成只含前缀的单行字面量。
  - 旧系统的 `os_log` 分支：格式串开头加一个 `%{public}s`，前缀照其它片段的做法经 `withCString` 传入，不依赖 Foundation。
  - 不写 `category:` 的 `#log` 展开逐字不变。
- **测试**：
  - 宏快照：改写现有三个 `category:` 用例；新增 raw 字符串、以插值开头、空消息、空的多行消息，以及调用方变量与闭包参数
    同名五例。有内容的多行消息不留快照，原因见决策日志。
  - 运行时：`_messagePrefix(for:)` 的两种结果；`LoggingControl` 的按 category 开关仍按名字匹配，与前缀开关无关
    （放进 `ProcessWideSwitchTests`）。
  - 端到端：经 `OSLogStore` 读回本进程刚打的日志，确认渲染出的文字就是 `[Name] message`，没打开前缀的 category 原样输出。
  - 编译守卫：`OSToolboxNoFoundationClient`（展开不依赖 Foundation）、`DefaultMainActorIsolationClient`（Swift 6、默认
    MainActor 隔离）、`FoundationToolboxSoleImportClient`（只 import 一个 product）各用一个打开前缀的 category；
    `OSToolboxClient` 加示例。
- **文档**：`LogCategory` 与 `#log(category:)` 的文档注释、`Documentations/LoggableCategories.md` 新增一节、随库发布的
  `loggable-and-log` skill、项目 `CLAUDE.md` 的 Logging 一条。

没有询问就采用的假设：

- 前缀格式固定为 `[name] `，`name` 原样输出；不提供自定义前缀文字。
- 只能在声明时打开：没有 `LoggingControl` 那样的运行时开关，也不覆盖不写 `category:` 的 `#log`（类型默认的 category
  是 `String`，不是 `LogCategory`）。
- 参数名 `prefixesMessages`：布尔属性读作对接收者的断言（「这个 category 给消息加前缀」），前缀的内容由文档注释说明。
- `LogCategory` 的 `==` / `hash` 沿用编译器合成，新属性算在内；`LoggingControl` 的开关一直按 `name` 匹配，不受影响。

### 源码兼容性

- `LogCategory("x")`，以及把 `LogCategory.init` 当函数值用：不变。
- 不写 `category:` 的 `#log`：展开逐字不变。
- 写了 `category:` 的 `#log`：每一处的展开都会变，多一个局部常量和一个前缀参数。没打开前缀时那个参数是空串，输出文字
  不变，只有 `log show --style json` 里的 `formatString` 多一个 `%{public}s`。目前只有本库自己的 Client target 用到
  `category:`。
- 名字相同、前缀开关不同的两个 `LogCategory` 不再相等。

### 落地步骤

1. [x] `LogCategory.prefixesMessages` 与 `LoggableMacro._messagePrefix(for:)`，加运行时测试。
2. [x] `#log(category:)` 的展开插入前缀（两条分支），更新与新增宏快照。
3. [ ] 编译守卫、示例与 `OSLogStore` 端到端测试。
4. [ ] 文档注释、`LoggableCategories.md`、`loggable-and-log` skill、`CLAUDE.md`。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-11 | Created as Draft | 使用方在消息里逐条手写 `[EngineMirroring]` 这类标签，要让 `LogCategory` 自己带上它 |
| 2026-11-11 | 前缀由每个 `LogCategory` 在声明时打开，默认关 | 用户选定。不一律加，是为了保留不带前缀的 category；不做全局开关，是因为手写的标签都是类型内部的子话题，从来不是类型名 |
| 2026-11-11 | 用户批准，开始实现 | 状态改为 Accepted |
| 2026-11-11 | category 绑定为外层闭包的参数，不是闭包里的 `let` | 实参在闭包外求值，调用方自己名为 `selectedLogCategory` 的变量也能当 category 传；`let selectedLogCategory = selectedLogCategory` 会引用到自己 |
| 2026-11-11 | 生成代码写全 `OSToolbox.LoggableMacro`；前缀插值逐个节点构造，不从模板字面量解析 | 展开落在调用方文件里，按宏的惯例写全模块名。第一版从解析出的 `"\(x)"` 取第一个片段，取到的是插值前的空字符串片段，前缀悄无声息地消失，快照测试才抓到 |
| 2026-11-11 | 有内容的多行消息不留快照，记为后续项 | 新系统分支已核对正确（前缀接过结束符的缩进），但旧系统分支把消息里的换行原样抄进单行的格式串字面量，编不过——不写 `category:` 时同样如此，是早于本提案的缺陷。raw 字符串内容里含 `"` 或 `\` 时同理 |
