// 行内评论数据模型 + 评论服务
// 借鉴 Notion 的行内评论（Inline Comments）和 AppFlowy v0.12 的评论系统
// 来源: https://www.notion.so
// 借鉴内容: 评论与记录/字段关联、回复嵌套、编辑/删除、时间戳

/// 行内评论
class DatabaseComment {
  final String id;
  final String recordId; // 关联的记录 ID
  final String? fieldId; // 关联的字段 ID（可选，null 为记录级评论）
  final String userId;
  final String username;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<DatabaseComment> replies; // 回复列表
  final String? replyToUserId; // 回复目标用户 ID

  DatabaseComment({
    required this.id,
    required this.recordId,
    this.fieldId,
    required this.userId,
    required this.username,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.replies = const [],
    this.replyToUserId,
  });

  DatabaseComment copyWith({
    String? content,
    DateTime? updatedAt,
    List<DatabaseComment>? replies,
  }) =>
      DatabaseComment(
        id: id,
        recordId: recordId,
        fieldId: fieldId,
        userId: userId,
        username: username,
        content: content ?? this.content,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        replies: replies ?? this.replies,
        replyToUserId: replyToUserId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'record_id': recordId,
        'field_id': fieldId,
        'user_id': userId,
        'username': username,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'replies': replies.map((r) => r.toJson()).toList(),
        'reply_to_user_id': replyToUserId,
      };

  factory DatabaseComment.fromJson(Map<String, dynamic> json) => DatabaseComment(
        id: json['id'] as String,
        recordId: json['record_id'] as String,
        fieldId: json['field_id'] as String?,
        userId: json['user_id'] as String,
        username: json['username'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
        replies: (json['replies'] as List? ?? [])
            .map((r) => DatabaseComment.fromJson(r as Map<String, dynamic>))
            .toList(),
        replyToUserId: json['reply_to_user_id'] as String?,
      );
}

/// 评论服务
class CommentService {
  // 内存存储（实际应持久化到数据库或通过 API）
  final Map<String, List<DatabaseComment>> _commentsByRecord = {};

  /// 获取记录的所有评论
  List<DatabaseComment> getComments(String recordId) {
    return _commentsByRecord[recordId] ?? [];
  }

  /// 添加评论
  DatabaseComment addComment({
    required String recordId,
    String? fieldId,
    required String userId,
    required String username,
    required String content,
    String? replyToCommentId,
    String? replyToUserId,
  }) {
    final comment = DatabaseComment(
      id: 'comment-${DateTime.now().millisecondsSinceEpoch}',
      recordId: recordId,
      fieldId: fieldId,
      userId: userId,
      username: username,
      content: content,
      createdAt: DateTime.now(),
      replyToUserId: replyToUserId,
    );

    if (replyToCommentId != null) {
      // 添加为回复
      final comments = _commentsByRecord[recordId] ?? [];
      final parentIndex = comments.indexWhere((c) => c.id == replyToCommentId);
      if (parentIndex >= 0) {
        final parent = comments[parentIndex];
        comments[parentIndex] = parent.copyWith(
          replies: [...parent.replies, comment],
        );
        _commentsByRecord[recordId] = comments;
      }
    } else {
      // 添加为顶级评论
      _commentsByRecord[recordId] = [
        ...(_commentsByRecord[recordId] ?? []),
        comment,
      ];
    }

    return comment;
  }

  /// 更新评论
  void updateComment(String recordId, String commentId, String newContent) {
    final comments = _commentsByRecord[recordId];
    if (comments == null) return;

    void updateInList(List<DatabaseComment> list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == commentId) {
          list[i] = list[i].copyWith(
            content: newContent,
            updatedAt: DateTime.now(),
          );
          return;
        }
        if (list[i].replies.isNotEmpty) {
          updateInList(list[i].replies);
        }
      }
    }

    updateInList(comments);
  }

  /// 删除评论
  void deleteComment(String recordId, String commentId) {
    final comments = _commentsByRecord[recordId];
    if (comments == null) return;

    comments.removeWhere((c) => c.id == commentId);
    // 也从回复中删除
    for (final comment in comments) {
      if (comment.replies.any((r) => r.id == commentId)) {
        final newReplies = comment.replies.where((r) => r.id != commentId).toList();
        final index = comments.indexOf(comment);
        comments[index] = comment.copyWith(replies: newReplies);
      }
    }
  }
}
