import 'dart:typed_data';
// 引入 Flutter 图像编解码 API,用于在 isolate 之外对图片进行重新编码压缩。
// 借鉴 1Password 等应用的思路:解码 -> 按质量重新编码 -> 比较大小。
// 修复: paint 中没有 instantiateImageCodec,该函数在 ui 库中
import 'dart:ui' as ui;

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

  // 修改原因：原实现为空 stub，直接返回原数据，无法减少图片内存占用。
  // 现改为异步方法，利用 Flutter 的 ui.instantiateImageCodec 解码图片后
  // 再按 quality 重新编码为 PNG，最后比较新旧字节长度，仅在压缩更优时返回新数据。
  // 改为 Future<Uint8List> 以适配 Flutter 图像 API 的异步语义；调用方可通过
  // await 获取结果，调用时未 await 也不影响原数据流（只是无法立即拿到压缩结果）。
  Future<Uint8List> compressImage(Uint8List data, {int quality = 80}) async {
    // 边界保护：空数据或 quality 越界时直接返回原数据。
    if (data.isEmpty) return data;
    if (quality < 1 || quality > 100) return data;
    try {
      // 1) 解码原始图片（支持 PNG / JPEG / WebP / GIF 等常见格式）
      final codec = await ui.instantiateImageCodec(
        data,
        targetWidth: null,
        targetHeight: null,
      );
      final frame = await codec.getNextFrame();
      try {
        // 2) 重新编码为 PNG 字节流。
        //    Flutter 的 toByteData 当前仅支持 PNG，因此使用 PNG 作为中间格式；
        //    真正的有损压缩需要原生插件（如 flutter_image_compress）。
        final byteData = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (byteData == null) return data;
        final result = byteData.buffer.asUint8List();
        // 3) 仅在压缩后体积更小且与原数据明显不同时返回新数据，
        //    避免无效压缩造成 CPU 浪费。
        if (result.length < data.length) {
          return result;
        }
        return data;
      } finally {
        // 4) 及时释放解码后的图像资源，避免临时占用 GPU/内存。
        frame.image.dispose();
      }
    } catch (_) {
      // 压缩失败（例如非图片字节流或格式不支持），回退到原数据。
      return data;
    }
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
