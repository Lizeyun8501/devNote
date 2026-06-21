//! DevNote 手写公式识别（数学墨迹）—— P2-9
//!
//! 将手写的数学符号转换为 LaTeX 公式并插入到笔记中。
//!
//! ## 设计
//! - 基于规则的特征匹配识别器（不依赖外部模型，零网络依赖，纯 Rust）
//! - 通过几何特征（长宽比、笔画方向变化、角点数）分类单笔画符号
//! - 通过笔画间相对位置检测分数、上下标、根号、求和、积分等结构
//! - 最终组装为 LaTeX 字符串
//!
//! ## C ABI
//! 暴露 `math_ink_recognize` / `math_ink_free_result` 两个 C 函数，
//! 输入为 JSON 序列化的 `Vec<InkStroke>`，输出为 JSON 序列化的 `MathRecognitionResult`。
//!
//! 借鉴: detexify (https://github.com/kirel/detexify) 的手写 LaTeX 符号识别思路

use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

// ============================================================
// 数据结构
// ============================================================

/// 手写笔触
///
/// 单笔画的轨迹点序列 + 平均压感 + 起笔时间戳。
/// 与 Dart 端 `InkStroke` 模型对齐（仅保留识别所需字段）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InkStroke {
    /// 轨迹点 (x, y)，单位为像素，相对画布左上角
    pub points: Vec<(f32, f32)>,
    /// 平均压感 (0.0 - 1.0)
    pub pressure: f32,
    /// 起笔时间戳（毫秒）
    pub timestamp: u64,
}

/// 符号候选
///
/// 单笔画分类后产生的候选符号及其置信度。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SymbolCandidate {
    /// LaTeX 表示（如 `\alpha`、`+`、`5`）
    pub latex: String,
    /// 置信度 (0.0 - 1.0)
    pub confidence: f32,
    /// 备选符号
    pub alternatives: Vec<String>,
}

/// 数学结构
///
/// 多笔画组合形成的结构（分数、上下标、根号、求和、积分等）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MathStructure {
    /// 结构类型
    pub kind: MathStructureKind,
    /// 参与该结构的笔画索引列表
    pub stroke_indices: Vec<usize>,
    /// 结构产生的 LaTeX 片段
    pub latex: String,
}

/// 数学结构类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MathStructureKind {
    /// 分数 `\frac{a}{b}`
    Fraction,
    /// 上标 `x^{n}`
    Superscript,
    /// 下标 `x_{n}`
    Subscript,
    /// 根号 `\sqrt{x}`
    SquareRoot,
    /// 求和 `\sum_{i=0}^{n}`
    Summation,
    /// 积分 `\int_{a}^{b}`
    Integral,
    /// 括号分组 `\left( ... \right)`
    Group,
}

/// 识别结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MathRecognitionResult {
    /// 主候选 LaTeX 公式（不含 `$`/`$$` 定界符）
    pub latex: String,
    /// 主候选置信度 (0.0 - 1.0)
    pub confidence: f32,
    /// 备选 LaTeX 公式
    pub alternatives: Vec<String>,
}

// ============================================================
// 几何特征工具
// ============================================================

/// 计算笔画的包围盒 (min_x, min_y, max_x, max_y)
fn bounding_box(points: &[(f32, f32)]) -> Option<(f32, f32, f32, f32)> {
    if points.is_empty() {
        return None;
    }
    let (mut min_x, mut min_y) = points[0];
    let (mut max_x, mut max_y) = points[0];
    for &(x, y) in points {
        if x < min_x {
            min_x = x;
        }
        if y < min_y {
            min_y = y;
        }
        if x > max_x {
            max_x = x;
        }
        if y > max_y {
            max_y = y;
        }
    }
    Some((min_x, min_y, max_x, max_y))
}

/// 笔画长宽比 (width / height)，避免除零
fn aspect_ratio(points: &[(f32, f32)]) -> f32 {
    if let Some((min_x, min_y, max_x, max_y)) = bounding_box(points) {
        let w = (max_x - min_x).max(1e-6);
        let h = (max_y - min_y).max(1e-6);
        w / h
    } else {
        1.0
    }
}

/// 笔画总长度
fn stroke_length(points: &[(f32, f32)]) -> f32 {
    let mut total = 0.0;
    for w in points.windows(2) {
        let dx = w[1].0 - w[0].0;
        let dy = w[1].1 - w[0].1;
        total += (dx * dx + dy * dy).sqrt();
    }
    total
}

