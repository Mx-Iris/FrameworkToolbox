# 0017 - WindowedRowsToolbox：上百万行的表格按需取行

- **状态**: Implemented
- **创建日期**: 2026-11-09
- **最后更新**: 2026-11-10
- **所属愿景**: 无
- **配套文档**: [WindowedRowsToolbox —— 用法契约与陷阱](../WindowedRowsToolbox.md)
- **关联提案**: MachOKitUI 的 `extract-windowed-rows`（把 windowed 机制抽成可复用组件），本提案是它的第 1 步

## 摘要

MachOKitUI 的详情表能显示上百万行，靠的是一套按需取行的机制：

- 使用方只给出行数，和一个按区间取行的函数；
- 缓存按可见区间分窗口取行，只留几个窗口；
- 过滤搜索在后台分批扫描；
- 拖动滚动条时暂停取行，松手后再补。

这套机制原先写死在 MachOKitUI 里：行的类型是 `MachODetailRow`，串起各部分的流程写在详情表的视图模型里。

本提案把其中与界面无关的部分搬进 FrameworkToolbox 的新 product `WindowedRowsToolbox`，按行的类型泛型，供任何大表格使用。随后两步：

- AppKit 的表格组件放进 UIFoundation；
- MachOKitUI 改用这两层。

## 方案

**新 product `WindowedRowsToolbox`**：只依赖 `OSToolbox`，用它的日志与埋点宏；不涉及任何界面框架，所以不碰界面的 MachOKitUICore 也能依赖它。它单独成一个 product，不放进 `FoundationToolbox`，因为后者的多数使用方用不到它。

| 类型 | 作用 | 在 MachOKitUI 里原来是 |
|------|------|------------------------|
| `WindowedRowSource<Row>` | 行数（第一次读时才算）、按区间取行、预热钩子、预先取好的首窗口；`rowByRow`、`fixedRowsPerElement`、`variableRowsPerElement` 三种常见形状 | `WindowedRowsProvider`；`WindowedRowsBuilder` 的 `simple`、`uniform`、`variable` |
| `WindowedLazyBox<Value>` | 只算一次、可跨线程读的惰性值 | 原样搬来 |
| `ViewportCache<Row>`、`ViewportCacheDiagnostics` | 按窗口缓存可见区间附近的行，缺的在后台取 | `MachONodeViewportCache` |
| `ViewportWindowingPolicy`、`WindowedRowsPrewarmPriority` | 窗口大小、常驻窗口数、合并上报与搜索防抖的时长 | 原样搬来 |
| `WindowedRowSearch<Row>`、`WindowedSearchProgress`、`KeywordMatcher` | 后台分批扫描全部行，收集匹配的行号；ASCII 关键词逐字节比较 | `WindowedSearchSession` |
| `WindowedRowsController<Row>` 及其 `Event` | 后台算行数、装缓存、拖动冻结与合并上报、取回窗口后重载哪些行、搜索防抖与进度节流 | 详情表视图模型里的 windowed 流程，加上两个协调器 |
| `WindowedDisplayedRows<Row>` | 当前显示的行（含过滤），供后台任务直接从来源逐行取，比如建 ⌘F 索引 | 详情表控制器里 ⌘F 扫描取行的那段 |
| `WindowedRowsScheduler`、`MainActorTaskScheduler` | 延时执行的注入点，测试里换成手动推进的时钟 | `Scheduler`、`MainActorScheduler` |

**调用点**：

```swift
let source = WindowedRowSource.rowByRow(totalCount: entries.count) { index in
    LogRow(entry: entries[index])
}
let controller = WindowedRowsController(placeholder: LogRow.loading) { source, keyword in
    .keywordMatching(source: source, keyword: keyword) { row, matcher in
        matcher.matches(row.message)
    }
}
controller.onEvent = { event in
    // Reload rows, forward visible ranges, settle — or let a table component do it
}
controller.setSource(source)
```

**没问就采用的决定**：

- **没取回的行给占位行，不给 `nil`**：占位行由使用方在构造时给。MachOKitUICore 的 `MachONodeViewportCache.row(at:)` 一直返回占位行，泛型缓存照它的做法，MachOKitUICore 才能用别名保持源码兼容。要区分真行和占位行，用 `isRowResident(at:)` 或 `isRowLoaded(atDisplayedRow:)`。
- **不标 `@available`**：`@Loggable` / `@Signpostable` 生成的成员标的是 macOS 11 起可用；外层类型若标 macOS 13，成员就比外层更早可用，编不过。所以计时改用 `ProcessInfo.systemUptime` 和 `TimeInterval`，不用 `ContinuousClock` / `Duration`，整个库在包支持的最低系统上就能用。
- **转发与预热由使用方执行**：控制器以事件交出两件事，可见区间的转发和松手后的同步预热，由使用方来做。MachOKitUI 在执行这一步的地方计算从松手到预热完成的耗时；事件序列和它原有的事件一一对应，所以它的视图模型测试不用改。
- **取消用 Combine 的 `Cancellable`**：定时注入点返回它，不另造一个取消协议。
- **搜索匹配哪些字符串，由使用方决定**：`keywordMatching(source:keyword:matches:)` 把按关键词建好的 `KeywordMatcher` 交给闭包，由闭包决定拿行里的哪些字符串去比。
- **日志名**：subsystem 统一为 `WindowedRowsToolbox`，category 是类型名。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-09 | Created as In Progress | MachOKitUI 的提案 `extract-windowed-rows` 已获用户批准，本提案是它的第 1 步，随实现一起写 |
| 2026-11-09 | 数据层放 FrameworkToolbox，单独一个 product | MachOKitUICore 要能脱离界面单独使用，它已经依赖 FrameworkToolbox；放进 UIFoundation 会让它新增对一个界面库的依赖。用户选定 |
| 2026-11-09 | 类型不标 `@available`，计时用系统运行时间 | 标了以后，宏生成的成员比外层类型更早可用，编译报错 |
| 2026-11-09 | 控制器的事件与 MachOKitUI 详情表视图模型原有的事件一一对应 | 视图模型改用控制器以后，它的测试照旧能钉住事件的顺序，不用改测试 |
| 2026-11-10 | 实现完成，合进 `main`，落地编号 0017，发布 0.19.0 | 用户批准发版。整个包的构建与测试通过；UIFoundation 的 `WindowedTable` 建在它上面，MachOKitUI 改用这两层后，默认与全部 trait 的全量测试都与改前一致。原定的版本号 0.18.0 已随 0016 发布，所以这一版是 0.19.0 |
| 2026-11-10 | 不另写实现说明，不加术语 | 使用指南 `WindowedRowsToolbox.md` 随实现写好，契约与实现要点都在里面；本库没有术语表，窗口、占位行这些说法在指南里都解释过 |
