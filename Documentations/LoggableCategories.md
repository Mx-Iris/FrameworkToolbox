# `@Loggable(categories:)` 与 `#log(category: \.name, ...)` 多 Category 支持

## 背景

`@Loggable` / `#log` 原本是"一个类型一个 category"：`@Loggable` 只生成一套
`category` / `subsystem` / `_osLog` / `logger`，`#log` 展开硬编码引用
`Self.logger` / `Self._osLog`。想在同一类型内把不同日志打到不同 category，只能
拆类型或绕开 `#log` 手写 `os.Logger`，而后者会失去 `#log` 的旧系统回退和隐私
标注转换。

目标：在 `@Loggable` 上声明一组命名 category，调用点静态引用，不传 logger
实例、不传裸字符串。

## 语言约束 —— 为什么不能是 `.network`

理想调用形态 `#log(category: .network, ...)` 做不到，卡在两条硬约束：

1. **表达式宏的实参在展开前就按宏声明的固定签名完成类型检查**（SE-0382）。
   `#log` 声明在库里、file scope，`.network` 这种 leading-dot 语法必须解析成
   `category:` 参数类型上真实存在的静态成员；`@Loggable` 生成的名字都在被标注
   类型内部，对 `#log` 的签名不可见。
2. **宏无法向其它类型注入成员**：只有 extension role 能生成 extension，且只能
   扩展被标注的类型本身；宏声明也只能出现在 file scope。所以 `@Loggable` 没有
   任何途径把 `network` 变成库类型上的静态成员。

## 采用的方案 —— key path 动态成员作为语法载体

`#log` 的 `category:` 参数声明为
`KeyPath<LoggableMacro.Categories, LoggableMacro.Category>`：

- `LoggableMacro.Categories` 是 `@dynamicMemberLookup`（String 键）的哑类型，
  任意名字的 `\.network` key path 字面量都能通过类型检查（Swift 5.2+ 的
  key path 字面量支持 String 键动态成员）。
- 宏在展开时从 `KeyPathExprSyntax` 中抠出成员名，重新发射为
  `Self.logger(for: .network)` / `Self._osLog(for: .network)`——`.network` 在
  展开代码里对着生成的 `LogCategory` 枚举重新解析，**真正的编译期校验发生在
  这里**：未声明的名字会在展开处报错。
- key path 本身在展开后被完全丢弃，运行时零开销。

调用形态最终是 `#log(.debug, category: \.network, "…")`，与理想形态只差一个
反斜杠。

### 生成物

`@Loggable(categories: "network", "persistence")` 在原有五个成员之外追加：

```swift
private enum LogCategory: String {
    case `network`
    case `persistence`
}
private nonisolated static func _osLog(for category: LogCategory) -> os.OSLog {
    LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.rawValue)
}
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
private nonisolated static func logger(for category: LogCategory) -> os.Logger {
    LoggableMacro._sharedLogger(subsystem: subsystem, category: category.rawValue)
}
```

- case 一律反引号引用，category 名撞上 Swift 关键字也能编译。
- 运行时缓存是新增的 `_sharedLogger(subsystem:category:)` /
  `_sharedOSLog(subsystem:category:)`（`Loggable.swift`），按
  subsystem + category 字符串对全进程共享，与既有按 `ObjectIdentifier` 键的
  协议路径缓存并存。

## 关键取舍

| 取舍 | 决定 | 理由 |
|------|------|------|
| `.network` vs `\.network` | 接受 `\.` | 语言层面无法让宏生成的名字参与库签名的 leading-dot 解析（见上文两条约束） |
| IDE 自动补全 | 放弃 `\.` 后的补全 | 动态成员没有固定成员表；校验仍是编译期的（在展开处） |
| 库级共享 `LogCategory` 结构体 + 手写 extension（方案 A） | 未采用 | 用户明确要求声明写在 `@Loggable` 上；方案 A 作为备选记录在案 |
| category 名约束 | 必须是合法 Swift 标识符 | 名字要成为枚举 case；非标识符（如含空格）由宏诊断拒绝 |
| protocol 支持 | 不支持并显式诊断 | protocol 不能容纳嵌套枚举 `LogCategory` |

## 影响面

- 新增 API：`@Loggable` 的 `categories: StaticString...` 参数、`#log` 的
  `category:` 重载、`LoggableMacro.Categories` / `LoggableMacro.Category`
  哑类型、`LoggableMacro._sharedLogger(subsystem:category:)` /
  `_sharedOSLog(subsystem:category:)` 运行时 helper。
- 既有用法完全不受影响：不写 `categories:`、不传 `category:` 时展开与之前
  逐字节一致（member 宏 `names:` 列表新增 `named(LogCategory)`，对旧代码无
  影响）。
- 测试：`LoggingMacroTests.swift` 新增 `@Loggable(categories:)` 两例展开快照
  与 `#log(category:)` 两例展开快照；`FoundationToolboxClient` 增加真实调用
  点验证（key path 参数的类型检查只有真实编译能覆盖）。

## 相关文件

- `Sources/FoundationToolbox/Macros/LoggableMacro.swift` — `@Loggable` 声明
- `Sources/FoundationToolbox/Macros/LogMacro.swift` — `#log` 声明与哑类型
- `Sources/FoundationToolbox/Loggable.swift` — 运行时缓存 helper
- `Sources/FoundationToolboxMacros/LoggableMacro.swift` — member 宏实现
- `Sources/FoundationToolboxMacros/LogMacro.swift` — 表达式宏实现
- `plugins/framework-toolbox/skills/loggable-and-log/SKILL.md` — 使用文档
