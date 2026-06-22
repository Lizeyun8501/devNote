// 实时协作 WebSocket handler
//
// 实现 DevNote 客户端实时协作（RealtimeCollabService / RealtimeTransport）
// 所需的 WebSocket 服务端，消息协议与客户端 realtime_transport.dart 对齐。
//
// 借鉴项目：
// - **Yjs y-websocket** ([GitHub](https://github.com/yjs/y-websocket)):
//   心跳保活 + 自动重连 + 操作广播的传输层模式。
// - **Logseq RTC** ([GitHub](https://github.com/logseq/logseq)):
//   WebSocket + 操作广播的实时协作，按笔记划分协作房间。
//
// 设计要点：
// 1. CollaborationHub 按 noteID 管理多个 CollaborationRoom，room 空时自动回收。
// 2. 消息字段名使用 camelCase，与客户端 Dart 协议完全一致。
// 3. 并发安全：Hub 与 Room 均使用 sync.RWMutex，广播时先拷贝客户端列表再发送，
//    避免持锁发送导致死锁。
// 4. 资源清理：连接断开时从 room 移除客户端、广播 presence leave、关闭连接。
package handler

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/devnote/sync-server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// 连接与心跳相关常量
//
// 借鉴 Yjs y-websocket 的超时策略：读超时略大于客户端心跳间隔的 3 倍，
// 允许偶尔的心跳丢失而不误断连接。
const (
	// pongWait 读超时：客户端心跳 30s，允许错过 2 次（90s）
	pongWait = 90 * time.Second
	// pingPeriod 服务端 ping 间隔，须小于 pongWait
	pingPeriod = 60 * time.Second
	// writeWait 单次 WebSocket 写操作的超时
	writeWait = 10 * time.Second
	// sendBufferSize 每个客户端发送 channel 的缓冲大小
	sendBufferSize = 256
	// maxOpHistory 每个 room 缓存的最近操作数（用于 sync_request 响应）
	maxOpHistory = 1000
)

// 消息类型常量（与客户端 realtime_transport.dart 的 RealtimeMessageType.label 对齐）
const (
	msgJoin         = "join"
	msgOp           = "op"
	msgPresence     = "presence"
	msgSyncRequest  = "sync_request"
	msgSyncResponse = "sync_response"
	msgHeartbeat    = "heartbeat"
)

// upgrader 将 HTTP 连接升级为 WebSocket
//
// P1 修复 (SEC-04): 原实现 CheckOrigin 恒返回 true，允许任意 origin 建立
// WebSocket 连接，存在 CSRF 风险。现改为校验 Origin 是否在白名单内。
// allowedOrigins 通过 SetupCheckOrigin 注入。
var allowedOrigins = []string{"*"}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		// 无 Origin 头（非浏览器客户端，如 curl）允许通过
		if origin == "" {
			return true
		}
		// P1 修复: 校验 Origin 是否在白名单内
		for _, allowed := range allowedOrigins {
			if allowed == "*" || allowed == origin {
				return true
			}
		}
		return false
	},
}

// SetupCheckOrigin 注入允许的 Origin 白名单
// P1 修复 (SEC-04): 由 main.go 在启动时调用，注入 config.AllowedOrigins
func SetupCheckOrigin(origins []string) {
	allowedOrigins = origins
}

// RealtimeHandler 处理 WebSocket 实时协作连接
type RealtimeHandler struct {
	authService *service.AuthService
	hub         *CollaborationHub
	// P2 修复 (P2-9): 注入 zap 结构化日志替代 log.Printf，便于统一收集和关联 Request ID
	logger *zap.Logger
}

// CollaborationHub 管理所有活跃的协作连接（按 noteID 分房间）
type CollaborationHub struct {
	mu    sync.RWMutex
	rooms map[string]*CollaborationRoom // noteID -> room
}

// CollaborationRoom 一个笔记的协作房间
type CollaborationRoom struct {
	mu        sync.RWMutex
	noteID    string
	clients   map[*websocket.Conn]*Client
	opHistory [][]byte // 最近操作的原始 JSON（用于 sync_request 响应）
}

// Client 一个 WebSocket 客户端
type Client struct {
	conn     *websocket.Conn
	userID   string
	username string
	deviceID string
	noteID   string
	send     chan []byte
	room     *CollaborationRoom
	presence []byte // 最近一次 presence state 的原始 JSON
	done     chan struct{}
	// P2 修复 (P2-9): 持有 logger 引用，供 readPump/writePump 记录结构化日志
	logger *zap.Logger
}

