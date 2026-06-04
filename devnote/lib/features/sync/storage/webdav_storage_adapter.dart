import 'dart:typed_data';

import 'webdav_adapter.dart';
import 'storage_adapter.dart';

/// WebDAV 存储适配器 —— 委托给 WebDavAdapter 实现
/// 借鉴 Nextcloud WebDAV 客户端
class WebDAVStorageAdapter implements StorageAdapter {
  final WebDavAdapter _adapter;

  WebDAVStorageAdapter({
    required String serverUrl,
    required String username,
    required String password,
    String basePath = '/devnote/',
  }) : _adapter = WebDavAdapter(WebDavConfig(
         serverUrl: serverUrl,
         username: username,
         password: password,
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
