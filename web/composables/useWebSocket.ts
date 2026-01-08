import type { NoteDTO } from '~/types'

export type WSMessageType =
  | 'note_created'
  | 'note_updated'
  | 'note_deleted'
  | 'sync_request'
  | 'sync_response'
  | 'ping'
  | 'pong'

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected'

export interface WSMessage {
  type: WSMessageType
  payload?: unknown
}

export interface NoteChangePayload {
  note: NoteDTO
}

export interface NoteDeletePayload {
  noteId: string
}

// Shared state across all components
const socket = ref<WebSocket | null>(null)
const connectionStatus = ref<ConnectionStatus>('disconnected')
const reconnectAttempts = ref(0)

const MAX_RECONNECT_ATTEMPTS = 5
const INITIAL_RECONNECT_DELAY = 1000
const PING_INTERVAL = 30000

let reconnectTimeout: ReturnType<typeof setTimeout> | null = null
let pingInterval: ReturnType<typeof setInterval> | null = null
let reconnectDelay = INITIAL_RECONNECT_DELAY

// WebSocket authentication protocol name (must match server)
const WS_AUTH_PROTOCOL = 'access_token'

export function useWebSocket() {
  const config = useRuntimeConfig()

  const connect = (token: string) => {
    if (!token || socket.value?.readyState === WebSocket.OPEN) {
      return
    }

    connectionStatus.value = 'connecting'

    // Convert HTTP URL to WebSocket URL (without token in URL for security)
    const baseUrl = config.public.apiBase as string
    const wsUrl = baseUrl.replace(/^http/, 'ws') + '/api/ws'

    try {
      // Use Sec-WebSocket-Protocol header for authentication
      // Format: ["access_token", "<actual-token>"]
      // This is more secure than query params as it's not logged in URLs
      socket.value = new WebSocket(wsUrl, [WS_AUTH_PROTOCOL, token])

      socket.value.onopen = handleOpen
      socket.value.onmessage = handleMessage
      socket.value.onclose = handleClose
      socket.value.onerror = handleError
    } catch (error) {
      console.error('WebSocket connection error:', error)
      connectionStatus.value = 'disconnected'
      attemptReconnect(token)
    }
  }

  const handleOpen = () => {
    console.log('WebSocket connected')
    connectionStatus.value = 'connected'
    reconnectAttempts.value = 0
    reconnectDelay = INITIAL_RECONNECT_DELAY
    startPingInterval()
  }

  const handleMessage = (event: MessageEvent) => {
    try {
      const message: WSMessage = JSON.parse(event.data)
      processMessage(message)
    } catch (error) {
      console.error('Failed to parse WebSocket message:', error)
    }
  }

  const processMessage = (message: WSMessage) => {
    const notesStore = useNotesStore()

    switch (message.type) {
      case 'note_created':
      case 'note_updated': {
        const payload = message.payload as NoteChangePayload
        if (payload?.note) {
          notesStore.upsertFromDTO(payload.note)
        }
        break
      }

      case 'note_deleted': {
        const payload = message.payload as NoteDeletePayload
        if (payload?.noteId) {
          const index = notesStore.notes.findIndex(n => n.id === payload.noteId)
          if (index !== -1) {
            notesStore.notes.splice(index, 1)
          }
        }
        break
      }

      case 'pong':
        // Connection is alive, nothing to do
        break

      default:
        console.log('Unknown WebSocket message type:', message.type)
    }
  }

  const handleClose = (event: CloseEvent) => {
    console.log('WebSocket closed:', event.code, event.reason)
    connectionStatus.value = 'disconnected'
    stopPingInterval()

    // Only attempt reconnect if not a clean close
    if (event.code !== 1000) {
      const authStore = useAuthStore()
      if (authStore.token) {
        attemptReconnect(authStore.token)
      }
    }
  }

  const handleError = (event: Event) => {
    console.error('WebSocket error:', event)
    // onclose will be called after onerror
  }

  const attemptReconnect = (token: string) => {
    if (reconnectAttempts.value >= MAX_RECONNECT_ATTEMPTS) {
      console.log('Max reconnect attempts reached')
      return
    }

    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout)
    }

    reconnectTimeout = setTimeout(() => {
      console.log(`Reconnecting... attempt ${reconnectAttempts.value + 1}`)
      reconnectAttempts.value++
      reconnectDelay = Math.min(reconnectDelay * 2, 30000) // Max 30s delay
      connect(token)
    }, reconnectDelay)
  }

  const disconnect = () => {
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout)
      reconnectTimeout = null
    }
    stopPingInterval()

    if (socket.value) {
      socket.value.close(1000, 'Client disconnect')
      socket.value = null
    }
    connectionStatus.value = 'disconnected'
    reconnectAttempts.value = 0
    reconnectDelay = INITIAL_RECONNECT_DELAY
  }

  const sendMessage = (message: WSMessage) => {
    if (socket.value?.readyState === WebSocket.OPEN) {
      socket.value.send(JSON.stringify(message))
    }
  }

  const sendPing = () => {
    sendMessage({ type: 'ping' })
  }

  const startPingInterval = () => {
    stopPingInterval()
    pingInterval = setInterval(sendPing, PING_INTERVAL)
  }

  const stopPingInterval = () => {
    if (pingInterval) {
      clearInterval(pingInterval)
      pingInterval = null
    }
  }

  return {
    socket: readonly(socket),
    connectionStatus: readonly(connectionStatus),
    reconnectAttempts: readonly(reconnectAttempts),
    connect,
    disconnect,
    sendMessage
  }
}
