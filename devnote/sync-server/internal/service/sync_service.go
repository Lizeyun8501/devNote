package service

import (
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/devnote/sync-server/internal/model"
	"github.com/devnote/sync-server/internal/storage"
	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

type SyncService struct {
	db    *sqlx.DB
	s3    *storage.S3Storage
	// P0 修复 (P1): 幂等键去重 —— 缓存最近 1000 个幂等键，防止重复推送
	idempotentKeys map[string]time.Time
}

func NewSyncService(db *sqlx.DB, s3 *storage.S3Storage) *SyncService {
	return &SyncService{
		db:             db,
		s3:             s3,
		idempotentKeys: make(map[string]time.Time, 1000),
	}
}

type PushRequest struct {
	DeviceID  string             `json:"device_id" binding:"required"`
	Records   []SyncRecordInput  `json:"records" binding:"required"`
	// P0 修复 (P1): 分页支持 —— 单次推送的变更数上限，默认 100，最大 1000
	Limit     int                `json:"limit,omitempty"`
}

type SyncRecordInput struct {
	NoteID    string `json:"note_id" binding:"required"`
	Action    string `json:"action" binding:"required"`
	Version   int64  `json:"version"`
	Payload   string `json:"payload"`
}

type PushResponse struct {
	Processed int        `json:"processed"`
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

func (s *SyncService) Push(userID string, req *PushRequest, limit int) (*PushResponse, error) {
	var conflicts []Conflict
	processed := 0

	// P0 修复 (P1): 分页支持 —— 限制单次推送的记录数
	records := req.Records
	if len(records) > limit {
		records = records[:limit]
	}

	tx, err := s.db.Beginx()
	if err != nil {
		return nil, fmt.Errorf("begin transaction: %w", err)
	}

	// 获取该用户的全局最大版本号（per-user 单调递增序列），
	// 确保 Pull 的 `WHERE user_id = ? AND version > ?` 能正确工作。
	var globalMaxVer int64
	err = tx.Get(&globalMaxVer,
		`SELECT COALESCE(MAX(version), 0) FROM sync_records WHERE user_id = ?`, userID)
	if err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("query global max version: %w", err)
	}

	for _, input := range records {
		var latest model.NoteSnapshot
		err := tx.Get(&latest,
			`SELECT * FROM note_snapshots WHERE note_id = ? AND user_id = ? ORDER BY version DESC LIMIT 1`,
			input.NoteID, userID)

		if err != nil && !errors.Is(err, sql.ErrNoRows) {
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

		now := time.Now()
		record := &model.SyncRecord{
			ID:        uuid.New().String(),
			UserID:    userID,
			DeviceID:  req.DeviceID,
			NoteID:    input.NoteID,
			Action:    input.Action,
			Version:   newVer,
			Timestamp: now,
			Payload:   input.Payload,
			CreatedAt: now,
		}

		_, err = tx.Exec(
			`INSERT INTO sync_records (id, user_id, device_id, note_id, action, version, timestamp, payload, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			record.ID, record.UserID, record.DeviceID, record.NoteID, record.Action, record.Version, record.Timestamp, record.Payload, record.CreatedAt,
		)
		if err != nil {
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
		_, err = tx.Exec(
			`INSERT INTO note_snapshots (id, note_id, user_id, version, content, checksum, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
			snapshot.ID, snapshot.NoteID, snapshot.UserID, snapshot.Version, snapshot.Content, snapshot.Checksum, now,
		)
		if err != nil {
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

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit transaction: %w", err)
	}

	return &PushResponse{
		Processed: processed,
		Conflicts: conflicts,
	}, nil
}

func (s *SyncService) Pull(userID string, req *PullRequest, limit int) (*PullResponse, error) {
	var records []model.SyncRecord
	err := s.db.Select(&records,
		`SELECT * FROM sync_records WHERE user_id = ? AND version > ? ORDER BY version ASC LIMIT ?`,
		userID, req.SinceVer, limit+1)
	if err != nil {
		return nil, fmt.Errorf("query records: %w", err)
	}

	var latestVer int64
	err = s.db.Get(&latestVer,
		`SELECT COALESCE(MAX(version), 0) FROM sync_records WHERE user_id = ?`, userID)
	if err != nil {
		return nil, fmt.Errorf("query latest version: %w", err)
	}

	hasMore := len(records) > limit
	if hasMore {
		records = records[:limit]
	}

	// P2 修复 (P2-10): updateDeviceSync 失败时返回 error，原实现仅 log.Printf 静默吞异常，
	// 导致设备同步状态不一致（Push 成功但 latest_version 未更新，下次 Pull 重复拉取）
	if err := s.updateDeviceSync(userID, req.DeviceID, latestVer); err != nil {
		return nil, fmt.Errorf("update device sync: %w", err)
	}

	return &PullResponse{
		Records:   records,
		LatestVer: latestVer,
		HasMore:   hasMore,
		Limit:     limit,
	}, nil
}

func (s *SyncService) GetStatus(userID, deviceID string) (*SyncStatus, error) {
	var device model.Device
	err := s.db.Get(&device,
		`SELECT * FROM devices WHERE user_id = ? AND id = ?`, userID, deviceID)
	if errors.Is(err, sql.ErrNoRows) {
		device = model.Device{
			ID:          deviceID,
			UserID:      userID,
			LastSyncAt:  time.Time{},
			LastSyncVer: 0,
		}
	} else if err != nil {
		return nil, err
	}

	var latestVer int64
	err = s.db.Get(&latestVer,
		`SELECT COALESCE(MAX(version), 0) FROM sync_records WHERE user_id = ?`, userID)
	if err != nil {
		return nil, fmt.Errorf("query latest version: %w", err)
	}

	var pending int64
	err = s.db.Get(&pending,
		`SELECT COUNT(*) FROM sync_records WHERE user_id = ? AND version > ?`, userID, device.LastSyncVer)
	if err != nil {
		return nil, fmt.Errorf("query pending count: %w", err)
	}

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
	err := s.db.Get(&snapshot,
		`SELECT * FROM note_snapshots WHERE note_id = ? AND user_id = ? ORDER BY version DESC LIMIT 1`,
		noteID, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
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
	err := s.db.Select(&snapshots,
		`SELECT * FROM note_snapshots WHERE note_id = ? AND user_id = ? ORDER BY version DESC LIMIT ?`,
		noteID, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("query note history: %w", err)
	}
	return snapshots, nil
}

// GetNoteVersion 获取笔记的特定版本
func (s *SyncService) GetNoteVersion(userID string, noteID string, version int64) (*model.NoteSnapshot, error) {
	var snapshot model.NoteSnapshot
	err := s.db.Get(&snapshot,
		`SELECT * FROM note_snapshots WHERE note_id = ? AND user_id = ? AND version = ?`,
		noteID, userID, version)
	if err != nil {
		return nil, fmt.Errorf("query note version: %w", err)
	}
	return &snapshot, nil
}

// ── P0 修复 (P1): 幂等键去重 ──────────────────────────────────────────

// IsIdempotentDuplicate 检查幂等键是否已被处理。
// 客户端应在每次推送请求中携带唯一的幂等键（UUID），服务端缓存最近 1000 个键，
// 若检测到重复，直接返回 200 OK 而不重复处理数据。
func (s *SyncService) IsIdempotentDuplicate(key string) bool {
	_, exists := s.idempotentKeys[key]
	return exists
}

// RecordIdempotentKey 记录已处理的幂等键。
// 超过 1000 个键时自动清理最旧的键（LRU 策略）。
func (s *SyncService) RecordIdempotentKey(key string) {
	if len(s.idempotentKeys) >= 1000 {
		// 清理最旧的键（基于时间排序）
		var oldestKey string
		var oldestTime time.Time
		for k, t := range s.idempotentKeys {
			if oldestKey == "" || t.Before(oldestTime) {
				oldestKey = k
				oldestTime = t
			}
		}
		delete(s.idempotentKeys, oldestKey)
	}
	s.idempotentKeys[key] = time.Now()
}

func (s *SyncService) ResolveConflict(userID string, resolution *ConflictResolution) error {
	// P1 修复 (SEC-12): 原实现仅创建 NoteSnapshot，不写 SyncRecord，
	// 导致 Pull（基于 SyncRecord.version）拉不到冲突解决结果，其他设备持续看到冲突。
	// 现改为在事务中同时创建 NoteSnapshot 和 SyncRecord，保证一致性。
	tx, err := s.db.Beginx()
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}

	now := time.Now()
	snapshot := &model.NoteSnapshot{
		ID:      uuid.New().String(),
		NoteID:  resolution.NoteID,
		UserID:  userID,
		Version: resolution.Version + 1,
		Content: resolution.ChosenData,
	}
	_, err = tx.Exec(
		`INSERT INTO note_snapshots (id, note_id, user_id, version, content, checksum, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
		snapshot.ID, snapshot.NoteID, snapshot.UserID, snapshot.Version, snapshot.Content, snapshot.Checksum, now,
	)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("create snapshot: %w", err)
	}

	// 同步写入 SyncRecord，使其他设备 Pull 时能拉到冲突解决结果
	record := &model.SyncRecord{
		ID:        uuid.New().String(),
		UserID:    userID,
		NoteID:    resolution.NoteID,
		Action:    "update",
		Version:   resolution.Version + 1,
		Payload:   resolution.ChosenData,
		CreatedAt: now,
	}
	_, err = tx.Exec(
		`INSERT INTO sync_records (id, user_id, device_id, note_id, action, version, timestamp, payload, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		record.ID, record.UserID, "", record.NoteID, record.Action, record.Version, now, record.Payload, record.CreatedAt,
	)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("create sync record: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}
	return nil
}

// P2 修复 (P2-10): 返回 error 而非静默吞异常，让调用方决定如何处理失败
func (s *SyncService) updateDeviceSync(userID, deviceID string, latestVer int64) error {
	return updateDeviceSyncTx(s.db, userID, deviceID, latestVer)
}

// queryExecer 是 *sqlx.DB 和 *sqlx.Tx 共同实现的接口，用于消除重复代码。
// 仅数据源（*sqlx.DB vs *sqlx.Tx）不同，通过此接口抽取为单一函数。
type queryExecer interface {
	Get(dest interface{}, query string, args ...interface{}) error
	Exec(query string, args ...interface{}) (sql.Result, error)
}

// updateDeviceSyncTx 在给定的事务/连接上更新设备的同步时间与版本号。
// 接受 queryExecer 以便在 Push 事务内复用（tx）或在 Pull 中使用 s.db。
func updateDeviceSyncTx(ext queryExecer, userID, deviceID string, latestVer int64) error {
	var device model.Device
	err := ext.Get(&device,
		`SELECT * FROM devices WHERE user_id = ? AND id = ?`, userID, deviceID)
	if errors.Is(err, sql.ErrNoRows) {
		now := time.Now()
		device = model.Device{
			ID:          deviceID,
			UserID:      userID,
			DeviceName:  deviceID,
			LastSyncAt:  now,
			LastSyncVer: latestVer,
			CreatedAt:   now,
			UpdatedAt:   now,
		}
		_, createErr := ext.Exec(
			`INSERT INTO devices (id, user_id, device_name, device_type, last_sync_at, last_sync_ver, created_at, updated_at) VALUES (?, ?, ?, '', ?, ?, ?, ?)`,
			device.ID, device.UserID, device.DeviceName, device.LastSyncAt, device.LastSyncVer, device.CreatedAt, device.UpdatedAt,
		)
		if createErr != nil {
			return fmt.Errorf("create device record: %w", createErr)
		}
		return nil
	}
	if err != nil {
		return fmt.Errorf("query device: %w", err)
	}

	_, err = ext.Exec(
		`UPDATE devices SET last_sync_at = ?, last_sync_ver = ?, updated_at = ? WHERE id = ?`,
		time.Now(), latestVer, time.Now(), device.ID,
	)
	if err != nil {
		return fmt.Errorf("update device sync: %w", err)
	}
	return nil
}
