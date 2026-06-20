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

// FolderService provides CRUD, tree management, move/copy, path resolution,
// and circular-reference detection for folders.
type FolderService struct {
	db *sql.DB
}

// NewFolderService creates a new FolderService.
func NewFolderService(db *sql.DB) *FolderService {
	return &FolderService{db: db}
}

// Create inserts a new folder.
func (s *FolderService) Create(userID string, folder *model.FolderMeta) (*model.FolderMeta, error) {
	if strings.TrimSpace(folder.Name) == "" {
		return nil, errors.New("folder name is required")
	}

	folder.ID = uuid.New().String()
	folder.UserID = userID
	now := time.Now().UTC()
	folder.CreatedAt = now
	folder.ModifiedAt = now

	// Build path
	folder.Path = s.buildPath(userID, folder.Name, folder.ParentID)

	_, err := s.db.Exec(`
		INSERT INTO folder_meta (id, user_id, name, parent_id, path, description, icon, color, sort_order, created_at, modified_at, note_count, child_count)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)
	`, folder.ID, folder.UserID, folder.Name, folder.ParentID, folder.Path, folder.Description,
		folder.Icon, folder.Color, folder.SortOrder, folder.CreatedAt, folder.ModifiedAt)
	if err != nil {
		return nil, fmt.Errorf("insert folder: %w", err)
	}

	// Update parent's child_count
	// 修复(P0): 原代码忽略 child_count 更新错误，统计数据可能永久错误。
	if folder.ParentID != "" {
		if _, err := s.db.Exec(`UPDATE folder_meta SET child_count = child_count + 1 WHERE id=? AND user_id=?`, folder.ParentID, userID); err != nil {
			return nil, fmt.Errorf("update parent child_count: %w", err)
		}
	}

	return folder, nil
}

// Get retrieves a folder by ID.
func (s *FolderService) Get(userID, id string) (*model.FolderMeta, error) {
	row := s.db.QueryRow(`
		SELECT id, user_id, name, parent_id, path, description, icon, color, sort_order, created_at, modified_at, note_count, child_count
		FROM folder_meta WHERE id=? AND user_id=?
	`, id, userID)

	var f model.FolderMeta
	err := row.Scan(&f.ID, &f.UserID, &f.Name, &f.ParentID, &f.Path, &f.Description, &f.Icon, &f.Color,
		&f.SortOrder, &f.CreatedAt, &f.ModifiedAt, &f.NoteCount, &f.ChildCount)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("folder not found: %s", id)
	}
	if err != nil {
		return nil, fmt.Errorf("scan folder: %w", err)
	}
	return &f, nil
}

// Update modifies an existing folder.
func (s *FolderService) Update(userID string, folder *model.FolderMeta) (*model.FolderMeta, error) {
	if folder.ID == "" {
		return nil, errors.New("id is required")
	}

	folder.ModifiedAt = time.Now().UTC()
	folder.Path = s.buildPath(userID, folder.Name, folder.ParentID)

	res, err := s.db.Exec(`
		UPDATE folder_meta SET name=?, parent_id=?, path=?, description=?, icon=?, color=?, sort_order=?, modified_at=?
		WHERE id=? AND user_id=?
	`, folder.Name, folder.ParentID, folder.Path, folder.Description,
		folder.Icon, folder.Color, folder.SortOrder, folder.ModifiedAt, folder.ID, userID)
	if err != nil {
		return nil, fmt.Errorf("update folder: %w", err)
	}
	if rows, _ := res.RowsAffected(); rows == 0 {
		return nil, fmt.Errorf("folder not found: %s", folder.ID)
	}
	folder.UserID = userID
	return folder, nil
}

