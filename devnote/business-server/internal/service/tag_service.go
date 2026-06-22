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
func (s *TagService) Create(userID string, tag *model.TagMeta) (*model.TagMeta, error) {
	if strings.TrimSpace(tag.Name) == "" {
		return nil, errors.New("tag name is required")
	}

	tag.ID = uuid.New().String()
	tag.UserID = userID
	tag.CreatedAt = time.Now().UTC()

	_, err := s.db.Exec(`
		INSERT INTO tag_meta (id, user_id, name, parent_id, color, description, created_at, use_count)
		VALUES (?, ?, ?, ?, ?, ?, ?, 0)
	`, tag.ID, tag.UserID, tag.Name, tag.ParentID, tag.Color, tag.Description, tag.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("insert tag: %w", err)
	}
	return tag, nil
}

// Get retrieves a single tag by ID.
func (s *TagService) Get(userID, id string) (*model.TagMeta, error) {
	row := s.db.QueryRow(`SELECT id, user_id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE id=? AND user_id=?`, id, userID)

	var t model.TagMeta
	err := row.Scan(&t.ID, &t.UserID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("tag not found: %s", id)
	}
	if err != nil {
		return nil, fmt.Errorf("scan tag: %w", err)
	}
	return &t, nil
}

// Update modifies an existing tag.
func (s *TagService) Update(userID string, tag *model.TagMeta) (*model.TagMeta, error) {
	if tag.ID == "" {
		return nil, errors.New("id is required")
	}

	res, err := s.db.Exec(`
		UPDATE tag_meta SET name=?, parent_id=?, color=?, description=?
		WHERE id=? AND user_id=?
	`, tag.Name, tag.ParentID, tag.Color, tag.Description, tag.ID, userID)
	if err != nil {
		return nil, fmt.Errorf("update tag: %w", err)
	}
	if rows, _ := res.RowsAffected(); rows == 0 {
		return nil, fmt.Errorf("tag not found: %s", tag.ID)
	}
	tag.UserID = userID
	return tag, nil
}

