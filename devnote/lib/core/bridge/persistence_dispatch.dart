// 持久化分发层 —— 通过 FFI Dispatch 调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository 模式，所有持久化操作通过 FFI 桥接完成

import 'dart:convert';
import 'dart:typed_data';

import 'dispatch.dart';

class PersistenceDispatch {
  static final PersistenceDispatch _instance = PersistenceDispatch._();
  factory PersistenceDispatch() => _instance;
  PersistenceDispatch._();

  final _dispatch = Dispatch();

  Future<Map<String, dynamic>> _call(String event, Map<String, dynamic> payload) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final result = await _dispatch.asyncRequest(event, payload: bytes);

    return result.when(
      success: (data) {
        if (data.isEmpty) return {};
        try {
          return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
        } catch (_) {
          return {};
        }
      },
      failure: (error) {
        throw Exception('FFI call failed: $event - $error');
      },
    );
  }

  Future<List<Map<String, dynamic>>> list({required String entity, Map<String, dynamic>? filter}) async {
    final result = await _call('${entity}:list', filter ?? {});
    return List<Map<String, dynamic>>.from(result['items'] ?? []);
  }

  Future<Map<String, dynamic>> create({required String entity, required Map<String, dynamic> data}) async {
    return await _call('${entity}:create', data);
  }

  Future<Map<String, dynamic>> update({required String entity, required String id, required Map<String, dynamic> data}) async {
    data['id'] = id;
    return await _call('${entity}:update', data);
  }

  Future<void> delete({required String entity, required String id}) async {
    await _call('${entity}:delete', {'id': id});
  }
}