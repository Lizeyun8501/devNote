use devnote_observe::{instrument};
use std::collections::HashMap;
use std::time::Duration;

use chrono::{DateTime, Utc};
use futures::StreamExt;
use libp2p::gossipsub::{self, IdentTopic, MessageAuthenticity};
use libp2p::identify;
use libp2p::identity;
use libp2p::kad;
use libp2p::kad::store::MemoryStore;
use libp2p::noise;
use libp2p::ping;
use libp2p::swarm::dial_opts::DialOpts;
use libp2p::swarm::{NetworkBehaviour, SwarmEvent};
use libp2p::SwarmBuilder;
use libp2p::tcp;
use libp2p::yamux;
use libp2p::Multiaddr;
use libp2p::PeerId;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::sync::mpsc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct P2PConfig {
    pub listen_addr: String,
    pub bootstrap_peers: Vec<String>,
    pub relay_server: Option<String>,
}

impl Default for P2PConfig {
    fn default() -> Self {
        Self {
            listen_addr: "/ip4/0.0.0.0/tcp/0".to_string(),
            bootstrap_peers: Vec::new(),
            relay_server: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerInfo {
    pub peer_id: String,
    pub addresses: Vec<String>,
    pub connected_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum P2PEvent {
    PeerDiscovered { peer_id: String, addresses: Vec<String> },
    PeerConnected { peer_id: String },
    PeerDisconnected { peer_id: String },
    DataReceived { peer_id: String, data: Vec<u8> },
    Error { message: String },
}

#[derive(Debug, Error)]
pub enum P2PError {
    #[error("transport error: {0}")]
    TransportError(String),
    #[error("behaviour error: {0}")]
    BehaviourError(String),
    #[error("connection error: {0}")]
    ConnectionError(String),
    #[error("node not running")]
    NotRunning,
    #[error("peer not found: {0}")]
    PeerNotFound(String),
    #[error("send error: {0}")]
    SendError(String),
    #[error("signaling error: {0}")]
    SignalingError(String),
    #[error("encryption error: {0}")]
    EncryptionError(String),
}

enum Command {
    Stop,
    DiscoverPeers,
    ConnectPeer(PeerId),
    SendData(PeerId, Vec<u8>),
    Broadcast(String, Vec<u8>),
}

#[derive(NetworkBehaviour)]
struct DevnoteBehaviour {
    kademlia: kad::Behaviour<MemoryStore>,
    gossipsub: gossipsub::Behaviour,
    identify: identify::Behaviour,
    ping: ping::Behaviour,
}

pub struct P2PNode {
    local_peer_id: String,
    command_tx: mpsc::UnboundedSender<Command>,
    event_rx: mpsc::UnboundedReceiver<P2PEvent>,
    peers: HashMap<String, PeerInfo>,
    running: bool,
    data_callback: Option<Box<dyn Fn(String, Vec<u8>) + Send + Sync>>,
}

impl std::fmt::Debug for P2PNode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("P2PNode")
            .field("local_peer_id", &self.local_peer_id)
            .field("peers", &self.peers)
            .field("running", &self.running)
            .finish()
    }
}

impl P2PNode {
    #[instrument]
    pub async fn start(config: P2PConfig) -> Result<Self, P2PError> {
        let local_key = identity::Keypair::generate_ed25519();
        let local_peer_id = PeerId::from(local_key.public());
        let local_peer_id_str = local_peer_id.to_string();

        let mut swarm = SwarmBuilder::with_existing_identity(local_key.clone())
            .with_tokio()
            .with_tcp(
                tcp::Config::default(),
                noise::Config::new,
                yamux::Config::default,
            )
            .map_err(|e| P2PError::TransportError(e.to_string()))?
            .with_behaviour(|key| {
                let peer_id = key.public().to_peer_id();
                let store = MemoryStore::new(peer_id);
                let kademlia = kad::Behaviour::new(peer_id, store);
                let gossipsub = gossipsub::Behaviour::new(
                    MessageAuthenticity::Signed(key.clone()),
                    gossipsub::Config::default(),
                )
                .expect("valid gossipsub config");
                let identify = identify::Behaviour::new(
                    identify::Config::new(
                        "/devnote/1.0.0".to_string(),
                        key.public(),
                    ),
                );
                DevnoteBehaviour {
                    kademlia,
                    gossipsub,
                    identify,
                    ping: ping::Behaviour::new(Default::default()),
                }
            })
            .map_err(|e| P2PError::BehaviourError(e.to_string()))?
            .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(60)))
            .build();

        let listen_addr: Multiaddr = config
            .listen_addr
            .parse()
            .map_err(|e| P2PError::TransportError(format!("invalid listen address: {}", e)))?;
        swarm
            .listen_on(listen_addr)
            .map_err(|e| P2PError::TransportError(e.to_string()))?;

        for peer in &config.bootstrap_peers {
            if let Ok(addr) = peer.parse::<Multiaddr>() {
                let _ = swarm.dial(addr);
            }
        }

        let topic = IdentTopic::new("devnote-sync");
        swarm
            .behaviour_mut()
            .gossipsub
            .subscribe(&topic)
            .map_err(|e| P2PError::BehaviourError(e.to_string()))?;

        let (command_tx, command_rx) = mpsc::unbounded_channel();
        let (event_tx, event_rx) = mpsc::unbounded_channel();

        tokio::spawn(event_loop(swarm, command_rx, event_tx));

        Ok(Self {
            local_peer_id: local_peer_id_str,
            command_tx,
            event_rx,
            peers: HashMap::new(),
            running: true,
            data_callback: None,
        })
    }