// WSMessage WebSocket 消息协议
//
// 字段名使用 camelCase，与客户端 realtime_transport.dart /
// realtime_collab_service.dart 中的消息格式完全对齐：
//   - join:        {type, noteId, deviceId, userId, name}
//   - op:          {type, operation}
//   - presence:    {type, state}
//   - sync_request:{type, since, deviceId, noteId}
//   - sync_response:{type, operations}
//   - join ack:    {type, peers}
//   - heartbeat:   {type, timestamp}
type WSMessage struct {
	Type       string          `json:"type"`
	NoteID     string          `json:"noteId,omitempty"`
	UserID     string          `json:"userId,omitempty"`
	DeviceID   string          `json:"deviceId,omitempty"`
	Name       string          `json:"name,omitempty"`
	Operation  json.RawMessage `json:"operation,omitempty"`
	State      json.RawMessage `json:"state,omitempty"`
	Since      json.RawMessage `json:"since,omitempty"`
	Operations json.RawMessage `json:"operations,omitempty"`
	Peers      json.RawMessage `json:"peers,omitempty"`
	Timestamp  int64           `json:"timestamp,omitempty"`
}

// NewRealtimeHandler 构造 RealtimeHandler
// P2 修复 (P2-9): 接收 zap.Logger 注入，替代包级 log.Printf
func NewRealtimeHandler(authService *service.AuthService, logger *zap.Logger) *RealtimeHandler {
	if logger == nil {
		logger = zap.NewNop()
	}
	return &RealtimeHandler{
		authService: authService,
		hub: &CollaborationHub{
			rooms: make(map[string]*CollaborationRoom),
		},
		logger: logger,
	}
}

// Connect WebSocket 升级入口（gin.HandlerFunc）
//
// 流程：
// 1. 从 query param `token` 获取 JWT 并校验（WebSocket 无法使用标准 Bearer header）
// 2. 升级 HTTP 为 WebSocket
// 3. 读取客户端首条 join 消息，获取 noteID / deviceID / username
// 4. 将客户端加入对应 room
// 5. 发送 join ack（携带当前在线协作者列表）
// 6. 广播 presence 通知其他客户端有新成员加入
// 7. 启动读循环和写循环 goroutine
func (h *RealtimeHandler) Connect(c *gin.Context) {
	// 1. 从 query param 获取 JWT 并校验
	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
		return
	}
	claims, err := h.authService.ValidateToken(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}

	// 2. 升级 HTTP 为 WebSocket
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		h.logger.Warn("websocket upgrade failed", zap.Error(err))
		return
	}

	// 3. 读取客户端首条 join 消息
	conn.SetReadDeadline(time.Now().Add(pongWait))
	_, raw, err := conn.ReadMessage()
	if err != nil {
		h.logger.Warn("failed to read join message", zap.Error(err))
		conn.Close()
		return
	}

	var joinMsg WSMessage
	if err := json.Unmarshal(raw, &joinMsg); err != nil || joinMsg.Type != msgJoin {
		h.logger.Warn("first message is not a valid join", zap.String("type", joinMsg.Type), zap.Error(err))
		conn.Close()
		return
	}

	noteID := joinMsg.NoteID
	if noteID == "" {
		h.logger.Warn("join message missing noteId")
		conn.Close()
		return
	}

	// 优先使用 join 消息中的字段，缺失时回退到 JWT claims
	deviceID := joinMsg.DeviceID
	userID := joinMsg.UserID
	if userID == "" {
		userID = claims.UserID
	}
	username := joinMsg.Name
	if username == "" {
		username = claims.Username
	}

	// 4. 获取或创建 room，加入客户端
	room := h.hub.getOrCreateRoom(noteID)
	client := &Client{
		conn:     conn,
		userID:   userID,
		username: username,
		deviceID: deviceID,
		noteID:   noteID,
		send:     make(chan []byte, sendBufferSize),
		room:     room,
		done:     make(chan struct{}),
		logger:   h.logger,
	}
	room.addClient(client)

	h.logger.Info("client joined",
		zap.String("user", userID),
		zap.String("device", deviceID),
		zap.String("note", noteID))

	// 5. 发送 join ack（包含当前在线协作者列表）
	h.sendJoinAck(client)

	// 6. 广播 presence 通知其他客户端有新成员加入
	room.broadcastPresence(client, true)

	// 7. 启动读循环和写循环
	go client.writePump()
	go client.readPump(h.hub)
}

