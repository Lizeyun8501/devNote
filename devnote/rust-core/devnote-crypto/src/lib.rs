//! 加密引擎模块
//! 
//! 借鉴: Notesnook 加密引擎 (https://github.com/streetwriters/notesnook)
//! - XChaCha20-Poly1305 对称加密算法
//! - Argon2id 密钥派生函数
//! - 零知识架构设计
//! 
//! 复用: rustcrypto 加密算法库 (https://github.com/RustCrypto)
//! - chacha20poly1305 crate
//! - argon2 crate
//! - rand crate (安全随机数)

use devnote_observe::{info, instrument, warn};
use thiserror::Error;
use argon2::{Argon2, Algorithm, Version, Params};
use chacha20poly1305::{XChaCha20Poly1305, Key, XNonce, KeyInit};
use chacha20poly1305::aead::Aead;
use rand_core::OsRng;
use rand_core::RngCore;
use base64::Engine;

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
    #[error("invalid input: {0}")]
    InvalidInput(String),
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

// ── Vault 保险库加密 API ──────────────────────────────────────────────
// P1-7: Vault 保险库（敏感笔记二次加密）
// 对标 Notesnook 的 Vault 功能：使用独立密码对敏感笔记进行二次加密
// 采用 Argon2id 密钥派生 + XChaCha20-Poly1305 加密（与主加密方案一致）

/// Vault 加密结果
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct VaultEncryptedData {
    /// 加密的密文（base64）
    pub ciphertext: String,
    /// 随机盐（base64，用于 Argon2id 密钥派生）
    pub salt: String,
    /// 随机 nonce（base64）
    pub nonce: String,
    /// Argon2id 参数
    pub memory_cost: u32,
    pub time_cost: u32,
    pub parallelism: u32,
}

/// Vault 加密：使用用户密码对明文进行加密
/// 采用 Argon2id 密钥派生 + XChaCha20-Poly1305 加密
pub fn vault_encrypt(password: &str, plaintext: &str) -> Result<VaultEncryptedData, CryptoError> {
    // 生成随机盐（16 字节）
    let mut salt = [0u8; 16];
    OsRng.fill_bytes(&mut salt);

    // Argon2id 参数 —— RFC 9106 推荐值
    let memory_cost = 65536;  // 64 MB
    let time_cost = 3;
    let parallelism = 4;

    // 派生密钥
    let params = Params::new(memory_cost, time_cost, parallelism, Some(32))
        .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut key_bytes = [0u8; 32];
    argon2
        .hash_password_into(password.as_bytes(), &salt, &mut key_bytes)
        .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;

    // 生成随机 nonce（24 字节，XChaCha20）
    let mut nonce_bytes = [0u8; 24];
    OsRng.fill_bytes(&mut nonce_bytes);

    // 加密
    let cipher = XChaCha20Poly1305::new(Key::from_slice(&key_bytes));
    let nonce = XNonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, plaintext.as_bytes())
        .map_err(|e| CryptoError::EncryptionFailed(e.to_string()))?;

    let b64 = base64::engine::general_purpose::STANDARD;
    Ok(VaultEncryptedData {
        ciphertext: b64.encode(&ciphertext),
        salt: b64.encode(&salt),
        nonce: b64.encode(&nonce_bytes),
        memory_cost,
        time_cost,
        parallelism,
    })
}

/// Vault 解密：使用用户密码对密文进行解密
pub fn vault_decrypt(password: &str, encrypted: &VaultEncryptedData) -> Result<String, CryptoError> {
    let b64 = base64::engine::general_purpose::STANDARD;
    let salt = b64
        .decode(&encrypted.salt)
        .map_err(|e| CryptoError::InvalidInput(e.to_string()))?;
    let nonce_bytes = b64
        .decode(&encrypted.nonce)
        .map_err(|e| CryptoError::InvalidInput(e.to_string()))?;
    let ciphertext = b64
        .decode(&encrypted.ciphertext)
        .map_err(|e| CryptoError::InvalidInput(e.to_string()))?;

    // 派生密钥
    let params = Params::new(
        encrypted.memory_cost,
        encrypted.time_cost,
        encrypted.parallelism,
        Some(32),
    )
    .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut key_bytes = [0u8; 32];
    argon2
        .hash_password_into(password.as_bytes(), &salt, &mut key_bytes)
        .map_err(|e| CryptoError::KeyDerivationFailed(e.to_string()))?;

    // 解密
    let cipher = XChaCha20Poly1305::new(Key::from_slice(&key_bytes));
    let nonce = XNonce::from_slice(&nonce_bytes);
    let plaintext = cipher
        .decrypt(nonce, ciphertext.as_ref())
        .map_err(|e| CryptoError::DecryptionFailed(e.to_string()))?;

    String::from_utf8(plaintext)
        .map_err(|e| CryptoError::InvalidInput(e.to_string()))
}

