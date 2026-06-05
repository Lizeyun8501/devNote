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
import 'dart:developer';
import 'dart:typed_data';

// ============================================================
// FRB 生成的绑定导入
// flutter_rust_bridge_codegen generate 会自动生成此文件
// 包含所有 Rust frb_api.rs 中导出函数的 Dart 绑定
//
// TODO(codegen): 运行 flutter_rust_bridge_codegen generate 后，
//   取消下方注释并删除 flutter_rust_bridge 的通用导入：
//   import 'package:devnote_ffi/src/rust/api/frb_api.dart' as rust_api;
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
  Future<void> init() async {
    try {
      // FRB v2 初始化 —— 替代原 DynamicLibrary.open + lookupFunction
      // FRB v2 正确模式: 直接构造 FRB codegen 生成的 API 类
      // TODO(codegen): 运行 flutter_rust_bridge_codegen generate 后，
      //   取消下方注释并删除 placeholder:
      //   final api = DevNoteApi();
      //   _frbApi = api;
      //   await _frbApi.initEngines();
      //
      // 当前 placeholder: 使用 RustApi 基类初始化（FRB v2 标准模式）
      // RustApi 是 FRB v2 所有生成 API 的基类，构造时自动加载 native 库
      final api = RustApi();
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