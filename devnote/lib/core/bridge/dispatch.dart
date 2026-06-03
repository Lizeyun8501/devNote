import 'dart:convert';
import 'dart:typed_data';

import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/ffi_request.dart';
import 'package:devnote/core/bridge/grpc_bridge.dart';
import 'package:devnote/core/bridge/websocket_bridge.dart';
import 'package:devnote/core/di/injection.dart';

enum NoteEvent {
  createNote('NoteEvent.CreateNote'),
  readNote('NoteEvent.ReadNote'),
  updateNote('NoteEvent.UpdateNote'),
  deleteNote('NoteEvent.DeleteNote'),
  listNotes('NoteEvent.ListNotes');

  const NoteEvent(this.name);
  final String name;
}

enum FolderEvent {
  createFolder('FolderEvent.CreateFolder'),
  readFolder('FolderEvent.ReadFolder'),
  updateFolder('FolderEvent.UpdateFolder'),
  deleteFolder('FolderEvent.DeleteFolder'),
  listFolders('FolderEvent.ListFolders');

  const FolderEvent(this.name);
  final String name;
}

enum EditorEvent {
  insertBlock('EditorEvent.InsertBlock'),
  updateBlock('EditorEvent.UpdateBlock'),
  deleteBlock('EditorEvent.DeleteBlock'),
  loadDocument('EditorEvent.LoadDocument');

  const EditorEvent(this.name);
  final String name;
}

enum SearchEvent {
  searchNotes('SearchEvent.SearchNotes'),
  searchContent('SearchEvent.SearchContent');

  const SearchEvent(this.name);
  final String name;
}

enum SyncEvent {
  startSync('SyncEvent.StartSync'),
  getSyncStatus('SyncEvent.GetSyncStatus'),
  resolveConflict('SyncEvent.ResolveConflict');

  const SyncEvent(this.name);
  final String name;
}

/// Dispatch mode: local (in-process via FFI) or remote (via gRPC/WebSocket)
enum DispatchMode {
  local,
  grpc,
  websocket,
}

class Dispatch {
  Dispatch();

  final FFIBridge _bridge = getIt<FFIBridge>();
  final GrpcBridge _grpcBridge = getIt<GrpcBridge>();
  final WebSocketBridge _wsBridge = getIt<WebSocketBridge>();

  DispatchMode _mode = DispatchMode.local;

  /// Set the dispatch mode
  void setMode(DispatchMode mode) {
    _mode = mode;
  }

  /// Get the current dispatch mode
  DispatchMode get mode => _mode;

  /// Initialize remote bridges (gRPC and WebSocket)
  void initRemote() {
    _grpcBridge.init();
    _wsBridge.init();
  }

  /// Connect to a gRPC server
  bool grpcConnect(String serverAddr) {
    final response = _grpcBridge.connect(serverAddr);
    return response.isOk;
  }

  /// Disconnect from the gRPC server
  bool grpcDisconnect() {
    final response = _grpcBridge.disconnect();
    return response.isOk;
  }

  /// Connect to a WebSocket server
  bool wsConnect(String url) {
    final response = _wsBridge.connect(url);
    return response.isOk;
  }

  /// Disconnect from the WebSocket server
  bool wsDisconnect() {
    final response = _wsBridge.disconnect();
    return response.isOk;
  }

  Future<FlowyResult<Uint8List, FlowyInternalError>> asyncRequest(
    String event, {
    Uint8List? payload,
  }) async {
    switch (_mode) {
      case DispatchMode.grpc:
        return _grpcRequest(event, payload: payload);
      case DispatchMode.websocket:
        return _wsRequest(event, payload: payload);
      case DispatchMode.local:
        return _localRequest(event, payload: payload);
    }
  }

