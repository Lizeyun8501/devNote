import 'dart:typed_data';

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
  S3Adapter(this._config);

  final S3Config _config;
  bool _configured = false;

  @override
  StorageAdapterType get type => StorageAdapterType.s3;

  @override
  String get name => 'S3 (${_config.bucket})';

  @override
  bool get isConfigured => _configured;

  void markConfigured() {
    _configured = true;
  }

  String _resolvePath(String path) => '${_config.effectivePrefix}$path';

  @override
  Future<bool> testConnection() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      _configured = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> upload(String path, Uint8List data) async {
    try {
      _resolvePath(path);
      await Future.delayed(const Duration(milliseconds: 50));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> download(String path) async {
    try {
      _resolvePath(path);
      await Future.delayed(const Duration(milliseconds: 50));
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> delete(String path) async {
    try {
      _resolvePath(path);
      await Future.delayed(const Duration(milliseconds: 50));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> list(String prefix) async {
    try {
      _resolvePath(prefix);
      await Future.delayed(const Duration(milliseconds: 50));
      return [];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<DateTime?> getLastModified(String path) async {
    try {
      _resolvePath(path);
      await Future.delayed(const Duration(milliseconds: 50));
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      _resolvePath(path);
      await Future.delayed(const Duration(milliseconds: 50));
      return false;
    } catch (_) {
      return false;
    }
  }
}
