# 0016 - 补齐 runtime proxy：init、类方法、block 参数与按对象核对的 proxy

- **状态**: Implemented
- **创建日期**: 2026-11-09
- **最后更新**: 2026-11-09
- **实现分支**: `feature/runtime-proxy-coverage`

## 摘要

`@RuntimeClassProxy` 从 Swift 声明推出选择子与类型编码，第一次调用前整批核对，但它只能表达「类名固定的
实例方法」。另外四种调用——init、类方法、带 block 参数的方法、类名随系统版本变化而只能经别的对象拿到的
对象——都还得回到 `DynamicObject`，并在旁边手写一串类型编码去核对。LaunchpadAwakener 的 payload 里剩下的
11 处手写编码全是这四种。本提案把它们补进 proxy，让编码一律由声明推出。

```swift
@RuntimeClassProxy("ECGridLayer")
protocol DockGridLayer {
    init?(layerSource: NSObject, rows: Int, columns: Int, scaleFactor: Float, layoutRTL: Bool)
    func layout()
}

@RuntimeClassProxy("DockGlassMaterialLayerController")
protocol DockGlassMaterialLayerController {
    init?(variant: Int, adaptive: Bool)
    static func currentDockMaterialEnvironmentWithColorScheme(_ colorScheme: Int) -> NSObject?
}

@RuntimeObjectProxy
protocol DockApplicationUninstalling {
    func uninstallabilityOfFileAtURL(_ url: NSURL) -> Int32?
    func uninstallBundleAtURL(_ url: NSURL, handler: @escaping @convention(block) (ObjCBool) -> Void)
}

let gridLayer = DockGridLayerImplementation(layerSource: source, rows: 5, columns: 7, scaleFactor: 2, layoutRTL: false)
gridLayer?.layout()
let environment = DockGlassMaterialLayerControllerImplementation.currentDockMaterialEnvironmentWithColorScheme(1)
DockApplicationUninstallingImplementation(uninstaller)?.uninstallBundleAtURL(url as NSURL) { hasUninstalled in }
```

## 方案

### 1. `init?` 要求：在 proxy 里构造对象

- 协议里写可失败的 `init?(…)`，生成类型里对应的构造器先对类发 `+alloc`，再发 `-init…`，成功时包住返回的
  对象。不可失败的 `init` 在编译期报错，理由与「有返回值的方法一律返回可选」相同。
- 选择子照 Swift 导入 Objective-C 时的规则反推：`init()` 是 `init`，`init(layerSource:rows:)` 是
  `initWithLayerSource:rows:`（第一个标签首字母大写，前接 `With`）。第一个参数不带标签的 `init(_:)` 推不出
  选择子，编译期报错。
- 编码返回 `@`，参数照声明推出；与实例方法一样记进 `methodRequirements`，由 `isSupported` 一并核对。
- 所有权照 ARC 的 init 族约定：`+alloc` 返回 +1，`-init…` 接管接收者并返回 +1。生成的代码经原始指针转交
  这两次引用，不经 Swift 的引用计数，所以 init 返回 nil 或换成另一个对象时都不会多放或少放。用 0.17.2 的
  引用计数测试辅助锁住。
- 类簇：`+alloc` 可能交回另一个类的对象（IconServices 的 `ISIcon` 交回 `ISIconFactory`）。initialiser
  在 alloc 交回的对象的类上查找；那个类与类名不同时，在它上面再核对一次编码，对不上就释放对象、返回 nil
  并记日志。
- 0.17.2 起拒绝写成 `func initWith…` 的 init 族方法，理由是 proxy 调用的对象不归它所有，这条不变。新的
  `init?` 调用的是自己刚 alloc 出来的对象，所有权完整。

### 2. `static` 要求：类方法

- `static func` 与只读的 `static var` 对应类方法，记进 `methodRequirements` 时 `isInstanceMethod` 为
  `false`（`MethodRequirement` 已有这个字段，`validate` 也已按它查元类），由 `isSupported` 一并核对。
- 选择子、编码与返回对象的所有权（`new`、`copy` 族为 +1）沿用实例方法的规则。

### 3. block 参数

- 写成 `@convention(block) (…) -> …` 的参数（可带 `@escaping`，可为可选）编码为 `@?`，按 block 对象传入。
  现在这种参数落到 `_ObjCTypeEncoding.of` 的兜底重载：推出 `?`，带一条弃用警告，运行时核对必然失败。
