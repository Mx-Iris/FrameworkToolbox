# 存储层重构与 `@UserDefault` 宏

## 背景

`@Keychain` 宏发布之后，运行时和编码协议都是 Keychain 专用的：

- `KeychainStorable` 协议定义在 `Sources/FoundationToolbox/Keychain/`，方法名 `_decodeKeychainValue` / `_encodeKeychainValue` 显式带 Keychain 前缀。
- 所有基础类型（`String`、`Data`、`Bool`、整数族、浮点、`Date`、`URL`、`Optional`）的 conformance 也耦合在该协议之上。
- 宏生成的 publisher 是 `AnyPublisher<Value, Never>`，多了一次 type-erase 的 boxing。

后续要加 `@UserDefault` 宏，本质和 Keychain 是同一类东西（"声明一个属性，背后跑一套带缓存 + 发布器的持久化"），但存储介质不同：Keychain 写 `Data`，UserDefaults 写 plist 原生对象（`String` / `NSNumber` / `NSDate` / `NSData` / `NSArray` / `NSDictionary`）。如果什么都不抽，等于把全套基础类型 conformance 再抄一遍，命名又冲突。

本次重构目标：

1. 把"基础类型编码"这一套抽到 `FoundationToolbox/Storage/`，让 Keychain 和 UserDefault 各自复用。
2. 把宏生成的 `AnyPublisher` 改成 `some Publisher`，省一次 boxing，同时让 publisher 的 opaque 返回类型天然遮蔽 `PassthroughSubject.send`。
3. 增加 `@UserDefault(key:suite:)` 宏，与 `@Keychain` 形态对齐。

## 整体结构

```
Sources/FoundationToolbox/
├── Storage/
│   ├── DataStorable.swift          ← Self ↔ Data（Keychain 用）
│   └── PlistStorable.swift         ← Self ↔ Any（UserDefaults 用）
├── Keychain/
│   ├── KeychainAccessibility.swift
│   ├── KeychainError.swift
│   ├── KeychainStorable.swift      ← 退化为 typealias 门面
│   └── KeychainStorage.swift       ← 改用 _decodeStorableData / _encodeStorableData
├── UserDefault/
│   ├── UserDefaultStorable.swift   ← typealias = PlistStorable
│   ├── UserDefaultError.swift
│   └── UserDefaultStorage.swift    ← 新增
└── Macros/
    ├── KeychainMacro.swift
    └── UserDefaultMacro.swift      ← 新增公共宏声明
```

宏实现侧：

```
Sources/FoundationToolboxMacros/
├── KeychainMacro.swift             ← 生成 $name 改 some Publisher
├── UserDefaultMacro.swift          ← 新增
└── MainPlugin.swift                ← 注册 UserDefaultMacro
```

## 协议设计

两个协议**对偶**，方法名都以 `_decodeStorable*` / `_encodeStorable*` 开头，前缀 `Storable` 强调"这是给底层 storage backend 用的内部 hook"，下划线开头标识"实现细节，但需要 public 让宏展开可以引用"。

### `DataStorable`

```swift
public protocol DataStorable: Sendable {
    static func _decodeStorableData(from data: Data) -> Self?
    func _encodeStorableData() -> Data
}

public protocol DataCodableStorable: DataStorable, Codable {}
```

行为完全沿用旧 `KeychainStorable`：整数走 little-endian 定宽编码，浮点走 `bitPattern`，`URL` 走 `absoluteString` 编码成 utf8 bytes，Codable 走 JSON。

### `PlistStorable`

```swift
public protocol PlistStorable: Sendable {
    static func _decodeStorablePlist(_ object: Any) -> Self?
    func _encodeStorablePlist() -> Any
}

public protocol PlistCodableStorable: PlistStorable, Codable {}
```

`_encodeStorablePlist()` 返回的 `Any` 必须是 plist-compatible 对象，否则 `UserDefaults.set(_:forKey:)` 会抛异常。基础类型一一映射：

| Swift 类型 | plist 表示 |
|---|---|
| `String` | `String` |
| `Data` | `Data` |
| `Bool` | `Bool`（NSNumber 桥接） |
| `Int*` / `UInt*` | `NSNumber` |
| `Double` / `Float` | `Double` / `Float` |
| `Date` | `Date` |
| `URL` | `String`（absoluteString） |

`URL` 故意走字符串而不是 `NSKeyedArchiver`，这样 `defaults read` 和 plist editor 都能直接看到 URL 文本——代价是 `UserDefaults.url(forKey:)` 会把这个字符串当作文件路径走 `URL(fileURLWithPath:)` + tilde 展开，**返回一个非 nil 但语义错误的 file URL**。这是一个**明确的取舍**：我们假定用户通过 `@UserDefault` 投影读写；若必须从 `UserDefaults` 直接读，用 `string(forKey:)` 再 `URL(string:)` 自己反序列化。