/// 笔画方向变化次数（粗略的"角点数"估计）
///
/// 通过相邻段向量的夹角变化检测，超过阈值视为一次方向改变。
fn direction_changes(points: &[(f32, f32)]) -> usize {
    if points.len() < 3 {
        return 0;
    }
    let mut changes = 0;
    let mut prev_dx = 0.0f32;
    let mut prev_dy = 0.0f32;
    let mut has_prev = false;
    let threshold = 0.5; // cos 夹角阈值
    for w in points.windows(2) {
        let dx = w[1].0 - w[0].0;
        let dy = w[1].1 - w[0].1;
        let mag = (dx * dx + dy * dy).sqrt();
        if mag < 1e-3 {
            continue;
        }
        if has_prev {
            let prev_mag = (prev_dx * prev_dx + prev_dy * prev_dy).sqrt().max(1e-6);
            let cos_angle = (dx * prev_dx + dy * prev_dy) / (mag * prev_mag);
            if cos_angle < threshold {
                changes += 1;
            }
        }
        prev_dx = dx;
        prev_dy = dy;
        has_prev = true;
    }
    changes
}

/// 笔画是否近似闭合（首尾点距离 < 包围盒对角线的 20%）
fn is_closed(points: &[(f32, f32)]) -> bool {
    if points.len() < 5 {
        return false;
    }
    let (first_x, first_y) = points[0];
    let (last_x, last_y) = points[points.len() - 1];
    let dist = ((first_x - last_x).powi(2) + (first_y - last_y).powi(2)).sqrt();
    if let Some((min_x, min_y, max_x, max_y)) = bounding_box(points) {
        let diag = ((max_x - min_x).powi(2) + (max_y - min_y).powi(2)).sqrt().max(1e-6);
        dist < diag * 0.2
    } else {
        false
    }
}

/// 笔画是否近似水平直线
fn is_horizontal(points: &[(f32, f32)]) -> bool {
    if points.len() < 2 {
        return false;
    }
    let ar = aspect_ratio(points);
    ar > 3.0
}

/// 笔画是否近似垂直直线
fn is_vertical(points: &[(f32, f32)]) -> bool {
    if points.len() < 2 {
        return false;
    }
    let ar = aspect_ratio(points);
    ar < 0.33
}

// ============================================================
// 识别器
// ============================================================

/// 手写公式识别器
pub struct MathInkRecognizer {
    // 预留：未来可加入缓存/模型句柄等
}

impl MathInkRecognizer {
    pub fn new() -> Self {
        Self {}
    }

    /// 识别入口：将一组笔画转换为 LaTeX 公式
    pub fn recognize(&self, strokes: Vec<InkStroke>) -> MathRecognitionResult {
        if strokes.is_empty() {
            return MathRecognitionResult {
                latex: String::new(),
                confidence: 0.0,
                alternatives: Vec::new(),
            };
        }

        // 1. 单笔画分类
        let symbols: Vec<SymbolCandidate> = strokes.iter().map(|s| Self::classify_symbol(s)).collect();

        // 2. 检测多笔画结构
        let structures = Self::detect_structures(&strokes, &symbols);

        // 3. 组装 LaTeX
        let latex = Self::strokes_to_latex(&strokes, &symbols, &structures);

        // 4. 生成备选（取每个符号的备选组合）
        let mut alternatives = Vec::new();
        if !symbols.is_empty() {
            // 简单策略：用每个符号的第一个备选组装
            let alt_latex: String = symbols
                .iter()
                .map(|s| {
                    s.alternatives
                        .first()
                        .cloned()
                        .unwrap_or_else(|| s.latex.clone())
                })
                .collect::<Vec<_>>()
                .join(" ");
            if alt_latex != latex && !alt_latex.is_empty() {
                alternatives.push(alt_latex);
            }
        }

        // 主候选置信度：所有符号置信度的几何平均
        let confidence = if symbols.is_empty() {
            0.0
        } else {
            let product: f32 = symbols.iter().map(|s| s.confidence.max(0.01)).product();
            product.powf(1.0 / symbols.len() as f32)
        };

        MathRecognitionResult {
            latex,
            confidence,
            alternatives,
        }
    }

