pub mod devnote {
    tonic::include_proto!("devnote");
}

use devnote_observe::{instrument};
use devnote::{
    dev_note_service_client::DevNoteServiceClient,
    dev_note_service_server::{DevNoteService, DevNoteServiceServer},
    sync_service_client::SyncServiceClient,
    sync_service_server::{SyncService, SyncServiceServer},
    DispatchRequest, DispatchResponse,
    PushRequest, PushResponse,
    PullRequest, PullResponse,
    WatchRequest, ChangeEvent,
    ClientEvent, ServerEvent,
};
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tokio::sync::RwLock;
use tonic::transport::{Certificate, Channel, ClientTlsConfig, Identity, Server, ServerTlsConfig};
use tonic::{Request, Response, Status, Streaming};

// ── Error Types ────────────────────────────────────────────────────────────

#[derive(Error, Debug)]
pub enum GrpcError {
    #[error("Connection error: {0}")]
    Connection(String),

    #[error("gRPC status error: {0}")]
    Status(#[from] Status),

    #[error("Transport error: {0}")]
    Transport(#[from] tonic::transport::Error),

    #[error("Serialization error: {0}")]
    Serialization(String),

    #[error("Not connected")]
    NotConnected,

    #[error("Already connected")]
    AlreadyConnected,

    #[error("Timeout")]
    Timeout,
}

// ── Connection State ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
}

// ── TLS Configuration ──────────────────────────────────────────────────────

#[derive(Clone)]
pub struct TlsConfig {
    pub ca_cert_pem: Option<String>,
    pub client_cert_pem: Option<String>,
    pub client_key_pem: Option<String>,
    pub domain: Option<String>,
}

// ── gRPC Client ────────────────────────────────────────────────────────────

pub struct DevNoteGrpcClient {
    addr: RwLock<String>,
    tls_config: RwLock<Option<TlsConfig>>,
    state: RwLock<ConnectionState>,
    dispatch_client: RwLock<Option<DevNoteServiceClient<Channel>>>,
    sync_client: RwLock<Option<SyncServiceClient<Channel>>>,
    reconnect_enabled: RwLock<bool>,
    #[allow(dead_code)]
    max_retries: u32,
    #[allow(dead_code)]
    retry_delay_ms: u64,
}

impl std::fmt::Debug for DevNoteGrpcClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DevNoteGrpcClient")
            .field("addr", &self.addr)
            .field("state", &self.state)
            .field("reconnect_enabled", &self.reconnect_enabled)
            .finish()
    }
}

impl DevNoteGrpcClient {
    pub fn new(addr: String) -> Self {
        Self {
            addr: RwLock::new(addr),
            tls_config: RwLock::new(None),
            state: RwLock::new(ConnectionState::Disconnected),
            dispatch_client: RwLock::new(None),
            sync_client: RwLock::new(None),
            reconnect_enabled: RwLock::new(true),
            max_retries: 5,
            retry_delay_ms: 1000,
        }
    }

    pub fn with_tls(addr: String, tls: TlsConfig) -> Self {
        let client = Self::new(addr);
        let _ = futures_executor::block_on(async {
            *client.tls_config.write().await = Some(tls);
        });
        client
    }

    /// Get current connection state
    pub async fn state(&self) -> ConnectionState {
        *self.state.read().await
    }

    /// Build a transport channel based on TLS config
    async fn build_channel(&self) -> Result<Channel, GrpcError> {
        let addr = self.addr.read().await.clone();
        let tls = self.tls_config.read().await.clone();

        match tls {
            Some(ref tls_config) => {
                let mut tls_builder = ClientTlsConfig::new();

                if let Some(ref domain) = tls_config.domain {
                    tls_builder = tls_builder.domain_name(domain.clone());
                }

                if let Some(ref ca_pem) = tls_config.ca_cert_pem {
                    let ca = Certificate::from_pem(ca_pem);
                    tls_builder = tls_builder.ca_certificate(ca);
                }

                if let (Some(ref cert_pem), Some(ref key_pem)) =
                    (&tls_config.client_cert_pem, &tls_config.client_key_pem)
                {
                    let identity = Identity::from_pem(cert_pem, key_pem);
                    tls_builder = tls_builder.identity(identity);
                }

                let channel = Channel::from_shared(addr.clone())
                    .map_err(|e| GrpcError::Connection(e.to_string()))?
                    .tls_config(tls_builder)?
                    .connect()
                    .await?;
                Ok(channel)
            }
            None => {
                let channel = Channel::from_shared(addr)
                    .map_err(|e| GrpcError::Connection(e.to_string()))?
                    .connect()
                    .await?;
                Ok(channel)
            }
        }
    }

