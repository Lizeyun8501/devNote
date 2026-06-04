use devnote_observe::{instrument, warn};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc, Duration};
use std::sync::Mutex;
use rusqlite::params;
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CardType {
    Basic,
    Cloze,
    Reverse,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Flashcard {
    pub id: Uuid,
    pub note_id: Option<Uuid>,
    pub card_type: CardType,
    pub front: String,
    pub back: String,
    pub deck_id: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlashcardDeck {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewRecord {
    pub id: Uuid,
    pub flashcard_id: Uuid,
    pub quality: u8,
    pub reviewed_at: DateTime<Utc>,
    pub next_review: DateTime<Utc>,
    pub ease_factor: f64,
    pub interval: i64,
    pub repetitions: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Sm2Result {
    pub next_review: DateTime<Utc>,
    pub new_ease_factor: f64,
    pub new_interval: i64,
    pub new_repetitions: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewStats {
    pub total_cards: i64,
    pub due_cards: i64,
    pub reviewed_today: i64,
    pub average_quality: f64,
}

#[instrument]
pub fn calculate_next_review(quality: u8, ease_factor: f64, interval: i64, repetitions: i32) -> Sm2Result {
    let quality = quality.min(5);
    let new_ease_factor = if quality < 3 {
        2.5
    } else {
        (ease_factor + (0.1 - (5 - quality) as f64 * (0.08 + (5 - quality) as f64 * 0.02))).max(1.3)
    };

    let (new_interval, new_repetitions) = if quality < 3 {
        (1, 0)
    } else {
        let new_reps = repetitions + 1;
        let new_interval = match new_reps {
            1 => 1,
            2 => 6,
            _ => (interval as f64 * new_ease_factor).round() as i64,
        };
        (new_interval, new_reps)
    };

    let next_review = Utc::now() + Duration::days(new_interval);

    Sm2Result {
        next_review,
        new_ease_factor,
        new_interval,
        new_repetitions,
    }
}

#[derive(Debug, Error)]
pub enum FlashcardError {
    #[error("deck not found: {0}")]
    DeckNotFound(Uuid),
    #[error("flashcard not found: {0}")]
    FlashcardNotFound(Uuid),
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
}

pub trait FlashcardEngine: Send + Sync {
    fn create_deck(&self, name: &str, description: &str) -> Result<FlashcardDeck, FlashcardError>;
    fn delete_deck(&self, id: &Uuid) -> Result<(), FlashcardError>;
    fn list_decks(&self) -> Result<Vec<FlashcardDeck>, FlashcardError>;
    fn create_flashcard(&self, deck_id: &Uuid, card_type: CardType, front: &str, back: &str, note_id: Option<Uuid>) -> Result<Flashcard, FlashcardError>;
    fn update_flashcard(&self, id: &Uuid, front: &str, back: &str) -> Result<Flashcard, FlashcardError>;
    fn delete_flashcard(&self, id: &Uuid) -> Result<(), FlashcardError>;
    fn review_flashcard(&self, flashcard_id: &Uuid, quality: u8) -> Result<ReviewRecord, FlashcardError>;
    fn get_due_cards(&self, deck_id: &Uuid, limit: usize) -> Result<Vec<Flashcard>, FlashcardError>;
    fn get_review_stats(&self, deck_id: &Uuid) -> Result<ReviewStats, FlashcardError>;
}

const FLASHCARD_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS flashcard_decks (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS flashcards (
    id TEXT PRIMARY KEY,
    note_id TEXT,
    card_type TEXT NOT NULL DEFAULT 'Basic',
    front TEXT NOT NULL,
    back TEXT NOT NULL,
    deck_id TEXT NOT NULL REFERENCES flashcard_decks(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS review_records (
    id TEXT PRIMARY KEY,
    flashcard_id TEXT NOT NULL REFERENCES flashcards(id) ON DELETE CASCADE,
    quality INTEGER NOT NULL,
    reviewed_at TEXT NOT NULL,
    next_review TEXT NOT NULL,
    ease_factor REAL NOT NULL DEFAULT 2.5,
    interval INTEGER NOT NULL DEFAULT 0,
    repetitions INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_flashcards_deck ON flashcards(deck_id);
CREATE INDEX IF NOT EXISTS idx_reviews_flashcard ON review_records(flashcard_id);
CREATE INDEX IF NOT EXISTS idx_reviews_next ON review_records(next_review);
"#;

pub struct SqliteFlashcardEngine {
    conn: Mutex<rusqlite::Connection>,
}

impl SqliteFlashcardEngine {
    pub fn init(db_path: &str) -> Result<Self, FlashcardError> {
        let conn = rusqlite::Connection::open(db_path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    pub fn in_memory() -> Result<Self, FlashcardError> {
        let conn = rusqlite::Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    fn init_schema(&self) -> Result<(), FlashcardError> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(FLASHCARD_SCHEMA)?;
        Ok(())
    }

    fn get_latest_review(&self, flashcard_id: &Uuid) -> Result<Option<ReviewRecord>, FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let fid_str = flashcard_id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, flashcard_id, quality, reviewed_at, next_review, ease_factor, interval, repetitions FROM review_records WHERE flashcard_id = ?1 ORDER BY reviewed_at DESC LIMIT 1"
        )?;
        let result = stmt.query_map(params![fid_str], |row| {
            let id_str: String = row.get(0)?;
            let fid_str: String = row.get(1)?;
            let quality: u8 = row.get(2)?;
            let reviewed_at_str: String = row.get(3)?;
            let next_review_str: String = row.get(4)?;
            let ease_factor: f64 = row.get(5)?;
            let interval: i64 = row.get(6)?;
            let repetitions: i32 = row.get(7)?;

            Ok(ReviewRecord {
                id: Uuid::parse_str(&id_str).unwrap(),
                flashcard_id: Uuid::parse_str(&fid_str).unwrap(),
                quality,
                reviewed_at: reviewed_at_str.parse().unwrap_or_else(|_| Utc::now()),
                next_review: next_review_str.parse().unwrap_or_else(|_| Utc::now()),
                ease_factor,
                interval,
                repetitions,
            })
        })?.next();

        match result {
            Some(Ok(record)) => Ok(Some(record)),
            Some(Err(_)) => Ok(None),
            None => Ok(None),
        }
    }
}

impl FlashcardEngine for SqliteFlashcardEngine {
    fn create_deck(&self, name: &str, description: &str) -> Result<FlashcardDeck, FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let id = Uuid::new_v4();
        let now = Utc::now();
        conn.execute(
            "INSERT INTO flashcard_decks (id, name, description, created_at) VALUES (?1, ?2, ?3, ?4)",
            params![id.to_string(), name, description, now.to_rfc3339()],
        )?;
        Ok(FlashcardDeck {
            id,
            name: name.to_string(),
            description: description.to_string(),
            created_at: now,
        })
    }

    fn delete_deck(&self, id: &Uuid) -> Result<(), FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let affected = conn.execute("DELETE FROM flashcard_decks WHERE id = ?1", params![id.to_string()])?;
        if affected == 0 {
            return Err(FlashcardError::DeckNotFound(*id));
        }
        Ok(())
    }

    fn list_decks(&self) -> Result<Vec<FlashcardDeck>, FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT id, name, description, created_at FROM flashcard_decks ORDER BY created_at")?;
        let decks = stmt.query_map([], |row| {
            let id_str: String = row.get(0)?;
            let name: String = row.get(1)?;
            let description: String = row.get(2)?;
            let created_at_str: String = row.get(3)?;
            Ok(FlashcardDeck {
                id: Uuid::parse_str(&id_str).unwrap(),
                name,
                description,
                created_at: created_at_str.parse().unwrap_or_else(|_| Utc::now()),
            })
        })?.collect::<Result<Vec<_>, _>>()?;
        Ok(decks)
    }

    fn create_flashcard(&self, deck_id: &Uuid, card_type: CardType, front: &str, back: &str, note_id: Option<Uuid>) -> Result<Flashcard, FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let deck_id_str = deck_id.to_string();
        let exists: bool = conn.query_row(
            "SELECT COUNT(*) FROM flashcard_decks WHERE id = ?1",
            params![deck_id_str],
            |row| row.get::<_, i64>(0).map(|c| c > 0),
        )?;
        if !exists {
            return Err(FlashcardError::DeckNotFound(*deck_id));
        }

        let id = Uuid::new_v4();
        let now = Utc::now();
        let ct_str = match card_type {
            CardType::Basic => "Basic",
            CardType::Cloze => "Cloze",
            CardType::Reverse => "Reverse",
        };
        let note_id_str = note_id.map(|n| n.to_string());

        conn.execute(
            "INSERT INTO flashcards (id, note_id, card_type, front, back, deck_id, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![id.to_string(), note_id_str, ct_str, front, back, deck_id_str, now.to_rfc3339()],
        )?;

        Ok(Flashcard {
            id,
            note_id,
            card_type,
            front: front.to_string(),
            back: back.to_string(),
            deck_id: *deck_id,
            created_at: now,
        })
    }

    fn update_flashcard(&self, id: &Uuid, front: &str, back: &str) -> Result<Flashcard, FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();

        let existing: (String, Option<String>, Uuid, String, DateTime<Utc>) = conn.query_row(
            "SELECT card_type, note_id, deck_id, front, created_at FROM flashcards WHERE id = ?1",
            params![id_str],
            |row| {
                let ct: String = row.get(0)?;
                let note_id_str: Option<String> = row.get(1)?;
                let deck_id_str: String = row.get(2)?;
                let front_str: String = row.get(3)?;
                let created_at_str: String = row.get(4)?;
                Ok((
                    ct,
                    note_id_str,
                    Uuid::parse_str(&deck_id_str).unwrap(),
                    front_str,
                    created_at_str.parse().unwrap_or_else(|_| Utc::now()),
                ))
            },
        ).map_err(|_| FlashcardError::FlashcardNotFound(*id))?;

        conn.execute(
            "UPDATE flashcards SET front = ?1, back = ?2 WHERE id = ?3",
            params![front, back, id_str],
        )?;

        let card_type = match existing.0.as_str() {
            "Cloze" => CardType::Cloze,
            "Reverse" => CardType::Reverse,
            _ => CardType::Basic,
        };

        Ok(Flashcard {
            id: *id,
            note_id: existing.1.and_then(|s| Uuid::parse_str(&s).ok()),
            card_type,
            front: front.to_string(),
            back: back.to_string(),
            deck_id: existing.2,
            created_at: existing.4,
        })
    }

    fn delete_flashcard(&self, id: &Uuid) -> Result<(), FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let affected = conn.execute("DELETE FROM flashcards WHERE id = ?1", params![id.to_string()])?;
        if affected == 0 {
            return Err(FlashcardError::FlashcardNotFound(*id));
        }
        Ok(())
    }

    fn review_flashcard(&self, flashcard_id: &Uuid, quality: u8) -> Result<ReviewRecord, FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let fid_str = flashcard_id.to_string();
        let exists: bool = conn.query_row(
            "SELECT COUNT(*) FROM flashcards WHERE id = ?1",
            params![fid_str],
            |row| row.get::<_, i64>(0).map(|c| c > 0),
        )?;
        if !exists {
            return Err(FlashcardError::FlashcardNotFound(*flashcard_id));
        }
        drop(conn);

        let latest = self.get_latest_review(flashcard_id)?;
        let (ease_factor, interval, repetitions) = match latest {
            Some(r) => (r.ease_factor, r.interval, r.repetitions),
            None => (2.5, 0, 0),
        };

        let result = calculate_next_review(quality, ease_factor, interval, repetitions);

        let conn = self.conn.lock().unwrap();
        let record_id = Uuid::new_v4();
        let now = Utc::now();
        conn.execute(
            "INSERT INTO review_records (id, flashcard_id, quality, reviewed_at, next_review, ease_factor, interval, repetitions) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                record_id.to_string(),
                fid_str,
                quality as i32,
                now.to_rfc3339(),
                result.next_review.to_rfc3339(),
                result.new_ease_factor,
                result.new_interval,
                result.new_repetitions,
            ],
        )?;

        Ok(ReviewRecord {
            id: record_id,
            flashcard_id: *flashcard_id,
            quality,
            reviewed_at: now,
            next_review: result.next_review,
            ease_factor: result.new_ease_factor,
            interval: result.new_interval,
            repetitions: result.new_repetitions,
        })
    }

    fn get_due_cards(&self, deck_id: &Uuid, limit: usize) -> Result<Vec<Flashcard>, FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let deck_id_str = deck_id.to_string();
        let now_str = Utc::now().to_rfc3339();

        let mut stmt = conn.prepare(
            "SELECT f.id, f.note_id, f.card_type, f.front, f.back, f.deck_id, f.created_at \
             FROM flashcards f \
             LEFT JOIN (SELECT flashcard_id, MAX(next_review) as next_review FROM review_records GROUP BY flashcard_id) r \
             ON f.id = r.flashcard_id \
             WHERE f.deck_id = ?1 AND (r.next_review IS NULL OR r.next_review <= ?2) \
             ORDER BY f.created_at \
             LIMIT ?3"
        )?;

        let cards = stmt.query_map(params![deck_id_str, now_str, limit as i64], |row| {
            let id_str: String = row.get(0)?;
            let note_id_str: Option<String> = row.get(1)?;
            let ct_str: String = row.get(2)?;
            let front: String = row.get(3)?;
            let back: String = row.get(4)?;
            let did_str: String = row.get(5)?;
            let created_at_str: String = row.get(6)?;

            let card_type = match ct_str.as_str() {
                "Cloze" => CardType::Cloze,
                "Reverse" => CardType::Reverse,
                _ => CardType::Basic,
            };

            Ok(Flashcard {
                id: Uuid::parse_str(&id_str).unwrap(),
                note_id: note_id_str.and_then(|s| Uuid::parse_str(&s).ok()),
                card_type,
                front,
                back,
                deck_id: Uuid::parse_str(&did_str).unwrap(),
                created_at: created_at_str.parse().unwrap_or_else(|_| Utc::now()),
            })
        })?.collect::<Result<Vec<_>, _>>()?;

        Ok(cards)
    }

    fn get_review_stats(&self, deck_id: &Uuid) -> Result<ReviewStats, FlashcardError> {
        let conn = self.conn.lock().unwrap();
        let deck_id_str = deck_id.to_string();

        let total_cards: i64 = conn.query_row(
            "SELECT COUNT(*) FROM flashcards WHERE deck_id = ?1",
            params![deck_id_str],
            |row| row.get(0),
        )?;

        let now_str = Utc::now().to_rfc3339();
        let due_cards: i64 = conn.query_row(
            "SELECT COUNT(*) FROM flashcards f \
             LEFT JOIN (SELECT flashcard_id, MAX(next_review) as next_review FROM review_records GROUP BY flashcard_id) r \
             ON f.id = r.flashcard_id \
             WHERE f.deck_id = ?1 AND (r.next_review IS NULL OR r.next_review <= ?2)",
            params![deck_id_str, now_str],
            |row| row.get(0),
        )?;

        let today_start = Utc::now().date_naive().and_hms_opt(0, 0, 0).unwrap();
        let today_start_str = DateTime::<Utc>::from_naive_utc_and_offset(today_start, Utc).to_rfc3339();
        let reviewed_today: i64 = conn.query_row(
            "SELECT COUNT(DISTINCT flashcard_id) FROM review_records WHERE flashcard_id IN (SELECT id FROM flashcards WHERE deck_id = ?1) AND reviewed_at >= ?2",
            params![deck_id_str, today_start_str],
            |row| row.get(0),
        )?;

        let avg_quality: f64 = conn.query_row(
            "SELECT COALESCE(AVG(quality), 0.0) FROM review_records WHERE flashcard_id IN (SELECT id FROM flashcards WHERE deck_id = ?1)",
            params![deck_id_str],
            |row| row.get(0),
        ).unwrap_or(0.0);

        Ok(ReviewStats {
            total_cards,
            due_cards,
            reviewed_today,
            average_quality: avg_quality,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sm2_algorithm() {
        let result = calculate_next_review(5, 2.5, 0, 0);
        assert_eq!(result.new_repetitions, 1);
        assert_eq!(result.new_interval, 1);

        let result = calculate_next_review(4, 2.5, 1, 1);
        assert_eq!(result.new_repetitions, 2);
        assert_eq!(result.new_interval, 6);

        let result = calculate_next_review(3, 2.5, 6, 2);
        assert_eq!(result.new_repetitions, 3);
        assert!(result.new_interval > 6);

        let result = calculate_next_review(1, 2.5, 6, 2);
        assert_eq!(result.new_repetitions, 0);
        assert_eq!(result.new_interval, 1);
    }

    #[test]
    fn test_create_deck() {
        let engine = SqliteFlashcardEngine::in_memory().unwrap();
        let deck = engine.create_deck("Test Deck", "A test deck").unwrap();
        assert_eq!(deck.name, "Test Deck");
    }

    #[test]
    fn test_create_flashcard() {
        let engine = SqliteFlashcardEngine::in_memory().unwrap();
        let deck = engine.create_deck("Test", "").unwrap();
        let card = engine.create_flashcard(&deck.id, CardType::Basic, "Front", "Back", None).unwrap();
        assert_eq!(card.front, "Front");
        assert_eq!(card.back, "Back");
    }

    #[test]
    fn test_review_flashcard() {
        let engine = SqliteFlashcardEngine::in_memory().unwrap();
        let deck = engine.create_deck("Test", "").unwrap();
        let card = engine.create_flashcard(&deck.id, CardType::Basic, "Q", "A", None).unwrap();
        let record = engine.review_flashcard(&card.id, 4).unwrap();
        assert_eq!(record.quality, 4);
        assert_eq!(record.repetitions, 1);
    }

    #[test]
    fn test_get_due_cards() {
        let engine = SqliteFlashcardEngine::in_memory().unwrap();
        let deck = engine.create_deck("Test", "").unwrap();
        engine.create_flashcard(&deck.id, CardType::Basic, "Q1", "A1", None).unwrap();
        engine.create_flashcard(&deck.id, CardType::Basic, "Q2", "A2", None).unwrap();

        let due = engine.get_due_cards(&deck.id, 10).unwrap();
        assert_eq!(due.len(), 2);
    }

    #[test]
    fn test_review_stats() {
        let engine = SqliteFlashcardEngine::in_memory().unwrap();
        let deck = engine.create_deck("Test", "").unwrap();
        let card = engine.create_flashcard(&deck.id, CardType::Basic, "Q", "A", None).unwrap();
        engine.review_flashcard(&card.id, 4).unwrap();

        let stats = engine.get_review_stats(&deck.id).unwrap();
        assert_eq!(stats.total_cards, 1);
        assert_eq!(stats.reviewed_today, 1);
    }
}