  Future<FlowyResult<Uint8List, FlowyInternalError>> _localRequest(
    String event, {
    Uint8List? payload,
  }) async {
    // Check if FFI bridge is available before making FFI calls
    if (!_bridge.isAvailable) {
      return _localFallback(event, payload: payload);
    }
    try {
      final request = FFIRequest(
        event: event,
        payload: payload,
      );
      final response = _bridge.invoke(request);

      if (response.isOk) {
        return Success(response.data ?? Uint8List(0));
      } else {
        return Failure(FlowyInternalError(
          code: response.code,
          message: response.message,
        ));
      }
    } catch (e) {
      return Failure(FlowyInternalError(
        code: FFIStatusCode.internal.index,
        message: e.toString(),
      ));
    }
  }

  /// Local Dart fallback when FFI is not available
  Future<FlowyResult<Uint8List, FlowyInternalError>> _localFallback(
    String event, {
    Uint8List? payload,
  }) async {
    try {
      final result = _handleLocalEvent(event, payload);
      return Success(result);
    } catch (e) {
      return Failure(FlowyInternalError(
        code: FFIStatusCode.internal.index,
        message: e.toString(),
      ));
    }
  }

  /// Handle events locally in Dart when FFI is not available
  Uint8List _handleLocalEvent(String event, Uint8List? payload) {
    final payloadJson = payload != null
        ? jsonDecode(utf8.decode(payload)) as Map<String, dynamic>
        : <String, dynamic>{};
    final response = <String, dynamic>{
      'code': 0,
      'message': 'ok (local fallback)',
      'data': payloadJson,
    };
    return utf8.encode(jsonEncode(response));
  }

  Future<FlowyResult<Uint8List, FlowyInternalError>> _grpcRequest(
    String event, {
    Uint8List? payload,
  }) async {
    try {
      final payloadStr = payload != null ? utf8.decode(payload) : null;
      final response = _grpcBridge.dispatch(event, payload: payloadStr);

      if (response.isOk) {
        return Success(response.data ?? Uint8List(0));
      } else {
        return Failure(FlowyInternalError(
          code: response.code,
          message: response.message,
        ));
      }
    } catch (e) {
      return Failure(FlowyInternalError(
        code: FFIStatusCode.internal.index,
        message: e.toString(),
      ));
    }
  }

  Future<FlowyResult<Uint8List, FlowyInternalError>> _wsRequest(
    String event, {
    Uint8List? payload,
  }) async {
    try {
      final message = jsonEncode({
        'event': event,
        'payload':
            payload != null ? base64Encode(payload) : null,
      });
      final response = _wsBridge.send(message);

      if (response.isOk) {
        return Success(response.data ?? Uint8List(0));
      } else {
        return Failure(FlowyInternalError(
          code: response.code,
          message: response.message,
        ));
      }
    } catch (e) {
      return Failure(FlowyInternalError(
        code: FFIStatusCode.internal.index,
        message: e.toString(),
      ));
    }
  }

  Future<FlowyResult<T, FlowyInternalError>> asyncRequestJson<T>(
    String event, {
    Uint8List? payload,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    final result = await asyncRequest(event, payload: payload);
    return result.when(
      success: (data) {
        final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
        return Success(fromJson(json));
      },
      failure: (error) => Failure(error),
    );
  }

  /// Send a WebSocket message directly (useful for real-time updates)
  Future<FlowyResult<bool, FlowyInternalError>> wsSend(Map<String, dynamic> json) async {
    try {
      final response = _wsBridge.sendJson(json);
      if (response.isOk) {
        return const Success(true);
      } else {
        return Failure(FlowyInternalError(
          code: response.code,
          message: response.message,
        ));
      }
    } catch (e) {
      return Failure(FlowyInternalError(
        code: FFIStatusCode.internal.index,
        message: e.toString(),
      ));
    }
  }

  String ping() => _bridge.isAvailable ? _bridge.ping() : 'FFI not available';
}

extension _FlowyResultWhen<S, F> on FlowyResult<S, F> {
  R when<R>({
    required R Function(S) success,
    required R Function(F) failure,
  }) {
    if (this is Success<S, F>) {
      return success((this as Success<S, F>).value);
    } else {
      return failure((this as Failure<S, F>).error);
    }
  }
}