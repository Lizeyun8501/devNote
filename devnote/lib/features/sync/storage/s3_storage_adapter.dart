import 'dart:typed_data';

import 's3_adapter.dart';
import 'storage_adapter.dart';

/// S3 兼容存储适配器 —— 委托给 S3Adapter 实现
/// 借鉴 MinIO SDK 的签名算法
class S3StorageAdapter implements StorageAdapter {
  final S3Adapter _adapter;

  S3StorageAdapter({
    required String endpoint,
    required String bucket,
    required String accessKey,
    required String secretKey,
    String? region,
  }) : _adapter = S3Adapter(S3Config(
         endpoint: endpoint,
         region: region ?? 'us-east-1',
         bucket: bucket,
         accessKey: accessKey,
         secretKey: secretKey,
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
