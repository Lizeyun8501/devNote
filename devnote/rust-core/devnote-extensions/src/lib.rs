// devnote-extensions —— 合并的扩展功能集合
//
// 将原先过度拆分的 6 个 crate（devnote-math-ink、devnote-ocr、devnote-ipfs、
// devnote-canvas、devnote-workflow、devnote-format）合并为单一 crate，
// 通过 feature flag 控制各模块编译，缩短 workspace 编译时间、降低版本协调成本。
//
// 使用方式：在 Cargo.toml 中按需启用 feature
//   devnote-extensions = { workspace = true, features = ["math-ink", "ocr", "canvas", "format"] }

#![cfg_attr(docsrs, feature(doc_cfg))]

#[cfg(feature = "math-ink")]
pub mod math_ink;

#[cfg(feature = "ocr")]
pub mod ocr;

#[cfg(feature = "ipfs")]
pub mod ipfs;

#[cfg(feature = "canvas")]
pub mod canvas;

#[cfg(feature = "workflow")]
pub mod workflow;

#[cfg(feature = "format")]
pub mod format;