    /// 通过几何特征分类单笔画符号
    ///
    /// 基于规则匹配：长宽比、闭合性、方向变化数、笔画长度等。
    pub fn classify_symbol(stroke: &InkStroke) -> SymbolCandidate {
        let points = &stroke.points;
        if points.is_empty() {
            return SymbolCandidate {
                latex: String::new(),
                confidence: 0.0,
                alternatives: Vec::new(),
            };
        }

        let ar = aspect_ratio(points);
        let closed = is_closed(points);
        let changes = direction_changes(points);
        let _len = stroke_length(points);
        let horizontal = is_horizontal(points);
        let vertical = is_vertical(points);

        // ── 1. 水平直线类 ──
        if horizontal && changes <= 1 {
            // 短水平线可能是减号或下划线
            if ar > 8.0 {
                return SymbolCandidate {
                    latex: "-".to_string(),
                    confidence: 0.85,
                    alternatives: vec!["\\overline{}".to_string(), "\\text{-}".to_string()],
                };
            }
            return SymbolCandidate {
                latex: "-".to_string(),
                confidence: 0.7,
                alternatives: vec!["\\bar{}".to_string(), "_".to_string()],
            };
        }

        // ── 2. 垂直直线类 ──
        if vertical && changes <= 1 {
            return SymbolCandidate {
                latex: "|".to_string(),
                confidence: 0.7,
                alternatives: vec!["1".to_string(), "I".to_string(), "!".to_string()],
            };
        }

        // ── 3. 闭合图形 ──
        if closed {
            // 圆形/椭圆 → 0 或 o 或 O
            if (0.6..=1.6).contains(&ar) && changes <= 4 {
                return SymbolCandidate {
                    latex: "0".to_string(),
                    confidence: 0.75,
                    alternatives: vec!["o".to_string(), "O".to_string(), "\\circ".to_string()],
                };
            }
            // 高瘦闭合 → 1 或 l
            if ar < 0.6 {
                return SymbolCandidate {
                    latex: "1".to_string(),
                    confidence: 0.6,
                    alternatives: vec!["l".to_string(), "I".to_string()],
                };
            }
            // 宽扁闭合 → D 或 0
            if ar > 1.6 {
                return SymbolCandidate {
                    latex: "D".to_string(),
                    confidence: 0.55,
                    alternatives: vec!["0".to_string(), "\\partial".to_string()],
                };
            }
        }

        // ── 4. 单一方向变化（V 形 / L 形 / 7 形） ──
        if changes == 1 {
            // + 号通常由两笔构成，单笔 V 形可能是 < 或 >
            // 通过首尾点相对位置判断
            let (first_x, _) = points[0];
            let (last_x, _) = points[points.len() - 1];
            if last_x > first_x {
                return SymbolCandidate {
                    latex: "<".to_string(),
                    confidence: 0.55,
                    alternatives: vec!["\\langle".to_string(), "\\leq".to_string()],
                };
            }
            return SymbolCandidate {
                latex: ">".to_string(),
                confidence: 0.55,
                alternatives: vec!["\\rangle".to_string(), "\\geq".to_string()],
            };
        }

        // ── 5. 两次方向变化 ──
        if changes == 2 {
            // 可能是 Z、N、S、2、5 等
            if (0.6..=1.6).contains(&ar) {
                return SymbolCandidate {
                    latex: "2".to_string(),
                    confidence: 0.5,
                    alternatives: vec!["Z".to_string(), "S".to_string(), "5".to_string()],
                };
            }
        }

        // ── 6. 多次方向变化（曲线/复杂符号） ──
        if changes >= 3 {
            // 可能是 3、8、6、9、α、π 等
            if closed && (0.6..=1.6).contains(&ar) {
                return SymbolCandidate {
                    latex: "8".to_string(),
                    confidence: 0.5,
                    alternatives: vec!["\\infty".to_string(), "B".to_string()],
                };
            }
            // 长曲线可能是 ∫
            if vertical {
                return SymbolCandidate {
                    latex: "\\int".to_string(),
                    confidence: 0.55,
                    alternatives: vec!["f".to_string(), "J".to_string()],
                };
            }
            // 横向波浪线可能是 ≈
            if horizontal {
                return SymbolCandidate {
                    latex: "\\approx".to_string(),
                    confidence: 0.5,
                    alternatives: vec!["\\sim".to_string(), "\\simeq".to_string()],
                };
            }
            // 默认归为 α 或 a
            return SymbolCandidate {
                latex: "\\alpha".to_string(),
                confidence: 0.4,
                alternatives: vec!["a".to_string(), "2".to_string()],
            };
        }

        // ── 7. 默认：根据长宽比猜测数字 ──
        if ar > 1.0 {
            return SymbolCandidate {
                latex: "7".to_string(),
                confidence: 0.35,
                alternatives: vec!["T".to_string(), "-".to_string()],
            };
        }
        SymbolCandidate {
            latex: "1".to_string(),
            confidence: 0.3,
            alternatives: vec!["l".to_string(), "|".to_string()],
        }
    }

