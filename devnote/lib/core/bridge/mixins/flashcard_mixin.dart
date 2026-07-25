// Flashcard API Mixin —— 基于 flutter_rust_bridge v2
//
// 从 FFIBridge 中抽取的闪卡 API。通过 FRB 生成的类型安全绑定调用 Rust。
//
// 拆分理由:
// - Flashcard 操作属领域 API，独立后便于维护
// - 9 个方法（3 个 FRB + 6 个 stub），约 30 行
// - 独立后便于未来对接 Dart 端 sqflite 兜底实现

import 'package:devnote/src/rust/library.dart' as rust;

/// Flashcard API Mixin
///
/// 宿主类需实现 [ffiCheckAvailable] 提供 FFI 可用性检查。
/// 无对应 FRB 函数的方法返回空结果，调用方应使用 Dart 端 sqflite 兜底。
mixin FlashcardMixin {
  /// 宿主类提供：检查 FFI 是否可用，不可用则抛 StateError
  void ffiCheckAvailable();

  /// 宿主类提供：P0 架构修复 —— 引擎句柄，所有 FRB API 调用均需传入
  BigInt get engineHandle;

  // ── 有 FRB 绑定的方法 ───────────────────────────────────

  Future<String> createDeck({required String name, required String description}) async {
    ffiCheckAvailable();
    return rust.createDeck(engineHandle: engineHandle, name: name, description: description);
  }

  Future<String> reviewFlashcard({required String flashcardId, required int quality}) async {
    ffiCheckAvailable();
    return rust.reviewFlashcard(engineHandle: engineHandle, flashcardId: flashcardId, quality: quality);
  }

  Future<String> getDueCards({required String deckId, int? limit}) async {
    ffiCheckAvailable();
    // FRB 生成的 getDueCards 期望 BigInt? 类型，需将 int? 转换
    return rust.getDueCards(
      engineHandle: engineHandle,
      deckId: deckId,
      limit: limit != null ? BigInt.from(limit) : null,
    );
  }

  // ── 无 FRB 绑定的 stub 方法（返回空结果）──────────
  // 调用方应使用 Dart 端 sqflite 兜底

  Future<void> deleteDeck({required String deckId}) async {}
  Future<List<Map<String, dynamic>>> listDecks() async => [];
  Future<Map<String, dynamic>> createFlashcard({required String deckId, required String cardType, required String front, required String back, String? noteId}) async => {};
  Future<Map<String, dynamic>> updateFlashcard({required String id, required String front, required String back}) async => {};
  Future<void> deleteFlashcard({required String flashcardId}) async {}
  Future<Map<String, dynamic>> getReviewStats({required String deckId}) async => {'total_cards': 0, 'due_cards': 0, 'new_cards': 0};
  Future<List<Map<String, dynamic>>> batchGenerateFromNote({required String noteId}) async => [];
}
