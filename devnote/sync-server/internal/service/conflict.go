package service

type ConflictStrategy string

const (
	StrategyLastWriteWins ConflictStrategy = "last_write_wins"
	StrategyManual        ConflictStrategy = "manual"
)

type Conflict struct {
	RecordID    string           `json:"record_id"`
	NoteID      string           `json:"note_id"`
	LocalVersion int64           `json:"local_version"`
	ServerVersion int64          `json:"server_version"`
	LocalData   string           `json:"local_data"`
	ServerData  string           `json:"server_data"`
	Strategy    ConflictStrategy `json:"strategy"`
}

type ConflictResolution struct {
	NoteID    string `json:"note_id"`
	ChosenData string `json:"chosen_data"`
	Version   int64  `json:"version"`
}

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
