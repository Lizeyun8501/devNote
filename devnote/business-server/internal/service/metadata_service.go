package service

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/devnote/business-server/internal/model"
	"github.com/google/uuid"
)

// MetadataService provides CRUD and search operations for note metadata.
type MetadataService struct {
	db *sql.DB
}

// NewMetadataService creates a new MetadataService.
func NewMetadataService(db *sql.DB) *MetadataService {
	return &MetadataService{db: db}
}

// Create inserts a new note-metadata record.
func (s *MetadataService) Create(userID string, meta *model.NoteMeta) (*model.NoteMeta, error) {
	if meta.Title == "" {
		return nil, errors.New("title is required")
	}

	meta.ID = uuid.New().String()
	meta.UserID = userID
	now := time.Now().UTC()
	meta.CreatedAt = now
	meta.ModifiedAt = now

	_, err := s.db.Exec(`
		INSERT INTO note_meta (id, user_id, title, author, created_at, modified_at, word_count, char_count, format, excerpt, language, is_encrypted, content_hash, custom_fields)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`,
		meta.ID, meta.UserID, meta.Title, meta.Author, meta.CreatedAt, meta.ModifiedAt,
		meta.WordCount, meta.CharCount, meta.Format, meta.Excerpt, meta.Language,
		boolToInt(meta.IsEncrypted), meta.ContentHash, meta.CustomFields,
	)
	if err != nil {
		return nil, fmt.Errorf("insert note meta: %w", err)
	}
	return meta, nil
}

// Get retrieves a single note-metadata record by ID.
func (s *MetadataService) Get(userID, id string) (*model.NoteMeta, error) {
	row := s.db.QueryRow(`
		SELECT id, user_id, title, author, created_at, modified_at, word_count, char_count, format, excerpt, language, is_encrypted, content_hash, custom_fields
		FROM note_meta WHERE id = ? AND user_id = ?
	`, id, userID)

	var m model.NoteMeta
	var isEnc int
	err := row.Scan(&m.ID, &m.UserID, &m.Title, &m.Author, &m.CreatedAt, &m.ModifiedAt,
		&m.WordCount, &m.CharCount, &m.Format, &m.Excerpt, &m.Language,
		&isEnc, &m.ContentHash, &m.CustomFields)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("note meta not found: %s", id)
	}
	if err != nil {
		return nil, fmt.Errorf("scan note meta: %w", err)
	}
	m.IsEncrypted = isEnc != 0
	return &m, nil
}

// Update modifies an existing note-metadata record.
func (s *MetadataService) Update(userID string, meta *model.NoteMeta) (*model.NoteMeta, error) {
	if meta.ID == "" {
		return nil, errors.New("id is required")
	}

	meta.ModifiedAt = time.Now().UTC()

	res, err := s.db.Exec(`
		UPDATE note_meta SET title=?, author=?, modified_at=?, word_count=?, char_count=?, format=?, excerpt=?, language=?, is_encrypted=?, content_hash=?, custom_fields=?
		WHERE id=? AND user_id=?
	`,
		meta.Title, meta.Author, meta.ModifiedAt, meta.WordCount, meta.CharCount,
		meta.Format, meta.Excerpt, meta.Language, boolToInt(meta.IsEncrypted),
		meta.ContentHash, meta.CustomFields, meta.ID, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("update note meta: %w", err)
	}
	if rows, _ := res.RowsAffected(); rows == 0 {
		return nil, fmt.Errorf("note meta not found: %s", meta.ID)
	}
	meta.UserID = userID
	return meta, nil
}

// Delete removes a note-metadata record by ID.
func (s *MetadataService) Delete(userID, id string) error {
	_, err := s.db.Exec(`DELETE FROM note_meta WHERE id = ? AND user_id = ?`, id, userID)
	return err
}

