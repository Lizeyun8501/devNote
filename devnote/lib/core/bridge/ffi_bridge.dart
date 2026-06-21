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
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' hide Utf16Pointer;
import 'package:pointycastle/export.dart';

import 'ffi_response.dart';

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

/// Vault 加密数据
class VaultEncryptedData {
  final String ciphertext;
  final String salt;
  final String nonce;
  final int memoryCost;
  final int timeCost;
  final int parallelism;

  VaultEncryptedData({
    required this.ciphertext,
    required this.salt,
    required this.nonce,
    required this.memoryCost,
    required this.timeCost,
    required this.parallelism,
  });

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'salt': salt,
    'nonce': nonce,
    'memory_cost': memoryCost,
    'time_cost': timeCost,
    'parallelism': parallelism,
  };

  factory VaultEncryptedData.fromJson(Map<String, dynamic> json) =>
      VaultEncryptedData(
        ciphertext: json['ciphertext'] as String,
        salt: json['salt'] as String,
        nonce: json['nonce'] as String,
        memoryCost: (json['memory_cost'] as num).toInt(),
        timeCost: (json['time_cost'] as num).toInt(),
        parallelism: (json['parallelism'] as num).toInt(),
      );
}

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

class FFIBridge {
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
      final code = responsePtr.ref.code;
      final message = responsePtr.ref.message.toDartString();
      _devnoteDestroy(responsePtr);

