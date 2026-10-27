# 0007 - `@FrameworkToolboxExtension` 让编译器判断协议是否只能由类遵循

- **状态**: Implemented
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **实现分支**: `feature/macro-patterns`

## 摘要

`@FrameworkToolboxExtension` 把 `box` 的默认实现拷进一个协议 extension。实例 `box` 的 setter 必须写回
（`set { self = newValue.base }`），否则经 `.box` 调用的 `mutating` 方法全部静默失效；但如果协议只能由类遵循
（class-bound：`CFType`、所有 `@objc` 协议、继承 `AnyObject` 的协议），extension 里的 setter 不是 `mutating`，
给 `self` 赋值时编译器不报错，而是在生成中间代码的阶段（SILGen）直接崩溃。宏只看得到 `extension CFType {}`，
看不到协议本身的声明，所以现在要靠调用方手写 `referenceSemantics: true` 告诉它——忘了写，就是一次编译器崩溃。

本提案让编译器替宏判断：生成的 `box` 属性挂一个 accessor 宏，按 `Self: AnyObject` 重载，协议 class-bound
时选不写回的那个实现。`referenceSemantics:` 不再需要，保留一个废弃的重载让旧写法继续编译。

## 方案

- 宏生成的实例属性改为 `@_FrameworkToolboxBoxAccessors(Self.self) public var box: FrameworkToolbox<Self>`，
  属性本身不写 accessor。
- `_FrameworkToolboxBoxAccessors` 是两个只差约束的 accessor 宏（skill 技巧 2）：`<Subject>` 版输出
  `get { FrameworkToolbox(self) }` 与 `set { self = newValue.base }`，`<Subject: AnyObject>` 版输出同样的 getter 与
  空 setter。在协议 extension 里 `Self` 是协议的泛型参数，协议 class-bound 时 `Self: AnyObject` 成立，约束更具体的
  那个胜出；否则只有不带约束的那个匹配。这正是库里 `FrameworkToolboxCompatible` 自己的两个 extension
  （一个 `where Self: AnyObject`）表达的同一个区分，只是换成了宏能用的形式。
- 辅助宏名字不带模块名：模块与类型同名（都叫 `FrameworkToolbox`），`@FrameworkToolbox.X` 会先被解析成那个 struct
  的成员而失败。名字带下划线并标 `@_documentation(visibility: private)`。
- `@FrameworkToolboxExtension` 拆成两个重载：常用的那个没有 `referenceSemantics:`；带 `referenceSemantics:` 的那个标
  `@available(*, deprecated)`，实现忽略这个参数。库内唯一的调用点（`CoreFoundationToolbox` 的 `CFType`）改掉。

需要真实编译验证的两点：在协议 extension 成员的宏参数里写 `Self.self` 能否正常解析、不触发循环引用；以及两个重载
在 class-bound 与非 class-bound 协议上各自选对。前者由 `CoreFoundationToolbox` 与 `SwiftStdlibToolbox` 的现有调用点覆盖，
后者另加客户端守卫（`@objc` 协议、继承 `AnyObject` 的协议、普通协议）与运行时测试（值类型经 `.box` 的 `mutating`
调用确实写回）。

### 源码兼容性

不写 `referenceSemantics:` 的调用点：class-bound 协议上从编译器崩溃变为正常编译，其余展开结果语义不变。写了的调用点
继续编译，多一条废弃警告。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 按 `swift-macro-patterns` skill 的技巧审视全部宏时发现：`referenceSemantics:` 是让调用方代替编译器回答「协议是不是 class-bound」，答错的代价是编译器崩溃 |
| 2026-10-27 | 用户批准，开始实现 | 审视结论中的各项改进经用户同意全部实施 |
| 2026-10-27 | `referenceSemantics:` 废弃而不删除 | 删除会让写了它的调用点编不过；废弃重载让旧写法继续编译，只多一条警告 |
| 2026-10-27 | 真实编译验证通过 | 守卫 `FrameworkToolboxClient/ReferenceSemanticsDetection.swift`（继承 `AnyObject` 的协议、`@objc` 协议、普通协议）在改动前让编译器在 SILGen 崩溃（signal 5，`While silgen emitFunction … ClassBoundService … box`），改动后编译通过；`Self.self` 作为协议 extension 成员上的宏参数可以正常解析，没有循环引用。`CFType` 去掉 `referenceSemantics:` 后照常编译；值类型一侧的写回由 `ComparableExtensionTests` 经 `BinaryInteger` 的扩展在运行时验证。旧写法用临时文件编译一次：编译通过，带一条废弃警告 |
| 2026-10-27 | 实现完成，待合并 | 完整测试套件通过 |
| 2026-10-27 | Implemented，编号 0007 | 随 `feature/macro-patterns` 合入 main，与方案没有偏离。文档判断：`referenceSemantics:` 的废弃写在宏的文档注释与废弃信息里，`CLAUDE.md` 的 box 条目已改写；不另写使用指南，没有新术语 |