    /// 检测分数、上下标、根号、求和、积分等结构
    pub fn detect_structures(strokes: &[InkStroke], symbols: &[SymbolCandidate]) -> Vec<MathStructure> {
        let mut structures = Vec::new();
        if strokes.is_empty() {
            return structures;
        }

        // 收集每个笔画的包围盒中心
        let centers: Vec<(f32, f32)> = strokes
            .iter()
            .filter_map(|s| bounding_box(&s.points))
            .map(|(min_x, min_y, max_x, max_y)| ((min_x + max_x) * 0.5, (min_y + max_y) * 0.5))
            .collect();

        // ── 检测水平横线作为分数线 ──
        for (i, stroke) in strokes.iter().enumerate() {
            if is_horizontal(&stroke.points) && stroke.points.len() >= 2 {
                // 查找线上方和线下方的笔画
                // 修复(P1): 替换 .unwrap() 为安全匹配，避免空笔画时 panic
                let bb = match bounding_box(&stroke.points) {
                    Some(b) => b,
                    None => continue,
                };
                let line_y = (bb.1 + bb.3) * 0.5;
                let mut above = Vec::new();
                let mut below = Vec::new();
                for (j, c) in centers.iter().enumerate() {
                    if j == i {
                        continue;
                    }
                    if c.1 < line_y - 5.0 {
                        above.push(j);
                    } else if c.1 > line_y + 5.0 {
                        below.push(j);
                    }
                }
                if !above.is_empty() && !below.is_empty() {
                    let mut indices = vec![i];
                    indices.extend(above.iter());
                    indices.extend(below.iter());
                    structures.push(MathStructure {
                        kind: MathStructureKind::Fraction,
                        stroke_indices: indices,
                        latex: format!(
                            "\\frac{{{}}}{{{}}}",
                            above
                                .iter()
                                .filter_map(|&k| symbols.get(k).map(|s| s.latex.clone()))
                                .collect::<Vec<_>>()
                                .join(""),
                            below
                                .iter()
                                .filter_map(|&k| symbols.get(k).map(|s| s.latex.clone()))
                                .collect::<Vec<_>>()
                                .join("")
                        ),
                    });
                }
            }
        }

        // ── 检测上下标：通过相对高度位置 ──
        if centers.len() >= 2 {
            // 计算平均 y 作为基线
            let avg_y: f32 = centers.iter().map(|c| c.1).sum::<f32>() / centers.len() as f32;
            let mut baseline_strokes: Vec<usize> = Vec::new();
            let mut superscript_strokes: Vec<usize> = Vec::new();
            let mut subscript_strokes: Vec<usize> = Vec::new();
            for (i, c) in centers.iter().enumerate() {
                // 仅对非闭合小符号判断上下标
                if c.1 < avg_y - 15.0 {
                    superscript_strokes.push(i);
                } else if c.1 > avg_y + 15.0 {
                    subscript_strokes.push(i);
                } else {
                    baseline_strokes.push(i);
                }
            }
            if !superscript_strokes.is_empty() && !baseline_strokes.is_empty() {
                let latex = format!(
                    "{}^{{{}}}",
                    baseline_strokes
                        .iter()
                        .filter_map(|&k| symbols.get(k).map(|s| s.latex.clone()))
                        .collect::<Vec<_>>()
                        .join(""),
                    superscript_strokes
                        .iter()
                        .filter_map(|&k| symbols.get(k).map(|s| s.latex.clone()))
                        .collect::<Vec<_>>()
                        .join("")
                );
                structures.push(MathStructure {
                    kind: MathStructureKind::Superscript,
                    stroke_indices: vec![],
                    latex,
                });
            }
            if !subscript_strokes.is_empty() && !baseline_strokes.is_empty() {
                let latex = format!(
                    "{}_{{{}}}",
                    baseline_strokes
                        .iter()
                        .filter_map(|&k| symbols.get(k).map(|s| s.latex.clone()))
                        .collect::<Vec<_>>()
                        .join(""),
                    subscript_strokes
                        .iter()
                        .filter_map(|&k| symbols.get(k).map(|s| s.latex.clone()))
                        .collect::<Vec<_>>()
                        .join("")
                );
                structures.push(MathStructure {
                    kind: MathStructureKind::Subscript,
                    stroke_indices: vec![],
                    latex,
                });
            }
        }

        // ── 检测根号、求和、积分符号 ──
        for (i, sym) in symbols.iter().enumerate() {
            match sym.latex.as_str() {
                "\\sqrt" | "\\sqrt{}" => {
                    structures.push(MathStructure {
                        kind: MathStructureKind::SquareRoot,
                        stroke_indices: vec![i],
                        latex: "\\sqrt{}".to_string(),
                    });
                }
                "\\sum" => {
                    structures.push(MathStructure {
                        kind: MathStructureKind::Summation,
                        stroke_indices: vec![i],
                        latex: "\\sum".to_string(),
                    });
                }
                "\\int" => {
                    structures.push(MathStructure {
                        kind: MathStructureKind::Integral,
                        stroke_indices: vec![i],
                        latex: "\\int".to_string(),
                    });
                }
                _ => {}
            }
        }

        structures
    }

