/// Dispatch 层 —— 基于 flutter_rust_bridge 的直接函数调用
///
/// ## 替换说明
/// 原实现：Event-Dispatch 模式，通过字符串事件名路由到 Rust handler
/// 替换为：FRB 直接函数调用，类型安全，无需字符串路由
///
/// ## 核心变更
/// 1. 消除 Event-Dispatch 字符串路由（"NoteEvent.CreateNote" → createNote()）
/// 2. 消除 JSON 序列化/反序列化（FRB 使用 SSE 编解码器）
/// 3. 消除 asyncRequest 的回调模式（FRB 直接返回 Future）
///
/// 来源: https://pub.dev/packages/flutter_rust_bridge
/// 借鉴 AppFlowy 的 Dispatch 模式（已升级为 FRB 直接调用）

import 'package:devnote/core/bridge/ffi_bridge.dart';
// 修复: 不要在本文件定义 getIt,直接使用 injection.dart 中的实例
// 旧代码在 dispatch.dart 顶层声明 getIt,与 injection.dart 的 getIt 冲突,导致
// 多个 service 文件 ambiguous import
// ignore: unused_import
import 'package:devnote/core/di/injection.dart' as di;
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/persistence/models/block_model.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';

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
  // 修复: 显式使用 injection.dart 中的 getIt
  FFIBridge get _bridge => di.getIt<FFIBridge>();

  // ============================================================
  // 笔记操作 —— 替代原 NoteEvent.* 事件路由
  // ============================================================

  Future<NoteModel> createNote({
    required String title,
    required String content,
    required String folderId,
  }) async {
    final map = await _bridge.createNote(title: title, content: content, folderId: folderId);
    return NoteModel.fromJson(map);
  }

  Future<NoteModel?> getNote(String id) async {
    final map = await _bridge.getNote(id);
    if (map == null) return null;
    return NoteModel.fromJson(map);
  }

  Future<NoteModel> updateNote({
    required String id,
    required String title,
    required String content,
  }) async {
    final map = await _bridge.updateNote(id: id, title: title, content: content);
    return NoteModel.fromJson(map);
  }

  Future<void> deleteNote(String id) => _bridge.deleteNote(id);

  Future<List<NoteModel>> listNotes(String folderId) async {
    final list = await _bridge.listNotes(folderId);
    return list.map((map) => NoteModel.fromJson(map)).toList();
  }

  // ============================================================
  // 文件夹操作 —— 替代原 FolderEvent.* 事件路由
  // ============================================================

  Future<FolderModel> createFolder({
    required String name,
    String? parentId,
  }) async {
    final map = await _bridge.createFolder(name: name, parentId: parentId);
    return FolderModel.fromJson(map);
  }

  Future<List<FolderModel>> listFolders({String? parentId}) async {
    final list = await _bridge.listFolders(parentId: parentId);
    return list.map((map) => FolderModel.fromJson(map)).toList();
  }

  Future<void> deleteFolder(String id) => _bridge.deleteFolder(id);

  // ============================================================
  // 标签操作 —— 替代原 TagEvent.* 事件路由
  // ============================================================

  Future<TagModel> createTag(String name) async {
    final map = await _bridge.createTag(name);
    return TagModel.fromJson(map);
  }

  Future<List<TagModel>> listTags() async {
    final list = await _bridge.listTags();
    return list.map((map) => TagModel.fromJson(map)).toList();
  }

  Future<void> deleteTag(String id) => _bridge.deleteTag(id);

  // ============================================================
  // 编辑器操作 —— 替代原 EditorEvent.* 事件路由
  // ============================================================

  Future<BlockModel> insertBlock({
    required String noteId,
    required String blockType,
    required String content,
    int? position,
  }) async {
    final map = await _bridge.insertBlock(
      noteId: noteId, blockType: blockType, content: content, position: position,
    );
    return BlockModel.fromJson(map);
  }

  Future<void> updateBlock({required String id, required String content}) =>
      _bridge.updateBlock(id: id, content: content);

  Future<void> deleteBlock(String id) => _bridge.deleteBlock(id);

  Future<List<BlockModel>> getBlocks(String noteId) async {
    final list = await _bridge.getBlocks(noteId);
    return list.map((map) => BlockModel.fromJson(map)).toList();
  }

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
  // Canvas 扩展操作 —— 替代原 CanvasEvent.* 事件路由
  // ============================================================

  Future<String> canvasCreateCanvas() => _bridge.canvasCreateCanvas();

  Future<Map<String, dynamic>> canvasGetCanvas({required String canvasId}) =>
      _bridge.canvasGetCanvas(canvasId: canvasId);

  Future<void> canvasMoveNode({required String canvasId, required String nodeId, required double x, required double y}) =>
      _bridge.canvasMoveNode(canvasId: canvasId, nodeId: nodeId, x: x, y: y);

  Future<void> canvasResizeNode({required String canvasId, required String nodeId, required double width, required double height}) =>
      _bridge.canvasResizeNode(canvasId: canvasId, nodeId: nodeId, width: width, height: height);

  Future<void> canvasAddEdge({required String canvasId, required String edgeJson}) =>
      _bridge.canvasAddEdge(canvasId: canvasId, edgeJson: edgeJson);

  Future<void> canvasRemoveEdge({required String canvasId, required String edgeId}) =>
      _bridge.canvasRemoveEdge(canvasId: canvasId, edgeId: edgeId);

  Future<void> canvasSaveCanvas({required String canvasId, required String path}) =>
      _bridge.canvasSaveCanvas(canvasId: canvasId, path: path);

  Future<String> canvasLoadCanvas({required String path}) =>
      _bridge.canvasLoadCanvas(path: path);

  Future<void> canvasStartCollaboration({required String canvasId, required String sessionId}) =>
      _bridge.canvasStartCollaboration(canvasId: canvasId, sessionId: sessionId);

  Future<Map<String, dynamic>> canvasJoinCollaboration({required String sessionId}) =>
      _bridge.canvasJoinCollaboration(sessionId: sessionId);

  Future<void> canvasBroadcastChange({required String changeJson}) =>
      _bridge.canvasBroadcastChange(changeJson: changeJson);

  Future<void> canvasEndCollaboration({required String sessionId}) =>
      _bridge.canvasEndCollaboration(sessionId: sessionId);

  // ============================================================
  // 闪卡扩展操作 —— 替代原 FlashcardEvent.* 事件路由
  // ============================================================

  Future<void> deleteDeck({required String deckId}) =>
      _bridge.deleteDeck(deckId: deckId);

  Future<List<Map<String, dynamic>>> listDecks() => _bridge.listDecks();

  Future<Map<String, dynamic>> createFlashcard({
    required String deckId,
    required String cardType,
    required String front,
    required String back,
    String? noteId,
  }) => _bridge.createFlashcard(deckId: deckId, cardType: cardType, front: front, back: back, noteId: noteId);

  Future<Map<String, dynamic>> updateFlashcard({required String id, required String front, required String back}) =>
      _bridge.updateFlashcard(id: id, front: front, back: back);

  Future<void> deleteFlashcard({required String flashcardId}) =>
      _bridge.deleteFlashcard(flashcardId: flashcardId);

  Future<Map<String, dynamic>> getReviewStats({required String deckId}) =>
      _bridge.getReviewStats(deckId: deckId);

  Future<List<Map<String, dynamic>>> batchGenerateFromNote({required String noteId}) =>
      _bridge.batchGenerateFromNote(noteId: noteId);

  // ============================================================
  // 图谱扩展操作 —— 替代原 GraphEvent.* 事件路由
  // ============================================================

  Future<String> getGraph() => _bridge.getGraph();
  Future<String> getNodeDetails({required String nodeId}) => _bridge.getNodeDetails(nodeId: nodeId);
  Future<String> getRelatedNodes({required String nodeId}) => _bridge.getRelatedNodes(nodeId: nodeId);
  Future<String> searchNodes({required String query}) => _bridge.searchNodes(query: query);
  Future<String> getGraphStats() => _bridge.getGraphStats();
  Future<String> getShortestPath({required String fromId, required String toId}) =>
      _bridge.getShortestPath(fromId: fromId, toId: toId);
  Future<String> getNeighbors({required String nodeId, required int depth}) =>
      _bridge.getNeighbors(nodeId: nodeId, depth: depth);

  // ============================================================
  // Git 操作 —— 替代原 GitEvent.* 事件路由
  // ============================================================

  Future<String> gitInit({required String repoPath}) => _bridge.gitInit(repoPath: repoPath);
  Future<String> gitStatus({required String repoPath}) => _bridge.gitStatus(repoPath: repoPath);
  Future<String> gitCommit({required String repoPath, required String message}) =>
      _bridge.gitCommit(repoPath: repoPath, message: message);
  Future<String> gitLog({required String repoPath, required int limit}) =>
      _bridge.gitLog(repoPath: repoPath, limit: limit);
  Future<String> gitBranch({required String repoPath}) => _bridge.gitBranch(repoPath: repoPath);
  Future<String> gitCheckout({required String repoPath, required String branch}) =>
      _bridge.gitCheckout(repoPath: repoPath, branch: branch);
  Future<String> gitDiff({required String repoPath}) => _bridge.gitDiff(repoPath: repoPath);

  // ============================================================
  // P2P 操作 —— 替代原 P2PEvent.* 事件路由
  // ============================================================

  Future<void> p2pStart({required String peerId}) => _bridge.p2pStart(peerId: peerId);
  Future<void> p2pStop() => _bridge.p2pStop();
  Future<String> p2pGetPeers() => _bridge.p2pGetPeers();
  Future<void> p2pConnectPeer({required String peerId, required String multiaddr}) =>
      _bridge.p2pConnectPeer(peerId: peerId, multiaddr: multiaddr);
  Future<void> p2pDisconnectPeer({required String peerId}) =>
      _bridge.p2pDisconnectPeer(peerId: peerId);
  Future<String> p2pGetStatus() => _bridge.p2pGetStatus();

  // ============================================================
  // Knowledge 操作 —— 替代原 KnowledgeEvent.* 事件路由
  // ============================================================

  Future<String> getKnowledgeMap({required String noteId}) => _bridge.getKnowledgeMap(noteId: noteId);
  Future<String> getLearningStats({required String noteId}) => _bridge.getLearningStats(noteId: noteId);
  Future<String> getDashboard() => _bridge.getDashboard();

  // ============================================================
  // 格式操作 —— 替代原 FormatEvent.* 事件路由
  // ============================================================

  Future<String> importMarkdown(String path) => _bridge.importMarkdown(path);
  Future<void> exportMarkdown({required String notesJson, required String path}) =>
      _bridge.exportMarkdown(notesJson: notesJson, path: path);

  /// 释放 Dispatch 层持有的资源
  void dispose() {
    // FRB 模式下 Dispatch 不持有需要显式释放的资源
    // 保留此方法供 DI 容器 disposeAll() 统一调用
  }
}