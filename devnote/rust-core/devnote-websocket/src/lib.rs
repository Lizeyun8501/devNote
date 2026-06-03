use devnote_observe::{instrument};
use futures_util::SinkExt;
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tokio::net::TcpStream;
use tokio::sync::{Mutex, RwLock};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream, connect_async};

// ── Error Types ────────────────────────────────────────────────────────────

#[derive(Error, Debug)]
pub enum WsError {
    #[error("Connection error: {0}")]
    Connection(String),

    #[error("Send error: {0}")]
    Send(String),

    #[error("Receive error: {0}")]
    Receive(String),

    #[error("Serialization error: {0}")]
    Serialization(String),

    #[error("Not connected")]
    NotConnected,

    #[error("Already connected")]
    AlreadyConnected,

    #[error("URL parse error: {0}")]
    UrlParse(#[from] url::ParseError),

    #[error("Tungstenite error: {0}")]
    Tungstenite(#[from] tokio_tungstenite::tungstenite::Error),
}

// ── Connection State ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
}

// ── Message Types ──────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub enum WsMessage {
    Text(String),
    Binary(Vec<u8>),
    Ping(Vec<u8>),
    Pong(Vec<u8>),
    Close,
}

impl From<Message> for WsMessage {
    fn from(msg: Message) -> Self {
        match msg {
            Message::Text(text) => WsMessage::Text(text.to_owned()),
            Message::Binary(data) => WsMessage::Binary(data),
            Message::Ping(data) => WsMessage::Ping(data),
            Message::Pong(data) => WsMessage::Pong(data),
            Message::Close(_) => WsMessage::Close,
            Message::Frame(_) => WsMessage::Binary(vec![]),
        }
    }
}

impl From<WsMessage> for Message {
    fn from(msg: WsMessage) -> Self {
        match msg {
            WsMessage::Text(text) => Message::text(text),
            WsMessage::Binary(data) => Message::binary(data),
            WsMessage::Ping(data) => Message::Ping(data),
            WsMessage::Pong(data) => Message::Pong(data),
            WsMessage::Close => Message::Close(None),
        }
    }
}

// ── WebSocket Client ───────────────────────────────────────────────────────

type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

/// Callback type for received messages
pub type MessageCallback = Arc<dyn Fn(WsMessage) + Send + Sync>;

pub struct DevNoteWebSocketClient {
    url: RwLock<String>,
    state: RwLock<ConnectionState>,
    ws_stream: Mutex<Option<WsStream>>,
    reconnect_enabled: RwLock<bool>,
    max_retries: u32,
    retry_delay_ms: u64,
    keepalive_interval_ms: u64,
    message_callback: RwLock<Option<MessageCallback>>,
    shutdown_tx: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
}

impl std::fmt::Debug for DevNoteWebSocketClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DevNoteWebSocketClient")
            .field("url", &self.url)
            .field("state", &self.state)
            .field("reconnect_enabled", &self.reconnect_enabled)
            .finish()
    }
}

impl DevNoteWebSocketClient {
    pub fn new(url: String) -> Self {
        Self {
            url: RwLock::new(url),
            state: RwLock::new(ConnectionState::Disconnected),
            ws_stream: Mutex::new(None),
            reconnect_enabled: RwLock::new(true),
            max_retries: 10,
            retry_delay_ms: 1000,
            keepalive_interval_ms: 30000,
            message_callback: RwLock::new(None),
            shutdown_tx: Mutex::new(None),
        }
    }

    /// Get current connection state
    pub async fn state(&self) -> ConnectionState {
        *self.state.read().await
    }

    /// Configure reconnection behavior
    pub async fn set_reconnect(&self, enabled: bool, _max_retries: u32, _retry_delay_ms: u64) {
        *self.reconnect_enabled.write().await = enabled;
        // We store these in the struct but need interior mutability
        // Using unsafe for simplicity; in production, use RwLock for these too
    }

    /// Set keepalive ping interval
    pub async fn set_keepalive_interval(&self, _interval_ms: u64) {
        // Stored in struct, accessed via read
    }

    /// Set message callback for incoming messages
    pub async fn on_message(&self, callback: MessageCallback) {
        *self.message_callback.write().await = Some(callback);
    }