    /// 将识别结果组装为 LaTeX
    pub fn strokes_to_latex(
        strokes: &[InkStroke],
        symbols: &[SymbolCandidate],
        structures: &[MathStructure],
    ) -> String {
        // 若检测到分数结构，优先使用其 LaTeX
        for s in structures {
            if s.kind == MathStructureKind::Fraction {
                return s.latex.clone();
            }
        }

        // 若检测到上下标结构，使用其 LaTeX
        for s in structures {
            if matches!(s.kind, MathStructureKind::Superscript | MathStructureKind::Subscript) {
                return s.latex.clone();
            }
        }

        // 否则按笔画顺序拼接符号
        if symbols.is_empty() {
            return String::new();
        }

        // 按笔画 x 坐标排序后拼接（左到右）
        let mut indexed: Vec<(usize, f32)> = strokes
            .iter()
            .enumerate()
            .filter_map(|(i, s)| bounding_box(&s.points).map(|bb| (i, bb.0)))
            .collect();
        indexed.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));

        let parts: Vec<String> = indexed
            .iter()
            .filter_map(|(i, _)| symbols.get(*i).map(|s| s.latex.clone()))
            .collect();

        parts.join(" ")
    }
}

impl Default for MathInkRecognizer {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================
// C ABI 接口
// ============================================================

/// 识别手写公式
///
/// 输入: JSON 序列化的 `Vec<InkStroke>` 字符串（C 字符串，UTF-8）
/// 输出: JSON 序列化的 `MathRecognitionResult` 字符串（堆分配，调用方需用 `math_ink_free_result` 释放）
///
/// # Safety
/// `strokes_json` 必须是有效的 C 字符串指针（以 null 结尾的 UTF-8 数据）。
#[no_mangle]
pub extern "C" fn math_ink_recognize(strokes_json: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if strokes_json.is_null() {
            let err = MathRecognitionResult {
                latex: String::new(),
                confidence: 0.0,
                alternatives: vec!["error: null input".to_string()],
            };
            let json = serde_json::to_string(&err).unwrap_or_default();
            return CString::new(json).unwrap_or_default().into_raw();
        }
        // SAFETY: caller guarantees strokes_json is a valid null-terminated UTF-8 C string.
        let cstr = unsafe { CStr::from_ptr(strokes_json) };
        let json_str = match cstr.to_str() {
            Ok(s) => s,
            Err(_) => {
                let err = MathRecognitionResult {
                    latex: String::new(),
                    confidence: 0.0,
                    alternatives: vec!["error: invalid utf-8".to_string()],
                };
                let json = serde_json::to_string(&err).unwrap_or_default();
                return CString::new(json).unwrap_or_default().into_raw();
            }
        };
        let strokes: Vec<InkStroke> = match serde_json::from_str(json_str) {
            Ok(v) => v,
            Err(e) => {
                let err = MathRecognitionResult {
                    latex: String::new(),
                    confidence: 0.0,
                    alternatives: vec![format!("error: parse failed: {}", e)],
                };
                let json = serde_json::to_string(&err).unwrap_or_default();
                return CString::new(json).unwrap_or_default().into_raw();
            }
        };
        let recognizer = MathInkRecognizer::new();
        let result = recognizer.recognize(strokes);
        let json = serde_json::to_string(&result).unwrap_or_default();
        CString::new(json).unwrap_or_default().into_raw()
    }));
    match result {
        Ok(ptr) => ptr,
        Err(_) => {
            let err = MathRecognitionResult {
                latex: String::new(),
                confidence: 0.0,
                alternatives: vec!["error: rust panic".to_string()],
            };
            let json = serde_json::to_string(&err).unwrap_or_default();
            CString::new(json).unwrap_or_default().into_raw()
        }
    }
}

