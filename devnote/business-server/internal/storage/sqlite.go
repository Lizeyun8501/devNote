package storage

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	_ "github.com/mattn/go-sqlite3"
)

// SQLiteStore wraps a sql.DB connection and provides CRUD operations
// for all business-server domain entities.
type SQLiteStore struct {
	DB *sql.DB
}

// NewSQLiteStore opens (or creates) a SQLite database at the given path
// and runs schema migrations.
func NewSQLiteStore(dbPath string) (*SQLiteStore, error) {
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create db dir: %w", err)
	}

	db, err := sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_foreign_keys=on")
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping sqlite: %w", err)
	}

	store := &SQLiteStore{DB: db}
	if err := store.migrate(); err != nil {
		return nil, fmt.Errorf("migrate: %w", err)
	}

	return store, nil
}

func (s *SQLiteStore) Close() error {
	return s.DB.Close()
}

// migrate creates all required tables if they do not exist.
func (s *SQLiteStore) migrate() error {
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
	`

	_, err := s.DB.Exec(schema)
	return err
}