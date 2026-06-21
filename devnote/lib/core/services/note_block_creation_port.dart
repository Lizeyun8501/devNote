// P1 修复 (P1-3): notes ↔ editor 循环依赖解耦
//
// 定义 notes 模块需要的 block 创建接口，由 editor 模块的 EditorService 实现。
// notes 模块依赖此抽象接口（依赖倒置原则），不再直接 import editor 模块，
// 打破 notes → editor 方向的循环依赖。
//
// 接口仅包含 notes 模块实际调用的方法，遵循接口隔离原则（ISP）。

/// 笔记 block 创建端口
///
/// notes 模块通过此接口创建笔记内容块，无需依赖 editor 模块的具体实现。
/// 实现方（EditorService）负责将字符串类型名映射为 BlockType enum 并持久化。
abstract class NoteBlockCreationPort {
  /// 根据字符串类型名创建 block
  ///
  /// [blockTypeName] 对应 BlockType enum 的 name（如 'paragraph'、'heading' 等），
  /// 找不到匹配时由实现方决定回退策略（通常回退为 paragraph）。
  Future<void> createBlockFromString({
    required String noteId,
    required String blockTypeName,
    required String content,
    required int position,
  });
}
