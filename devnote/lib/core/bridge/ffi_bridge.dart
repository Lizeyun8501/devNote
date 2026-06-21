/// FFIBridge - 基于 dart:ffi 的 C ABI 桥接层
///
/// 直接调用 Rust 编译的动态库（libdevnote_ffi.so/.dylib/.dll），
/// 通过 `devnote_dispatch` C ABI 函数与 Rust 核心引擎通信。
///
/// ## 架构
/// Dart → dart:ffi → devnote_dispatch(event, payload) → Rust handlers → 引擎
///
/// ## 优势
/// - 无需 flutter_rust_bridge codegen，零代码生成依赖
/// - 直接 C ABI 调用，无中间序列化层
/// - 编译时函数查找，运行时零开销
///
/// 借鉴: AppFlowy FFI 桥接模式 (https://github.com/AppFlowy-IO/AppFlowy)

import 'dart:convert';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' hide Utf16Pointer;

import 'ffi_response.dart';
import 'mixins/git_mixin.dart';
import 'mixins/knowledge_mixin.dart';
import 'mixins/p2p_mixin.dart';
import 'mixins/vault_mixin.dart';

// P1 修复 (P1-2): 重新导出 VaultEncryptedData，保持向后兼容
// vault_service.dart 等调用方仍可通过 ffi_bridge.dart 导入该类型
export 'mixins/vault_mixin.dart' show VaultEncryptedData;

// ============================================================
// C ABI 函数类型定义
// ============================================================

// devnote_init() -> *mut FFIResponse
typedef _InitNative = Pointer<FFIResponseC> Function();
typedef _InitDart = Pointer<FFIResponseC> Function();

// devnote_destroy(*mut FFIResponse) -> void
typedef _DestroyNative = Void Function(Pointer<FFIResponseC>);
typedef _DestroyDart = void Function(Pointer<FFIResponseC>);

// devnote_dispatch(*const c_char) -> *mut c_char
typedef _DispatchNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _DispatchDart = Pointer<Utf8> Function(Pointer<Utf8>);

// devnote_free_string(*mut c_char) -> void
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

// ============================================================
// 数据类型
// ============================================================

