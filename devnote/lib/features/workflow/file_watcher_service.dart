import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';

enum FileChangeKind { create, modify, delete, rename }

class FileChangeEvent {
  final String path;
  final FileChangeKind kind;

  const FileChangeEvent({
    required this.path,
    required this.kind,
  });

  factory FileChangeEvent.fromJson(Map<String, dynamic> json) {
    return FileChangeEvent(
      path: json['path'] as String,
      kind: FileChangeKind.values.firstWhere(
        (e) => e.name == (json['kind'] as String),
        orElse: () => FileChangeKind.modify,
      ),
    );
  }
}

class FileWatcherService {
  final Dispatch _dispatch = getIt<Dispatch>();
  StreamController<FileChangeEvent>? _controller;

  Stream<FileChangeEvent> get onFileChange {
    _controller ??= StreamController<FileChangeEvent>.broadcast();
    return _controller!.stream;
  }

  Future<void> watchDirectory(String path) async {
    final payload = jsonEncode({'watch_path': path});
    await _dispatch.asyncRequest(
      'WorkflowEvent.WatchDirectory',
      payload: utf8.encode(payload),
    );
  }

  Future<void> stopWatching() async {
    await _controller?.close();
    _controller = null;
  }

  void handleEvent(FlowyResult<Uint8List, FlowyInternalError> result) {
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        final event = FileChangeEvent.fromJson(json);
        _controller?.add(event);
      }
    }
  }
}
