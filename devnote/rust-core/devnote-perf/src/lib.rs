use devnote_observe::{debug};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use crossbeam_channel::{Receiver, Sender};
use dashmap::DashMap;
use lru::LruCache as LruCacheImpl;
use serde::{Deserialize, Serialize};
use std::num::NonZeroUsize;

pub struct ObjectPool<T> {
    pool: Mutex<Vec<T>>,
    factory: Box<dyn Fn() -> T + Send + Sync>,
}

impl<T> ObjectPool<T> {
    pub fn new(capacity: usize, factory: impl Fn() -> T + Send + Sync + 'static) -> Self {
        let mut pool = Vec::with_capacity(capacity);
        for _ in 0..capacity {
            pool.push(factory());
        }
        Self {
            pool: Mutex::new(pool),
            factory: Box::new(factory),
        }
    }

    pub fn acquire(&self) -> T {
        self.pool
            .lock()
            .unwrap()
            .pop()
            .unwrap_or_else(|| (self.factory)())
    }

    pub fn release(&self, obj: T) {
        self.pool.lock().unwrap().push(obj);
    }
}

pub struct BufferPool {
    pool: ObjectPool<Vec<u8>>,
}

impl BufferPool {
    pub fn new(capacity: usize, buffer_size: usize) -> Self {
        Self {
            pool: ObjectPool::new(capacity, move || Vec::with_capacity(buffer_size)),
        }
    }

    pub fn acquire(&self) -> Vec<u8> {
        let mut buf = self.pool.acquire();
        buf.clear();
        buf
    }

    pub fn release(&self, buf: Vec<u8>) {
        self.pool.release(buf);
    }
}

pub struct LruCache<K, V> {
    inner: Mutex<LruCacheImpl<K, V>>,
}

impl<K: std::hash::Hash + Eq, V> LruCache<K, V> {
    pub fn new(capacity: usize) -> Self {
        Self {
            inner: Mutex::new(LruCacheImpl::new(
                NonZeroUsize::new(capacity).unwrap_or(NonZeroUsize::new(1).unwrap()),
            )),
        }
    }

    pub fn get(&self, key: &K) -> Option<V>
    where
        V: Clone,
    {
        self.inner.lock().unwrap().get(key).cloned()
    }

    pub fn put(&self, key: K, value: V) {
        self.inner.lock().unwrap().put(key, value);
    }

    pub fn remove(&self, key: &K) -> Option<V> {
        self.inner.lock().unwrap().pop(key)
    }

