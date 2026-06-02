use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum CanvasError {
    #[error("canvas not found: {0}")]
    CanvasNotFound(String),
    #[error("node not found: {0}")]
    NodeNotFound(String),
    #[error("edge not found: {0}")]
    EdgeNotFound(String),
    #[error("io error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NodeType {
    Note,
    Image,
    File,
    Link,
    Group,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Side {
    Top,
    Bottom,
    Left,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LayoutType {
    Grid,
    Force,
    Hierarchical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Alignment {
    Left,
    Center,
    Right,
    Top,
    Middle,
    Bottom,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DistributeDirection {
    Horizontal,
    Vertical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CanvasNode {
    pub id: String,
    #[serde(rename = "type")]
    pub node_type: NodeType,
    pub x: i64,
    pub y: i64,
    pub width: i64,
    pub height: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CanvasEdge {
    pub id: String,
    #[serde(rename = "fromNode")]
    pub from_node: String,
    #[serde(rename = "toNode")]
    pub to_node: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    #[serde(rename = "fromSide", skip_serializing_if = "Option::is_none")]
    pub from_side: Option<Side>,
    #[serde(rename = "toSide", skip_serializing_if = "Option::is_none")]
    pub to_side: Option<Side>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CanvasData {
    pub nodes: Vec<CanvasNode>,
    pub edges: Vec<CanvasEdge>,
}

impl Default for CanvasData {
    fn default() -> Self {
        Self {
            nodes: Vec::new(),
            edges: Vec::new(),
        }
    }
}

pub struct CanvasEngine {
    canvases: HashMap<String, CanvasData>,
}

impl CanvasEngine {
    pub fn new() -> Self {
        Self {
            canvases: HashMap::new(),
        }
    }

    pub fn create_canvas(&mut self) -> String {
        let id = Uuid::new_v4().to_string();
        self.canvases.insert(id.clone(), CanvasData::default());
        id
    }

    pub fn add_node(&mut self, canvas_id: &str, node: CanvasNode) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;
        canvas.nodes.push(node);
        Ok(())
    }

    pub fn remove_node(&mut self, canvas_id: &str, node_id: &str) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;
        let before = canvas.nodes.len();
        canvas.nodes.retain(|n| n.id != node_id);
        if canvas.nodes.len() == before {
            return Err(CanvasError::NodeNotFound(node_id.to_string()));
        }
        canvas.edges.retain(|e| e.from_node != node_id && e.to_node != node_id);
        Ok(())
    }

    pub fn move_node(
        &mut self,
        canvas_id: &str,
        node_id: &str,
        x: i64,
        y: i64,
    ) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;
        let node = canvas
            .nodes
            .iter_mut()
            .find(|n| n.id == node_id)
            .ok_or_else(|| CanvasError::NodeNotFound(node_id.to_string()))?;
        node.x = x;
        node.y = y;
        Ok(())
    }

    pub fn resize_node(
        &mut self,
        canvas_id: &str,
        node_id: &str,
        width: i64,
        height: i64,
    ) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;
        let node = canvas
            .nodes
            .iter_mut()
            .find(|n| n.id == node_id)
            .ok_or_else(|| CanvasError::NodeNotFound(node_id.to_string()))?;
        node.width = width;
        node.height = height;
        Ok(())
    }

    pub fn add_edge(&mut self, canvas_id: &str, edge: CanvasEdge) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;
        canvas.edges.push(edge);
        Ok(())
    }

    pub fn remove_edge(&mut self, canvas_id: &str, edge_id: &str) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;
        let before = canvas.edges.len();
        canvas.edges.retain(|e| e.id != edge_id);
        if canvas.edges.len() == before {
            return Err(CanvasError::EdgeNotFound(edge_id.to_string()));
        }
        Ok(())
    }

    pub fn get_canvas(&self, canvas_id: &str) -> Result<&CanvasData, CanvasError> {
        self.canvases
            .get(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))
    }

    pub fn save_canvas(&self, canvas_id: &str, path: &str) -> Result<(), CanvasError> {
        let canvas = self.get_canvas(canvas_id)?;
        let json = serde_json::to_string_pretty(canvas)?;
        fs::write(Path::new(path), json)?;
        Ok(())
    }

    pub fn load_canvas(&mut self, path: &str) -> Result<String, CanvasError> {
        let content = fs::read_to_string(Path::new(path))?;
        let data: CanvasData = serde_json::from_str(&content)?;
        let id = Uuid::new_v4().to_string();
        self.canvases.insert(id.clone(), data);
        Ok(id)
    }

    pub fn auto_layout(
        &mut self,
        canvas_id: &str,
        layout_type: LayoutType,
    ) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;

        match layout_type {
            LayoutType::Grid => {
                let cols = (canvas.nodes.len() as f64).sqrt().ceil() as usize;
                let gap_x: i64 = 300;
                let gap_y: i64 = 250;
                for (i, node) in canvas.nodes.iter_mut().enumerate() {
                    let row = i / cols;
                    let col = i % cols;
                    node.x = col as i64 * gap_x;
                    node.y = row as i64 * gap_y;
                }
            }
            LayoutType::Force => {
                let n = canvas.nodes.len();
                if n == 0 {
                    return Ok(());
                }
                let iterations = 100;
                let k = 300.0_f64;
                let gravity = 0.01;
                let damping = 0.9;
                let mut vx = vec![0.0_f64; n];
                let mut vy = vec![0.0_f64; n];

                for _ in 0..iterations {
                    for i in 0..n {
                        for j in (i + 1)..n {
                            let dx = canvas.nodes[j].x as f64 - canvas.nodes[i].x as f64;
                            let dy = canvas.nodes[j].y as f64 - canvas.nodes[i].y as f64;
                            let dist = (dx * dx + dy * dy).sqrt().max(1.0);
                            let force = k * k / dist;
                            let fx = dx / dist * force;
                            let fy = dy / dist * force;
                            vx[i] -= fx;
                            vy[i] -= fy;
                            vx[j] += fx;
                            vy[j] += fy;
                        }
                    }
                    for edge in &canvas.edges {
                        let from_idx = canvas.nodes.iter().position(|n| n.id == edge.from_node);
                        let to_idx = canvas.nodes.iter().position(|n| n.id == edge.to_node);
                        if let (Some(fi), Some(ti)) = (from_idx, to_idx) {
                            let dx = canvas.nodes[ti].x as f64 - canvas.nodes[fi].x as f64;
                            let dy = canvas.nodes[ti].y as f64 - canvas.nodes[fi].y as f64;
                            let dist = (dx * dx + dy * dy).sqrt().max(1.0);
                            let force = (dist - k) * 0.05;
                            let fx = dx / dist * force;
                            let fy = dy / dist * force;
                            vx[fi] += fx;
                            vy[fi] += fy;
                            vx[ti] -= fx;
                            vy[ti] -= fy;
                        }
                    }
                    for i in 0..n {
                        vx[i] -= canvas.nodes[i].x as f64 * gravity;
                        vy[i] -= canvas.nodes[i].y as f64 * gravity;
                        vx[i] *= damping;
                        vy[i] *= damping;
                        canvas.nodes[i].x += vx[i] as i64;
                        canvas.nodes[i].y += vy[i] as i64;
                    }
                }
            }
            LayoutType::Hierarchical => {
                let mut in_degree: HashMap<&str, usize> = HashMap::new();
                let mut adj: HashMap<&str, Vec<&str>> = HashMap::new();
                for node in &canvas.nodes {
                    in_degree.entry(&node.id).or_insert(0);
                    adj.entry(&node.id).or_insert_with(Vec::new);
                }
                for edge in &canvas.edges {
                    *in_degree.entry(&edge.to_node).or_insert(0) += 1;
                    adj.entry(&edge.from_node).or_default().push(&edge.to_node);
                }
                let mut layers: Vec<Vec<&str>> = Vec::new();
                let mut remaining: std::collections::HashSet<&str> =
                    canvas.nodes.iter().map(|n| n.id.as_str()).collect();
                while !remaining.is_empty() {
                    let mut layer: Vec<&str> = remaining
                        .iter()
                        .filter(|id| *in_degree.get(*id).unwrap_or(&0) == 0)
                        .copied()
                        .collect();
                    if layer.is_empty() {
                        layer = remaining.iter().copied().collect();
                    }
                    for id in &layer {
                        remaining.remove(id);
                        if let Some(neighbors) = adj.get(id) {
                            for neighbor in neighbors {
                                if let Some(deg) = in_degree.get_mut(neighbor) {
                                    *deg = deg.saturating_sub(1);
                                }
                            }
                        }
                    }
                    layers.push(layer);
                }
                let gap_y: i64 = 250;
                let gap_x: i64 = 300;
                let mut positions: HashMap<String, (i64, i64)> = HashMap::new();
                for (layer_idx, layer) in layers.iter().enumerate() {
                    let start_x = -((layer.len() as i64 - 1) * gap_x) / 2;
                    for (node_idx, id) in layer.iter().enumerate() {
                        positions.insert(id.to_string(), (start_x + node_idx as i64 * gap_x, layer_idx as i64 * gap_y));
                    }
                }
                for node in &mut canvas.nodes {
                    if let Some((x, y)) = positions.get(&node.id) {
                        node.x = *x;
                        node.y = *y;
                    }
                }
            }
        }
        Ok(())
    }

    pub fn align_nodes(
        &mut self,
        canvas_id: &str,
        node_ids: &[String],
        alignment: Alignment,
    ) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;

        let nodes: Vec<&mut CanvasNode> = canvas
            .nodes
            .iter_mut()
            .filter(|n| node_ids.contains(&n.id))
            .collect();
        if nodes.is_empty() {
            return Ok(());
        }

        match alignment {
            Alignment::Left => {
                let min_x = nodes.iter().map(|n| n.x).min().unwrap();
                for node in &mut canvas.nodes {
                    if node_ids.contains(&node.id) {
                        node.x = min_x;
                    }
                }
            }
            Alignment::Right => {
                let max_x = nodes.iter().map(|n| n.x + n.width).max().unwrap();
                for node in &mut canvas.nodes {
                    if node_ids.contains(&node.id) {
                        node.x = max_x - node.width;
                    }
                }
            }
            Alignment::Center => {
                let avg_x: i64 = nodes.iter().map(|n| n.x + n.width / 2).sum::<i64>()
                    / nodes.len() as i64;
                for node in &mut canvas.nodes {
                    if node_ids.contains(&node.id) {
                        node.x = avg_x - node.width / 2;
                    }
                }
            }
            Alignment::Top => {
                let min_y = nodes.iter().map(|n| n.y).min().unwrap();
                for node in &mut canvas.nodes {
                    if node_ids.contains(&node.id) {
                        node.y = min_y;
                    }
                }
            }
            Alignment::Bottom => {
                let max_y = nodes.iter().map(|n| n.y + n.height).max().unwrap();
                for node in &mut canvas.nodes {
                    if node_ids.contains(&node.id) {
                        node.y = max_y - node.height;
                    }
                }
            }
            Alignment::Middle => {
                let avg_y: i64 = nodes.iter().map(|n| n.y + n.height / 2).sum::<i64>()
                    / nodes.len() as i64;
                for node in &mut canvas.nodes {
                    if node_ids.contains(&node.id) {
                        node.y = avg_y - node.height / 2;
                    }
                }
            }
        }
        Ok(())
    }

    pub fn distribute_nodes(
        &mut self,
        canvas_id: &str,
        node_ids: &[String],
        direction: DistributeDirection,
    ) -> Result<(), CanvasError> {
        let canvas = self
            .canvases
            .get_mut(canvas_id)
            .ok_or_else(|| CanvasError::CanvasNotFound(canvas_id.to_string()))?;

        if node_ids.len() < 2 {
            return Ok(());
        }

        let mut positions: Vec<(String, i64, i64, i64, i64)> = canvas
            .nodes
            .iter()
            .filter(|n| node_ids.contains(&n.id))
            .map(|n| (n.id.clone(), n.x, n.y, n.width, n.height))
            .collect();

        match direction {
            DistributeDirection::Horizontal => {
                positions.sort_by_key(|p| p.1);
                let min_x = positions.first().unwrap().1;
                let max_x = positions
                    .last()
                    .map(|p| p.1 + p.3)
                    .unwrap();
                let total_width: i64 = positions.iter().map(|p| p.3).sum();
                let gap = if positions.len() > 1 {
                    (max_x - min_x - total_width) / (positions.len() as i64 - 1)
                } else {
                    0
                };
                let mut current_x = min_x;
                for pos in &positions {
                    if let Some(node) = canvas.nodes.iter_mut().find(|n| n.id == pos.0) {
                        node.x = current_x;
                        current_x += pos.3 + gap;
                    }
                }
            }
            DistributeDirection::Vertical => {
                positions.sort_by_key(|p| p.2);
                let min_y = positions.first().unwrap().2;
                let max_y = positions
                    .last()
                    .map(|p| p.2 + p.4)
                    .unwrap();
                let total_height: i64 = positions.iter().map(|p| p.4).sum();
                let gap = if positions.len() > 1 {
                    (max_y - min_y - total_height) / (positions.len() as i64 - 1)
                } else {
                    0
                };
                let mut current_y = min_y;
                for pos in &positions {
                    if let Some(node) = canvas.nodes.iter_mut().find(|n| n.id == pos.0) {
                        node.y = current_y;
                        current_y += pos.4 + gap;
                    }
                }
            }
        }
        Ok(())
    }
}

