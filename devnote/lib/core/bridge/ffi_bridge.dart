/// FFIBridge - 基于 flutter_rust_bridge v2 的类型安全桥接层
///
/// 通过 FRB v2 自动生成的 Dart 绑定调用 Rust 核心引擎。
/// 消除了手写 dart:ffi C ABI 代码（DynamicLibrary/lookupFunction/FFIResponseC）。
///
/// ## 架构
/// Dart → FRB 生成绑定 → SSE 编解码器 → Rust frb_api.rs → 引擎
///
/// ## 优势
/// - 类型安全：FRB 自动生成 Dart ↔ Rust 类型映射
/// - 内存安全：FRB 自动管理跨语言内存分配/释放
/// - 性能：SSE 编解码器比 JSON 序列化快数倍
/// - 异步原生支持：FRB 原生支持 Future
///
/// 借鉴: AppFlowy FFI 桥接模式 (https://github.com/AppFlowy-IO/AppFlowy)
/// 来源: https://pub.dev/packages/flutter_rust_bridge

import 'dart:convert';
import 'dart:developer';

import 'package:devnote/src/rust/frb_generated.dart';
import 'package:devnote/src/rust/library.dart' as rust;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'mixins/canvas_mixin.dart';
import 'mixins/flashcard_mixin.dart';
import 'mixins/git_mixin.dart';
import 'mixins/graph_mixin.dart';
import 'mixins/knowledge_mixin.dart';
import 'mixins/p2p_mixin.dart';
import 'mixins/vault_mixin.dart';

// 重新导出 VaultEncryptedData，保持向后兼容
// vault_service.dart 等调用方仍可通过 ffi_bridge.dart 导入该类型
export 'mixins/vault_mixin.dart' show VaultEncryptedData;

// ============================================================
// 数据类型
// ============================================================

/// FFI 协议版本 —— 与 Rust 端 frb_api.rs 中 VersionInfo.api_version 一致
const int kFFIApiVersion = 1;

/// 协议协商结果
class FfiVersionInfo {
  final int apiVersion;
  final String rustVersion;
  final int compatibleMin;
  final List<String> features;

  FfiVersionInfo({
    required this.apiVersion,
    required this.rustVersion,
    required this.compatibleMin,
    required this.features,
  });

  bool get isCompatible =>
      apiVersion >= compatibleMin && kFFIApiVersion >= compatibleMin;

  factory FfiVersionInfo.fromRust(rust.VersionInfo v) {
    return FfiVersionInfo(
      apiVersion: v.apiVersion,
      rustVersion: v.rustVersion,
      compatibleMin: v.compatibleMin,
      features: v.features,
    );
  }
}

/// 语音转文字结果
class TranscribeResultFfi {
  final String text;
  final int durationMs;
  final List<TranscriptSegmentFfi> segments;

  TranscribeResultFfi({
    required this.text,
    required this.durationMs,
    required this.segments,
  });
}

/// 转写片段
class TranscriptSegmentFfi {
  final String text;
  final int startMs;
  final int endMs;

  TranscriptSegmentFfi({
    required this.text,
    required this.startMs,
    required this.endMs,
  });
}

// ============================================================
// FFI 错误
// ============================================================

/// FFI 调用异常
class FfiException implements Exception {
  final String event;
  final String message;

  const FfiException(this.event, this.message);

  @override
  String toString() => 'FfiException($event): $message';
}

// ============================================================
// FFIBridge —— Flutter 与 Rust 核心通信桥接
// ============================================================

