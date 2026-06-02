use thiserror::Error;

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

pub trait CryptoEngine: Send + Sync {
    fn encrypt(&self, plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError>;
    fn decrypt(&self, ciphertext: &[u8], key: &[u8]) -> Result<Vec<u8>, CryptoError>;
    fn derive_key(&self, password: &str, salt: &[u8]) -> Result<Vec<u8>, CryptoError>;
    fn generate_salt(&self) -> Vec<u8>;
}
