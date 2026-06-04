import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 备份结果数据类
class BackupResult {
  final bool success;
  final String message;
  final String? backupPath;
  final int? filesCount;
  final int? totalSize;
  final DateTime timestamp;

  const BackupResult({
    required this.success,
    required this.message,
    this.backupPath,
    this.filesCount,
    this.totalSize,
    required this.timestamp,
  });

  factory BackupResult.success({
    String? backupPath,
    int? filesCount,
    int? totalSize,
    String message = '备份成功',
  }) {
    return BackupResult(
      success: true,
      message: message,
      backupPath: backupPath,
      filesCount: filesCount,
      totalSize: totalSize,
      timestamp: DateTime.now(),
    );
  }

  factory BackupResult.failure(String message) {
    return BackupResult(
      success: false,
      message: message,
      timestamp: DateTime.now(),
    );
  }
}

/// 备份信息数据类
class BackupInfo {
  final String path;
  final DateTime createdAt;
  final int filesCount;
  final int totalSize;
  final String label;

  const BackupInfo({
    required this.path,
    required this.createdAt,
    required this.filesCount,
    required this.totalSize,
    this.label = '',
  });
}

/// 本地备份服务
///
/// ## 借鉴的开源项目
/// - **Joplin 备份机制** ([官方文档](https://joplinapp.org/help/apps/backup/)):
///   借鉴其基于 JEX 文件的本地备份方案，支持增量备份和定时备份
/// - **restic 增量备份** ([官网](https://restic.net/)):
///   借鉴其基于文件变更检测的增量备份策略，仅备份发生变化的文件
///
/// ## 实现说明
/// 使用本地文件系统作为备份存储，支持：
/// - 完整备份：复制所有笔记数据到备份目录
/// - 增量备份：仅备份自上次备份以来发生变更的文件
/// - 定时备份：通过 Timer 实现自动定时备份
/// - 备份恢复：从备份目录恢复数据
class BackupService {
  static const String _backupManifestFile = 'backup_manifest.json';
  Timer? _autoBackupTimer;
  BackupManifest? _lastManifest;

  /// 创建备份
  ///
  /// 借鉴 Joplin 的全量备份机制：将数据目录打包复制到指定路径
  /// 借鉴 restic 的增量备份：仅复制自上次备份后发生变化的文件
  Future<BackupResult> createBackup(String backupPath) async {
    try {
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // 获取应用数据目录
      final dataDir = await getApplicationDocumentsDirectory();
      final dataFiles = await _collectDataFiles(dataDir.path);

      // 加载上次备份清单（用于增量备份）
      final manifest = await _loadManifest(backupPath);
      final lastBackupTime = manifest?.lastBackupAt;

      int filesCopied = 0;
      int totalSize = 0;

      for (final file in dataFiles) {
        final stat = await file.stat();
        final relativePath = file.path.substring(dataDir.path.length + 1);

        // 增量备份：跳过未变更的文件（借鉴 restic 的变更检测机制）
        if (lastBackupTime != null) {
          final lastModified = manifest?.files[relativePath];
          if (lastModified != null &&
              stat.modified.millisecondsSinceEpoch <= lastModified) {
            continue;
          }
        }

        final destFile = File('$backupPath/$relativePath');
        await destFile.parent.create(recursive: true);
        await file.copy(destFile.path);
        filesCopied++;
        totalSize += stat.size;
      }

      // 保存备份清单（借鉴 Joplin 的 manifest 机制）
      await _saveManifest(backupPath, dataFiles, dataDir.path);

      return BackupResult.success(
        backupPath: backupPath,
        filesCount: filesCopied,
        totalSize: totalSize,
        message: '备份完成，共复制 $filesCopied 个文件',
      );
    } catch (e) {
      return BackupResult.failure('备份失败: $e');
    }
  }