impl Default for CanvasEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_node(id: &str, x: i64, y: i64, w: i64, h: i64) -> CanvasNode {
        CanvasNode {
            id: id.to_string(),
            node_type: NodeType::Note,
            x,
            y,
            width: w,
            height: h,
            content: None,
            color: None,
            file: None,
        }
    }

    fn make_edge(id: &str, from: &str, to: &str) -> CanvasEdge {
        CanvasEdge {
            id: id.to_string(),
            from_node: from.to_string(),
            to_node: to.to_string(),
            label: None,
            color: None,
            from_side: None,
            to_side: None,
        }
    }

    #[test]
    fn test_create_canvas() {
        let mut engine = CanvasEngine::new();
        let id = engine.create_canvas();
        assert!(engine.get_canvas(&id).is_ok());
    }

    #[test]
    fn test_add_and_remove_node() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        let node = make_node("n1", 0, 0, 200, 100);
        engine.add_node(&canvas_id, node).unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.nodes.len(), 1);
        engine.remove_node(&canvas_id, "n1").unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.nodes.len(), 0);
    }

    #[test]
    fn test_move_node() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        let node = make_node("n1", 0, 0, 200, 100);
        engine.add_node(&canvas_id, node).unwrap();
        engine.move_node(&canvas_id, "n1", 100, 200).unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.nodes[0].x, 100);
        assert_eq!(canvas.nodes[0].y, 200);
    }

    #[test]
    fn test_resize_node() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        let node = make_node("n1", 0, 0, 200, 100);
        engine.add_node(&canvas_id, node).unwrap();
        engine.resize_node(&canvas_id, "n1", 400, 300).unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.nodes[0].width, 400);
        assert_eq!(canvas.nodes[0].height, 300);
    }

    #[test]
    fn test_add_and_remove_edge() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        engine.add_node(&canvas_id, make_node("n1", 0, 0, 200, 100)).unwrap();
        engine.add_node(&canvas_id, make_node("n2", 300, 0, 200, 100)).unwrap();
        let edge = make_edge("e1", "n1", "n2");
        engine.add_edge(&canvas_id, edge).unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.edges.len(), 1);
        engine.remove_edge(&canvas_id, "e1").unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.edges.len(), 0);
    }

    #[test]
    fn test_remove_node_removes_edges() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        engine.add_node(&canvas_id, make_node("n1", 0, 0, 200, 100)).unwrap();
        engine.add_node(&canvas_id, make_node("n2", 300, 0, 200, 100)).unwrap();
        engine.add_edge(&canvas_id, make_edge("e1", "n1", "n2")).unwrap();
        engine.remove_node(&canvas_id, "n1").unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.edges.len(), 0);
    }

    #[test]
    fn test_grid_layout() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        for i in 0..5 {
            engine
                .add_node(&canvas_id, make_node(&format!("n{}", i), i as i64 * 100, 0, 200, 100))
                .unwrap();
        }
        engine.auto_layout(&canvas_id, LayoutType::Grid).unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.nodes[0].x, 0);
        assert_eq!(canvas.nodes[0].y, 0);
    }

    #[test]
    fn test_align_nodes() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        engine.add_node(&canvas_id, make_node("n1", 0, 0, 200, 100)).unwrap();
        engine.add_node(&canvas_id, make_node("n2", 100, 50, 200, 100)).unwrap();
        engine
            .align_nodes(&canvas_id, &["n1".to_string(), "n2".to_string()], Alignment::Left)
            .unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        assert_eq!(canvas.nodes[0].x, canvas.nodes[1].x);
    }

    #[test]
    fn test_distribute_nodes() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        engine.add_node(&canvas_id, make_node("n1", 0, 0, 100, 100)).unwrap();
        engine.add_node(&canvas_id, make_node("n2", 50, 0, 100, 100)).unwrap();
        engine.add_node(&canvas_id, make_node("n3", 200, 0, 100, 100)).unwrap();
        engine
            .distribute_nodes(
                &canvas_id,
                &["n1".to_string(), "n2".to_string(), "n3".to_string()],
                DistributeDirection::Horizontal,
            )
            .unwrap();
        let canvas = engine.get_canvas(&canvas_id).unwrap();
        let gap1 = canvas.nodes[1].x - canvas.nodes[0].x - canvas.nodes[0].width;
        let gap2 = canvas.nodes[2].x - canvas.nodes[1].x - canvas.nodes[1].width;
        assert_eq!(gap1, gap2);
    }

    #[test]
    fn test_save_and_load_canvas() {
        let mut engine = CanvasEngine::new();
        let canvas_id = engine.create_canvas();
        engine.add_node(&canvas_id, make_node("n1", 0, 0, 200, 100)).unwrap();
        let dir = std::env::temp_dir().join("devnote_canvas_test");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("test.canvas").to_string_lossy().to_string();
        engine.save_canvas(&canvas_id, &path).unwrap();
        let loaded_id = engine.load_canvas(&path).unwrap();
        let loaded = engine.get_canvas(&loaded_id).unwrap();
        assert_eq!(loaded.nodes.len(), 1);
        assert_eq!(loaded.nodes[0].id, "n1");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