// Delete removes a tag and its tag-relation records.
func (s *TagService) Delete(userID, id string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	// Verify ownership before deleting relations.
	var cnt int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE id=? AND user_id=?`, id, userID).Scan(&cnt); err != nil {
		return fmt.Errorf("check tag ownership: %w", err)
	}
	if cnt == 0 {
		return fmt.Errorf("tag not found: %s", id)
	}

	if _, err := tx.Exec(`DELETE FROM tag_relation WHERE tag_id=?`, id); err != nil {
		return fmt.Errorf("delete tag relations: %w", err)
	}
	if _, err := tx.Exec(`DELETE FROM tag_meta WHERE id=? AND user_id=?`, id, userID); err != nil {
		return fmt.Errorf("delete tag: %w", err)
	}
	return tx.Commit()
}

// List returns all tags with optional search.
func (s *TagService) List(userID string, page, pageSize int, search string) (*model.PaginatedResponse, error) {
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
		err = s.db.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE user_id=? AND name LIKE ?`, userID, like).Scan(&total)
		if err != nil {
			return nil, fmt.Errorf("count tags: %w", err)
		}
		offset := (page - 1) * pageSize
		rows, err = s.db.Query(`SELECT id, user_id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE user_id=? AND name LIKE ? ORDER BY use_count DESC LIMIT ? OFFSET ?`, userID, like, pageSize, offset)
	} else {
		err = s.db.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE user_id=?`, userID).Scan(&total)
		if err != nil {
			return nil, fmt.Errorf("count tags: %w", err)
		}
		offset := (page - 1) * pageSize
		rows, err = s.db.Query(`SELECT id, user_id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE user_id=? ORDER BY use_count DESC LIMIT ? OFFSET ?`, userID, pageSize, offset)
	}
	if err != nil {
		return nil, fmt.Errorf("list tags: %w", err)
	}
	defer rows.Close()

	var items []model.TagMeta
	for rows.Next() {
		var t model.TagMeta
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount); err != nil {
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
func (s *TagService) GetChildren(userID, parentID string) ([]model.TagMeta, error) {
	rows, err := s.db.Query(`SELECT id, user_id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE user_id=? AND parent_id=? ORDER BY name ASC`, userID, parentID)
	if err != nil {
		return nil, fmt.Errorf("get children: %w", err)
	}
	defer rows.Close()

	var children []model.TagMeta
	for rows.Next() {
		var t model.TagMeta
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount); err != nil {
			return nil, fmt.Errorf("scan child: %w", err)
		}
		children = append(children, t)
	}
	return children, nil
}

// GetHierarchy builds the full ancestor chain for a tag.
func (s *TagService) GetHierarchy(userID, tagID string) ([]model.TagMeta, error) {
	var chain []model.TagMeta
	currentID := tagID

	for currentID != "" {
		tag, err := s.Get(userID, currentID)
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
func (s *TagService) LinkTagToNote(userID, tagID, noteID string) (*model.TagRelation, error) {
	// Verify tag ownership
	var tagCnt int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE id=? AND user_id=?`, tagID, userID).Scan(&tagCnt); err != nil {
		return nil, fmt.Errorf("check tag ownership: %w", err)
	}
	if tagCnt == 0 {
		return nil, fmt.Errorf("tag not found: %s", tagID)
	}
	// Verify note ownership
	var noteCnt int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM note_meta WHERE id=? AND user_id=?`, noteID, userID).Scan(&noteCnt); err != nil {
		return nil, fmt.Errorf("check note ownership: %w", err)
	}
	if noteCnt == 0 {
		return nil, fmt.Errorf("note not found: %s", noteID)
	}

	// Check for existing link
	var cnt int
	// 修复(P0): 原代码忽略 QueryRow.Scan 的错误，DB 异常时 cnt 为 0，
	// 导致重复插入而非返回"already linked"错误。
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=? AND note_id=?`, tagID, noteID).Scan(&cnt); err != nil {
		return nil, fmt.Errorf("check existing link: %w", err)
	}
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
	// 修复(P0): 原代码忽略 Exec 错误，use_count 更新失败时统计数据永久错误。
	if _, err := s.db.Exec(`UPDATE tag_meta SET use_count = use_count + 1 WHERE id=? AND user_id=?`, tagID, userID); err != nil {
		return nil, fmt.Errorf("update tag use_count: %w", err)
	}

	return rel, nil
}