// List returns a paginated list of note-metadata records with optional search filter.
func (s *MetadataService) List(userID string, page, pageSize int, search string) (*model.PaginatedResponse, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	var total int
	var rows *sql.Rows
	var err error

	if search != "" {
		like := "%" + search + "%"
		err = s.db.QueryRow(`SELECT COUNT(*) FROM note_meta WHERE user_id = ? AND (title LIKE ? OR author LIKE ?)`, userID, like, like).Scan(&total)
		if err != nil {
			return nil, fmt.Errorf("count note meta: %w", err)
		}
		offset := (page - 1) * pageSize
		rows, err = s.db.Query(`SELECT id, user_id, title, author, created_at, modified_at, word_count, char_count, format, excerpt, language, is_encrypted, content_hash, custom_fields FROM note_meta WHERE user_id = ? AND (title LIKE ? OR author LIKE ?) ORDER BY modified_at DESC LIMIT ? OFFSET ?`,
			userID, like, like, pageSize, offset)
	} else {
		err = s.db.QueryRow(`SELECT COUNT(*) FROM note_meta WHERE user_id = ?`, userID).Scan(&total)
		if err != nil {
			return nil, fmt.Errorf("count note meta: %w", err)
		}
		offset := (page - 1) * pageSize
		rows, err = s.db.Query(`SELECT id, user_id, title, author, created_at, modified_at, word_count, char_count, format, excerpt, language, is_encrypted, content_hash, custom_fields FROM note_meta WHERE user_id = ? ORDER BY modified_at DESC LIMIT ? OFFSET ?`,
			userID, pageSize, offset)
	}
	if err != nil {
		return nil, fmt.Errorf("list note meta: %w", err)
	}
	defer rows.Close()

	var items []model.NoteMeta
	for rows.Next() {
		var m model.NoteMeta
		var isEnc int
		if err := rows.Scan(&m.ID, &m.UserID, &m.Title, &m.Author, &m.CreatedAt, &m.ModifiedAt,
			&m.WordCount, &m.CharCount, &m.Format, &m.Excerpt, &m.Language,
			&isEnc, &m.ContentHash, &m.CustomFields); err != nil {
			return nil, fmt.Errorf("scan row: %w", err)
		}
		m.IsEncrypted = isEnc != 0
		items = append(items, m)
	}

	totalPages := (total + pageSize - 1) / pageSize
	return &model.PaginatedResponse{
		Data:       items,
		Total:      total,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	}, nil
}

// BatchCreate inserts multiple note-metadata records in a single transaction.
func (s *MetadataService) BatchCreate(userID string, items []*model.NoteMeta) ([]*model.NoteMeta, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	for _, m := range items {
		m.ID = uuid.New().String()
		m.UserID = userID
		now := time.Now().UTC()
		m.CreatedAt = now
		m.ModifiedAt = now

		_, err := tx.Exec(`
			INSERT INTO note_meta (id, user_id, title, author, created_at, modified_at, word_count, char_count, format, excerpt, language, is_encrypted, content_hash, custom_fields)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		`,
			m.ID, m.UserID, m.Title, m.Author, m.CreatedAt, m.ModifiedAt,
			m.WordCount, m.CharCount, m.Format, m.Excerpt, m.Language,
			boolToInt(m.IsEncrypted), m.ContentHash, m.CustomFields,
		)
		if err != nil {
			return nil, fmt.Errorf("batch insert: %w", err)
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}
	return items, nil
}

// BatchDelete removes multiple note-metadata records by IDs.
func (s *MetadataService) BatchDelete(userID string, ids []string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	for _, id := range ids {
		if _, err := tx.Exec(`DELETE FROM note_meta WHERE id = ? AND user_id = ?`, id, userID); err != nil {
			return fmt.Errorf("batch delete: %w", err)
		}
	}
	return tx.Commit()
}

// Filter returns notes matching the given criteria.
func (s *MetadataService) Filter(userID string, filterMap map[string]string, page, pageSize int) (*model.PaginatedResponse, error) {
	// Simplified filter implementation — extend as needed.
	query := "SELECT id, user_id, title, author, created_at, modified_at, word_count, char_count, format, excerpt, language, is_encrypted, content_hash, custom_fields FROM note_meta WHERE user_id = ?"
	countQ := "SELECT COUNT(*) FROM note_meta WHERE user_id = ?"
	args := []interface{}{userID}

	if v, ok := filterMap["format"]; ok && v != "" {
		query += " AND format = ?"
		countQ += " AND format = ?"
		args = append(args, v)
	}
	if v, ok := filterMap["author"]; ok && v != "" {
		query += " AND author = ?"
		countQ += " AND author = ?"
		args = append(args, v)
	}
	if v, ok := filterMap["language"]; ok && v != "" {
		query += " AND language = ?"
		countQ += " AND language = ?"
		args = append(args, v)
	}

	var total int
	if err := s.db.QueryRow(countQ, args...).Scan(&total); err != nil {
		return nil, fmt.Errorf("count filter: %w", err)
	}

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	offset := (page - 1) * pageSize
	query += " ORDER BY modified_at DESC LIMIT ? OFFSET ?"
	args = append(args, pageSize, offset)

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("filter query: %w", err)
	}
	defer rows.Close()

	var items []model.NoteMeta
	for rows.Next() {
		var m model.NoteMeta
		var isEnc int
		if err := rows.Scan(&m.ID, &m.UserID, &m.Title, &m.Author, &m.CreatedAt, &m.ModifiedAt,
			&m.WordCount, &m.CharCount, &m.Format, &m.Excerpt, &m.Language,
			&isEnc, &m.ContentHash, &m.CustomFields); err != nil {
			return nil, fmt.Errorf("scan filter row: %w", err)
		}
		m.IsEncrypted = isEnc != 0
		items = append(items, m)
	}

	totalPages := (total + pageSize - 1) / pageSize
	return &model.PaginatedResponse{
		Data:       items,
		Total:      total,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	}, nil
}

// parseCustomFields unmarshals a JSON custom_fields string into a Go map.
func parseCustomFields(raw string) map[string]interface{} {
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		return map[string]interface{}{}
	}
	return m
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
