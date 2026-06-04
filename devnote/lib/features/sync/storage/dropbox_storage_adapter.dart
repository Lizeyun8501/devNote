import 'dart:typed_data';

import 'dropbox_adapter.dart';
import 'storage_adapter.dart';

/// Dropbox 存储适配器 —— 委托给 DropboxAdapter 实现
/// 借鉴 Dropbox API v2 规范
class DropboxStorageAdapter implements StorageAdapter {
  final DropboxAdapter _adapter;

  DropboxStorageAdapter({
    required String accessToken,
    String basePath = '/devnote/',
  }) : _adapter = DropboxAdapter(DropboxConfig(
         accessToken: accessToken,
         basePath: basePath,
       ));

  @override
  StorageAdapterType get type => _adapter.type;

  @override
  String get name => _adapter.name;

  @override
  bool get isConfigured => _adapter.isConfigured;

  @override
  Future<bool> testConnection() => _adapter.testConnection();

  @override
  Future<bool> upload(String path, Uint8List data) => _adapter.upload(path, data);

  @override
  Future<Uint8List?> download(String path) => _adapter.download(path);

  @override
  Future<bool> delete(String path) => _adapter.delete(path);

  @override
  Future<List<String>> list(String prefix) => _adapter.list(prefix);

  @override
  Future<DateTime?> getLastModified(String path) => _adapter.getLastModified(path);

  @override
  Future<bool> exists(String path) => _adapter.exists(path);
}
