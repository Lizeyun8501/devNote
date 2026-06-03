use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureFlag {
    pub key: String,
    pub enabled: bool,
    pub description: String,
    pub updated_at: i64,
}

pub enum FeatureFlagKey {
    GrpcSync,
    P2PSync,
    WasmPlugins,
    IpfsStorage,
    CanvasQt,
    AiAssist,
    CustomFeature(String),
}

impl FeatureFlagKey {
    pub fn as_str(&self) -> &str {
        match self {
            Self::GrpcSync => "grpc_sync",
            Self::P2PSync => "p2p_sync",
            Self::WasmPlugins => "wasm_plugins",
            Self::IpfsStorage => "ipfs_storage",
            Self::CanvasQt => "canvas_qt",
            Self::AiAssist => "ai_assist",
            Self::CustomFeature(s) => s.as_str(),
        }
    }
}
