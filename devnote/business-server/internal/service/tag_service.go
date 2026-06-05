package service

import (
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/devnote/business-server/internal/model"
	"github.com/google/uuid"
)

// TagService provides CRUD, hierarchy, association, merge/split,
// and statistics operations for tags.
type TagService struct {
	db *sql.DB
}

// NewTagService creates a new TagService.
func NewTagService(db *sql.DB) *TagService {
	return &TagService{db: db}
}

// Create inserts a new tag.
func (s *TagService) Create(tag *model.TagMeta) (*model.TagMeta, error) {
	if strings.TrimSpace(tag.Name) == "" {
		return nil, errors.New("tag name is required")
	}

	tag.ID = uuid.New().String()
	tag.CreatedAt = time.Now().UTC()

	_, err := s.db.Exec(`
		INSERT INTO tag_meta (id, name, parent_id, color, description, created_at, use_count)
		VALUES (?, ?, ?, ?, ?, ?, 0)
	`, tag.ID, tag.Name, tag.ParentID, tag.Color, tag.Description, tag.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("insert tag: %w", err)
	}
	return tag, nil
}

// Get retrieves a single tag by ID.
func (s *TagService) Get(id string) (*model.TagMeta, error) {
	row := s.db.QueryRow(`SELECT id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE id=?`, id)

	var t model.TagMeta
	err := row.Scan(&t.ID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("tag not found: %s", id)
	}
	if err != nil {
		return nil, fmt.Errorf("scan tag: %w", err)
	}
	return &t, nil
}

// Update modifies an existing tag.
func (s *TagService) Update(tag *model.TagMeta) (*model.TagMeta, error) {
	if tag.ID == "" {
		return nil, errors.New("id is required")
	}

	_, err := s.db.Exec(`
		UPDATE tag_meta SET name=?, parent_id=?, color=?, description=?
		WHERE id=?
	`, tag.Name, tag.ParentID, tag.Color, tag.Description, tag.ID)
	if err != nil {
		return nil, fmt.Errorf("update tag: %w", err)
	}
	return tag, nil
}

// Delete removes a tag and its tag-relation records.
func (s *TagService) Delete(id string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`DELETE FROM tag_relation WHERE tag_id=?`, id); err != nil {
		return fmt.Errorf("delete tag relations: %w", err)
	}
	if _, err := tx.Exec(`DELETE FROM tag_meta WHERE id=?`, id); err != nil {
		return fmt.Errorf("delete tag: %w", err)
	}
	return tx.Commit()
}

// List returns all tags with optional search.
func (s *TagService) List(page, pageSize int, search string) (*model.PaginatedResponse, error) {
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
		err = s.db.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE name LIKE ?`, like).Scan(&total)
		if err != nil {
			return nil, fmt.Errorf("count tags: %w", err)
		}
		offset := (page - 1) * pageSize
		rows, err = s.db.Query(`SELECT id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE name LIKE ? ORDER BY use_count DESC LIMIT ? OFFSET ?`, like, pageSize, offset)
	} else {
		err = s.db.QueryRow(`SELECT COUNT(*) FROM tag_meta`).Scan(&total)
		if err != nil {
			return nil, fmt.Errorf("count tags: %w", err)
		}
		offset := (page - 1) * pageSize
		rows, err = s.db.Query(`SELECT id, name, parent_id, color, description, created_at, use_count FROM tag_meta ORDER BY use_count DESC LIMIT ? OFFSET ?`, pageSize, offset)
	}
	if err != nil {
		return nil, fmt.Errorf("list tags: %w", err)
	}
	defer rows.Close()

	var items []model.TagMeta
	for rows.Next() {
		var t model.TagMeta
		if err := rows.Scan(&t.ID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount); err != nil {
			return nil, fmt.Errorf("scan tag row: %w", err)
		}
		items = append(items, t)
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

// GetChildren returns immediate child tags of the given parent.
func (s *TagService) GetChildren(parentID string) ([]model.TagMeta, error) {
	rows, err := s.db.Query(`SELECT id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE parent_id=? ORDER BY name ASC`, parentID)
	if err != nil {
		return nil, fmt.Errorf("get children: %w", err)
	}
	defer rows.Close()

	var children []model.TagMeta
	for rows.Next() {
		var t model.TagMeta
		if err := rows.Scan(&t.ID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount); err != nil {
			return nil, fmt.Errorf("scan child: %w", err)
		}
		children = append(children, t)
	}
	return children, nil
}

// GetHierarchy builds the full ancestor chain for a tag.
func (s *TagService) GetHierarchy(tagID string) ([]model.TagMeta, error) {
	var chain []model.TagMeta
	currentID := tagID

	for currentID != "" {
		tag, err := s.Get(currentID)
		if err != nil {
			return nil, err
		}
		// Prepend to build root → tag order
		chain = append([]model.TagMeta{*tag}, chain...)
		currentID = tag.ParentID
	}
	return chain, nil
}

// ----------------------------------------------------------------
// Tag-to-note association
// ----------------------------------------------------------------

// LinkTagToNote associates a tag with a note.
func (s *TagService) LinkTagToNote(tagID, noteID string) (*model.TagRelation, error) {
	// Check for existing link
	var cnt int
	s.db.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=? AND note_id=?`, tagID, noteID).Scan(&cnt)
	if cnt > 0 {
		return nil, fmt.Errorf("tag %s already linked to note %s", tagID, noteID)
	}

	rel := &model.TagRelation{
		ID:       uuid.New().String(),
		TagID:    tagID,
		NoteID:   noteID,
		LinkedAt: time.Now().UTC(),
	}

	_, err := s.db.Exec(`INSERT INTO tag_relation (id, tag_id, note_id, linked_at) VALUES (?, ?, ?, ?)`,
		rel.ID, rel.TagID, rel.NoteID, rel.LinkedAt)
	if err != nil {
		return nil, fmt.Errorf("link tag to note: %w", err)
	}

	// Update use count
	s.db.Exec(`UPDATE tag_meta SET use_count = use_count + 1 WHERE id=?`, tagID)

	return rel, nil
}

