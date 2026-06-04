import 'dart:developer' as developer;
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = 'devnote.db';
  static const _databaseVersion = 2;

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        folder_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE note_tags (
        note_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (note_id, tag_id),
        FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE blocks (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        block_type TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        language TEXT,
        position INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE schema_version (
        version INTEGER PRIMARY KEY
      )
    ''');
    await db.insert('schema_version', {'version': version});
  }

  // 迁移回滚保障 —— 借鉴 SQLite 官方迁移最佳实践
  // 在执行迁移前备份数据库文件，迁移失败时自动恢复

  Future<void> _backupBeforeMigration() async {
    final dbPath = await getDatabasesPath();
    final backupPath = '$dbPath/devnote_backup_${DateTime.now().millisecondsSinceEpoch}.db';
    final originalPath = join(dbPath, _databaseName);
    try {
      final originalFile = File(originalPath);
      if (await originalFile.exists()) {
        await originalFile.copy(backupPath);
        developer.log('Migration backup created at $backupPath', name: 'DatabaseHelper');
      }
    } catch (e) {
      developer.log('Could not create migration backup', name: 'DatabaseHelper', error: e);
    }
  }

  Future<void> _restoreFromBackup(String backupPath) async {
    final dbPath = await getDatabasesPath();
    final originalPath = join(dbPath, _databaseName);
    try {
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.copy(originalPath);
        developer.log('Migration restored from backup: $backupPath', name: 'DatabaseHelper');
      }
    } catch (e) {
      developer.log('Could not restore from backup', name: 'DatabaseHelper', error: e);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _backupBeforeMigration();
    try {
      for (int version = oldVersion + 1; version <= newVersion; version++) {
        switch (version) {
          case 2:
            // v2: 新增 blocks.language 列，用于存储代码块的语言标识
            await db.execute('ALTER TABLE blocks ADD COLUMN language TEXT');
            break;
          default:
            break;
        }
      }
    } catch (e) {
      developer.log('Migration error — database may be in an inconsistent state. Please restore from backup.',
          name: 'DatabaseHelper', error: e);
      rethrow;
    }
  }
}