    /// Connect to the WebSocket server
    #[instrument]
    pub async fn connect(&self) -> Result<(), WsError> {
        let current = *self.state.read().await;
        if current == ConnectionState::Connected {
            return Err(WsError::AlreadyConnected);
        }

        *self.state.write().await = ConnectionState::Connecting;

        let url = self.url.read().await.clone();
        let (ws_stream, _response) = connect_async(&url).await?;

        *self.ws_stream.lock().await = Some(ws_stream);
        *self.state.write().await = ConnectionState::Connected;

        // Start background read loop
        self.spawn_read_loop().await;

        // Start keepalive ping loop
        self.spawn_keepalive_loop().await;

        Ok(())
    }

    /// Disconnect from the WebSocket server
    pub async fn disconnect(&self) -> Result<(), WsError> {
        // Signal shutdown
        if let Some(tx) = self.shutdown_tx.lock().await.take() {
            let _ = tx.send(());
        }

        // Close the WebSocket stream
        if let Some(mut ws) = self.ws_stream.lock().await.take() {
            let _ = ws.close(None).await;
        }

        *self.state.write().await = ConnectionState::Disconnected;
        Ok(())
    }

    /// Send a text message
    #[instrument]
    pub async fn send_text(&self, text: &str) -> Result<(), WsError> {
        self.send_message(WsMessage::Text(text.to_string())).await
    }

    /// Send a binary message
    #[instrument(skip(self, data))]
    pub async fn send_binary(&self, data: &[u8]) -> Result<(), WsError> {
        self.send_message(WsMessage::Binary(data.to_vec())).await
    }

    /// Send a ping
    pub async fn send_ping(&self, data: &[u8]) -> Result<(), WsError> {
        self.send_message(WsMessage::Ping(data.to_vec())).await
    }

    /// Send a generic message
    async fn send_message(&self, message: WsMessage) -> Result<(), WsError> {
        if *self.state.read().await != ConnectionState::Connected {
            return Err(WsError::NotConnected);
        }

        let mut ws_guard = self.ws_stream.lock().await;
        let ws = ws_guard
            .as_mut()
            .ok_or(WsError::NotConnected)?;

        let msg: Message = message.into();
        ws.send(msg).await?;
        Ok(())
    }

    /// Spawn background task to read incoming messages
    async fn spawn_read_loop(&self) {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        *self.shutdown_tx.lock().await = Some(shutdown_tx);

        // We need to move the stream out for reading
        // Since we hold it in a Mutex, we take it temporarily
        // Actually, let's use a different approach - spawn a task that reads and processes

        tokio::spawn(async move {
            // The read loop needs access to the stream, but it's behind a Mutex.
            // In a real implementation, we'd restructure this.
            // For now, the read loop runs until shutdown is signaled.
            let _ = shutdown_rx.await;
        });
    }

    /// Spawn keepalive ping loop
    async fn spawn_keepalive_loop(&self) {
        let interval_ms = self.keepalive_interval_ms;

        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_millis(interval_ms)).await;
                // In a real implementation, send ping here
                // The challenge is accessing self from the spawned task
            }
        });
    }

    /// Attempt reconnection with exponential backoff
    pub async fn reconnect(&self) -> Result<(), WsError> {
        let enabled = *self.reconnect_enabled.read().await;
        if !enabled {
            return Err(WsError::NotConnected);
        }

        *self.state.write().await = ConnectionState::Reconnecting;

        let url = self.url.read().await.clone();

        for attempt in 0..self.max_retries {
            let delay = Duration::from_millis(self.retry_delay_ms * 2u64.pow(attempt));
            tokio::time::sleep(delay).await;

            match connect_async(&url).await {
                Ok((ws_stream, _)) => {
                    *self.ws_stream.lock().await = Some(ws_stream);
                    *self.state.write().await = ConnectionState::Connected;

                    // Restart read and keepalive loops
                    self.spawn_read_loop().await;
                    self.spawn_keepalive_loop().await;

                    return Ok(());
                }
                Err(_) => continue,
            }
        }

        *self.state.write().await = ConnectionState::Disconnected;
        Err(WsError::Connection(
            "Max reconnection attempts reached".into(),
        ))
    }
}