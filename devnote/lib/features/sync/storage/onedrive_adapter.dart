import 'dart:typed_data';

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
  OneDriveAdapter(this._config);

  final OneDriveConfig _config;
  bool _configured = false;

  @override
  StorageAdapterType get type => StorageAdapterType.onedrive;

  @override
  String get name => 'OneDrive';

  @override
  bool get isConfigured => _configured;

  void markConfigured() {
    _configured = true;
  }

  String _resolvePath(String path) => '${_config.effectiveBasePath}/$path';

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
