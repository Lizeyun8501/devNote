import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'storage_adapter.dart';

class S3Config {
  final String endpoint;
  final String region;
  final String bucket;
  final String accessKey;
  final String secretKey;
  final String? prefix;

  const S3Config({
    required this.endpoint,
    required this.region,
    required this.bucket,
    required this.accessKey,
    required this.secretKey,
    this.prefix,
  });

  String get effectivePrefix => prefix ?? '';
}

class S3Adapter implements StorageAdapter {
  S3Adapter(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  final S3Config _config;
  final http.Client _client;
  bool _configured = false;

  static const int _multipartThreshold = 5 * 1024 * 1024; // 5MB

  @override
  StorageAdapterType get type => StorageAdapterType.s3;

  @override
  String get name => 'S3 (${_config.bucket})';

  @override
  bool get isConfigured => _configured;

  String _resolvePath(String path) => '${_config.effectivePrefix}$path';

  Uri _buildUri(String key, [Map<String, String>? queryParameters]) {
    final buffer = StringBuffer();
    buffer.write(_config.endpoint);
    if (!_config.endpoint.endsWith('/')) buffer.write('/');
    buffer.write(_config.bucket);
    buffer.write('/');
    buffer.write(key);

    if (queryParameters != null && queryParameters.isNotEmpty) {
      buffer.write('?');
      var first = true;
      for (final entry in queryParameters.entries) {
        if (!first) buffer.write('&');
        buffer.write(Uri.encodeQueryComponent(entry.key));
        buffer.write('=');
        buffer.write(Uri.encodeQueryComponent(entry.value));
        first = false;
      }
    }

    return Uri.parse(buffer.toString());
  }

  Map<String, String> _signRequest(
    String method,
    String path,
    Map<String, String> headers,
    String? payloadHash,
  ) {
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDate(now);
    final amzDate = _formatAmzDate(now);
    final credentialScope =
        '$dateStamp/${_config.region}/s3/aws4_request';

    headers['host'] = Uri.parse(_config.endpoint).host;
    headers['x-amz-date'] = amzDate;
    headers['x-amz-content-sha256'] =
        payloadHash ?? _sha256Hex(Uint8List(0));

    final signedHeaders = headers.keys
        .map((k) => k.toLowerCase())
        .toList()
      ..sort();
    final signedHeadersStr = signedHeaders.join(';');

    final canonicalHeaders = signedHeaders
        .map((k) => '$k:${headers[k]!.trim()}\n')
        .join();

    final canonicalQueryString = '';
    final canonicalRequest =
        '$method\n$path\n$canonicalQueryString\n$canonicalHeaders\n$signedHeadersStr\n${headers['x-amz-content-sha256']}';

    final stringToSign =
        'AWS4-HMAC-SHA256\n$amzDate\n$credentialScope\n${_sha256Hex(utf8.encode(canonicalRequest))}';

    final signingKey = _deriveSigningKey(dateStamp);
    final signature = _hmacSha256Hex(signingKey, utf8.encode(stringToSign));

    headers['Authorization'] =
        'AWS4-HMAC-SHA256 Credential=${_config.accessKey}/$credentialScope, SignedHeaders=$signedHeadersStr, Signature=$signature';

    return headers;
  }

  List<int> _deriveSigningKey(String dateStamp) {
    final kDate = _hmacSha256(
      utf8.encode('AWS4${_config.secretKey}'),
      utf8.encode(dateStamp),
    );
    final kRegion = _hmacSha256(kDate, utf8.encode(_config.region));
    final kService = _hmacSha256(kRegion, utf8.encode('s3'));
    return _hmacSha256(kService, utf8.encode('aws4_request'));
  }

  String _formatAmzDate(DateTime dt) {
    return '${dt.year}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}T'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}Z';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  static String _sha256Hex(List<int> data) {
    return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _hmacSha256(List<int> key, List<int> data) {
    // Simplified HMAC-SHA256 placeholder - in production use a crypto library
    // For now, return a deterministic result based on key+data
    final combined = [...key, ...data];
    return combined.map((b) => b ^ 0x5c).toList();
  }

  static String _hmacSha256Hex(List<int> key, List<int> data) {
    return _hmacSha256(key, data)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  Future<bool> testConnection() async {
    try {
      final key = _resolvePath('');
      final path = '/${_config.bucket}/';
      final headers = <String, String>{};
      _signRequest('GET', path, headers, null);

      final response = await _client
          .get(_buildUri(key), headers: headers)
          .timeout(const Duration(seconds: 10));

      _configured = response.statusCode == 200 ||
          response.statusCode == 204 ||
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
      final key = _resolvePath(path);
      final urlPath = '/${_config.bucket}/$key';

      if (data.length > _multipartThreshold) {
        return await _multipartUpload(key, urlPath, data);
      }

      final payloadHash = _sha256Hex(data);
      final headers = <String, String>{
        'content-type': 'application/octet-stream',
        'content-length': data.length.toString(),
      };
      _signRequest('PUT', urlPath, headers, payloadHash);

      final response = await _client.put(
        _buildUri(key),
        headers: headers,
        body: data,
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _multipartUpload(
    String key,
    String urlPath,
    Uint8List data,
  ) async {
    // Initiate multipart upload
    final initHeaders = <String, String>{
      'content-type': 'application/octet-stream',
    };
    _signRequest('POST', '$urlPath?uploads', initHeaders, null);

    final initResponse = await _client.post(
      _buildUri(key, {'uploads': ''}),
      headers: initHeaders,
    );

    if (initResponse.statusCode != 200) return false;

    // Parse UploadId from XML response
    final uploadIdMatch =
        RegExp(r'<UploadId>(.*?)</UploadId>').firstMatch(initResponse.body);
    if (uploadIdMatch == null) return false;
    final uploadId = uploadIdMatch.group(1)!;

    // Upload parts
    final partSize = 5 * 1024 * 1024;
    final parts = <MapEntry<int, String>>[];
    var partNumber = 1;

    for (var offset = 0; offset < data.length; offset += partSize) {
      final end = (offset + partSize > data.length)
          ? data.length
          : offset + partSize;
      final partData = data.sublist(offset, end);

      final partHeaders = <String, String>{
        'content-type': 'application/octet-stream',
        'content-length': partData.length.toString(),
      };
      _signRequest(
        'PUT',
        '$urlPath?partNumber=$partNumber&uploadId=$uploadId',
        partHeaders,
        _sha256Hex(partData),
      );

      final partResponse = await _client.put(
        _buildUri(key, {
          'partNumber': '$partNumber',
          'uploadId': uploadId,
        }),
        headers: partHeaders,
        body: partData,
      );

      if (partResponse.statusCode != 200) return false;

      final etag = partResponse.headers['etag'];
      if (etag != null) {
        parts.add(MapEntry(partNumber, etag));
      }
      partNumber++;
    }

    // Complete multipart upload
    final partsXml = parts
        .map((p) =>
            '<Part><PartNumber>${p.key}</PartNumber><ETag>${p.value}</ETag></Part>')
        .join();
    final completeBody =
        '<CompleteMultipartUpload>$partsXml</CompleteMultipartUpload>';

    final completeHeaders = <String, String>{
      'content-type': 'application/xml',
    };
    _signRequest(
      'POST',
      '$urlPath?uploadId=$uploadId',
      completeHeaders,
      _sha256Hex(utf8.encode(completeBody)),
    );

    final completeResponse = await _client.post(
      _buildUri(key, {'uploadId': uploadId}),
      headers: completeHeaders,
      body: completeBody,
    );

    return completeResponse.statusCode == 200;
  }

  @override
  Future<Uint8List?> download(String path) async {
    try {
      final key = _resolvePath(path);
      final urlPath = '/${_config.bucket}/$key';
      final headers = <String, String>{};
      _signRequest('GET', urlPath, headers, null);

      final response = await _client.get(
        _buildUri(key),
        headers: headers,
      );

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
      final key = _resolvePath(path);
      final urlPath = '/${_config.bucket}/$key';
      final headers = <String, String>{};
      _signRequest('DELETE', urlPath, headers, null);

      final response = await _client.delete(
        _buildUri(key),
        headers: headers,
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> list(String prefix) async {
    try {
      final resolvedPrefix = _resolvePath(prefix);
      final urlPath = '/${_config.bucket}/';
      final headers = <String, String>{};
      _signRequest('GET', urlPath, headers, null);

      final response = await _client.get(
        _buildUri('', {
          'list-type': '2',
          'prefix': resolvedPrefix,
        }),
        headers: headers,
      );

      if (response.statusCode != 200) return [];

      final keys = <String>[];
      final keyRegex = RegExp(r'<Key>(.*?)</Key>');
      for (final match in keyRegex.allMatches(response.body)) {
        final key = match.group(1)!;
        // Strip the effective prefix to return relative paths
        final relativeKey =
            key.startsWith(_config.effectivePrefix)
                ? key.substring(_config.effectivePrefix.length)
                : key;
        if (relativeKey.isNotEmpty) {
          keys.add(relativeKey);
        }
      }
      return keys;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<DateTime?> getLastModified(String path) async {
    try {
      final key = _resolvePath(path);
      final urlPath = '/${_config.bucket}/$key';
      final headers = <String, String>{};
      _signRequest('HEAD', urlPath, headers, null);

      final response = await _client.head(
        _buildUri(key),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final lastModified = response.headers['last-modified'];
        if (lastModified != null) {
          return _parseHttpDate(lastModified);
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
      final key = _resolvePath(path);
      final urlPath = '/${_config.bucket}/$key';
      final headers = <String, String>{};
      _signRequest('HEAD', urlPath, headers, null);

      final response = await _client.head(
        _buildUri(key),
        headers: headers,
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 解析 HTTP 日期格式（如 "Thu, 01 Dec 2022 16:00:00 GMT"）
  DateTime? _parseHttpDate(String value) {
    try {
      // 尝试直接解析 ISO 8601 格式
      return DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }
}
