//! CRDT 冲突合并引擎
//! 
//! 借鉴: AppFlowy CRDT 算法 (https://github.com/AppFlowy-IO/AppFlowy)
//! - YATA 操作变换算法
//! - HLC 混合逻辑时钟
//! - VectorClock 向量时钟
//! 
//! 借鉴: Yjs CRDT 实现 (https://github.com/yjs/yjs)
//! - 操作合并策略
//! - 删除墓碑处理

use devnote_observe::{instrument, warn};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CRDTError {
    #[error("operation conflict: {0}")]
    Conflict(String),
    #[error("invalid operation: {0}")]
    InvalidOperation(String),
    #[error("tombstone already deleted: {0}")]
    TombstoneDeleted(String),
    #[error("serialization error: {0}")]
    SerializationError(String),
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct HLC {
    pub physical_ms: u64,      // Physical clock in milliseconds
    pub logical: u32,          // Logical counter for same-timestamp events
    pub node_id: String,       // Unique node identifier
}

impl HLC {
    pub fn new(node_id: String) -> Self {
        Self {
            physical_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            logical: 0,
            node_id,
        }
    }

    /// Create a new event - increment logical clock
    pub fn increment(&mut self) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;

        if now > self.physical_ms {
            self.physical_ms = now;
            self.logical = 0;
        } else {
            self.logical += 1;
        }
    }

    /// Receive an event from another node - merge clocks
    pub fn receive(&mut self, other: &HLC) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;

        if now > self.physical_ms && now > other.physical_ms {
            self.physical_ms = now;
            self.logical = 0;
        } else if other.physical_ms > self.physical_ms {
            self.physical_ms = other.physical_ms;
            self.logical = other.logical + 1;
        } else if self.physical_ms > other.physical_ms {
            self.logical += 1;
        } else {
            // Same timestamp - use max logical + 1
            self.logical = std::cmp::max(self.logical, other.logical) + 1;
        }
    }
}

impl Ord for HLC {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        match self.physical_ms.cmp(&other.physical_ms) {
            std::cmp::Ordering::Equal => match self.logical.cmp(&other.logical) {
                std::cmp::Ordering::Equal => self.node_id.cmp(&other.node_id),
                other => other,
            },
            other => other,
        }
    }
}

impl PartialOrd for HLC {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct VectorClock {
    pub clocks: HashMap<String, HLC>,
}

impl VectorClock {
    pub fn new() -> Self {
        Self {
            clocks: HashMap::new(),
        }
    }

    pub fn increment(&mut self, device_id: &str) {
        let hlc = self.clocks.entry(device_id.to_string()).or_insert_with(|| HLC::new(device_id.to_string()));
        hlc.increment();
    }

    pub fn get(&self, device_id: &str) -> Option<&HLC> {
        self.clocks.get(device_id)
    }

    pub fn merge(&mut self, other: &VectorClock) {
        for (node_id, hlc) in &other.clocks {
            match self.clocks.get_mut(node_id) {
                Some(our_hlc) => our_hlc.receive(hlc),
                None => { self.clocks.insert(node_id.clone(), hlc.clone()); }
            }
        }
    }

    pub fn happens_before(&self, other: &VectorClock) -> bool {
        let all_leq = self
            .clocks
            .iter()
            .all(|(node_id, hlc)| {
                other.clocks.get(node_id).map_or(false, |other_hlc| hlc <= other_hlc)
            });
        let any_lt = self
            .clocks
            .iter()
            .any(|(node_id, hlc)| {
                other.clocks.get(node_id).map_or(false, |other_hlc| hlc < other_hlc)
            });
        all_leq && any_lt
    }

    pub fn is_concurrent(&self, other: &VectorClock) -> bool {
        !self.happens_before(other) && !other.happens_before(self) && self != other
    }
}

impl Default for VectorClock {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Operation {
    Insert {
        id: HLC,
        block_id: String,
        position: usize,
        content: String,
        vector_clock: VectorClock,
    },
    Delete {
        id: HLC,
        block_id: String,
        vector_clock: VectorClock,
    },
    Replace {
        id: HLC,
        block_id: String,
        old_content: String,
        new_content: String,
        vector_clock: VectorClock,
    },
    Move {
        id: HLC,
        block_id: String,
        from_position: usize,
        to_position: usize,
        vector_clock: VectorClock,
    },
}

impl Operation {
    pub fn id(&self) -> &HLC {
        match self {
            Operation::Insert { id, .. } => id,
            Operation::Delete { id, .. } => id,
            Operation::Replace { id, .. } => id,
            Operation::Move { id, .. } => id,
        }
    }

