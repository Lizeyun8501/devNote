package service

import (
	"errors"
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

	for _, input := range req.Records {
		var latest model.NoteSnapshot
		err := s.db.Where("note_id = ? AND user_id = ?", input.NoteID, userID).Order("version DESC").First(&latest).Error

		if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, err
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

		newVer := input.Version + 1
		if latest.ID != "" && newVer <= latest.Version {
			newVer = latest.Version + 1
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

		if err := s.db.Create(record).Error; err != nil {
			return nil, err
		}

		snapshot := &model.NoteSnapshot{
			ID:      uuid.New().String(),
			NoteID:  input.NoteID,
			UserID:  userID,
			Version: newVer,
			Content: input.Payload,
		}
		if err := s.db.Create(snapshot).Error; err != nil {
			return nil, err
		}

		processed++
	}

	s.updateDeviceSync(userID, req.DeviceID)

	return &PushResponse{
		Processed: processed,
		Conflicts: conflicts,
	}, nil
}

func (s *SyncService) Pull(userID string, req *PullRequest) (*PullResponse, error) {
	var records []model.SyncRecord
	query := s.db.Where("user_id = ? AND version > ?", userID, req.SinceVer)
	if err := query.Order("version ASC").Find(&records).Error; err != nil {
		return nil, err
	}

	var latestVer int64
	s.db.Model(&model.SyncRecord{}).Where("user_id = ?", userID).Select("COALESCE(MAX(version), 0)").Scan(&latestVer)

	s.updateDeviceSync(userID, req.DeviceID)

	return &PullResponse{
		Records:   records,
		LatestVer: latestVer,
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
	s.db.Model(&model.SyncRecord{}).Where("user_id = ?", userID).Select("COALESCE(MAX(version), 0)").Scan(&latestVer)

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

func (s *SyncService) updateDeviceSync(userID, deviceID string) {
	var device model.Device
	err := s.db.Where("user_id = ? AND id = ?", userID, deviceID).First(&device).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		device = model.Device{
			ID:         deviceID,
			UserID:     userID,
			DeviceName: deviceID,
			LastSyncAt: time.Now(),
		}
		s.db.Create(&device)
	} else if err == nil {
		s.db.Model(&device).Updates(map[string]interface{}{
			"last_sync_at": time.Now(),
		})
	}
}
