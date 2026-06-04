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

import 'dart:convert';
import 'dart:typed_data';

// ============================================================
// FRB 生成的绑定导入
// flutter_rust_bridge_codegen generate 会自动生成此文件
// 包含所有 Rust frb_api.rs 中导出函数的 Dart 绑定
// ============================================================
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';

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

/// ============================================================
/// FFIBridge —— 基于 FRB 的新桥接层
///
/// 核心变更：
/// 1. 不再使用 DynamicLibrary + NativeFunction 手动绑定
/// 2. 不再使用 JSON 字符串序列化通信
/// 3. 不再使用 malloc/free 手动内存管理
/// 4. 不再使用 Event-Dispatch 字符串路由
///
/// 替代为：
/// 1. FRB 自动生成的类型安全函数调用
/// 2. SSE 编解码器（比 JSON 快数倍）
/// 3. FRB 自动管理内存生命周期
/// 4. 直接函数调用（createNote, getNote, listNotes 等）
/// ============================================================
class FFIBridge {
  FFIBridge();

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  // FRB 生成的 API 实例
  // flutter_rust_bridge_codegen generate 后会创建对应的 Dart 类
  // 这里使用动态类型，实际类型由 FRB 代码生成器生成
  dynamic _frbApi;

  /// 初始化 FRB 桥接
  ///
  /// FRB 自动处理：
  /// - 加载 native 库（跨平台路径适配）
  /// - 初始化 wasmtime 运行时
  /// - 建立 SSE 通信通道
  Future<void> init() async {
    try {
      // FRB 初始化 —— 替代原 DynamicLibrary.open + lookupFunction
      // FRB 自动处理跨平台库路径适配
      final api = await FlutterRustBridge.init();
      _frbApi = api;

      // 调用 Rust 端 initEngines() —— 替代原 devnote_init + register_all_handlers
      await _frbApi.initEngines();

      _isAvailable = true;
    } catch (e) {
      _isAvailable = false;
      _frbApi = null;
      rethrow;
    }
  }

  /// 版本协商 —— 替代原 SystemEvent.GetVersion 事件
  Future<FfiVersionInfo?> negotiateVersion() async {
    if (!_isAvailable || _frbApi == null) return null;
    try {
      // 直接调用 Rust 函数，无需 JSON 序列化
      final version = await _frbApi.getVersion();
      return FfiVersionInfo.fromFrb(version);
    } catch (_) {
      return null;
    }
  }

  /// 健康检查 —— 替代原 SystemEvent.HealthCheck 事件
  Future<Map<String, bool>?> healthCheck() async {
    if (!_isAvailable || _frbApi == null) return null;
    try {
      final health = await _frbApi.healthCheck();
      return Map<String, bool>.from(health.engines as Map);
    } catch (_) {
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
      final json = (obj as dynamic).toJson();
      return Map<String, dynamic>.from(json as Map);
    } catch (_) {
      return {'value': obj.toString()};
    }
  }

  void dispose() {
    _frbApi = null;
    _isAvailable = false;
  }
}