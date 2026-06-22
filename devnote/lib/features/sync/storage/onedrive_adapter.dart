import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:devnote/core/observability/app_logger.dart';
import 'storage_adapter.dart';

class OneDriveConfig {
  final String accessToken;
  final String? basePath;

  const OneDriveConfig({
    required this.accessToken,
    this.basePath,
  });

  String get effectiveBasePath => basePath ?? '/devnote-sync';
}

class OneDriveAdapter implements StorageAdapter {
  OneDriveAdapter(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  final OneDriveConfig _config;
  final http.Client _client;
  bool _configured = false;

  static const String _graphApi = 'https://graph.microsoft.com/v1.0/me/drive/root';

  @override
  StorageAdapterType get type => StorageAdapterType.onedrive;

  @override
  String get name => 'OneDrive';

  @override
  bool get isConfigured => _configured;

  String _resolvePath(String path) => '${_config.effectiveBasePath}/$path';

  Map<String, String> _authHeaders() {
    return {'Authorization': 'Bearer ${_config.accessToken}'};
  }

  @override
  Future<bool> testConnection() async {
    try {
      final response = await _client.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me/drive'),
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 10));

      _configured = response.statusCode == 200;
      return _configured;
    } catch (e) {
      _configured = false;
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }

  @override
  Future<bool> upload(String path, Uint8List data) async {
    try {
      final itemPath = _resolvePath(path);
      final headers = _authHeaders();
      headers['content-type'] = 'application/octet-stream';

      final response = await _client.put(
        Uri.parse('$_graphApi:$itemPath:/content'),
        headers: headers,
        body: data,
      );

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }

  @override
  Future<Uint8List?> download(String path) async {
    try {
      final itemPath = _resolvePath(path);
      final headers = _authHeaders();

      final response = await _client.get(
        Uri.parse('$_graphApi:$itemPath:/content'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }

  @override
  Future<bool> delete(String path) async {
    try {
      final itemPath = _resolvePath(path);
      final headers = _authHeaders();

      final response = await _client.delete(
        Uri.parse('$_graphApi:$itemPath'),
        headers: headers,
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }

  @override
  Future<List<String>> list(String prefix) async {
    try {
      final itemPath = _resolvePath(prefix);
      final headers = _authHeaders();

      final response = await _client.get(
        Uri.parse('$_graphApi:$itemPath:/children'),
        headers: headers,
      );

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = json['value'] as List<dynamic>;

      final files = <String>[];
      final basePath = _config.effectiveBasePath;

      for (final item in items) {
        final name = item['name'] as String;
        final parentPath = item['parentReference']?['path'] as String?;
        if (parentPath != null && parentPath.contains(basePath)) {
          files.add(name);
        } else {
          files.add(name);
        }
      }

      // Handle pagination via @odata.nextLink
      var nextLink = json['@odata.nextLink'] as String?;
      while (nextLink != null) {
        final nextResponse = await _client.get(
          Uri.parse(nextLink),
          headers: headers,
        );

        if (nextResponse.statusCode != 200) break;

        final nextJson =
            jsonDecode(nextResponse.body) as Map<String, dynamic>;
        final nextItems = nextJson['value'] as List<dynamic>;

        for (final item in nextItems) {
          final name = item['name'] as String;
          files.add(name);
        }

        nextLink = nextJson['@odata.nextLink'] as String?;
      }

      return files;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }

  @override
  Future<DateTime?> getLastModified(String path) async {
    try {
      final itemPath = _resolvePath(path);
      final headers = _authHeaders();

      final response = await _client.get(
        Uri.parse('$_graphApi:$itemPath'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final modified = json['lastModifiedDateTime'] as String?;
        if (modified != null) {
          return DateTime.parse(modified);
        }
      }
      return null;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      final itemPath = _resolvePath(path);
      final headers = _authHeaders();

      final response = await _client.get(
        Uri.parse('$_graphApi:$itemPath'),
        headers: headers,
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }
}