// Mixin 拆分 God Class：
// - VaultMixin: 纯 Dart 加密实现，无 FFI 依赖
// - GitMixin: 全 stub
// - P2PMixin: 全 stub，P2P 在 Dart 端独立实现
// - KnowledgeMixin: 全 stub，KnowledgeService 走 sqflite 兜底
// - CanvasMixin: 调用 FRB Canvas API
// - GraphMixin: 调用 FRB Graph API
// - FlashcardMixin: 调用 FRB Flashcard API
// 对外 API 完全不变，所有调用方零改动。
class FFIBridge
    with VaultMixin, GitMixin, P2PMixin, KnowledgeMixin, CanvasMixin, GraphMixin, FlashcardMixin {
  FFIBridge();

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  /// 初始化 FRB 桥接：加载动态库 + 初始化 FRB 运行时 + 初始化 Rust 引擎
  Future<void> init() async {
    try {
      // 初始化 FRB 运行时（加载 native 动态库 + SSE 编解码器）
      // FRB v2 使用静态方法 RustLib.init() 初始化
      await RustLib.init();

      // 初始化 Rust 核心引擎（持久化/搜索/同步等）
      // 使用应用文档目录下的 devnote.db，确保数据持久化
      final dbPath = await _getDbPath();
      await rust.initEngines(dbPath: dbPath);

      _isAvailable = true;
      log('FFIBridge initialized successfully (FRB v2)', name: 'FFIBridge');
    } catch (e) {
      _isAvailable = false;
      log('FFIBridge init failed: $e', name: 'FFIBridge', level: 900);
      rethrow;
    }
  }

  /// 获取数据库路径 —— 使用应用文档目录
  Future<String> _getDbPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'devnote.db');
    } catch (_) {
      // path_provider 不可用时使用默认路径
      return 'devnote.db';
    }
  }

  void _checkAvailable() {
    if (!_isAvailable) {
      throw StateError('FFI bridge not available. Call init() first.');
    }
  }

  // Mixin 宿主接口实现
  @override
  void ffiCheckAvailable() => _checkAvailable();

  // ============================================================
  // 系统 API
  // ============================================================

  Future<FfiVersionInfo?> negotiateVersion() async {
    if (!_isAvailable) return null;
    try {
      final version = await rust.getVersion();
      return FfiVersionInfo.fromRust(version);
    } catch (e) {
      log('FFI negotiateVersion failed: $e', name: 'FFIBridge');
      return null;
    }
  }

  Future<Map<String, bool>?> healthCheck() async {
    if (!_isAvailable) return null;
    try {
      final result = await rust.healthCheck();
      return result.engines;
    } catch (e) {
      log('FFI healthCheck failed: $e', name: 'FFIBridge');
      return null;
    }
  }

  // ============================================================
  // 笔记 API —— 调用 FRB 生成函数，转换为 Map 保持向后兼容
  // ============================================================

  Future<Map<String, dynamic>> createNote({
    required String title,
    required String content,
    required String folderId,
  }) async {
    _checkAvailable();
    final note = await rust.createNote(
      title: title,
      content: content,
      folderId: folderId,
    );
    return _noteToMap(note);
  }

  Future<Map<String, dynamic>?> getNote(String id) async {
    _checkAvailable();
    final note = await rust.getNote(id: id);
    return note != null ? _noteToMap(note) : null;
  }

  Future<Map<String, dynamic>> updateNote({
    required String id,
    required String title,
    required String content,
  }) async {
    _checkAvailable();
    final note = await rust.updateNote(id: id, title: title, content: content);
    return _noteToMap(note);
  }

  Future<void> deleteNote(String id) async {
    _checkAvailable();
    await rust.deleteNote(id: id);
  }

  Future<List<Map<String, dynamic>>> listNotes(String folderId) async {
    _checkAvailable();
    final notes = await rust.listNotes(folderId: folderId);
    return notes.map(_noteToMap).toList();
  }

  // ============================================================
  // 文件夹 API
  // ============================================================

  Future<Map<String, dynamic>> createFolder({
    required String name,
    String? parentId,
  }) async {
    _checkAvailable();
    final folder = await rust.createFolder(name: name, parentId: parentId);
    return _folderToMap(folder);
  }

  Future<List<Map<String, dynamic>>> listFolders({String? parentId}) async {
    _checkAvailable();
    final folders = await rust.listFolders(parentId: parentId);
    return folders.map(_folderToMap).toList();
  }

  Future<Map<String, dynamic>?> getFolder(String id) async {
    _checkAvailable();
    final folder = await rust.getFolder(id: id);
    return folder != null ? _folderToMap(folder) : null;
  }

  Future<void> deleteFolder(String id) async {
    _checkAvailable();
    await rust.deleteFolder(id: id);
  }

  Future<Map<String, dynamic>> updateFolder({
    required String id,
    required String name,
    String? parentId,
  }) async {
    _checkAvailable();
    final folder = await rust.updateFolder(
      id: id,
      name: name,
      parentId: parentId,
    );
    return _folderToMap(folder);
  }

  // ============================================================
  // 标签 API
  // ============================================================

  Future<Map<String, dynamic>> createTag(String name) async {
    _checkAvailable();
    final tag = await rust.createTag(name: name);
    return _tagToMap(tag);
  }

  Future<List<Map<String, dynamic>>> listTags() async {
    _checkAvailable();
    final tags = await rust.listTags();
    return tags.map(_tagToMap).toList();
  }

  Future<void> deleteTag(String id) async {
    _checkAvailable();
    await rust.deleteTag(id: id);
  }

  /// P1-2 修复: 按标签查询笔记 ID —— 通过 FFI 调用 Rust 持久化层
  Future<List<String>> getNoteIdsByTag(String tagId) async {
    _checkAvailable();
    return await rust.getNoteIdsByTag(tagId: tagId);
  }

  // ============================================================
  // 编辑器 API
  // ============================================================

  Future<Map<String, dynamic>> insertBlock({
    required String noteId,
    required String blockType,
    required String content,
    int? position,
  }) async {
    _checkAvailable();
    // FRB 生成的 insertBlock 期望 BigInt? 类型，需将 int? 转换
    final block = await rust.insertBlock(
      noteId: noteId,
      blockType: blockType,
      content: content,
      position: position != null ? BigInt.from(position) : null,
    );
    return _blockToMap(block);
  }

  Future<void> updateBlock({required String id, required String content}) async {
    _checkAvailable();
    await rust.updateBlock(id: id, content: content);
  }

  Future<void> deleteBlock(String id) async {
    _checkAvailable();
    await rust.deleteBlock(id: id);
  }

  Future<List<Map<String, dynamic>>> getBlocks(String noteId) async {
    _checkAvailable();
    final blocks = await rust.getBlocks(noteId: noteId);
    return blocks.map(_blockToMap).toList();
  }

  /// P1 架构修复 (3.3): 补齐 FFI block API
  Future<Map<String, dynamic>?> getBlock(String id) async {
    _checkAvailable();
    final block = await rust.getBlock(id: id);
    return block != null ? _blockToMap(block) : null;
  }

  /// P1 架构修复 (3.3): 补齐 FFI block API，完成双持久化迁移
  Future<void> moveBlock({required String id, required int newPosition}) async {
    _checkAvailable();
    await rust.moveBlock(id: id, newPosition: BigInt.from(newPosition));
  }

  /// P1 架构修复 (3.3): 补齐 FFI block API
  Future<void> updateBlockType({required String id, required String blockType}) async {
    _checkAvailable();
    await rust.updateBlockType(id: id, blockType: blockType);
  }

  /// P1 架构修复 (3.3): 补齐 FFI block API
  Future<List<Map<String, dynamic>>> replaceBlocks({
    required String noteId,
    required List<Map<String, dynamic>> blocks,
  }) async {
    _checkAvailable();
    final blockDataList = blocks.map((b) => _mapToBlockData(b)).toList();
    final result = await rust.replaceBlocks(noteId: noteId, blocks: blockDataList);
    return result.map(_blockToMap).toList();
  }

  // ============================================================
  // 搜索 API
  // ============================================================

  Future<List<Map<String, dynamic>>> searchNotes({
    required String query,
    int? limit,
    int? offset,
  }) async {
    _checkAvailable();
    // FRB 生成的 searchNotes 期望 BigInt? 类型，需将 int? 转换
    final results = await rust.searchNotes(
      query: query,
      limit: limit != null ? BigInt.from(limit) : null,
      offset: offset != null ? BigInt.from(offset) : null,
    );
    return results.map(_searchResultToMap).toList();
  }

  // ============================================================
  // 加密 API
  // ============================================================

  Future<String> encrypt({
    required String plaintextBase64,
    required String keyBase64,
  }) async {
    _checkAvailable();
    return rust.encrypt(plaintextBase64: plaintextBase64, keyBase64: keyBase64);
  }

  Future<String> decrypt({
    required String ciphertextBase64,
    required String keyBase64,
  }) async {
    _checkAvailable();
    return rust.decrypt(ciphertextBase64: ciphertextBase64, keyBase64: keyBase64);
  }

  Future<String> deriveKey({
    required String password,
    required String saltBase64,
  }) async {
    _checkAvailable();
    return rust.deriveKey(password: password, saltBase64: saltBase64);
  }

  // ============================================================
  // 同步 API
  // ============================================================

  Future<void> pushChanges() async {
    _checkAvailable();
    await rust.pushChanges();
  }

  Future<void> pullChanges() async {
    _checkAvailable();
    await rust.pullChanges();
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    _checkAvailable();
    final status = await rust.getSyncStatus();
    return _syncStatusToMap(status);
  }

  // ============================================================
  // 数据库 API
  // ============================================================

  Future<String> createDatabase(String name) async {
    _checkAvailable();
    return rust.createDatabase(name: name);
  }

  Future<String> evaluateFormula({
    required String formula,
    required String rowValues,
    required String allRows,
  }) async {
    _checkAvailable();
    final result = await rust.evaluateFormula(
      formula: formula,
      rowValues: rowValues,
      allRows: allRows,
    );
    return jsonEncode(result);
  }

  // ============================================================
  // CRDT API
  // ============================================================

  Future<Map<String, dynamic>> crdtMerge({
    required String docId,
    required String deviceId,
    required String remoteOpsJson,
  }) async {
    _checkAvailable();
    final result = await rust.crdtMerge(
      docId: docId,
      deviceId: deviceId,
      remoteOpsJson: remoteOpsJson,
    );
    return _mergeResultToMap(result);
  }

  // ============================================================
  // 格式 API
  // ============================================================

  Future<String> importMarkdown(String path) async {
    _checkAvailable();
    return rust.importMarkdown(path: path);
  }

  Future<void> exportMarkdown({
    required String notesJson,
    required String path,
  }) async {
    _checkAvailable();
    await rust.exportMarkdown(notesJson: notesJson, path: path);
  }

  // ============================================================
  // 语音转文字 API —— Rust 端尚未集成 whisper-rs
  // ============================================================

  Future<TranscribeResultFfi> transcribeAudio({
    required String audioBase64,
    required String lang,
  }) async => TranscribeResultFfi(text: '', durationMs: 0, segments: const []);

  // ============================================================
  // OCR API
  // ============================================================

  Future<String> ocrRecognizeImage({required String imageBase64}) async {
    _checkAvailable();
    return rust.ocrRecognizeImage(imageBase64: imageBase64);
  }

  Future<Map<String, dynamic>> ocrRecognizeImageDetailed({
    required String imageBase64,
  }) async {
    _checkAvailable();
    final result = await rust.ocrRecognizeImageDetailed(imageBase64: imageBase64);
    return {
      'text': result.text,
      'lines': result.lines,
      'confidence': result.confidence,
    };
  }

  Future<void> indexOcrText({
    required String noteId,
    required String ocrText,
  }) async {
    _checkAvailable();
    await rust.indexOcrText(noteId: noteId, ocrText: ocrText);
  }

  // ============================================================
  // FeatureFlag API —— Rust 端 frb_api.rs 暂未实现，返回空结果
  // ============================================================

  Future<List<Map<String, dynamic>>> listFeatureFlags() async => [];

  Future<void> setFeatureFlag({
    required String key,
    required bool enabled,
    String description = '',
  }) async {}

  // ============================================================
  // 工具方法
  // ============================================================

  // FRB 生成的类型不包含 toJson() 方法，以下辅助方法将其转换为 Map，
  // 保持与原 toJson() 调用方兼容的向后兼容性。
  // TODO: FRB v2 迁移后可考虑让调用方直接使用 FRB 类型

  static Map<String, dynamic> _noteToMap(rust.NoteData note) => {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'folder_id': note.folderId,
        'is_pinned': note.isPinned,
        'is_encrypted': note.isEncrypted,
        'created_at': note.createdAt,
        'updated_at': note.updatedAt,
      };

  static Map<String, dynamic> _folderToMap(rust.FolderData folder) => {
        'id': folder.id,
        'name': folder.name,
        'parent_id': folder.parentId,
        'sort_order': folder.sortOrder,
        'created_at': folder.createdAt,
        'updated_at': folder.updatedAt,
      };

  static Map<String, dynamic> _tagToMap(rust.TagData tag) => {
        'id': tag.id,
        'name': tag.name,
        'created_at': tag.createdAt,
      };

  static Map<String, dynamic> _blockToMap(rust.BlockData block) => {
        'id': block.id,
        'note_id': block.noteId,
        'block_type': block.blockType,
        'content': block.content,
        'position': block.position,
        'created_at': block.createdAt,
        'updated_at': block.updatedAt,
      };

  /// P1 架构修复 (3.3): Map 转 BlockData，用于 replaceBlocks 批量传入
  static rust.BlockData _mapToBlockData(Map<String, dynamic> map) => rust.BlockData(
        id: map['id'] as String? ?? '',
        noteId: map['note_id'] as String? ?? '',
        blockType: map['block_type'] as String? ?? 'paragraph',
        content: map['content'] as String? ?? '',
        position: (map['position'] as int?) ?? 0,
        createdAt: (map['created_at'] as String?) ?? DateTime.now().toIso8601String(),
        updatedAt: (map['updated_at'] as String?) ?? DateTime.now().toIso8601String(),
      );

  static Map<String, dynamic> _searchResultToMap(rust.SearchResult r) => {
        'note_id': r.noteId,
        'title': r.title,
        'snippet': r.snippet,
        'score': r.score,
      };

  static Map<String, dynamic> _syncStatusToMap(rust.SyncStatusData status) => {
        'status': status.status,
        'last_synced': status.lastSynced,
        'pending_changes': status.pendingChanges,
      };

  static Map<String, dynamic> _mergeResultToMap(rust.MergeResult result) => {
        'applied_count': result.appliedCount,
        'conflicts': result.conflicts,
      };

  void dispose() {
    _isAvailable = false;
  }
}