    /// Connect to the gRPC server
    #[instrument]
    pub async fn connect(&self) -> Result<(), GrpcError> {
        let current = *self.state.read().await;
        if current == ConnectionState::Connected {
            return Err(GrpcError::AlreadyConnected);
        }

        *self.state.write().await = ConnectionState::Connecting;

        match self.build_channel().await {
            Ok(channel) => {
                let dispatch_client = DevNoteServiceClient::new(channel.clone());
                let sync_client = SyncServiceClient::new(channel);

                *self.dispatch_client.write().await = Some(dispatch_client);
                *self.sync_client.write().await = Some(sync_client);
                *self.state.write().await = ConnectionState::Connected;
                Ok(())
            }
            Err(e) => {
                *self.state.write().await = ConnectionState::Disconnected;
                Err(e)
            }
        }
    }

    /// Disconnect from the gRPC server
    pub async fn disconnect(&self) {
        *self.dispatch_client.write().await = None;
        *self.sync_client.write().await = None;
        *self.state.write().await = ConnectionState::Disconnected;
    }

    /// Dispatch a request to the server
    #[instrument(skip(self, payload))]
    pub async fn dispatch(
        &self,
        method: &str,
        payload: Vec<u8>,
        request_id: &str,
    ) -> Result<DispatchResponse, GrpcError> {
        let mut client_guard = self.dispatch_client.write().await;
        let client = client_guard
            .as_mut()
            .ok_or(GrpcError::NotConnected)?;

        let request = Request::new(DispatchRequest {
            method: method.to_string(),
            payload,
            request_id: request_id.to_string(),
        });

        let response = client
            .dispatch(request)
            .await
            .map_err(|e| {
                Self::handle_status_error_inner(&e);
                GrpcError::Status(e)
            })?;

        Ok(response.into_inner())
    }

    /// Bidirectional streaming for real-time events
    pub async fn stream_events(
        &self,
    ) -> Result<
        (
            tokio::sync::mpsc::Sender<ClientEvent>,
            tokio::sync::mpsc::Receiver<Result<ServerEvent, GrpcError>>,
        ),
        GrpcError,
    > {
        let mut client_guard = self.dispatch_client.write().await;
        let mut client = client_guard
            .as_mut()
            .ok_or(GrpcError::NotConnected)?
            .clone();

        let (tx_in, mut rx_in) = tokio::sync::mpsc::channel::<ClientEvent>(32);
        let (tx_out, rx_out) = tokio::sync::mpsc::channel::<Result<ServerEvent, GrpcError>>(32);

        tokio::spawn(async move {
            let out_stream = async_stream::stream! {
                while let Some(event) = rx_in.recv().await {
                    yield event;
                }
            };

            let response = match client.stream_events(out_stream).await {
                Ok(response) => response,
                Err(e) => {
                    let _ = tx_out
                        .send(Err(GrpcError::Status(e)))
                        .await;
                    return;
                }
            };

            let mut inbound = response.into_inner();
            loop {
                match inbound.message().await {
                    Ok(Some(event)) => {
                        let _ = tx_out.send(Ok(event)).await;
                    }
                    Ok(None) => break,
                    Err(e) => {
                        let _ = tx_out
                            .send(Err(GrpcError::Status(e)))
                            .await;
                        break;
                    }
                }
            }
        });

        Ok((tx_in, rx_out))
    }

    /// Push changes to the sync server
    #[instrument(skip(self, encrypted_data))]
    pub async fn push_changes(
        &self,
        device_id: &str,
        encrypted_data: Vec<u8>,
        base_version: i64,
    ) -> Result<PushResponse, GrpcError> {
        let mut client_guard = self.sync_client.write().await;
        let client = client_guard
            .as_mut()
            .ok_or(GrpcError::NotConnected)?;

        let request = Request::new(PushRequest {
            device_id: device_id.to_string(),
            encrypted_data,
            base_version,
        });

        let response = client
            .push_changes(request)
            .await
            .map_err(|e| {
                Self::handle_status_error_inner(&e);
                GrpcError::Status(e)
            })?;

        Ok(response.into_inner())
    }

    /// Pull changes from the sync server
    #[instrument]
    pub async fn pull_changes(
        &self,
        device_id: &str,
        since_version: i64,
    ) -> Result<PullResponse, GrpcError> {
        let mut client_guard = self.sync_client.write().await;
        let client = client_guard
            .as_mut()
            .ok_or(GrpcError::NotConnected)?;

        let request = Request::new(PullRequest {
            device_id: device_id.to_string(),
            since_version,
        });

        let response = client
            .pull_changes(request)
            .await
            .map_err(|e| {
                Self::handle_status_error_inner(&e);
                GrpcError::Status(e)
            })?;

        Ok(response.into_inner())
    }

