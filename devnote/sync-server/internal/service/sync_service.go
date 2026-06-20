package service

import (
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/devnote/sync-server/internal/model"
	"github.com/devnote/sync-server/internal/storage"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type SyncService struct {
	db    *gorm.DB
	s3    *storage.S3Storage
}

func NewSyncService(db *gorm.DB, s3 *storage.S3Storage) *SyncService {
	return &SyncService{db: db, s3: s3}
}

type PushRequest struct {
	DeviceID  string           `json:"device_id" binding:"required"`
	Records   []SyncRecordInput `json:"records" binding:"required"`
}

type SyncRecordInput struct {
	NoteID    string `json:"note_id" binding:"required"`
	Action    string `json:"action" binding:"required"`
	Version   int64  `json:"version"`
	Payload   string `json:"payload"`
}

type PushResponse struct {
	Processed int      `json:"processed"`
	Conflicts []Conflict `json:"conflicts,omitempty"`
}

type PullRequest struct {
	DeviceID  string `json:"device_id" binding:"required"`
	SinceVer  int64  `json:"since_version"`
}

type PullResponse struct {
	Records     []model.SyncRecord `json:"records"`
	LatestVer   int64              `json:"latest_version"`
	HasMore     bool               `json:"has_more"`
	Limit       int                `json:"limit"`
}

type SyncStatus struct {
	DeviceID    string    `json:"device_id"`
	LastSyncAt  time.Time `json:"last_sync_at"`
	LastSyncVer int64     `json:"last_sync_version"`
	LatestVer   int64     `json:"latest_version"`
	Pending     int64     `json:"pending_count"`
}

func (s *SyncService) Push(userID string, req *PushRequest) (*PushResponse, error) {
	var conflicts []Conflict
	processed := 0

	tx := s.db.Begin()
	if tx.Error != nil {
		return nil, fmt.Errorf("begin transaction: %w", tx.Error)
	}

	// 获取该用户的全局最大版本号（per-user 单调递增序列），
	// 确保 Pull 的 `WHERE user_id = ? AND version > ?` 能正确工作。
	var globalMaxVer int64
	if err := tx.Model(&model.SyncRecord{}).Where("user_id = ?", userID).Select("COALESCE(MAX(version), 0)").Scan(&globalMaxVer).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("query global max version: %w", err)
	}

	for _, input := range req.Records {
		var latest model.NoteSnapshot
		err := tx.Where("note_id = ? AND user_id = ?", input.NoteID, userID).Order("version DESC").First(&latest).Error

		if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			tx.Rollback()
			return nil, fmt.Errorf("query latest snapshot: %w", err)
		}

		if latest.ID != "" && latest.Version > input.Version {
			conflict := DetectConflict(input.Version, latest.Version, input.Payload, latest.Content)
			if conflict != nil {
				conflict.NoteID = input.NoteID
				conflict.RecordID = uuid.New().String()
				resolution := ResolveLastWriteWins(conflict)
				input.Payload = resolution.ChosenData
				conflicts = append(conflicts, *conflict)
			}
		}

		// 全局递增分配版本号
		globalMaxVer++
		newVer := globalMaxVer

		// 防止乱序：若该笔记已有更新版本（例如通过 ResolveConflict 直接写入
		// NoteSnapshot），则调整版本号以保持单调递增。
		if latest.ID != "" && newVer <= latest.Version {
			newVer = latest.Version + 1
			globalMaxVer = newVer
		}

		record := &model.SyncRecord{
			ID:        uuid.New().String(),
			UserID:    userID,
			DeviceID:  req.DeviceID,
			NoteID:    input.NoteID,
			Action:    input.Action,
			Version:   newVer,
			Timestamp: time.Now(),
			Payload:   input.Payload,
		}

		if err := tx.Create(record).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("create sync record: %w", err)
		}

		snapshot := &model.NoteSnapshot{
			ID:      uuid.New().String(),
			NoteID:  input.NoteID,
			UserID:  userID,
			Version: newVer,
			Content: input.Payload,
		}
		if err := tx.Create(snapshot).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("create note snapshot: %w", err)
		}

		processed++
	}

	// 在事务内更新设备同步状态
	if err := updateDeviceSyncTx(tx, userID, req.DeviceID, globalMaxVer); err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("update device sync: %w", err)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("commit transaction: %w", err)
	}

	return &PushResponse{
		Processed: processed,
		Conflicts: conflicts,
	}, nil
}

