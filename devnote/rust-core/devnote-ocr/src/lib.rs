//! DevNote OCR 引擎
//! 基于 ocrs（纯 Rust OCR）实现图片文字识别
//!
//! ocrs 是纯 Rust 的 OCR 引擎，无需外部 Tesseract 依赖，适合跨平台打包。
//! 来源: https://github.com/robertknight/ocrs
//!
//! 注意：ocrs 需要下载模型文件（.rten 格式）才能进行实际识别。
//! 沙箱环境无法下载模型，因此本实现保留了完整的接口框架，
//! 实际识别逻辑以 TODO 标注，模型可用时取消注释即可。

use anyhow::{Context, Result};
use image::GrayImage;

/// OCR 识别结果
#[derive(Debug, Clone)]
pub struct OcrResult {
    /// 识别出的全文
    pub text: String,
    /// 按行分割的结果
    pub lines: Vec<String>,
    /// 置信度（0.0-1.0）
    pub confidence: f32,
}

/// OCR 引擎
pub struct OcrEngine {
    // ocrs 引擎实例（懒加载模型）
    // 注意：ocrs 需要下载模型文件，首次使用时加载
    initialized: bool,
}

impl OcrEngine {
    pub fn new() -> Self {
        Self { initialized: false }
    }

    /// 从 base64 编码的图片识别文字
    /// image_base64: base64 编码的图片数据（支持 PNG/JPEG/WebP）
    pub fn recognize_from_base64(&mut self, image_base64: &str) -> Result<OcrResult> {
        // 解码 base64
        let image_bytes = base64_decode(image_base64)?;

        // 解码图片
        let img = image::load_from_memory(&image_bytes)
            .context("Failed to decode image")?;

        // 转为灰度图
        let gray = img.to_luma8();

        // 使用 ocrs 识别
        // 注意：ocrs 需要模型文件，这里实现接口框架
        // 实际使用时需要下载模型并加载
        self.recognize_image(&gray)
    }

    /// 从图片字节识别文字
    pub fn recognize_from_bytes(&mut self, image_bytes: &[u8]) -> Result<OcrResult> {
        let img = image::load_from_memory(image_bytes)
            .context("Failed to decode image")?;
        let gray = img.to_luma8();
        self.recognize_image(&gray)
    }

    /// 核心识别逻辑
    fn recognize_image(&mut self, gray: &GrayImage) -> Result<OcrResult> {
        // TODO: 当 ocrs 模型可用时，使用以下代码进行识别：
        // let img_vec: Vec<u8> = gray.iter().copied().collect();
        // let img_info = ocrs::ImageInfo {
        //     width: gray.width() as usize,
        //     height: gray.height() as usize,
        //     data: &img_vec,
        // };
        // let input = ocrs::OcrInput::from_image(img_info)?;
        // let ocr_engine = ocrs::OcrEngine::new(&model)?;
        // let output = ocr_engine.detect(&input)?;
        //
        // let mut lines = Vec::new();
        // for line in output.lines {
        //     let line_text: String = line.to_string();
        //     lines.push(line_text);
        // }
        // let text = lines.join("\n");

        // 临时实现：返回空结果（模型未加载时）
        // 模型加载成功后应将 self.initialized 置为 true
        let _ = gray; // 模型可用后此处将使用 gray
        Ok(OcrResult {
            text: String::new(),
            lines: Vec::new(),
            confidence: 0.0,
        })
    }

    /// 检查 OCR 引擎是否可用（模型是否已加载）
    pub fn is_available(&self) -> bool {
        self.initialized
    }
}

impl Default for OcrEngine {
    fn default() -> Self {
        Self::new()
    }
}

/// 简单的 base64 解码（不依赖外部 crate）
fn base64_decode(input: &str) -> Result<Vec<u8>> {
    const TABLE: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let input: Vec<u8> = input.bytes().filter(|b| !b.is_ascii_whitespace()).collect();
    let mut output = Vec::with_capacity(input.len() * 3 / 4);

    for chunk in input.chunks(4) {
        if chunk.len() < 2 {
            break;
        }
        let mut vals = [0u8; 4];
        for (i, &b) in chunk.iter().enumerate() {
            if b == b'=' {
                vals[i] = 0;
            } else {
                vals[i] = TABLE
                    .iter()
                    .position(|&t| t == b)
                    .ok_or_else(|| anyhow::anyhow!("invalid base64 character"))? as u8;
            }
        }
        output.push((vals[0] << 2) | (vals[1] >> 4));
        if chunk.len() > 2 && chunk[2] != b'=' {
            output.push((vals[1] << 4) | (vals[2] >> 2));
        }
        if chunk.len() > 3 && chunk[3] != b'=' {
            output.push((vals[2] << 6) | vals[3]);
        }
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_base64_decode_roundtrip() {
        // "Hello" in base64 is "SGVsbG8="
        let decoded = base64_decode("SGVsbG8=").unwrap();
        assert_eq!(decoded, b"Hello");
    }

    #[test]
    fn test_base64_decode_with_padding() {
        // "Hi" -> "SGk="
        let decoded = base64_decode("SGk=").unwrap();
        assert_eq!(decoded, b"Hi");
    }

    #[test]
    fn test_engine_unavailable_without_model() {
        let engine = OcrEngine::new();
        assert!(!engine.is_available());
    }

    #[test]
    fn test_recognize_invalid_base64_returns_error() {
        let mut engine = OcrEngine::new();
        // 包含非法字符 '!' 的输入应返回错误
        let result = engine.recognize_from_base64("!!!!");
        assert!(result.is_err());
    }
}
