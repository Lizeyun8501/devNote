use async_trait::async_trait;
use bytes::Bytes;
use cid::Cid;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum IpfsError {
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("IPFS error: {0}")]
    Ipfs(String),
    #[error("CID parse error: {0}")]
    Cid(String),
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("other error: {0}")]
    Other(#[from] anyhow::Error),
}

// IPFS API response types
#[derive(Debug, Deserialize)]
struct IpfsAddResponse {
    #[serde(rename = "Name")]
    name: String,
    #[serde(rename = "Hash")]
    hash: String,
    #[serde(rename = "Size")]
    size: String,
}

#[derive(Debug, Deserialize)]
struct IpfsPinResponse {
    #[serde(rename = "Pins")]
    pins: Vec<String>,
}

// Configuration for IPFS connection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpfsConfig {
    pub api_url: String,        // e.g., "http://localhost:5001"
    pub gateway_url: String,    // e.g., "http://localhost:8080"
    pub timeout_secs: u64,
    pub pin_on_add: bool,
    pub chunk_size: usize,      // for large file chunking
}

impl Default for IpfsConfig {
    fn default() -> Self {
        Self {
            api_url: "http://localhost:5001".to_string(),
            gateway_url: "http://localhost:8080".to_string(),
            timeout_secs: 30,
            pin_on_add: true,
            chunk_size: 256 * 1024, // 256KB chunks
        }
    }
}

/// Content-addressed block stored in IPFS
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpfsBlock {
    pub cid: String,
    pub size: u64,
    pub content_type: String,
    pub pinned: bool,
}

/// IPFS client for block storage operations
pub struct IpfsClient {
    config: IpfsConfig,
    client: reqwest::Client,
    api_token: Option<String>,
}

impl IpfsClient {
    pub fn new(config: IpfsConfig, api_token: Option<String>) -> Result<Self, IpfsError> {
        let mut client_builder = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(config.timeout_secs));

        if let Some(ref token) = api_token {
            if token.is_empty() {
                tracing::warn!("IPFS API token is empty - authentication disabled");
            } else {
                let mut headers = reqwest::header::HeaderMap::new();
                let auth_value = format!("Bearer {}", token);
                let header_value = reqwest::header::HeaderValue::from_str(&auth_value)
                    .map_err(|e| IpfsError::Ipfs(format!("Invalid API token: {}", e)))?;
                headers.insert(reqwest::header::AUTHORIZATION, header_value);
                client_builder = client_builder.default_headers(headers);
            }
        } else {
            tracing::warn!("IPFS API token not set - authentication disabled");
        }

