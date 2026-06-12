import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 插件数据隔离器
///
/// 设计灵感来源：
/// 1. Docker 容器隔离设计 (https://www.docker.com/)
///    - 每个插件拥有独立的命名空间，互不干扰
///    - 使用 pluginId 作为隔离边界
/// 2. WebExtension storage API 隔离 (https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/storage)
///    - 每个插件拥有独立的 localStorage 空间
///    - 通过前缀键实现逻辑隔离
class PluginDataIsolator {
  /// 插件数据存储前缀，用于在共享存储中划分命名空间
  static const String _storagePrefix = 'plugin_isolated_';

  /// 插件操作日志前缀
  static const String _logPrefix = 'plugin_log_';

  /// 单例实例
  static final PluginDataIsolator _instance = PluginDataIsolator._internal();

  factory PluginDataIsolator() => _instance;

  PluginDataIsolator._internal();

  /// 构建插件隔离的存储键
  String _buildKey(String pluginId, String key) {
    return '${_storagePrefix}${pluginId}::$key';
  }

  /// 构建插件日志的存储键
  String _buildLogKey(String pluginId) {
    return '${_logPrefix}${pluginId}';
  }

  /// 为插件创建隔离的存储空间
  ///
  /// 初始化时检查存储空间是否可用，确保后续读写操作的可靠性。
  /// 借鉴 Docker 容器初始化时创建独立文件系统的机制。
  Future<void> initializeIsolatedStorage(String pluginId) async {
    // 验证 pluginId 合法性（模拟 Docker 的容器名校验）
    if (pluginId.isEmpty || pluginId.contains(RegExp(r'[^a-zA-Z0-9_\-\.]'))) {
      throw ArgumentError('Invalid pluginId: must contain only alphanumeric, underscore, hyphen, and dot');
    }

    final prefs = await SharedPreferences.getInstance();
    final logKey = _buildLogKey(pluginId);

    // 如果日志不存在则初始化空列表
    if (!prefs.containsKey(logKey)) {
      await prefs.setString(logKey, jsonEncode(<Map<String, dynamic>>[]));
    }
  }

  /// 读取插件隔离数据
  ///
  /// 借鉴 WebExtension storage.local.get API：
  /// 仅允许插件访问自己的命名空间数据，无法跨插件读取。
  Future<dynamic> getData(String pluginId, String key) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = _buildKey(pluginId, key);
    final raw = prefs.getString(storageKey);

    if (raw == null) return null;

    try {
      return jsonDecode(raw);
    } catch (_) {
      // 如果不是 JSON 格式，则返回原始字符串
      return raw;
    }
  }

  /// 写入插件隔离数据
  ///
  /// 借鉴 WebExtension storage.local.set API：
  /// 数据以 JSON 序列化后存入，支持 Map、List、primitive 类型。
  Future<void> setData(String pluginId, String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = _buildKey(pluginId, key);

    final encoded = jsonEncode(value);
    await prefs.setString(storageKey, encoded);
  }

  /// 清除插件隔离数据
  ///
  /// 借鉴 Docker 容器删除时清理所有相关资源的机制：
  /// 一次性清除该插件的所有数据和操作日志。
  Future<void> clearData(String pluginId) async {
    final prefs = await SharedPreferences.getInstance();

    // 清除所有该插件的数据键（通过前缀匹配）
    final keysToRemove = prefs
        .getKeys()
        .where((k) => k.startsWith(_buildKey(pluginId, '')) || k == _buildLogKey(pluginId))
        .toList();

    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  /// 记录插件操作日志
  ///
  /// 借鉴 Docker 容器日志收集机制：
  /// 每次操作都附带时间戳和上下文详情，便于审计与排障。
  Future<void> logAction(String pluginId, String action, Map<String, dynamic> details) async {
    final prefs = await SharedPreferences.getInstance();
    final logKey = _buildLogKey(pluginId);

    final raw = prefs.getString(logKey);
    List<Map<String, dynamic>> logs;

    if (raw == null) {
      logs = [];
    } else {
      try {
        logs = (jsonDecode(raw) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        logs = [];
      }
    }

    logs.add({
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'details': details,
    });

    await prefs.setString(logKey, jsonEncode(logs));
  }

  /// 获取插件操作日志
  ///
  /// 返回该插件的全部操作记录，按时间顺序排列。
  Future<List<Map<String, dynamic>>> getActionLog(String pluginId) async {
    final prefs = await SharedPreferences.getInstance();
    final logKey = _buildLogKey(pluginId);

    final raw = prefs.getString(logKey);
    if (raw == null) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
