import 'dart:typed_data';

class MemoryManager {
  MemoryManager();

  final Map<String, _CacheEntry> _imageCache = {};
  final Map<String, int> _memoryUsage = {};
  int _totalMemoryUsage = 0;
  int _memoryLimit = 100 * 1024 * 1024;

  int get totalMemoryUsage => _totalMemoryUsage;
  int get memoryLimit => _memoryLimit;
  double get memoryUsageRatio => _totalMemoryUsage / _memoryLimit;

  void setMemoryLimit(int bytes) {
    _memoryLimit = bytes;
    _evictIfNeeded();
  }

  void cacheImage(String key, Uint8List data) {
    final size = data.lengthInBytes;
    _memoryUsage[key] = size;
    _totalMemoryUsage += size;
    _imageCache[key] = _CacheEntry(data: data, size: size, lastAccess: DateTime.now());
    _evictIfNeeded();
  }

  Uint8List? getImage(String key) {
    final entry = _imageCache[key];
    if (entry != null) {
      entry.lastAccess = DateTime.now();
      return entry.data;
    }
    return null;
  }

  void removeImage(String key) {
    final entry = _imageCache.remove(key);
    if (entry != null) {
      _totalMemoryUsage -= entry.size;
      _memoryUsage.remove(key);
    }
  }

  void _evictIfNeeded() {
    while (_totalMemoryUsage > _memoryLimit && _imageCache.isNotEmpty) {
      _evictOldest();
    }
  }

  void _evictOldest() {
    if (_imageCache.isEmpty) return;
    String? oldestKey;
    DateTime? oldestTime;
    for (final entry in _imageCache.entries) {
      if (oldestTime == null || entry.value.lastAccess.isBefore(oldestTime)) {
        oldestTime = entry.value.lastAccess;
        oldestKey = entry.key;
      }
    }
    if (oldestKey != null) {
      removeImage(oldestKey);
    }
  }

  void releaseCache() {
    _imageCache.clear();
    _memoryUsage.clear();
    _totalMemoryUsage = 0;
  }

  void onLowMemory() {
    final targetUsage = _memoryLimit ~/ 2;
    while (_totalMemoryUsage > targetUsage && _imageCache.isNotEmpty) {
      _evictOldest();
    }
  }

  Uint8List compressImage(Uint8List data, {int quality = 80}) {
    return data;
  }
}

class _CacheEntry {
  final Uint8List data;
  final int size;
  DateTime lastAccess;

  _CacheEntry({
    required this.data,
    required this.size,
    required this.lastAccess,
  });
}
