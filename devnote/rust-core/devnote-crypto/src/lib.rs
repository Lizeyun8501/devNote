//! 加密引擎 —— 借鉴 Notesnook 的 XChaCha20-Poly1305 算法和 Argon2id 密钥派生
//! 密钥恢复采用 BIP-39 助记词方案（借鉴 Bitcoin 生态标准）
//!
//! 借鉴 Notesnook 的加密方案
//! 来源: https://github.com/streetwriters/notesnook
//! 借鉴内容: XChaCha20-Poly1305 AEAD 加密 + Argon2id 密钥派生算法组合
//!
//! 借鉴 Bitcoin 生态的 BIP-39 标准
//! 来源: https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
//! 借鉴内容: 24 词助记词生成与恢复，用于用户密钥的备份与恢复

use devnote_observe::{info, instrument, warn};
use thiserror::Error;
use argon2::{Argon2, Algorithm, Version, Params};
use chacha20poly1305::{XChaCha20Poly1305, Key, XNonce, KeyInit};
use chacha20poly1305::aead::Aead;
use rand_core::OsRng;
use rand_core::RngCore;

#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("encryption failed: {0}")]
    EncryptionFailed(String),
    #[error("decryption failed: {0}")]
    DecryptionFailed(String),
    #[error("key derivation failed: {0}")]
    KeyDerivationFailed(String),
    #[error("key derivation error: {0}")]
    KeyDerivationError(String),
    #[error("invalid key")]
    InvalidKey,
    #[error("authentication failed")]
    AuthenticationFailed,
}

#[derive(Debug, Clone)]
pub struct EncryptedData {
    pub nonce: Vec<u8>,
    pub ciphertext: Vec<u8>,
    pub tag: Vec<u8>,
}

impl EncryptedData {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut result = Vec::with_capacity(self.nonce.len() + self.ciphertext.len() + self.tag.len());
        result.extend_from_slice(&self.nonce);
        result.extend_from_slice(&self.ciphertext);
        result.extend_from_slice(&self.tag);
        result
    }

    pub fn from_bytes(data: &[u8]) -> Result<Self, CryptoError> {
        let nonce_len = 24;
        let tag_len = 16;
        if data.len() < nonce_len + tag_len {
            return Err(CryptoError::DecryptionFailed("invalid encrypted data length".to_string()));
        }
        let ciphertext_len = data.len() - nonce_len - tag_len;
        Ok(Self {
            nonce: data[..nonce_len].to_vec(),
            ciphertext: data[nonce_len..nonce_len + ciphertext_len].to_vec(),
            tag: data[nonce_len + ciphertext_len..].to_vec(),
        })
    }
}

#[derive(Debug, Clone)]
pub struct CryptoConfig {
    pub algorithm: String,
    pub key_derivation: String,
    /// Argon2id 时间成本 (iteration count) — RFC 9106 推荐 t=3
    pub iterations: u32,
    /// Argon2id 内存成本 (KiB) — RFC 9106 推荐 m=65536 (64 MiB)
    pub memory_kib: u32,
    /// Argon2id 并行度 (lanes) — RFC 9106 推荐 p=4
    pub parallelism: u32,
}

impl Default for CryptoConfig {
    fn default() -> Self {
        Self {
            algorithm: "XChaCha20-Poly1305".to_string(),
            key_derivation: "Argon2id".to_string(),
            iterations: 3,
            memory_kib: 65536,
            parallelism: 4,
        }
    }
}

impl CryptoConfig {
    /// RFC 9106 标准参数 — 平衡性能与安全
    pub fn standard() -> Self {
        Self::default()
    }

    /// 高安全等级 — 适合服务器端或敏感场景
    pub fn high_strength() -> Self {
        Self {
            algorithm: "XChaCha20-Poly1305".to_string(),
            key_derivation: "Argon2id".to_string(),
            iterations: 6,
            memory_kib: 131072, // 128 MiB
            parallelism: 8,
        }
    }

    /// 低资源模式 — 适合移动端或嵌入式
    pub fn low_resource() -> Self {
        Self {
            algorithm: "XChaCha20-Poly1305".to_string(),
            key_derivation: "Argon2id".to_string(),
            iterations: 2,
            memory_kib: 19456, // 19 MiB — Argon2id 最低安全值
            parallelism: 1,
        }
    }

    /// 从环境变量加载(允许运行时覆盖)
    /// 借鉴 1Password 的 Argon2id 强度分级
    /// 来源: https://blog.1password.com/1password-argon2id-implementation/
    pub fn from_env_or_default() -> Self {
        let mut cfg = Self::default();
        if let Ok(v) = std::env::var("DEVNOTE_ARGON2_ITERATIONS") {
            if let Ok(n) = v.parse() { cfg.iterations = n; }
        }
        if let Ok(v) = std::env::var("DEVNOTE_ARGON2_MEMORY_KIB") {
            if let Ok(n) = v.parse() { cfg.memory_kib = n; }
        }
        if let Ok(v) = std::env::var("DEVNOTE_ARGON2_PARALLELISM") {
            if let Ok(n) = v.parse() { cfg.parallelism = n; }
        }
        cfg
    }
}

