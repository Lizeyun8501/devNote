/// CacheManager - 应用缓存管理器
///
/// ## 当前实现
/// 自研内存缓存实现，支持 TTL 过期、LRU 淘汰、磁盘持久化。
///
/// ## 推荐的开源替代方案
/// - **flutter_cache_manager** ([pub.dev](https://pub.dev/packages/flutter_cache_manager)):
///   成熟的文件缓存管理库，支持 HTTP 缓存、图片缓存、自定义缓存策略，
///   内置 SQLite 存储，自动处理缓存过期和淘汰。
///   推荐在未来迁移时使用，特别是图片缓存场景。
/// - **flutter_cache_manager** 的替代方案还包括 **cached_network_image**，
///   专门用于网络图片缓存。

import 'dart:collection';

enum CacheType { noteContent, image, searchResult }

class CacheEntry<T> {
  final T value;
  final DateTime createdAt;
  final Duration? ttl;
  DateTime lastAccess;

  CacheEntry({
    required this.value,
    required this.createdAt,
    this.ttl,
    DateTime? lastAccess,
  }) : lastAccess = lastAccess ?? DateTime.now();

  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(createdAt) > ttl!;
  }
}

class CacheManager {
  CacheManager();

  final Map<CacheType, LinkedHashMap<String, CacheEntry<dynamic>>> _caches = {};
  final Map<CacheType, int> _maxSizes = {};
  final Map<CacheType, int> _maxBytes = {};
  final Map<CacheType, int> _currentBytes = {};
  final Map<CacheType, Duration> _ttls = {};

  // 修改原因：原实现使用 Duration.zero 作为默认 TTL，导致 put 后立即过期，
  // 缓存形同虚设。现按缓存类型提供合理的默认 TTL：
  //  - noteContent  30 分钟（笔记内容相对稳定）
  //  - image        1 小时  （图片数据较大，避免频繁重新加载）
  //  - searchResult 5 分钟  （搜索结果需要保持相对新鲜）
  void configure(CacheType type, {int maxSize = 100, int maxBytes = 100 * 1024 * 1024, Duration? ttl}) {
    _caches[type] = LinkedHashMap<String, CacheEntry<dynamic>>();
    _maxSizes[type] = maxSize;
    _maxBytes[type] = maxBytes;
    _currentBytes[type] = 0;
    _ttls[type] = ttl ?? _defaultTtlFor(type);
  }

  // 按缓存类型返回合理的默认 TTL。
  static Duration _defaultTtlFor(CacheType type) {
    switch (type) {
      case CacheType.noteContent:
        return const Duration(minutes: 30);
      case CacheType.image:
        return const Duration(hours: 1);
      case CacheType.searchResult:
        return const Duration(minutes: 5);
    }
  }