      if (code != 0) {
        throw StateError('FFI init failed ($code): $message');
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

      final responseJson = responsePtr.toDartString();
      _devnoteFreeString(responsePtr);

      final response = jsonDecode(responseJson) as Map<String, dynamic>;
      final code = (response['code'] as num).toInt();
      if (code != 0) {
        throw FfiException(event, code, response['message'] as String? ?? 'Unknown error');
      }

      final data = response['data'] as String?;
      if (data == null || data.isEmpty) return null;
      return jsonDecode(data);
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
  Future<String> canvasCreateCanvas() async => throw UnimplementedError('canvasCreateCanvas: no C ABI handler');
  Future<Map<String, dynamic>> canvasGetCanvas({required String canvasId}) async => throw UnimplementedError('canvasGetCanvas: no C ABI handler');
  Future<void> canvasMoveNode({required String canvasId, required String nodeId, required double x, required double y}) async => throw UnimplementedError('canvasMoveNode: no C ABI handler');
  Future<void> canvasResizeNode({required String canvasId, required String nodeId, required double width, required double height}) async => throw UnimplementedError('canvasResizeNode: no C ABI handler');
  Future<void> canvasRemoveEdge({required String canvasId, required String edgeId}) async => throw UnimplementedError('canvasRemoveEdge: no C ABI handler');
  Future<void> canvasStartCollaboration({required String canvasId, required String sessionId}) async => throw UnimplementedError('canvasStartCollaboration: no C ABI handler');
  Future<Map<String, dynamic>> canvasJoinCollaboration({required String sessionId}) async => throw UnimplementedError('canvasJoinCollaboration: no C ABI handler');
  Future<void> canvasBroadcastChange({required String changeJson}) async => throw UnimplementedError('canvasBroadcastChange: no C ABI handler');
  Future<void> canvasEndCollaboration({required String sessionId}) async => throw UnimplementedError('canvasEndCollaboration: no C ABI handler');

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
  Future<String> getGraph() async => throw UnimplementedError('getGraph: no C ABI handler');
  Future<String> getNodeDetails({required String nodeId}) async => throw UnimplementedError('getNodeDetails: no C ABI handler');
  Future<String> getRelatedNodes({required String nodeId}) async => throw UnimplementedError('getRelatedNodes: no C ABI handler');
  Future<String> searchNodes({required String query}) async => throw UnimplementedError('searchNodes: no C ABI handler');
  Future<String> getGraphStats() async => throw UnimplementedError('getGraphStats: no C ABI handler');
  Future<String> getShortestPath({required String fromId, required String toId}) async => throw UnimplementedError('getShortestPath: no C ABI handler');
  Future<String> getNeighbors({required String nodeId, required int depth}) async => throw UnimplementedError('getNeighbors: no C ABI handler');

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
  Future<void> deleteDeck({required String deckId}) async => throw UnimplementedError('deleteDeck: no C ABI handler');
  Future<List<Map<String, dynamic>>> listDecks() async => throw UnimplementedError('listDecks: no C ABI handler');
  Future<Map<String, dynamic>> createFlashcard({required String deckId, required String cardType, required String front, required String back, String? noteId}) async => throw UnimplementedError('createFlashcard: no C ABI handler');
  Future<Map<String, dynamic>> updateFlashcard({required String id, required String front, required String back}) async => throw UnimplementedError('updateFlashcard: no C ABI handler');
  Future<void> deleteFlashcard({required String flashcardId}) async => throw UnimplementedError('deleteFlashcard: no C ABI handler');
  Future<Map<String, dynamic>> getReviewStats({required String deckId}) async => throw UnimplementedError('getReviewStats: no C ABI handler');
  Future<List<Map<String, dynamic>>> batchGenerateFromNote({required String noteId}) async => throw UnimplementedError('batchGenerateFromNote: no C ABI handler');

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

  // ============================================================
  // Git API —— 无对应 C ABI handler
  // ============================================================

  Future<String> gitInit({required String repoPath}) async => throw UnimplementedError('gitInit: no C ABI handler');
  Future<String> gitStatus({required String repoPath}) async => throw UnimplementedError('gitStatus: no C ABI handler');
  Future<String> gitCommit({required String repoPath, required String message}) async => throw UnimplementedError('gitCommit: no C ABI handler');
  Future<String> gitLog({required String repoPath, required int limit}) async => throw UnimplementedError('gitLog: no C ABI handler');
  Future<String> gitBranch({required String repoPath}) async => throw UnimplementedError('gitBranch: no C ABI handler');
  Future<String> gitCheckout({required String repoPath, required String branch}) async => throw UnimplementedError('gitCheckout: no C ABI handler');
  Future<String> gitDiff({required String repoPath}) async => throw UnimplementedError('gitDiff: no C ABI handler');

  // ============================================================
  // P2P API —— 无对应 C ABI handler（P2P 在 Dart 端独立实现）
  // ============================================================

  Future<void> p2pStart({required String peerId}) async => throw UnimplementedError('p2pStart: no C ABI handler');
  Future<void> p2pStop() async => throw UnimplementedError('p2pStop: no C ABI handler');
  Future<String> p2pGetPeers() async => throw UnimplementedError('p2pGetPeers: no C ABI handler');
  Future<void> p2pConnectPeer({required String peerId, required String multiaddr}) async => throw UnimplementedError('p2pConnectPeer: no C ABI handler');
  Future<void> p2pDisconnectPeer({required String peerId}) async => throw UnimplementedError('p2pDisconnectPeer: no C ABI handler');
  Future<String> p2pGetStatus() async => throw UnimplementedError('p2pGetStatus: no C ABI handler');

  // ============================================================
  // Knowledge API —— 无对应 C ABI handler
  // ============================================================

  Future<String> getKnowledgeMap({required String noteId}) async => throw UnimplementedError('getKnowledgeMap: no C ABI handler');
  Future<String> getLearningStats({required String noteId}) async => throw UnimplementedError('getLearningStats: no C ABI handler');
  Future<String> getDashboard() async => throw UnimplementedError('getDashboard: no C ABI handler');

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
  }) async => throw UnimplementedError('transcribeAudio: no C ABI handler, use platform native API');

  // ============================================================
  // OCR API
  // ============================================================

  Future<String> ocrRecognizeImage({required String imageBase64}) async {
    _checkAvailable();
    return _dispatchString('OcrEvent.Recognize', {'image_base64': imageBase64});
  }

  Future<Map<String, dynamic>> ocrRecognizeImageDetailed({required String imageBase64}) async => throw UnimplementedError('ocrRecognizeImageDetailed: no C ABI handler');

  Future<void> indexOcrText({required String noteId, required String ocrText}) async {
    _checkAvailable();
    _dispatch('OcrEvent.IndexImage', {
      'note_id': noteId,
      'image_base64': '',
    });
  }

  // ============================================================
  // Vault API —— Dart 端实现（Rust 端无对应 C ABI handler）
  // 使用 AES-256-GCM + PBKDF2-HMAC-SHA256（与 CryptoService 一致）
  // VaultEncryptedData 中的 memoryCost/timeCost/parallelism 保留用于
  // 未来 Argon2id 迁移，当前 PBKDF2 使用固定迭代次数
  // ============================================================

  static const int _vaultPbkdf2Iterations = 100000;

  Future<VaultEncryptedData> vaultEncrypt({
    required String password,
    required String plaintext,
  }) async {
    final salt = _generateSecureRandom(32);
    final nonce = _generateSecureRandom(12);
    final key = _deriveVaultKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final ciphertextWithTag = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));

    return VaultEncryptedData(
      ciphertext: base64Encode(ciphertextWithTag),
      salt: base64Encode(salt),
      nonce: base64Encode(nonce),
      memoryCost: 0,
      timeCost: _vaultPbkdf2Iterations,
      parallelism: 1,
    );
  }

  Future<String> vaultDecrypt({
    required String password,
    required VaultEncryptedData encrypted,
  }) async {
    final salt = base64Decode(encrypted.salt);
    final nonce = base64Decode(encrypted.nonce);
    final ciphertextWithTag = base64Decode(encrypted.ciphertext);
    final key = _deriveVaultKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final plaintext = cipher.process(ciphertextWithTag);
    return utf8.decode(plaintext);
  }

  Future<bool> vaultVerifyPassword({
    required String password,
    required VaultEncryptedData encrypted,
  }) async {
    try {
      await vaultDecrypt(password: password, encrypted: encrypted);
      return true;
    } catch (_) {
      return false;
    }
  }

  Uint8List _generateSecureRandom(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  Uint8List _deriveVaultKey(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _vaultPbkdf2Iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  // ============================================================
  // 工具方法
  // ============================================================

  void dispose() {
    _isAvailable = false;
    _dylib = null;
  }
}
