package model

import "time"

// NoteMeta represents metadata for a single note.
type NoteMeta struct {
	ID           string    `json:"id"`
	Title        string    `json:"title"`
	Author       string    `json:"author"`
	CreatedAt    time.Time `json:"created_at"`
	ModifiedAt   time.Time `json:"modified_at"`
	WordCount    int       `json:"word_count"`
	CharCount    int       `json:"char_count"`
	Format       string    `json:"format"`
	Excerpt      string    `json:"excerpt"`
	Language     string    `json:"language"`
	IsEncrypted  bool      `json:"is_encrypted"`
	ContentHash  string    `json:"content_hash"`
	CustomFields string    `json:"custom_fields"`
}

// FolderMeta represents metadata for a folder/directory.
type FolderMeta struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	ParentID    string    `json:"parent_id"`
	Path        string    `json:"path"`
	Description string    `json:"description"`
	Icon        string    `json:"icon"`
	Color       string    `json:"color"`
	SortOrder   int       `json:"sort_order"`
	CreatedAt   time.Time `json:"created_at"`
	ModifiedAt  time.Time `json:"modified_at"`
	NoteCount   int       `json:"note_count"`
	ChildCount  int       `json:"child_count"`
}

// TagMeta represents a tag entity.
type TagMeta struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	ParentID    string    `json:"parent_id"`
	Color       string    `json:"color"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	UseCount    int       `json:"use_count"`
}

// TagRelation links a tag to a note.
type TagRelation struct {
	ID     string    `json:"id"`
	TagID  string    `json:"tag_id"`
	NoteID string    `json:"note_id"`
	LinkedAt time.Time `json:"linked_at"`
}

// KnowledgeRelation represents a bidirectional link between two notes.
type KnowledgeRelation struct {
	ID             string    `json:"id"`
	SourceNoteID   string    `json:"source_note_id"`
	TargetNoteID   string    `json:"target_note_id"`
	Weight         float64   `json:"weight"`
	ReferenceCount int       `json:"reference_count"`
	RelationType   string    `json:"relation_type"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// ValidationRule defines a rule for validating note content or structure.
type ValidationRule struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	Category    string    `json:"category"`
	RuleType    string    `json:"rule_type"`
	Pattern     string    `json:"pattern"`
	Severity    string    `json:"severity"`
	IsEnabled   bool      `json:"is_enabled"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// BusinessRule represents a custom user-defined business rule.
type BusinessRule struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	Expression string    `json:"expression"`
	Action     string    `json:"action"`
	Priority   int       `json:"priority"`
	IsEnabled  bool      `json:"is_enabled"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// ----------------------------------------------------------------
// Request / Response helpers
// ----------------------------------------------------------------

// PaginatedResponse wraps a list result with pagination info.
type PaginatedResponse struct {
	Data       interface{} `json:"data"`
	Total      int         `json:"total"`
	Page       int         `json:"page"`
	PageSize   int         `json:"page_size"`
	TotalPages int         `json:"total_pages"`
}

// ErrorResponse is the canonical error shape returned by the API.
type ErrorResponse struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Detail  string `json:"detail,omitempty"`
}

// SuccessResponse wraps a single data result.
type SuccessResponse struct {
	Data interface{} `json:"data"`
}

// GraphMetrics holds computed knowledge-graph metrics.
type GraphMetrics struct {
	TotalNodes       int                     `json:"total_nodes"`
	TotalEdges       int                     `json:"total_edges"`
	Density          float64                 `json:"density"`
	OrphanCount      int                     `json:"orphan_count"`
	ClusterCount     int                     `json:"cluster_count"`
	AvgDegree        float64                 `json:"avg_degree"`
	DegreeCentrality map[string]float64      `json:"degree_centrality"`
	PageRank         map[string]float64      `json:"page_rank"`
	Betweenness      map[string]float64      `json:"betweenness"`
	Clusters         map[string][]string     `json:"clusters"`
}

// ValidationResult is the outcome of running a validation rule.
type ValidationResult struct {
	RuleID   string `json:"rule_id"`
	RuleName string `json:"rule_name"`
	Passed   bool   `json:"passed"`
	Message  string `json:"message"`
	Severity string `json:"severity"`
}

// ValidationReport wraps a set of validation results.
type ValidationReport struct {
	TargetID string             `json:"target_id"`
	Type     string             `json:"type"`
	Results  []ValidationResult `json:"results"`
	Passed   bool               `json:"passed"`
}