    /// Watch for changes from the sync server (streaming)
    pub async fn watch_changes(
        &self,
        device_id: &str,
    ) -> Result<tonic::Streaming<ChangeEvent>, GrpcError> {
        let mut client_guard = self.sync_client.write().await;
        let client = client_guard
            .as_mut()
            .ok_or(GrpcError::NotConnected)?;

        let request = Request::new(WatchRequest {
            device_id: device_id.to_string(),
        });

        let response = client
            .watch_changes(request)
            .await
            .map_err(|e| {
                Self::handle_status_error_inner(&e);
                GrpcError::Status(e)
            })?;

        Ok(response.into_inner())
    }

    /// Attempt reconnection with exponential backoff
    pub async fn reconnect(&self) -> Result<(), GrpcError> {
        let enabled = *self.reconnect_enabled.read().await;
        if !enabled {
            return Err(GrpcError::NotConnected);
        }

        *self.state.write().await = ConnectionState::Reconnecting;

        for attempt in 0..self.max_retries {
            let delay = Duration::from_millis(self.retry_delay_ms * 2u64.pow(attempt));
            tokio::time::sleep(delay).await;

            match self.build_channel().await {
                Ok(channel) => {
                    let dispatch_client = DevNoteServiceClient::new(channel.clone());
                    let sync_client = SyncServiceClient::new(channel);

                    *self.dispatch_client.write().await = Some(dispatch_client);
                    *self.sync_client.write().await = Some(sync_client);
                    *self.state.write().await = ConnectionState::Connected;
                    return Ok(());
                }
                Err(_) => continue,
            }
        }

        *self.state.write().await = ConnectionState::Disconnected;
        Err(GrpcError::Connection("Max reconnection attempts reached".into()))
    }

    fn handle_status_error_inner(status: &Status) {
        match status.code() {
            tonic::Code::Unauthenticated | tonic::Code::PermissionDenied => {
                // Auth errors - don't reconnect
            }
            tonic::Code::Unavailable
            | tonic::Code::DeadlineExceeded
            | tonic::Code::Internal => {
                // Transient errors - could trigger reconnection
            }
            _ => {}
        }
    }
}

// ── gRPC Server ────────────────────────────────────────────────────────────

/// Trait for handling dispatch logic on the server side
#[async_trait::async_trait]
pub trait DispatchHandler: Send + Sync {
    async fn handle_dispatch(
        &self,
        method: &str,
        payload: &[u8],
        request_id: &str,
    ) -> Result<Vec<u8>, String>;
}

/// Trait for handling sync operations on the server side
#[async_trait::async_trait]
pub trait SyncHandler: Send + Sync {
    async fn handle_push(
        &self,
        device_id: &str,
        encrypted_data: &[u8],
        base_version: i64,
    ) -> Result<(bool, i64), String>;

    async fn handle_pull(
        &self,
        device_id: &str,
        since_version: i64,
    ) -> Result<(Vec<Vec<u8>>, i64), String>;
}

/// Trait for handling stream events on the server side
#[async_trait::async_trait]
pub trait StreamHandler: Send + Sync {
    async fn on_client_event(&self, event: ClientEvent) -> Option<ServerEvent>;
}

/// Combined handler trait
pub trait ServiceHandler: DispatchHandler + SyncHandler + StreamHandler {}
impl<T: DispatchHandler + SyncHandler + StreamHandler> ServiceHandler for T {}

struct DevNoteServiceHandler {
    handler: Arc<dyn ServiceHandler>,
}

type StreamEventsStream =
    std::pin::Pin<Box<dyn tokio_stream::Stream<Item = Result<ServerEvent, Status>> + Send>>;

#[async_trait::async_trait]
impl DevNoteService for DevNoteServiceHandler {
    type StreamEventsStream = StreamEventsStream;

    async fn dispatch(
        &self,
        request: Request<DispatchRequest>,
    ) -> Result<Response<DispatchResponse>, Status> {
        let req = request.into_inner();
        match self
            .handler
            .handle_dispatch(&req.method, &req.payload, &req.request_id)
            .await
        {
            Ok(payload) => Ok(Response::new(DispatchResponse {
                success: true,
                payload,
                error: String::new(),
                request_id: req.request_id,
            })),
            Err(e) => Ok(Response::new(DispatchResponse {
                success: false,
                payload: vec![],
                error: e,
                request_id: req.request_id,
            })),
        }
    }

