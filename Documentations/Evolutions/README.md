# Evolution 提案索引

- **项目类型**: 库（源码分发）

SPM library product，使用方以源码依赖并重新编译，未开启 library evolution，
也不以 `binaryTarget` 分发。

**「ABI 兼容性」一节填「不适用 —— 本库以 SPM 源码分发，使用方每次重新编译」即可；
「源码兼容性」一节必填。**

本库有两条特有的注意事项：

- **宏展开结果的变化也是源码破坏。** 调用点代码没改，但展开后的代码变了，同样会让下游编译不过
  或行为改变。提案里要按源码兼容性对待。
- **re-export 链会放大影响面。** `OSToolbox` re-export `FrameworkToolbox` 与 `os`，
  `SwiftStdlibToolbox` re-export `OSToolbox`，`FoundationToolbox` 再 re-export 上一层。
  改动一层的可见符号会沿链条传导到所有下游，「下游影响」一节要把链条走完。

提案格式与流程见全局 `CLAUDE.md` 的「Evolution 提案制」一节，用 `/evolution <描述>` 创建。

## 提案

| 编号 | 标题 | 状态 |
|------|------|------|
| [0001](0001-dyld-toolbox-extraction.md) | 把 dyld interposing 抽成独立的 DyldToolbox | Implemented |
| [0002](0002-signpost-macros.md) | 仿 @Loggable / #log 实现 os_signpost：@Signpostable 与 #signpost | Implemented |
| [0003](0003-objc-runtime-toolbox-self-contained-leaf.md) | 把 ObjCRuntimeToolbox 恢复为自包含的 .dynamic 叶子 | Implemented |
| [0004](0004-logging-enable-switch.md) | 给 @Loggable / @Signpostable 加启用开关，并解除泛型类型的限制 | Implemented |
| [draft](draft-objective-c-typed-collections.md) | 给被类型擦除的 NS 集合类补回 Swift 泛型 | Implemented |
| [draft](draft-inline-mutex-raw-layout.md) | 用 `@_rawLayout` 把 Mutex 的锁与值内联（暂不采纳） | Deferred |
| [draft](draft-availability-macros.md) | 引入 SwiftStdlib 可用性宏，收掉四平台长写法 | Implemented |
| [draft](draft-lexic-enum-macros.md) | 把 lexic 的五个枚举宏并入 SwiftStdlibToolbox | Implemented |
| [draft](draft-projection-multi-payload.md) | 让 @Projection 支持多关联值的 case，并修掉展开出的 unreachable default | Implemented |
| [draft](draft-projection-marker-macro.md) | 把 @Projection 的字符串参数换成标记宏 | Implemented |
| [draft](draft-sequence-comparison-selection.md) | 让序列比较可以指定用哪一套排序定义 | Implemented |

`Specs/` 与 `Plans/` 是提案制确立前的产物，见[上级索引](../README.md)，保持原样不迁移。