Codable 类型走 `JSONEncoder` 编码成 `Data`，存到 plist 里仍然是 `Data`。如果用户想让 `defaults read` 看到结构化的字典，可以手写 `PlistStorable` 把 `Codable` 转成 `[String: Any]`。

### 共享的 `_AnyOptionalStorableValue` hook

`Optional` 对两个协议都条件 conform。`nil` 的语义两边一致：让 storage backend 走"删除"路径（`SecItemDelete` / `removeObject(forKey:)`），而不是写入"空"或 `NSNull`。

为了避免每个 protocol 单独维护一个 nil-detection hook，抽出一个 internal 协议放在 `DataStorable.swift` 末尾：

```swift
internal protocol _AnyOptionalStorableValue {
    var _isStorableNil: Bool { get }
}

extension Optional: _AnyOptionalStorableValue {
    internal var _isStorableNil: Bool {
        switch self {
        case .none: return true
        case .some: return false
        }
    }
}
```

`KeychainStorage` 和 `UserDefaultStorage` 都用 `as? _AnyOptionalStorableValue` 来探测 nil。

### 向后兼容

```swift
public typealias KeychainStorable = DataStorable
public typealias KeychainCodableStorable = DataCodableStorable
public typealias UserDefaultStorable = PlistStorable
public typealias UserDefaultCodableStorable = PlistCodableStorable
```

旧代码里 `struct X: KeychainCodableStorable` 这种声明 **不需要改**。但旧的 `_encodeKeychainValue` / `_decodeKeychainValue` 方法名重命名为 `_encodeStorableData` / `_decodeStorableData`——这两个是 underscore-prefixed 的实现细节，**理论上不算 public API**，但项目内的测试用到了，已经一并改过来。

## `some Publisher` 改造

旧版宏生成：

```swift
var $accessToken: AnyPublisher<String, Never> {
    _accessToken.publisher
}
```

新版：

```swift
var $accessToken: some Publisher<String, Never> {
    _accessToken.publisher
}
```

`KeychainStorage.publisher` 和 `UserDefaultStorage.publisher` 也都从 `AnyPublisher<Value, Never>` 改成 `some Publisher<Value, Never>`，直接返回 `subject`（`PassthroughSubject<Value, Never>`）。opaque return type 自动隐藏 `PassthroughSubject` 的具体类型，所以外部拿到的 publisher **看不到** `.send(_:)`——天然防止了"用 publisher 投影绕过 storage 直接 inject 值"这种误用。

`Combine.Publisher` 在 macOS 13 / iOS 16 之后的 SDK 标注了 primary associated types `Publisher<Output, Failure>`，Swift 5.7+ 编译期合法。Package 使用 `swift-tools-version: 6.2`，对应 Xcode 26+ 工具链，SDK 一定带有该标注。

## `UserDefaultStorage` 运行时

```swift
public final class UserDefaultStorage<Value: UserDefaultStorable>: @unchecked Sendable
```

骨架与 `KeychainStorage` 对齐：

- `NSRecursiveLock` 保护所有可变状态。
- 内存 `cachedValue` + `hasLoadedCache`，第一次 `get()` 才命中 `UserDefaults`。
- `PassthroughSubject<Value, Never>` 作为 publisher 底座。
- `errorHandler` 可注入，默认 `print(error)`。

`UserDefaultStorage` 比 `KeychainStorage` 多一份职责：**外部修改**。`UserDefaults.didChangeNotification` 会在本进程任何 `set(_:forKey:)` 之后同步发出，订阅这个通知就能把"系统 Settings.app 修改"、"代码里直接 `UserDefaults.standard.set(...)` 绕过我们"、"另一个进程对同一 suite 写入"等场景都纳入 publisher。

### 去重问题

`set(_:forKey:)` 同步触发 `didChangeNotification`，如果我们 `set(_:)` 自己 send 一次、handler 又 send 一次，subscriber 会收到重复事件。

方案对比：

| 方案 | 优点 | 缺点 |
|---|---|---|
| 只让 handler send | 单一发布点 | 外部 `removeObject` 时 handler 无法区分"是本进程 set(nil) 导致的"还是"外部删的"，cache 重置成 default 会丢掉本进程刚 set(nil) 的 cache=.some(.none) 语义 |
| 只让 set send | 简单 | 外部修改感知不到 |
| set send + handler send | 完整 | 重复 |
| set send + suppress flag | 完整 + 不重复 | 依赖 `didChangeNotification` 在 `set(_:forKey:)` 内同步触发 |

最终采用最后一种：

```swift
public func set(_ newValue: Value) {
    lock.withLock {
        cachedValue = newValue
        hasLoadedCache = true

        suppressNextNotification = true
        defer { suppressNextNotification = false }

        if let optional = newValue as? _AnyOptionalStorableValue, optional._isStorableNil {
            store.removeObject(forKey: key)
        } else {
            store.set(newValue._encodeStorablePlist(), forKey: key)
        }

        subject.send(newValue)
    }
}

private func handleExternalChange() {
    lock.withLock {
        if suppressNextNotification {
            suppressNextNotification = false
            return
        }
        // 重读 store + send
        ...
    }
}
```