        let client = client_builder.build()?;
        Ok(Self { config, client, api_token })
    }

    /// Check if IPFS node is reachable
    pub async fn ping(&self) -> Result<bool, IpfsError> {
        let resp = self.client
            .post(format!("{}/api/v0/id", self.config.api_url))
            .send()
            .await?;
        Ok(resp.status().is_success())
    }

    /// Add data to IPFS and return CID
    pub async fn add(&self, data: &[u8]) -> Result<String, IpfsError> {
        let form = reqwest::multipart::Form::new()
            .part("file", reqwest::multipart::Part::bytes(data.to_vec())
                .file_name("block.bin"));

        let resp = self.client
            .post(format!("{}/api/v0/add?pin={}", self.config.api_url, self.config.pin_on_add))
            .multipart(form)
            .send()
            .await?;

        let result: IpfsAddResponse = resp.json().await?;
        Ok(result.hash)
    }

    /// Add data with chunking for large files
    pub async fn add_chunked(&self, data: &[u8]) -> Result<String, IpfsError> {
        let mut offset = 0;
        let mut links = Vec::new();

        while offset < data.len() {
            let end = std::cmp::min(offset + self.config.chunk_size, data.len());
            let chunk = &data[offset..end];
            let cid = self.add(chunk).await?;
            links.push(cid);
            offset = end;
        }

        // If single chunk, return it directly
        if links.len() == 1 {
            return Ok(links[0].clone());
        }

        // Create a manifest linking all chunks
        let manifest = serde_json::json!({
            "type": "devnote-ipfs-chunked",
            "chunks": links,
            "total_size": data.len()
        });
        self.add(manifest.to_string().as_bytes()).await
    }

    /// Get data from IPFS by CID
    pub async fn get(&self, cid: &str) -> Result<Bytes, IpfsError> {
        let resp = self.client
            .post(format!("{}/api/v0/cat?arg={}", self.config.api_url, cid))
            .send()
            .await?;

        if !resp.status().is_success() {
            return Err(IpfsError::Ipfs(format!("Failed to get CID {}: {}", cid, resp.status())));
        }

        Ok(resp.bytes().await?)
    }

    /// Get chunked data (reassembles from manifest)
    pub async fn get_chunked(&self, cid: &str) -> Result<Bytes, IpfsError> {
        let data = self.get(cid).await?;

        // Try to parse as chunk manifest
        if let Ok(manifest) = serde_json::from_slice::<serde_json::Value>(&data) {
            if manifest["type"] == "devnote-ipfs-chunked" {
                let mut result = Vec::new();
                let chunks = manifest["chunks"].as_array()
                    .ok_or_else(|| anyhow::anyhow!("manifest missing 'chunks' array"))?;
                for chunk_cid in chunks {
                    let cid_str = chunk_cid.as_str()
                        .ok_or_else(|| anyhow::anyhow!("chunk CID is not a string"))?;
                    let chunk_data = self.get(cid_str).await?;
                    result.extend_from_slice(&chunk_data);
                }
                return Ok(Bytes::from(result));
            }
        }

        Ok(data)
    }

    /// Pin a CID (prevent garbage collection)
    pub async fn pin(&self, cid: &str) -> Result<(), IpfsError> {
        let resp = self.client
            .post(format!("{}/api/v0/pin/add?arg={}", self.config.api_url, cid))
            .send()
            .await?;
        if resp.status().is_success() {
            Ok(())
        } else {
            Err(IpfsError::Ipfs(format!("Failed to pin CID {}", cid)))
        }
    }

    /// Unpin a CID
    pub async fn unpin(&self, cid: &str) -> Result<(), IpfsError> {
        let resp = self.client
            .post(format!("{}/api/v0/pin/rm?arg={}", self.config.api_url, cid))
            .send()
            .await?;
        if resp.status().is_success() {
            Ok(())
        } else {
            Err(IpfsError::Ipfs(format!("Failed to unpin CID {}", cid)))
        }
    }

    /// List all pinned CIDs
    pub async fn list_pins(&self) -> Result<Vec<String>, IpfsError> {
        let resp = self.client
            .post(format!("{}/api/v0/pin/ls?type=recursive", self.config.api_url))
            .send()
            .await?;

        let result: IpfsPinResponse = resp.json().await?;
        Ok(result.pins)
    }

    /// Remove a CID from IPFS (unpin + garbage collect)
    pub async fn remove(&self, cid: &str) -> Result<(), IpfsError> {
        self.unpin(cid).await?;
        // Trigger garbage collection
        let _ = self.client
            .post(format!("{}/api/v0/repo/gc", self.config.api_url))
            .send()
            .await?;
        Ok(())
    }

    /// Check if a CID exists and is accessible
    pub async fn exists(&self, cid: &str) -> Result<bool, IpfsError> {
        match self.get(cid).await {
            Ok(_) => Ok(true),
            Err(IpfsError::Ipfs(_)) => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// Get block info
    pub async fn stat(&self, cid: &str) -> Result<u64, IpfsError> {
        let resp = self.client
            .post(format!("{}/api/v0/block/stat?arg={}", self.config.api_url, cid))
            .send()
            .await?;

        #[derive(Deserialize)]
        struct StatResponse { #[serde(rename = "Size")] size: u64 }
        
        let result: StatResponse = resp.json().await?;
        Ok(result.size)
    }

    /// Compute CID from data without adding to IPFS
    pub fn compute_cid(data: &[u8]) -> String {
        let hash = Sha256::digest(data);
        // CIDv1 with raw codec and sha2-256
        let mh = multihash::Multihash::wrap(0x12, &hash)
            .expect("Multihash::wrap for sha2-256 (32 bytes) never fails");
        let cid = Cid::new_v1(0x55, mh); // 0x55 = raw codec
        cid.to_string()
    }
}

/// Trait for block storage adapters (IPFS or local file)
#[async_trait]
pub trait BlockStorage: Send + Sync {
    async fn store(&self, key: &str, data: &[u8]) -> Result<String, IpfsError>;
    async fn retrieve(&self, cid: &str) -> Result<Bytes, IpfsError>;
    async fn delete(&self, cid: &str) -> Result<(), IpfsError>;
    async fn exists(&self, cid: &str) -> Result<bool, IpfsError>;
}

#[async_trait]
impl BlockStorage for IpfsClient {
    async fn store(&self, _key: &str, data: &[u8]) -> Result<String, IpfsError> {
        self.add(data).await
    }

    async fn retrieve(&self, cid: &str) -> Result<Bytes, IpfsError> {
        self.get(cid).await
    }

    async fn delete(&self, cid: &str) -> Result<(), IpfsError> {
        self.remove(cid).await
    }

    async fn exists(&self, cid: &str) -> Result<bool, IpfsError> {
        self.exists(cid).await
    }
}