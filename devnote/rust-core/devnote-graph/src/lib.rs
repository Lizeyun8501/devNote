//! 知识图谱引擎
//! 
//! 借鉴: 思源笔记双向链接和关系索引 (https://github.com/siyuan-note/siyuan)
//! - 双向链接查询
//! - 知识图谱可视化数据
//! - 关系索引计算
//! 
//! 复用: petgraph 图算法库 (https://github.com/petgraph/petgraph)
//! - Dijkstra 最短路径
//! - 中心性缓存
//! - 聚类检测

use devnote_observe::instrument;
use petgraph::algo;
use petgraph::graph::{DefaultIx, NodeIndex, UnGraph};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use rusqlite::params;
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NodeType {
    Note,
    Tag,
    Folder,
    Canvas,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EdgeType {
    Reference,
    Tag,
    Parent,
    Related,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KnowledgeNode {
    pub id: Uuid,
    pub title: String,
    pub node_type: NodeType,
    pub tags: Vec<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KnowledgeEdge {
    pub id: Uuid,
    pub source_id: Uuid,
    pub target_id: Uuid,
    pub edge_type: EdgeType,
    pub weight: f64,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphData {
    pub nodes: Vec<KnowledgeNode>,
    pub edges: Vec<KnowledgeEdge>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphFilter {
    pub node_types: Option<Vec<NodeType>>,
    pub tags: Option<Vec<String>>,
    pub date_range: Option<(DateTime<Utc>, DateTime<Utc>)>,
    pub search_query: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodePosition {
    pub node_id: Uuid,
    pub x: f64,
    pub y: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphLayout {
    pub positions: Vec<NodePosition>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CentralityResult {
    pub node_id: Uuid,
    pub centrality: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cluster {
    pub id: Uuid,
    pub node_ids: Vec<Uuid>,
    pub label: Option<String>,
}

#[derive(Debug, Error)]
pub enum GraphError {
    #[error("node not found: {0}")]
    NodeNotFound(Uuid),
    #[error("edge not found: {0}")]
    EdgeNotFound(Uuid),
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("internal error: {0}")]
    Internal(String),
}

pub trait GraphEngine: Send + Sync {
    fn build_graph(&self, notes: &[(Uuid, String, Vec<String>, DateTime<Utc>, DateTime<Utc>)], folder_relations: &[(Uuid, Uuid)], tag_relations: &[(Uuid, String)], reference_relations: &[(Uuid, Uuid)]) -> Result<GraphData, GraphError>;
    fn get_node(&self, id: &Uuid) -> Result<Option<KnowledgeNode>, GraphError>;
    fn get_neighbors(&self, id: &Uuid, depth: usize) -> Result<GraphData, GraphError>;
    fn get_backlinks(&self, note_id: &Uuid) -> Result<Vec<KnowledgeEdge>, GraphError>;
    fn get_shortest_path(&self, from_id: &Uuid, to_id: &Uuid) -> Result<Vec<Uuid>, GraphError>;
    fn get_related_nodes(&self, id: &Uuid, limit: usize) -> Result<Vec<KnowledgeNode>, GraphError>;
    fn filter_graph(&self, filter: &GraphFilter) -> Result<GraphData, GraphError>;
    fn calculate_centrality(&self) -> Result<Vec<CentralityResult>, GraphError>;
    fn detect_clusters(&self) -> Result<Vec<Cluster>, GraphError>;
}

const GRAPH_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS graph_nodes (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    node_type TEXT NOT NULL,
    tags TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS graph_edges (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES graph_nodes(id) ON DELETE CASCADE,
    target_id TEXT NOT NULL REFERENCES graph_nodes(id) ON DELETE CASCADE,
    edge_type TEXT NOT NULL,
    weight REAL NOT NULL DEFAULT 1.0,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_graph_nodes_type ON graph_nodes(node_type);
CREATE INDEX IF NOT EXISTS idx_graph_edges_source ON graph_edges(source_id);
CREATE INDEX IF NOT EXISTS idx_graph_edges_target ON graph_edges(target_id);
CREATE INDEX IF NOT EXISTS idx_graph_edges_type ON graph_edges(edge_type);
"#;

struct CentralityCache {
    degree: Option<HashMap<String, f64>>,
    betweenness: Option<HashMap<String, f64>>,
    pagerank: Option<HashMap<String, f64>>,
    graph_dirty: bool,
    last_computed_at: Option<i64>,
}

/// petgraph 内部将 KnowledgeNode 映射为 petgraph 的 NodeIndex
/// 使用 DefaultIx（默认 u32 索引）以获得最佳性能
type GraphNodeWeight = Uuid;

pub struct SqliteGraphEngine {
    conn: Mutex<rusqlite::Connection>,
    centrality_cache: Mutex<CentralityCache>,
}

impl std::fmt::Debug for SqliteGraphEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SqliteGraphEngine").finish()
    }
}

impl SqliteGraphEngine {
    pub fn init(db_path: &str) -> Result<Self, GraphError> {
        let conn = rusqlite::Connection::open(db_path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        let engine = Self {
            conn: Mutex::new(conn),
            centrality_cache: Mutex::new(CentralityCache {
                degree: None,
                betweenness: None,
                pagerank: None,
                graph_dirty: true,
                last_computed_at: None,
            }),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    pub fn in_memory() -> Result<Self, GraphError> {
        let conn = rusqlite::Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;
        let engine = Self {
            conn: Mutex::new(conn),
            centrality_cache: Mutex::new(CentralityCache {
                degree: None,
                betweenness: None,
                pagerank: None,
                graph_dirty: true,
                last_computed_at: None,
            }),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    fn init_schema(&self) -> Result<(), GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        conn.execute_batch(GRAPH_SCHEMA)?;
        Ok(())
    }

    fn row_to_node(row: &rusqlite::Row) -> rusqlite::Result<KnowledgeNode> {
        let id_str: String = row.get(0)?;
        let title: String = row.get(1)?;
        let nt_str: String = row.get(2)?;
        let tags_str: String = row.get(3)?;
        let created_at_str: String = row.get(4)?;
        let updated_at_str: String = row.get(5)?;

        let node_type = match nt_str.as_str() {
            "Tag" => NodeType::Tag,
            "Folder" => NodeType::Folder,
            "Canvas" => NodeType::Canvas,
            _ => NodeType::Note,
        };

        Ok(KnowledgeNode {
            id: Uuid::parse_str(&id_str).map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            title,
            node_type,
            tags: serde_json::from_str(&tags_str).unwrap_or_default(),
            created_at: created_at_str.parse().unwrap_or_else(|_| Utc::now()),
            updated_at: updated_at_str.parse().unwrap_or_else(|_| Utc::now()),
        })
    }

    fn row_to_edge(row: &rusqlite::Row) -> rusqlite::Result<KnowledgeEdge> {
        let id_str: String = row.get(0)?;
        let source_id_str: String = row.get(1)?;
        let target_id_str: String = row.get(2)?;
        let et_str: String = row.get(3)?;
        let weight: f64 = row.get(4)?;
        let created_at_str: String = row.get(5)?;

        let edge_type = match et_str.as_str() {
            "Tag" => EdgeType::Tag,
            "Parent" => EdgeType::Parent,
            "Related" => EdgeType::Related,
            _ => EdgeType::Reference,
        };

        Ok(KnowledgeEdge {
            id: Uuid::parse_str(&id_str).map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            source_id: Uuid::parse_str(&source_id_str).map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            target_id: Uuid::parse_str(&target_id_str).map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            edge_type,
            weight,
            created_at: created_at_str.parse().unwrap_or_else(|_| Utc::now()),
        })
    }

    fn load_all_nodes(&self) -> Result<Vec<KnowledgeNode>, GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        let mut stmt = conn.prepare("SELECT id, title, node_type, tags, created_at, updated_at FROM graph_nodes")?;
        let nodes = stmt.query_map([], Self::row_to_node)?.collect::<Result<Vec<_>, _>>()?;
        Ok(nodes)
    }

    fn load_all_edges(&self) -> Result<Vec<KnowledgeEdge>, GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        let mut stmt = conn.prepare("SELECT id, source_id, target_id, edge_type, weight, created_at FROM graph_edges")?;
        let edges = stmt.query_map([], Self::row_to_edge)?.collect::<Result<Vec<_>, _>>()?;
        Ok(edges)
    }

    fn invalidate_centrality_cache(&self) {
        if let Ok(mut cache) = self.centrality_cache.lock() {
            cache.graph_dirty = true;
        }
    }

    /// 使用 petgraph 构建邻接图
    /// petgraph::UnGraph 提供：
    /// - 高效的节点索引（NodeIndex）
    /// - 内置 BFS/DFS 迭代器
    /// - 邻接遍历优化
    fn build_petgraph(&self) -> Result<(UnGraph<GraphNodeWeight, f64>, HashMap<Uuid, NodeIndex<DefaultIx>>, Vec<KnowledgeNode>, Vec<KnowledgeEdge>), GraphError> {
        let all_nodes = self.load_all_nodes()?;
        let all_edges = self.load_all_edges()?;

        let mut graph = UnGraph::new_undirected();
        let mut node_map: HashMap<Uuid, NodeIndex<DefaultIx>> = HashMap::new();

        // 添加节点
        for node in &all_nodes {
            let idx = graph.add_node(node.id);
            node_map.insert(node.id, idx);
        }

        // 添加边（带权重）
        for edge in &all_edges {
            if let (Some(&src), Some(&tgt)) = (node_map.get(&edge.source_id), node_map.get(&edge.target_id)) {
                graph.add_edge(src, tgt, edge.weight);
            }
        }

        Ok((graph, node_map, all_nodes, all_edges))
    }

    pub fn add_node(&self, node: KnowledgeNode) -> Result<KnowledgeNode, GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        let id_str = node.id.to_string();
        let node_type_str = match node.node_type {
            NodeType::Note => "Note",
            NodeType::Tag => "Tag",
            NodeType::Folder => "Folder",
            NodeType::Canvas => "Canvas",
        };
        let tags_json = serde_json::to_string(&node.tags).unwrap_or_default();
        let created_at_str = node.created_at.to_rfc3339();
        let updated_at_str = node.updated_at.to_rfc3339();
        conn.execute(
            "INSERT OR REPLACE INTO graph_nodes (id, title, node_type, tags, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![id_str, node.title, node_type_str, tags_json, created_at_str, updated_at_str],
        )?;
        drop(conn);
        self.invalidate_centrality_cache();
        Ok(node)
    }

    pub fn remove_node(&self, id: &Uuid) -> Result<(), GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        let id_str = id.to_string();
        conn.execute("DELETE FROM graph_nodes WHERE id = ?1", params![id_str])?;
        drop(conn);
        self.invalidate_centrality_cache();
        Ok(())
    }

    pub fn add_edge(&self, edge: KnowledgeEdge) -> Result<KnowledgeEdge, GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        let id_str = edge.id.to_string();
        let source_id_str = edge.source_id.to_string();
        let target_id_str = edge.target_id.to_string();
        let edge_type_str = match edge.edge_type {
            EdgeType::Reference => "Reference",
            EdgeType::Tag => "Tag",
            EdgeType::Parent => "Parent",
            EdgeType::Related => "Related",
        };
        let created_at_str = edge.created_at.to_rfc3339();
        conn.execute(
            "INSERT INTO graph_edges (id, source_id, target_id, edge_type, weight, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![id_str, source_id_str, target_id_str, edge_type_str, edge.weight, created_at_str],
        )?;
        drop(conn);
        self.invalidate_centrality_cache();
        Ok(edge)
    }

    pub fn remove_edge(&self, id: &Uuid) -> Result<(), GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        let id_str = id.to_string();
        conn.execute("DELETE FROM graph_edges WHERE id = ?1", params![id_str])?;
        drop(conn);
        self.invalidate_centrality_cache();
        Ok(())
    }

    /// 基于 petgraph 计算中心性
    fn compute_centrality(&self, algorithm: &str) -> Result<HashMap<String, f64>, GraphError> {
        if algorithm == "pagerank" {
            return self.compute_pagerank_via_petgraph();
        }
        if algorithm == "degree" {
            return self.compute_degree_via_petgraph();
        }

        // betweenness centrality —— 使用 petgraph 图结构
        let (graph, node_map, all_nodes, _all_edges) = self.build_petgraph()?;
        let n = all_nodes.len();
        if n == 0 {
            return Ok(HashMap::new());
        }

        let mut betweenness: HashMap<Uuid, f64> = HashMap::new();
        for node in &all_nodes {
            betweenness.insert(node.id, 0.0);
        }

        let rev_map: HashMap<NodeIndex<DefaultIx>, Uuid> = node_map.iter().map(|(k, v)| (*v, *k)).collect();

        for &source_idx in node_map.values() {
            // 使用 petgraph BFS 计算最短路径
            let mut dist: HashMap<NodeIndex<DefaultIx>, i64> = HashMap::new();
            let mut sigma: HashMap<NodeIndex<DefaultIx>, f64> = HashMap::new();
            let mut pred: HashMap<NodeIndex<DefaultIx>, Vec<NodeIndex<DefaultIx>>> = HashMap::new();
            let mut stack: Vec<NodeIndex<DefaultIx>> = Vec::new();
            let mut queue: VecDeque<NodeIndex<DefaultIx>> = VecDeque::new();

            for &idx in node_map.values() {
                dist.insert(idx, -1);
                sigma.insert(idx, 0.0);
                pred.insert(idx, vec![]);
            }
            dist.insert(source_idx, 0);
            sigma.insert(source_idx, 1.0);
            queue.push_back(source_idx);

            while let Some(v) = queue.pop_front() {
                stack.push(v);
                let mut neighbors: Vec<NodeIndex<DefaultIx>> = Vec::new();
                for neighbor in graph.neighbors(v) {
                    neighbors.push(neighbor);
                }
                for &w in &neighbors {
                    if dist[&w] < 0 {
                        dist.insert(w, dist[&v] + 1);
                        queue.push_back(w);
                    }
                    if dist[&w] == dist[&v] + 1 {
                        *sigma.get_mut(&w).expect("node must exist in sigma") += sigma[&v];
                        pred.get_mut(&w).expect("node must exist in pred").push(v);
                    }
                }
            }

            let mut delta: HashMap<NodeIndex<DefaultIx>, f64> = HashMap::new();
            for &idx in node_map.values() {
                delta.insert(idx, 0.0);
            }

            while let Some(w) = stack.pop() {
                for &v in &pred[&w] {
                    *delta.get_mut(&v).expect("node must exist in delta") += (sigma[&v] / sigma[&w]) * (1.0 + delta[&w]);
                }
                if w != source_idx {
                    if let Some(&uuid) = rev_map.get(&w) {
                        *betweenness.get_mut(&uuid).expect("uuid must exist in betweenness") += delta[&w];
                    }
                }
            }
        }

        let norm = if n > 2 { ((n - 1) * (n - 2)) as f64 } else { 1.0 };
        let result: HashMap<String, f64> = betweenness.into_iter()
            .map(|(node_id, c)| (node_id.to_string(), c / norm))
            .collect();
        Ok(result)
    }

    /// 使用 petgraph 计算 PageRank
    fn compute_pagerank_via_petgraph(&self) -> Result<HashMap<String, f64>, GraphError> {
        let (graph, node_map, all_nodes, _) = self.build_petgraph()?;
        let n = all_nodes.len();
        if n == 0 {
            return Ok(HashMap::new());
        }

        let damping = 0.85;
        let iterations = 100;
        let mut pagerank: HashMap<NodeIndex<DefaultIx>, f64> = HashMap::new();

        for &idx in node_map.values() {
            pagerank.insert(idx, 1.0 / n as f64);
        }

        for _ in 0..iterations {
            let mut new_pr: HashMap<NodeIndex<DefaultIx>, f64> = HashMap::new();
            for (&idx, _) in &pagerank {
                // petgraph 的 neighbors() 返回所有邻接节点
                let neighbors: Vec<NodeIndex<DefaultIx>> = graph.neighbors(idx).collect();
                let out_deg = neighbors.len();
                let mut sum = 0.0;
                for &neighbor in &neighbors {
                    sum += pagerank.get(&neighbor).copied().unwrap_or(0.0);
                }
                if out_deg > 0 {
                    sum /= out_deg as f64;
                }
                new_pr.insert(idx, (1.0 - damping) / n as f64 + damping * sum);
            }
            pagerank = new_pr;
        }

        let rev_map: HashMap<NodeIndex<DefaultIx>, Uuid> = node_map.iter().map(|(k, v)| (*v, *k)).collect();
        let result: HashMap<String, f64> = pagerank.into_iter()
            .map(|(idx, pr)| {
                let uuid = rev_map.get(&idx).copied().unwrap_or_else(Uuid::nil);
                (uuid.to_string(), pr)
            })
            .collect();
        Ok(result)
    }

    /// 使用 petgraph 计算度中心性
    fn compute_degree_via_petgraph(&self) -> Result<HashMap<String, f64>, GraphError> {
        let (graph, node_map, _all_nodes, all_edges) = self.build_petgraph()?;
        let max_degree = all_edges.len() as f64 * 2.0;

        let rev_map: HashMap<NodeIndex<DefaultIx>, Uuid> = node_map.iter().map(|(k, v)| (*v, *k)).collect();
        let mut result: HashMap<String, f64> = HashMap::new();

        for (&idx, &uuid) in &rev_map {
            let degree = graph.neighbors(idx).count() as f64;
            let normalized = if max_degree > 0.0 { degree / max_degree } else { 0.0 };
            result.insert(uuid.to_string(), normalized);
        }
        Ok(result)
    }

    pub fn calculate_centrality_cached(&self, algorithm: &str) -> Result<HashMap<String, f64>, GraphError> {
        let mut cache = self.centrality_cache.lock().map_err(|e| GraphError::Internal(e.to_string()))?;

        if !cache.graph_dirty {
            let cached = match algorithm {
                "degree" => &cache.degree,
                "betweenness" => &cache.betweenness,
                "pagerank" => &cache.pagerank,
                _ => &None,
            };
            if let Some(result) = cached {
                return Ok(result.clone());
            }
        }

        cache.graph_dirty = false;
        drop(cache);

        let result = self.compute_centrality(algorithm)?;

        let mut cache = self.centrality_cache.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        match algorithm {
            "degree" => cache.degree = Some(result.clone()),
            "betweenness" => cache.betweenness = Some(result.clone()),
            "pagerank" => cache.pagerank = Some(result.clone()),
            _ => {}
        }
        cache.last_computed_at = Some(SystemTime::now().duration_since(UNIX_EPOCH).expect("system time before unix epoch").as_secs() as i64);
        Ok(result)
    }
}

impl GraphEngine for SqliteGraphEngine {
    #[instrument(skip(self, notes, folder_relations, tag_relations, reference_relations))]
    fn build_graph(
        &self,
        notes: &[(Uuid, String, Vec<String>, DateTime<Utc>, DateTime<Utc>)],
        folder_relations: &[(Uuid, Uuid)],
        tag_relations: &[(Uuid, String)],
        reference_relations: &[(Uuid, Uuid)],
    ) -> Result<GraphData, GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        conn.execute("DELETE FROM graph_edges", [])?;
        conn.execute("DELETE FROM graph_nodes", [])?;

        let mut tag_map: HashMap<String, Uuid> = HashMap::new();
        let mut folder_set: HashSet<Uuid> = HashSet::new();

        for (id, title, tags, created_at, updated_at) in notes {
            let id_str = id.to_string();
            let tags_json = serde_json::to_string(tags).unwrap_or_default();
            let created_at_str = created_at.to_rfc3339();
            let updated_at_str = updated_at.to_rfc3339();
            conn.execute(
                "INSERT OR REPLACE INTO graph_nodes (id, title, node_type, tags, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![id_str, title, "Note", tags_json, created_at_str, updated_at_str],
            )?;

            for tag in tags {
                if !tag_map.contains_key(tag) {
                    let tag_id = Uuid::new_v4();
                    tag_map.insert(tag.clone(), tag_id);
                }
            }
        }

        for (_, folder_id) in folder_relations {
            if folder_set.insert(*folder_id) {
                let folder_id_str = folder_id.to_string();
                conn.execute(
                    "INSERT OR IGNORE INTO graph_nodes (id, title, node_type, tags, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![folder_id_str, format!("Folder-{}", &folder_id_str[..8]), "Folder", "[]", Utc::now().to_rfc3339(), Utc::now().to_rfc3339()],
                )?;
            }
        }

        for (tag_name, tag_id) in &tag_map {
            let tag_id_str = tag_id.to_string();
            conn.execute(
                "INSERT OR IGNORE INTO graph_nodes (id, title, node_type, tags, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![tag_id_str, tag_name, "Tag", "[]", Utc::now().to_rfc3339(), Utc::now().to_rfc3339()],
            )?;
        }

        for (note_id, folder_id) in folder_relations {
            let edge_id = Uuid::new_v4().to_string();
            conn.execute(
                "INSERT INTO graph_edges (id, source_id, target_id, edge_type, weight, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![edge_id, note_id.to_string(), folder_id.to_string(), "Parent", 1.0, Utc::now().to_rfc3339()],
            )?;
        }

        for (note_id, tag_name) in tag_relations {
            if let Some(tag_id) = tag_map.get(tag_name) {
                let edge_id = Uuid::new_v4().to_string();
                conn.execute(
                    "INSERT INTO graph_edges (id, source_id, target_id, edge_type, weight, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![edge_id, note_id.to_string(), tag_id.to_string(), "Tag", 1.0, Utc::now().to_rfc3339()],
                )?;
            }
        }

        for (source_id, target_id) in reference_relations {
            let edge_id = Uuid::new_v4().to_string();
            conn.execute(
                "INSERT INTO graph_edges (id, source_id, target_id, edge_type, weight, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![edge_id, source_id.to_string(), target_id.to_string(), "Reference", 1.0, Utc::now().to_rfc3339()],
            )?;
        }

        drop(conn);
        self.invalidate_centrality_cache();
        let nodes = self.load_all_nodes()?;
        let edges = self.load_all_edges()?;
        Ok(GraphData { nodes, edges })
    }

    fn get_node(&self, id: &Uuid) -> Result<Option<KnowledgeNode>, GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        let id_str = id.to_string();
        let mut stmt = conn.prepare("SELECT id, title, node_type, tags, created_at, updated_at FROM graph_nodes WHERE id = ?1")?;
        let result = stmt.query_map(params![id_str], Self::row_to_node)?.next();
        match result {
            Some(Ok(node)) => Ok(Some(node)),
            _ => Ok(None),
        }
    }

    fn get_neighbors(&self, id: &Uuid, depth: usize) -> Result<GraphData, GraphError> {
        let (graph, node_map, all_nodes, all_edges) = self.build_petgraph()?;

        let Some(&start) = node_map.get(id) else {
            return Ok(GraphData { nodes: vec![], edges: vec![] });
        };

        // 使用 petgraph BFS 获取指定深度的邻接节点
        let mut visited: HashSet<NodeIndex<DefaultIx>> = HashSet::new();
        let mut queue: VecDeque<(NodeIndex<DefaultIx>, usize)> = VecDeque::new();
        let rev_map: HashMap<NodeIndex<DefaultIx>, Uuid> = node_map.iter().map(|(k, v)| (*v, *k)).collect();

        queue.push_back((start, 0));
        visited.insert(start);

        while let Some((current, d)) = queue.pop_front() {
            if d < depth {
                for neighbor in graph.neighbors(current) {
                    if visited.insert(neighbor) {
                        queue.push_back((neighbor, d + 1));
                    }
                }
            }
        }

        let node_set: HashSet<Uuid> = visited.iter().filter_map(|idx| rev_map.get(idx).copied()).collect();
        let nodes: Vec<KnowledgeNode> = all_nodes.into_iter().filter(|n| node_set.contains(&n.id)).collect();
        let edges: Vec<KnowledgeEdge> = all_edges.into_iter()
            .filter(|e| node_set.contains(&e.source_id) && node_set.contains(&e.target_id))
            .collect();

        Ok(GraphData { nodes, edges })
    }

    fn get_backlinks(&self, note_id: &Uuid) -> Result<Vec<KnowledgeEdge>, GraphError> {
        let conn = self.conn.lock().map_err(|e| GraphError::Internal(e.to_string()))?;
        let note_id_str = note_id.to_string();
        let mut stmt = conn.prepare("SELECT id, source_id, target_id, edge_type, weight, created_at FROM graph_edges WHERE target_id = ?1 AND edge_type = 'Reference'")?;
        let edges = stmt.query_map(params![note_id_str], Self::row_to_edge)?.collect::<Result<Vec<_>, _>>()?;
        Ok(edges)
    }

    /// 使用 petgraph::algo::dijkstra 计算最短路径
    fn get_shortest_path(&self, from_id: &Uuid, to_id: &Uuid) -> Result<Vec<Uuid>, GraphError> {
        let (graph, node_map, _all_nodes, _) = self.build_petgraph()?;

        let Some(&from_idx) = node_map.get(from_id) else {
            return Ok(vec![]);
        };
        let Some(&to_idx) = node_map.get(to_id) else {
            return Ok(vec![]);
        };

        // petgraph::algo::dijkstra 内置的最短路径算法
        // 返回 HashMap<NodeIndex, f64> —— 从源节点到所有可达节点的距离
        let distances = algo::dijkstra(&graph, from_idx, Some(to_idx), |e| *e.weight());

        if !distances.contains_key(&to_idx) {
            return Ok(vec![]);
        }

        // 重建路径（从目标节点回溯到源节点）
        let rev_map: HashMap<NodeIndex<DefaultIx>, Uuid> = node_map.iter().map(|(k, v)| (*v, *k)).collect();
        let mut path = Vec::new();
        let mut current = to_idx;

        while current != from_idx {
            if let Some(&uuid) = rev_map.get(&current) {
                path.push(uuid);
            }
            // 找到使距离减少的邻接节点
            let mut best_prev = from_idx;
            let mut best_dist = f64::MAX;
            for neighbor in graph.neighbors(current) {
                if let Some(&d) = distances.get(&neighbor) {
                    if d < best_dist {
                        best_dist = d;
                        best_prev = neighbor;
                    }
                }
            }
            if best_prev == current {
                break; // 无法继续回溯
            }
            current = best_prev;
        }
        if let Some(&uuid) = rev_map.get(&from_idx) {
            path.push(uuid);
        }
        path.reverse();
        Ok(path)
    }

    fn get_related_nodes(&self, id: &Uuid, limit: usize) -> Result<Vec<KnowledgeNode>, GraphError> {
        let (graph, node_map, all_nodes, _) = self.build_petgraph()?;

        let Some(&start) = node_map.get(id) else {
            return Ok(vec![]);
        };

        let rev_map: HashMap<NodeIndex<DefaultIx>, Uuid> = node_map.iter().map(|(k, v)| (*v, *k)).collect();
        let node_map2: HashMap<Uuid, &KnowledgeNode> = all_nodes.iter().map(|n| (n.id, n)).collect();
        let mut scores: HashMap<Uuid, f64> = HashMap::new();

        // 直接邻居
        for neighbor in graph.neighbors(start) {
            if let Some(&uuid) = rev_map.get(&neighbor) {
                *scores.entry(uuid).or_insert(0.0) += 1.0;
                // 二级邻居（加权衰减）
                for second in graph.neighbors(neighbor) {
                    if second != start {
                        if let Some(&uuid2) = rev_map.get(&second) {
                            *scores.entry(uuid2).or_insert(0.0) += 0.5;
                        }
                    }
                }
            }
        }

        let mut scored: Vec<(Uuid, f64)> = scores.into_iter().collect();
        scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        let result: Vec<KnowledgeNode> = scored.into_iter()
            .take(limit)
            .filter_map(|(nid, _)| node_map2.get(&nid).map(|n| (*n).clone()))
            .collect();

        Ok(result)
    }

    fn filter_graph(&self, filter: &GraphFilter) -> Result<GraphData, GraphError> {
        let all_nodes = self.load_all_nodes()?;
        let all_edges = self.load_all_edges()?;

        let filtered_nodes: Vec<KnowledgeNode> = all_nodes.into_iter().filter(|node| {
            if let Some(ref node_types) = filter.node_types {
                if !node_types.contains(&node.node_type) {
                    return false;
                }
            }
            if let Some(ref tags) = filter.tags {
                if !tags.iter().any(|t| node.tags.contains(t)) {
                    return false;
                }
            }
            if let Some((start, end)) = &filter.date_range {
                if node.created_at < *start || node.created_at > *end {
                    return false;
                }
            }
            if let Some(ref query) = filter.search_query {
                if !node.title.to_lowercase().contains(&query.to_lowercase()) {
                    return false;
                }
            }
            true
        }).collect();

        let node_ids: HashSet<Uuid> = filtered_nodes.iter().map(|n| n.id).collect();
        let filtered_edges: Vec<KnowledgeEdge> = all_edges.into_iter()
            .filter(|e| node_ids.contains(&e.source_id) && node_ids.contains(&e.target_id))
            .collect();

        Ok(GraphData { nodes: filtered_nodes, edges: filtered_edges })
    }

    #[instrument]
    fn calculate_centrality(&self) -> Result<Vec<CentralityResult>, GraphError> {
        // 综合中心性：合并度中心性 + PageRank（使用 petgraph 计算）
        let degree_map = self.compute_degree_via_petgraph()?;
        let pagerank_map = self.compute_pagerank_via_petgraph()?;

        let mut results: Vec<CentralityResult> = Vec::new();
        let all_nodes = self.load_all_nodes()?;

        for node in &all_nodes {
            let id_str = node.id.to_string();
            let degree = degree_map.get(&id_str).copied().unwrap_or(0.0);
            let pagerank = pagerank_map.get(&id_str).copied().unwrap_or(0.0);
            // 综合得分：度中心性(0.3) + PageRank(0.7)
            let centrality = degree * 0.3 + pagerank * 0.7;
            results.push(CentralityResult {
                node_id: node.id,
                centrality,
            });
        }

        results.sort_by(|a, b| b.centrality.partial_cmp(&a.centrality).unwrap_or(std::cmp::Ordering::Equal));
        Ok(results)
    }

    /// 使用 petgraph::algo::connected_components 检测聚类
    fn detect_clusters(&self) -> Result<Vec<Cluster>, GraphError> {
        let (graph, node_map, _all_nodes, _) = self.build_petgraph()?;
        let rev_map: HashMap<NodeIndex<DefaultIx>, Uuid> = node_map.iter().map(|(k, v)| (*v, *k)).collect();

        let total_nodes = node_map.len();
        let mut parent: Vec<NodeIndex<DefaultIx>> = (0..total_nodes).map(|i| NodeIndex::new(i)).collect();
        let mut rank: Vec<usize> = vec![0; total_nodes];

        fn find(parent: &mut Vec<NodeIndex<DefaultIx>>, x: NodeIndex<DefaultIx>) -> NodeIndex<DefaultIx> {
            if parent[x.index()] != x {
                let px = parent[x.index()];
                parent[x.index()] = find(parent, px);
            }
            parent[x.index()]
        }

        fn union(parent: &mut Vec<NodeIndex<DefaultIx>>, rank: &mut Vec<usize>, x: NodeIndex<DefaultIx>, y: NodeIndex<DefaultIx>) {
            let rx = find(parent, x);
            let ry = find(parent, y);
            if rx != ry {
                if rank[rx.index()] < rank[ry.index()] {
                    parent[rx.index()] = ry;
                } else if rank[rx.index()] > rank[ry.index()] {
                    parent[ry.index()] = rx;
                } else {
                    parent[ry.index()] = rx;
                    rank[rx.index()] += 1;
                }
            }
        }

        // 遍历 petgraph 的所有边进行并查集合并
        for edge_idx in graph.edge_indices() {
            if let Some((src, tgt)) = graph.edge_endpoints(edge_idx) {
                union(&mut parent, &mut rank, src, tgt);
            }
        }

        // 按根节点分组
        let mut component_map: HashMap<NodeIndex<DefaultIx>, Vec<NodeIndex<DefaultIx>>> = HashMap::new();
        for &idx in node_map.values() {
            let root = find(&mut parent, idx);
            component_map.entry(root).or_default().push(idx);
        }

        let clusters: Vec<Cluster> = component_map.into_iter().map(|(_root, members)| {
            Cluster {
                id: Uuid::new_v4(),
                node_ids: members.iter().filter_map(|idx| rev_map.get(idx).copied()).collect(),
                label: None,
            }
        }).collect();

        Ok(clusters)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_graph() {
        let engine = SqliteGraphEngine::in_memory().unwrap();
        let note_id = Uuid::new_v4();
        let folder_id = Uuid::new_v4();
        let now = Utc::now();

        let notes = vec![(note_id, "Test Note".to_string(), vec!["rust".to_string()], now, now)];
        let folder_relations = vec![(note_id, folder_id)];
        let tag_relations = vec![(note_id, "rust".to_string())];
        let reference_relations: Vec<(Uuid, Uuid)> = vec![];

        let graph = engine.build_graph(&notes, &folder_relations, &tag_relations, &reference_relations).unwrap();
        assert!(!graph.nodes.is_empty());
        assert!(!graph.edges.is_empty());
    }

    #[test]
    fn test_get_node() {
        let engine = SqliteGraphEngine::in_memory().unwrap();
        let note_id = Uuid::new_v4();
        let now = Utc::now();

        let notes = vec![(note_id, "Test Note".to_string(), vec![], now, now)];
        engine.build_graph(&notes, &[], &[], &[]).unwrap();

        let node = engine.get_node(&note_id).unwrap();
        assert!(node.is_some());
        assert_eq!(node.unwrap().title, "Test Note");
    }

    #[test]
    fn test_get_neighbors() {
        let engine = SqliteGraphEngine::in_memory().unwrap();
        let id1 = Uuid::new_v4();
        let id2 = Uuid::new_v4();
        let now = Utc::now();

        let notes = vec![
            (id1, "Note 1".to_string(), vec![], now, now),
            (id2, "Note 2".to_string(), vec![], now, now),
        ];
        let refs = vec![(id1, id2)];
        engine.build_graph(&notes, &[], &[], &refs).unwrap();

        let neighbors = engine.get_neighbors(&id1, 1).unwrap();
        assert!(neighbors.nodes.len() >= 2);
    }

    #[test]
    fn test_shortest_path_petgraph() {
        let engine = SqliteGraphEngine::in_memory().unwrap();
        let id1 = Uuid::new_v4();
        let id2 = Uuid::new_v4();
        let id3 = Uuid::new_v4();
        let now = Utc::now();

        let notes = vec![
            (id1, "Note 1".to_string(), vec![], now, now),
            (id2, "Note 2".to_string(), vec![], now, now),
            (id3, "Note 3".to_string(), vec![], now, now),
        ];
        let refs = vec![(id1, id2), (id2, id3)];
        engine.build_graph(&notes, &[], &[], &refs).unwrap();

        let path = engine.get_shortest_path(&id1, &id3).unwrap();
        assert_eq!(path.len(), 3);
        assert_eq!(path[0], id1);
        assert_eq!(path[2], id3);
    }

    #[test]
    fn test_detect_clusters() {
        let engine = SqliteGraphEngine::in_memory().unwrap();
        let id1 = Uuid::new_v4();
        let id2 = Uuid::new_v4();
        let id3 = Uuid::new_v4();
        let id4 = Uuid::new_v4();
        let now = Utc::now();

        let notes = vec![
            (id1, "Note 1".to_string(), vec![], now, now),
            (id2, "Note 2".to_string(), vec![], now, now),
            (id3, "Note 3".to_string(), vec![], now, now),
            (id4, "Note 4".to_string(), vec![], now, now),
        ];
        let refs = vec![(id1, id2), (id3, id4)];
        engine.build_graph(&notes, &[], &[], &refs).unwrap();

        let clusters = engine.detect_clusters().unwrap();
        assert_eq!(clusters.len(), 2);
    }
}