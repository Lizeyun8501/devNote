import 'dart:typed_data';

enum StorageAdapterType {
  s3,
  webdav,
  dropbox,
  onedrive,
}

abstract class StorageAdapter {
  StorageAdapterType get type;
  String get name;
  bool get isConfigured;

  Future<bool> testConnection();
  Future<bool> upload(String path, Uint8List data);
  Future<Uint8List?> download(String path);
  Future<bool> delete(String path);
  Future<List<String>> list(String prefix);
  Future<DateTime?> getLastModified(String path);
  Future<bool> exists(String path);
}