pub trait CryptoEngine: Send + Sync {
    fn encrypt(&self, plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError>;
    fn decrypt(&self, ciphertext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError>;
    fn derive_key(&self, password: &str, salt: &[u8]) -> Result<Vec<u8>, CryptoError>;
    fn generate_salt(&self) -> Vec<u8>;
}

pub struct DefaultCryptoEngine {
    config: CryptoConfig,
}

impl DefaultCryptoEngine {
    pub fn new(config: CryptoConfig) -> Self {
        Self { config }
    }

    pub fn derive_key_with_params(&self, password: &str, salt: &[u8], output_len: usize) -> Result<Vec<u8>, CryptoError> {
        let params = Params::new(self.config.memory_kib, self.config.iterations, self.config.parallelism, Some(output_len))
            .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;
        let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
        let mut output = vec![0u8; output_len];
        argon2
            .hash_password_into(password.as_bytes(), salt, &mut output)
            .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;
        Ok(output)
    }

    pub fn hash_password(&self, password: &str, salt: &[u8]) -> Result<Vec<u8>, CryptoError> {
        self.derive_key_with_params(password, salt, 64)
    }

    pub fn verify_password(&self, password: &str, salt: &[u8], hash: &[u8]) -> Result<bool, CryptoError> {
        let computed = self.hash_password(password, salt)?;
        Ok(computed == hash)
    }

    /// Generate a 24-word BIP-39 mnemonic for key recovery
    pub fn generate_recovery_phrase() -> Result<String, CryptoError> {
        let mut entropy = [0u8; 32]; // 32 bytes = 256 bits = 24 words
        OsRng.fill_bytes(&mut entropy);
        let mnemonic = bip39::Mnemonic::from_entropy(&entropy)
            .map_err(|e| CryptoError::KeyDerivationError(e.to_string()))?;
        Ok(mnemonic.to_string())
    }

    /// Derive master key from recovery phrase
    pub fn key_from_recovery_phrase(phrase: &str, salt: &[u8]) -> Result<[u8; 32], CryptoError> {
        let mnemonic = bip39::Mnemonic::parse_normalized(phrase)
            .map_err(|e| CryptoError::KeyDerivationError(format!("Invalid recovery phrase: {}", e)))?;
        let seed = mnemonic.to_seed("");
        // Derive key using Argon2id from seed
        let params = argon2::Params::new(8192, 2, 1, Some(32))
            .map_err(|e| CryptoError::KeyDerivationError(e.to_string()))?;
        let mut key = [0u8; 32];
        argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params)
            .hash_password_into(&seed, salt, &mut key)
            .map_err(|e| CryptoError::KeyDerivationError(e.to_string()))?;
        Ok(key)
    }

    /// Verify a recovery phrase matches the stored key
    pub fn verify_recovery_phrase(phrase: &str, salt: &[u8], expected_key: &[u8; 32]) -> Result<bool, CryptoError> {
        let derived = Self::key_from_recovery_phrase(phrase, salt)?;
        Ok(derived == *expected_key)
    }

    pub fn encrypt_structured(&self, plaintext: &[u8], key: &[u8]) -> Result<EncryptedData, CryptoError> {
        let cipher = XChaCha20Poly1305::new(Key::from_slice(key));
        let mut nonce_bytes = [0u8; 24];
        OsRng.fill_bytes(&mut nonce_bytes);
        let nonce = XNonce::from_slice(&nonce_bytes);
        let encrypted = cipher
            .encrypt(nonce, plaintext)
            .map_err(|e| CryptoError::EncryptionFailed(e.to_string()))?;
        let ciphertext_len = encrypted.len() - 16;
        Ok(EncryptedData {
            nonce: nonce_bytes.to_vec(),
            ciphertext: encrypted[..ciphertext_len].to_vec(),
            tag: encrypted[ciphertext_len..].to_vec(),
        })
    }

    pub fn decrypt_structured(&self, data: &EncryptedData, key: &[u8]) -> Result<Vec<u8>, CryptoError> {
        let cipher = XChaCha20Poly1305::new(Key::from_slice(key));
        let nonce = XNonce::from_slice(&data.nonce);
        let mut combined = data.ciphertext.clone();
        combined.extend_from_slice(&data.tag);
        cipher
            .decrypt(nonce, combined.as_slice())
            .map_err(|_| CryptoError::AuthenticationFailed)
    }
}

impl Default for DefaultCryptoEngine {
    fn default() -> Self {
        Self::new(CryptoConfig::default())
    }
}

impl CryptoEngine for DefaultCryptoEngine {
    #[instrument(skip(self, plaintext, key))]
    fn encrypt(&self, plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError> {
        info!("encrypt: plaintext_len={}", plaintext.len());
        let result = self.encrypt_structured(plaintext, key)?;
        Ok(result.to_bytes())
    }

    #[instrument(skip(self, ciphertext, key))]
    fn decrypt(&self, ciphertext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError> {
        info!("decrypt: ciphertext_len={}", ciphertext.len());
        let encrypted_data = EncryptedData::from_bytes(ciphertext)?;
        self.decrypt_structured(&encrypted_data, key)
    }

    fn derive_key(&self, password: &str, salt: &[u8]) -> Result<Vec<u8>, CryptoError> {
        self.derive_key_with_params(password, salt, 32)
    }

    fn generate_salt(&self) -> Vec<u8> {
        let mut salt = vec![0u8; 32];
        OsRng.fill_bytes(&mut salt);
        salt
    }
}