    pub fn len(&self) -> usize {
        self.inner.lock().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.inner.lock().unwrap().is_empty()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteContent {
    pub note_id: String,
    pub title: String,
    pub content: String,
    pub blocks: Vec<String>,
    pub updated_at: u64,
}

pub struct NoteCache {
    cache: LruCache<String, NoteContent>,
}

impl NoteCache {
    pub fn new(capacity: usize) -> Self {
        Self {
            cache: LruCache::new(capacity),
        }
    }

    pub fn get(&self, note_id: &str) -> Option<NoteContent> {
        let result = self.cache.get(&note_id.to_string());
        if result.is_some() {
            debug!("note_cache: hit note_id={}", note_id);
        } else {
            debug!("note_cache: miss note_id={}", note_id);
        }
        result
    }

    pub fn put(&self, note_id: &str, content: NoteContent) {
        self.cache.put(note_id.to_string(), content);
    }

    pub fn invalidate(&self, note_id: &str) {
        self.cache.remove(&note_id.to_string());
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockData {
    pub block_id: String,
    pub note_id: String,
    pub block_type: String,
    pub content: String,
    pub position: usize,
}

pub struct BlockCache {
    cache: DashMap<String, BlockData>,
    note_index: DashMap<String, Vec<String>>,
}

impl BlockCache {
    pub fn new() -> Self {
        Self {
            cache: DashMap::new(),
            note_index: DashMap::new(),
        }
    }

    pub fn get(&self, block_id: &str) -> Option<BlockData> {
        self.cache.get(block_id).map(|r| r.value().clone())
    }

    pub fn put(&self, data: BlockData) {
        let block_id = data.block_id.clone();
        let note_id = data.note_id.clone();
        self.cache.insert(block_id.clone(), data);
        self.note_index
            .entry(note_id)
            .or_insert_with(Vec::new)
            .push(block_id);
    }

    pub fn get_by_note(&self, note_id: &str) -> Vec<BlockData> {
        if let Some(index) = self.note_index.get(note_id) {
            index
                .iter()
                .filter_map(|id| self.cache.get(id).map(|r| r.value().clone()))
                .collect()
        } else {
            Vec::new()
        }
    }

    pub fn invalidate_note(&self, note_id: &str) {
        if let Some((_, block_ids)) = self.note_index.remove(note_id) {
            for id in block_ids {
                self.cache.remove(&id);
            }
        }
    }
}

mod rusqlite {
    pub struct Connection;

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct OpenFlags(u32);

    impl OpenFlags {
        pub const SQLITE_OPEN_READ_ONLY: OpenFlags = OpenFlags(0x00000001);
        pub const SQLITE_OPEN_NO_MUTEX: OpenFlags = OpenFlags(0x00008000);
    }

    impl std::ops::BitOr for OpenFlags {
        type Output = Self;
        fn bitor(self, rhs: Self) -> Self {
            OpenFlags(self.0 | rhs.0)
        }
    }

    impl Connection {
        pub fn open(_path: &str) -> anyhow::Result<Self> {
            Ok(Connection)
        }

        pub fn open_with_flags(
            _path: &str,
            _flags: OpenFlags,
        ) -> anyhow::Result<Self> {
            Ok(Connection)
        }

        pub fn execute_batch(&self, _sql: &str) -> anyhow::Result<()> {
            Ok(())
        }
    }
}

pub struct SqliteConnectionPool {
    read_connections: Vec<Mutex<Option<rusqlite::Connection>>>,
    write_connection: Mutex<Option<rusqlite::Connection>>,
    database_path: String,
    read_count: usize,
    current_read: Mutex<usize>,
}

impl SqliteConnectionPool {
    pub fn new(database_path: &str, read_pool_size: usize) -> Self {
        let mut read_connections = Vec::with_capacity(read_pool_size);
        for _ in 0..read_pool_size {
            read_connections.push(Mutex::new(None));
        }
        Self {
            read_connections,
            write_connection: Mutex::new(None),
            database_path: database_path.to_string(),
            read_count: read_pool_size,
            current_read: Mutex::new(0),
        }
    }

    pub fn get_read_connection(&self) -> Result<std::sync::MutexGuard<'_, Option<rusqlite::Connection>>> {
        let idx = {
            let mut current = self.current_read.lock().unwrap();
            let idx = *current % self.read_count;
            *current = (*current + 1) % self.read_count;
            idx
        };
        let mut guard = self.read_connections[idx].lock().unwrap();
        if guard.is_none() {
            let conn = rusqlite::Connection::open_with_flags(
                &self.database_path,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
            )?;
            *guard = Some(conn);
        }
        Ok(guard)
    }

    pub fn get_write_connection(&self) -> Result<std::sync::MutexGuard<'_, Option<rusqlite::Connection>>> {
        let mut guard = self.write_connection.lock().unwrap();
        if guard.is_none() {
            let conn = rusqlite::Connection::open(&self.database_path)?;
            conn.execute_batch("PRAGMA journal_mode=WAL;")?;
            *guard = Some(conn);
        }
        Ok(guard)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum TaskPriority {
    Low = 0,
    Normal = 1,
    High = 2,
    Critical = 3,
}

pub struct ScheduledTask {
    pub id: String,
    pub priority: TaskPriority,
    pub task_type: String,
    pub payload: Vec<u8>,
}

pub struct TaskScheduler {
    sender: Sender<ScheduledTask>,
    receiver: Receiver<ScheduledTask>,
}

impl TaskScheduler {
    pub fn new() -> Self {
        let (sender, receiver) = crossbeam_channel::unbounded();
        Self {
            sender,
            receiver,
        }
    }

    pub fn submit(&self, task: ScheduledTask) {
        self.sender.send(task).ok();
    }

    pub fn submit_batch(&self, tasks: Vec<ScheduledTask>) {
        for task in tasks {
            self.sender.send(task).ok();
        }
    }

    pub fn try_recv(&self) -> Option<ScheduledTask> {
        self.receiver.try_recv().ok()
    }

    pub fn recv(&self) -> ScheduledTask {
        self.receiver.recv().unwrap()
    }
}

pub struct BackgroundWorker {
    scheduler: Arc<TaskScheduler>,
    running: Arc<Mutex<bool>>,
}

impl BackgroundWorker {
    pub fn new(scheduler: Arc<TaskScheduler>) -> Self {
        Self {
            scheduler,
            running: Arc::new(Mutex::new(false)),
        }
    }

    pub fn start(&self, handler: impl Fn(ScheduledTask) + Send + 'static) {
        let mut running = self.running.lock().unwrap();
        *running = true;
        let scheduler = Arc::clone(&self.scheduler);
        let running_flag = Arc::clone(&self.running);
        std::thread::spawn(move || {
            loop {
                if let Some(task) = scheduler.try_recv() {
                    handler(task);
                } else {
                    let is_running = *running_flag.lock().unwrap();
                    if !is_running {
                        break;
                    }
                    std::thread::yield_now();
                }
            }
        });
    }

    pub fn stop(&self) {
        let mut running = self.running.lock().unwrap();
        *running = false;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompiledTemplate {
    pub template_id: String,
    pub source_hash: u64,
    pub compiled_data: Vec<u8>,
    pub created_at: u64,
}

pub struct CompiledTemplateCache {
    cache: DashMap<String, CompiledTemplate>,
}

impl CompiledTemplateCache {
    pub fn new() -> Self {
        Self {
            cache: DashMap::new(),
        }
    }

    pub fn get(&self, template_id: &str) -> Option<CompiledTemplate> {
        self.cache.get(template_id).map(|r| r.value().clone())
    }

    pub fn put(&self, template: CompiledTemplate) {
        self.cache
            .insert(template.template_id.clone(), template);
    }

    pub fn invalidate(&self, template_id: &str) {
        self.cache.remove(template_id);
    }

    pub fn invalidate_by_hash(&self, source_hash: u64) {
        self.cache
            .retain(|_, v| v.source_hash != source_hash);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentDiff {
    pub added_lines: Vec<usize>,
    pub removed_lines: Vec<usize>,
    pub modified_lines: Vec<usize>,
    pub old_content: String,
    pub new_content: String,
}

pub struct DiffCalculator;

impl DiffCalculator {
    pub fn calculate(old_content: &str, new_content: &str) -> ContentDiff {
        let old_lines: Vec<&str> = old_content.lines().collect();
        let new_lines: Vec<&str> = new_content.lines().collect();

        let mut added_lines = Vec::new();
        let mut removed_lines = Vec::new();
        let mut modified_lines = Vec::new();

        let max_len = old_lines.len().max(new_lines.len());

        for i in 0..max_len {
            match (old_lines.get(i), new_lines.get(i)) {
                (None, Some(_)) => {
                    added_lines.push(i);
                }
                (Some(_), None) => {
                    removed_lines.push(i);
                }
                (Some(old), Some(new)) => {
                    if old != new {
                        modified_lines.push(i);
                    }
                }
                (None, None) => {}
            }
        }

        ContentDiff {
            added_lines,
            removed_lines,
            modified_lines,
            old_content: old_content.to_string(),
            new_content: new_content.to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IncrementalChange {
    pub change_type: String,
    pub block_id: String,
    pub old_content: Option<String>,
    pub new_content: Option<String>,
}

pub struct IncrementalProcessor {
    last_state: Mutex<HashMap<String, String>>,
}

impl IncrementalProcessor {
    pub fn new() -> Self {
        Self {
            last_state: Mutex::new(HashMap::new()),
        }
    }

    pub fn process(&self, current_state: &HashMap<String, String>) -> Vec<IncrementalChange> {
        let mut last = self.last_state.lock().unwrap();
        let mut changes = Vec::new();

        for (block_id, content) in current_state {
            match last.get(block_id) {
                None => {
                    changes.push(IncrementalChange {
                        change_type: "added".to_string(),
                        block_id: block_id.clone(),
                        old_content: None,
                        new_content: Some(content.clone()),
                    });
                }
                Some(old_content) if old_content != content => {
                    changes.push(IncrementalChange {
                        change_type: "modified".to_string(),
                        block_id: block_id.clone(),
                        old_content: Some(old_content.clone()),
                        new_content: Some(content.clone()),
                    });
                }
                _ => {}
            }
        }

        for block_id in last.keys() {
            if !current_state.contains_key(block_id) {
                changes.push(IncrementalChange {
                    change_type: "removed".to_string(),
                    block_id: block_id.clone(),
                    old_content: last.get(block_id).cloned(),
                    new_content: None,
                });
            }
        }

        *last = current_state.clone();
        changes
    }

    pub fn reset(&self) {
        self.last_state.lock().unwrap().clear();
    }
}
