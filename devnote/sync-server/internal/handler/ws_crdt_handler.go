// Package handler provides HTTP/WebSocket handlers for the sync server.
//
// P0 架构修复 (P3): WebSocket CRDT 实时协同编辑
// 基于 WebSocket 的 CRDT 文档同步中心，支持多用户实时协作编辑同一笔记。
// 设计参考：AppFlowy 的 CollabPlugins、Yjs 的 y-websocket provider。
package handler

import (
	"encoding/json"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// CRDTMessage 表示客户端与服务端之间的 CRDT 同步消息
// 格式兼容 Yjs 的 sync protocol（sync1/sync2/update）
type CRDTMessage struct {
	// Type 消息类型: "sync1" (请求同步), "sync2" (响应同步), "update" (增量更新)
	Type string `json:"type"`
	// DocID 文档标识符（笔记 ID）
	DocID string `json:"doc_id"`
	// Data 序列化的 CRDT 更新数据（base64 编码的 Yjs/CRDT 二进制）
	Data string `json:"data,omitempty"`
	// ClientID 客户端唯一标识
	ClientID string `json:"client_id"`
	// Clock 客户端逻辑时钟（用于冲突检测）
	Clock uint64 `json:"clock"`
}

// CRDTHub 管理所有活跃 WebSocket 连接的 CRDT 同步中心
//
// 每个文档 (docID) 维护一个房间 (room)，房间内所有客户端通过 broadcast 接收更新。
// 服务端不执行 CRDT 合并 —— 仅作为中继（relay）转发更新。
// 服务端同时持久化最新的 CRDT 状态快照，供新客户端接入时同步。
type CRDTHub struct {
	// rooms 文档 → 客户端连接集合
	rooms map[string]map[*websocket.Conn]bool
	// docStates 文档 → 最新 CRDT 状态（base64 编码的二进制）
	docStates map[string]string
	// clientClocks 客户端 → 逻辑时钟
	clientClocks map[*websocket.Conn]uint64
	mu           sync.RWMutex
	logger       *zap.Logger
}

// NewCRDTHub 创建 CRDT 同步中心
func NewCRDTHub(logger *zap.Logger) *CRDTHub {
	return &CRDTHub{
		rooms:        make(map[string]map[*websocket.Conn]bool),
		docStates:    make(map[string]string),
		clientClocks: make(map[*websocket.Conn]uint64),
		logger:       logger,
	}
}

// JoinRoom 客户端加入文档协作房间
func (h *CRDTHub) JoinRoom(docID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.rooms[docID] == nil {
		h.rooms[docID] = make(map[*websocket.Conn]bool)
	}
	h.rooms[docID][conn] = true
	h.logger.Info("client joined CRDT room",
		zap.String("doc_id", docID),
		zap.Int("room_size", len(h.rooms[docID])))
}

// LeaveRoom 客户端离开文档协作房间
func (h *CRDTHub) LeaveRoom(docID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.rooms[docID] != nil {
		delete(h.rooms[docID], conn)
		if len(h.rooms[docID]) == 0 {
			delete(h.rooms, docID)
		}
	}
	delete(h.clientClocks, conn)
	h.logger.Info("client left CRDT room", zap.String("doc_id", docID))
}

// BroadcastUpdate 向房间内除发送者外的所有客户端广播 CRDT 更新
func (h *CRDTHub) BroadcastUpdate(docID string, sender *websocket.Conn, msg *CRDTMessage) {
	h.mu.RLock()
	room, exists := h.rooms[docID]
	h.mu.RUnlock()

	if !exists {
		return
	}

	// 服务端作为中继，不解析 CRDT 数据，仅转发
	data, err := json.Marshal(msg)
	if err != nil {
		h.logger.Error("failed to marshal CRDT message", zap.Error(err))
		return
	}

	h.mu.RLock()
	clients := make([]*websocket.Conn, 0, len(room))
	for conn := range room {
		if conn != sender {
			clients = append(clients, conn)
		}
	}
	h.mu.RUnlock()

	for _, conn := range clients {
		if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
			h.logger.Warn("failed to broadcast CRDT update", zap.Error(err))
		}
	}
}

