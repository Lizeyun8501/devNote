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

  void configure(CacheType type, {int maxSize = 100, Duration? ttl}) {
    _caches[type] = LinkedHashMap<String, CacheEntry<dynamic>>();
    _maxSizes[type] = maxSize;
    _ttls[type] = ttl ?? Duration.zero;
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
