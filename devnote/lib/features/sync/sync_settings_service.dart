// P1 修复 (P1-5): 同步设置服务
//
// 将 SyncBloc 中直接读写 SharedPreferences 的副作用外移到独立 Service，
// 使 SyncBloc 仅依赖抽象接口，便于测试与替换持久化实现。
//
// 设计要点:
// 1. 所有同步相关偏好（自动同步开关、同步间隔、服务器地址）集中管理。
// 2. 默认值与原 SyncBloc 内的常量保持一致，行为不变。
// 3. 通过构造函数注入 SyncBloc，符合依赖倒置原则。

import 'package:shared_preferences/shared_preferences.dart';

/// 持久化同步相关用户偏好的服务。
///
/// 替代 SyncBloc 内直接调用 SharedPreferences 的副作用，
/// 使 BLoC 仅负责状态转换，IO 操作下沉到 Service 层。
class SyncSettingsService {
  SyncSettingsService();

  // SharedPreferences 键名 —— 与历史版本保持一致，确保向后兼容
  static const String _keyAutoSync = 'sync_auto_sync_enabled';
  static const String _keySyncInterval = 'sync_interval_minutes';
  static const String _keyServerAddress = 'sync_server_address';

  // 默认值 —— 与原 SyncBloc 内的回退值保持一致
  static const bool defaultAutoSync = false;
  static const Duration defaultSyncInterval = Duration(minutes: 5);

  /// 读取自动同步开关。未设置时返回 [defaultAutoSync]。
  Future<bool> getAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoSync) ?? defaultAutoSync;
  }

  /// 持久化自动同步开关。
  Future<void> setAutoSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSync, enabled);
  }

  /// 读取同步间隔。未设置时返回 [defaultSyncInterval]。
  Future<Duration> getSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt(_keySyncInterval) ?? defaultSyncInterval.inMinutes;
    return Duration(minutes: minutes);
  }

  /// 持久化同步间隔（按分钟存储）。
  Future<void> setSyncInterval(Duration interval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySyncInterval, interval.inMinutes);
  }

  /// 读取同步服务器地址。未设置时返回 null。
  Future<String?> getServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerAddress);
  }

  /// 持久化同步服务器地址。传入 null 等价于删除。
  Future<void> setServerAddress(String? address) async {
    final prefs = await SharedPreferences.getInstance();
    if (address == null) {
      await prefs.remove(_keyServerAddress);
    } else {
      await prefs.setString(_keyServerAddress, address);
    }
  }

  /// 一次性加载全部同步配置，避免多次 await SharedPreferences.getInstance()。
  Future<SyncSettingsSnapshot> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return SyncSettingsSnapshot(
      autoSyncEnabled: prefs.getBool(_keyAutoSync) ?? defaultAutoSync,
      syncInterval: Duration(
        minutes: prefs.getInt(_keySyncInterval) ?? defaultSyncInterval.inMinutes,
      ),
      serverAddress: prefs.getString(_keyServerAddress),
    );
  }
}

/// 同步配置快照 —— 一次性读取的不可变视图。
class SyncSettingsSnapshot {
  const SyncSettingsSnapshot({
    required this.autoSyncEnabled,
    required this.syncInterval,
    this.serverAddress,
  });

  final bool autoSyncEnabled;
  final Duration syncInterval;
  final String? serverAddress;
}