// UnlinkTagFromNote removes a tag-note association.
func (s *TagService) UnlinkTagFromNote(userID, tagID, noteID string) error {
	// Verify tag ownership before modifying relations.
	var tagCnt int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE id=? AND user_id=?`, tagID, userID).Scan(&tagCnt); err != nil {
		return fmt.Errorf("check tag ownership: %w", err)
	}
	if tagCnt == 0 {
		return fmt.Errorf("tag not found: %s", tagID)
	}

	_, err := s.db.Exec(`DELETE FROM tag_relation WHERE tag_id=? AND note_id=?`, tagID, noteID)
	if err != nil {
		return fmt.Errorf("unlink tag: %w", err)
	}
	// 修复(P0): 原代码忽略 use_count 更新错误，统计数据可能永久错误。
	if _, err := s.db.Exec(`UPDATE tag_meta SET use_count = MAX(use_count - 1, 0) WHERE id=? AND user_id=?`, tagID, userID); err != nil {
		return fmt.Errorf("update tag use_count: %w", err)
	}
	return nil
}

// GetNotesByTag returns all note IDs associated with a tag.
func (s *TagService) GetNotesByTag(userID, tagID string, page, pageSize int) (*model.PaginatedResponse, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	// Count relations scoped to the user's tag and notes.
	var total int
	if err := s.db.QueryRow(`
		SELECT COUNT(*) FROM tag_relation tr
		INNER JOIN tag_meta t ON tr.tag_id = t.id
		INNER JOIN note_meta nm ON tr.note_id = nm.id
		WHERE tr.tag_id=? AND t.user_id=? AND nm.user_id=?
	`, tagID, userID, userID).Scan(&total); err != nil {
		return nil, fmt.Errorf("count tag relations: %w", err)
	}

	offset := (page - 1) * pageSize
	rows, err := s.db.Query(`
		SELECT tr.id, tr.tag_id, tr.note_id, tr.linked_at, nm.title
		FROM tag_relation tr
		INNER JOIN tag_meta t ON tr.tag_id = t.id
		INNER JOIN note_meta nm ON tr.note_id = nm.id
		WHERE tr.tag_id=? AND t.user_id=? AND nm.user_id=?
		LIMIT ? OFFSET ?
	`, tagID, userID, userID, pageSize, offset)
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
func (s *TagService) GetTagsByNote(userID, noteID string) ([]model.TagMeta, error) {
	// Verify note ownership.
	var noteCnt int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM note_meta WHERE id=? AND user_id=?`, noteID, userID).Scan(&noteCnt); err != nil {
		return nil, fmt.Errorf("check note ownership: %w", err)
	}
	if noteCnt == 0 {
		return nil, fmt.Errorf("note not found: %s", noteID)
	}

	rows, err := s.db.Query(`
		SELECT t.id, t.user_id, t.name, t.parent_id, t.color, t.description, t.created_at, t.use_count
		FROM tag_meta t
		INNER JOIN tag_relation tr ON t.id=tr.tag_id
		WHERE tr.note_id=? AND t.user_id=?
		ORDER BY t.name ASC
	`, noteID, userID)
	if err != nil {
		return nil, fmt.Errorf("get tags by note: %w", err)
	}
	defer rows.Close()

	var tags []model.TagMeta
	for rows.Next() {
		var t model.TagMeta
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount); err != nil {
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
func (s *TagService) MergeTags(userID, sourceTagID, targetTagID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	// Verify ownership of both tags.
	var srcCnt, tgtCnt int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE id=? AND user_id=?`, sourceTagID, userID).Scan(&srcCnt); err != nil {
		return fmt.Errorf("check source tag ownership: %w", err)
	}
	if srcCnt == 0 {
		return fmt.Errorf("source tag not found: %s", sourceTagID)
	}
	if err := tx.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE id=? AND user_id=?`, targetTagID, userID).Scan(&tgtCnt); err != nil {
		return fmt.Errorf("check target tag ownership: %w", err)
	}
	if tgtCnt == 0 {
		return fmt.Errorf("target tag not found: %s", targetTagID)
	}

	// Move relations that targetTag doesn't already have (only for notes owned by the user).
	_, err = tx.Exec(`
		INSERT OR IGNORE INTO tag_relation (id, tag_id, note_id, linked_at)
		SELECT lower(hex(randomblob(16))), ?, tr.note_id, tr.linked_at
		FROM tag_relation tr
		INNER JOIN note_meta nm ON tr.note_id = nm.id
		WHERE tr.tag_id = ? AND nm.user_id = ?
	`, targetTagID, sourceTagID, userID)
	if err != nil {
		return fmt.Errorf("merge relations: %w", err)
	}

	// Remove source tag relations
	if _, err := tx.Exec(`DELETE FROM tag_relation WHERE tag_id=?`, sourceTagID); err != nil {
		return fmt.Errorf("delete source relations: %w", err)
	}

	// Update use count for target
	// 修复(P0): 原代码忽略 tx.QueryRow 和 tx.Exec 错误，
	// 事务提交后 use_count 可能与实际关联数不一致。
	var cnt int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=?`, targetTagID).Scan(&cnt); err != nil {
		return fmt.Errorf("count target relations: %w", err)
	}
	if _, err := tx.Exec(`UPDATE tag_meta SET use_count=? WHERE id=? AND user_id=?`, cnt, targetTagID, userID); err != nil {
		return fmt.Errorf("update target use_count: %w", err)
	}

	// Delete source tag
	if _, err := tx.Exec(`DELETE FROM tag_meta WHERE id=? AND user_id=?`, sourceTagID, userID); err != nil {
		return fmt.Errorf("delete source tag: %w", err)
	}

	return tx.Commit()
}

// SplitTag creates a new tag and moves some notes to it.
func (s *TagService) SplitTag(userID, sourceTagID, newTagName string, noteIDs []string) (*model.TagMeta, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	// Verify source tag ownership.
	var srcCnt int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE id=? AND user_id=?`, sourceTagID, userID).Scan(&srcCnt); err != nil {
		return nil, fmt.Errorf("check source tag ownership: %w", err)
	}
	if srcCnt == 0 {
		return nil, fmt.Errorf("source tag not found: %s", sourceTagID)
	}

	newTag := &model.TagMeta{
		ID:        uuid.New().String(),
		UserID:    userID,
		Name:      newTagName,
		CreatedAt: time.Now().UTC(),
	}
	_, err = tx.Exec(`INSERT INTO tag_meta (id, user_id, name, parent_id, color, description, created_at, use_count) VALUES (?, ?, ?, ?, ?, ?, ?, 0)`,
		newTag.ID, newTag.UserID, newTag.Name, newTag.ParentID, newTag.Color, newTag.Description, newTag.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("insert new tag: %w", err)
	}

	for _, noteID := range noteIDs {
		// Verify note ownership before moving association.
		var noteCnt int
		if err := tx.QueryRow(`SELECT COUNT(*) FROM note_meta WHERE id=? AND user_id=?`, noteID, userID).Scan(&noteCnt); err != nil {
			return nil, fmt.Errorf("check note ownership %s: %w", noteID, err)
		}
		if noteCnt == 0 {
			return nil, fmt.Errorf("note not found: %s", noteID)
		}
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
	// 修复(P0): 原代码忽略 tx.QueryRow 和 tx.Exec 错误，
	// 事务提交后 use_count 可能与实际关联数不一致。
	var srcCount int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=?`, sourceTagID).Scan(&srcCount); err != nil {
		return nil, fmt.Errorf("count source relations: %w", err)
	}
	if _, err := tx.Exec(`UPDATE tag_meta SET use_count=? WHERE id=? AND user_id=?`, srcCount, sourceTagID, userID); err != nil {
		return nil, fmt.Errorf("update source use_count: %w", err)
	}

	var newCount int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM tag_relation WHERE tag_id=?`, newTag.ID).Scan(&newCount); err != nil {
		return nil, fmt.Errorf("count new tag relations: %w", err)
	}
	if _, err := tx.Exec(`UPDATE tag_meta SET use_count=? WHERE id=? AND user_id=?`, newCount, newTag.ID, userID); err != nil {
		return nil, fmt.Errorf("update new tag use_count: %w", err)
	}

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
func (s *TagService) GetStats(userID, tagID string) (*TagStats, error) {
	tag, err := s.Get(userID, tagID)
	if err != nil {
		return nil, err
	}

	// Find related tags (tags that co-occur on the same notes), scoped to the user.
	rows, err := s.db.Query(`
		SELECT t.id, t.name, COUNT(*) as co_occur
		FROM tag_relation tr1
		INNER JOIN tag_relation tr2 ON tr1.note_id = tr2.note_id AND tr1.tag_id != tr2.tag_id
		INNER JOIN tag_meta t ON tr2.tag_id = t.id
		WHERE tr1.tag_id = ? AND t.user_id = ?
		GROUP BY t.id
		ORDER BY co_occur DESC
		LIMIT 10
	`, tagID, userID)
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
func (s *TagService) GetTopTags(userID string, limit int) ([]model.TagMeta, error) {
	if limit < 1 {
		limit = 10
	}
	rows, err := s.db.Query(`SELECT id, user_id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE user_id=? ORDER BY use_count DESC LIMIT ?`, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("top tags: %w", err)
	}
	defer rows.Close()

	var tags []model.TagMeta
	for rows.Next() {
		var t model.TagMeta
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &t.ParentID, &t.Color, &t.Description, &t.CreatedAt, &t.UseCount); err != nil {
			return nil, fmt.Errorf("scan top tag: %w", err)
		}
		tags = append(tags, t)
	}
	return tags, nil
}