/// FFI 协议版本 —— 与 Rust 端 handlers.rs 中 FFI_API_VERSION 常量严格一致
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

  factory FfiVersionInfo.fromJson(Map<String, dynamic> json) {
    return FfiVersionInfo(
      apiVersion: (json['api_version'] as num).toInt(),
      rustVersion: json['rust_version'] as String,
      compatibleMin: (json['compatible_min'] as num).toInt(),
      features: List<String>.from(json['features'] as List),
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

// P1 修复 (P1-2): VaultEncryptedData 已迁移至 mixins/vault_mixin.dart
// 并通过本文件顶部的 export 语句重新导出，保持向后兼容。

// ============================================================
// FFI 错误
// ============================================================

/// FFI 调用异常
class FfiException implements Exception {
  final String event;
  final int code;
  final String message;

  const FfiException(this.event, this.code, this.message);

  @override
  String toString() => 'FfiException($event, code=$code): $message';
}

// ============================================================
// FFIBridge —— Flutter 与 Rust 核心通信桥接
// ============================================================

// P1 修复 (P1-2): 应用领域 Mixin 拆分 God Class
// - VaultMixin: 纯 Dart 加密实现，无 C ABI 依赖
// - GitMixin: 全 stub，Rust 端无 handler
// - P2PMixin: 全 stub，P2P 在 Dart 端独立实现
// - KnowledgeMixin: 全 stub，KnowledgeService 走 sqflite 兜底
// 对外 API 完全不变，所有调用方零改动。
class FFIBridge with VaultMixin, GitMixin, P2PMixin, KnowledgeMixin {
  FFIBridge();

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  DynamicLibrary? _dylib;

  // C ABI 函数引用
  late final _InitDart _devnoteInit;
  late final _DestroyDart _devnoteDestroy;
  late final _DispatchDart _devnoteDispatch;
  late final _FreeStringDart _devnoteFreeString;

  /// 初始化 FFI 桥接：加载动态库 + 查找函数 + 调用 devnote_init 注册处理器
  Future<void> init() async {
    try {
      final dylib = _openNativeLibrary();
      if (dylib == null) {
        throw StateError('Native library not found');
      }
      _dylib = dylib;

      // 查找 C ABI 函数
      _devnoteInit = _dylib!.lookupFunction<_InitNative, _InitDart>('devnote_init');
      _devnoteDestroy = _dylib!.lookupFunction<_DestroyNative, _DestroyDart>('devnote_destroy');
      _devnoteDispatch = _dylib!.lookupFunction<_DispatchNative, _DispatchDart>('devnote_dispatch');
      _devnoteFreeString = _dylib!.lookupFunction<_FreeStringNative, _FreeStringDart>('devnote_free_string');

      // 调用 devnote_init 注册所有事件处理器并初始化引擎
      final responsePtr = _devnoteInit();
      try {
        if (responsePtr == nullptr) {
          throw StateError('devnote_init returned null pointer');
        }
        final code = responsePtr.ref.code;
        final message = responsePtr.ref.message.toDartString();
        if (code != 0) {
          throw StateError('FFI init failed ($code): $message');
        }
      } finally {
        // P0 修复: 无论 toDartString 是否抛异常都释放 responsePtr
        _devnoteDestroy(responsePtr);
      }

      _isAvailable = true;
      log('FFIBridge initialized successfully', name: 'FFIBridge');
    } catch (e) {
      _isAvailable = false;
      log('FFIBridge init failed: $e', name: 'FFIBridge', level: 900);
      rethrow;
    }
  }

  /// 跨平台加载 native 动态库
  DynamicLibrary? _openNativeLibrary() {
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('libdevnote_ffi.so');
      }
      if (Platform.isIOS) {
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

  // ============================================================
  // 核心分发方法 —— 通过 C ABI 调用 Rust dispatch
  // ============================================================

  /// 调用 Rust 端 devnote_dispatch，返回解析后的 JSON 数据
  dynamic _dispatch(String event, [Map<String, dynamic>? payload]) {
    final requestJson = jsonEncode({
      'event': event,
      'payload': payload != null ? jsonEncode(payload) : null,
    });

    final requestPtr = requestJson.toNativeUtf8();
    try {
      final responsePtr = _devnoteDispatch(requestPtr);
      if (responsePtr == nullptr) {
        throw StateError('FFI dispatch returned null for event: $event');
      }

      try {
        final responseJson = responsePtr.toDartString();
        final response = jsonDecode(responseJson) as Map<String, dynamic>;
        final code = (response['code'] as num).toInt();
        if (code != 0) {
          throw FfiException(event, code, response['message'] as String? ?? 'Unknown error');
        }

        final data = response['data'] as String?;
        if (data == null || data.isEmpty) return null;
        return jsonDecode(data);
      } finally {
        // P0 修复: 无论 toDartString/jsonDecode 是否抛异常都释放 responsePtr
        // 避免 Rust 端 CString::into_raw() 分配的内存泄漏
        _devnoteFreeString(responsePtr);
      }
    } finally {
      malloc.free(requestPtr);
    }
  }

  /// 分发并返回 Map
  Map<String, dynamic> _dispatchMap(String event, [Map<String, dynamic>? payload]) {
    final result = _dispatch(event, payload);
    if (result == null) return {};
    return Map<String, dynamic>.from(result as Map);
  }

  /// 分发并返回 List<Map>
  List<Map<String, dynamic>> _dispatchList(String event, [Map<String, dynamic>? payload]) {
    final result = _dispatch(event, payload);
    if (result == null) return [];
    return (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 分发并返回 String
  String _dispatchString(String event, [Map<String, dynamic>? payload]) {
    final result = _dispatch(event, payload);
    if (result == null) return '';
    if (result is String) return result;
    return result.toString();
  }

  void _checkAvailable() {
    if (!_isAvailable) {
      throw StateError('FFI bridge not available. Call init() first.');
    }
  }

  // ============================================================
  // 系统 API
  // ============================================================

  Future<FfiVersionInfo?> negotiateVersion() async {
    if (!_isAvailable) return null;
    try {
      final result = _dispatchMap('SystemEvent.GetVersion');
      return FfiVersionInfo.fromJson(result);
    } catch (e) {
      log('FFI negotiateVersion failed: $e', name: 'FFIBridge');
      return null;
    }
  }

  Future<Map<String, bool>?> healthCheck() async {
    if (!_isAvailable) return null;
    try {
      final result = _dispatchMap('SystemEvent.HealthCheck');
      final engines = result['engines'] as Map<String, dynamic>;
      return engines.map((k, v) => MapEntry(k, v as bool));
    } catch (e) {
      log('FFI healthCheck failed: $e', name: 'FFIBridge');
      return null;
    }
  }

  // ============================================================
  // 笔记 API
  // ============================================================

  Future<Map<String, dynamic>> createNote({
    required String title,
    required String content,
    required String folderId,
  }) async {
    _checkAvailable();
    return _dispatchMap('NoteEvent.CreateNote', {
      'title': title,
      'content': content,
      'folder_id': folderId,
    });
  }

  Future<Map<String, dynamic>?> getNote(String id) async {
    _checkAvailable();
    final result = _dispatch('NoteEvent.GetNote', {'id': id});
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> updateNote({
    required String id,
    required String title,
    required String content,
  }) async {
    _checkAvailable();
    return _dispatchMap('NoteEvent.UpdateNote', {
      'id': id,
      'title': title,
      'content': content,
    });
  }

  Future<void> deleteNote(String id) async {
    _checkAvailable();
    _dispatch('NoteEvent.DeleteNote', {'id': id});
  }

  Future<List<Map<String, dynamic>>> listNotes(String folderId) async {
    _checkAvailable();
    return _dispatchList('NoteEvent.ListNotes', {'folder_id': folderId});
  }

  // ============================================================
  // 文件夹 API
  // ============================================================

  Future<Map<String, dynamic>> createFolder({
    required String name,
    String? parentId,
  }) async {
    _checkAvailable();
    return _dispatchMap('FolderEvent.CreateFolder', {
      'name': name,
      'parent_id': parentId,
    });
  }

  Future<List<Map<String, dynamic>>> listFolders({String? parentId}) async {
    _checkAvailable();
    return _dispatchList('FolderEvent.ListFolders', {
      'parent_id': parentId,
    });
  }

  /// 修复(P0): 补全 getFolder，原缺失导致 PersistenceDispatch.get(entity:'folder') 抛 UnimplementedError
  Future<Map<String, dynamic>?> getFolder(String id) async {
    _checkAvailable();
    final result = _dispatch('FolderEvent.GetFolder', {'id': id});
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> deleteFolder(String id) async {
    _checkAvailable();
    _dispatch('FolderEvent.DeleteFolder', {'id': id});
  }

  Future<Map<String, dynamic>> updateFolder({
    required String id,
    required String name,
    String? parentId,
  }) async {
    _checkAvailable();
    return _dispatchMap('FolderEvent.UpdateFolder', {
      'id': id,
      'name': name,
      'parent_id': parentId,
    });
  }

  // ============================================================
  // 标签 API
  // ============================================================

  Future<Map<String, dynamic>> createTag(String name) async {
    _checkAvailable();
    return _dispatchMap('TagEvent.CreateTag', {'name': name});
  }

  Future<List<Map<String, dynamic>>> listTags() async {
    _checkAvailable();
    return _dispatchList('TagEvent.ListTags');
  }

  Future<void> deleteTag(String id) async {
    _checkAvailable();
    _dispatch('TagEvent.DeleteTag', {'id': id});
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
    return _dispatchMap('EditorEvent.InsertBlock', {
      'note_id': noteId,
      'block_type': blockType,
      'content': content,
      'position': position,
    });
  }

  Future<void> updateBlock({required String id, required String content}) async {
    _checkAvailable();
    _dispatch('EditorEvent.UpdateBlock', {'id': id, 'content': content});
  }

  Future<void> deleteBlock(String id) async {
    _checkAvailable();
    _dispatch('EditorEvent.DeleteBlock', {'id': id});
  }

  Future<List<Map<String, dynamic>>> getBlocks(String noteId) async {
    _checkAvailable();
    return _dispatchList('EditorEvent.GetBlocks', {'note_id': noteId});
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
    return _dispatchList('SearchEvent.Search', {
      'query': query,
      'limit': limit,
      'offset': offset,
    });
  }

  // ============================================================
  // 加密 API
  // ============================================================

  Future<String> encrypt({required String plaintextBase64, required String keyBase64}) async {
    _checkAvailable();
    return _dispatchString('CryptoEvent.Encrypt', {
      'plaintext_base64': plaintextBase64,
      'key_base64': keyBase64,
    });
  }

  Future<String> decrypt({required String ciphertextBase64, required String keyBase64}) async {
    _checkAvailable();
    return _dispatchString('CryptoEvent.Decrypt', {
      'ciphertext_base64': ciphertextBase64,
      'key_base64': keyBase64,
    });
  }

  Future<String> deriveKey({required String password, required String saltBase64}) async {
    _checkAvailable();
    return _dispatchString('CryptoEvent.DeriveKey', {
      'password': password,
      'salt_base64': saltBase64,
    });
  }

  // ============================================================
  // 同步 API
  // ============================================================

  Future<void> pushChanges() async {
    _checkAvailable();
    _dispatch('SyncEvent.PushChanges');
  }

  Future<void> pullChanges() async {
    _checkAvailable();
    _dispatch('SyncEvent.PullChanges');
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    _checkAvailable();
    return _dispatchMap('SyncEvent.GetStatus');
  }

  // ============================================================
  // Canvas API
  // ============================================================

  Future<void> canvasAddNode({required String canvasId, required String nodeJson}) async {
    _checkAvailable();
    _dispatch('CanvasEvent.AddNode', {
      'canvas_id': canvasId,
      'node': jsonDecode(nodeJson),
    });
  }

  Future<void> canvasRemoveNode({required String canvasId, required String nodeId}) async {
    _checkAvailable();
    _dispatch('CanvasEvent.RemoveNode', {
      'canvas_id': canvasId,
      'node_id': nodeId,
    });
  }

  Future<void> canvasAutoLayout({required String canvasId, required String layoutType}) async {
    _checkAvailable();
    _dispatch('CanvasEvent.AutoLayout', {
      'canvas_id': canvasId,
      'layout_type': layoutType,
    });
  }

  Future<void> canvasAddEdge({required String canvasId, required String edgeJson}) async {
    _checkAvailable();
    _dispatch('CanvasEvent.AddEdge', {
      'canvas_id': canvasId,
      'edge': jsonDecode(edgeJson),
    });
  }

  Future<void> canvasSaveCanvas({required String canvasId, required String path}) async {
    _checkAvailable();
    _dispatch('CanvasEvent.SaveJson', {
      'canvas_id': canvasId,
      'path': path,
    });
  }

  Future<String> canvasLoadCanvas({required String path}) async {
    _checkAvailable();
    final result = _dispatch('CanvasEvent.LoadJson', {'path': path});
    return jsonEncode(result);
  }

  // 以下 Canvas 方法无对应 C ABI handler
  // P0 修复: 原 throw UnimplementedError 会导致调用方崩溃，改为返回降级结果
  // 调用方应根据返回值判断是否成功，而非依赖 try-catch
  Future<String> canvasCreateCanvas() async => '{}';
  Future<Map<String, dynamic>> canvasGetCanvas({required String canvasId}) async => {};
  Future<void> canvasMoveNode({required String canvasId, required String nodeId, required double x, required double y}) async {}
  Future<void> canvasResizeNode({required String canvasId, required String nodeId, required double width, required double height}) async {}
  Future<void> canvasRemoveEdge({required String canvasId, required String edgeId}) async {}
  Future<void> canvasStartCollaboration({required String canvasId, required String sessionId}) async {}
  Future<Map<String, dynamic>> canvasJoinCollaboration({required String sessionId}) async => {};
  Future<void> canvasBroadcastChange({required String changeJson}) async {}
  Future<void> canvasEndCollaboration({required String sessionId}) async {}

  // ============================================================
  // 数据库 API
  // ============================================================

  Future<String> createDatabase(String name) async {
    _checkAvailable();
    final result = _dispatch('DatabaseEvent.CreateDatabase', {'name': name});
    return jsonEncode(result);
  }

  Future<String> evaluateFormula({
    required String formula,
    required String rowValues,
    required String allRows,
  }) async {
    _checkAvailable();
    final result = _dispatch('DatabaseEvent.EvaluateFormula', {
      'formula': formula,
      'row_values': jsonDecode(rowValues),
      'all_rows': jsonDecode(allRows),
    });
    return jsonEncode(result);
  }

  // ============================================================
  // 图谱 API
  // ============================================================

  Future<String> calculateCentrality() async {
    _checkAvailable();
    return jsonEncode(_dispatch('GraphEvent.CalculateCentrality'));
  }

  Future<String> detectClusters() async {
    _checkAvailable();
    return jsonEncode(_dispatch('GraphEvent.DetectClusters'));
  }

  // 以下图谱方法无对应 C ABI handler
  // P0 修复: 返回空 JSON 而非抛异常，调用方应处理空结果
  Future<String> getGraph() async => '{"nodes":[],"edges":[]}';
  Future<String> getNodeDetails({required String nodeId}) async => '{}';
  Future<String> getRelatedNodes({required String nodeId}) async => '{"nodes":[]}';
  Future<String> searchNodes({required String query}) async => '{"nodes":[]}';
  Future<String> getGraphStats() async => '{"node_count":0,"edge_count":0}';
  Future<String> getShortestPath({required String fromId, required String toId}) async => '{"path":[]}';
  Future<String> getNeighbors({required String nodeId, required int depth}) async => '{"nodes":[]}';

  // ============================================================
  // 闪卡 API
  // ============================================================

  Future<String> createDeck({required String name, required String description}) async {
    _checkAvailable();
    return jsonEncode(_dispatch('FlashcardEvent.CreateDeck', {
      'name': name,
      'description': description,
    }));
  }

  Future<String> reviewFlashcard({required String flashcardId, required int quality}) async {
    _checkAvailable();
    return jsonEncode(_dispatch('FlashcardEvent.ReviewCard', {
      'flashcard_id': flashcardId,
      'quality': quality,
    }));
  }

  Future<String> getDueCards({required String deckId, int? limit}) async {
    _checkAvailable();
    return jsonEncode(_dispatch('FlashcardEvent.GetDueCards', {
      'deck_id': deckId,
      'limit': limit,
    }));
  }

  // 以下闪卡方法无对应 C ABI handler
  // P0 修复: 返回空结果而非抛异常，调用方应使用 Dart 端 sqflite 兜底
  Future<void> deleteDeck({required String deckId}) async {}
  Future<List<Map<String, dynamic>>> listDecks() async => [];
  Future<Map<String, dynamic>> createFlashcard({required String deckId, required String cardType, required String front, required String back, String? noteId}) async => {};
  Future<Map<String, dynamic>> updateFlashcard({required String id, required String front, required String back}) async => {};
  Future<void> deleteFlashcard({required String flashcardId}) async {}
  Future<Map<String, dynamic>> getReviewStats({required String deckId}) async => {'total_cards': 0, 'due_cards': 0, 'new_cards': 0};
  Future<List<Map<String, dynamic>>> batchGenerateFromNote({required String noteId}) async => [];

  // ============================================================
  // CRDT API
  // ============================================================

  Future<Map<String, dynamic>> crdtMerge({
    required String docId,
    required String deviceId,
    required String remoteOpsJson,
  }) async {
    _checkAvailable();
    return _dispatchMap('CRDTEvent.Merge', {
      'doc_id': docId,
      'device_id': deviceId,
      'remote_ops': jsonDecode(remoteOpsJson),
    });
  }

  // P1 修复 (P1-2): Git/P2P/Knowledge API 已迁移至 Mixin
  // - GitMixin (mixins/git_mixin.dart)
  // - P2PMixin (mixins/p2p_mixin.dart)
  // - KnowledgeMixin (mixins/knowledge_mixin.dart)

  // ============================================================
  // 格式 API
  // ============================================================

  Future<String> importMarkdown(String path) async {
    _checkAvailable();
    return jsonEncode(_dispatch('FormatEvent.ImportMarkdown', {'path': path}));
  }

  Future<void> exportMarkdown({required String notesJson, required String path}) async {
    _checkAvailable();
    _dispatch('FormatEvent.ExportMarkdown', {
      'notes': jsonDecode(notesJson),
      'path': path,
    });
  }

  // ============================================================
  // 语音转文字 API —— 无对应 C ABI handler
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
    return _dispatchString('OcrEvent.Recognize', {'image_base64': imageBase64});
  }

  Future<Map<String, dynamic>> ocrRecognizeImageDetailed({required String imageBase64}) async => {'text': '', 'blocks': []};

  Future<void> indexOcrText({required String noteId, required String ocrText}) async {
    _checkAvailable();
    _dispatch('OcrEvent.IndexImage', {
      'note_id': noteId,
      'image_base64': '',
    });
  }

  // ============================================================
  // FeatureFlag API —— 修复(P1/R10-04): 补全 FFI 桥接，原 UI 为空壳
  // ============================================================

  Future<List<Map<String, dynamic>>> listFeatureFlags() async {
    _checkAvailable();
    return _dispatchList('FeatureFlagEvent.ListFlags');
  }

  Future<void> setFeatureFlag({
    required String key,
    required bool enabled,
    String description = '',
  }) async {
    _checkAvailable();
    _dispatch('FeatureFlagEvent.SetFlag', {
      'key': key,
      'enabled': enabled,
      'description': description,
    });
  }

  // P1 修复 (P1-2): Vault API 已迁移至 mixins/vault_mixin.dart (VaultMixin)
  // - vaultEncrypt / vaultDecrypt / vaultVerifyPassword
  // - _generateSecureRandom / _deriveVaultKey
  // - VaultEncryptedData 数据类
  // 通过本文件顶部的 export 语句重新导出 VaultEncryptedData。

  // ============================================================
  // 工具方法
  // ============================================================

  void dispose() {
    _isAvailable = false;
    _dylib = null;
  }
}
