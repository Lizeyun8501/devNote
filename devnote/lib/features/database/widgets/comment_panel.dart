// 评论面板 —— 显示记录的所有评论，支持添加/回复/编辑/删除
// 借鉴 Notion 的评论侧边栏和 AppFlowy v0.12 的行内评论
// 来源: https://www.notion.so
// 借鉴内容: 评论列表、回复嵌套、编辑/删除操作、时间格式化、输入框

import 'package:flutter/material.dart';
import 'package:devnote/features/database/models/comment_model.dart';

/// 评论面板 — 显示记录的所有评论，支持添加/回复/编辑/删除
class CommentPanel extends StatefulWidget {
  final String recordId;
  final List<DatabaseComment> comments;
  final Function(String content, String? replyToCommentId)? onAddComment;
  final Function(String commentId, String newContent)? onUpdateComment;
  final Function(String commentId)? onDeleteComment;
  final String currentUserId;
  final String currentUsername;

  const CommentPanel({
    super.key,
    required this.recordId,
    required this.comments,
    this.onAddComment,
    this.onUpdateComment,
    this.onDeleteComment,
    required this.currentUserId,
    required this.currentUsername,
  });

  @override
  State<CommentPanel> createState() => _CommentPanelState();
}

class _CommentPanelState extends State<CommentPanel> {
  final _controller = TextEditingController();
  String? _replyToCommentId;
  String? _editingCommentId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isEmpty) return;

    if (_editingCommentId != null) {
      widget.onUpdateComment?.call(_editingCommentId!, _controller.text);
      setState(() {
        _editingCommentId = null;
        _controller.clear();
      });
    } else {
      widget.onAddComment?.call(_controller.text, _replyToCommentId);
      setState(() {
        _controller.clear();
        _replyToCommentId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Row(
              children: [
                const Icon(Icons.comment, size: 20),
                const SizedBox(width: 8),
                Text(
                  '评论 (${widget.comments.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // 评论列表
          Expanded(
            child: widget.comments.isEmpty
                ? const Center(
                    child: Text('暂无评论', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.comments.length,
                    itemBuilder: (context, index) {
                      return _buildCommentItem(widget.comments[index]);
                    },
                  ),
          ),
          // 输入框
          if (_replyToCommentId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.2),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('正在回复...', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      setState(() {
                        _replyToCommentId = null;
                        _controller.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: _editingCommentId != null
                          ? '编辑评论...'
                          : _replyToCommentId != null
                              ? '回复评论...'
                              : '添加评论...',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(DatabaseComment comment) {
    final isOwn = comment.userId == widget.currentUserId;
    final isEditing = _editingCommentId == comment.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 评论内容
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  comment.username.isNotEmpty
                      ? comment.username[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.username,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(comment.createdAt),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        if (comment.updatedAt != null)
                          const Text(
                            ' (已编辑)',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (isEditing)
                      TextField(
                        controller: TextEditingController(text: comment.content),
                        autofocus: true,
                        maxLines: null,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (newContent) {
                          widget.onUpdateComment?.call(comment.id, newContent);
                          setState(() => _editingCommentId = null);
                        },
                      )
                    else
                      Text(comment.content),
                    // 操作按钮
                    if (!isEditing)
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _replyToCommentId = comment.id;
                                _controller.clear();
                              });
                            },
                            child: const Text('回复', style: TextStyle(fontSize: 12)),
                          ),
                          if (isOwn) ...[
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _editingCommentId = comment.id;
                                  _controller.text = comment.content;
                                });
                              },
                              child: const Text('编辑', style: TextStyle(fontSize: 12)),
                            ),
                            TextButton(
                              onPressed: () =>
                                  widget.onDeleteComment?.call(comment.id),
                              child: Text(
                                '删除',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 回复列表
          if (comment.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 8),
              child: Column(
                children: comment.replies
                    .map((reply) => _buildReplyItem(reply))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(DatabaseComment reply) {
    final isOwn = reply.userId == widget.currentUserId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: Theme.of(context).colorScheme.secondary,
            child: Text(
              reply.username.isNotEmpty ? reply.username[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reply.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(reply.content, style: const TextStyle(fontSize: 13)),
                Text(
                  _formatTime(reply.createdAt),
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          if (isOwn)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: () => widget.onDeleteComment?.call(reply.id),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }
}
