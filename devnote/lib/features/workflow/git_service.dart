import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';

class GitStatusModel {
  final List<String> modified;
  final List<String> added;
  final List<String> deleted;
  final List<String> untracked;

  const GitStatusModel({
    required this.modified,
    required this.added,
    required this.deleted,
    required this.untracked,
  });

  factory GitStatusModel.fromJson(Map<String, dynamic> json) {
    return GitStatusModel(
      modified: (json['modified'] as List<dynamic>).cast<String>(),
      added: (json['added'] as List<dynamic>).cast<String>(),
      deleted: (json['deleted'] as List<dynamic>).cast<String>(),
      untracked: (json['untracked'] as List<dynamic>).cast<String>(),
    );
  }

  bool get hasChanges =>
      modified.isNotEmpty ||
      added.isNotEmpty ||
      deleted.isNotEmpty ||
      untracked.isNotEmpty;
}

class GitCommitInfoModel {
  final String hash;
  final String author;
  final String date;
  final String message;

  const GitCommitInfoModel({
    required this.hash,
    required this.author,
    required this.date,
    required this.message,
  });

  factory GitCommitInfoModel.fromJson(Map<String, dynamic> json) {
    return GitCommitInfoModel(
      hash: json['hash'] as String,
      author: json['author'] as String,
      date: json['date'] as String,
      message: json['message'] as String,
    );
  }
}

class GitDiffEntryModel {
  final String file;
  final String status;
  final int additions;
  final int deletions;

  const GitDiffEntryModel({
    required this.file,
    required this.status,
    required this.additions,
    required this.deletions,
  });

  factory GitDiffEntryModel.fromJson(Map<String, dynamic> json) {
    return GitDiffEntryModel(
      file: json['file'] as String,
      status: json['status'] as String,
      additions: json['additions'] as int,
      deletions: json['deletions'] as int,
    );
  }
}

class GitBranchInfoModel {
  final String name;
  final bool isCurrent;

  const GitBranchInfoModel({
    required this.name,
    required this.isCurrent,
  });

  factory GitBranchInfoModel.fromJson(Map<String, dynamic> json) {
    return GitBranchInfoModel(
      name: json['name'] as String,
      isCurrent: json['is_current'] as bool,
    );
  }
}

T _parseResult<T>(
  FlowyResult<Uint8List, FlowyInternalError> result,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (result is Success<Uint8List, FlowyInternalError>) {
    final json = jsonDecode(utf8.decode(result.value));
    if (json is Map<String, dynamic>) {
      return fromJson(json);
    }
    throw Exception('Invalid response format');
  }
  if (result is Failure<Uint8List, FlowyInternalError>) {
    throw Exception(result.error.message);
  }
  throw Exception('Unknown result type');
}

List<T> _parseListResult<T>(
  FlowyResult<Uint8List, FlowyInternalError> result,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (result is Success<Uint8List, FlowyInternalError>) {
    final json = jsonDecode(utf8.decode(result.value));
    if (json is List) {
      return json
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (json is Map<String, dynamic> && json.containsKey('data')) {
      final data = json['data'];
      if (data is List) {
        return data
            .map((e) => fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    // 修复：非预期格式时抛出异常而非静默返回空列表
    // 原代码返回 [] 掩盖了 Rust 后端返回格式错误的问题
    throw Exception('Invalid list response format: expected List, got ${json.runtimeType}');
  }
  if (result is Failure<Uint8List, FlowyInternalError>) {
    throw Exception(result.error.message);
  }
  throw Exception('Unknown result type');
}

class GitService {
  final Dispatch _dispatch = getIt<Dispatch>();

  Future<void> init(String repoPath) async {
    final payload = jsonEncode({'repo_path': repoPath});
    // 修复：检查 FFI 返回结果，避免 git init 失败时静默继续
    // 原代码直接 await 不处理返回值，init 失败时用户不会收到任何提示
    final result = await _dispatch.asyncRequest(
      'WorkflowEvent.GitInit',
      payload: utf8.encode(payload),
    );
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception('Git初始化失败: ${result.error.message}');
    }
  }

  Future<void> commit(String message) async {
    final payload = jsonEncode({'message': message});
    // 修复：检查 FFI 返回结果，避免 git commit 失败时静默继续
    final result = await _dispatch.asyncRequest(
      'WorkflowEvent.GitCommit',
      payload: utf8.encode(payload),
    );
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception('Git提交失败: ${result.error.message}');
    }
  }

  Future<List<GitCommitInfoModel>> log({int? maxCount}) async {
    final payload = jsonEncode({'max_count': maxCount});
    final result = await _dispatch.asyncRequest(
      'WorkflowEvent.GitLog',
      payload: utf8.encode(payload),
    );
    return _parseListResult(result, GitCommitInfoModel.fromJson);
  }

  Future<List<GitDiffEntryModel>> diff({String? commitHash}) async {
    final payload = jsonEncode({'commit_hash': commitHash});
    final result = await _dispatch.asyncRequest(
      'WorkflowEvent.GitDiff',
      payload: utf8.encode(payload),
    );
    return _parseListResult(result, GitDiffEntryModel.fromJson);
  }

  Future<void> checkout(String reference) async {
    final payload = jsonEncode({'reference': reference});
    // 修复：检查 FFI 返回结果，避免 checkout 失败时静默继续
    final result = await _dispatch.asyncRequest(
      'WorkflowEvent.GitCheckout',
      payload: utf8.encode(payload),
    );
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception('Git checkout失败: ${result.error.message}');
    }
  }

  Future<List<GitBranchInfoModel>> branch({String? name}) async {
    final payload = jsonEncode({'name': name});
    final result = await _dispatch.asyncRequest(
      'WorkflowEvent.GitBranch',
      payload: utf8.encode(payload),
    );
    return _parseListResult(result, GitBranchInfoModel.fromJson);
  }

  Future<GitStatusModel> status() async {
    final result = await _dispatch.asyncRequest(
      'WorkflowEvent.GitStatus',
      payload: Uint8List(0),
    );
    return _parseResult(result, GitStatusModel.fromJson);
  }
}
