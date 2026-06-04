use devnote_observe::{instrument};
use futures_util::{SinkExt, StreamExt};
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
type WsSink = futures_util::stream::SplitSink<WsStream, Message>;
type WsReadStream = futures_util::stream::SplitStream<WsStream>;

/// Callback type for received messages
pub type MessageCallback = Arc<dyn Fn(WsMessage) + Send + Sync>;

/// WebSocket 客户端
/// 借鉴 Anytype 的 WebSocket 全双工通信模式：读循环+保活循环+自动重连
pub struct DevNoteWebSocketClient {
    inner: Arc<ClientInner>,
}

struct ClientInner {
    url: RwLock<String>,
    state: RwLock<ConnectionState>,
    ws_sink: Mutex<Option<WsSink>>,
    reconnect_enabled: RwLock<bool>,
    max_retries: RwLock<u32>,
    retry_delay_ms: RwLock<u64>,
    keepalive_interval_ms: RwLock<u64>,
    message_callback: RwLock<Option<MessageCallback>>,
    read_shutdown_tx: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    keepalive_shutdown_tx: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
}

impl std::fmt::Debug for DevNoteWebSocketClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DevNoteWebSocketClient")
            .field("url", &self.inner.url)
            .field("state", &self.inner.state)
            .field("reconnect_enabled", &self.inner.reconnect_enabled)
            .finish()
    }
}

impl DevNoteWebSocketClient {
    pub fn new(url: String) -> Self {
        Self {
            inner: Arc::new(ClientInner {
                url: RwLock::new(url),
                state: RwLock::new(ConnectionState::Disconnected),
                ws_sink: Mutex::new(None),
                reconnect_enabled: RwLock::new(true),
                max_retries: RwLock::new(10),
                retry_delay_ms: RwLock::new(1000),
                keepalive_interval_ms: RwLock::new(30000),
                message_callback: RwLock::new(None),
                read_shutdown_tx: Mutex::new(None),
                keepalive_shutdown_tx: Mutex::new(None),
            }),
        }
    }

    /// Get current connection state
    pub async fn state(&self) -> ConnectionState {
        *self.inner.state.read().await
    }

    /// Configure reconnection behavior
    pub async fn set_reconnect(&self, enabled: bool, max_retries: u32, retry_delay_ms: u64) {
        *self.inner.reconnect_enabled.write().await = enabled;
        *self.inner.max_retries.write().await = max_retries;
        *self.inner.retry_delay_ms.write().await = retry_delay_ms;
    }

    /// Set keepalive ping interval
    pub async fn set_keepalive_interval(&self, interval_ms: u64) {
        *self.inner.keepalive_interval_ms.write().await = interval_ms;
    }

    /// Set message callback for incoming messages
    pub async fn on_message(&self, callback: MessageCallback) {
        *self.inner.message_callback.write().await = Some(callback);
    }

    /// Connect to the WebSocket server
    #[instrument]
    pub async fn connect(&self) -> Result<(), WsError> {
        let current = *self.inner.state.read().await;
        if current == ConnectionState::Connected {
            return Err(WsError::AlreadyConnected);
        }

        *self.inner.state.write().await = ConnectionState::Connecting;

        let url = self.inner.url.read().await.clone();
        let (ws_stream, _response) = connect_async(&url).await?;
        let (sink, stream) = ws_stream.split();

        *self.inner.ws_sink.lock().await = Some(sink);
        *self.inner.state.write().await = ConnectionState::Connected;

        // 启动后台读循环，持续从 WebSocket 流读取消息
        ClientInner::spawn_read_loop(Arc::clone(&self.inner), stream);

        // 启动保活循环，定期发送 Ping 帧
        ClientInner::spawn_keepalive_loop(Arc::clone(&self.inner));

        Ok(())
    }

    /// Disconnect from the WebSocket server
    pub async fn disconnect(&self) -> Result<(), WsError> {
        // 通知读循环退出
        if let Some(tx) = self.inner.read_shutdown_tx.lock().await.take() {
            let _ = tx.send(());
        }

        // 通知保活循环退出
        if let Some(tx) = self.inner.keepalive_shutdown_tx.lock().await.take() {
            let _ = tx.send(());
        }

        // 通过 Sink 关闭 WebSocket 连接
        if let Some(mut sink) = self.inner.ws_sink.lock().await.take() {
            let _ = sink.close().await;
        }

        *self.inner.state.write().await = ConnectionState::Disconnected;
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
        if *self.inner.state.read().await != ConnectionState::Connected {
            return Err(WsError::NotConnected);
        }

        let mut sink_guard = self.inner.ws_sink.lock().await;
        let sink = sink_guard
            .as_mut()
            .ok_or(WsError::NotConnected)?;

        let msg: Message = message.into();
        sink.send(msg).await.map_err(|e| WsError::Send(e.to_string()))?;
        Ok(())
    }

