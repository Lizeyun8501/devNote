/// Dispatch 层 —— 基于 flutter_rust_bridge 的直接函数调用
///
/// ## 替换说明
/// 原实现：Event-Dispatch 模式，通过字符串事件名路由到 Rust handler
/// 替换为：FRB 直接函数调用，类型安全，无需字符串路由
///
/// ## 核心变更
/// 1. 消除 Event-Dispatch 字符串路由（"NoteEvent.CreateNote" → createNote()）
/// 2. 消除 JSON 序列化/反序列化（FRB 使用 SSE 编解码器）
/// 3. 消除 FlowyResult 包装（FRB 直接使用 Result 类型）
/// 4. 消除 asyncRequest 的回调模式（FRB 直接返回 Future）
///
/// 来源: https://pub.dev/packages/flutter_rust_bridge
/// 借鉴 AppFlowy 的 Dispatch 模式（已升级为 FRB 直接调用）

import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

/// FRB Dispatch —— 替代原 Event-Dispatch 模式
///
/// 原模式：dispatch.asyncRequest("NoteEvent.CreateNote", payload: bytes)
/// 新模式：dispatch.createNote(title: "xxx", content: "xxx", folderId: "xxx")
///
/// 优势：
/// - 编译时类型检查（拼写错误在编译时发现）
/// - 无需 JSON 序列化/反序列化
/// - 无需手动管理 payload 编码
/// - IDE 自动补全和重构支持
class Dispatch {
  FFIBridge get _bridge => getIt<FFIBridge>();

  // ============================================================
  // 笔记操作 —— 替代原 NoteEvent.* 事件路由
  // ============================================================

  Future<Map<String, dynamic>> createNote({
    required String title,
    required String content,
    required String folderId,
  }) => _bridge.createNote(title: title, content: content, folderId: folderId);

  Future<Map<String, dynamic>?> getNote(String id) => _bridge.getNote(id);

  Future<Map<String, dynamic>> updateNote({
    required String id,
    required String title,
    required String content,
  }) => _bridge.updateNote(id: id, title: title, content: content);

  Future<void> deleteNote(String id) => _bridge.deleteNote(id);

  Future<List<Map<String, dynamic>>> listNotes(String folderId) =>
      _bridge.listNotes(folderId);

  // ============================================================
  // 文件夹操作 —— 替代原 FolderEvent.* 事件路由
  // ============================================================

  Future<Map<String, dynamic>> createFolder({
    required String name,
    String? parentId,
  }) => _bridge.createFolder(name: name, parentId: parentId);

  Future<List<Map<String, dynamic>>> listFolders({String? parentId}) =>
      _bridge.listFolders(parentId: parentId);

  Future<void> deleteFolder(String id) => _bridge.deleteFolder(id);

  // ============================================================
  // 标签操作 —— 替代原 TagEvent.* 事件路由
  // ============================================================

  Future<Map<String, dynamic>> createTag(String name) => _bridge.createTag(name);

  Future<List<Map<String, dynamic>>> listTags() => _bridge.listTags();

  Future<void> deleteTag(String id) => _bridge.deleteTag(id);

  // ============================================================
  // 编辑器操作 —— 替代原 EditorEvent.* 事件路由
  // ============================================================

  Future<Map<String, dynamic>> insertBlock({
    required String noteId,
    required String blockType,
    required String content,
    int? position,
  }) => _bridge.insertBlock(
    noteId: noteId, blockType: blockType, content: content, position: position,
  );

  Future<void> updateBlock({required String id, required String content}) =>
      _bridge.updateBlock(id: id, content: content);

  Future<void> deleteBlock(String id) => _bridge.deleteBlock(id);

  Future<List<Map<String, dynamic>>> getBlocks(String noteId) =>
      _bridge.getBlocks(noteId);

  // ============================================================
  // 搜索操作 —— 替代原 SearchEvent.* 事件路由
  // ============================================================

  Future<List<Map<String, dynamic>>> searchNotes({
    required String query,
    int? limit,
    int? offset,
  }) => _bridge.searchNotes(query: query, limit: limit, offset: offset);

  // ============================================================
  // 加密操作 —— 替代原 CryptoEvent.* 事件路由
  // ============================================================

  Future<String> encrypt({required String plaintextBase64, required String keyBase64}) =>
      _bridge.encrypt(plaintextBase64: plaintextBase64, keyBase64: keyBase64);

  Future<String> decrypt({required String ciphertextBase64, required String keyBase64}) =>
      _bridge.decrypt(ciphertextBase64: ciphertextBase64, keyBase64: keyBase64);

