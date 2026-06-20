/// FFIBridge - 基于 flutter_rust_bridge v2 的类型安全 FFI 桥接层
///
/// ## 替换说明
/// 原实现：自研 DynamicLibrary + NativeFunction 绑定方案（~238 行 Dart + ~1840 行 Rust），
/// 采用 Event-Dispatch 架构、JSON 序列化通信、手动 malloc/free 内存管理。
///
/// 替换为：flutter_rust_bridge v2 自动生成类型安全绑定
///
/// ## FRB 优势
/// - **类型安全**：自动生成 Dart 绑定，消除双端 JSON schema 不一致
/// - **内存安全**：消除手写 malloc/free 和 catch_unwind
/// - **性能**：SSE 编解码器比 JSON 序列化快数倍
/// - **开发效率**：新增 Rust 函数只需 `flutter_rust_bridge_codegen generate`
/// - **高级特性**：支持 async/await、Stream、Result 类型
///
/// 来源: https://pub.dev/packages/flutter_rust_bridge
/// 版本: v2.12.0
/// Flutter Favorite: ✅

import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

// ============================================================
// FRB 生成的绑定导入
// flutter_rust_bridge_codegen generate 会自动生成此文件
// 包含所有 Rust frb_api.rs 中导出函数的 Dart 绑定
//
// TODO(codegen): 运行 flutter_rust_bridge_codegen generate 后，
//   取消下方注释并删除 flutter_rust_bridge 的通用导入：
//   import 'package:devnote_ffi/src/rust/api/frb_api.dart' as rust_api;
// ============================================================

/// FFI 协议版本 —— 与 Rust 端 frb_api.rs 中 FFI_API_VERSION 常量严格一致
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

  bool get isCompatible => apiVersion >= compatibleMin && kFFIApiVersion >= compatibleMin;

  /// 从 FRB 生成的 VersionInfo 创建
  factory FfiVersionInfo.fromFrb(dynamic frbVersion) {
    return FfiVersionInfo(
      apiVersion: frbVersion.apiVersion as int,
      rustVersion: frbVersion.rustVersion as String,
      compatibleMin: frbVersion.compatibleMin as int,
      features: List<String>.from(frbVersion.features as List),
    );
  }
}

/// 语音转文字结果（FRB 映射类型）
///
/// 对应 Rust 端 `TranscribeResultFfi` 结构体，
/// FRB codegen 运行后由生成代码替换。
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

/// 转写片段（FRB 映射类型）
///
/// 对应 Rust 端 `TranscriptSegmentFfi` 结构体。
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

/// FFI 桥接层 - Flutter 与 Rust 核心通信
/// 
/// 借鉴: AppFlowy FFI 桥接模式 (https://github.com/AppFlowy-IO/AppFlowy)
/// - 类型安全的 FFI 调用
/// - 异步运行时支持
/// 
/// 复用: flutter_rust_bridge v2 (https://github.com/fzyzcjy/flutter_rust_bridge)
/// - 自动生成 Dart-Rust 绑定
/// - SSE 序列化 (零拷贝)
/// - Stream 支持
class FFIBridge {
  FFIBridge();

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  // FRB 生成的 API 实例
  // flutter_rust_bridge_codegen generate 后会创建对应的 Dart 类
  // 实际类型为 DevNoteApi（由 FRB 代码生成器生成），此处使用 dynamic
  // 直到 codegen 运行后才能确定具体类型
  dynamic _frbApi;

  /// 初始化 FRB 桥接
  ///
  /// FRB v2 初始化模式：
  /// 1. 构造 FRB 生成的 API 实例（如 DevNoteApi()）
  /// 2. 调用 Rust 端 initEngines() 初始化引擎
  ///
  /// TODO(codegen): 运行 flutter_rust_bridge_codegen generate 后，
  ///   将下方替换为：
  ///   final api = DevNoteApi();
  ///   await api.initEngines();
  ///   _frbApi = api;
  /// 初始化 FRB 桥接
  ///
  /// 注意：当前项目尚未运行 `flutter_rust_bridge_codegen generate` 生成
  /// `DevNoteApi`/`RustApi`，所以 init() 只能做"符号存在性"检查。
  /// 修复：避免使用不存在的 `RustApi()` 构造，改为通过 `DynamicLibrary.open`
  /// 检查 native 库是否存在；不可用时抛错由 main() 捕获并 graceful degradation。
  Future<void> init() async {
    try {
      // 尝试加载 native 库 —— 不存在时（如未运行 codegen）init 失败
      try {
        // ignore: avoid_dynamic_calls
        final dylib = _openNativeLibrary();
        if (dylib == null) {
          throw StateError('Native library not found');
        }
      } catch (e) {
        _isAvailable = false;
        _frbApi = null;
        rethrow;
      }
      _isAvailable = true;
    } catch (e) {
      _isAvailable = false;
      _frbApi = null;
      rethrow;
    }
  }

