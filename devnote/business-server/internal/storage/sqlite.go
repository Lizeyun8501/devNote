package storage

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/sqlite3"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/jmoiron/sqlx"
	_ "github.com/mattn/go-sqlite3"
)

// SQLiteStore wraps a sqlx.DB connection and provides CRUD operations
// for all business-server domain entities.
type SQLiteStore struct {
	DB *sqlx.DB
}

// NewSQLiteStore opens (or creates) a SQLite database at the given path
// and runs schema migrations via golang-migrate.
func NewSQLiteStore(dbPath, migrationsPath string) (*SQLiteStore, error) {
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create db dir: %w", err)
	}

	db, err := sqlx.Open("sqlite3", dbPath+"?_journal_mode=WAL&_foreign_keys=on")
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}

	// P0 修复: SQLite 连接池配置
	// SQLite 是文件级锁，多写连接会导致 SQLITE_BUSY。
	// WAL 模式允许并发读，但写仍串行。
	// 设置 MaxOpenConns=1 确保写操作串行化，避免 BUSY 错误。
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(0) // 永不过期

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping sqlite: %w", err)
	}

	// P0 修复: 设置 busy_timeout，写冲突时等待 5 秒而非立即返回 BUSY
	if _, err := db.Exec("PRAGMA busy_timeout = 5000;"); err != nil {
		return nil, fmt.Errorf("set busy_timeout: %w", err)
	}

	store := &SQLiteStore{DB: db}
	if err := store.migrate(migrationsPath); err != nil {
		return nil, fmt.Errorf("migrate: %w", err)
	}

	return store, nil
}

func (s *SQLiteStore) Close() error {
	return s.DB.Close()
}

// migrate runs golang-migrate migrations from the given source path.
func (s *SQLiteStore) migrate(migrationsPath string) error {
	m, err := migrate.New(
		"file://"+migrationsPath,
		"sqlite3://"+s.DB.DriverName(),
	)
	if err != nil {
		// Fallback: if migrate instance creation fails, run inline schema
		return s.migrateInline()
	}
	defer m.Close()

	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		return fmt.Errorf("apply migrations: %w", err)
	}
	return nil
}

