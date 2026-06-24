use devnote_observe::{debug, error, info, instrument, warn};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use std::sync::Mutex;
use rusqlite::params;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectType {
    pub id: Uuid,
    pub name: String,
    pub icon: String,
    pub properties: Vec<ObjectProperty>,
    pub relations: Vec<ObjectRelation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectProperty {
    pub id: Uuid,
    pub name: String,
    pub property_type: PropertyType,
    pub format: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PropertyType {
    Text,
    Number,
    Select,
    Date,
    Relation,
    File,
    Checkbox,
    URL,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectRelation {
    pub id: Uuid,
    pub name: String,
    pub relation_type: RelationType,
    pub source_type: Uuid,
    pub target_type: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RelationType {
    OneToOne,
    OneToMany,
    ManyToMany,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Object {
    pub id: Uuid,
    pub object_type_id: Uuid,
    pub properties: serde_json::Value,
    pub relations: Vec<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectValue {
    pub property_id: Uuid,
    pub value: serde_json::Value,
}

#[derive(Debug, thiserror::Error)]
pub enum ObjectError {
    #[error("Object type not found: {0}")]
    TypeNotFound(Uuid),
    #[error("Object not found: {0}")]
    ObjectNotFound(Uuid),
    #[error("Relation not found: {0}")]
    RelationNotFound(Uuid),
    #[error("SQLite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("database error: {0}")]
    DatabaseError(String),
    #[error("internal error: {0}")]
    Internal(String),
}

pub trait ObjectEngine: Send + Sync {
    fn create_object_type(&self, name: &str, icon: &str, properties: Vec<ObjectProperty>) -> Result<ObjectType, ObjectError>;
    fn update_object_type(&self, type_id: &Uuid, name: &str, icon: &str) -> Result<ObjectType, ObjectError>;
    fn delete_object_type(&self, type_id: &Uuid) -> Result<(), ObjectError>;
    fn list_object_types(&self) -> Result<Vec<ObjectType>, ObjectError>;

    fn create_object(&self, type_id: &Uuid, properties: serde_json::Value) -> Result<Object, ObjectError>;
    fn update_object(&self, object_id: &Uuid, properties: serde_json::Value) -> Result<Object, ObjectError>;
    fn delete_object(&self, object_id: &Uuid) -> Result<(), ObjectError>;
    fn get_object(&self, object_id: &Uuid) -> Result<Object, ObjectError>;
    fn list_objects(&self, type_id: Option<&Uuid>) -> Result<Vec<Object>, ObjectError>;

    fn add_relation(&self, source_id: &Uuid, target_id: &Uuid, relation_id: &Uuid) -> Result<(), ObjectError>;
    fn remove_relation(&self, source_id: &Uuid, target_id: &Uuid, relation_id: &Uuid) -> Result<(), ObjectError>;
    fn get_related_objects(&self, object_id: &Uuid, relation_id: Option<&Uuid>) -> Result<Vec<Object>, ObjectError>;

    fn promote_block_to_object(&self, note_id: &Uuid, block_id: &Uuid, object_type_id: &Uuid) -> Result<Object, ObjectError>;
}

const OBJ_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS object_types (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS object_type_properties (
    id TEXT PRIMARY KEY,
    object_type_id TEXT NOT NULL REFERENCES object_types(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    property_type TEXT NOT NULL,
    format TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS object_type_relations (
    id TEXT PRIMARY KEY,
    object_type_id TEXT NOT NULL REFERENCES object_types(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    relation_type TEXT NOT NULL,
    source_type TEXT NOT NULL,
    target_type TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS objects (
    id TEXT PRIMARY KEY,
    object_type_id TEXT NOT NULL REFERENCES object_types(id) ON DELETE CASCADE,
    properties TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS object_relations (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
    target_id TEXT NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
    relation_id TEXT NOT NULL REFERENCES object_type_relations(id) ON DELETE CASCADE,
    UNIQUE(source_id, target_id, relation_id)
);

CREATE INDEX IF NOT EXISTS idx_obj_type ON objects(object_type_id);
CREATE INDEX IF NOT EXISTS idx_ot_props ON object_type_properties(object_type_id);
CREATE INDEX IF NOT EXISTS idx_ot_rels ON object_type_relations(object_type_id);
CREATE INDEX IF NOT EXISTS idx_obj_rels_source ON object_relations(source_id);
CREATE INDEX IF NOT EXISTS idx_obj_rels_target ON object_relations(target_id);
CREATE INDEX IF NOT EXISTS idx_obj_rels_rel ON object_relations(relation_id);
"#;

pub struct SqliteObjectEngine {
    conn: Mutex<rusqlite::Connection>,
}

impl SqliteObjectEngine {
    pub fn init(db_path: &str) -> Result<Self, ObjectError> {
        let conn = rusqlite::Connection::open(db_path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    /// 基于已有 SQLite 连接构造对象引擎 —— 用于共享连接池场景
    /// 调用方负责确保传入的连接已设置合适的 PRAGMA（如 WAL、foreign_keys）
    pub fn new(conn: rusqlite::Connection) -> Result<Self, ObjectError> {
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    pub fn in_memory() -> Result<Self, ObjectError> {
        let conn = rusqlite::Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    fn init_schema(&self) -> Result<(), ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        conn.execute_batch(OBJ_SCHEMA)?;
        Ok(())
    }

    fn load_object_type(&self, conn: &rusqlite::Connection, type_id: &Uuid) -> Result<ObjectType, ObjectError> {
        let type_id_str = type_id.to_string();
        let (name, icon): (String, String) = conn.query_row(
            "SELECT name, icon FROM object_types WHERE id = ?1",
            params![type_id_str],
            |row| Ok((row.get(0)?, row.get(1)?)),
        ).map_err(|e| match e {
            rusqlite::Error::QueryReturnedNoRows => ObjectError::TypeNotFound(*type_id),
            _ => ObjectError::DatabaseError(e.to_string()),
        })?;

        let properties = self.load_type_properties(conn, type_id)?;
        let relations = self.load_type_relations(conn, type_id)?;

        Ok(ObjectType {
            id: *type_id,
            name,
            icon,
            properties,
            relations,
        })
    }

    fn load_type_properties(&self, conn: &rusqlite::Connection, type_id: &Uuid) -> Result<Vec<ObjectProperty>, ObjectError> {
        let type_id_str = type_id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, name, property_type, format FROM object_type_properties WHERE object_type_id = ?1"
        )?;
        let props = stmt.query_map(params![type_id_str], |row| {
            let id_str: String = row.get(0)?;
            let name: String = row.get(1)?;
            let pt_str: String = row.get(2)?;
            let format_str: String = row.get(3)?;

            let property_type = match pt_str.as_str() {
                "Number" => PropertyType::Number,
                "Select" => PropertyType::Select,
                "Date" => PropertyType::Date,
                "Relation" => PropertyType::Relation,
                "File" => PropertyType::File,
                "Checkbox" => PropertyType::Checkbox,
                "URL" => PropertyType::URL,
                _ => PropertyType::Text,
            };

            Ok(ObjectProperty {
                id: Uuid::parse_str(&id_str)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
                name,
                property_type,
                format: serde_json::from_str(&format_str)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            })
        })?.collect::<Result<Vec<_>, _>>()?;

        Ok(props)
    }

    fn load_type_relations(&self, conn: &rusqlite::Connection, type_id: &Uuid) -> Result<Vec<ObjectRelation>, ObjectError> {
        let type_id_str = type_id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, name, relation_type, source_type, target_type FROM object_type_relations WHERE object_type_id = ?1"
        )?;
        let rels = stmt.query_map(params![type_id_str], |row| {
            let id_str: String = row.get(0)?;
            let name: String = row.get(1)?;
            let rt_str: String = row.get(2)?;
            let source_str: String = row.get(3)?;
            let target_str: String = row.get(4)?;

            let relation_type = match rt_str.as_str() {
                "OneToOne" => RelationType::OneToOne,
                "OneToMany" => RelationType::OneToMany,
                _ => RelationType::ManyToMany,
            };

            Ok(ObjectRelation {
                id: Uuid::parse_str(&id_str)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
                name,
                relation_type,
                source_type: Uuid::parse_str(&source_str)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
                target_type: Uuid::parse_str(&target_str)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            })
        })?.collect::<Result<Vec<_>, _>>()?;

        Ok(rels)
    }

    fn load_object(&self, conn: &rusqlite::Connection, object_id: &Uuid) -> Result<Object, ObjectError> {
        let object_id_str = object_id.to_string();
        let (type_id_str, props_str, created_str, updated_str): (String, String, String, String) = conn.query_row(
            "SELECT object_type_id, properties, created_at, updated_at FROM objects WHERE id = ?1",
            params![object_id_str],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        ).map_err(|e| match e {
            rusqlite::Error::QueryReturnedNoRows => ObjectError::ObjectNotFound(*object_id),
            _ => ObjectError::DatabaseError(e.to_string()),
        })?;

        let mut rel_stmt = conn.prepare(
            "SELECT target_id FROM object_relations WHERE source_id = ?1"
        )?;
        let rels: Vec<Uuid> = rel_stmt.query_map(params![object_id_str], |row| {
            let target_str: String = row.get(0)?;
            Uuid::parse_str(&target_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))
        })?.collect::<Result<Vec<_>, _>>()?;

        Ok(Object {
            id: *object_id,
            object_type_id: Uuid::parse_str(&type_id_str)
                .map_err(|e| ObjectError::DatabaseError(format!("invalid object_type_id: {e}")))?,
            properties: serde_json::from_str(&props_str)
                .map_err(|e| ObjectError::DatabaseError(format!("invalid properties JSON: {e}")))?,
            relations: rels,
            created_at: created_str.parse()
                .map_err(|e| ObjectError::DatabaseError(format!("invalid created_at timestamp: {e}")))?,
            updated_at: updated_str.parse()
                .map_err(|e| ObjectError::DatabaseError(format!("invalid updated_at timestamp: {e}")))?,
        })
    }
}

impl ObjectEngine for SqliteObjectEngine {
    #[instrument(skip(self, properties))]
    fn create_object_type(&self, name: &str, icon: &str, properties: Vec<ObjectProperty>) -> Result<ObjectType, ObjectError> {
        let mut conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let id = Uuid::new_v4();

        // P1 修复 (P1-7): INSERT 类型 + 循环 INSERT 属性包裹在事务中
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO object_types (id, name, icon) VALUES (?1, ?2, ?3)",
            params![id.to_string(), name, icon],
        )?;

        for prop in &properties {
            let pt_str = match prop.property_type {
                PropertyType::Text => "Text",
                PropertyType::Number => "Number",
                PropertyType::Select => "Select",
                PropertyType::Date => "Date",
                PropertyType::Relation => "Relation",
                PropertyType::File => "File",
                PropertyType::Checkbox => "Checkbox",
                PropertyType::URL => "URL",
            };
            tx.execute(
                "INSERT INTO object_type_properties (id, object_type_id, name, property_type, format) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![prop.id.to_string(), id.to_string(), prop.name, pt_str, prop.format.to_string()],
            )?;
        }
        tx.commit()?;

        Ok(ObjectType {
            id,
            name: name.to_string(),
            icon: icon.to_string(),
            properties,
            relations: vec![],
        })
    }

    fn update_object_type(&self, type_id: &Uuid, name: &str, icon: &str) -> Result<ObjectType, ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let affected = conn.execute(
            "UPDATE object_types SET name = ?1, icon = ?2 WHERE id = ?3",
            params![name, icon, type_id.to_string()],
        )?;
        if affected == 0 {
            return Err(ObjectError::TypeNotFound(*type_id));
        }
        drop(conn);
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        self.load_object_type(&conn, type_id)
    }

    fn delete_object_type(&self, type_id: &Uuid) -> Result<(), ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let affected = conn.execute(
            "DELETE FROM object_types WHERE id = ?1",
            params![type_id.to_string()],
        )?;
        if affected == 0 {
            return Err(ObjectError::TypeNotFound(*type_id));
        }
        Ok(())
    }

    fn list_object_types(&self) -> Result<Vec<ObjectType>, ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let mut stmt = conn.prepare("SELECT id FROM object_types")?;
        let ids: Vec<Uuid> = stmt.query_map([], |row| {
            let id_str: String = row.get(0)?;
            Uuid::parse_str(&id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))
        })?.collect::<Result<Vec<_>, _>>()?;

        let mut types = Vec::new();
        for id in ids {
            types.push(self.load_object_type(&conn, &id)?);
        }
        Ok(types)
    }

    #[instrument(skip(self, properties))]
    fn create_object(&self, type_id: &Uuid, properties: serde_json::Value) -> Result<Object, ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let exists: bool = conn.query_row(
            "SELECT COUNT(*) FROM object_types WHERE id = ?1",
            params![type_id.to_string()],
            |row| row.get::<_, i64>(0).map(|c| c > 0),
        )?;
        if !exists {
            return Err(ObjectError::TypeNotFound(*type_id));
        }

        let id = Uuid::new_v4();
        let now = Utc::now();
        conn.execute(
            "INSERT INTO objects (id, object_type_id, properties, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id.to_string(), type_id.to_string(), properties.to_string(), now.to_rfc3339(), now.to_rfc3339()],
        )?;

        Ok(Object {
            id,
            object_type_id: *type_id,
            properties,
            relations: vec![],
            created_at: now,
            updated_at: now,
        })
    }

    fn update_object(&self, object_id: &Uuid, properties: serde_json::Value) -> Result<Object, ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let now = Utc::now();
        let affected = conn.execute(
            "UPDATE objects SET properties = ?1, updated_at = ?2 WHERE id = ?3",
            params![properties.to_string(), now.to_rfc3339(), object_id.to_string()],
        )?;
        if affected == 0 {
            return Err(ObjectError::ObjectNotFound(*object_id));
        }
        drop(conn);
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        self.load_object(&conn, object_id)
    }

    fn delete_object(&self, object_id: &Uuid) -> Result<(), ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let affected = conn.execute(
            "DELETE FROM objects WHERE id = ?1",
            params![object_id.to_string()],
        )?;
        if affected == 0 {
            return Err(ObjectError::ObjectNotFound(*object_id));
        }
        Ok(())
    }

    fn get_object(&self, object_id: &Uuid) -> Result<Object, ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        self.load_object(&conn, object_id)
    }

    fn list_objects(&self, type_id: Option<&Uuid>) -> Result<Vec<Object>, ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let ids: Vec<Uuid> = match type_id {
            Some(tid) => {
                let mut stmt = conn.prepare("SELECT id FROM objects WHERE object_type_id = ?1")?;
                let ids: Vec<Uuid> = stmt.query_map(params![tid.to_string()], |row| {
                    let id_str: String = row.get(0)?;
                    Uuid::parse_str(&id_str)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))
                })?.collect::<Result<Vec<_>, _>>()?;
                ids
            }
            None => {
                let mut stmt = conn.prepare("SELECT id FROM objects")?;
                let ids: Vec<Uuid> = stmt.query_map([], |row| {
                    let id_str: String = row.get(0)?;
                    Uuid::parse_str(&id_str)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))
                })?.collect::<Result<Vec<_>, _>>()?;
                ids
            }
        };

        let mut objects = Vec::new();
        for id in ids {
            objects.push(self.load_object(&conn, &id)?);
        }
        Ok(objects)
    }

    fn add_relation(&self, source_id: &Uuid, target_id: &Uuid, relation_id: &Uuid) -> Result<(), ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let id = Uuid::new_v4();
        conn.execute(
            "INSERT INTO object_relations (id, source_id, target_id, relation_id) VALUES (?1, ?2, ?3, ?4)",
            params![id.to_string(), source_id.to_string(), target_id.to_string(), relation_id.to_string()],
        )?;
        Ok(())
    }

    fn remove_relation(&self, source_id: &Uuid, target_id: &Uuid, relation_id: &Uuid) -> Result<(), ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        conn.execute(
            "DELETE FROM object_relations WHERE source_id = ?1 AND target_id = ?2 AND relation_id = ?3",
            params![source_id.to_string(), target_id.to_string(), relation_id.to_string()],
        )?;
        Ok(())
    }

    fn get_related_objects(&self, object_id: &Uuid, relation_id: Option<&Uuid>) -> Result<Vec<Object>, ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let target_ids: Vec<Uuid> = match relation_id {
            Some(rid) => {
                let mut stmt = conn.prepare(
                    "SELECT target_id FROM object_relations WHERE source_id = ?1 AND relation_id = ?2"
                )?;
                let ids: Vec<Uuid> = stmt.query_map(params![object_id.to_string(), rid.to_string()], |row| {
                    let s: String = row.get(0)?;
                    Uuid::parse_str(&s)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))
                })?.collect::<Result<Vec<_>, _>>()?;
                ids
            }
            None => {
                let mut stmt = conn.prepare(
                    "SELECT target_id FROM object_relations WHERE source_id = ?1"
                )?;
                let ids: Vec<Uuid> = stmt.query_map(params![object_id.to_string()], |row| {
                    let s: String = row.get(0)?;
                    Uuid::parse_str(&s)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))
                })?.collect::<Result<Vec<_>, _>>()?;
                ids
            }
        };

        let mut objects = Vec::new();
        for tid in target_ids {
            objects.push(self.load_object(&conn, &tid)?);
        }
        Ok(objects)
    }

    fn promote_block_to_object(&self, _note_id: &Uuid, _block_id: &Uuid, object_type_id: &Uuid) -> Result<Object, ObjectError> {
        let conn = self.conn.lock().map_err(|e| ObjectError::Internal(e.to_string()))?;
        let exists: bool = conn.query_row(
            "SELECT COUNT(*) FROM object_types WHERE id = ?1",
            params![object_type_id.to_string()],
            |row| row.get::<_, i64>(0).map(|c| c > 0),
        )?;
        if !exists {
            return Err(ObjectError::TypeNotFound(*object_type_id));
        }

        let id = Uuid::new_v4();
        let now = Utc::now();
        let props = serde_json::json!({
            "source_note_id": _note_id.to_string(),
            "source_block_id": _block_id.to_string(),
        });

        conn.execute(
            "INSERT INTO objects (id, object_type_id, properties, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id.to_string(), object_type_id.to_string(), props.to_string(), now.to_rfc3339(), now.to_rfc3339()],
        )?;

        Ok(Object {
            id,
            object_type_id: *object_type_id,
            properties: props,
            relations: vec![],
            created_at: now,
            updated_at: now,
        })
    }
}

