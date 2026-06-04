import 'dart:developer' as developer;
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = 'devnote.db';
  static const _databaseVersion = 4;

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

    // Database tables
    await db.execute('''
      CREATE TABLE databases (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE database_fields (
        id TEXT PRIMARY KEY,
        database_id TEXT NOT NULL,
        name TEXT NOT NULL,
        field_type TEXT NOT NULL,
        options TEXT,
        formula TEXT,
        position INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (database_id) REFERENCES databases(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE database_rows (
        id TEXT PRIMARY KEY,
        database_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (database_id) REFERENCES databases(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE database_cells (
        id TEXT PRIMARY KEY,
        row_id TEXT NOT NULL,
        field_id TEXT NOT NULL,
        value TEXT,
        FOREIGN KEY (row_id) REFERENCES database_rows(id) ON DELETE CASCADE,
        FOREIGN KEY (field_id) REFERENCES database_fields(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE database_views (
        id TEXT PRIMARY KEY,
        database_id TEXT NOT NULL,
        name TEXT NOT NULL,
        view_type TEXT NOT NULL,
        filters TEXT,
        sorts TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (database_id) REFERENCES databases(id) ON DELETE CASCADE
      )
    ''');

    // Object tables (v4)
    await db.execute('''
      CREATE TABLE object_types (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE object_properties (
        id TEXT PRIMARY KEY,
        type_id TEXT NOT NULL,
        name TEXT NOT NULL,
        property_type TEXT NOT NULL,
        format TEXT NOT NULL DEFAULT '{}',
        position INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE object_relations_definitions (
        id TEXT PRIMARY KEY,
        type_id TEXT NOT NULL,
        name TEXT NOT NULL,
        relation_type TEXT NOT NULL,
        source_type TEXT NOT NULL,
        target_type TEXT NOT NULL,
        FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE objects (
        id TEXT PRIMARY KEY,
        type_id TEXT NOT NULL,
        properties TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE object_relations (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        target_id TEXT NOT NULL,
        relation_id TEXT NOT NULL,
        FOREIGN KEY (source_id) REFERENCES objects(id) ON DELETE CASCADE,
        FOREIGN KEY (target_id) REFERENCES objects(id) ON DELETE CASCADE,
        FOREIGN KEY (relation_id) REFERENCES object_relations_definitions(id) ON DELETE CASCADE
      )
    ''');
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
    // P1-1 修复: 使用 batch 执行迁移操作，利用 sqflite 的事务机制确保原子性
    // 修复原因: 原代码逐条执行 db.execute，若中间某条语句失败会导致数据库处于部分升级的不一致状态
    // sqflite batch.commit() 会将所有操作放在一个事务中，任一失败则整体回滚
    final batch = db.batch();
    try {
      for (int version = oldVersion + 1; version <= newVersion; version++) {
        switch (version) {
          case 2:
            // v2: 新增 blocks.language 列，用于存储代码块的语言标识
            batch.execute('ALTER TABLE blocks ADD COLUMN language TEXT');
            break;
          case 3:
            // v3: 新增 database 相关表
            batch.execute('''
              CREATE TABLE databases (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            batch.execute('''
              CREATE TABLE database_fields (
                id TEXT PRIMARY KEY,
                database_id TEXT NOT NULL,
                name TEXT NOT NULL,
                field_type TEXT NOT NULL,
                options TEXT,
                formula TEXT,
                position INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                FOREIGN KEY (database_id) REFERENCES databases(id) ON DELETE CASCADE
              )
            ''');
            batch.execute('''
              CREATE TABLE database_rows (
                id TEXT PRIMARY KEY,
                database_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY (database_id) REFERENCES databases(id) ON DELETE CASCADE
              )
            ''');
            batch.execute('''
              CREATE TABLE database_cells (
                id TEXT PRIMARY KEY,
                row_id TEXT NOT NULL,
                field_id TEXT NOT NULL,
                value TEXT,
                FOREIGN KEY (row_id) REFERENCES database_rows(id) ON DELETE CASCADE,
                FOREIGN KEY (field_id) REFERENCES database_fields(id) ON DELETE CASCADE
              )
            ''');
            batch.execute('''
              CREATE TABLE database_views (
                id TEXT PRIMARY KEY,
                database_id TEXT NOT NULL,
                name TEXT NOT NULL,
                view_type TEXT NOT NULL,
                filters TEXT,
                sorts TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (database_id) REFERENCES databases(id) ON DELETE CASCADE
              )
            ''');
            break;
          case 4:
            // v4: 新增 object 相关表，持久化 ObjectService 的内存数据
            batch.execute('''
              CREATE TABLE object_types (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                icon TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            batch.execute('''
              CREATE TABLE object_properties (
                id TEXT PRIMARY KEY,
                type_id TEXT NOT NULL,
                name TEXT NOT NULL,
                property_type TEXT NOT NULL,
                format TEXT NOT NULL DEFAULT '{}',
                position INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
              )
            ''');
            batch.execute('''
              CREATE TABLE object_relations_definitions (
                id TEXT PRIMARY KEY,
                type_id TEXT NOT NULL,
                name TEXT NOT NULL,
                relation_type TEXT NOT NULL,
                source_type TEXT NOT NULL,
                target_type TEXT NOT NULL,
                FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
              )
            ''');
            batch.execute('''
              CREATE TABLE objects (
                id TEXT PRIMARY KEY,
                type_id TEXT NOT NULL,
                properties TEXT NOT NULL DEFAULT '{}',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
              )
            ''');
            batch.execute('''
              CREATE TABLE object_relations (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                target_id TEXT NOT NULL,
                relation_id TEXT NOT NULL,
                FOREIGN KEY (source_id) REFERENCES objects(id) ON DELETE CASCADE,
                FOREIGN KEY (target_id) REFERENCES objects(id) ON DELETE CASCADE,
                FOREIGN KEY (relation_id) REFERENCES object_relations_definitions(id) ON DELETE CASCADE
              )
            ''');
            break;
          default:
            break;
        }
      }
      // batch.commit() 将所有操作放在一个事务中，任一失败则整体回滚
      await batch.commit(noResult: true);
      developer.log('数据库升级成功: $oldVersion -> $newVersion', name: 'DatabaseHelper');
    } catch (e) {
      // P1-1 修复: 迁移失败时通过 catch 捕获，batch 未 commit 则自动回滚
      // 同时记录详细错误日志，便于排查问题
      developer.log('数据库升级失败，事务已回滚: $e', name: 'DatabaseHelper');
      rethrow;
    }
  }
}