// UnlinkTagFromNote removes a tag-note association.
func (s *TagService) UnlinkTagFromNote(tagID, noteID string) error {
	_, err := s.db.Exec(`DELETE FROM tag_relation WHERE tag_id=? AND note_id=?`, tagID, noteID)
	if err != nil {
		return fmt.Errorf("unlink tag: %w", err)
	}
	s.db.Exec(`UPDATE tag_meta SET use_count = MAX(use_count - 1, 0) WHERE id=?`, tagID)
	return nil
}

// GetNotesByTag returns all note IDs associated with a tag.
func (s *TagService) GetNotesByTag(tagID string, page, pageSize int) (*model.PaginatedResponse, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	var total int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=?`, tagID).Scan(&total); err != nil {
		return nil, fmt.Errorf("count tag relations: %w", err)
	}

	offset := (page - 1) * pageSize
	rows, err := s.db.Query(`SELECT tr.id, tr.tag_id, tr.note_id, tr.linked_at, nm.title FROM tag_relation tr LEFT JOIN note_meta nm ON tr.note_id=nm.id WHERE tr.tag_id=? LIMIT ? OFFSET ?`, tagID, pageSize, offset)
	if err != nil {
		return nil, fmt.Errorf("get notes by tag: %w", err)
	}
	defer rows.Close()

	type NoteRef struct {
		ID    string `json:"id"`
		Title string `json:"title"`
	}
	var items []NoteRef
	for rows.Next() {
		var relID, tID, nID string
		var linkedAt time.Time
		var title sql.NullString
		if err := rows.Scan(&relID, &tID, &nID, &linkedAt, &title); err != nil {
			return nil, fmt.Errorf("scan relation: %w", err)
		}
		t := ""
		if title.Valid {
			t = title.String
		}
		items = append(items, NoteRef{ID: nID, Title: t})
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

// GetTagsByNote returns all tags associated with a note.
func (s *TagService) GetTagsByNote(noteID string) ([]model.TagMeta, error) {
	rows, err := s.db.Query(`SELECT t.id, t.name, t.parent_id, t.color, t.description, t.created_at, t.use_count FROM tag_meta t INNER JOIN tag_relation tr ON t.id=tr.tag_id WHERE tr.note_id=? ORDER BY t.name ASC`, noteID)
	if err != nil {
		return nil, fmt.Errorf("get tags by note: %w", err)
	}
	defer rows.Close()

	var tags []model.TagMeta
	for rows.Next() {
		var t model.TagMeta
		if err := rows.Scan(&t.ID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount); err != nil {
			return nil, fmt.Errorf("scan tag: %w", err)
		}
		tags = append(tags, t)
	}
	return tags, nil
}

// ----------------------------------------------------------------
// Merge / Split
// ----------------------------------------------------------------

// MergeTags merges all relations from sourceTagID into targetTagID and deletes the source.
func (s *TagService) MergeTags(sourceTagID, targetTagID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	// Move relations that targetTag doesn't already have
	_, err = tx.Exec(`
		INSERT OR IGNORE INTO tag_relation (id, tag_id, note_id, linked_at)
		SELECT lower(hex(randomblob(16))), ?, tr.note_id, tr.linked_at
		FROM tag_relation tr
		WHERE tr.tag_id = ?
	`, targetTagID, sourceTagID)
	if err != nil {
		return fmt.Errorf("merge relations: %w", err)
	}

	// Remove source tag relations
	if _, err := tx.Exec(`DELETE FROM tag_relation WHERE tag_id=?`, sourceTagID); err != nil {
		return fmt.Errorf("delete source relations: %w", err)
	}

	// Update use count for target
	var cnt int
	tx.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=?`, targetTagID).Scan(&cnt)
	tx.Exec(`UPDATE tag_meta SET use_count=? WHERE id=?`, cnt, targetTagID)

	// Delete source tag
	if _, err := tx.Exec(`DELETE FROM tag_meta WHERE id=?`, sourceTagID); err != nil {
		return fmt.Errorf("delete source tag: %w", err)
	}

	return tx.Commit()
}

