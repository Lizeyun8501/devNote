package service

import (
	"database/sql"
	"fmt"
	"regexp"
	"strings"

	"github.com/devnote/business-server/internal/model"
	"github.com/google/uuid"
)

// ValidationService validates note structures, folder hierarchies, tags,
// and knowledge relationships against defined rules.
type ValidationService struct {
	db      *sql.DB
	cfg     ValidationConfig
}

// ValidationConfig holds configurable limits for validation.
type ValidationConfig struct {
	MaxTagDepth    int
	MaxFolderDepth int
	MaxNoteSize    int
}

// NewValidationService creates a new ValidationService.
func NewValidationService(db *sql.DB, cfg ValidationConfig) *ValidationService {
	return &ValidationService{db: db, cfg: cfg}
}

// ValidateNote validates a note's structure: required fields, format compliance, size.
func (s *ValidationService) ValidateNote(noteID string) (*model.ValidationReport, error) {
	var note model.NoteMeta
	var isEnc int
	row := s.db.QueryRow(`
		SELECT id, title, author, created_at, modified_at, word_count, char_count, format, excerpt, language, is_encrypted, content_hash, custom_fields
		FROM note_meta WHERE id=?
	`, noteID)
	if err := row.Scan(&note.ID, &note.Title, &note.Author, &note.CreatedAt, &note.ModifiedAt,
		&note.WordCount, &note.CharCount, &note.Format, &note.Excerpt, &note.Language,
		&isEnc, &note.ContentHash, &note.CustomFields); err != nil {
		if err == sql.ErrNoRows {
			msg := fmt.Sprintf("note not found: %s", noteID)
			return &model.ValidationReport{
				TargetID: noteID,
				Type:     "note",
				Results:  []model.ValidationResult{},
				Passed:   false,
			}, fmt.Errorf(msg)
		}
		return nil, err
	}
	note.IsEncrypted = isEnc != 0

	var results []model.ValidationResult

	// Rule: title required
	if strings.TrimSpace(note.Title) == "" {
		results = append(results, model.ValidationResult{
			RuleID: "note-title-required", RuleName: "Title Required",
			Passed: false, Message: "note title cannot be empty", Severity: "error",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "note-title-required", RuleName: "Title Required",
			Passed: true, Severity: "error",
		})
	}

	// Rule: valid format
	validFormats := map[string]bool{"markdown": true, "plaintext": true, "rich": true, "latex": true}
	if !validFormats[note.Format] {
		results = append(results, model.ValidationResult{
			RuleID: "note-format-valid", RuleName: "Valid Format",
			Passed: false, Message: fmt.Sprintf("unsupported format: %s", note.Format), Severity: "error",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "note-format-valid", RuleName: "Valid Format",
			Passed: true, Severity: "error",
		})
	}

	// Rule: content size
	if note.CharCount > s.cfg.MaxNoteSize {
		results = append(results, model.ValidationResult{
			RuleID: "note-size-limit", RuleName: "Size Limit",
			Passed: false, Message: fmt.Sprintf("note size %d exceeds limit %d", note.CharCount, s.cfg.MaxNoteSize), Severity: "warning",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "note-size-limit", RuleName: "Size Limit",
			Passed: true, Severity: "warning",
		})
	}

	allPassed := true
	for _, r := range results {
		if !r.Passed {
			allPassed = false
			break
		}
	}

	return &model.ValidationReport{
		TargetID: noteID,
		Type:     "note",
		Results:  results,
		Passed:   allPassed,
	}, nil
}

// ValidateFolder validates folder hierarchy: no circular references, max depth.
func (s *ValidationService) ValidateFolder(folderID string) (*model.ValidationReport, error) {
	var results []model.ValidationResult

	// Rule: circular reference check
	hasCycle, err := s.detectFolderCycle(folderID, folderID, make(map[string]bool))
	if err != nil {
		return nil, err
	}
	if hasCycle {
		results = append(results, model.ValidationResult{
			RuleID: "folder-no-cycle", RuleName: "No Circular Reference",
			Passed: false, Message: "circular reference detected in folder hierarchy", Severity: "error",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "folder-no-cycle", RuleName: "No Circular Reference",
			Passed: true, Severity: "error",
		})
	}

	// Rule: max depth
	depth, err := s.calculateFolderDepth(folderID, 1)
	if err != nil {
		return nil, err
	}
	if depth > s.cfg.MaxFolderDepth {
		results = append(results, model.ValidationResult{
			RuleID: "folder-max-depth", RuleName: "Max Depth",
			Passed: false, Message: fmt.Sprintf("folder depth %d exceeds maximum %d", depth, s.cfg.MaxFolderDepth), Severity: "warning",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "folder-max-depth", RuleName: "Max Depth",
			Passed: true, Severity: "warning",
		})
	}

	allPassed := true
	for _, r := range results {
		if !r.Passed {
			allPassed = false
			break
		}
	}

	return &model.ValidationReport{
		TargetID: folderID,
		Type:     "folder",
		Results:  results,
		Passed:   allPassed,
	}, nil
}