// SendSyncResponse 向新客户端发送当前文档的完整 CRDT 状态
func (h *CRDTHub) SendSyncResponse(docID string, conn *websocket.Conn) {
	h.mu.RLock()
	state, hasState := h.docStates[docID]
	h.mu.RUnlock()

	msg := CRDTMessage{
		Type:   "sync2",
		DocID:  docID,
		Data:   state,
		Clock:  0,
	}

	if !hasState {
		// 文档无状态，发送空同步响应
		msg.Data = ""
	}

	data, err := json.Marshal(msg)
	if err != nil {
		h.logger.Error("failed to marshal sync response", zap.Error(err))
		return
	}

	if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
		h.logger.Warn("failed to send sync response", zap.Error(err))
	}
}

// SaveDocState 保存文档的最新 CRDT 状态快照
func (h *CRDTHub) SaveDocState(docID string, state string) {
	h.mu.Lock()
	h.docStates[docID] = state
	h.mu.Unlock()
}

// GetDocState 获取文档的 CRDT 状态快照
func (h *CRDTHub) GetDocState(docID string) string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.docStates[docID]
}

// RoomSize 获取房间内客户端数量
func (h *CRDTHub) RoomSize(docID string) int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if room, exists := h.rooms[docID]; exists {
		return len(room)
	}
	return 0
}

// ── WebSocket 升级器 ──────────────────────────────────────────────────

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// 允许所有来源（生产环境应限制为白名单域名）
	CheckOrigin: func(r *gin.Context) bool {
		// 生产环境应从配置读取允许的来源
		return true
	},
}

// HandleCRDTWebSocket 处理 WebSocket CRDT 连接
//
// 路由: GET /api/v1/ws/crdt/:doc_id
// 请求头: Authorization: Bearer <token>
// 查询参数: client_id (可选)
//
// 协议:
//  1. 客户端连接后发送 "sync1" 请求
//  2. 服务端返回 "sync2" 响应（包含当前文档状态）
//  3. 客户端编辑时发送 "update" 消息
//  4. 服务端广播 "update" 到房间内其他客户端
//  5. 客户端断开连接时自动离开房间
func HandleCRDTWebSocket(hub *CRDTHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		docID := c.Param("doc_id")
		if docID == "" {
			c.JSON(400, gin.H{"error": "missing doc_id"})
			return
		}

		userID := c.GetString("user_id")
		clientID := c.Query("client_id")
		if clientID == "" {
			clientID = userID
		}

		conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
		if err != nil {
			hub.logger.Error("failed to upgrade WebSocket", zap.Error(err))
			return
		}
		defer conn.Close()

		hub.JoinRoom(docID, conn)
		defer hub.LeaveRoom(docID, conn)

		hub.logger.Info("CRDT WebSocket connection established",
				zap.String("doc_id", docID),
				zap.String("client_id", clientID))

		// 发送初始同步状态
		hub.SendSyncResponse(docID, conn)

		for {
			_, message, err := conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
					hub.logger.Warn("WebSocket read error", zap.Error(err))
				}
				break
			}

			var msg CRDTMessage
			if err := json.Unmarshal(message, &msg); err != nil {
				hub.logger.Warn("invalid CRDT message", zap.Error(err))
				continue
			}

			msg.ClientID = clientID

			switch msg.Type {
			case "sync1":
				// 客户端请求同步 → 发送完整状态
				hub.SendSyncResponse(docID, conn)

			case "update":
				// 客户端发送增量更新 → 广播给其他客户端
				hub.BroadcastUpdate(docID, conn, &msg)
				// 定期保存状态快照（每 N 次更新保存一次）
				hub.SaveDocState(docID, msg.Data)

			default:
				hub.logger.Warn("unknown CRDT message type", zap.String("type", msg.Type))
			}
		}
	}
}