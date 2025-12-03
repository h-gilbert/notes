package websocket

import (
	"sync"

	"github.com/google/uuid"
)

// Hub maintains the set of active clients and broadcasts messages to them.
type Hub struct {
	// Clients mapped by userID -> connectionID -> Client
	clients map[uuid.UUID]map[string]*Client

	// Register requests from clients
	register chan *Client

	// Unregister requests from clients
	unregister chan *Client

	// Mutex for thread-safe access to clients map
	mu sync.RWMutex
}

// BroadcastMessage represents a message to broadcast to a user's connections
type BroadcastMessage struct {
	UserID    uuid.UUID
	Message   []byte
	ExcludeID string // Connection ID to exclude (the sender)
}

// NewHub creates a new Hub instance
func NewHub() *Hub {
	return &Hub{
		clients:    make(map[uuid.UUID]map[string]*Client),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
}

// Run starts the hub's main event loop
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.registerClient(client)
		case client := <-h.unregister:
			h.unregisterClient(client)
		}
	}
}

// Register adds a client to the hub
func (h *Hub) Register(client *Client) {
	h.register <- client
}

// Unregister removes a client from the hub
func (h *Hub) Unregister(client *Client) {
	h.unregister <- client
}

func (h *Hub) registerClient(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.clients[client.UserID] == nil {
		h.clients[client.UserID] = make(map[string]*Client)
	}
	h.clients[client.UserID][client.ID] = client
}

func (h *Hub) unregisterClient(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if userClients, ok := h.clients[client.UserID]; ok {
		if _, ok := userClients[client.ID]; ok {
			delete(userClients, client.ID)
			close(client.Send)

			// Clean up empty user map
			if len(userClients) == 0 {
				delete(h.clients, client.UserID)
			}
		}
	}
}

// BroadcastToUser sends a message to all connections for a given user
// optionally excluding a specific connection (e.g., the sender)
func (h *Hub) BroadcastToUser(userID uuid.UUID, message []byte, excludeConnID string) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if userClients, ok := h.clients[userID]; ok {
		for connID, client := range userClients {
			if connID == excludeConnID {
				continue
			}
			select {
			case client.Send <- message:
			default:
				// Client's send buffer is full, skip this message
				// The client will reconnect and sync if needed
			}
		}
	}
}

// GetConnectionCount returns the number of active connections for a user
func (h *Hub) GetConnectionCount(userID uuid.UUID) int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if userClients, ok := h.clients[userID]; ok {
		return len(userClients)
	}
	return 0
}

// GetTotalConnections returns the total number of active connections
func (h *Hub) GetTotalConnections() int {
	h.mu.RLock()
	defer h.mu.RUnlock()

	total := 0
	for _, userClients := range h.clients {
		total += len(userClients)
	}
	return total
}
