import 'dart:convert';
import 'dart:typed_data';

import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/ffi_request.dart';

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

class Dispatch {
  Dispatch._();

  static final Dispatch _instance = Dispatch._();
  static Dispatch get instance => _instance;

  final FFIBridge _bridge = FFIBridge.instance;

  Future<FlowyResult<Uint8List, FlowyInternalError>> asyncRequest(
    String event, {
    Uint8List? payload,
  }) async {
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

  String ping() => _bridge.ping();
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