// sendJoinAck 向新加入的客户端发送 join 确认，携带当前在线协作者列表
func (h *RealtimeHandler) sendJoinAck(client *Client) {
	peers := client.room.buildPeersList(client)
	peersJSON, err := json.Marshal(peers)
	if err != nil {
		return
	}
	ack := WSMessage{
		Type:  msgJoin,
		Peers: peersJSON,
	}
	data, err := json.Marshal(ack)
	if err != nil {
		return
	}
	select {
	case client.send <- data:
	default:
	}
}

// --- Client 方法 ---

// readPump 读循环：持续读取 WebSocket 消息并分发处理
//
// 连接断开（读错误或正常关闭）时执行清理。
func (c *Client) readPump(hub *CollaborationHub) {
	defer func() {
		c.cleanup(hub)
	}()

	conn := c.conn
	conn.SetReadDeadline(time.Now().Add(pongWait))
	// Pong 处理器：收到客户端 pong 后重置读超时
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				c.logger.Warn("read error",
					zap.String("user", c.userID),
					zap.String("device", c.deviceID),
					zap.Error(err))
			}
			return
		}

		// 解析消息类型
		var msg WSMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			c.logger.Warn("invalid json from client", zap.String("device", c.deviceID), zap.Error(err))
			continue
		}

		// 任何消息都视为连接活跃，重置读超时
		conn.SetReadDeadline(time.Now().Add(pongWait))

		switch msg.Type {
		case msgOp:
			c.handleOp(raw)
		case msgPresence:
			c.handlePresence(raw, &msg)
		case msgSyncRequest:
			c.handleSyncRequest()
		case msgHeartbeat:
			c.handleHeartbeat()
		case msgJoin:
			// 后续 join 消息忽略（首条 join 已在 Connect 中处理）
		default:
			c.logger.Warn("unknown message type", zap.String("type", msg.Type))
		}
	}
}

// handleOp 处理 op 消息：缓存到操作历史并广播给同 room 其他客户端
func (c *Client) handleOp(raw []byte) {
	room := c.room
	room.cacheOp(raw)
	room.broadcast(raw, c)
}

// handlePresence 处理 presence 消息：更新本地状态并广播给同 room 其他客户端
func (c *Client) handlePresence(raw []byte, msg *WSMessage) {
	if len(msg.State) > 0 {
		c.presence = msg.State
	}
	c.room.broadcast(raw, c)
}

// handleSyncRequest 处理 sync_request：返回 room 最近的操作历史
//
// 简化实现：返回内存中缓存的全部操作，客户端 OpLog 会自动去重。
func (c *Client) handleSyncRequest() {
	ops := c.room.getOpHistory()
	opsJSON, err := json.Marshal(ops)
	if err != nil {
		return
	}
	resp := WSMessage{
		Type:       msgSyncResponse,
		Operations: opsJSON,
	}
	data, err := json.Marshal(resp)
	if err != nil {
		return
	}
	select {
	case c.send <- data:
	default:
	}
}

// handleHeartbeat 处理心跳：回复 heartbeat
func (c *Client) handleHeartbeat() {
	resp := WSMessage{
		Type:      msgHeartbeat,
		Timestamp: time.Now().UnixMilli(),
	}
	data, err := json.Marshal(resp)
	if err != nil {
		return
	}
	select {
	case c.send <- data:
	default:
	}
}

// writePump 写循环：从 send channel 读取消息写入 WebSocket
//
// 借鉴 gorilla/websocket 官方 chat 示例的写循环模式：
// - 每次写操作前设置写超时
// - 定期发送 ping 维持连接
// - done channel 关闭时立即退出
func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case <-c.done:
			return
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// cleanup 连接断开时的清理：从 room 移除、广播 presence leave、关闭连接
func (c *Client) cleanup(hub *CollaborationHub) {
	room := c.room
	room.removeClient(c)
	hub.removeClientIfEmpty(room.noteID)
	// 广播 presence leave 给剩余客户端
	room.broadcastPresence(c, false)
	// 关闭 done channel 通知 writePump 退出
	close(c.done)
	// 关闭 WebSocket 连接
	c.conn.Close()
	c.logger.Info("client left",
		zap.String("user", c.userID),
		zap.String("device", c.deviceID),
		zap.String("note", c.noteID))
}

// --- CollaborationRoom 方法 ---

// addClient 将客户端加入房间
func (r *CollaborationRoom) addClient(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.clients[c.conn] = c
}

