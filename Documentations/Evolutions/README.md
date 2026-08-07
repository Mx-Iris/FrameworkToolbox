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

尚无提案。今后的新功能与架构改动一律从这里开始，编号自 `0001` 起。

`Specs/` 与 `Plans/` 是提案制确立前的产物，见[上级索引](../README.md)，保持原样不迁移。