  /// 子类可重写此方法提供自定义的 DynamicLibrary 加载策略
  // ignore: avoid_dynamic_calls
  DynamicLibrary? _openNativeLibrary() {
    // 修复(P2): 原实现仅尝试 'libdevnote_ffi.so'，不区分 macOS（.dylib）、
    // Windows（.dll）、iOS（DynamicLibrary.process()），跨平台运行时 FFI 必然失败。
    // 现按平台加载正确的动态库文件名。
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('libdevnote_ffi.so');
      }
      if (Platform.isIOS) {
        // iOS: 静态链接，通过 process 查找符号
        return DynamicLibrary.process();
      }
      if (Platform.isMacOS) {
        return DynamicLibrary.open('libdevnote_ffi.dylib');
      }
      if (Platform.isLinux) {
        return DynamicLibrary.open('libdevnote_ffi.so');
      }
      if (Platform.isWindows) {
        return DynamicLibrary.open('devnote_ffi.dll');
      }
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    } catch (_) {
      return null;
    }
  }

  /// 版本协商 —— 替代原 SystemEvent.GetVersion 事件
  Future<FfiVersionInfo?> negotiateVersion() async {
    if (!_isAvailable || _frbApi == null) return null;
    try {
      // 直接调用 Rust 函数，无需 JSON 序列化
      final version = await _frbApi.getVersion();
      return FfiVersionInfo.fromFrb(version);
    } catch (e) {
      log('FRB negotiateVersion failed: $e', name: 'FFIBridge');
      return null;
    }
  }

  /// 健康检查 —— 替代原 SystemEvent.HealthCheck 事件
  Future<Map<String, bool>?> healthCheck() async {
    if (!_isAvailable || _frbApi == null) return null;
    try {
      final health = await _frbApi.healthCheck();
      return Map<String, bool>.from(health.engines as Map);
    } catch (e) {
      log('FRB healthCheck failed: $e', name: 'FFIBridge');
      return null;
    }
  }

  // ============================================================
  // 笔记 API —— 替代原 NoteEvent.* 事件
  // 每个方法直接调用 Rust 函数，无需 Event-Dispatch 路由
  // ============================================================

  Future<Map<String, dynamic>> createNote({
    required String title,
    required String content,
    required String folderId,
  }) async {
    _checkAvailable();
    final result = await _frbApi.createNote(title: title, content: content, folderId: folderId);
    return _toMap(result);
  }

  Future<Map<String, dynamic>?> getNote(String id) async {
    _checkAvailable();
    final result = await _frbApi.getNote(id: id);
    return result != null ? _toMap(result) : null;
  }

  Future<Map<String, dynamic>> updateNote({
    required String id,
    required String title,
    required String content,
  }) async {
    _checkAvailable();
    final result = await _frbApi.updateNote(id: id, title: title, content: content);
    return _toMap(result);
  }

  Future<void> deleteNote(String id) async {
    _checkAvailable();
    await _frbApi.deleteNote(id: id);
  }

  Future<List<Map<String, dynamic>>> listNotes(String folderId) async {
    _checkAvailable();
    final result = await _frbApi.listNotes(folderId: folderId);
    return (result as List).map((e) => _toMap(e)).toList();
  }

  // ============================================================
  // 文件夹 API —— 替代原 FolderEvent.* 事件
  // ============================================================

  Future<Map<String, dynamic>> createFolder({
    required String name,
    String? parentId,
  }) async {
    _checkAvailable();
    final result = await _frbApi.createFolder(name: name, parentId: parentId);
    return _toMap(result);
  }

  Future<List<Map<String, dynamic>>> listFolders({String? parentId}) async {
    _checkAvailable();
    final result = await _frbApi.listFolders(parentId: parentId);
    return (result as List).map((e) => _toMap(e)).toList();
  }

  Future<void> deleteFolder(String id) async {
    _checkAvailable();
    await _frbApi.deleteFolder(id: id);
  }

  // ============================================================
  // 标签 API —— 替代原 TagEvent.* 事件
  // ============================================================

  Future<Map<String, dynamic>> createTag(String name) async {
    _checkAvailable();
    final result = await _frbApi.createTag(name: name);
    return _toMap(result);
  }

  Future<List<Map<String, dynamic>>> listTags() async {
    _checkAvailable();
    final result = await _frbApi.listTags();
    return (result as List).map((e) => _toMap(e)).toList();
  }

  Future<void> deleteTag(String id) async {
    _checkAvailable();
    await _frbApi.deleteTag(id: id);
  }

  // ============================================================
  // 编辑器 API —— 替代原 EditorEvent.* 事件
  // ============================================================

  Future<Map<String, dynamic>> insertBlock({
    required String noteId,
    required String blockType,
    required String content,
    int? position,
  }) async {
    _checkAvailable();
    final result = await _frbApi.insertBlock(
      noteId: noteId, blockType: blockType, content: content, position: position,
    );
    return _toMap(result);
  }

  Future<void> updateBlock({required String id, required String content}) async {
    _checkAvailable();
    await _frbApi.updateBlock(id: id, content: content);
  }

  Future<void> deleteBlock(String id) async {
    _checkAvailable();
    await _frbApi.deleteBlock(id: id);
  }

  Future<List<Map<String, dynamic>>> getBlocks(String noteId) async {
    _checkAvailable();
    final result = await _frbApi.getBlocks(noteId: noteId);
    return (result as List).map((e) => _toMap(e)).toList();
  }

  // ============================================================
  // 搜索 API —— 替代原 SearchEvent.* 事件
  // ============================================================

  Future<List<Map<String, dynamic>>> searchNotes({
    required String query,
    int? limit,
    int? offset,
  }) async {
    _checkAvailable();
    final result = await _frbApi.searchNotes(query: query, limit: limit, offset: offset);
    return (result as List).map((e) => _toMap(e)).toList();
  }

  // ============================================================
  // 加密 API —— 替代原 CryptoEvent.* 事件
  // ============================================================

  Future<String> encrypt({required String plaintextBase64, required String keyBase64}) async {
    _checkAvailable();
    return await _frbApi.encrypt(plaintextBase64: plaintextBase64, keyBase64: keyBase64);
  }

  Future<String> decrypt({required String ciphertextBase64, required String keyBase64}) async {
    _checkAvailable();
    return await _frbApi.decrypt(ciphertextBase64: ciphertextBase64, keyBase64: keyBase64);
  }

  Future<String> deriveKey({required String password, required String saltBase64}) async {
    _checkAvailable();
    return await _frbApi.deriveKey(password: password, saltBase64: saltBase64);
  }

  // ============================================================
  // 同步 API —— 替代原 SyncEvent.* 事件
  // ============================================================

  Future<void> pushChanges() async {
    _checkAvailable();
    await _frbApi.pushChanges();
  }

  Future<void> pullChanges() async {
    _checkAvailable();
    await _frbApi.pullChanges();
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    _checkAvailable();
    final result = await _frbApi.getSyncStatus();
    return _toMap(result);
  }

  // ============================================================
  // Canvas API —— 替代原 CanvasEvent.* 事件
  // ============================================================

  Future<void> canvasAddNode({required String canvasId, required String nodeJson}) async {
    _checkAvailable();
    await _frbApi.canvasAddNode(canvasId: canvasId, nodeJson: nodeJson);
  }

  Future<void> canvasRemoveNode({required String canvasId, required String nodeId}) async {
    _checkAvailable();
    await _frbApi.canvasRemoveNode(canvasId: canvasId, nodeId: nodeId);
  }

  Future<void> canvasAutoLayout({required String canvasId, required String layoutType}) async {
    _checkAvailable();
    await _frbApi.canvasAutoLayout(canvasId: canvasId, layoutType: layoutType);
  }

  Future<String> canvasCreateCanvas() async {
    _checkAvailable();
    return await _frbApi.canvasCreateCanvas();
  }

  Future<Map<String, dynamic>> canvasGetCanvas({required String canvasId}) async {
    _checkAvailable();
    final result = await _frbApi.canvasGetCanvas(canvasId: canvasId);
    return _toMap(result);
  }

  Future<void> canvasMoveNode({required String canvasId, required String nodeId, required double x, required double y}) async {
    _checkAvailable();
    await _frbApi.canvasMoveNode(canvasId: canvasId, nodeId: nodeId, x: x, y: y);
  }

  Future<void> canvasResizeNode({required String canvasId, required String nodeId, required double width, required double height}) async {
    _checkAvailable();
    await _frbApi.canvasResizeNode(canvasId: canvasId, nodeId: nodeId, width: width, height: height);
  }

  Future<void> canvasAddEdge({required String canvasId, required String edgeJson}) async {
    _checkAvailable();
    await _frbApi.canvasAddEdge(canvasId: canvasId, edgeJson: edgeJson);
  }

  Future<void> canvasRemoveEdge({required String canvasId, required String edgeId}) async {
    _checkAvailable();
    await _frbApi.canvasRemoveEdge(canvasId: canvasId, edgeId: edgeId);
  }

  Future<void> canvasSaveCanvas({required String canvasId, required String path}) async {
    _checkAvailable();
    await _frbApi.canvasSaveCanvas(canvasId: canvasId, path: path);
  }

  Future<String> canvasLoadCanvas({required String path}) async {
    _checkAvailable();
    return await _frbApi.canvasLoadCanvas(path: path);
  }

  Future<void> canvasStartCollaboration({required String canvasId, required String sessionId}) async {
    _checkAvailable();
    await _frbApi.canvasStartCollaboration(canvasId: canvasId, sessionId: sessionId);
  }

  Future<Map<String, dynamic>> canvasJoinCollaboration({required String sessionId}) async {
    _checkAvailable();
    final result = await _frbApi.canvasJoinCollaboration(sessionId: sessionId);
    return _toMap(result);
  }

  Future<void> canvasBroadcastChange({required String changeJson}) async {
    _checkAvailable();
    await _frbApi.canvasBroadcastChange(changeJson: changeJson);
  }

  Future<void> canvasEndCollaboration({required String sessionId}) async {
    _checkAvailable();
    await _frbApi.canvasEndCollaboration(sessionId: sessionId);
  }

  // ============================================================
  // 数据库 API —— 替代原 DatabaseEvent.* 事件
  // ============================================================

  Future<String> createDatabase(String name) async {
    _checkAvailable();
    return await _frbApi.createDatabase(name: name);
  }

  Future<String> evaluateFormula({
    required String formula,
    required String rowValues,
    required String allRows,
  }) async {
    _checkAvailable();
    return await _frbApi.evaluateFormula(formula: formula, rowValues: rowValues, allRows: allRows);
  }

  // ============================================================
  // 图谱 API —— 替代原 GraphEvent.* 事件
  // ============================================================

  Future<String> calculateCentrality() async {
    _checkAvailable();
    return await _frbApi.calculateCentrality();
  }

  Future<String> detectClusters() async {
    _checkAvailable();
    return await _frbApi.detectClusters();
  }

  Future<String> getGraph() async {
    _checkAvailable();
    return await _frbApi.getGraph();
  }

  Future<String> getNodeDetails({required String nodeId}) async {
    _checkAvailable();
    return await _frbApi.getNodeDetails(nodeId: nodeId);
  }

  Future<String> getRelatedNodes({required String nodeId}) async {
    _checkAvailable();
    return await _frbApi.getRelatedNodes(nodeId: nodeId);
  }

  Future<String> searchNodes({required String query}) async {
    _checkAvailable();
    return await _frbApi.searchNodes(query: query);
  }

  Future<String> getGraphStats() async {
    _checkAvailable();
    return await _frbApi.getGraphStats();
  }

  Future<String> getShortestPath({required String fromId, required String toId}) async {
    _checkAvailable();
    return await _frbApi.getShortestPath(fromId: fromId, toId: toId);
  }

  Future<String> getNeighbors({required String nodeId, required int depth}) async {
    _checkAvailable();
    return await _frbApi.getNeighbors(nodeId: nodeId, depth: depth);
  }

  // ============================================================
  // 闪卡 API —— 替代原 FlashcardEvent.* 事件
  // ============================================================

  Future<String> createDeck({required String name, required String description}) async {
    _checkAvailable();
    return await _frbApi.createDeck(name: name, description: description);
  }

  Future<String> reviewFlashcard({required String flashcardId, required int quality}) async {
    _checkAvailable();
    return await _frbApi.reviewFlashcard(flashcardId: flashcardId, quality: quality);
  }

  Future<String> getDueCards({required String deckId, int? limit}) async {
    _checkAvailable();
    return await _frbApi.getDueCards(deckId: deckId, limit: limit);
  }

  Future<void> deleteDeck({required String deckId}) async {
    _checkAvailable();
    await _frbApi.deleteDeck(deckId: deckId);
  }

  Future<List<Map<String, dynamic>>> listDecks() async {
    _checkAvailable();
    final result = await _frbApi.listDecks();
    return (result as List).map((e) => _toMap(e)).toList();
  }

  Future<Map<String, dynamic>> createFlashcard({
    required String deckId,
    required String cardType,
    required String front,
    required String back,
    String? noteId,
  }) async {
    _checkAvailable();
    final result = await _frbApi.createFlashcard(
      deckId: deckId, cardType: cardType, front: front, back: back, noteId: noteId,
    );
    return _toMap(result);
  }

  Future<Map<String, dynamic>> updateFlashcard({required String id, required String front, required String back}) async {
    _checkAvailable();
    final result = await _frbApi.updateFlashcard(id: id, front: front, back: back);
    return _toMap(result);
  }

  Future<void> deleteFlashcard({required String flashcardId}) async {
    _checkAvailable();
    await _frbApi.deleteFlashcard(flashcardId: flashcardId);
  }

  Future<Map<String, dynamic>> getReviewStats({required String deckId}) async {
    _checkAvailable();
    final result = await _frbApi.getReviewStats(deckId: deckId);
    return _toMap(result);
  }

  Future<List<Map<String, dynamic>>> batchGenerateFromNote({required String noteId}) async {
    _checkAvailable();
    final result = await _frbApi.batchGenerateFromNote(noteId: noteId);
    return (result as List).map((e) => _toMap(e)).toList();
  }

  // ============================================================
  // CRDT API —— 替代原 CRDTEvent.* 事件
  // ============================================================

  Future<Map<String, dynamic>> crdtMerge({
    required String docId,
    required String deviceId,
    required String remoteOpsJson,
  }) async {
    _checkAvailable();
    final result = await _frbApi.crdtMerge(docId: docId, deviceId: deviceId, remoteOpsJson: remoteOpsJson);
    return _toMap(result);
  }

  // ============================================================
  // Git API —— 替代原 GitEvent.* 事件
  // ============================================================

  Future<String> gitInit({required String repoPath}) async {
    _checkAvailable();
    return await _frbApi.gitInit(repoPath: repoPath);
  }

  Future<String> gitStatus({required String repoPath}) async {
    _checkAvailable();
    return await _frbApi.gitStatus(repoPath: repoPath);
  }

  Future<String> gitCommit({required String repoPath, required String message}) async {
    _checkAvailable();
    return await _frbApi.gitCommit(repoPath: repoPath, message: message);
  }

  Future<String> gitLog({required String repoPath, required int limit}) async {
    _checkAvailable();
    return await _frbApi.gitLog(repoPath: repoPath, limit: limit);
  }

  Future<String> gitBranch({required String repoPath}) async {
    _checkAvailable();
    return await _frbApi.gitBranch(repoPath: repoPath);
  }

  Future<String> gitCheckout({required String repoPath, required String branch}) async {
    _checkAvailable();
    return await _frbApi.gitCheckout(repoPath: repoPath, branch: branch);
  }

  Future<String> gitDiff({required String repoPath}) async {
    _checkAvailable();
    return await _frbApi.gitDiff(repoPath: repoPath);
  }

  // ============================================================
  // P2P API —— 替代原 P2PEvent.* 事件
  // ============================================================

  Future<void> p2pStart({required String peerId}) async {
    _checkAvailable();
    await _frbApi.p2pStart(peerId: peerId);
  }

  Future<void> p2pStop() async {
    _checkAvailable();
    await _frbApi.p2pStop();
  }

  Future<String> p2pGetPeers() async {
    _checkAvailable();
    return await _frbApi.p2pGetPeers();
  }

  Future<void> p2pConnectPeer({required String peerId, required String multiaddr}) async {
    _checkAvailable();
    await _frbApi.p2pConnectPeer(peerId: peerId, multiaddr: multiaddr);
  }

  Future<void> p2pDisconnectPeer({required String peerId}) async {
    _checkAvailable();
    await _frbApi.p2pDisconnectPeer(peerId: peerId);
  }

  Future<String> p2pGetStatus() async {
    _checkAvailable();
    return await _frbApi.p2pGetStatus();
  }

  // ============================================================
  // Knowledge API —— 替代原 KnowledgeEvent.* 事件
  // ============================================================

  Future<String> getKnowledgeMap({required String noteId}) async {
    _checkAvailable();
    return await _frbApi.getKnowledgeMap(noteId: noteId);
  }

  Future<String> getLearningStats({required String noteId}) async {
    _checkAvailable();
    return await _frbApi.getLearningStats(noteId: noteId);
  }

  Future<String> getDashboard() async {
    _checkAvailable();
    return await _frbApi.getDashboard();
  }

  // ============================================================
  // 格式 API —— 替代原 FormatEvent.* 事件
  // ============================================================

  Future<String> importMarkdown(String path) async {
    _checkAvailable();
    return await _frbApi.importMarkdown(path: path);
  }

  Future<void> exportMarkdown({required String notesJson, required String path}) async {
    _checkAvailable();
    await _frbApi.exportMarkdown(notesJson: notesJson, path: path);
  }

  // ============================================================
  // 语音转文字 API —— Speech-to-Text
  // ============================================================

  /// 语音转文字 —— 调用 Rust 端 whisper-rs 进行本地转写
  ///
  /// [audioBase64] 音频文件的 base64 编码
  /// [lang] 语言代码（如 'zh', 'en', 'ja'）
  ///
  /// Rust 端未集成 whisper-rs 时返回 Err，调用方应降级为平台原生 API。
  Future<TranscribeResultFfi> transcribeAudio({
    required String audioBase64,
    required String lang,
  }) async {
    _checkAvailable();
    // ignore: avoid_dynamic_calls
    final result = await _frbApi.transcribeAudio(audioBase64: audioBase64, lang: lang);
    // ignore: avoid_dynamic_calls
    return TranscribeResultFfi(
      text: result.text as String,
      durationMs: result.durationMs as int,
      segments: (result.segments as List)
          // ignore: avoid_dynamic_calls
          .map((s) => TranscriptSegmentFfi(
                text: s.text as String,
                startMs: s.startMs as int,
                endMs: s.endMs as int,
              ))
          .toList(),
    );
  }

  // ============================================================
  // OCR API —— 替代原 OcrEvent.* 事件
  // P0-2: OCR 文字识别 + 图片搜索
  // ============================================================

  /// OCR 识别图片中的文字
  Future<String> ocrRecognizeImage({required String imageBase64}) async {
    _checkAvailable();
    return await _frbApi.ocrRecognizeImage(imageBase64: imageBase64);
  }

  /// OCR 识别并返回结构化结果（含按行分割与置信度）
  Future<Map<String, dynamic>> ocrRecognizeImageDetailed({required String imageBase64}) async {
    _checkAvailable();
    final result = await _frbApi.ocrRecognizeImageDetailed(imageBase64: imageBase64);
    return _toMap(result);
  }

  /// 将 OCR 识别文本纳入笔记的全文搜索索引
  Future<void> indexOcrText({required String noteId, required String ocrText}) async {
    _checkAvailable();
    await _frbApi.indexOcrText(noteId: noteId, ocrText: ocrText);
  }

  // ============================================================
  // 工具方法
  // ============================================================

  void _checkAvailable() {
    if (!_isAvailable || _frbApi == null) {
      throw StateError('FFI bridge not available. Call init() first.');
    }
  }

  /// 将 FRB 生成的 Dart 对象转换为 Map
  /// FRB 生成的类包含 toJson() 方法，可直接序列化
  Map<String, dynamic> _toMap(dynamic obj) {
    if (obj == null) return {};
    if (obj is Map) return Map<String, dynamic>.from(obj);
    // FRB 生成的类有 toJson() 方法
    try {
      if (obj is Function || obj is String || obj is num || obj is bool) {
        return {'value': obj};
      }
      final json = (obj as dynamic).toJson();
      return Map<String, dynamic>.from(json as Map);
    } catch (e) {
      log('FRB _toMap failed: $e', name: 'FFIBridge');
      return {'value': obj.toString()};
    }
  }

  void dispose() {
    _frbApi = null;
    _isAvailable = false;
  }
}