// Delete removes a folder. If cascade is true, deletes all descendants.
func (s *FolderService) Delete(userID, id string, cascade bool) error {
	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	// Verify ownership before deleting.
	var ownCnt int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM folder_meta WHERE id=? AND user_id=?`, id, userID).Scan(&ownCnt); err != nil {
		return fmt.Errorf("check folder ownership: %w", err)
	}
	if ownCnt == 0 {
		return fmt.Errorf("folder not found: %s", id)
	}

	if cascade {
		children, err := s.getAllDescendantIDs(tx, userID, id)
		if err != nil {
			return err
		}
		for _, childID := range children {
			// 修复(P0): 原代码忽略级联删除错误，可能导致子文件夹残留。
			if _, err := tx.Exec(`DELETE FROM folder_meta WHERE id=? AND user_id=?`, childID, userID); err != nil {
				return fmt.Errorf("delete descendant %s: %w", childID, err)
			}
		}
	}

	// Get parent before deleting
	var parentID string
	if err := tx.QueryRow(`SELECT parent_id FROM folder_meta WHERE id=? AND user_id=?`, id, userID).Scan(&parentID); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("get parent id: %w", err)
	}

	if _, err := tx.Exec(`DELETE FROM folder_meta WHERE id=? AND user_id=?`, id, userID); err != nil {
		return fmt.Errorf("delete folder: %w", err)
	}

	// Update parent's child_count
	// 修复(P0): 原代码忽略 child_count 更新错误。
	if parentID != "" {
		if _, err := tx.Exec(`UPDATE folder_meta SET child_count = MAX(child_count - 1, 0) WHERE id=? AND user_id=?`, parentID, userID); err != nil {
			return fmt.Errorf("update parent child_count: %w", err)
		}
	}

	return tx.Commit()
}

// List returns all folders at the root level or all folders.
func (s *FolderService) List(userID, parentID string) ([]model.FolderMeta, error) {
	var rows *sql.Rows
	var err error

	if parentID == "" {
		rows, err = s.db.Query(`SELECT id, user_id, name, parent_id, path, description, icon, color, sort_order, created_at, modified_at, note_count, child_count FROM folder_meta WHERE user_id=? ORDER BY sort_order ASC, name ASC`, userID)
	} else {
		rows, err = s.db.Query(`SELECT id, user_id, name, parent_id, path, description, icon, color, sort_order, created_at, modified_at, note_count, child_count FROM folder_meta WHERE user_id=? AND parent_id=? ORDER BY sort_order ASC, name ASC`, userID, parentID)
	}
	if err != nil {
		return nil, fmt.Errorf("list folders: %w", err)
	}
	defer rows.Close()

	var folders []model.FolderMeta
	for rows.Next() {
		var f model.FolderMeta
		if err := rows.Scan(&f.ID, &f.UserID, &f.Name, &f.ParentID, &f.Path, &f.Description, &f.Icon, &f.Color,
			&f.SortOrder, &f.CreatedAt, &f.ModifiedAt, &f.NoteCount, &f.ChildCount); err != nil {
			return nil, fmt.Errorf("scan folder: %w", err)
		}
		folders = append(folders, f)
	}
	return folders, nil
}

// GetTree returns the folder tree rooted at parentID ("" means root).
func (s *FolderService) GetTree(userID, parentID string) ([]FolderTreeNode, error) {
	children, err := s.List(userID, parentID)
	if err != nil {
		return nil, err
	}

	var nodes []FolderTreeNode
	for _, f := range children {
		node := FolderTreeNode{
			Folder:     f,
			Children:   nil,
			NoteCount:  f.NoteCount,
			ChildCount: f.ChildCount,
		}
		if f.ChildCount > 0 {
			sub, err := s.GetTree(userID, f.ID)
			if err != nil {
				return nil, err
			}
			node.Children = sub
		}
		nodes = append(nodes, node)
	}
	return nodes, nil
}

// FolderTreeNode represents a node in the folder tree.
type FolderTreeNode struct {
	Folder     model.FolderMeta  `json:"folder"`
	Children   []FolderTreeNode  `json:"children,omitempty"`
	NoteCount  int               `json:"note_count"`
	ChildCount int               `json:"child_count"`
}

// ----------------------------------------------------------------
// Move / Copy
// ----------------------------------------------------------------

// MoveFolder moves a folder under a new parent.
func (s *FolderService) MoveFolder(userID, folderID, newParentID string) error {
	// Circular reference check
	if folderID == newParentID {
		return errors.New("a folder cannot be its own parent")
	}

	hasCycle, err := s.hasCycle(userID, folderID, newParentID)
	if err != nil {
		return err
	}
	if hasCycle {
		return errors.New("moving would create a circular reference")
	}

	// Get old parent
	var oldParentID string
	if err := s.db.QueryRow(`SELECT parent_id FROM folder_meta WHERE id=? AND user_id=?`, folderID, userID).Scan(&oldParentID); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("get old parent: %w", err)
	}
	if errors.Is(err, sql.ErrNoRows) {
		return fmt.Errorf("folder not found: %s", folderID)
	}

	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	// Update parent
	newPath := s.buildPathFor(userID, folderID, newParentID)
	_, err = tx.Exec(`UPDATE folder_meta SET parent_id=?, path=?, modified_at=? WHERE id=? AND user_id=?`, newParentID, newPath, time.Now().UTC(), folderID, userID)
	if err != nil {
		return fmt.Errorf("move folder: %w", err)
	}

	// Update old parent child_count
	// 修复(P0): 原代码忽略 child_count 更新错误，统计数据可能永久错误。
	if oldParentID != "" {
		if _, err := tx.Exec(`UPDATE folder_meta SET child_count = MAX(child_count - 1, 0) WHERE id=? AND user_id=?`, oldParentID, userID); err != nil {
			return fmt.Errorf("update old parent child_count: %w", err)
		}
	}

	// Update new parent child_count
	if newParentID != "" {
		if _, err := tx.Exec(`UPDATE folder_meta SET child_count = child_count + 1 WHERE id=? AND user_id=?`, newParentID, userID); err != nil {
			return fmt.Errorf("update new parent child_count: %w", err)
		}
	}

	return tx.Commit()
}

// CopyFolder duplicates a folder and all its descendants under a new parent.
func (s *FolderService) CopyFolder(userID, folderID, newParentID string) (*model.FolderMeta, error) {
	src, err := s.Get(userID, folderID)
	if err != nil {
		return nil, err
	}

	copy, err := s.Create(userID, &model.FolderMeta{
		Name:        src.Name + " (copy)",
		ParentID:    newParentID,
		Description: src.Description,
		Icon:        src.Icon,
		Color:       src.Color,
		SortOrder:   src.SortOrder,
	})
	if err != nil {
		return nil, err
	}

	// Recursively copy children
	children, err := s.List(userID, folderID)
	if err != nil {
		return nil, err
	}
	for _, child := range children {
		if _, err := s.CopyFolder(userID, child.ID, copy.ID); err != nil {
			return nil, err
		}
	}

	return copy, nil
}

// ----------------------------------------------------------------
// Path resolution
// ----------------------------------------------------------------

// ResolvePath returns the full path string for a folder.
func (s *FolderService) ResolvePath(userID, folderID string) (string, error) {
	f, err := s.Get(userID, folderID)
	if err != nil {
		return "", err
	}
	return f.Path, nil
}

// buildPath constructs a full path from folder name and parent.
func (s *FolderService) buildPath(userID, name, parentID string) string {
	if parentID == "" {
		return "/" + name
	}
	parentPath, err := s.ResolvePath(userID, parentID)
	if err != nil {
		return "/" + name
	}
	return parentPath + "/" + name
}

func (s *FolderService) buildPathFor(userID, folderID, newParentID string) string {
	var name string
	if err := s.db.QueryRow(`SELECT name FROM folder_meta WHERE id=? AND user_id=?`, folderID, userID).Scan(&name); err != nil {
		return "/"
	}
	if newParentID == "" {
		return "/" + name
	}
	parentPath, err := s.ResolvePath(userID, newParentID)
	if err != nil {
		return "/" + name
	}
	return parentPath + "/" + name
}

// ----------------------------------------------------------------
// Folder ↔ Note associations
// ----------------------------------------------------------------

// GetNotesByFolder returns notes metadata associated with a folder.
func (s *FolderService) GetNotesByFolder(userID, folderID string, page, pageSize int) (*model.PaginatedResponse, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	// Association is stored via a custom field / external lookup.
	// Here we query note_meta.custom_fields for a "folder_id" key.
	search := `%"folder_id":"` + folderID + `"%`
	var total int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM note_meta WHERE user_id=? AND custom_fields LIKE ?`, userID, search).Scan(&total); err != nil {
		return nil, fmt.Errorf("count folder notes: %w", err)
	}

	offset := (page - 1) * pageSize
	rows, err := s.db.Query(
		`SELECT id, user_id, title, author, created_at, modified_at, word_count, char_count, format, excerpt, language, is_encrypted, content_hash, custom_fields FROM note_meta WHERE user_id=? AND custom_fields LIKE ? ORDER BY modified_at DESC LIMIT ? OFFSET ?`,
		userID, search, pageSize, offset)
	if err != nil {
		return nil, fmt.Errorf("get folder notes: %w", err)
	}
	defer rows.Close()

	var items []model.NoteMeta
	for rows.Next() {
		var m model.NoteMeta
		var isEnc int
		if err := rows.Scan(&m.ID, &m.UserID, &m.Title, &m.Author, &m.CreatedAt, &m.ModifiedAt,
			&m.WordCount, &m.CharCount, &m.Format, &m.Excerpt, &m.Language,
			&isEnc, &m.ContentHash, &m.CustomFields); err != nil {
			return nil, fmt.Errorf("scan note: %w", err)
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

// ----------------------------------------------------------------
// Circular reference detection
// ----------------------------------------------------------------

// hasCycle checks whether making childID a descendant of parentID creates a cycle.
func (s *FolderService) hasCycle(userID, childID, parentID string) (bool, error) {
	if parentID == "" {
		return false, nil
	}
	return s.isAncestor(userID, parentID, childID)
}

// isAncestor returns true if ancestor is an ancestor of folderID.
func (s *FolderService) isAncestor(userID, ancestorID, folderID string) (bool, error) {
	currentID := folderID
	visited := make(map[string]bool)
	for currentID != "" {
		if visited[currentID] {
			return false, nil
		}
		visited[currentID] = true
		if currentID == ancestorID {
			return true, nil
		}
		var pid string
		err := s.db.QueryRow(`SELECT parent_id FROM folder_meta WHERE id=? AND user_id=?`, currentID, userID).Scan(&pid)
		if err == sql.ErrNoRows {
			return false, nil
		}
		if err != nil {
			return false, err
		}
		currentID = pid
	}
	return false, nil
}

// getAllDescendantIDs collects all descendant IDs recursively using a transaction.
func (s *FolderService) getAllDescendantIDs(tx *sql.Tx, userID, folderID string) ([]string, error) {
	var ids []string
	rows, err := tx.Query(`SELECT id FROM folder_meta WHERE parent_id=? AND user_id=?`, folderID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
		children, err := s.getAllDescendantIDs(tx, userID, id)
		if err != nil {
			return nil, err
		}
		ids = append(ids, children...)
	}
	return ids, nil
}