    pub async fn stop(&mut self) -> Result<(), P2PError> {
        if !self.running {
            return Err(P2PError::NotRunning);
        }
        let _ = self.command_tx.send(Command::Stop);
        self.running = false;
        Ok(())
    }

    #[instrument]
    pub async fn discover_peers(&mut self) -> Result<Vec<PeerInfo>, P2PError> {
        if !self.running {
            return Err(P2PError::NotRunning);
        }
        let _ = self.command_tx.send(Command::DiscoverPeers);
        Ok(self.peers.values().cloned().collect())
    }

    #[instrument]
    pub async fn connect_peer(&mut self, peer_id: &str) -> Result<(), P2PError> {
        if !self.running {
            return Err(P2PError::NotRunning);
        }
        let peer = peer_id
            .parse::<PeerId>()
            .map_err(|e| P2PError::PeerNotFound(format!("invalid peer id: {}", e)))?;
        let _ = self.command_tx.send(Command::ConnectPeer(peer));
        Ok(())
    }

    #[instrument(skip(self, data))]
    pub async fn send_data(&mut self, peer_id: &str, data: Vec<u8>) -> Result<(), P2PError> {
        if !self.running {
            return Err(P2PError::NotRunning);
        }
        let peer = peer_id
            .parse::<PeerId>()
            .map_err(|e| P2PError::PeerNotFound(format!("invalid peer id: {}", e)))?;
        let _ = self.command_tx.send(Command::SendData(peer, data));
        Ok(())
    }

    pub fn on_data_received(&mut self, callback: Box<dyn Fn(String, Vec<u8>) + Send + Sync>) {
        self.data_callback = Some(callback);
    }

    pub fn local_peer_id(&self) -> &str {
        &self.local_peer_id
    }

    pub fn is_running(&self) -> bool {
        self.running
    }

    pub fn connected_peers(&self) -> Vec<&PeerInfo> {
        self.peers
            .values()
            .filter(|p| p.connected_at.is_some())
            .collect()
    }

    pub async fn poll_events(&mut self) -> Option<P2PEvent> {
        self.event_rx.recv().await
    }

    pub async fn broadcast(&mut self, topic: &str, data: Vec<u8>) -> Result<(), P2PError> {
        if !self.running {
            return Err(P2PError::NotRunning);
        }
        let _ = self.command_tx.send(Command::Broadcast(topic.to_string(), data));
        Ok(())
    }

    pub fn process_events(&mut self) {
        while let Ok(event) = self.event_rx.try_recv() {
            if let P2PEvent::PeerConnected { ref peer_id } = event {
                let info = self.peers.entry(peer_id.clone()).or_insert_with(|| PeerInfo {
                    peer_id: peer_id.clone(),
                    addresses: Vec::new(),
                    connected_at: None,
                });
                info.connected_at = Some(Utc::now());
            }
            if let P2PEvent::PeerDisconnected { ref peer_id } = event {
                if let Some(info) = self.peers.get_mut(peer_id) {
                    info.connected_at = None;
                }
            }
            if let P2PEvent::PeerDiscovered {
                ref peer_id,
                ref addresses,
            } = event
            {
                let info = self.peers.entry(peer_id.clone()).or_insert_with(|| PeerInfo {
                    peer_id: peer_id.clone(),
                    addresses: Vec::new(),
                    connected_at: None,
                });
                info.addresses = addresses.clone();
            }
            if let P2PEvent::DataReceived { ref peer_id, ref data } = event {
                if let Some(ref callback) = self.data_callback {
                    callback(peer_id.clone(), data.clone());
                }
            }
        }
    }
}