// removeClient 将客户端从房间移除
func (r *CollaborationRoom) removeClient(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.clients, c.conn)
}

// broadcast 广播消息给 room 内除发送者外的所有客户端
//
// 先在锁内拷贝客户端列表，释放锁后再发送，避免持锁发送导致死锁。
// 发送缓冲已满的客户端视为慢消费者，关闭其连接。
func (r *CollaborationRoom) broadcast(message []byte, sender *Client) {
	r.mu.RLock()
	clients := make([]*Client, 0, len(r.clients))
	for _, c := range r.clients {
		if c == sender {
			continue
		}
		clients = append(clients, c)
	}
	r.mu.RUnlock()

	for _, c := range clients {
		select {
		case c.send <- message:
		default:
			// 发送缓冲已满，关闭慢消费者
			c.logger.Warn("send buffer full, closing client", zap.String("device", c.deviceID))
			go c.conn.Close()
		}
	}
}

// broadcastPresence 广播 presence 更新（加入/离开）
//
// join=true 表示新成员加入，join=false 表示成员离开（last_seen=0 使客户端判定离线）。
func (r *CollaborationRoom) broadcastPresence(client *Client, join bool) {
	state := map[string]interface{}{
		"user_id":   client.userID,
		"device_id": client.deviceID,
		"name":      client.username,
	}
	if join {
		state["last_seen"] = time.Now().UnixMilli()
		// 如果客户端已有 presence 状态（如重连后），合并使用
		if len(client.presence) > 0 {
			var existing map[string]interface{}
			if err := json.Unmarshal(client.presence, &existing); err == nil {
				for k, v := range existing {
					state[k] = v
				}
			}
		}
	} else {
		// 离开时设置 last_seen=0，客户端 PresenceState.isOnline 据此判定离线
		state["last_seen"] = 0
	}

	stateJSON, err := json.Marshal(state)
	if err != nil {
		return
	}
	msg := WSMessage{
		Type:  msgPresence,
		State: stateJSON,
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	r.broadcast(data, client)
}

// buildPeersList 构建当前 room 内除指定客户端外的协作者列表
//
// 用于 join ack，每个 peer 至少包含 user_id / device_id / name，
// 若该客户端曾发送 presence 则合并其完整状态。
func (r *CollaborationRoom) buildPeersList(exclude *Client) []map[string]interface{} {
	r.mu.RLock()
	defer r.mu.RUnlock()

	peers := make([]map[string]interface{}, 0, len(r.clients))
	for _, c := range r.clients {
		if c == exclude {
			continue
		}
		peer := map[string]interface{}{
			"user_id":   c.userID,
			"device_id": c.deviceID,
			"name":      c.username,
		}
		if len(c.presence) > 0 {
			var p map[string]interface{}
			if err := json.Unmarshal(c.presence, &p); err == nil {
				for k, v := range p {
					peer[k] = v
				}
			}
		}
		peers = append(peers, peer)
	}
	return peers
}

// cacheOp 缓存最近操作（用于 sync_request 响应），超过上限时丢弃最旧的操作
func (r *CollaborationRoom) cacheOp(raw []byte) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.opHistory = append(r.opHistory, raw)
	if len(r.opHistory) > maxOpHistory {
		r.opHistory = r.opHistory[len(r.opHistory)-maxOpHistory:]
	}
}

// getOpHistory 获取缓存的操作历史（返回副本避免并发修改）
func (r *CollaborationRoom) getOpHistory() [][]byte {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([][]byte, len(r.opHistory))
	copy(result, r.opHistory)
	return result
}

// --- CollaborationHub 方法 ---

// getOrCreateRoom 获取或创建 room
func (h *CollaborationHub) getOrCreateRoom(noteID string) *CollaborationRoom {
	h.mu.Lock()
	defer h.mu.Unlock()
	room, ok := h.rooms[noteID]
	if !ok {
		room = &CollaborationRoom{
			noteID:  noteID,
			clients: make(map[*websocket.Conn]*Client),
		}
		h.rooms[noteID] = room
	}
	return room
}

// removeClientIfEmpty 当 room 为空时从 hub 中删除 room
func (h *CollaborationHub) removeClientIfEmpty(noteID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if room, ok := h.rooms[noteID]; ok {
		room.mu.RLock()
		empty := len(room.clients) == 0
		room.mu.RUnlock()
		if empty {
			delete(h.rooms, noteID)
		}
	}
}