- 同一张编码表也供 `@RuntimeMethodReplacement` 使用，hook 的 block 参数一并可用。
- 返回 block 的方法仍不支持，编译期报错。

### 4. `@RuntimeObjectProxy`：按对象自己的类核对

- 写法与 `@RuntimeClassProxy` 相同，只是不给类名。`init?(_ host:)` 在 `object_getClass(host)` 上核对全部
  要求，结果按类缓存（加锁），每个类的不符只记一次日志。
- 用于经别的对象拿到、类名随版本变化的对象。例如 Dock 的环境对象，26.6.2 的类名是 `Environment`，27.2 是
  `_TtC8DockCore11Environment`，接口却相同。
- 没有可调用的类，所以 `init?` 与 `static` 要求在编译期报错；也没有 `runtimeClassName` 与 `isSupported`。
  `methodRequirements` 照样生成，供测试比对。
- 另起一个名字，而不是让 `@RuntimeClassProxy` 的类名可以省略：两者核对的时机不同，一个在第一次使用时
  对整个类核对一次，一个在每次包对象时按对象的类核对，名字上应当看得出来。

### 不做的

- 不给 proxy 加 `typeEncoding:` 参数：本提案的目的正是让编码只来自声明。
- `DynamicObject` 不动，它留给没有固定声明的探索性调用。

### 兼容性、测试与发布

- 源码兼容：现有声明的展开不变。只有带 block 参数的声明展开会变，而它们此前在运行时必定核对失败。
- ABI 兼容性：不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。
- 测试：宏展开快照覆盖四种新形状与每条新诊断；运行时测试用测试里定义的 Objective-C 类，实际调用 init、
  类方法、block 参数和按对象核对的 proxy，所有权用引用计数测试辅助检查。
- 文档：两个宏的文档注释，`CLAUDE.md` 里讲 proxy 的段落。
- 发布 0.18.0。LaunchpadAwakener 随后改用它，payload 里的 11 处手写编码与 `DynamicObject` 调用全部去掉。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-09 | Created as Draft | LaunchpadAwakener 的 payload 里剩下的 11 处手写类型编码，全部出自 proxy 表达不了的四种调用；用户同意按需给 ObjCRuntimeToolbox 增加功能 |
| 2026-11-09 | 用户批准，开始实现；实现中的问题自行决定，做完由用户验收 | 用户要求一路做完、不再逐项询问 |
| 2026-11-09 | 类簇只支持「公开类自己也实现了 initialiser」的情形；公开类没有实现的（如 `ISIcon`），proxy 照常报告不可用 | `isSupported` 对类名核对全部要求，initialiser 也不例外；为类簇单开一条推迟到构造时才核对的路径，会让 `isSupported` 不再代表「能用」。真实类簇 `NSDate` 的公开类实现了 initialiser，测试里能构造出来 |
| 2026-11-09 | initialiser 返回的对象不是类名所指类的实例时，构造失败、返回 nil | proxy 的实例方法是对类名核对的，换成别的类的对象再调用就失去了核对的意义；与 `init?(_:)` 拒绝无关对象同一个理由 |
| 2026-11-09 | block 参数必须写 `@escaping` 或为可选，否则编译期报错；block 类型的属性与返回值一律报错 | Swift 由非逃逸闭包做出的 block 会在调用返回时检查是否被留下，被调用方留下就让进程崩溃，而 Objective-C 可以留下它收到的任何 block。可选的闭包本来就是逃逸的。读回 block 的路径无法核对 block 自己的签名 |
| 2026-11-09 | 生成的 `init?` 与 `static` 成员都标 `nonisolated`；`static var` 只能只读 | 默认 `MainActor` 隔离的模块里，协议要求的实现会继承协议的隔离，`DefaultMainActorIsolationClient` 已为此加了用例；设置类属性的需求目前没有用例 |
| 2026-11-09 | 实现完成，合进 `main`，落地编号 0016，发布 0.18.0 | 整个包的构建与测试通过；LaunchpadAwakener 改用后，payload 在 macOS 27.2 与 26.6.2 的 Dock 里核对、构造、调用全部正常，其中环境对象在两个版本上类名不同，都由 `@RuntimeObjectProxy` 核对通过 |
| 2026-11-09 | 不另写使用指南，不加术语 | 用法写在两个宏的文档注释里，与 `@RuntimeClassProxy` 原有的写法一致；维护要点写进 `CLAUDE.md` 的「Runtime proxies」一条。本库没有术语表，这次也没有新的概念需要定名 |
