pub mod formula;

use devnote_observe::{debug, error, info, instrument, warn};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use std::sync::Mutex;
use rusqlite::params;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Database {
    pub id: Uuid,
    pub name: String,
    pub views: Vec<DatabaseView>,
    pub fields: Vec<DatabaseField>,
    pub rows: Vec<DatabaseRow>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseField {
    pub id: Uuid,
    pub name: String,
    pub field_type: FieldType,
    pub options: serde_json::Value,
    pub formula: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FieldType {
    Text,
    Number,
    Select,
    MultiSelect,
    Date,
    Checkbox,
    URL,
    Relation,
    Formula,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseRow {
    pub id: Uuid,
    pub cells: Vec<DatabaseCell>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseCell {
    pub field_id: Uuid,
    pub value: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseView {
    pub id: Uuid,
    pub name: String,
    pub view_type: ViewType,
    pub filters: Vec<Filter>,
    pub sorts: Vec<Sort>,
    pub group_by: Option<Uuid>,
    pub field_orders: Vec<FieldOrder>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ViewType {
    Table,
    Kanban,
    Calendar,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Filter {
    pub field_id: Uuid,
    pub operator: String,
    pub value: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Sort {
    pub field_id: Uuid,
    pub direction: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldOrder {
    pub field_id: Uuid,
    pub position: i64,
}

#[derive(Debug, thiserror::Error)]
pub enum DatabaseError {
    #[error("Database not found: {0}")]
    NotFound(Uuid),
    #[error("Field not found: {0}")]
    FieldNotFound(Uuid),
    #[error("Row not found: {0}")]
    RowNotFound(Uuid),
    #[error("View not found: {0}")]
    ViewNotFound(Uuid),
    #[error("Formula error: {0}")]
    FormulaError(String),
    #[error("SQLite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

pub trait DatabaseEngine: Send + Sync {
    fn create_database(&self, name: &str) -> Result<Database, DatabaseError>;
    fn delete_database(&self, id: &Uuid) -> Result<(), DatabaseError>;
    fn get_database(&self, id: &Uuid) -> Result<Database, DatabaseError>;

    fn add_field(&self, db_id: &Uuid, name: &str, field_type: FieldType, options: serde_json::Value, formula: Option<String>) -> Result<DatabaseField, DatabaseError>;
    fn update_field(&self, db_id: &Uuid, field_id: &Uuid, name: &str, options: serde_json::Value) -> Result<DatabaseField, DatabaseError>;
    fn delete_field(&self, db_id: &Uuid, field_id: &Uuid) -> Result<(), DatabaseError>;

    fn add_row(&self, db_id: &Uuid, cells: Vec<DatabaseCell>) -> Result<DatabaseRow, DatabaseError>;
    fn update_row(&self, db_id: &Uuid, row_id: &Uuid, cells: Vec<DatabaseCell>) -> Result<DatabaseRow, DatabaseError>;
    fn delete_row(&self, db_id: &Uuid, row_id: &Uuid) -> Result<(), DatabaseError>;
    fn get_rows(&self, db_id: &Uuid) -> Result<Vec<DatabaseRow>, DatabaseError>;

    fn update_cell(&self, db_id: &Uuid, row_id: &Uuid, field_id: &Uuid, value: serde_json::Value) -> Result<DatabaseCell, DatabaseError>;

    fn add_view(&self, db_id: &Uuid, name: &str, view_type: ViewType) -> Result<DatabaseView, DatabaseError>;
    fn update_view(&self, db_id: &Uuid, view_id: &Uuid, name: &str, filters: Vec<Filter>, sorts: Vec<Sort>, group_by: Option<Uuid>) -> Result<DatabaseView, DatabaseError>;
    fn delete_view(&self, db_id: &Uuid, view_id: &Uuid) -> Result<(), DatabaseError>;

    fn apply_filter(&self, rows: &[DatabaseRow], filters: &[Filter], fields: &[DatabaseField]) -> Vec<DatabaseRow>;
    fn apply_sort(&self, rows: &[DatabaseRow], sorts: &[Sort], fields: &[DatabaseField]) -> Vec<DatabaseRow>;
}

const DB_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS databases (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS database_fields (
    id TEXT PRIMARY KEY,
    database_id TEXT NOT NULL REFERENCES databases(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    field_type TEXT NOT NULL,
    options TEXT NOT NULL DEFAULT '{}',
    formula TEXT,
    position INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS database_rows (
    id TEXT PRIMARY KEY,
    database_id TEXT NOT NULL REFERENCES databases(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS database_cells (
    row_id TEXT NOT NULL REFERENCES database_rows(id) ON DELETE CASCADE,
    field_id TEXT NOT NULL REFERENCES database_fields(id) ON DELETE CASCADE,
    value TEXT NOT NULL DEFAULT 'null',
    PRIMARY KEY (row_id, field_id)
);

CREATE TABLE IF NOT EXISTS database_views (
    id TEXT PRIMARY KEY,
    database_id TEXT NOT NULL REFERENCES databases(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    view_type TEXT NOT NULL,
    filters TEXT NOT NULL DEFAULT '[]',
    sorts TEXT NOT NULL DEFAULT '[]',
    group_by TEXT,
    field_orders TEXT NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_fields_db ON database_fields(database_id);
CREATE INDEX IF NOT EXISTS idx_rows_db ON database_rows(database_id);
CREATE INDEX IF NOT EXISTS idx_cells_row ON database_cells(row_id);
CREATE INDEX IF NOT EXISTS idx_views_db ON database_views(database_id);
"#;

#[derive(Debug)]
pub struct SqliteDatabaseEngine {
    conn: Mutex<rusqlite::Connection>,
}

impl SqliteDatabaseEngine {
    pub fn init(db_path: &str) -> Result<Self, DatabaseError> {
        let conn = rusqlite::Connection::open(db_path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    pub fn in_memory() -> Result<Self, DatabaseError> {
        let conn = rusqlite::Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    fn init_schema(&self) -> Result<(), DatabaseError> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(DB_SCHEMA)?;
        Ok(())
    }

    fn load_database(&self, id: &Uuid) -> Result<Database, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();

        let name: String = conn.query_row(
            "SELECT name FROM databases WHERE id = ?1",
            params![id_str],
            |row| row.get(0),
        ).map_err(|_| DatabaseError::NotFound(*id))?;

        let fields = self.load_fields(&conn, id)?;
        let rows = self.load_rows(&conn, id)?;
        let views = self.load_views(&conn, id)?;

        Ok(Database {
            id: *id,
            name,
            views,
            fields,
            rows,
        })
    }

    fn load_fields(&self, conn: &rusqlite::Connection, db_id: &Uuid) -> Result<Vec<DatabaseField>, DatabaseError> {
        let db_id_str = db_id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, name, field_type, options, formula FROM database_fields WHERE database_id = ?1 ORDER BY position"
        )?;
        let fields = stmt.query_map(params![db_id_str], |row| {
            let id_str: String = row.get(0)?;
            let name: String = row.get(1)?;
            let ft_str: String = row.get(2)?;
            let options_str: String = row.get(3)?;
            let formula: Option<String> = row.get(4)?;

            let field_type = match ft_str.as_str() {
                "Text" => FieldType::Text,
                "Number" => FieldType::Number,
                "Select" => FieldType::Select,
                "MultiSelect" => FieldType::MultiSelect,
                "Date" => FieldType::Date,
                "Checkbox" => FieldType::Checkbox,
                "URL" => FieldType::URL,
                "Relation" => FieldType::Relation,
                "Formula" => FieldType::Formula,
                _ => FieldType::Text,
            };

            Ok(DatabaseField {
                id: Uuid::parse_str(&id_str).unwrap(),
                name,
                field_type,
                options: serde_json::from_str(&options_str).unwrap_or(serde_json::Value::Null),
                formula,
            })
        })?.collect::<Result<Vec<_>, _>>()?;

        Ok(fields)
    }

    fn load_rows(&self, conn: &rusqlite::Connection, db_id: &Uuid) -> Result<Vec<DatabaseRow>, DatabaseError> {
        let db_id_str = db_id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, created_at, updated_at FROM database_rows WHERE database_id = ?1"
        )?;

        let row_ids: Vec<(Uuid, String, String)> = stmt.query_map(params![db_id_str], |row| {
            Ok((
                Uuid::parse_str(&row.get::<_, String>(0)?).unwrap(),
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })?.collect::<Result<Vec<_>, _>>()?;

        let mut rows = Vec::new();
        for (row_id, created_at_str, updated_at_str) in row_ids {
            let cells = self.load_cells(conn, &row_id)?;
            rows.push(DatabaseRow {
                id: row_id,
                cells,
                created_at: created_at_str.parse().unwrap_or_else(|_| Utc::now()),
                updated_at: updated_at_str.parse().unwrap_or_else(|_| Utc::now()),
            });
        }

        Ok(rows)
    }

    fn load_cells(&self, conn: &rusqlite::Connection, row_id: &Uuid) -> Result<Vec<DatabaseCell>, DatabaseError> {
        let row_id_str = row_id.to_string();
        let mut stmt = conn.prepare(
            "SELECT field_id, value FROM database_cells WHERE row_id = ?1"
        )?;
        let cells = stmt.query_map(params![row_id_str], |row| {
            let field_id_str: String = row.get(0)?;
            let value_str: String = row.get(1)?;
            Ok(DatabaseCell {
                field_id: Uuid::parse_str(&field_id_str).unwrap(),
                value: serde_json::from_str(&value_str).unwrap_or(serde_json::Value::Null),
            })
        })?.collect::<Result<Vec<_>, _>>()?;

        Ok(cells)
    }

    fn load_views(&self, conn: &rusqlite::Connection, db_id: &Uuid) -> Result<Vec<DatabaseView>, DatabaseError> {
        let db_id_str = db_id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, name, view_type, filters, sorts, group_by, field_orders FROM database_views WHERE database_id = ?1"
        )?;
        let views = stmt.query_map(params![db_id_str], |row| {
            let id_str: String = row.get(0)?;
            let name: String = row.get(1)?;
            let vt_str: String = row.get(2)?;
            let filters_str: String = row.get(3)?;
            let sorts_str: String = row.get(4)?;
            let group_by: Option<String> = row.get(5)?;
            let field_orders_str: String = row.get(6)?;

            let view_type = match vt_str.as_str() {
                "Kanban" => ViewType::Kanban,
                "Calendar" => ViewType::Calendar,
                _ => ViewType::Table,
            };

            Ok(DatabaseView {
                id: Uuid::parse_str(&id_str).unwrap(),
                name,
                view_type,
                filters: serde_json::from_str(&filters_str).unwrap_or_default(),
                sorts: serde_json::from_str(&sorts_str).unwrap_or_default(),
                group_by: group_by.and_then(|s| Uuid::parse_str(&s).ok()),
                field_orders: serde_json::from_str(&field_orders_str).unwrap_or_default(),
            })
        })?.collect::<Result<Vec<_>, _>>()?;

        Ok(views)
    }
}

impl DatabaseEngine for SqliteDatabaseEngine {
    #[instrument]
    fn create_database(&self, name: &str) -> Result<Database, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let id = Uuid::new_v4();
        let id_str = id.to_string();

        conn.execute(
            "INSERT INTO databases (id, name) VALUES (?1, ?2)",
            params![id_str, name],
        )?;

        let default_view_id = Uuid::new_v4();
        conn.execute(
            "INSERT INTO database_views (id, database_id, name, view_type) VALUES (?1, ?2, ?3, ?4)",
            params![default_view_id.to_string(), id_str, "Table View", "Table"],
        )?;

        Ok(Database {
            id,
            name: name.to_string(),
            views: vec![DatabaseView {
                id: default_view_id,
                name: "Table View".to_string(),
                view_type: ViewType::Table,
                filters: vec![],
                sorts: vec![],
                group_by: None,
                field_orders: vec![],
            }],
            fields: vec![],
            rows: vec![],
        })
    }

    fn delete_database(&self, id: &Uuid) -> Result<(), DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();
        let affected = conn.execute("DELETE FROM databases WHERE id = ?1", params![id_str])?;
        if affected == 0 {
            return Err(DatabaseError::NotFound(*id));
        }
        Ok(())
    }

    fn get_database(&self, id: &Uuid) -> Result<Database, DatabaseError> {
        self.load_database(id)
    }

    fn add_field(&self, db_id: &Uuid, name: &str, field_type: FieldType, options: serde_json::Value, formula: Option<String>) -> Result<DatabaseField, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let db_id_str = db_id.to_string();

        let exists: bool = conn.query_row(
            "SELECT COUNT(*) FROM databases WHERE id = ?1",
            params![db_id_str],
            |row| row.get::<_, i64>(0).map(|c| c > 0),
        )?;
        if !exists {
            return Err(DatabaseError::NotFound(*db_id));
        }

        let id = Uuid::new_v4();
        let ft_str = match field_type {
            FieldType::Text => "Text",
            FieldType::Number => "Number",
            FieldType::Select => "Select",
            FieldType::MultiSelect => "MultiSelect",
            FieldType::Date => "Date",
            FieldType::Checkbox => "Checkbox",
            FieldType::URL => "URL",
            FieldType::Relation => "Relation",
            FieldType::Formula => "Formula",
        };

        let position: i64 = conn.query_row(
            "SELECT COALESCE(MAX(position), -1) + 1 FROM database_fields WHERE database_id = ?1",
            params![db_id_str],
            |row| row.get(0),
        )?;

        conn.execute(
            "INSERT INTO database_fields (id, database_id, name, field_type, options, formula, position) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![id.to_string(), db_id_str, name, ft_str, options.to_string(), formula, position],
        )?;

        Ok(DatabaseField {
            id,
            name: name.to_string(),
            field_type,
            options,
            formula,
        })
    }

    fn update_field(&self, db_id: &Uuid, field_id: &Uuid, name: &str, options: serde_json::Value) -> Result<DatabaseField, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let field_id_str = field_id.to_string();

        let ft_str: String = conn.query_row(
            "SELECT field_type FROM database_fields WHERE id = ?1 AND database_id = ?2",
            params![field_id_str, db_id.to_string()],
            |row| row.get(0),
        ).map_err(|_| DatabaseError::FieldNotFound(*field_id))?;

        let formula: Option<String> = conn.query_row(
            "SELECT formula FROM database_fields WHERE id = ?1",
            params![field_id_str],
            |row| row.get(0),
        )?;

        conn.execute(
            "UPDATE database_fields SET name = ?1, options = ?2 WHERE id = ?3",
            params![name, options.to_string(), field_id_str],
        )?;

        let field_type = match ft_str.as_str() {
            "Number" => FieldType::Number,
            "Select" => FieldType::Select,
            "MultiSelect" => FieldType::MultiSelect,
            "Date" => FieldType::Date,
            "Checkbox" => FieldType::Checkbox,
            "URL" => FieldType::URL,
            "Relation" => FieldType::Relation,
            "Formula" => FieldType::Formula,
            _ => FieldType::Text,
        };

        Ok(DatabaseField {
            id: *field_id,
            name: name.to_string(),
            field_type,
            options,
            formula,
        })
    }

    fn delete_field(&self, db_id: &Uuid, field_id: &Uuid) -> Result<(), DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let field_id_str = field_id.to_string();
        let affected = conn.execute(
            "DELETE FROM database_fields WHERE id = ?1 AND database_id = ?2",
            params![field_id_str, db_id.to_string()],
        )?;
        if affected == 0 {
            return Err(DatabaseError::FieldNotFound(*field_id));
        }
        Ok(())
    }

    fn add_row(&self, db_id: &Uuid, cells: Vec<DatabaseCell>) -> Result<DatabaseRow, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let db_id_str = db_id.to_string();

        let exists: bool = conn.query_row(
            "SELECT COUNT(*) FROM databases WHERE id = ?1",
            params![db_id_str],
            |row| row.get::<_, i64>(0).map(|c| c > 0),
        )?;
        if !exists {
            return Err(DatabaseError::NotFound(*db_id));
        }

        let id = Uuid::new_v4();
        let now = Utc::now();
        let now_str = now.to_rfc3339();

        conn.execute(
            "INSERT INTO database_rows (id, database_id, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)",
            params![id.to_string(), db_id_str, now_str, now_str],
        )?;

        for cell in &cells {
            conn.execute(
                "INSERT INTO database_cells (row_id, field_id, value) VALUES (?1, ?2, ?3)",
                params![id.to_string(), cell.field_id.to_string(), cell.value.to_string()],
            )?;
        }

        Ok(DatabaseRow {
            id,
            cells,
            created_at: now,
            updated_at: now,
        })
    }

    fn update_row(&self, db_id: &Uuid, row_id: &Uuid, cells: Vec<DatabaseCell>) -> Result<DatabaseRow, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let row_id_str = row_id.to_string();
        let now = Utc::now();

        let exists: bool = conn.query_row(
            "SELECT COUNT(*) FROM database_rows WHERE id = ?1 AND database_id = ?2",
            params![row_id_str, db_id.to_string()],
            |row| row.get::<_, i64>(0).map(|c| c > 0),
        )?;
        if !exists {
            return Err(DatabaseError::RowNotFound(*row_id));
        }

        conn.execute(
            "UPDATE database_rows SET updated_at = ?1 WHERE id = ?2",
            params![now.to_rfc3339(), row_id_str],
        )?;

        for cell in &cells {
            conn.execute(
                "INSERT OR REPLACE INTO database_cells (row_id, field_id, value) VALUES (?1, ?2, ?3)",
                params![row_id_str, cell.field_id.to_string(), cell.value.to_string()],
            )?;
        }

        Ok(DatabaseRow {
            id: *row_id,
            cells,
            created_at: now,
            updated_at: now,
        })
    }

    fn delete_row(&self, db_id: &Uuid, row_id: &Uuid) -> Result<(), DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let affected = conn.execute(
            "DELETE FROM database_rows WHERE id = ?1 AND database_id = ?2",
            params![row_id.to_string(), db_id.to_string()],
        )?;
        if affected == 0 {
            return Err(DatabaseError::RowNotFound(*row_id));
        }
        Ok(())
    }

    fn get_rows(&self, db_id: &Uuid) -> Result<Vec<DatabaseRow>, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        self.load_rows(&conn, db_id)
    }

    fn update_cell(&self, _db_id: &Uuid, row_id: &Uuid, field_id: &Uuid, value: serde_json::Value) -> Result<DatabaseCell, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let now = Utc::now();

        conn.execute(
            "UPDATE database_rows SET updated_at = ?1 WHERE id = ?2",
            params![now.to_rfc3339(), row_id.to_string()],
        )?;

        conn.execute(
            "INSERT OR REPLACE INTO database_cells (row_id, field_id, value) VALUES (?1, ?2, ?3)",
            params![row_id.to_string(), field_id.to_string(), value.to_string()],
        )?;

        Ok(DatabaseCell {
            field_id: *field_id,
            value,
        })
    }

    #[instrument]
    fn add_view(&self, db_id: &Uuid, name: &str, view_type: ViewType) -> Result<DatabaseView, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let id = Uuid::new_v4();
        let vt_str = match view_type {
            ViewType::Table => "Table",
            ViewType::Kanban => "Kanban",
            ViewType::Calendar => "Calendar",
        };

        conn.execute(
            "INSERT INTO database_views (id, database_id, name, view_type) VALUES (?1, ?2, ?3, ?4)",
            params![id.to_string(), db_id.to_string(), name, vt_str],
        )?;

        Ok(DatabaseView {
            id,
            name: name.to_string(),
            view_type,
            filters: vec![],
            sorts: vec![],
            group_by: None,
            field_orders: vec![],
        })
    }

    fn update_view(&self, db_id: &Uuid, view_id: &Uuid, name: &str, filters: Vec<Filter>, sorts: Vec<Sort>, group_by: Option<Uuid>) -> Result<DatabaseView, DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let view_id_str = view_id.to_string();

        let vt_str: String = conn.query_row(
            "SELECT view_type FROM database_views WHERE id = ?1 AND database_id = ?2",
            params![view_id_str, db_id.to_string()],
            |row| row.get(0),
        ).map_err(|_| DatabaseError::ViewNotFound(*view_id))?;

        let view_type = match vt_str.as_str() {
            "Kanban" => ViewType::Kanban,
            "Calendar" => ViewType::Calendar,
            _ => ViewType::Table,
        };

        conn.execute(
            "UPDATE database_views SET name = ?1, filters = ?2, sorts = ?3, group_by = ?4 WHERE id = ?5",
            params![
                name,
                serde_json::to_string(&filters).unwrap_or_default(),
                serde_json::to_string(&sorts).unwrap_or_default(),
                group_by.map(|g| g.to_string()),
                view_id_str,
            ],
        )?;

        Ok(DatabaseView {
            id: *view_id,
            name: name.to_string(),
            view_type,
            filters,
            sorts,
            group_by,
            field_orders: vec![],
        })
    }

    fn delete_view(&self, db_id: &Uuid, view_id: &Uuid) -> Result<(), DatabaseError> {
        let conn = self.conn.lock().unwrap();
        let affected = conn.execute(
            "DELETE FROM database_views WHERE id = ?1 AND database_id = ?2",
            params![view_id.to_string(), db_id.to_string()],
        )?;
        if affected == 0 {
            return Err(DatabaseError::ViewNotFound(*view_id));
        }
        Ok(())
    }

    fn apply_filter(&self, rows: &[DatabaseRow], filters: &[Filter], _fields: &[DatabaseField]) -> Vec<DatabaseRow> {
        rows.iter()
            .filter(|row| {
                filters.iter().all(|filter| {
                    let cell = row.cells.iter().find(|c| c.field_id == filter.field_id);
                    match cell {
                        Some(c) => {
                            let cell_str = match &c.value {
                                serde_json::Value::String(s) => s.clone(),
                                other => other.to_string(),
                            };
                            let filter_str = match &filter.value {
                                serde_json::Value::String(s) => s.clone(),
                                other => other.to_string(),
                            };
                            match filter.operator.as_str() {
                                "contains" => cell_str.contains(&filter_str),
                                "equals" => cell_str == filter_str,
                                "not_equals" => cell_str != filter_str,
                                "starts_with" => cell_str.starts_with(&filter_str),
                                "ends_with" => cell_str.ends_with(&filter_str),
                                "greater_than" => cell_str > filter_str,
                                "less_than" => cell_str < filter_str,
                                "is_empty" => cell_str.is_empty() || cell_str == "null",
                                "is_not_empty" => !cell_str.is_empty() && cell_str != "null",
                                _ => true,
                            }
                        }
                        None => filter.operator == "is_empty",
                    }
                })
            })
            .cloned()
            .collect()
    }

    fn apply_sort(&self, rows: &[DatabaseRow], sorts: &[Sort], _fields: &[DatabaseField]) -> Vec<DatabaseRow> {
        let mut sorted = rows.to_vec();
        for sort in sorts.iter().rev() {
            let field_id = sort.field_id;
            let ascending = sort.direction != "desc";
            sorted.sort_by(|a, b| {
                let a_cell = a.cells.iter().find(|c| c.field_id == field_id);
                let b_cell = b.cells.iter().find(|c| c.field_id == field_id);
                let a_val = a_cell.map(|c| cell_sort_value(&c.value)).unwrap_or_default();
                let b_val = b_cell.map(|c| cell_sort_value(&c.value)).unwrap_or_default();
                let cmp = a_val.cmp(&b_val);
                if ascending { cmp } else { cmp.reverse() }
            });
        }
        sorted
    }
}

fn cell_sort_value(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::Number(n) => {
            if let Some(f) = n.as_f64() {
                format!("{:020.10}", f)
            } else {
                n.to_string()
            }
        }
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Bool(b) => b.to_string(),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_database() {
        let engine = SqliteDatabaseEngine::in_memory().unwrap();
        let db = engine.create_database("Test DB").unwrap();
        assert_eq!(db.name, "Test DB");
        assert!(!db.views.is_empty());
    }

    #[test]
    fn test_add_field_and_row() {
        let engine = SqliteDatabaseEngine::in_memory().unwrap();
        let db = engine.create_database("Test DB").unwrap();
        let field = engine.add_field(&db.id, "Name", FieldType::Text, serde_json::Value::Null, None).unwrap();
        let row = engine.add_row(&db.id, vec![DatabaseCell {
            field_id: field.id,
            value: serde_json::Value::String("Hello".to_string()),
        }]).unwrap();
        assert_eq!(row.cells.len(), 1);
    }

    #[test]
    fn test_filter_and_sort() {
        let engine = SqliteDatabaseEngine::in_memory().unwrap();
        let db = engine.create_database("Test").unwrap();
        let field = engine.add_field(&db.id, "Score", FieldType::Number, serde_json::Value::Null, None).unwrap();

        engine.add_row(&db.id, vec![DatabaseCell { field_id: field.id, value: serde_json::json!(10) }]).unwrap();
        engine.add_row(&db.id, vec![DatabaseCell { field_id: field.id, value: serde_json::json!(30) }]).unwrap();
        engine.add_row(&db.id, vec![DatabaseCell { field_id: field.id, value: serde_json::json!(20) }]).unwrap();

        let rows = engine.get_rows(&db.id).unwrap();
        let sorted = engine.apply_sort(&rows, &[Sort { field_id: field.id, direction: "desc".to_string() }], &[]);
        assert_eq!(sorted[0].cells[0].value, serde_json::json!(30));
    }
}