// SplitTag creates a new tag and moves some notes to it.
func (s *TagService) SplitTag(sourceTagID, newTagName string, noteIDs []string) (*model.TagMeta, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	newTag := &model.TagMeta{
		ID:        uuid.New().String(),
		Name:      newTagName,
		CreatedAt: time.Now().UTC(),
	}
	_, err = tx.Exec(`INSERT INTO tag_meta (id, name, parent_id, color, description, created_at, use_count) VALUES (?, ?, ?, ?, ?, ?, 0)`,
		newTag.ID, newTag.Name, newTag.ParentID, newTag.Color, newTag.Description, newTag.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("insert new tag: %w", err)
	}

	for _, noteID := range noteIDs {
		// Move association from source to new tag
		if _, err := tx.Exec(`DELETE FROM tag_relation WHERE tag_id=? AND note_id=?`, sourceTagID, noteID); err != nil {
			return nil, fmt.Errorf("unlink note %s: %w", noteID, err)
		}
		relID := uuid.New().String()
		now := time.Now().UTC()
		if _, err := tx.Exec(`INSERT INTO tag_relation (id, tag_id, note_id, linked_at) VALUES (?, ?, ?, ?)`,
			relID, newTag.ID, noteID, now); err != nil {
			return nil, fmt.Errorf("link note %s to new tag: %w", noteID, err)
		}
	}

	// Update use counts
	var srcCount int
	tx.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=?`, sourceTagID).Scan(&srcCount)
	tx.Exec(`UPDATE tag_meta SET use_count=? WHERE id=?`, srcCount, sourceTagID)

	var newCount int
	tx.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=?`, newTag.ID).Scan(&newCount)
	tx.Exec(`UPDATE tag_meta SET use_count=? WHERE id=?`, newCount, newTag.ID)

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}
	return newTag, nil
}

// ----------------------------------------------------------------
// Statistics
// ----------------------------------------------------------------

// TagStats holds tag usage statistics.
type TagStats struct {
	Tag         model.TagMeta `json:"tag"`
	UseCount    int           `json:"use_count"`
	RelatedTags []RelatedTag  `json:"related_tags"`
}

// RelatedTag represents a tag frequently co-occurring with another.
type RelatedTag struct {
	TagID     string `json:"tag_id"`
	TagName   string `json:"tag_name"`
	CoOccur   int    `json:"co_occurrence_count"`
}

// GetStats returns statistics for a specific tag.
func (s *TagService) GetStats(tagID string) (*TagStats, error) {
	tag, err := s.Get(tagID)
	if err != nil {
		return nil, err
	}

	// Find related tags (tags that co-occur on the same notes)
	rows, err := s.db.Query(`
		SELECT t.id, t.name, COUNT(*) as co_occur
		FROM tag_relation tr1
		INNER JOIN tag_relation tr2 ON tr1.note_id = tr2.note_id AND tr1.tag_id != tr2.tag_id
		INNER JOIN tag_meta t ON tr2.tag_id = t.id
		WHERE tr1.tag_id = ?
		GROUP BY t.id
		ORDER BY co_occur DESC
		LIMIT 10
	`, tagID)
	if err != nil {
		return nil, fmt.Errorf("related tags query: %w", err)
	}
	defer rows.Close()

	var related []RelatedTag
	for rows.Next() {
		var rt RelatedTag
		if err := rows.Scan(&rt.TagID, &rt.TagName, &rt.CoOccur); err != nil {
			return nil, fmt.Errorf("scan related: %w", err)
		}
		related = append(related, rt)
	}

	return &TagStats{
		Tag:         *tag,
		UseCount:    tag.UseCount,
		RelatedTags: related,
	}, nil
}

// GetTopTags returns the most-used tags.
func (s *TagService) GetTopTags(limit int) ([]model.TagMeta, error) {
	if limit < 1 {
		limit = 10
	}
	rows, err := s.db.Query(`SELECT id, name, parent_id, color, description, created_at, use_count FROM tag_meta ORDER BY use_count DESC LIMIT ?`, limit)
	if err != nil {
		return nil, fmt.Errorf("top tags: %w", err)
	}
	defer rows.Close()

	var tags []model.TagMeta
	for rows.Next() {
		var t model.TagMeta
		if err := rows.Scan(&t.ID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount); err != nil {
			return nil, fmt.Errorf("scan top tag: %w", err)
		}
		tags = append(tags, t)
	}
	return tags, nil
}