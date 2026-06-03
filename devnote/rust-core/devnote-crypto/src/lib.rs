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
    pub iterations: u32,
}

impl Default for CryptoConfig {
    fn default() -> Self {
        Self {
            algorithm: "XChaCha20-Poly1305".to_string(),
            key_derivation: "Argon2id".to_string(),
            iterations: 3,
        }
    }
}

impl CryptoConfig {
    pub fn standard() -> Self {
        Self {
            algorithm: "XChaCha20-Poly1305".to_string(),
            key_derivation: "Argon2id".to_string(),
            iterations: 3,
        }
    }

    pub fn high_strength() -> Self {
        Self {
            algorithm: "XChaCha20-Poly1305".to_string(),
            key_derivation: "Argon2id".to_string(),
            iterations: 6,
        }
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
        let params = Params::new(65536, self.config.iterations, 4, Some(output_len))
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