    /// Attempt reconnection with exponential backoff
    pub async fn reconnect(&self) -> Result<(), WsError> {
        ClientInner::reconnect(&self.inner).await
    }
}

impl ClientInner {
    /// 读循环：持续从 WebSocket 流中读取消息并回调通知上层
    fn spawn_read_loop(inner: Arc<Self>, mut read_stream: WsReadStream) {
        tokio::spawn(async move {
            // 通知旧的读循环退出（如果存在）
            if let Some(tx) = inner.read_shutdown_tx.lock().await.take() {
                let _ = tx.send(());
            }

            let (shutdown_tx, mut shutdown_rx) = tokio::sync::oneshot::channel::<()>();
            *inner.read_shutdown_tx.lock().await = Some(shutdown_tx);

            let self_clone = Arc::clone(&inner);

            loop {
                tokio::select! {
                    _ = &mut shutdown_rx => break,
                    msg = read_stream.next() => {
                        match msg {
                            Some(Ok(msg)) => {
                                if let Some(cb) = self_clone.message_callback.read().await.as_ref() {
                                    cb(msg.into());
                                }
                            }
                            Some(Err(e)) => {
                                tracing::warn!("WebSocket read error: {}", e);
                                *self_clone.state.write().await = ConnectionState::Disconnected;
                                if *self_clone.reconnect_enabled.read().await {
                                    let _ = self_clone.reconnect().await;
                                }
                                break;
                            }
                            None => {
                                // 流正常结束（服务端关闭连接）
                                *self_clone.state.write().await = ConnectionState::Disconnected;
                                if *self_clone.reconnect_enabled.read().await {
                                    let _ = self_clone.reconnect().await;
                                }
                                break;
                            }
                        }
                    }
                }
            }
        });
    }

    /// 保活循环：每 30 秒发送 Ping 帧保持连接活跃
    fn spawn_keepalive_loop(inner: Arc<Self>) {
        tokio::spawn(async move {
            // 通知旧的保活循环退出（如果存在）
            if let Some(tx) = inner.keepalive_shutdown_tx.lock().await.take() {
                let _ = tx.send(());
            }

            let interval = Duration::from_millis(*inner.keepalive_interval_ms.read().await);
            let (shutdown_tx, mut shutdown_rx) = tokio::sync::oneshot::channel::<()>();
            *inner.keepalive_shutdown_tx.lock().await = Some(shutdown_tx);

            let self_clone = Arc::clone(&inner);

            loop {
                tokio::select! {
                    _ = tokio::time::sleep(interval) => {
                        if *self_clone.state.read().await != ConnectionState::Connected {
                            continue;
                        }
                        let mut sink_guard = self_clone.ws_sink.lock().await;
                        if let Some(ref mut sink) = *sink_guard {
                            let _ = sink.send(Message::Ping(vec![])).await;
                        }
                    }
                    _ = &mut shutdown_rx => break,
                }
            }
        });
    }

    /// 自动重连：指数退避 + 最多重试 max_retries 次
    async fn reconnect(self: &Arc<Self>) -> Result<(), WsError> {
        let enabled = *self.reconnect_enabled.read().await;
        if !enabled {
            return Err(WsError::NotConnected);
        }

        *self.state.write().await = ConnectionState::Reconnecting;

        let url = self.url.read().await.clone();

        for attempt in 0..*self.max_retries.read().await {
            let delay = Duration::from_millis(*self.retry_delay_ms.read().await * 2u64.pow(attempt));
            tokio::time::sleep(delay).await;

            match connect_async(&url).await {
                Ok((ws_stream, _)) => {
                    let (sink, stream) = ws_stream.split();
                    *self.ws_sink.lock().await = Some(sink);
                    *self.state.write().await = ConnectionState::Connected;

                    // 重连成功后重启读循环和保活循环
                    Self::spawn_read_loop(Arc::clone(self), stream);
                    Self::spawn_keepalive_loop(Arc::clone(self));

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