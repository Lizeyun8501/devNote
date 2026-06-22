// P2 修复 (P2-4): FFIBridge God Class 进一步拆分 —— Flashcard 领域 Mixin
//
// 从 FFIBridge 中抽取的闪卡 API。部分方法通过 C ABI 调用 Rust，
// 部分（无对应 handler）为 stub 返回降级结果。
//
// 拆分理由:
// - Flashcard 操作与 FFI 核心职责（C ABI 分发）无关，属领域 API
// - 9 个方法（3 个 FFI + 6 个 stub），约 30 行
// - 独立后便于未来对接 Dart 端 sqflite 兜底实现

import 'dart:convert';

/// Flashcard API Mixin
///
/// 宿主类需实现 [ffiCheckAvailable] 和 [ffiDispatch] 提供 C ABI 访问能力。
/// 无对应 C ABI handler 的方法返回空结果，调用方应使用 Dart 端 sqflite 兜底。
mixin FlashcardMixin {
  /// 宿主类提供：检查 FFI 是否可用，不可用则抛 StateError
  void ffiCheckAvailable();

  /// 宿主类提供：通过 C ABI 调用 Rust dispatch，返回解析后的 JSON 数据
  dynamic ffiDispatch(String event, [Map<String, dynamic>? payload]);

  // ── 有 C ABI handler 的方法 ──────────────────────────────

  Future<String> createDeck({required String name, required String description}) async {
    ffiCheckAvailable();
    return jsonEncode(ffiDispatch('FlashcardEvent.CreateDeck', {
      'name': name,
      'description': description,
    }));
  }

  Future<String> reviewFlashcard({required String flashcardId, required int quality}) async {
    ffiCheckAvailable();
    return jsonEncode(ffiDispatch('FlashcardEvent.ReviewCard', {
      'flashcard_id': flashcardId,
      'quality': quality,
    }));
  }

  Future<String> getDueCards({required String deckId, int? limit}) async {
    ffiCheckAvailable();
    return jsonEncode(ffiDispatch('FlashcardEvent.GetDueCards', {
      'deck_id': deckId,
      'limit': limit,
    }));
  }

  // ── 无 C ABI handler 的 stub 方法（返回空结果）──────────
  // P0 修复: 返回空结果而非抛异常，调用方应使用 Dart 端 sqflite 兜底

  Future<void> deleteDeck({required String deckId}) async {}
  Future<List<Map<String, dynamic>>> listDecks() async => [];
  Future<Map<String, dynamic>> createFlashcard({required String deckId, required String cardType, required String front, required String back, String? noteId}) async => {};
  Future<Map<String, dynamic>> updateFlashcard({required String id, required String front, required String back}) async => {};
  Future<void> deleteFlashcard({required String flashcardId}) async {}
  Future<Map<String, dynamic>> getReviewStats({required String deckId}) async => {'total_cards': 0, 'due_cards': 0, 'new_cards': 0};
  Future<List<Map<String, dynamic>>> batchGenerateFromNote({required String noteId}) async => [];
}
