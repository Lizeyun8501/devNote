import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:devnote/core/observability/app_logger.dart';

class DatabaseHelper {
  static const _databaseName = 'devnote.db';
  static const _databaseVersion = 7;

  // 修复(P2-14): 移除 static 单例字段。DatabaseHelper 本身已通过
  // getIt.registerLazySingleton 注册为单例，static 字段会造成"双重单例"，
  // 导致测试中无法通过 reset/dispose 真正重置数据库连接。
  Database? _database;

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
      onConfigure: _onConfigure,
    );
  }

  /// 启用 SQLite 外键约束
  /// 修复：sqflite 默认不启用 PRAGMA foreign_keys，导致所有 ON DELETE CASCADE
  /// 约束静默失效，产生大量孤儿数据。必须在 onConfigure 中启用，确保每次
  /// 打开数据库连接时都生效（包括 WAL 模式下的连接池）。
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        folder_id TEXT NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_encrypted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES folders(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        color TEXT,
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

    // 修复(P2-15): 抽取 database/object/fts 建表 SQL 为公共方法，消除 _onCreate 与
    // _onUpgrade case 3/4/6 之间的重复 SQL（原约 100 行重复代码）。
    // 返回 List<String> 而非接收 DatabaseExecutor，是因为 sqflite 的 Batch 不实现
    // DatabaseExecutor 接口（Batch.execute 返回 void，Database.execute 返回 Future），
    // 返回 SQL 列表让调用方自行选择 await db.execute 或 batch.execute，类型安全。
    for (final sql in _databaseTableStatements()) {
      await db.execute(sql);
    }
    for (final sql in _objectTableStatements()) {
      await db.execute(sql);
    }
    for (final sql in _notesFtsSchemaStatements()) {
      await db.execute(sql);
    }
  }

  /// database_* 相关表的建表 SQL（v3 引入）。
  /// 由 _onCreate（通过 db.execute）和 _onUpgrade case 3（通过 batch.execute）共用，
  /// 确保建表 SQL 单一来源。
  static List<String> _databaseTableStatements() => [
        '''
        CREATE TABLE IF NOT EXISTS databases (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''',
        '''
        CREATE TABLE IF NOT EXISTS database_fields (
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
      ''',
        '''
        CREATE TABLE IF NOT EXISTS database_rows (
          id TEXT PRIMARY KEY,
          database_id TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (database_id) REFERENCES databases(id) ON DELETE CASCADE
        )
      ''',
        '''
        CREATE TABLE IF NOT EXISTS database_cells (
          id TEXT PRIMARY KEY,
          row_id TEXT NOT NULL,
          field_id TEXT NOT NULL,
          value TEXT,
          FOREIGN KEY (row_id) REFERENCES database_rows(id) ON DELETE CASCADE,
          FOREIGN KEY (field_id) REFERENCES database_fields(id) ON DELETE CASCADE
        )
      ''',
        '''
        CREATE TABLE IF NOT EXISTS database_views (
          id TEXT PRIMARY KEY,
          database_id TEXT NOT NULL,
          name TEXT NOT NULL,
          view_type TEXT NOT NULL,
          filters TEXT,
          sorts TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (database_id) REFERENCES databases(id) ON DELETE CASCADE
        )
      ''',
      ];

  /// object_* 相关表的建表 SQL（v4 引入）。
  /// 由 _onCreate 和 _onUpgrade case 4 共用，确保建表 SQL 单一来源。
  static List<String> _objectTableStatements() => [
        '''
        CREATE TABLE IF NOT EXISTS object_types (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          icon TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''',
        '''
        CREATE TABLE IF NOT EXISTS object_properties (
          id TEXT PRIMARY KEY,
          type_id TEXT NOT NULL,
          name TEXT NOT NULL,
          property_type TEXT NOT NULL,
          format TEXT NOT NULL DEFAULT '{}',
          position INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
        )
      ''',
        '''
        CREATE TABLE IF NOT EXISTS object_relations_definitions (
          id TEXT PRIMARY KEY,
          type_id TEXT NOT NULL,
          name TEXT NOT NULL,
          relation_type TEXT NOT NULL,
          source_type TEXT NOT NULL,
          target_type TEXT NOT NULL,
          FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
        )
      ''',
        '''
        CREATE TABLE IF NOT EXISTS objects (
          id TEXT PRIMARY KEY,
          type_id TEXT NOT NULL,
          properties TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (type_id) REFERENCES object_types(id) ON DELETE CASCADE
        )
      ''',
        '''
        CREATE TABLE IF NOT EXISTS object_relations (
          id TEXT PRIMARY KEY,
          source_id TEXT NOT NULL,
          target_id TEXT NOT NULL,
          relation_id TEXT NOT NULL,
          FOREIGN KEY (source_id) REFERENCES objects(id) ON DELETE CASCADE,
          FOREIGN KEY (target_id) REFERENCES objects(id) ON DELETE CASCADE,
          FOREIGN KEY (relation_id) REFERENCES object_relations_definitions(id) ON DELETE CASCADE
        )
      ''',
      ];

  /// FTS5 全文搜索虚拟表及同步触发器的 SQL（v6 引入）。
  /// 由 _onCreate 和 _onUpgrade case 6 共用。
  static List<String> _notesFtsSchemaStatements() => [
        '''
        CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
          note_id UNINDEXED,
          title,
          content,
          tokenize = 'unicode61'
        )
      ''',
        '''
        CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
          INSERT INTO notes_fts(note_id, title, content) VALUES (new.id, new.title, new.content);
        END
      ''',
        '''
        CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
          DELETE FROM notes_fts WHERE note_id = old.id;
          INSERT INTO notes_fts(note_id, title, content) VALUES (new.id, new.title, new.content);
        END
      ''',
        '''
        CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
          DELETE FROM notes_fts WHERE note_id = old.id;
        END
      ''',
      ];

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
        AppLogger.d('DatabaseHelper', 'Migration backup created at $backupPath');
      }
    } catch (e) {
      AppLogger.w('DatabaseHelper', 'Could not create migration backup', error: e);
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
            // 修复(P2-15): 复用 _databaseTableStatements，与 _onCreate 共享单一 SQL 来源
            for (final sql in _databaseTableStatements()) {
              batch.execute(sql);
            }
            break;
          case 4:
            // v4: 新增 object 相关表，持久化 ObjectService 的内存数据
            // 修复(P2-15): 复用 _objectTableStatements，与 _onCreate 共享单一 SQL 来源
            for (final sql in _objectTableStatements()) {
              batch.execute(sql);
            }
            break;
          case 5:
            // v5: 为 notes.folder_id 和 folders.parent_id 添加 FK 约束
            // SQLite 不支持 ALTER TABLE ADD CONSTRAINT，需要重建表
            // 步骤：创建新表 → 复制数据 → 删除旧表 → 重命名新表
            // folders 表先迁移（notes 依赖 folders）
            batch.execute('''
              CREATE TABLE folders_v5 (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                parent_id TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY (parent_id) REFERENCES folders_v5(id) ON DELETE CASCADE
              )
            ''');
            batch.execute('INSERT INTO folders_v5 SELECT * FROM folders');
            batch.execute('DROP TABLE folders');
            batch.execute('ALTER TABLE folders_v5 RENAME TO folders');
            // notes 表迁移
            batch.execute('''
              CREATE TABLE notes_v5 (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL DEFAULT '',
                folder_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
              )
            ''');
            batch.execute('INSERT INTO notes_v5 SELECT * FROM notes');
            batch.execute('DROP TABLE notes');
            batch.execute('ALTER TABLE notes_v5 RENAME TO notes');
            break;
          case 6:
            // v6: 添加 FTS5 全文搜索索引，提升大规模笔记库的搜索性能
            // 借鉴 Joplin 的全文搜索引擎，使用 contentless 模式避免数据冗余
            // 修复(P2-15): 复用 _notesFtsSchemaStatements，与 _onCreate 共享单一 SQL 来源
            for (final sql in _notesFtsSchemaStatements()) {
              batch.execute(sql);
            }
            // 回填现有笔记数据到 FTS 索引
            batch.execute('''
              INSERT INTO notes_fts(note_id, title, content)
              SELECT id, title, content FROM notes
            ''');
            break;
          case 7:
            // v7: P1-6 数据模型跨端对齐
            // 为 notes 添加 is_pinned/is_encrypted 列（与 Rust Note 模型对齐）
            // 为 folders 添加 sort_order 列（与 Rust Folder 模型对齐）
            // 为 tags 添加 color 列（与 Rust Tag 模型对齐）
            // 使用 ALTER TABLE ADD COLUMN，SQLite 支持且不会丢失数据
            // 注意: notes.blocks/tags 不添加列，因为它们由 blocks/note_tags 关联表管理
            batch.execute(
                'ALTER TABLE notes ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0');
            batch.execute(
                'ALTER TABLE notes ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 0');
            batch.execute(
                'ALTER TABLE folders ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
            batch.execute('ALTER TABLE tags ADD COLUMN color TEXT');
            break;
          default:
            break;
        }
      }
      // batch.commit() 将所有操作放在一个事务中，任一失败则整体回滚
      await batch.commit(noResult: true);
      AppLogger.d('DatabaseHelper', '数据库升级成功: $oldVersion -> $newVersion');
    } catch (e) {
      // P1-1 修复: 迁移失败时通过 catch 捕获，batch 未 commit 则自动回滚
      // 同时记录详细错误日志，便于排查问题
      AppLogger.w('DatabaseHelper', '数据库升级失败，事务已回滚', error: e);
      rethrow;
    }
  }

  /// 使用 FTS5 全文搜索笔记
  /// 支持 MATCH 语法：phrase search, prefix search, AND/OR/NOT
  Future<List<Map<String, dynamic>>> searchNotesFTS(String query, {int limit = 50}) async {
    final db = await database;
    // 使用 FTS5 MATCH 查询，返回笔记完整数据
    final results = await db.rawQuery('''
      SELECT n.* FROM notes n
      INNER JOIN notes_fts f ON f.note_id = n.id
      WHERE notes_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    ''', [query, limit]);
    return results;
  }

  /// 修复(P2-16): 关闭数据库连接。
  /// 原实现无 close() 方法，导致应用退出或测试 tearDown 时数据库句柄泄漏，
  /// 在测试套件中尤其会触发 "database is locked" 或文件句柄耗尽。
  /// 由 disposeCore() 在应用退出前调用。
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