    pub fn vector_clock(&self) -> &VectorClock {
        match self {
            Operation::Insert { vector_clock, .. } => vector_clock,
            Operation::Delete { vector_clock, .. } => vector_clock,
            Operation::Replace { vector_clock, .. } => vector_clock,
            Operation::Move { vector_clock, .. } => vector_clock,
        }
    }

    pub fn block_id(&self) -> &str {
        match self {
            Operation::Insert { block_id, .. } => block_id,
            Operation::Delete { block_id, .. } => block_id,
            Operation::Replace { block_id, .. } => block_id,
            Operation::Move { block_id, .. } => block_id,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CRDTDocument {
    pub id: String,
    pub version: VectorClock,
    pub blocks: Vec<BlockCRDT>,
    pub operations: Vec<Operation>,
    pub device_id: String,
    pub hlc: HLC,
}

impl CRDTDocument {
    pub fn new(id: String, device_id: String) -> Self {
        let hlc = HLC::new(device_id.clone());
        Self {
            id,
            version: VectorClock::new(),
            blocks: Vec::new(),
            operations: Vec::new(),
            device_id,
            hlc,
        }
    }

    pub fn next_operation_id(&mut self) -> HLC {
        self.hlc.increment();
        self.version.increment(&self.device_id);
        self.hlc.clone()
    }

    #[instrument]
    pub fn insert_block(&mut self, block_id: String, position: usize, content: String) -> Operation {
        let id = self.next_operation_id();
        let op = Operation::Insert {
            id: id.clone(),
            block_id,
            position,
            content: content.clone(),
            vector_clock: self.version.clone(),
        };
        self.apply_operation(op.clone())
            .expect("apply_operation for Insert always succeeds");
        op
    }

    #[instrument]
    pub fn delete_block(&mut self, block_id: String) -> Operation {
        let id = self.next_operation_id();
        let op = Operation::Delete {
            id: id.clone(),
            block_id,
            vector_clock: self.version.clone(),
        };
        self.apply_operation(op.clone())
            .expect("apply_operation for local Delete: block must exist and not be tombstoned");
        op
    }

    #[instrument]
    pub fn replace_block(&mut self, block_id: String, old_content: String, new_content: String) -> Operation {
        let id = self.next_operation_id();
        let op = Operation::Replace {
            id: id.clone(),
            block_id,
            old_content,
            new_content,
            vector_clock: self.version.clone(),
        };
        self.apply_operation(op.clone())
            .expect("apply_operation for local Replace: block must exist and not be tombstoned");
        op
    }

    pub fn move_block(&mut self, block_id: String, from_position: usize, to_position: usize) -> Operation {
        let id = self.next_operation_id();
        let op = Operation::Move {
            id: id.clone(),
            block_id,
            from_position,
            to_position,
            vector_clock: self.version.clone(),
        };
        self.apply_operation(op.clone())
            .expect("apply_operation for local Move: block must exist and not be tombstoned");
        op
    }

    #[instrument]
    pub fn merge(&mut self, remote_ops: Vec<Operation>) -> Result<Vec<Operation>, CRDTError> {
        let mut applied_ops = Vec::new();
        let local_ids: std::collections::HashSet<HLC> = self
            .operations
            .iter()
            .map(|op| op.id().clone())
            .collect();

        let mut new_ops: Vec<&Operation> = remote_ops
            .iter()
            .filter(|op| !local_ids.contains(op.id()))
            .collect();

        new_ops.sort_by_key(|op| op.id().clone());

        for op in new_ops {
            // Merge HLC with remote operation's HLC
            self.hlc.receive(op.id());

            let transformed = transform(op.clone(), &self.operations)?;
            match self.apply_operation(transformed.clone()) {
                Ok(()) => {
                    applied_ops.push(transformed);
                }
                Err(CRDTError::TombstoneDeleted(_)) => {}
                Err(e) => return Err(e),
            }
        }

        self.version.merge(
            &remote_ops
                .iter()
                .fold(VectorClock::new(), |mut acc, op| {
                    acc.merge(op.vector_clock());
                    acc
                }),
        );

        Ok(applied_ops)
    }

    pub fn apply_operation(&mut self, op: Operation) -> Result<(), CRDTError> {
        match &op {
            Operation::Insert {
                id,
                block_id,
                position,
                content,
                ..
            } => {
                let block = BlockCRDT {
                    id: block_id.clone(),
                    position: *position,
                    content: content.clone(),
                    tombstone: false,
                    last_modified_id: id.clone(),
                    text_crdt: TextCRDT::new(content.clone()),
                };
                self.blocks.push(block);
                self.blocks.sort_by(|a, b| a.last_modified_id.cmp(&b.last_modified_id));
                self.reindex_positions();
            }
            Operation::Delete { block_id, .. } => {
                let block = self
                    .blocks
                    .iter_mut()
                    .find(|b| b.id == *block_id)
                    .ok_or_else(|| {
                        CRDTError::InvalidOperation(format!("block {} not found", block_id))
                    })?;
                if block.tombstone {
                    return Err(CRDTError::TombstoneDeleted(block_id.clone()));
                }
                block.tombstone = true;
            }
            Operation::Replace {
                id,
                block_id,
                new_content,
                ..
            } => {
                let block = self
                    .blocks
                    .iter_mut()
                    .find(|b| b.id == *block_id)
                    .ok_or_else(|| {
                        CRDTError::InvalidOperation(format!("block {} not found", block_id))
                    })?;
                if block.tombstone {
                    return Err(CRDTError::TombstoneDeleted(block_id.clone()));
                }
                block.content = new_content.clone();
                block.last_modified_id = id.clone();
                block.text_crdt = TextCRDT::new(new_content.clone());
            }
            Operation::Move {
                id,
                block_id,
                to_position,
                ..
            } => {
                // First, find the block and get its current position
                let old_pos = self
                    .blocks
                    .iter()
                    .find(|b| b.id == *block_id)
                    .ok_or_else(|| {
                        CRDTError::InvalidOperation(format!("block {} not found", block_id))
                    })?
                    .position;

                let is_tombstone = self
                    .blocks
                    .iter()
                    .find(|b| b.id == *block_id)
                    .map(|b| b.tombstone)
                    .unwrap_or(true);

                if is_tombstone {
                    return Err(CRDTError::TombstoneDeleted(block_id.clone()));
                }

                let new_pos = *to_position;
                if old_pos != new_pos {
                    // Adjust positions of other blocks to make room
                    if new_pos > old_pos {
                        // Moving down: shift blocks between (old_pos, new_pos] up by 1
                        for b in self.blocks.iter_mut() {
                            if b.id != *block_id && !b.tombstone
                                && b.position > old_pos && b.position <= new_pos
                            {
                                b.position -= 1;
                            }
                        }
                    } else {
                        // Moving up: shift blocks between [new_pos, old_pos) down by 1
                        for b in self.blocks.iter_mut() {
                            if b.id != *block_id && !b.tombstone
                                && b.position >= new_pos && b.position < old_pos
                            {
                                b.position += 1;
                            }
                        }
                    }
                    // Now set the target block's position
                    let block = self
                        .blocks
                        .iter_mut()
                        .find(|b| b.id == *block_id)
                        .expect("block existence verified earlier in Move handling");
                    block.position = new_pos;
                    block.last_modified_id = id.clone();
                    self.reindex_positions();
                } else {
                    let block = self
                        .blocks
                        .iter_mut()
                        .find(|b| b.id == *block_id)
                        .expect("block existence verified earlier in Move handling");
                    block.last_modified_id = id.clone();
                }
            }
        }
        self.operations.push(op);
        Ok(())
    }

    fn reindex_positions(&mut self) {
        let mut active: Vec<&mut BlockCRDT> = self
            .blocks
            .iter_mut()
            .filter(|b| !b.tombstone)
            .collect();
        active.sort_by_key(|b| b.position);
        for (i, block) in active.iter_mut().enumerate() {
            block.position = i;
        }
    }

    pub fn active_blocks(&self) -> Vec<&BlockCRDT> {
        let mut blocks: Vec<&BlockCRDT> = self.blocks.iter().filter(|b| !b.tombstone).collect();
        blocks.sort_by_key(|b| b.position);
        blocks
    }
}

pub fn transform(op: Operation, existing_ops: &[Operation]) -> Result<Operation, CRDTError> {
    let conflicting: Vec<&Operation> = existing_ops
        .iter()
        .filter(|existing| {
            existing.block_id() == op.block_id()
                && existing.vector_clock().is_concurrent(op.vector_clock())
        })
        .collect();

    if conflicting.is_empty() {
        return Ok(op);
    }

    match op {
        Operation::Insert {
            id,
            block_id,
            position,
            content,
            vector_clock,
        } => {
            let adjusted_position = conflicting
                .iter()
                .filter_map(|c| {
                    if let Operation::Insert { id: cid, .. } = c {
                        if cid < &id {
                            Some(1usize)
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
                .sum::<usize>();
            Ok(Operation::Insert {
                id,
                block_id,
                position: position + adjusted_position,
                content,
                vector_clock,
            })
        }
        Operation::Delete { .. } => Ok(op),
        Operation::Replace {
            id,
            block_id,
            old_content,
            new_content,
            vector_clock,
        } => {
            // P1 修复 (R1): 原 if/else 两个分支返回完全相同的操作，transform 形同虚设。
            // LWW（last-write-wins）语义：若存在更新的并发冲突（latest.id() > &id），
            // 当前操作落败，应让步——将 new_content 回退为 old_content，使 apply 变为 no-op，
            // 保留胜出方的内容，避免静默覆盖。
            let latest_conflict = conflicting.iter().max_by_key(|c| c.id());
            let yielded = latest_conflict.map(|latest| latest.id() > &id).unwrap_or(false);
            Ok(Operation::Replace {
                id,
                block_id,
                old_content: old_content.clone(),
                new_content: if yielded { old_content } else { new_content },
                vector_clock,
            })
        }
        Operation::Move {
            id,
            block_id,
            from_position,
            to_position,
            vector_clock,
        } => {
            // P1 修复 (R1): 同上，原 if/else 两分支返回相同操作。
            // LWW 落败时令 to_position = from_position，使 move 变为 no-op。
            let latest_conflict = conflicting.iter().max_by_key(|c| c.id());
            let yielded = latest_conflict.map(|latest| latest.id() > &id).unwrap_or(false);
            Ok(Operation::Move {
                id,
                block_id,
                from_position,
                to_position: if yielded { from_position } else { to_position },
                vector_clock,
            })
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockCRDT {
    pub id: String,
    pub position: usize,
    pub content: String,
    pub tombstone: bool,
    pub last_modified_id: HLC,
    pub text_crdt: TextCRDT,
}

impl BlockCRDT {
    pub fn new(id: String, position: usize, content: String, device_id: String) -> Self {
        let hlc = HLC::new(device_id);
        Self {
            id,
            position,
            content: content.clone(),
            tombstone: false,
            last_modified_id: hlc,
            text_crdt: TextCRDT::new(content),
        }
    }

    pub fn insert_char(&mut self, index: usize, ch: char, op_id: HLC) {
        self.text_crdt.insert(index, ch, op_id.clone());
        self.content = self.text_crdt.to_string();
        self.last_modified_id = op_id;
    }

    pub fn delete_range(&mut self, start: usize, end: usize, op_id: HLC) {
        self.text_crdt.delete(start, end, op_id.clone());
        self.content = self.text_crdt.to_string();
        self.last_modified_id = op_id;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RGAChar {
    pub ch: char,
    pub id: HLC,
    pub left_id: Option<HLC>,
    pub deleted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextCRDT {
    pub chars: Vec<RGAChar>,
}

impl TextCRDT {
    pub fn new(content: String) -> Self {
        let chars = content
            .chars()
            .enumerate()
            .map(|(i, ch)| RGAChar {
                ch,
                id: HLC {
                    physical_ms: 0,
                    logical: i as u32,
                    node_id: String::new(),
                },
                left_id: if i > 0 {
                    Some(HLC {
                        physical_ms: 0,
                        logical: (i - 1) as u32,
                        node_id: String::new(),
                    })
                } else {
                    None
                },
                deleted: false,
            })
            .collect();
        Self { chars }
    }

    pub fn insert(&mut self, index: usize, ch: char, op_id: HLC) {
        let left_id = if index > 0 && !self.chars.is_empty() {
            let active: Vec<&RGAChar> = self.chars.iter().filter(|c| !c.deleted).collect();
            if index > 0 && index <= active.len() {
                Some(active[index - 1].id.clone())
            } else {
                None
            }
        } else {
            None
        };

        let rga_char = RGAChar {
            ch,
            id: op_id,
            left_id,
            deleted: false,
        };

        let insert_pos = self.find_insert_position(&rga_char);
        self.chars.insert(insert_pos, rga_char);
    }

    fn find_insert_position(&self, new_char: &RGAChar) -> usize {
        if self.chars.is_empty() {
            return 0;
        }

        match &new_char.left_id {
            Some(left_id) => {
                for (i, c) in self.chars.iter().enumerate() {
                    if c.id == *left_id {
                        let mut pos = i + 1;
                        while pos < self.chars.len()
                            && self.chars[pos].left_id == Some(left_id.clone())
                            && self.chars[pos].id < new_char.id
                        {
                            pos += 1;
                        }
                        return pos;
                    }
                }
                self.chars.len()
            }
            None => {
                let mut pos = 0;
                while pos < self.chars.len() && self.chars[pos].left_id.is_none() && self.chars[pos].id < new_char.id {
                    pos += 1;
                }
                pos
            }
        }
    }

    pub fn delete(&mut self, start: usize, end: usize, _op_id: HLC) {
        let active_indices: Vec<usize> = self
            .chars
            .iter()
            .enumerate()
            .filter(|(_, c)| !c.deleted)
            .map(|(i, _)| i)
            .collect();

        for i in start..end {
            if i < active_indices.len() {
                self.chars[active_indices[i]].deleted = true;
            }
        }
    }

    pub fn to_string(&self) -> String {
        self.chars
            .iter()
            .filter(|c| !c.deleted)
            .map(|c| c.ch)
            .collect()
    }

    pub fn merge(&mut self, remote: &TextCRDT) {
        let local_ids: std::collections::HashSet<(String, u32)> = self
            .chars
            .iter()
            .map(|c| (c.id.node_id.clone(), c.id.logical))
            .collect();

        for remote_char in &remote.chars {
            let key = (remote_char.id.node_id.clone(), remote_char.id.logical);
            if !local_ids.contains(&key) {
                let pos = self.find_insert_position(remote_char);
                let mut new_char = remote_char.clone();
                if remote_char.deleted {
                    if let Some(local) = self.chars.iter().find(|c| c.id == remote_char.id) {
                        new_char.deleted = local.deleted || remote_char.deleted;
                    }
                }
                self.chars.insert(pos, new_char);
            } else if remote_char.deleted {
                if let Some(local) = self.chars.iter_mut().find(|c| {
                    c.id.node_id == remote_char.id.node_id && c.id.logical == remote_char.id.logical
                }) {
                    local.deleted = local.deleted || remote_char.deleted;
                }
            }
        }
    }
}

#[instrument]
pub fn merge_documents(local: &mut CRDTDocument, remote_ops: Vec<Operation>) -> Result<Vec<Operation>, CRDTError> {
    local.merge(remote_ops)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConflictInfo {
    pub block_id: String,
    pub local_content: String,
    pub remote_content: String,
    pub local_operation_id: HLC,
    pub remote_operation_id: HLC,
    pub conflict_type: ConflictType,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ConflictType {
    ContentConflict,
    MoveConflict,
    DeleteModifyConflict,
}

#[instrument]
pub fn detect_conflicts(local: &CRDTDocument, remote_ops: &[Operation]) -> Vec<ConflictInfo> {
    let mut conflicts = Vec::new();
    let local_op_ids: std::collections::HashSet<(String, u32)> = local
        .operations
        .iter()
        .map(|op| (op.id().node_id.clone(), op.id().logical))
        .collect();

    for remote_op in remote_ops {
        let remote_key = (remote_op.id().node_id.clone(), remote_op.id().logical);
        if local_op_ids.contains(&remote_key) {
            continue;
        }

        match remote_op {
            Operation::Replace {
                id: remote_id,
                block_id,
                new_content: remote_content,
                ..
            } => {
                if let Some(local_op) = local.operations.iter().rev().find(|op| {
                    op.block_id() == block_id.as_str()
                        && matches!(op, Operation::Replace { .. })
                        && op.vector_clock().is_concurrent(remote_op.vector_clock())
                }) {
                    if let Operation::Replace {
                        id: local_id,
                        new_content: local_content,
                        ..
                    } = local_op
                    {
                        let local_block = local.blocks.iter().find(|b| b.id == *block_id);
                        let current_local = local_block.map(|b| b.content.clone()).unwrap_or_default();
                        if current_local != *remote_content {
                            conflicts.push(ConflictInfo {
                                block_id: block_id.clone(),
                                local_content: local_content.clone(),
                                remote_content: remote_content.clone(),
                                local_operation_id: local_id.clone(),
                                remote_operation_id: remote_id.clone(),
                                conflict_type: ConflictType::ContentConflict,
                            });
                        }
                    }
                }
            }
            Operation::Move {
                id: remote_id,
                block_id,
                to_position: remote_pos,
                ..
            } => {
                if let Some(local_op) = local.operations.iter().rev().find(|op| {
                    op.block_id() == block_id.as_str()
                        && matches!(op, Operation::Move { .. })
                        && op.vector_clock().is_concurrent(remote_op.vector_clock())
                }) {
                    if let Operation::Move {
                        id: local_id,
                        to_position: local_pos,
                        ..
                    } = local_op
                    {
                        if local_pos != remote_pos {
                            conflicts.push(ConflictInfo {
                                block_id: block_id.clone(),
                                local_content: format!("position: {}", local_pos),
                                remote_content: format!("position: {}", remote_pos),
                                local_operation_id: local_id.clone(),
                                remote_operation_id: remote_id.clone(),
                                conflict_type: ConflictType::MoveConflict,
                            });
                        }
                    }
                }
            }
            Operation::Delete {
                id: remote_id,
                block_id,
                ..
            } => {
                if let Some(local_op) = local.operations.iter().rev().find(|op| {
                    op.block_id() == block_id.as_str()
                        && matches!(op, Operation::Replace { .. })
                        && op.vector_clock().is_concurrent(remote_op.vector_clock())
                }) {
                    if let Operation::Replace {
                        id: local_id,
                        new_content: local_content,
                        ..
                    } = local_op
                    {
                        conflicts.push(ConflictInfo {
                            block_id: block_id.clone(),
                            local_content: local_content.clone(),
                            remote_content: String::new(),
                            local_operation_id: local_id.clone(),
                            remote_operation_id: remote_id.clone(),
                            conflict_type: ConflictType::DeleteModifyConflict,
                        });
                    }
                }
            }
            _ => {}
        }
    }

    conflicts
}

#[cfg(test)]
// 测试约定：测试中使用 `.unwrap()` 是 Rust 惯用写法，由 `#[cfg(test)]` 门控，
// 不会编译进生产二进制。生产代码使用 `?` 运算符传播错误。
mod tests {
    use super::*;

    #[test]
    fn test_hlc_ordering() {
        let mut hlc1 = HLC::new("node-a".into());
        hlc1.increment();
        let mut hlc2 = HLC::new("node-b".into());
        hlc2.increment();
        // Different nodes, same physical time - ordered by node_id
        assert!(hlc1 < hlc2 || hlc1 > hlc2); // deterministic
    }

    #[test]
    fn test_hlc_receive() {
        let mut hlc1 = HLC::new("node-a".into());
        hlc1.increment();
        let hlc2 = hlc1.clone();
        hlc1.receive(&hlc2);
        assert!(hlc1 > hlc2);
    }

    #[test]
    fn test_hlc_causality() {
        let mut hlc1 = HLC::new("node-a".into());
        hlc1.increment();
        let mut hlc2 = HLC::new("node-b".into());
        hlc2.receive(&hlc1); // hlc2 happens-after hlc1
        assert!(hlc2 > hlc1);
    }

    #[test]
    fn test_vector_clock_happens_before() {
        let mut vc1 = VectorClock::new();
        vc1.increment("a");
        let mut vc2 = VectorClock::new();
        vc2.increment("a");
        vc2.increment("a");
        assert!(vc1.happens_before(&vc2));
        assert!(!vc2.happens_before(&vc1));
    }

    #[test]
    fn test_vector_clock_concurrent() {
        let mut vc1 = VectorClock::new();
        vc1.increment("a");
        let mut vc2 = VectorClock::new();
        vc2.increment("b");
        assert!(vc1.is_concurrent(&vc2));
    }

    #[test]
    fn test_vector_clock_merge() {
        let mut vc1 = VectorClock::new();
        vc1.increment("a");
        let mut vc2 = VectorClock::new();
        vc2.increment("b");
        vc1.merge(&vc2);
        assert!(vc1.get("a").is_some());
        assert!(vc1.get("b").is_some());
    }

    #[test]
    fn test_document_insert_and_delete() {
        let mut doc = CRDTDocument::new("doc1".to_string(), "device_a".to_string());
        doc.insert_block("block1".to_string(), 0, "Hello".to_string());
        assert_eq!(doc.active_blocks().len(), 1);
        doc.delete_block("block1".to_string());
        assert_eq!(doc.active_blocks().len(), 0);
    }

    #[test]
    fn test_document_replace() {
        let mut doc = CRDTDocument::new("doc1".to_string(), "device_a".to_string());
        doc.insert_block("block1".to_string(), 0, "Hello".to_string());
        doc.replace_block("block1".to_string(), "Hello".to_string(), "World".to_string());
        let blocks = doc.active_blocks();
        assert_eq!(blocks[0].content, "World");
    }

    #[test]
    fn test_document_move() {
        let mut doc = CRDTDocument::new("doc1".to_string(), "device_a".to_string());
        doc.insert_block("block1".to_string(), 0, "First".to_string());
        doc.insert_block("block2".to_string(), 1, "Second".to_string());
        doc.move_block("block1".to_string(), 0, 1);
        let blocks = doc.active_blocks();
        assert_eq!(blocks[0].content, "Second");
        assert_eq!(blocks[1].content, "First");
    }

    #[test]
    fn test_text_crdt_insert_and_delete() {
        let mut text = TextCRDT::new("Hello".to_string());
        assert_eq!(text.to_string(), "Hello");
        let op_id = HLC::new("device_a".to_string());
        text.insert(5, '!', op_id);
        assert_eq!(text.to_string(), "Hello!");
    }

    #[test]
    fn test_text_crdt_merge() {
        let mut local = TextCRDT::new("Hello".to_string());
        let mut remote = TextCRDT::new("Hello".to_string());
        let mut op_id = HLC::new("device_b".to_string());
        op_id.logical = 100;
        remote.insert(5, '!', op_id);
        local.merge(&remote);
        assert!(local.to_string().contains('!'));
    }

    #[test]
    fn test_merge_documents() {
        let mut doc1 = CRDTDocument::new("doc1".to_string(), "device_a".to_string());
        doc1.insert_block("block1".to_string(), 0, "Hello".to_string());

        let mut doc2 = CRDTDocument::new("doc1".to_string(), "device_b".to_string());
        let op = doc2.insert_block("block2".to_string(), 0, "World".to_string());

        let result = doc1.merge(vec![op]);
        assert!(result.is_ok());
        assert_eq!(doc1.active_blocks().len(), 2);
    }

    #[test]
    fn test_tombstone_delete() {
        let mut doc = CRDTDocument::new("doc1".to_string(), "device_a".to_string());
        doc.insert_block("block1".to_string(), 0, "Hello".to_string());
        doc.delete_block("block1".to_string());
        let block = doc.blocks.iter().find(|b| b.id == "block1").unwrap();
        assert!(block.tombstone);
        assert_eq!(doc.active_blocks().len(), 0);
    }
}
