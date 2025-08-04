// Event types for real-time communication
export interface BaseEvent {
  id: string
  type: string
  timestamp: number
  userId?: string
  sessionId?: string
}

// Chat Events
export interface ChatMessageEvent extends BaseEvent {
  type: "chat.message"
  data: {
    id: string
    content: string
    role: "user" | "assistant" | "system"
    status: "pending" | "streaming" | "completed" | "error"
    metadata?: Record<string, any>
  }
}

export interface ChatStreamEvent extends BaseEvent {
  type: "chat.stream"
  data: {
    messageId: string
    chunk: string
    isComplete: boolean
    metadata?: Record<string, any>
  }
}

export interface ChatTypingEvent extends BaseEvent {
  type: "chat.typing"
  data: {
    isTyping: boolean
    userName?: string
  }
}

// System Events
export interface ConnectionEvent extends BaseEvent {
  type: "connection.status"
  data: {
    status: "connected" | "disconnected" | "reconnecting" | "error"
    reason?: string
  }
}

export interface NotificationEvent extends BaseEvent {
  type: "notification"
  data: {
    title: string
    message: string
    level: "info" | "success" | "warning" | "error"
    actions?: Array<{
      label: string
      action: string
      data?: any
    }>
  }
}

// Data Events
export interface DataUpdateEvent extends BaseEvent {
  type: "data.update"
  data: {
    resource: string
    operation: "create" | "update" | "delete"
    payload: any
    version?: number
  }
}

export interface SyncStatusEvent extends BaseEvent {
  type: "sync.status"
  data: {
    resource: string
    status: "syncing" | "synced" | "error"
    progress?: number
    error?: string
  }
}

// Feature Flag Events
export interface FeatureFlagEvent extends BaseEvent {
  type: "feature.flag"
  data: {
    flag: string
    value: any
    changed: boolean
  }
}

// Authentication Events
export interface AuthStatusEvent extends BaseEvent {
  type: "auth.status"
  data: {
    status: "authenticated" | "unauthenticated" | "expired"
    user?: {
      id: string
      email: string
      name?: string
    }
  }
}

// Union type for all events
export type RealtimeEvent = 
  | ChatMessageEvent
  | ChatStreamEvent 
  | ChatTypingEvent
  | ConnectionEvent
  | NotificationEvent
  | DataUpdateEvent
  | SyncStatusEvent
  | FeatureFlagEvent
  | AuthStatusEvent

// Event listener types
export type EventListener<T extends RealtimeEvent = RealtimeEvent> = (event: T) => void

// Connection states
export type ConnectionState = "connecting" | "connected" | "disconnected" | "reconnecting" | "error"

// Retry configuration
export interface RetryConfig {
  maxAttempts: number
  baseDelay: number
  maxDelay: number
  backoffFactor: number
}