    async fn stream_events(
        &self,
        request: Request<Streaming<ClientEvent>>,
    ) -> Result<Response<Self::StreamEventsStream>, Status> {
        let mut inbound = request.into_inner();
        let handler = self.handler.clone();

        let out_stream = async_stream::try_stream! {
            while let Ok(Some(event)) = inbound.message().await {
                if let Some(response) = handler.on_client_event(event).await {
                    yield response;
                }
            }
        };

        Ok(Response::new(Box::pin(out_stream)))
    }
}

struct SyncServiceHandlerImpl {
    handler: Arc<dyn ServiceHandler>,
}

type WatchChangesStream =
    std::pin::Pin<Box<dyn tokio_stream::Stream<Item = Result<ChangeEvent, Status>> + Send>>;

#[async_trait::async_trait]
impl SyncService for SyncServiceHandlerImpl {
    type WatchChangesStream = WatchChangesStream;

    async fn push_changes(
        &self,
        request: Request<PushRequest>,
    ) -> Result<Response<PushResponse>, Status> {
        let req = request.into_inner();
        match self
            .handler
            .handle_push(&req.device_id, &req.encrypted_data, req.base_version)
            .await
        {
            Ok((success, version)) => Ok(Response::new(PushResponse {
                success,
                new_version: version,
                error: String::new(),
            })),
            Err(e) => Ok(Response::new(PushResponse {
                success: false,
                new_version: 0,
                error: e,
            })),
        }
    }

    async fn pull_changes(
        &self,
        request: Request<PullRequest>,
    ) -> Result<Response<PullResponse>, Status> {
        let req = request.into_inner();
        match self
            .handler
            .handle_pull(&req.device_id, req.since_version)
            .await
        {
            Ok((changes, version)) => Ok(Response::new(PullResponse {
                changes,
                latest_version: version,
            })),
            Err(e) => Err(Status::internal(e)),
        }
    }

    async fn watch_changes(
        &self,
        request: Request<WatchRequest>,
    ) -> Result<Response<Self::WatchChangesStream>, Status> {
        let _req = request.into_inner();

        // Return an empty but properly-typed stream
        let (_, rx) = tokio::sync::mpsc::channel::<Result<ChangeEvent, Status>>(1);
        let stream = tokio_stream::wrappers::ReceiverStream::new(rx);

        Ok(Response::new(Box::pin(stream)))
    }
}

/// gRPC Server builder and runner
pub struct DevNoteGrpcServer {
    addr: String,
    tls_config: Option<TlsConfig>,
    handler: Option<Arc<dyn ServiceHandler>>,
}

impl DevNoteGrpcServer {
    pub fn new(addr: String) -> Self {
        Self {
            addr,
            tls_config: None,
            handler: None,
        }
    }

    pub fn with_tls(mut self, tls: TlsConfig) -> Self {
        self.tls_config = Some(tls);
        self
    }

    pub fn with_handler(mut self, handler: Arc<dyn ServiceHandler>) -> Self {
        self.handler = Some(handler);
        self
    }

    pub async fn serve(self) -> Result<(), Box<dyn std::error::Error>> {
        let handler = self
            .handler
            .expect("Handler must be set before serving");

        let devnote_svc = DevNoteServiceHandler {
            handler: handler.clone(),
        };
        let sync_svc = SyncServiceHandlerImpl {
            handler: handler.clone(),
        };

        let addr: std::net::SocketAddr = self.addr.parse()?;

        match self.tls_config {
            Some(tls) => {
                let mut tls_builder = ServerTlsConfig::new();

                if let (Some(ref cert_pem), Some(ref key_pem)) =
                    (&tls.client_cert_pem, &tls.client_key_pem)
                {
                    let identity = Identity::from_pem(cert_pem, key_pem);
                    tls_builder = tls_builder.identity(identity);
                }

                if let Some(ref ca_pem) = tls.ca_cert_pem {
                    let ca = Certificate::from_pem(ca_pem);
                    tls_builder = tls_builder.client_ca_root(ca);
                }

                Server::builder()
                    .tls_config(tls_builder)?
                    .add_service(DevNoteServiceServer::new(devnote_svc))
                    .add_service(SyncServiceServer::new(sync_svc))
                    .serve(addr)
                    .await?;
            }
            None => {
                Server::builder()
                    .add_service(DevNoteServiceServer::new(devnote_svc))
                    .add_service(SyncServiceServer::new(sync_svc))
                    .serve(addr)
                    .await?;
            }
        }

        Ok(())
    }
}