// migrateInline is a fallback that runs the schema directly when
// golang-migrate source files are not available (e.g. in tests).
func (s *SQLiteStore) migrateInline() error {
	schema := `
	CREATE TABLE IF NOT EXISTS note_meta (
		id            TEXT PRIMARY KEY,
		user_id       TEXT NOT NULL,
		title         TEXT NOT NULL DEFAULT '',
		author        TEXT NOT NULL DEFAULT '',
		created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		modified_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		word_count    INTEGER NOT NULL DEFAULT 0,
		char_count    INTEGER NOT NULL DEFAULT 0,
		format        TEXT NOT NULL DEFAULT 'markdown',
		excerpt       TEXT NOT NULL DEFAULT '',
		language      TEXT NOT NULL DEFAULT 'en',
		is_encrypted  INTEGER NOT NULL DEFAULT 0,
		content_hash  TEXT NOT NULL DEFAULT '',
		custom_fields TEXT NOT NULL DEFAULT '{}'
	);

	CREATE TABLE IF NOT EXISTS folder_meta (
		id          TEXT PRIMARY KEY,
		user_id     TEXT NOT NULL,
		name        TEXT NOT NULL DEFAULT '',
		parent_id   TEXT NOT NULL DEFAULT '',
		path        TEXT NOT NULL DEFAULT '',
		description TEXT NOT NULL DEFAULT '',
		icon        TEXT NOT NULL DEFAULT '',
		color       TEXT NOT NULL DEFAULT '',
		sort_order  INTEGER NOT NULL DEFAULT 0,
		created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		note_count  INTEGER NOT NULL DEFAULT 0,
		child_count INTEGER NOT NULL DEFAULT 0
	);

	CREATE TABLE IF NOT EXISTS tag_meta (
		id          TEXT PRIMARY KEY,
		user_id     TEXT NOT NULL,
		name        TEXT NOT NULL DEFAULT '',
		parent_id   TEXT NOT NULL DEFAULT '',
		color       TEXT NOT NULL DEFAULT '',
		description TEXT NOT NULL DEFAULT '',
		created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		use_count   INTEGER NOT NULL DEFAULT 0
	);

	CREATE TABLE IF NOT EXISTS tag_relation (
		id       TEXT PRIMARY KEY,
		tag_id   TEXT NOT NULL,
		note_id  TEXT NOT NULL,
		linked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		FOREIGN KEY (tag_id) REFERENCES tag_meta(id) ON DELETE CASCADE
	);

	CREATE TABLE IF NOT EXISTS knowledge_relation (
		id               TEXT PRIMARY KEY,
		user_id          TEXT NOT NULL,
		source_note_id   TEXT NOT NULL,
		target_note_id   TEXT NOT NULL,
		weight           REAL NOT NULL DEFAULT 0.0,
		reference_count  INTEGER NOT NULL DEFAULT 0,
		relation_type    TEXT NOT NULL DEFAULT 'link',
		created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS validation_rule (
		id          TEXT PRIMARY KEY,
		user_id     TEXT NOT NULL DEFAULT '',
		name        TEXT NOT NULL DEFAULT '',
		description TEXT NOT NULL DEFAULT '',
		category    TEXT NOT NULL DEFAULT '',
		rule_type   TEXT NOT NULL DEFAULT '',
		pattern     TEXT NOT NULL DEFAULT '',
		severity    TEXT NOT NULL DEFAULT 'warning',
		is_enabled  INTEGER NOT NULL DEFAULT 1,
		created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS business_rule (
		id         TEXT PRIMARY KEY,
		user_id    TEXT NOT NULL DEFAULT '',
		name       TEXT NOT NULL DEFAULT '',
		expression TEXT NOT NULL DEFAULT '',
		action     TEXT NOT NULL DEFAULT '',
		priority   INTEGER NOT NULL DEFAULT 0,
		is_enabled INTEGER NOT NULL DEFAULT 1,
		created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_note_meta_title ON note_meta(title);
	CREATE INDEX IF NOT EXISTS idx_note_meta_author ON note_meta(author);
	CREATE INDEX IF NOT EXISTS idx_note_meta_user_id ON note_meta(user_id);
	CREATE INDEX IF NOT EXISTS idx_folder_meta_parent ON folder_meta(parent_id);
	CREATE INDEX IF NOT EXISTS idx_folder_meta_user_id ON folder_meta(user_id);
	CREATE INDEX IF NOT EXISTS idx_tag_meta_parent ON tag_meta(parent_id);
	CREATE INDEX IF NOT EXISTS idx_tag_meta_user_id ON tag_meta(user_id);
	CREATE INDEX IF NOT EXISTS idx_tag_relation_tag ON tag_relation(tag_id);
	CREATE INDEX IF NOT EXISTS idx_tag_relation_note ON tag_relation(note_id);
	CREATE INDEX IF NOT EXISTS idx_knowledge_source ON knowledge_relation(source_note_id);
	CREATE INDEX IF NOT EXISTS idx_knowledge_target ON knowledge_relation(target_note_id);
	CREATE INDEX IF NOT EXISTS idx_knowledge_relation_user_id ON knowledge_relation(user_id);
	CREATE INDEX IF NOT EXISTS idx_validation_rule_user_id ON validation_rule(user_id);
	CREATE INDEX IF NOT EXISTS idx_business_rule_user_id ON business_rule(user_id);
	`
	_, err := s.DB.Exec(schema)
	return err
}

// DBConn returns the underlying *sql.DB for backward compatibility.
func (s *SQLiteStore) DBConn() *sql.DB {
	return s.DB.DB
}