/// 验证 Vault 密码（通过尝试解密一个测试向量）
pub fn vault_verify_password(password: &str, encrypted: &VaultEncryptedData) -> bool {
    vault_decrypt(password, encrypted).is_ok()
}

#[cfg(test)]
// 测试约定：测试中使用 `.unwrap()` 是 Rust 惯用写法，由 `#[cfg(test)]` 门控，
// 不会编译进生产二进制。生产代码使用 `?` 运算符传播错误。
mod tests {
    use super::*;

    /// 测试用极低参数配置，加速 Argon2id 计算（仅用于单元测试，不可用于生产）
    fn test_config() -> CryptoConfig {
        CryptoConfig {
            algorithm: "XChaCha20-Poly1305".to_string(),
            key_derivation: "Argon2id".to_string(),
            iterations: 1,
            memory_kib: 8,
            parallelism: 1,
        }
    }

    // ==================== EncryptedData 序列化测试 ====================

    #[test]
    fn test_encrypted_data_round_trip() {
        let data = EncryptedData {
            nonce: vec![0u8; 24],
            ciphertext: vec![1u8, 2, 3, 4, 5],
            tag: vec![0u8; 16],
        };
        let bytes = data.to_bytes();
        let restored = EncryptedData::from_bytes(&bytes).unwrap();
        assert_eq!(restored.nonce, data.nonce);
        assert_eq!(restored.ciphertext, data.ciphertext);
        assert_eq!(restored.tag, data.tag);
    }

    #[test]
    fn test_encrypted_data_from_bytes_too_short() {
        // 数据长度不足 nonce(24) + tag(16) = 40 字节，应返回错误
        let short_data = vec![0u8; 10];
        let result = EncryptedData::from_bytes(&short_data);
        assert!(result.is_err());
    }

