import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:devnote/core/observability/app_logger.dart';
import 'storage_adapter.dart';

class DropboxConfig {
  final String accessToken;
  final String? basePath;

  const DropboxConfig({
    required this.accessToken,
    this.basePath,
  });

  String get effectiveBasePath => basePath ?? '/devnote-sync';
}

class DropboxAdapter implements StorageAdapter {
  DropboxAdapter(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  final DropboxConfig _config;
  final http.Client _client;
  bool _configured = false;

  static const String _apiContent = 'https://content.dropboxapi.com';
  static const String _api = 'https://api.dropboxapi.com';

  @override
  StorageAdapterType get type => StorageAdapterType.dropbox;

  @override
  String get name => 'Dropbox';

  @override
  bool get isConfigured => _configured;

  String _resolvePath(String path) => '${_config.effectiveBasePath}/$path';

  Map<String, String> _authHeaders() {
    return {'Authorization': 'Bearer ${_config.accessToken}'};
  }

  @override
  Future<bool> testConnection() async {
    try {
      final response = await _client.post(
        Uri.parse('$_api/2/users/get_current_account'),
        headers: _authHeaders(),
      );

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
      final dropboxPath = _resolvePath(path);
      final headers = _authHeaders();
      headers['content-type'] = 'application/octet-stream';
      headers['Dropbox-API-Arg'] = jsonEncode({
        'path': dropboxPath,
        'mode': 'overwrite',
        'autorename': false,
        'mute': false,
      });

      final response = await _client.post(
        Uri.parse('$_apiContent/2/files/upload'),
        headers: headers,
        body: data,
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }

  @override
  Future<Uint8List?> download(String path) async {
    try {
      final dropboxPath = _resolvePath(path);
      final headers = _authHeaders();
      headers['Dropbox-API-Arg'] = jsonEncode({'path': dropboxPath});

      final response = await _client.post(
        Uri.parse('$_apiContent/2/files/download'),
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
      final dropboxPath = _resolvePath(path);
      final headers = _authHeaders();
      headers['content-type'] = 'application/json';

      final response = await _client.post(
        Uri.parse('$_api/2/files/delete_v2'),
        headers: headers,
        body: jsonEncode({'path': dropboxPath}),
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }

  @override
  Future<List<String>> list(String prefix) async {
    try {
      final dropboxPath = _resolvePath(prefix);
      final headers = _authHeaders();
      headers['content-type'] = 'application/json';

      final response = await _client.post(
        Uri.parse('$_api/2/files/list_folder'),
        headers: headers,
        body: jsonEncode({
          'path': dropboxPath.isNotEmpty ? dropboxPath : '',
          'recursive': false,
        }),
      );

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final entries = json['entries'] as List<dynamic>;

      final files = <String>[];
      final basePath = _config.effectiveBasePath;
      for (final entry in entries) {
        final entryPath = entry['path_display'] as String;
        if (entryPath.startsWith(basePath)) {
          final relativePath =
              entryPath.substring(basePath.length).replaceAll(RegExp(r'^/+'), '');
          if (relativePath.isNotEmpty) {
            files.add(relativePath);
          }
        }
      }

      // Handle pagination if there are more entries
      var hasMore = json['has_more'] as bool? ?? false;
      var cursor = json['cursor'] as String?;

      while (hasMore && cursor != null) {
        final continueHeaders = _authHeaders();
        continueHeaders['content-type'] = 'application/json';

        final continueResponse = await _client.post(
          Uri.parse('$_api/2/files/list_folder/continue'),
          headers: continueHeaders,
          body: jsonEncode({'cursor': cursor}),
        );

        if (continueResponse.statusCode != 200) break;

        final continueJson =
            jsonDecode(continueResponse.body) as Map<String, dynamic>;
        final continueEntries = continueJson['entries'] as List<dynamic>;

        for (final entry in continueEntries) {
          final entryPath = entry['path_display'] as String;
          if (entryPath.startsWith(basePath)) {
            final relativePath =
                entryPath.substring(basePath.length).replaceAll(RegExp(r'^/+'), '');
            if (relativePath.isNotEmpty) {
              files.add(relativePath);
            }
          }
        }

        hasMore = continueJson['has_more'] as bool? ?? false;
        cursor = continueJson['cursor'] as String?;
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
      final dropboxPath = _resolvePath(path);
      final headers = _authHeaders();
      headers['content-type'] = 'application/json';

      final response = await _client.post(
        Uri.parse('$_api/2/files/get_metadata'),
        headers: headers,
        body: jsonEncode({'path': dropboxPath}),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final modified = json['server_modified'] as String?;
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
      final dropboxPath = _resolvePath(path);
      final headers = _authHeaders();
      headers['content-type'] = 'application/json';

      final response = await _client.post(
        Uri.parse('$_api/2/files/get_metadata'),
        headers: headers,
        body: jsonEncode({'path': dropboxPath}),
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.w('StorageAdapter', '操作失败', error: e);
      rethrow;
    }
  }
}
