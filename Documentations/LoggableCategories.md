# `LogCategory` 与 `#log(category: .name, ...)` 多 Category 支持

## 背景

`@Loggable` / `#log` 原本是"一个类型一个 category"：`@Loggable` 只生成一套
`category` / `subsystem` / `_osLog` / `logger`，`#log` 展开硬编码引用
`Self.logger` / `Self._osLog`。想在同一类型内把不同日志打到不同 category，只能
拆类型或绕开 `#log` 手写 `os.Logger`，而后者会失去 `#log` 的旧系统回退和隐私
标注转换。

目标：声明一次 category 名，调用点静态引用（带补全），不传 logger 实例、不传
裸字符串。

## 语言约束 —— 为什么名字不能声明在 `@Loggable` 括号里

理想中「`@Loggable(categories: "network")` 声明 + `#log(category: .network)`
引用」的组合做不到，卡在两条硬约束：

1. **表达式宏的实参在展开前就按宏声明的固定签名完成类型检查**（SE-0382）。
   `#log` 声明在库里、file scope，`.network` 这种 leading-dot 语法必须解析成
   `category:` 参数类型上真实存在的静态成员；`@Loggable` 生成的名字都在被标注
   类型内部，对 `#log` 的签名不可见。
2. **宏无法向其它类型注入成员**：只有 extension role 能生成 extension，且只能
   扩展被标注的类型本身；宏声明也只能出现在 file scope。所以 `@Loggable` 没有
   任何途径把 `network` 变成库类型上的静态成员。

### 被否决的方案 B —— key path 动态成员（曾实现后回退）

曾用 `KeyPath<LoggableMacro.Categories, LoggableMacro.Category>` +
`@dynamicMemberLookup` 哑类型让任意 `\.network` 通过调用点类型检查，宏抠出名
字对着 `@Loggable(categories:)` 生成的嵌套枚举重新解析。名字声明确实留在了
`@Loggable` 上，但代价是 **IDE 对 `\.` 后的动态成员没有自动补全**，且拼错名
字的报错落在展开代码里。实测后因补全缺失被否决，回退换用方案 A。

## 采用的方案 —— 库级 `LogCategory` + 用户静态成员（`Notification.Name` 模式）

库提供一个平凡的值类型（`Sources/FoundationToolbox/LogCategory.swift`）：

```swift
public struct LogCategory: Hashable, Sendable {
    public let name: String
    public init(_ name: String)
}
```

使用方一行声明、处处引用——leading-dot 直接解析到用户扩展的静态成员，**补全、
调用点类型检查、跳转定义全部是原生体验**：

```swift
extension LogCategory {
    static let network = LogCategory("network")
    static let persistence = LogCategory("persistence")
}

@Loggable
struct SyncService {
    func run() {
        #log(.debug, category: .network, "request issued")
    }
}
```

### 生成物

`@Loggable` 现在对每个被标注类型（含 protocol 的默认实现 extension）**恒定**
追加两个访问器：

```swift
private nonisolated static func _osLog(for category: FoundationToolbox.LogCategory) -> os.OSLog {
    LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
}
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private nonisolated static func logger(for category: FoundationToolbox.LogCategory) -> os.Logger {
    LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
}
```

`#log(.debug, category: <expr>, ...)` 把 category 表达式**原样搬运**进展开代码
`Self.logger(for: <expr>)`——因此不限于 leading-dot，任何 `LogCategory` 表达式
（局部常量、`LogCategory("adhoc")`）都可用，并在运行时正常求值。

运行时缓存 `_sharedLogger(subsystem:category:)` /
`_sharedOSLog(subsystem:category:)`（`Loggable.swift`）按 subsystem + category
字符串对全进程共享 logger 实例。

## 关键取舍

| 取舍 | 决定 | 理由 |
|------|------|------|
| 名字声明位置 | 库类型的用户扩展，而非 `@Loggable` 括号内 | 语言约束（见上文）；换来原生补全与调用点报错，即 SwiftUI `ShapeStyle` / `Notification.Name` 的生态惯例 |
| 访问器生成时机 | 恒定生成，无开关参数 | category 集合对宏不可见，无从按需；两个静态函数零运行时成本，且让任何 `@Loggable` 类型开箱即用 `#log(category:)` |
| category 作用域 | app 级全局共享 | category 本就是横切关注点（"network" 会被多个类型使用）；subsystem 仍归属各类型自身 |
| 生成代码中的类型引用 | 限定为 `FoundationToolbox.LogCategory` | 沿用 4902ffb 确立的「生成代码限定运行时类型」约定，防用户同名类型遮蔽 |
| protocol 支持 | 支持（访问器进默认实现 extension） | 方案 A 不需要嵌套类型，protocol 路径顺带获得能力（B 方案做不到） |

## 影响面

- 新增 API：`LogCategory` 结构体、`#log` 的 `category: LogCategory` 重载、
  `LoggableMacro._sharedLogger(subsystem:category:)` /
  `_sharedOSLog(subsystem:category:)` 运行时 helper、`@Loggable` 恒定生成的
  `logger(for:)` / `_osLog(for:)`。
- 方案 B 的中间产物（`@Loggable` 的 `categories:` 参数、嵌套 `LogCategory`
  枚举、`LoggableMacro.Categories` / `Category` 哑类型、`#log` 的 KeyPath
  重载）已全部移除；B 仅存在于中间提交，未发布过版本。
- 既有用法不受影响：不传 `category:` 时 `#log` 展开与引入前逐字节一致；
  `@Loggable` 的展开多出两个访问器成员（`names:` 列表未变，`named(logger)` /
  `named(_osLog)` 已覆盖同基名函数）。
- 测试：`LoggingMacroTests.swift` 全部 `@Loggable` 快照重录（多两个成员）；
  `#log(category:)` 三例（leading-dot、带插值隐私、任意表达式）；
  `FoundationToolboxClient` 含 `extension LogCategory` 声明与真实调用点验证。

## 相关文件

- `Sources/FoundationToolbox/LogCategory.swift` — `LogCategory` 结构体
- `Sources/FoundationToolbox/Macros/LoggableMacro.swift` — `@Loggable` 声明
- `Sources/FoundationToolbox/Macros/LogMacro.swift` — `#log` 声明
- `Sources/FoundationToolbox/Loggable.swift` — 运行时缓存 helper
- `Sources/FoundationToolboxMacros/LoggableMacro.swift` — member 宏实现
- `Sources/FoundationToolboxMacros/LogMacro.swift` — 表达式宏实现
- `plugins/framework-toolbox/skills/loggable-and-log/SKILL.md` — 使用文档