#[cfg(test)]
// 测试约定：测试中使用 `.unwrap()` 是 Rust 惯用写法，由 `#[cfg(test)]` 门控，
// 不会编译进生产二进制。生产代码使用 `?` 运算符传播错误。
mod tests {
    use super::*;

    #[test]
    fn test_create_object_type() {
        let engine = SqliteObjectEngine::in_memory().unwrap();
        let ot = engine.create_object_type("Task", "📋", vec![]).unwrap();
        assert_eq!(ot.name, "Task");
    }

    #[test]
    fn test_create_and_get_object() {
        let engine = SqliteObjectEngine::in_memory().unwrap();
        let ot = engine.create_object_type("Task", "📋", vec![]).unwrap();
        let obj = engine.create_object(&ot.id, serde_json::json!({"title": "My Task"})).unwrap();
        let fetched = engine.get_object(&obj.id).unwrap();
        assert_eq!(fetched.id, obj.id);
    }

    #[test]
    fn test_relations() {
        let engine = SqliteObjectEngine::in_memory().unwrap();
        let ot = engine.create_object_type("Person", "👤", vec![]).unwrap();

        let a = engine.create_object(&ot.id, serde_json::json!({"name": "Alice"})).unwrap();
        let b = engine.create_object(&ot.id, serde_json::json!({"name": "Bob"})).unwrap();

        let rel = ObjectRelation {
            id: Uuid::new_v4(),
            name: "friend".to_string(),
            relation_type: RelationType::ManyToMany,
            source_type: ot.id,
            target_type: ot.id,
        };

        let conn = engine.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO object_type_relations (id, object_type_id, name, relation_type, source_type, target_type) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![rel.id.to_string(), ot.id.to_string(), rel.name, "ManyToMany", rel.source_type.to_string(), rel.target_type.to_string()],
        ).unwrap();
        drop(conn);

        engine.add_relation(&a.id, &b.id, &rel.id).unwrap();
        let related = engine.get_related_objects(&a.id, Some(&rel.id)).unwrap();
        assert_eq!(related.len(), 1);
        assert_eq!(related[0].id, b.id);
    }
}