  Future<String> deriveKey({required String password, required String saltBase64}) =>
      _bridge.deriveKey(password: password, saltBase64: saltBase64);

  // ============================================================
  // 同步操作 —— 替代原 SyncEvent.* 事件路由
  // ============================================================

  Future<void> pushChanges() => _bridge.pushChanges();
  Future<void> pullChanges() => _bridge.pullChanges();
  Future<Map<String, dynamic>> getSyncStatus() => _bridge.getSyncStatus();

  // ============================================================
  // Canvas 操作 —— 替代原 CanvasEvent.* 事件路由
  // ============================================================

  Future<void> canvasAddNode({required String canvasId, required String nodeJson}) =>
      _bridge.canvasAddNode(canvasId: canvasId, nodeJson: nodeJson);

  Future<void> canvasRemoveNode({required String canvasId, required String nodeId}) =>
      _bridge.canvasRemoveNode(canvasId: canvasId, nodeId: nodeId);

  Future<void> canvasAutoLayout({required String canvasId, required String layoutType}) =>
      _bridge.canvasAutoLayout(canvasId: canvasId, layoutType: layoutType);

  // ============================================================
  // 数据库操作 —— 替代原 DatabaseEvent.* 事件路由
  // ============================================================

  Future<String> createDatabase(String name) => _bridge.createDatabase(name);

  Future<String> evaluateFormula({
    required String formula,
    required String rowValues,
    required String allRows,
  }) => _bridge.evaluateFormula(formula: formula, rowValues: rowValues, allRows: allRows);

  // ============================================================
  // 图谱操作 —— 替代原 GraphEvent.* 事件路由
  // ============================================================

  Future<String> calculateCentrality() => _bridge.calculateCentrality();
  Future<String> detectClusters() => _bridge.detectClusters();

  // ============================================================
  // 闪卡操作 —— 替代原 FlashcardEvent.* 事件路由
  // ============================================================

  Future<String> createDeck({required String name, required String description}) =>
      _bridge.createDeck(name: name, description: description);

  Future<String> reviewFlashcard({required String flashcardId, required int quality}) =>
      _bridge.reviewFlashcard(flashcardId: flashcardId, quality: quality);

  Future<String> getDueCards({required String deckId, int? limit}) =>
      _bridge.getDueCards(deckId: deckId, limit: limit);

  // ============================================================
  // CRDT 操作 —— 替代原 CRDTEvent.* 事件路由
  // ============================================================

  Future<Map<String, dynamic>> crdtMerge({
    required String docId,
    required String deviceId,
    required String remoteOpsJson,
  }) => _bridge.crdtMerge(docId: docId, deviceId: deviceId, remoteOpsJson: remoteOpsJson);

  // ============================================================
  // 格式操作 —— 替代原 FormatEvent.* 事件路由
  // ============================================================

  Future<String> importMarkdown(String path) => _bridge.importMarkdown(path);
  Future<void> exportMarkdown({required String notesJson, required String path}) =>
      _bridge.exportMarkdown(notesJson: notesJson, path: path);

  // ============================================================
  // 兼容接口 —— 保持原有 asyncRequest 签名，内部转换为 FRB 调用
  // 用于尚未迁移到新 API 的调用方
  // ============================================================

  /// 兼容旧 Event-Dispatch 调用方式
  /// 新代码应直接使用上面的类型安全方法
  ///
  /// TODO(R10-06): 迁移迁移指南
  /// 以下文件仍在使用 asyncRequest，需逐步迁移到类型安全方法：
  /// - lib/features/knowledge_graph/graph_service.dart (9 处调用)
  /// - lib/features/canvas/canvas_service.dart (13 处调用)
  /// - lib/features/flashcard/flashcard_service.dart (11 处调用)
  /// - lib/features/sync/p2p/p2p_service.dart (6 处调用)
  /// - lib/features/workflow/git_service.dart (7 处调用)
  /// - lib/features/workflow/file_watcher_service.dart (1 处调用)
  /// - lib/features/workflow/external_editor_sync.dart (3 处调用)
  /// - lib/features/search/search_service.dart (2 处调用)
  /// - lib/features/knowledge/knowledge_service.dart (2 处调用)
  /// - lib/features/knowledge/knowledge_map/knowledge_map_service.dart (4 处调用)
  /// - lib/features/knowledge/learning_stats/learning_stats_service.dart (4 处调用)
  /// - lib/features/knowledge/dashboard/dashboard_service.dart (3 处调用)
  /// 迁移方法：将 asyncRequest('XxxEvent.Yyy', payload: ...) 替换为
  /// 对应的类型安全方法如 dispatch.createNote(title: ..., content: ..., folderId: ...)
  @Deprecated('Use type-safe methods instead of Event-Dispatch strings')
  Future<FlowyResult> asyncRequest(String event, {Uint8List? payload}) async {
    try {
      final result = await _dispatchLegacy(event, payload);
      return FlowyResult.success(result);
    } catch (e) {
      return FlowyResult.failure(FlowyInternalError(message: e.toString()));
    }
  }

