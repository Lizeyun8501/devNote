import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:devnote/core/config/app_config.dart';

class VersionHistoryService {
  /// 获取笔记版本历史
  Future<List<VersionItem>> getNoteHistory(String noteId, {int limit = 50}) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(syncServerUrlKey) ?? defaultSyncServerUrl;
    final token = prefs.getString(syncAuthTokenKey) ?? '';

    final response = await http.get(
      Uri.parse('$serverUrl/api/v1/sync/notes/$noteId/history?limit=$limit'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to load version history: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final versions = data['versions'] as List;
    return versions
        .map((v) => VersionItem.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  /// 获取特定版本
  Future<VersionItem> getNoteVersion(String noteId, int version) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(syncServerUrlKey) ?? defaultSyncServerUrl;
    final token = prefs.getString(syncAuthTokenKey) ?? '';

    final response = await http.get(
      Uri.parse('$serverUrl/api/v1/sync/notes/$noteId/versions/$version'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to load version: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return VersionItem.fromJson(data);
  }
}

/// 版本条目
class VersionItem {
  final int version;
  final String content;
  final String checksum;
  final DateTime createdAt;

  VersionItem({
    required this.version,
    required this.content,
    required this.checksum,
    required this.createdAt,
  });

  factory VersionItem.fromJson(Map<String, dynamic> json) => VersionItem(
    version: (json['version'] as num).toInt(),
    content: json['content'] as String? ?? '',
    checksum: json['checksum'] as String? ?? '',
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.now(),
  );
}
