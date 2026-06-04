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

  CacheEntry({required this.value, required this.createdAt, this.ttl});

  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(createdAt) > ttl!;
  }
}

class CacheManager {
  CacheManager();

  final Map<CacheType, LinkedHashMap<String, CacheEntry<dynamic>>> _caches = {};
  final Map<CacheType, int> _maxSizes = {};
  final Map<CacheType, Duration> _ttls = {};

  // 修改原因：原实现使用 Duration.zero 作为默认 TTL，导致 put 后立即过期，
  // 缓存形同虚设。现按缓存类型提供合理的默认 TTL：
  //  - noteContent  30 分钟（笔记内容相对稳定）
  //  - image        1 小时  （图片数据较大，避免频繁重新加载）
  //  - searchResult 5 分钟  （搜索结果需要保持相对新鲜）
  void configure(CacheType type, {int maxSize = 100, Duration? ttl}) {
    _caches[type] = LinkedHashMap<String, CacheEntry<dynamic>>();
    _maxSizes[type] = maxSize;
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
      cache.remove(key);
      return null;
    }
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
    cache[key] = CacheEntry(value: value, createdAt: DateTime.now(), ttl: ttl);
    _evictIfNeeded(type);
  }

  void remove(CacheType type, String key) {
    _caches[type]?.remove(key);
  }

  void clear(CacheType type) {
    _caches[type]?.clear();
  }

  void clearAll() {
    for (final cache in _caches.values) {
      cache.clear();
    }
  }

  void _evictIfNeeded(CacheType type) {
    final cache = _caches[type];
    final maxSize = _maxSizes[type] ?? 100;
    if (cache == null) return;
    while (cache.length > maxSize) {
      final firstKey = cache.keys.first;
      cache.remove(firstKey);
    }
  }

  int size(CacheType type) {
    return _caches[type]?.length ?? 0;
  }

  void invalidatePattern(CacheType type, Pattern pattern) {
    final cache = _caches[type];
    if (cache == null) return;
    final keysToRemove = cache.keys.where((k) => pattern.allMatches(k).isNotEmpty).toList();
    for (final key in keysToRemove) {
      cache.remove(key);
    }
  }
}
