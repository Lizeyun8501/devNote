// 服务接口定义 —— Phase 3-A 六边形架构演进
//
// 目的: 让 handler 依赖服务抽象而非具体类型，便于单元测试时注入 mock 实现。
// 借鉴 Go 标准做法: 接口定义在消费方一侧通常更合适，但本仓库将所有业务服务
// 接口集中在此文件，便于跨 handler 复用与统一维护。
//
// Go 的结构化类型系统保证: 现有具体服务实现无需声明 implements 即可满足这些接口，
// 因此 main.go 中的装配代码无需改动。

package service

import (
	"github.com/devnote/business-server/internal/model"
)

// FolderServiceInterface 定义文件夹服务的领域接口
type FolderServiceInterface interface {
	Create(userID string, folder *model.FolderMeta) (*model.FolderMeta, error)
	Get(userID, id string) (*model.FolderMeta, error)
	Update(userID string, folder *model.FolderMeta) (*model.FolderMeta, error)
	Delete(userID, id string, cascade bool) error
	List(userID, parentID string) ([]model.FolderMeta, error)
	GetTree(userID, parentID string) ([]FolderTreeNode, error)
	MoveFolder(userID, folderID, newParentID string) error
	CopyFolder(userID, folderID, newParentID string) (*model.FolderMeta, error)
	ResolvePath(userID, folderID string) (string, error)
	GetNotesByFolder(userID, folderID string, page, pageSize int) (*model.PaginatedResponse, error)
}

// TagServiceInterface 定义标签服务的领域接口
type TagServiceInterface interface {
	Create(userID string, tag *model.TagMeta) (*model.TagMeta, error)
	Get(userID, id string) (*model.TagMeta, error)
	Update(userID string, tag *model.TagMeta) (*model.TagMeta, error)
	Delete(userID, id string) error
	List(userID string, page, pageSize int, search string) (*model.PaginatedResponse, error)
	GetChildren(userID, parentID string) ([]model.TagMeta, error)
	GetHierarchy(userID, tagID string) ([]model.TagMeta, error)
	LinkTagToNote(userID, tagID, noteID string) (*model.TagRelation, error)
	UnlinkTagFromNote(userID, tagID, noteID string) error
	GetNotesByTag(userID, tagID string, page, pageSize int) (*model.PaginatedResponse, error)
	GetTagsByNote(userID, noteID string) ([]model.TagMeta, error)
	MergeTags(userID, sourceTagID, targetTagID string) error
	SplitTag(userID, sourceTagID, newTagName string, noteIDs []string) (*model.TagMeta, error)
	GetStats(userID, tagID string) (*TagStats, error)
	GetTopTags(userID string, limit int) ([]model.TagMeta, error)
}

// KnowledgeServiceInterface 定义知识图谱服务的领域接口
type KnowledgeServiceInterface interface {
	CreateRelation(userID, sourceNoteID, targetNoteID, relationType string, weight float64) (*model.KnowledgeRelation, error)
	DeleteRelation(userID, id string) error
	GetRelations(userID, noteID string) ([]model.KnowledgeRelation, error)
	ComputeGraphEdges(userID string) ([]GraphEdge, error)
	ComputeMetrics(userID string) (*model.GraphMetrics, error)
	FindOrphanNotes(userID string) ([]string, error)
	ComputeCoverage(userID string) (*CoverageMetrics, error)
	SuggestRelatedNotes(userID, noteID string, limit int) ([]SuggestedNote, error)
	FindShortestPath(userID, fromNoteID, toNoteID string) ([]string, float64, error)
}

// MetadataServiceInterface 定义笔记元数据服务的领域接口
type MetadataServiceInterface interface {
	Create(userID string, meta *model.NoteMeta) (*model.NoteMeta, error)
	Get(userID, id string) (*model.NoteMeta, error)
	Update(userID string, meta *model.NoteMeta) (*model.NoteMeta, error)
	Delete(userID, id string) error
	List(userID string, page, pageSize int, search string) (*model.PaginatedResponse, error)
	BatchCreate(userID string, items []*model.NoteMeta) ([]*model.NoteMeta, error)
	BatchDelete(userID string, ids []string) error
	Filter(userID string, filterMap map[string]string, page, pageSize int) (*model.PaginatedResponse, error)
}

// ValidationServiceInterface 定义校验服务的领域接口
type ValidationServiceInterface interface {
	ValidateNote(userID, noteID string) (*model.ValidationReport, error)
	ValidateFolder(userID, folderID string) (*model.ValidationReport, error)
	ValidateTag(userID, tagID string) (*model.ValidationReport, error)
	ValidateKnowledgeRelation(userID, relID string) (*model.ValidationReport, error)
	CreateRule(userID string, rule *model.ValidationRule) (*model.ValidationRule, error)
	ListRules(userID string) ([]model.ValidationRule, error)
	UpdateRule(userID string, rule *model.ValidationRule) (*model.ValidationRule, error)
	DeleteRule(userID, id string) error
	CreateBusinessRule(userID string, rule *model.BusinessRule) (*model.BusinessRule, error)
	ListBusinessRules(userID string) ([]model.BusinessRule, error)
	UpdateBusinessRule(userID string, rule *model.BusinessRule) (*model.BusinessRule, error)
	DeleteBusinessRule(userID, id string) error
}
