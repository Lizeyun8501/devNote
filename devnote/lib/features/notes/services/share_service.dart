import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:devnote/core/config/app_config.dart';

class ShareService {
  Future<String> _getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(syncServerUrlKey) ?? defaultSyncServerUrl;
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(syncAuthTokenKey) ?? '';
  }

  /// 创建分享链接
  Future<ShareResult> createShare({
    required String noteId,
    required String title,
    required String content,
    String? password,
    Duration? expiresIn,
  }) async {
    final serverUrl = await _getServerUrl();
    final token = await _getToken();

    final response = await http
        .post(
          Uri.parse('$serverUrl/api/v1/shares'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'note_id': noteId,
            'title': title,
            'content': content,
            'password': password ?? '',
            'expires_in': expiresIn?.inSeconds ?? 0,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to create share: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ShareResult.fromJson(data);
  }

  /// 列出用户的分享
  Future<List<ShareItem>> listShares() async {
    final serverUrl = await _getServerUrl();
    final token = await _getToken();

    final response = await http
        .get(
          Uri.parse('$serverUrl/api/v1/shares'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to list shares: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final shares = data['shares'] as List;
    return shares
        .map((s) => ShareItem.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// 删除分享
  Future<void> deleteShare(String shareId) async {
    final serverUrl = await _getServerUrl();
    final token = await _getToken();

    final response = await http
        .delete(
          Uri.parse('$serverUrl/api/v1/shares/$shareId'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to delete share: ${response.statusCode}');
    }
  }
}

class ShareResult {
  final String id;
  final String shareToken;
  final String shareUrl;
  final bool hasPassword;
  final DateTime? expiresAt;
  final DateTime createdAt;

  ShareResult({
    required this.id,
    required this.shareToken,
    required this.shareUrl,
    required this.hasPassword,
    this.expiresAt,
    required this.createdAt,
  });

  factory ShareResult.fromJson(Map<String, dynamic> json) => ShareResult(
        id: json['id'] as String,
        shareToken: json['share_token'] as String,
        shareUrl: json['share_url'] as String,
        hasPassword: json['has_password'] as bool? ?? false,
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ShareItem {
  final String id;
  final String noteId;
  final String shareToken;
  final String title;
  final bool hasPassword;
  final DateTime? expiresAt;
  final int viewCount;
  final DateTime createdAt;

  ShareItem({
    required this.id,
    required this.noteId,
    required this.shareToken,
    required this.title,
    required this.hasPassword,
    this.expiresAt,
    required this.viewCount,
    required this.createdAt,
  });

  factory ShareItem.fromJson(Map<String, dynamic> json) => ShareItem(
        id: json['id'] as String,
        noteId: json['note_id'] as String,
        shareToken: json['share_token'] as String,
        title: json['title'] as String,
        hasPassword: json['has_password'] as bool? ?? false,
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