  /// 旧事件路由兼容层 —— 将字符串事件名映射到 FRB 函数调用
  /// TODO(R10-06): 迁移所有 asyncRequest 调用方到类型安全方法后移除此方法
  Future<Uint8List> _dispatchLegacy(String event, Uint8List? payload) async {
    log('Warning: asyncRequest legacy path used for event: $event. Migrate to type-safe method.', name: 'Dispatch');
    final payloadMap = payload != null
        ? jsonDecode(utf8.decode(payload)) as Map<String, dynamic>
        : <String, dynamic>{};

    // 笔记事件
    if (event == 'NoteEvent.CreateNote') {
      final result = await createNote(
        title: payloadMap['title'] as String,
        content: payloadMap['content'] as String,
        folderId: payloadMap['folder_id'] as String,
      );
      return utf8.encode(jsonEncode(result));
    }
    if (event == 'NoteEvent.GetNote') {
      final result = await getNote(payloadMap['id'] as String);
      return utf8.encode(jsonEncode(result));
    }
    if (event == 'NoteEvent.UpdateNote') {
      final result = await updateNote(
        id: payloadMap['id'] as String,
        title: payloadMap['title'] as String,
        content: payloadMap['content'] as String,
      );
      return utf8.encode(jsonEncode(result));
    }
    if (event == 'NoteEvent.DeleteNote') {
      await deleteNote(payloadMap['id'] as String);
      return Uint8List(0);
    }
    if (event == 'NoteEvent.ListNotes') {
      final result = await listNotes(payloadMap['folder_id'] as String);
      return utf8.encode(jsonEncode(result));
    }

    // 文件夹事件
    if (event == 'FolderEvent.CreateFolder') {
      final result = await createFolder(
        name: payloadMap['name'] as String,
        parentId: payloadMap['parent_id'] as String?,
      );
      return utf8.encode(jsonEncode(result));
    }
    if (event == 'FolderEvent.ListFolders') {
      final result = await listFolders(parentId: payloadMap['parent_id'] as String?);
      return utf8.encode(jsonEncode(result));
    }
    if (event == 'FolderEvent.DeleteFolder') {
      await deleteFolder(payloadMap['id'] as String);
      return Uint8List(0);
    }

    // 标签事件
    if (event == 'TagEvent.CreateTag') {
      final result = await createTag(payloadMap['name'] as String);
      return utf8.encode(jsonEncode(result));
    }
    if (event == 'TagEvent.ListTags') {
      final result = await listTags();
      return utf8.encode(jsonEncode(result));
    }
    if (event == 'TagEvent.DeleteTag') {
      await deleteTag(payloadMap['id'] as String);
      return Uint8List(0);
    }

    // 搜索事件
    if (event == 'SearchEvent.Search') {
      final result = await searchNotes(
        query: payloadMap['query'] as String,
        limit: payloadMap['limit'] as int?,
        offset: payloadMap['offset'] as int?,
      );
      return utf8.encode(jsonEncode(result));
    }

    // 系统事件
    if (event == 'SystemEvent.GetVersion') {
      final version = await _bridge.negotiateVersion();
      return utf8.encode(jsonEncode({
        'api_version': version?.apiVersion ?? 0,
        'rust_version': version?.rustVersion ?? 'unknown',
        'compatible_min': version?.compatibleMin ?? 1,
        'features': version?.features ?? [],
      }));
    }
    if (event == 'SystemEvent.HealthCheck') {
      final health = await _bridge.healthCheck();
      return utf8.encode(jsonEncode({
        'status': 'ok',
        'engines': health ?? {},
      }));
    }

    throw UnimplementedError('Event not mapped to FRB: $event');
  }
}

/// 兼容类型 —— 保持原有 FlowyResult 接口
class FlowyResult {
  final Uint8List? data;
  final FlowyInternalError? error;

  FlowyResult.success(this.data) : error = null;
  FlowyResult.failure(this.error) : data = null;

  T when<T>({
    required T Function(Uint8List data) success,
    required T Function(FlowyInternalError error) failure,
  }) {
    if (error != null) return failure(error!);
    return success(data ?? Uint8List(0));
  }
}

class FlowyInternalError {
  final String message;
  FlowyInternalError({required this.message});
}