    #[test]
    fn test_encrypted_data_from_bytes_empty_ciphertext() {
        // ciphertext 长度为 0，仅包含 nonce 和 tag
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&[0u8; 24]); // nonce
        bytes.extend_from_slice(&[0u8; 16]); // tag
        let result = EncryptedData::from_bytes(&bytes).unwrap();
        assert_eq!(result.nonce.len(), 24);
        assert!(result.ciphertext.is_empty());
        assert_eq!(result.tag.len(), 16);
    }

    // ==================== CryptoConfig 预设测试 ====================

    #[test]
    fn test_config_standard() {
        let cfg = CryptoConfig::standard();
        assert_eq!(cfg.algorithm, "XChaCha20-Poly1305");
        assert_eq!(cfg.key_derivation, "Argon2id");
        assert_eq!(cfg.iterations, 3);
        assert_eq!(cfg.memory_kib, 65536);
        assert_eq!(cfg.parallelism, 4);
    }

    #[test]
    fn test_config_high_strength() {
        let cfg = CryptoConfig::high_strength();
        assert_eq!(cfg.iterations, 6);
        assert_eq!(cfg.memory_kib, 131072);
        assert_eq!(cfg.parallelism, 8);
        // 高安全等级参数应大于等于标准参数
        assert!(cfg.iterations >= CryptoConfig::standard().iterations);
        assert!(cfg.memory_kib >= CryptoConfig::standard().memory_kib);
    }

    #[test]
    fn test_config_low_resource() {
        let cfg = CryptoConfig::low_resource();
        assert_eq!(cfg.iterations, 2);
        assert_eq!(cfg.memory_kib, 19456);
        assert_eq!(cfg.parallelism, 1);
        // 低资源模式参数应小于等于标准参数
        assert!(cfg.iterations <= CryptoConfig::standard().iterations);
        assert!(cfg.memory_kib <= CryptoConfig::standard().memory_kib);
    }

    #[test]
    fn test_config_default_matches_standard() {
        // default 与 standard 应返回相同参数
        let default_cfg = CryptoConfig::default();
        let standard_cfg = CryptoConfig::standard();
        assert_eq!(default_cfg.iterations, standard_cfg.iterations);
        assert_eq!(default_cfg.memory_kib, standard_cfg.memory_kib);
        assert_eq!(default_cfg.parallelism, standard_cfg.parallelism);
    }

    // ==================== 密钥派生测试 ====================

    #[test]
    fn test_derive_key_deterministic() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = vec![0xAAu8; 32];
        let key1 = engine.derive_key("password123", &salt).unwrap();
        let key2 = engine.derive_key("password123", &salt).unwrap();
        // 相同密码和盐值应派生出相同密钥
        assert_eq!(key1, key2);
        assert_eq!(key1.len(), 32);
    }

    #[test]
    fn test_derive_key_different_passwords() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = vec![0xBBu8; 32];
        let key1 = engine.derive_key("password1", &salt).unwrap();
        let key2 = engine.derive_key("password2", &salt).unwrap();
        // 不同密码应派生出不同密钥
        assert_ne!(key1, key2);
    }

    #[test]
    fn test_derive_key_different_salts() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt1 = vec![0xCCu8; 32];
        let salt2 = vec![0xDDu8; 32];
        let key1 = engine.derive_key("password", &salt1).unwrap();
        let key2 = engine.derive_key("password", &salt2).unwrap();
        // 不同盐值应派生出不同密钥
        assert_ne!(key1, key2);
    }

    #[test]
    fn test_derive_key_with_custom_output_len() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = vec![0u8; 32];
        let key = engine.derive_key_with_params("password", &salt, 64).unwrap();
        assert_eq!(key.len(), 64);
    }

    #[test]
    fn test_generate_salt_length() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        assert_eq!(salt.len(), 32);
    }

    #[test]
    fn test_generate_salt_randomness() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt1 = engine.generate_salt();
        let salt2 = engine.generate_salt();
        // 两次生成的盐值应不同（概率上）
        assert_ne!(salt1, salt2);
    }

    // ==================== 密码哈希与验证测试 ====================

    #[test]
    fn test_hash_and_verify_password() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = vec![0u8; 32];
        let hash = engine.hash_password("my_secret", &salt).unwrap();
        assert_eq!(hash.len(), 64);
        // 正确密码应验证通过
        assert!(engine.verify_password("my_secret", &salt, &hash).unwrap());
    }

    #[test]
    fn test_verify_password_wrong_password() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = vec![0u8; 32];
        let hash = engine.hash_password("correct", &salt).unwrap();
        // 错误密码应验证失败
        assert!(!engine.verify_password("wrong", &salt, &hash).unwrap());
    }

    #[test]
    fn test_verify_password_wrong_salt() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt1 = vec![0u8; 32];
        let salt2 = vec![1u8; 32];
        let hash = engine.hash_password("password", &salt1).unwrap();
        // 不同盐值应验证失败
        assert!(!engine.verify_password("password", &salt2, &hash).unwrap());
    }

    // ==================== 加密/解密测试 ====================

    #[test]
    fn test_encrypt_decrypt_round_trip() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        let key = engine.derive_key("test_password", &salt).unwrap();

        let plaintext = b"Hello, DevNote!";
        let ciphertext = engine.encrypt(plaintext, &key).unwrap();
        let decrypted = engine.decrypt(&ciphertext, &key).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_encrypt_decrypt_empty_data() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        let key = engine.derive_key("test_password", &salt).unwrap();

        let plaintext = b"";
        let ciphertext = engine.encrypt(plaintext, &key).unwrap();
        let decrypted = engine.decrypt(&ciphertext, &key).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_encrypt_decrypt_large_data() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        let key = engine.derive_key("test_password", &salt).unwrap();

        let plaintext = vec![0x42u8; 100_000]; // 100 KB
        let ciphertext = engine.encrypt(&plaintext, &key).unwrap();
        let decrypted = engine.decrypt(&ciphertext, &key).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_encrypt_produces_different_ciphertexts() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        let key = engine.derive_key("test_password", &salt).unwrap();

        let plaintext = b"Same plaintext";
        let ct1 = engine.encrypt(plaintext, &key).unwrap();
        let ct2 = engine.encrypt(plaintext, &key).unwrap();

        // 由于随机 nonce，相同明文应产生不同密文
        assert_ne!(ct1, ct2);
    }

    #[test]
    fn test_decrypt_with_wrong_key_fails() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        let key1 = engine.derive_key("password1", &salt).unwrap();
        let key2 = engine.derive_key("password2", &salt).unwrap();

        let ciphertext = engine.encrypt(b"secret data", &key1).unwrap();
        // 使用错误密钥解密应失败
        let result = engine.decrypt(&ciphertext, &key2);
        assert!(result.is_err());
    }

    #[test]
    fn test_decrypt_tampered_ciphertext_fails() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        let key = engine.derive_key("test_password", &salt).unwrap();

        let ciphertext = engine.encrypt(b"secret data", &key).unwrap();
        // 篡改密文
        let mut tampered = ciphertext.clone();
        let tamper_pos = tampered.len() / 2;
        tampered[tamper_pos] ^= 0xFF;

        let result = engine.decrypt(&tampered, &key);
        assert!(result.is_err());
    }

    #[test]
    fn test_decrypt_invalid_data_fails() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        let key = engine.derive_key("test_password", &salt).unwrap();

        // 数据长度不足，应返回错误
        let short_data = vec![0u8; 10];
        let result = engine.decrypt(&short_data, &key);
        assert!(result.is_err());
    }

    // ==================== 结构化加密/解密测试 ====================

    #[test]
    fn test_encrypt_structured_decrypt_structured_round_trip() {
        let engine = DefaultCryptoEngine::new(test_config());
        let key = vec![0x42u8; 32];
        let plaintext = b"structured data test";

        let encrypted = engine.encrypt_structured(plaintext, &key).unwrap();
        assert_eq!(encrypted.nonce.len(), 24);
        assert_eq!(encrypted.tag.len(), 16);

        let decrypted = engine.decrypt_structured(&encrypted, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_encrypt_structured_via_trait_decrypt() {
        let engine = DefaultCryptoEngine::new(test_config());
        let key = vec![0x42u8; 32];
        let plaintext = b"trait round trip";

        // 通过 trait 方法加密（返回 to_bytes 格式）
        let ciphertext = engine.encrypt(plaintext, &key).unwrap();
        // 通过 trait 方法解密
        let decrypted = engine.decrypt(&ciphertext, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    // ==================== 恢复短语测试 ====================

    #[test]
    fn test_generate_recovery_phrase() {
        let phrase = DefaultCryptoEngine::generate_recovery_phrase().unwrap();
        // BIP-39 24 个单词短语
        let words: Vec<&str> = phrase.split_whitespace().collect();
        assert_eq!(words.len(), 24);
    }

    #[test]
    fn test_generate_recovery_phrase_uniqueness() {
        let phrase1 = DefaultCryptoEngine::generate_recovery_phrase().unwrap();
        let phrase2 = DefaultCryptoEngine::generate_recovery_phrase().unwrap();
        // 两次生成的短语应不同
        assert_ne!(phrase1, phrase2);
    }

    #[test]
    fn test_key_from_recovery_phrase_deterministic() {
        let salt = vec![0u8; 32];
        let phrase = DefaultCryptoEngine::generate_recovery_phrase().unwrap();
        let key1 = DefaultCryptoEngine::key_from_recovery_phrase(&phrase, &salt).unwrap();
        let key2 = DefaultCryptoEngine::key_from_recovery_phrase(&phrase, &salt).unwrap();
        // 相同短语和盐值应派生出相同密钥
        assert_eq!(key1, key2);
    }

    #[test]
    fn test_verify_recovery_phrase_valid() {
        let salt = vec![0u8; 32];
        let phrase = DefaultCryptoEngine::generate_recovery_phrase().unwrap();
        let key = DefaultCryptoEngine::key_from_recovery_phrase(&phrase, &salt).unwrap();
        // 正确短语应验证通过
        assert!(DefaultCryptoEngine::verify_recovery_phrase(&phrase, &salt, &key).unwrap());
    }

    #[test]
    fn test_verify_recovery_phrase_invalid() {
        let salt = vec![0u8; 32];
        let phrase1 = DefaultCryptoEngine::generate_recovery_phrase().unwrap();
        let phrase2 = DefaultCryptoEngine::generate_recovery_phrase().unwrap();
        let key = DefaultCryptoEngine::key_from_recovery_phrase(&phrase1, &salt).unwrap();
        // 不同短语应验证失败
        assert!(!DefaultCryptoEngine::verify_recovery_phrase(&phrase2, &salt, &key).unwrap());
    }

    #[test]
    fn test_key_from_recovery_phrase_invalid_phrase() {
        let salt = vec![0u8; 32];
        let result = DefaultCryptoEngine::key_from_recovery_phrase("invalid phrase not bip39", &salt);
        assert!(result.is_err());
    }

    // ==================== CryptoEngine trait 测试 ====================

    #[test]
    fn test_crypto_engine_trait_implementation() {
        let engine = DefaultCryptoEngine::new(test_config());
        let salt = engine.generate_salt();
        let key = engine.derive_key("password", &salt).unwrap();

        // 验证 trait 方法完整可用
        let plaintext = b"trait test";
        let ciphertext = engine.encrypt(plaintext, &key).unwrap();
        let decrypted = engine.decrypt(&ciphertext, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_default_crypto_engine_default() {
        // Default trait 应使用标准配置
        let engine = DefaultCryptoEngine::default();
        assert_eq!(engine.config.iterations, 3);
        assert_eq!(engine.config.memory_kib, 65536);
    }
}
