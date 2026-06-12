import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'storage_adapter.dart';

class WebDavConfig {
  final String serverUrl;
  final String username;
  final String password;
  final String? basePath;

  const WebDavConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.basePath,
  });

  String get effectiveBasePath => basePath ?? '/devnote-sync';
}

class WebDavAdapter implements StorageAdapter {
  WebDavAdapter(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  final WebDavConfig _config;
  final http.Client _client;
  bool _configured = false;

  @override
  StorageAdapterType get type => StorageAdapterType.webdav;

  @override
  String get name => 'WebDAV (${_config.serverUrl})';

  @override
  bool get isConfigured => _configured;

  String _resolvePath(String path) => '${_config.effectiveBasePath}/$path';

  Uri _buildUri(String path) {
    final base = _config.serverUrl.replaceAll(RegExp(r'/+$'), '');
    final resolved = _resolvePath(path);
    return Uri.parse('$base$resolved');
  }

  Map<String, String> _authHeaders() {
    final credentials =
        base64Encode(utf8.encode('${_config.username}:${_config.password}'));
    return {'Authorization': 'Basic $credentials'};
  }

  /// 发送 HTTP 请求（兼容 http 包新版本，Client 不再有 request 方法）
  Future<http.Response> _request(String method, Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final request = http.Request(method, uri);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) request.body = body;
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  DateTime? _parseHttpDate(String value) {
    return DateTime.tryParse(value);
  }

  Future<bool> _ensureBasePath() async {
    final segments = _config.effectiveBasePath.split('/').where((s) => s.isNotEmpty);
    var currentPath = '';
    for (final segment in segments) {
      currentPath += '/$segment';
      final uri = Uri.parse(
        '${_config.serverUrl.replaceAll(RegExp(r'/+$'), '')}$currentPath',
      );
      final headers = _authHeaders();
      headers['content-length'] = '0';
      final response = await _request('MKCOL', uri, headers: headers);
      // 201 = created, 405 = already exists, both are fine
      if (response.statusCode != 201 && response.statusCode != 405) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<bool> testConnection() async {
    try {
      final uri = _buildUri('');
      final headers = _authHeaders();
      final response = await _request('PROPFIND', uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      _configured = response.statusCode == 207 ||
          response.statusCode == 200 ||
          response.statusCode == 404;
      return _configured;
    } catch (_) {
      _configured = false;
      return false;
    }
  }

  @override
  Future<bool> upload(String path, Uint8List data) async {
    try {
      await _ensureBasePath();

      // Ensure parent directories exist
      final parts = path.split('/');
      if (parts.length > 1) {
        var parentPath = '';
        for (var i = 0; i < parts.length - 1; i++) {
          parentPath += '/${parts[i]}';
          final uri = Uri.parse(
            '${_config.serverUrl.replaceAll(RegExp(r'/+$'), '')}${_config.effectiveBasePath}$parentPath',
          );
          final headers = _authHeaders();
          headers['content-length'] = '0';
          await _request('MKCOL', uri, headers: headers);
        }
      }

      final uri = _buildUri(path);
      final headers = _authHeaders();
      headers['content-type'] = 'application/octet-stream';
      headers['content-length'] = data.length.toString();

      final response = await _client.put(uri, headers: headers, body: data);
      return response.statusCode == 201 ||
          response.statusCode == 204 ||
          response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> download(String path) async {
    try {
      final uri = _buildUri(path);
      final headers = _authHeaders();

      final response = await _client.get(uri, headers: headers);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> delete(String path) async {
    try {
      final uri = _buildUri(path);
      final headers = _authHeaders();

      final response = await _client.delete(uri, headers: headers);
      return response.statusCode == 204 ||
          response.statusCode == 200 ||
          response.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> list(String prefix) async {
    try {
      final uri = _buildUri(prefix);
      final headers = _authHeaders();
      headers['depth'] = '1';
      headers['content-type'] = 'application/xml; charset=utf-8';

      final propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:getlastmodified/>
  </d:prop>
</d:propfind>''';

      final response = await _request(
        'PROPFIND',
        uri,
        headers: headers,
        body: propfindBody,
      );

      if (response.statusCode != 207) return [];

      final files = <String>[];
      final hrefRegex = RegExp(r'<d:href>(.*?)</d:href>');
      final basePath = _config.effectiveBasePath;
      final prefixPath = '$basePath/${prefix.replaceAll(RegExp(r'^/+|/+$'), '')}';

      for (final match in hrefRegex.allMatches(response.body)) {
        var href = Uri.decodeFull(match.group(1)!);
        // Remove trailing slash
        href = href.replaceAll(RegExp(r'/+$'), '');
        // Extract relative path
        if (href.contains(basePath)) {
          final relativePath = href.substring(href.indexOf(basePath) + basePath.length);
          if (relativePath.isNotEmpty && relativePath != '/') {
            final cleanPath = relativePath.replaceAll(RegExp(r'^/+'), '');
            // Skip the directory entry itself
            if (cleanPath != prefix.replaceAll(RegExp(r'^/+|/+$'), '') && cleanPath.isNotEmpty) {
              files.add(cleanPath);
            }
          }
        }
      }
      return files;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<DateTime?> getLastModified(String path) async {
    try {
      final uri = _buildUri(path);
      final headers = _authHeaders();
      headers['depth'] = '0';
      headers['content-type'] = 'application/xml; charset=utf-8';

      final propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:getlastmodified/>
  </d:prop>
</d:propfind>''';

      final response = await _request(
        'PROPFIND',
        uri,
        headers: headers,
        body: propfindBody,
      );

      if (response.statusCode == 207) {
        final lastModifiedMatch =
            RegExp(r'<d:getlastmodified>(.*?)</d:getlastmodified>')
                .firstMatch(response.body);
        if (lastModifiedMatch != null) {
          return _parseHttpDate(lastModifiedMatch.group(1)!);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      final uri = _buildUri(path);
      final headers = _authHeaders();

      final response = await _client.head(uri, headers: headers);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
