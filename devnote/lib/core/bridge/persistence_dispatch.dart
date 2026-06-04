// 持久化分发层 —— 通过 FFI Dispatch 调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository 模式，所有持久化操作通过 FFI 桥接完成
//
// 借鉴 AppFlowy 的 Repository + FFI 模式
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 通过 FFI 桥接调 Rust 持久化层、entity → event 路由
//
// 事件命名约定: entity="note" → "NoteEvent.*", entity="folder" → "FolderEvent.*",
// entity="tag" → "TagEvent.*", entity="block" → "EditorEvent.*"
// 与 rust-core/devnote-ffi/src/handlers.rs 中 register_handler 注册的
// 事件名严格一致。

import 'dart:convert';
import 'dart:typed_data';

import 'dispatch.dart';

/// 实体类型 → Rust 端事件命名空间映射
/// 借鉴 AppFlowy 的事件命名空间隔离设计 —— 每个业务域独立命名空间
/// 来源: https://github.com/AppFlowy-IO/AppFlowy
class _EntityEventMap {
  static const Map<String, String> _namespace = {
    'note': 'NoteEvent',
    'folder': 'FolderEvent',
    'tag': 'TagEvent',
    'block': 'EditorEvent',
  };

  /// 根据实体名和动作名构造 Rust 端注册的事件名
  /// 例如: ("note", "list") → "NoteEvent.ListNotes"
  static String resolve(String entity, String action) {
    final ns = _namespace[entity] ?? '${entity[0].toUpperCase()}${entity.substring(1)}Event';
    final verb = _actionToVerb(action);
    return '$ns.$verb';
  }

  /// 动作名 → 事件动词转换
  /// list  → List<entity>s (复数)
  /// create → Create<entity>
  /// update → Update<entity>
  /// delete → Delete<entity>
  /// get   → Get<entity>
  static String _actionToVerb(String action) {
    switch (action) {
      case 'list':
        return 'List';
      case 'create':
        return 'Create';
      case 'update':
        return 'Update';
      case 'delete':
        return 'Delete';
      case 'get':
        return 'Get';
      default:
        return action[0].toUpperCase() + action.substring(1);
    }
  }

  /// 实体名 → 单数类型名（用于 Create/Get/Update/Delete 事件）
  static String entityName(String entity) {
    switch (entity) {
      case 'note':
        return 'Note';
      case 'folder':
        return 'Folder';
      case 'tag':
        return 'Tag';
      case 'block':
        return 'Block';
      default:
        return entity[0].toUpperCase() + entity.substring(1);
    }
  }
}

class PersistenceDispatch {
  static final PersistenceDispatch _instance = PersistenceDispatch._();
  factory PersistenceDispatch() => _instance;
  PersistenceDispatch._();

  final _dispatch = Dispatch();

  /// 通用 FFI 调用: 发送事件到 Rust 并解析响应
  Future<Map<String, dynamic>> _call(String event, Map<String, dynamic> payload) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final result = await _dispatch.asyncRequest(event, payload: bytes);

    return result.when(
      success: (data) {
        if (data.isEmpty) return {};
        try {
          final decoded = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
          // 兼容两种返回格式：{code, message, data} 或 {code, message, data: '<json string>'}
          final innerData = decoded['data'];
          if (innerData is String) {
            try {
              return jsonDecode(innerData) as Map<String, dynamic>;
            } catch (_) {
              return {'value': innerData};
            }
          }
          return decoded;
        } catch (_) {
          return {};
        }
      },
      failure: (error) {
        throw Exception('FFI call failed: $event - $error');
      },
    );
  }

  /// 列表查询: Rust 端 List<entity>s 事件返回的 data 字段是 JSON 数组字符串
  Future<List<Map<String, dynamic>>> list({required String entity, Map<String, dynamic>? filter}) async {
    final event = '${_EntityEventMap.entityName(entity)}Event.List${_EntityEventMap.entityName(entity)}s';
    final result = await _call(event, filter ?? {});

    if (result['data'] is String) {
      try {
        final list = jsonDecode(result['data'] as String) as List<dynamic>;
        return list.cast<Map<String, dynamic>>();
      } catch (_) {
        return [];
      }
    }
    if (result['data'] is List) {
      return (result['data'] as List).cast<Map<String, dynamic>>();
    }
    return List<Map<String, dynamic>>.from(result['items'] ?? const []);
  }

  Future<Map<String, dynamic>> create({required String entity, required Map<String, dynamic> data}) async {
    final event = '${_EntityEventMap.entityName(entity)}Event.Create${_EntityEventMap.entityName(entity)}';
    return await _call(event, data);
  }

  Future<Map<String, dynamic>> update({required String entity, required String id, required Map<String, dynamic> data}) async {
    data['id'] = id;
    final event = '${_EntityEventMap.entityName(entity)}Event.Update${_EntityEventMap.entityName(entity)}';
    return await _call(event, data);
  }

  Future<void> delete({required String entity, required String id}) async {
    final event = '${_EntityEventMap.entityName(entity)}Event.Delete${_EntityEventMap.entityName(entity)}';
    await _call(event, {'id': id});
  }
}