async fn event_loop(
    mut swarm: libp2p::Swarm<DevnoteBehaviour>,
    mut command_rx: mpsc::UnboundedReceiver<Command>,
    event_tx: mpsc::UnboundedSender<P2PEvent>,
) {
    loop {
        tokio::select! {
            event = swarm.select_next_some() => {
                handle_swarm_event(event, &mut swarm, &event_tx);
            }
            command = command_rx.recv() => {
                match command {
                    Some(Command::Stop) => break,
                    Some(Command::DiscoverPeers) => {
                        let _ = swarm.behaviour_mut().kademlia.bootstrap();
                    }
                    Some(Command::ConnectPeer(peer_id)) => {
                        let _ = swarm.dial(DialOpts::peer_id(peer_id).build());
                    }
                    Some(Command::SendData(peer_id, data)) => {
                        let topic = IdentTopic::new(format!("direct-{}", peer_id));
                        let _ = swarm.behaviour_mut().gossipsub.publish(topic, data);
                    }
                    Some(Command::Broadcast(topic, data)) => {
                        let topic = IdentTopic::new(topic);
                        let _ = swarm.behaviour_mut().gossipsub.publish(topic, data);
                    }
                    None => break,
                }
            }
        }
    }
}

fn handle_swarm_event(
    event: SwarmEvent<DevnoteBehaviourEvent>,
    swarm: &mut libp2p::Swarm<DevnoteBehaviour>,
    event_tx: &mpsc::UnboundedSender<P2PEvent>,
) {
    match event {
        SwarmEvent::ConnectionEstablished { peer_id, .. } => {
            let _ = event_tx.send(P2PEvent::PeerConnected {
                peer_id: peer_id.to_string(),
            });
        }
        SwarmEvent::ConnectionClosed { peer_id, .. } => {
            let _ = event_tx.send(P2PEvent::PeerDisconnected {
                peer_id: peer_id.to_string(),
            });
        }
        SwarmEvent::Behaviour(behaviour_event) => match behaviour_event {
            DevnoteBehaviourEvent::Kademlia(kad_event) => match kad_event {
                kad::Event::RoutingUpdated { peer, .. } => {
                    let _ = event_tx.send(P2PEvent::PeerDiscovered {
                        peer_id: peer.to_string(),
                        addresses: Vec::new(),
                    });
                }
                _ => {}
            },
            DevnoteBehaviourEvent::Gossipsub(gs_event) => match gs_event {
                gossipsub::Event::Message {
                    propagation_source,
                    message,
                    ..
                } => {
                    let _ = event_tx.send(P2PEvent::DataReceived {
                        peer_id: propagation_source.to_string(),
                        data: message.data,
                    });
                }
                _ => {}
            },
            DevnoteBehaviourEvent::Identify(id_event) => match id_event {
                identify::Event::Received { peer_id, info, .. } => {
                    for addr in info.listen_addrs {
                        swarm
                            .behaviour_mut()
                            .kademlia
                            .add_address(&peer_id, addr);
                    }
                }
                _ => {}
            },
            DevnoteBehaviourEvent::Ping(_) => {}
        },
        _ => {}
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalingConfig {
    pub server_url: String,
    pub auth_token: Option<String>,
}

impl Default for SignalingConfig {
    fn default() -> Self {
        Self {
            server_url: "https://signal.devnote.app".to_string(),
            auth_token: None,
        }
    }
}

pub trait SignalingClient: Send + Sync {
    fn register(&self, peer_id: &str, public_key: &[u8], addresses: &[String]) -> Result<(), P2PError>;
    fn resolve(&self, peer_id: &str) -> Result<PeerInfo, P2PError>;
    fn request_nat_traversal(&self, peer_id: &str) -> Result<Vec<String>, P2PError>;
}

pub struct DefaultSignalingClient {
    _config: SignalingConfig,
}

impl DefaultSignalingClient {
    pub fn new(config: SignalingConfig) -> Self {
        Self { _config: config }
    }
}

impl SignalingClient for DefaultSignalingClient {
    fn register(&self, _peer_id: &str, _public_key: &[u8], _addresses: &[String]) -> Result<(), P2PError> {
        Ok(())
    }

    fn resolve(&self, _peer_id: &str) -> Result<PeerInfo, P2PError> {
        Err(P2PError::SignalingError("not implemented".to_string()))
    }

    fn request_nat_traversal(&self, _peer_id: &str) -> Result<Vec<String>, P2PError> {
        Err(P2PError::SignalingError("not implemented".to_string()))
    }
}
