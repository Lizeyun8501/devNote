import 'dart:convert';
import 'package:devnote/core/bridge/dispatch.dart';
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
  String jsonStr,
  T Function(Map<String, dynamic>) fromJson,
) {
  final json = jsonDecode(jsonStr);
  if (json is Map<String, dynamic>) {
    return fromJson(json);
  }
  throw Exception('Invalid response format');
}

List<T> _parseListResult<T>(
  String jsonStr,
  T Function(Map<String, dynamic>) fromJson,
) {
  final json = jsonDecode(jsonStr);
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

class GitService {
  final Dispatch _dispatch = getIt<Dispatch>();
  String? _repoPath;

  Future<void> init(String repoPath) async {
    await _dispatch.gitInit(repoPath: repoPath);
    _repoPath = repoPath;
  }

  String _ensureRepoPath() {
    final path = _repoPath;
    if (path == null) {
      throw StateError('Git 仓库未初始化，请先调用 init()');
    }
    return path;
  }

  Future<void> commit(String message) async {
    await _dispatch.gitCommit(repoPath: _ensureRepoPath(), message: message);
  }

  Future<List<GitCommitInfoModel>> log({int maxCount = 50}) async {
    final jsonStr = await _dispatch.gitLog(repoPath: _ensureRepoPath(), limit: maxCount);
    return _parseListResult(jsonStr, GitCommitInfoModel.fromJson);
  }

  Future<List<GitDiffEntryModel>> diff({String? commitHash}) async {
    final jsonStr = await _dispatch.gitDiff(repoPath: _ensureRepoPath());
    return _parseListResult(jsonStr, GitDiffEntryModel.fromJson);
  }

  Future<void> checkout(String reference) async {
    await _dispatch.gitCheckout(repoPath: _ensureRepoPath(), branch: reference);
  }

  Future<List<GitBranchInfoModel>> branch() async {
    final jsonStr = await _dispatch.gitBranch(repoPath: _ensureRepoPath());
    return _parseListResult(jsonStr, GitBranchInfoModel.fromJson);
  }

  Future<GitStatusModel> status() async {
    final jsonStr = await _dispatch.gitStatus(repoPath: _ensureRepoPath());
    return _parseResult(jsonStr, GitStatusModel.fromJson);
  }
}