  /// 恢复备份
  ///
  /// 借鉴 Joplin 的备份恢复机制：从备份目录还原文件到数据目录
  Future<BackupResult> restoreBackup(String backupPath) async {
    try {
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        return BackupResult.failure('备份目录不存在: $backupPath');
      }

      // 获取应用数据目录
      final dataDir = await getApplicationDocumentsDirectory();
      final backupFiles = await _collectDataFiles(backupPath);

      int filesRestored = 0;
      int totalSize = 0;

      for (final file in backupFiles) {
        final relativePath = file.path.substring(backupPath.length + 1);
        final destFile = File('${dataDir.path}/$relativePath');
        await destFile.parent.create(recursive: true);
        await file.copy(destFile.path);
        filesRestored++;
        final stat = await file.stat();
        totalSize += stat.size;
      }

      return BackupResult.success(
        filesCount: filesRestored,
        totalSize: totalSize,
        message: '恢复完成，共还原 $filesRestored 个文件',
      );
    } catch (e) {
      return BackupResult.failure('恢复失败: $e');
    }
  }

  /// 列出所有备份
  ///
  /// 遍历备份目录下的所有子目录，读取每个备份的 manifest 文件获取信息
  Future<List<BackupInfo>> listBackups(String backupDir) async {
    final backups = <BackupInfo>[];
    final dir = Directory(backupDir);

    if (!await dir.exists()) {
      return backups;
    }

    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final manifestPath = '${entity.path}/$_backupManifestFile';
        final manifestFile = File(manifestPath);

        DateTime createdAt = DateTime.now();
        int filesCount = 0;
        int totalSize = 0;
        String label = entity.path.split(Platform.pathSeparator).last;

        if (await manifestFile.exists()) {
          try {
            final content = await manifestFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            createdAt = DateTime.parse(json['createdAt'] as String);
            filesCount = (json['filesCount'] as num?)?.toInt() ?? 0;
            totalSize = (json['totalSize'] as num?)?.toInt() ?? 0;
            label = json['label'] as String? ?? label;
          } catch (_) {
            // 解析失败时使用默认值
          }
        }

        backups.add(BackupInfo(
          path: entity.path,
          createdAt: createdAt,
          filesCount: filesCount,
          totalSize: totalSize,
          label: label,
        ));
      }
    }

    // 按创建时间倒序
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  /// 设置定时自动备份
  ///
  /// 借鉴 Joplin 的定时备份机制：使用 Timer 实现周期性自动备份
  /// 默认间隔为 24 小时
  Future<void> scheduleAutoBackup({
    Duration interval = const Duration(hours: 24),
    required String backupPath,
  }) async {
    // 取消已有的定时备份
    await cancelAutoBackup();

    // 立即执行一次备份
    await createBackup(backupPath);

    // 设置定时备份（借鉴 Joplin 的自动备份机制）
    _autoBackupTimer = Timer.periodic(interval, (_) async {
      await createBackup(backupPath);
    });
  }

  /// 取消定时自动备份
  Future<void> cancelAutoBackup() async {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
  }

  /// 检查是否正在运行定时备份
  bool get isAutoBackupScheduled => _autoBackupTimer?.isActive ?? false;

  // ========== 私有方法 ==========

  /// 递归收集目录下的所有数据文件
  Future<List<File>> _collectDataFiles(String dirPath) async {
    final files = <File>[];
    final dir = Directory(dirPath);

    if (!await dir.exists()) return files;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        // 跳过备份清单文件本身
        if (entity.path.endsWith(_backupManifestFile)) continue;
        files.add(entity);
      }
    }

    return files;
  }

  /// 保存备份清单（借鉴 Joplin 的 manifest 机制）
  Future<void> _saveManifest(
    String backupPath,
    List<File> files,
    String sourceDir,
  ) async {
    final manifest = BackupManifest(
      createdAt: DateTime.now(),
      lastBackupAt: DateTime.now(),
      filesCount: files.length,
      totalSize: files.fold<int>(0, (sum, f) => sum + f.statSync().size),
      files: {
        for (final f in files)
          f.path.substring(sourceDir.length + 1):
              f.statSync().modified.millisecondsSinceEpoch,
      },
      label: 'backup_${DateTime.now().toString().substring(0, 19).replaceAll(' ', '_').replaceAll(':', '-')}',
    );

    final manifestFile = File('$backupPath/$_backupManifestFile');
    await manifestFile.writeAsString(jsonEncode(manifest.toJson()));
  }

  /// 加载备份清单
  Future<BackupManifest?> _loadManifest(String backupPath) async {
    final manifestFile = File('$backupPath/$_backupManifestFile');
    if (!await manifestFile.exists()) return null;

    try {
      final content = await manifestFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return BackupManifest.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

/// 备份清单数据类（借鉴 Joplin 的 manifest 结构）
class BackupManifest {
  final DateTime createdAt;
  final DateTime lastBackupAt;
  final int filesCount;
  final int totalSize;
  final Map<String, int> files; // relativePath -> lastModified timestamp
  final String label;

  const BackupManifest({
    required this.createdAt,
    required this.lastBackupAt,
    required this.filesCount,
    required this.totalSize,
    required this.files,
    this.label = '',
  });

  Map<String, dynamic> toJson() => {
        'createdAt': createdAt.toIso8601String(),
        'lastBackupAt': lastBackupAt.toIso8601String(),
        'filesCount': filesCount,
        'totalSize': totalSize,
        'files': files,
        'label': label,
      };

  factory BackupManifest.fromJson(Map<String, dynamic> json) =>
      BackupManifest(
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastBackupAt: DateTime.parse(json['lastBackupAt'] as String),
        filesCount: (json['filesCount'] as num).toInt(),
        totalSize: (json['totalSize'] as num).toInt(),
        files: (json['files'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
        label: json['label'] as String? ?? '',
      );
}