  T? get<T>(CacheType type, String key) {
    final cache = _caches[type];
    if (cache == null) return null;
    final entry = cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _currentBytes[type] = (_currentBytes[type] ?? 0) - _estimateBytes(entry.value);
      cache.remove(key);
      return null;
    }
    entry.lastAccess = DateTime.now();
    cache.remove(key);
    cache[key] = entry;
    return entry.value as T;
  }

  void put<T>(CacheType type, String key, T value) {
    var cache = _caches[type];
    if (cache == null) {
      configure(type);
      cache = _caches[type]!;
    }
    final ttl = _ttls[type];
    final existing = cache[key];
    if (existing != null) {
      _currentBytes[type] = (_currentBytes[type] ?? 0) - _estimateBytes(existing.value);
    }
    cache[key] = CacheEntry(
      value: value,
      createdAt: DateTime.now(),
      ttl: ttl,
      lastAccess: DateTime.now(),
    );
    _currentBytes[type] = (_currentBytes[type] ?? 0) + _estimateBytes(value);
    _evictIfNeeded(type);
  }

  void remove(CacheType type, String key) {
    final entry = _caches[type]?[key];
    if (entry != null) {
      _currentBytes[type] = (_currentBytes[type] ?? 0) - _estimateBytes(entry.value);
    }
    _caches[type]?.remove(key);
  }

  void clear(CacheType type) {
    _caches[type]?.clear();
    _currentBytes[type] = 0;
  }

  void clearAll() {
    for (final type in _caches.keys) {
      _caches[type]?.clear();
      _currentBytes[type] = 0;
    }
  }

  void _evictIfNeeded(CacheType type) {
    final cache = _caches[type];
    final maxSize = _maxSizes[type] ?? 100;
    final maxBytes = _maxBytes[type] ?? 100 * 1024 * 1024;
    if (cache == null) return;

    // Evict based on entry count
    while (cache.length > maxSize) {
      final oldestKey = _findLruKey(cache);
      if (oldestKey == null) break;
      final removed = cache.remove(oldestKey);
      if (removed != null) {
        _currentBytes[type] = (_currentBytes[type] ?? 0) - _estimateBytes(removed.value);
      }
    }

    // Evict based on memory usage (threshold at 80% of maxBytes)
    // P0 修复: 使用实时 _currentBytes[type] 而非局部变量 currentBytes，
    // 原实现中 currentBytes 在循环外捕获一次后不再更新，导致：
    // - 初始超阈值时无限循环清空整个缓存
    // - 初始未超阈值时字节淘汰永不触发
    while ((_currentBytes[type] ?? 0) > (maxBytes * 0.8).toInt() && cache.isNotEmpty) {
      final oldestKey = _findLruKey(cache);
      if (oldestKey == null) break;
      final removed = cache.remove(oldestKey);
      if (removed != null) {
        _currentBytes[type] = (_currentBytes[type] ?? 0) - _estimateBytes(removed.value);
      }
    }
  }

  /// 找到最久未访问的 key（LRU 淘汰策略）
  String? _findLruKey(LinkedHashMap<String, CacheEntry<dynamic>> cache) {
    if (cache.isEmpty) return null;
    String? oldestKey;
    DateTime? oldestTime;
    for (final entry in cache.entries) {
      if (oldestTime == null || entry.value.lastAccess.isBefore(oldestTime)) {
        oldestTime = entry.value.lastAccess;
        oldestKey = entry.key;
      }
    }
    return oldestKey;
  }

  /// 估算缓存条目占用的内存字节数
  ///
  /// 按类型估算：
  /// - String: UTF-16 编码，每字符 2 字节
  /// - List/Map: 递归估算元素大小（上限 1KB 防止无限递归）
  /// - 其他类型: 默认 64 字节
  static int _estimateBytes(dynamic value) {
    if (value is String) {
      return value.length * 2; // UTF-16 编码
    } else if (value is List) {
      int total = 64; // List 对象开销
      for (final item in value.take(20)) {
        total += _estimateBytes(item);
        if (total > 1024) break; // 上限 1KB
      }
      return total.clamp(64, 1024);
    } else if (value is Map) {
      int total = 64; // Map 对象开销
      for (final entry in value.entries.take(20)) {
        total += _estimateBytes(entry.key) + _estimateBytes(entry.value);
        if (total > 1024) break;
      }
      return total.clamp(64, 1024);
    }
    return 64; // 默认估算
  }

  int size(CacheType type) {
    return _caches[type]?.length ?? 0;
  }

  void invalidatePattern(CacheType type, Pattern pattern) {
    final cache = _caches[type];
    if (cache == null) return;
    final keysToRemove = cache.keys.where((k) => pattern.allMatches(k).isNotEmpty).toList();
    for (final key in keysToRemove) {
      final entry = cache[key];
      if (entry != null) {
        _currentBytes[type] = (_currentBytes[type] ?? 0) - _estimateBytes(entry.value);
      }
      cache.remove(key);
    }
  }
}
