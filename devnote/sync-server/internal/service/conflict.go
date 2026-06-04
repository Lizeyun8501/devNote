// Package service 提供同步服务器的核心业务服务实现。
//
// 本文件 conflict.go 实现笔记同步过程中的冲突检测与解决逻辑。
//
// ## 借鉴的开源项目
//   - **CRDT 冲突解决理论**:
//     借鉴 CRDT（Conflict-free Replicated Data Type）中的"无冲突复制数据类型"
//     思想：通过对每次操作赋予单调递增的版本号（LocalVersion / ServerVersion），
//     客户端与服务端能够在最终一致（Eventual Consistency）的语义下判定数据的新旧。
//   - **git merge-file 工具** ([源码](https://git-scm.com/docs/git-merge-file)):
//     借鉴 git merge-file 的"两路对比 + 基线（base）"合并思路：
//     - 当 `localData != serverData` 且版本号不同，视为存在内容冲突；
//     - 当 `LocalVersion > ServerVersion`，本地为"较新"，策略选择 `LocalData`；
//     - 当 `LocalVersion < ServerVersion`，服务端为"较新"，策略选择 `ServerData`。
//
// ## 实现说明
//   - 冲突检测（DetectConflict）仅在"内容不一致"且"版本不一致"时返回 Conflict，
//     否则认为已经自动达成一致（`nil`）。
//   - 解决策略分两类：自动（`last_write_wins`）与人工介入（`manual`）。
//   - `ConflictResolution` 是解决结果的不可变视图：包含选定的内容与新版本号。
package service

// ConflictStrategy 冲突解决策略
//
// 借鉴 CRDT 理论中的"最终一致性"分类：自动 vs 手动。
type ConflictStrategy string

const (
	// StrategyLastWriteWins 借鉴 git merge-file 的 "ours / theirs" 二元选择：
	// 选择版本号更大的一方作为最终结果。
	StrategyLastWriteWins ConflictStrategy = "last_write_wins"
	// StrategyManual 借鉴 CRDT 中的"应用层冲突解决"：当自动策略无法决策时
	// （例如删除 vs 修改、并发移动到不同位置等），必须由用户或上层服务介入。
	StrategyManual ConflictStrategy = "manual"
)

// Conflict 描述一次同步冲突
//
// 借鉴 git 的"三方合并"语义模型：本结构同时记录 local / server 两侧的版本号与数据，
// 用以驱动后续合并决策（last-write-wins 或 manual）。
type Conflict struct {
	RecordID      string           `json:"record_id"`
	NoteID        string           `json:"note_id"`
	LocalVersion  int64            `json:"local_version"`
	ServerVersion int64            `json:"server_version"`
	LocalData     string           `json:"local_data"`
	ServerData    string           `json:"server_data"`
	Strategy      ConflictStrategy `json:"strategy"`
}

// ConflictResolution 是冲突解决后的不可变结果
//
// 借鉴 git `merge-file` 命令的退出码语义：返回"选定的内容 + 新版本号"。
type ConflictResolution struct {
	NoteID     string `json:"note_id"`
	ChosenData string `json:"chosen_data"`
	Version    int64  `json:"version"`
}

// DetectConflict 检测本地与服务端之间是否存在内容冲突
//
// 借鉴 CRDT 的"最终一致性"判定：
//   - 当内容相同（`localData == serverData`）时认为已达成一致，返回 nil。
//   - 当版本号相同时认为是"重放"（同一次更新被多次同步），返回 nil。
//   - 仅当内容与版本号"双双不同"时，构造 Conflict 对象，策略默认 `last_write_wins`。
//
// **算法来源**: CRDT 冲突解决理论 + git merge-file 的检测策略。
func DetectConflict(localVer, serverVer int64, localData, serverData string) *Conflict {
	if localData != serverData && localVer != serverVer {
		return &Conflict{
			NoteID:        "",
			LocalVersion:  localVer,
			ServerVersion: serverVer,
			LocalData:     localData,
			ServerData:    serverData,
			Strategy:      StrategyLastWriteWins,
		}
	}
	return nil
}

// ResolveLastWriteWins 使用"最后写入获胜"策略解决冲突
//
// 借鉴 git merge-file 的 "ours/theirs" 决策：
//   - 若本地版本号更大（视为"后写"），选择 `LocalData` 并将 `LocalVersion` 提升为新版本；
//   - 否则选择 `ServerData` 与 `ServerVersion`。
//
// **算法来源**: git merge-file 的版本号比较。
func ResolveLastWriteWins(c *Conflict) *ConflictResolution {
	if c.LocalVersion > c.ServerVersion {
		return &ConflictResolution{
			NoteID:     c.NoteID,
			ChosenData: c.LocalData,
			Version:    c.LocalVersion,
		}
	}
	return &ConflictResolution{
		NoteID:     c.NoteID,
		ChosenData: c.ServerData,
		Version:    c.ServerVersion,
	}
}

// ResolveManual 由调用方（用户 / 业务层）显式指定使用本地或服务端版本
//
// 借鉴 CRDT 中"应用层冲突解决（application-level conflict resolution）"：
// 当 CRDT 自动策略无法达成一致时（例如删除 vs 修改、并发移动），
// 由用户选择保留 `LocalData` 或 `ServerData`。
//
// **算法来源**: CRDT 冲突解决理论中的应用层介入模式。
func ResolveManual(c *Conflict, chooseLocal bool) *ConflictResolution {
	if chooseLocal {
		return &ConflictResolution{
			NoteID:     c.NoteID,
			ChosenData: c.LocalData,
			Version:    c.LocalVersion,
		}
	}
	return &ConflictResolution{
		NoteID:     c.NoteID,
		ChosenData: c.ServerData,
		Version:    c.ServerVersion,
	}
}