`NSRecursiveLock` 让本线程同步重入是安全的。observer 用 `queue: nil` 注册，回调在 posting 线程上**同步**执行（Foundation 文档保证：`If queue is nil, the block is run synchronously on the posting thread.`）。所以 set 路径里 `suppressNextNotification` flag 一定在 handler 那次回调被消费完之前不会跑出 lock 区域。

外部修改 → handler 看到 `suppressNextNotification == false` → 重读 + send。

外部 `removeObject` → handler 看到 store.object 为 nil → 失效 cache 并发 defaultValue。

### `suite` 解析失败

`UserDefaults(suiteName:)` 对保留名（如 `NSGlobalDomain`）会返回 nil。我们 fallback 到 `.standard` 并打印一行 `UserDefaultError.unresolvedSuite`。开发期容易暴露，不至于静默吞掉。

## 宏 API

```swift
@attached(accessor)
@attached(peer, names: arbitrary)
public macro UserDefault(
    key: String,
    suite: String? = nil
) = #externalMacro(module: "FoundationToolboxMacros", type: "UserDefaultMacro")
```

参数特意只暴露 `key` 和 `suite`——不接收任意 `UserDefaults` 实例，这样宏参数全是常量字符串，宏展开生成的 `private let _name = UserDefaultStorage<...>(...)` 在 module load 阶段就能完成初始化，不踩"非 standard 实例的生命周期"这种坑。app group 场景通过 suite 名搞定就够覆盖 99% 用例。

宏实现复用 `MacroToolbox.LockPropertyParser`（与 `@Keychain` 一致），所以 weak / static / public / optional / 显式初始值等所有边角情况都已经被那一层处理过了。

## 取舍清单

- **URL plist 编码用 absoluteString**：换来 `defaults read` 可读性，代价是与 `UserDefaults.url(forKey:)` 不互通。
- **Codable 走 JSON Data**：换来实现简单，代价是 `defaults read` 看到的是一团 Data。需要 plist 字典样式的用户可以手写 `PlistStorable`。
- **suite 解析失败 fallback 到 .standard**：换来不需要 throws init，代价是开发期错误只通过 print 报。
- **`set` 显式 send + suppress flag**：依赖了"`didChangeNotification` 在 `set(_:forKey:)` 内同步触发 + `queue: nil` observer 同步回调"这两条 Foundation 行为；若未来 Foundation 改成异步分发，会出现重复事件（非崩溃，subscriber 会观察到一次重复），届时需要换成 generation counter 之类的 token 机制。

## 测试覆盖

- `PlistStorableTests`：所有基础类型 + Optional + Codable round-trip + 异常输入。
- `UserDefaultStorageTests`：
  - 基础类型 round-trip（String / Int / Bool / Date / URL）
  - Optional nil → `removeObject`
  - publisher 在本地 set 时**严格一次**发出（验证 suppress flag）
  - publisher 在外部 `set(_:forKey:)` 时发出
  - publisher 在外部 `removeObject` 时发出 defaultValue
  - errorHandler 捕获 decoding failure
  - Codable round-trip
- `UserDefaultMacroTests`：与 `KeychainMacroTests` 形态对齐（string / int / optional / customSuite / public / static）。
- 现有 `KeychainStorableTests` / `KeychainMacroTests` 已经同步改用新方法名 / 新 publisher 类型。

## 迁移指引（对外）

- 旧代码里 `struct X: KeychainCodableStorable` **无需改动**——typealias 仍然有效。
- 如果你之前手写了 `_encodeKeychainValue` / `_decodeKeychainValue` 实现来覆盖默认 JSON 编码，必须重命名为 `_encodeStorableData` / `_decodeStorableData`，否则你的实现不会再被协议看到，会被默认实现（JSON）静默替代。
- 旧代码里把 `KeychainStorage(...).publisher` 或宏投影 `$name` 当 `AnyPublisher<...>` 存到属性的，要改成 `some Publisher<...>` 或者 `.eraseToAnyPublisher()`。
- 任何之前接收 `AnyPublisher<Value, Never>` 参数的函数也无法再直接传入 `$name` / `storage.publisher`，需要先 `.eraseToAnyPublisher()` 或把参数改为 `some Publisher<Value, Never>`。
- `KeychainError.encodingFailed` 和 `UserDefaultError.encodingFailed` 是当前未被任何代码路径触发的 dead case，本次重构已移除。如果你之前 switch 这两个错误，需要从 switch 中删掉对应 case。
- 新增 `@UserDefault` 宏与 `@Keychain` 对偶，可立即使用。