func (s *SyncService) Pull(userID string, req *PullRequest, limit int) (*PullResponse, error) {
	var records []model.SyncRecord
	query := s.db.Where("user_id = ? AND version > ?", userID, req.SinceVer)
	if err := query.Order("version ASC").Limit(limit + 1).Find(&records).Error; err != nil {
		return nil, err
	}

	var latestVer int64
	if err := s.db.Model(&model.SyncRecord{}).Where("user_id = ?", userID).Select("COALESCE(MAX(version), 0)").Scan(&latestVer).Error; err != nil {
		return nil, fmt.Errorf("query latest version: %w", err)
	}

	hasMore := len(records) > limit
	if hasMore {
		records = records[:limit]
	}

	s.updateDeviceSync(userID, req.DeviceID, latestVer)

	return &PullResponse{
		Records:   records,
		LatestVer: latestVer,
		HasMore:   hasMore,
		Limit:     limit,
	}, nil
}

func (s *SyncService) GetStatus(userID, deviceID string) (*SyncStatus, error) {
	var device model.Device
	if err := s.db.Where("user_id = ? AND id = ?", userID, deviceID).First(&device).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			device = model.Device{
				ID:          deviceID,
				UserID:      userID,
				LastSyncAt:  time.Time{},
				LastSyncVer: 0,
			}
		} else {
			return nil, err
		}
	}

	var latestVer int64
	if err := s.db.Model(&model.SyncRecord{}).Where("user_id = ?", userID).Select("COALESCE(MAX(version), 0)").Scan(&latestVer).Error; err != nil {
		return nil, fmt.Errorf("query latest version: %w", err)
	}

	var pending int64
	s.db.Model(&model.SyncRecord{}).Where("user_id = ? AND version > ?", userID, device.LastSyncVer).Count(&pending)

	return &SyncStatus{
		DeviceID:    deviceID,
		LastSyncAt:  device.LastSyncAt,
		LastSyncVer: device.LastSyncVer,
		LatestVer:   latestVer,
		Pending:     pending,
	}, nil
}

// GetNoteLatestVersion 返回指定笔记在最新快照中的版本号，找不到时返回 0。
// 用于剪藏等场景在 Push 之后获取实际分配到的版本号。
func (s *SyncService) GetNoteLatestVersion(userID, noteID string) (int64, error) {
	var snapshot model.NoteSnapshot
	err := s.db.Where("note_id = ? AND user_id = ?", noteID, userID).
		Order("version DESC").First(&snapshot).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return 0, nil
		}
		return 0, fmt.Errorf("query note latest version: %w", err)
	}
	return snapshot.Version, nil
}

// GetNoteHistory 获取笔记的版本历史
func (s *SyncService) GetNoteHistory(userID string, noteID string, limit int) ([]model.NoteSnapshot, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	var snapshots []model.NoteSnapshot
	err := s.db.Where("note_id = ? AND user_id = ?", noteID, userID).
		Order("version DESC").
		Limit(limit).
		Find(&snapshots).Error
	if err != nil {
		return nil, fmt.Errorf("query note history: %w", err)
	}
	return snapshots, nil
}

// GetNoteVersion 获取笔记的特定版本
func (s *SyncService) GetNoteVersion(userID string, noteID string, version int64) (*model.NoteSnapshot, error) {
	var snapshot model.NoteSnapshot
	err := s.db.Where("note_id = ? AND user_id = ? AND version = ?", noteID, userID, version).
		First(&snapshot).Error
	if err != nil {
		return nil, fmt.Errorf("query note version: %w", err)
	}
	return &snapshot, nil
}

func (s *SyncService) ResolveConflict(userID string, resolution *ConflictResolution) error {
	snapshot := &model.NoteSnapshot{
		ID:      uuid.New().String(),
		NoteID:  resolution.NoteID,
		UserID:  userID,
		Version: resolution.Version + 1,
		Content: resolution.ChosenData,
	}
	return s.db.Create(snapshot).Error
}

func (s *SyncService) updateDeviceSync(userID, deviceID string, latestVer int64) {
	if err := updateDeviceSyncTx(s.db, userID, deviceID, latestVer); err != nil {
		log.Printf("update device sync failed: %v", err)
	}
}

// updateDeviceSyncTx 在给定的事务/连接上更新设备的同步时间与版本号。
// 接受 *gorm.DB 以便在 Push 事务内复用（tx）或在 Pull 中使用 s.db。
func updateDeviceSyncTx(db *gorm.DB, userID, deviceID string, latestVer int64) error {
	var device model.Device
	err := db.Where("user_id = ? AND id = ?", userID, deviceID).First(&device).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		device = model.Device{
			ID:          deviceID,
			UserID:      userID,
			DeviceName:  deviceID,
			LastSyncAt:  time.Now(),
			LastSyncVer: latestVer,
		}
		if createErr := db.Create(&device).Error; createErr != nil {
			return fmt.Errorf("create device record: %w", createErr)
		}
		return nil
	}
	if err != nil {
		return fmt.Errorf("query device: %w", err)
	}

	if updateErr := db.Model(&device).Updates(map[string]interface{}{
		"last_sync_at":  time.Now(),
		"last_sync_ver": latestVer,
	}).Error; updateErr != nil {
		return fmt.Errorf("update device sync: %w", updateErr)
	}
	return nil
}