func (s *ValidationService) detectFolderCycle(rootID, currentID string, visited map[string]bool) (bool, error) {
	if visited[currentID] {
		return currentID == rootID, nil
	}
	visited[currentID] = true

	// Get children
	var parentID string
	err := s.db.QueryRow(`SELECT parent_id FROM folder_meta WHERE id=?`, currentID).Scan(&parentID)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if parentID == "" {
		return false, nil
	}
	return s.detectFolderCycle(rootID, parentID, visited)
}

func (s *ValidationService) calculateFolderDepth(folderID string, currentDepth int) (int, error) {
	var parentID string
	err := s.db.QueryRow(`SELECT parent_id FROM folder_meta WHERE id=?`, folderID).Scan(&parentID)
	if err == sql.ErrNoRows || parentID == "" {
		return currentDepth, nil
	}
	if err != nil {
		return 0, err
	}
	return s.calculateFolderDepth(parentID, currentDepth+1)
}

// ValidateTag validates a tag: name length, valid characters, no duplicates.
func (s *ValidationService) ValidateTag(tagID string) (*model.ValidationReport, error) {
	var tag model.TagMeta
	row := s.db.QueryRow(`SELECT id, name, parent_id, color, description, created_at, use_count FROM tag_meta WHERE id=?`, tagID)
	if err := row.Scan(&tag.ID, &tag.Name, &tag.ParentID, &tag.Color, &tag.Description, &tag.CreatedAt, &tag.UseCount); err != nil {
		if err == sql.ErrNoRows {
			msg := fmt.Sprintf("tag not found: %s", tagID)
			return &model.ValidationReport{
				TargetID: tagID,
				Type:     "tag",
				Results:  []model.ValidationResult{},
				Passed:   false,
			}, fmt.Errorf(msg)
		}
		return nil, err
	}

	var results []model.ValidationResult

	// Rule: name length
	nameLen := len(strings.TrimSpace(tag.Name))
	if nameLen == 0 {
		results = append(results, model.ValidationResult{
			RuleID: "tag-name-length", RuleName: "Name Length",
			Passed: false, Message: "tag name cannot be empty", Severity: "error",
		})
	} else if nameLen > 64 {
		results = append(results, model.ValidationResult{
			RuleID: "tag-name-length", RuleName: "Name Length",
			Passed: false, Message: fmt.Sprintf("tag name too long: %d characters (max 64)", nameLen), Severity: "warning",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "tag-name-length", RuleName: "Name Length",
			Passed: true, Severity: "warning",
		})
	}

	// Rule: valid characters
	validName := regexp.MustCompile(`^[a-zA-Z0-9_\-\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}\s]+$`)
	if nameLen > 0 && !validName.MatchString(tag.Name) {
		results = append(results, model.ValidationResult{
			RuleID: "tag-name-chars", RuleName: "Valid Characters",
			Passed: false, Message: "tag name contains invalid characters", Severity: "error",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "tag-name-chars", RuleName: "Valid Characters",
			Passed: true, Severity: "error",
		})
	}

	// Rule: duplicate check
	var cnt int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM tag_meta WHERE name=? AND id!=?`, tag.Name, tag.ID).Scan(&cnt); err == nil && cnt > 0 {
		results = append(results, model.ValidationResult{
			RuleID: "tag-name-unique", RuleName: "Unique Name",
			Passed: false, Message: fmt.Sprintf("duplicate tag name: %s", tag.Name), Severity: "warning",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "tag-name-unique", RuleName: "Unique Name",
			Passed: true, Severity: "warning",
		})
	}

	// Rule: tag depth
	if tag.ParentID != "" {
		depth, err := s.calculateTagDepth(tag.ID, 1)
		if err != nil {
			return nil, err
		}
		if depth > s.cfg.MaxTagDepth {
			results = append(results, model.ValidationResult{
				RuleID: "tag-max-depth", RuleName: "Max Tag Depth",
				Passed: false, Message: fmt.Sprintf("tag depth %d exceeds maximum %d", depth, s.cfg.MaxTagDepth), Severity: "warning",
			})
		} else {
			results = append(results, model.ValidationResult{
				RuleID: "tag-max-depth", RuleName: "Max Tag Depth",
				Passed: true, Severity: "warning",
			})
		}
	}

	allPassed := true
	for _, r := range results {
		if !r.Passed {
			allPassed = false
			break
		}
	}

	return &model.ValidationReport{
		TargetID: tagID,
		Type:     "tag",
		Results:  results,
		Passed:   allPassed,
	}, nil
}

func (s *ValidationService) calculateTagDepth(tagID string, currentDepth int) (int, error) {
	var parentID string
	err := s.db.QueryRow(`SELECT parent_id FROM tag_meta WHERE id=?`, tagID).Scan(&parentID)
	if err == sql.ErrNoRows || parentID == "" {
		return currentDepth, nil
	}
	if err != nil {
		return 0, err
	}
	return s.calculateTagDepth(parentID, currentDepth+1)
}

// ValidateKnowledgeRelation validates a knowledge relationship: no self-references, valid targets.
func (s *ValidationService) ValidateKnowledgeRelation(relID string) (*model.ValidationReport, error) {
	var rel model.KnowledgeRelation
	row := s.db.QueryRow(`
		SELECT id, source_note_id, target_note_id, weight, reference_count, relation_type, created_at, updated_at
		FROM knowledge_relation WHERE id=?
	`, relID)
	if err := row.Scan(&rel.ID, &rel.SourceNoteID, &rel.TargetNoteID, &rel.Weight,
		&rel.ReferenceCount, &rel.RelationType, &rel.CreatedAt, &rel.UpdatedAt); err != nil {
		if err == sql.ErrNoRows {
			msg := fmt.Sprintf("knowledge relation not found: %s", relID)
			return &model.ValidationReport{
				TargetID: relID,
				Type:     "knowledge_relation",
				Results:  []model.ValidationResult{},
				Passed:   false,
			}, fmt.Errorf(msg)
		}
		return nil, err
	}

	var results []model.ValidationResult

	// Rule: no self-reference
	if rel.SourceNoteID == rel.TargetNoteID {
		results = append(results, model.ValidationResult{
			RuleID: "knowledge-no-self-ref", RuleName: "No Self Reference",
			Passed: false, Message: "a knowledge relation cannot reference itself", Severity: "error",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "knowledge-no-self-ref", RuleName: "No Self Reference",
			Passed: true, Severity: "error",
		})
	}

	// Rule: source note exists
	var srcCnt int
	s.db.QueryRow(`SELECT COUNT(*) FROM note_meta WHERE id=?`, rel.SourceNoteID).Scan(&srcCnt)
	if srcCnt == 0 {
		results = append(results, model.ValidationResult{
			RuleID: "knowledge-valid-source", RuleName: "Valid Source",
			Passed: false, Message: fmt.Sprintf("source note not found: %s", rel.SourceNoteID), Severity: "error",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "knowledge-valid-source", RuleName: "Valid Source",
			Passed: true, Severity: "error",
		})
	}

	// Rule: target note exists
	var tgtCnt int
	s.db.QueryRow(`SELECT COUNT(*) FROM note_meta WHERE id=?`, rel.TargetNoteID).Scan(&tgtCnt)
	if tgtCnt == 0 {
		results = append(results, model.ValidationResult{
			RuleID: "knowledge-valid-target", RuleName: "Valid Target",
			Passed: false, Message: fmt.Sprintf("target note not found: %s", rel.TargetNoteID), Severity: "error",
		})
	} else {
		results = append(results, model.ValidationResult{
			RuleID: "knowledge-valid-target", RuleName: "Valid Target",
			Passed: true, Severity: "error",
		})
	}

	allPassed := true
	for _, r := range results {
		if !r.Passed {
			allPassed = false
			break
		}
	}

	return &model.ValidationReport{
		TargetID: relID,
		Type:     "knowledge_relation",
		Results:  results,
		Passed:   allPassed,
	}, nil
}

// ----------------------------------------------------------------
// Validation Rule CRUD (the rules themselves, not running them)
// ----------------------------------------------------------------

// CreateRule inserts a new validation rule.
func (s *ValidationService) CreateRule(rule *model.ValidationRule) (*model.ValidationRule, error) {
	rule.ID = uuid.New().String()
	_, err := s.db.Exec(`
		INSERT INTO validation_rule (id, name, description, category, rule_type, pattern, severity, is_enabled, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
	`, rule.ID, rule.Name, rule.Description, rule.Category, rule.RuleType, rule.Pattern, rule.Severity, boolToInt(rule.IsEnabled))
	if err != nil {
		return nil, fmt.Errorf("insert validation rule: %w", err)
	}
	return rule, nil
}

// ListRules returns all validation rules.
func (s *ValidationService) ListRules() ([]model.ValidationRule, error) {
	rows, err := s.db.Query(`SELECT id, name, description, category, rule_type, pattern, severity, is_enabled, created_at, updated_at FROM validation_rule ORDER BY created_at DESC`)
	if err != nil {
		return nil, fmt.Errorf("list rules: %w", err)
	}
	defer rows.Close()

	var rules []model.ValidationRule
	for rows.Next() {
		var r model.ValidationRule
		var isEnabled int
		if err := rows.Scan(&r.ID, &r.Name, &r.Description, &r.Category, &r.RuleType, &r.Pattern, &r.Severity, &isEnabled, &r.CreatedAt, &r.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan rule: %w", err)
		}
		r.IsEnabled = isEnabled != 0
		rules = append(rules, r)
	}
	return rules, nil
}

// UpdateRule modifies an existing validation rule.
func (s *ValidationService) UpdateRule(rule *model.ValidationRule) (*model.ValidationRule, error) {
	_, err := s.db.Exec(`
		UPDATE validation_rule SET name=?, description=?, category=?, rule_type=?, pattern=?, severity=?, is_enabled=?, updated_at=CURRENT_TIMESTAMP
		WHERE id=?
	`, rule.Name, rule.Description, rule.Category, rule.RuleType, rule.Pattern, rule.Severity, boolToInt(rule.IsEnabled), rule.ID)
	if err != nil {
		return nil, fmt.Errorf("update rule: %w", err)
	}
	return rule, nil
}

// DeleteRule removes a validation rule.
func (s *ValidationService) DeleteRule(id string) error {
	_, err := s.db.Exec(`DELETE FROM validation_rule WHERE id=?`, id)
	return err
}

// ----------------------------------------------------------------
// Business Rule CRUD
// ----------------------------------------------------------------

// CreateBusinessRule inserts a new business rule.
func (s *ValidationService) CreateBusinessRule(rule *model.BusinessRule) (*model.BusinessRule, error) {
	rule.ID = uuid.New().String()
	_, err := s.db.Exec(`
		INSERT INTO business_rule (id, name, expression, action, priority, is_enabled, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
	`, rule.ID, rule.Name, rule.Expression, rule.Action, rule.Priority, boolToInt(rule.IsEnabled))
	if err != nil {
		return nil, fmt.Errorf("insert business rule: %w", err)
	}
	return rule, nil
}

// ListBusinessRules returns all business rules.
func (s *ValidationService) ListBusinessRules() ([]model.BusinessRule, error) {
	rows, err := s.db.Query(`SELECT id, name, expression, action, priority, is_enabled, created_at, updated_at FROM business_rule ORDER BY priority DESC`)
	if err != nil {
		return nil, fmt.Errorf("list business rules: %w", err)
	}
	defer rows.Close()

	var rules []model.BusinessRule
	for rows.Next() {
		var r model.BusinessRule
		var isEnabled int
		if err := rows.Scan(&r.ID, &r.Name, &r.Expression, &r.Action, &r.Priority, &isEnabled, &r.CreatedAt, &r.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan business rule: %w", err)
		}
		r.IsEnabled = isEnabled != 0
		rules = append(rules, r)
	}
	return rules, nil
}

// UpdateBusinessRule modifies an existing business rule.
func (s *ValidationService) UpdateBusinessRule(rule *model.BusinessRule) (*model.BusinessRule, error) {
	_, err := s.db.Exec(`
		UPDATE business_rule SET name=?, expression=?, action=?, priority=?, is_enabled=?, updated_at=CURRENT_TIMESTAMP
		WHERE id=?
	`, rule.Name, rule.Expression, rule.Action, rule.Priority, boolToInt(rule.IsEnabled), rule.ID)
	if err != nil {
		return nil, fmt.Errorf("update business rule: %w", err)
	}
	return rule, nil
}

// DeleteBusinessRule removes a business rule.
func (s *ValidationService) DeleteBusinessRule(id string) error {
	_, err := s.db.Exec(`DELETE FROM business_rule WHERE id=?`, id)
	return err
}