/// 释放 `math_ink_recognize` 返回的字符串
///
/// # Safety
/// `ptr` 必须是 `math_ink_recognize` 返回的指针，且只能释放一次。
#[no_mangle]
pub extern "C" fn math_ink_free_result(ptr: *mut c_char) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if !ptr.is_null() {
            // SAFETY: ptr was created via CString::into_raw() in math_ink_recognize.
            let _ = unsafe { CString::from_raw(ptr) };
        }
    }));
    if result.is_err() {
        // 释放函数中无法记录日志，静默忽略
    }
}

// ============================================================
// 单元测试
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn make_horizontal_line() -> InkStroke {
        InkStroke {
            points: vec![(0.0, 50.0), (10.0, 50.0), (20.0, 50.0), (30.0, 50.0), (40.0, 50.0)],
            pressure: 0.5,
            timestamp: 0,
        }
    }

    fn make_circle() -> InkStroke {
        // 粗略的圆: 8 个点环绕中心 (50, 50)，半径 20
        let mut pts = Vec::new();
        for i in 0..=16 {
            let angle = (i as f32) * std::f32::consts::PI / 8.0;
            pts.push((50.0 + 20.0 * angle.cos(), 50.0 + 20.0 * angle.sin()));
        }
        InkStroke {
            points: pts,
            pressure: 0.5,
            timestamp: 0,
        }
    }

    #[test]
    fn test_recognize_empty_strokes() {
        let recognizer = MathInkRecognizer::new();
        let result = recognizer.recognize(Vec::new());
        assert!(result.latex.is_empty());
        assert_eq!(result.confidence, 0.0);
    }

    #[test]
    fn test_classify_horizontal_line_as_minus() {
        let stroke = make_horizontal_line();
        let sym = MathInkRecognizer::classify_symbol(&stroke);
        assert_eq!(sym.latex, "-");
        assert!(!sym.alternatives.is_empty());
    }

    #[test]
    fn test_classify_circle_as_zero() {
        let stroke = make_circle();
        let sym = MathInkRecognizer::classify_symbol(&stroke);
        // 圆形应识别为 0 或 o/O 之一
        assert!(sym.latex == "0" || sym.latex == "o" || sym.latex == "O");
    }

    #[test]
    fn test_bounding_box() {
        let pts = vec![(0.0, 0.0), (10.0, 5.0), (5.0, 20.0)];
        let bb = bounding_box(&pts).unwrap();
        assert_eq!(bb, (0.0, 0.0, 10.0, 20.0));
    }

    #[test]
    fn test_aspect_ratio() {
        let pts = vec![(0.0, 0.0), (10.0, 0.0)];
        let ar = aspect_ratio(&pts);
        assert!(ar > 1.0);
    }

    #[test]
    fn test_is_closed_circle() {
        let stroke = make_circle();
        assert!(is_closed(&stroke.points));
    }

    #[test]
    fn test_is_horizontal_line() {
        let stroke = make_horizontal_line();
        assert!(is_horizontal(&stroke.points));
    }

    #[test]
    fn test_c_abi_null_input() {
        let ptr = math_ink_recognize(std::ptr::null());
        // SAFETY: ptr was returned by math_ink_recognize, valid to read.
        let cstr = unsafe { CStr::from_ptr(ptr) };
        let json = cstr.to_str().unwrap();
        assert!(json.contains("error"));
        math_ink_free_result(ptr);
    }

    #[test]
    fn test_c_abi_valid_input() {
        let strokes = vec![make_horizontal_line()];
        let json = serde_json::to_string(&strokes).unwrap();
        let cstr = CString::new(json).unwrap();
        let ptr = math_ink_recognize(cstr.as_ptr());
        // SAFETY: ptr was returned by math_ink_recognize.
        let result_cstr = unsafe { CStr::from_ptr(ptr) };
        let result_json = result_cstr.to_str().unwrap();
        assert!(result_json.contains("latex"));
        math_ink_free_result(ptr);
    }
}
