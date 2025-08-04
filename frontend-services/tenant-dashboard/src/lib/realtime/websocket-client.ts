import { RealtimeEvent, EventListener, ConnectionState, RetryConfig } from "./events"
import { trackEvent } from "@/app/posthog-provider"
import { handleAsyncError } from "@/components/error-boundary"

interface WebSocketClientOptions {
  url: string
  protocols?: string[]
  headers?: Record<string, string>
  retry?: Partial<RetryConfig>
  reconnectOnError?: boolean
  heartbeatInterval?: number
  maxMessageQueue?: number
  binaryType?: "blob" | "arraybuffer"
}

const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxAttempts: 5,
  baseDelay: 1000,
  maxDelay: 30000,
  backoffFactor: 2,
}

export class WebSocketClient {
  private ws: WebSocket | null = null
  private listeners = new Map<string, Set<EventListener>>()
  private state: ConnectionState = "disconnected"
  private retryConfig: RetryConfig
  private retryCount = 0
  private retryTimer: NodeJS.Timeout | null = null
  private heartbeatTimer: NodeJS.Timeout | null = null
  private messageQueue: RealtimeEvent[] = []
  private lastPong = 0
  private sessionId: string

  constructor(private options: WebSocketClientOptions) {
    this.retryConfig = { ...DEFAULT_RETRY_CONFIG, ...options.retry }
    this.sessionId = crypto.randomUUID()
  }

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.state === "connected" || this.state === "connecting") {
        resolve()
        return
      }

      this.setState("connecting")
      
      try {
        // Construct WebSocket URL with authentication if available
        const url = new URL(this.options.url)
        url.searchParams.set("sessionId", this.sessionId)
        
        this.ws = new WebSocket(
          url.toString(), 
          this.options.protocols
        )

        if (this.options.binaryType) {
          this.ws.binaryType = this.options.binaryType
        }

        // Connection opened
        this.ws.onopen = () => {
          this.setState("connected")
          this.retryCount = 0
          this.startHeartbeat()
          
          // Send authentication if headers provided
          if (this.options.headers) {
            this.send({
              type: "auth",
              data: this.options.headers,
            })
          }
          
          trackEvent("websocket_connected", {
            url: this.options.url,
            retry_count: this.retryCount,
            session_id: this.sessionId,
          })
          
          resolve()
        }

        // Message received
        this.ws.onmessage = (event) => {
          this.handleMessage(event)
        }

        // Connection closed
        this.ws.onclose = (event) => {
          this.handleClose(event)
        }

        // Error occurred
        this.ws.onerror = (error) => {
          this.handleError(error)
          
          if (this.state === "connecting") {
            reject(new Error("Failed to connect to WebSocket endpoint"))
          }
        }

      } catch (error) {
        this.setState("error")
        reject(error)
      }
    })
  }

  disconnect(): void {
    this.clearRetryTimer()
    this.clearHeartbeatTimer()
    
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.close(1000, "Client disconnect")
    }
    
    this.ws = null
    this.setState("disconnected")
    
    trackEvent("websocket_disconnected", {
      url: this.options.url,
      session_id: this.sessionId,
    })
  }

  send(data: any): boolean {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try {
        const message = typeof data === "string" ? data : JSON.stringify(data)
        this.ws.send(message)
        return true
      } catch (error) {
        handleAsyncError(error as Error, "websocket-send")
        return false
      }
    }
    return false
  }

  on<T extends RealtimeEvent>(eventType: string, listener: EventListener<T>): void {
    if (!this.listeners.has(eventType)) {
      this.listeners.set(eventType, new Set())
    }
    this.listeners.get(eventType)!.add(listener as EventListener)
  }

  off<T extends RealtimeEvent>(eventType: string, listener: EventListener<T>): void {
    const listeners = this.listeners.get(eventType)
    if (listeners) {
      listeners.delete(listener as EventListener)
      if (listeners.size === 0) {
        this.listeners.delete(eventType)
      }
    }
  }

  getState(): ConnectionState {
    return this.state
  }

  getQueuedMessages(): readonly RealtimeEvent[] {
    return [...this.messageQueue]
  }

  clearQueue(): void {
    this.messageQueue = []
  }

  private handleMessage(event: MessageEvent): void {
    try {
      // Handle different data types
      let data: any
      
      if (typeof event.data === "string") {
        try {
          data = JSON.parse(event.data)
        } catch {
          // Handle plain text messages
          data = { content: event.data }
        }
      } else if (event.data instanceof ArrayBuffer || event.data instanceof Blob) {
        // Handle binary data - convert to base64 for now
        data = { 
          binary: true, 
          data: event.data instanceof ArrayBuffer 
            ? Array.from(new Uint8Array(event.data))
            : event.data 
        }
      } else {
        data = event.data
      }

      // Handle special control messages
      if (data.type === "pong") {
        this.lastPong = Date.now()
        return
      }

      const realtimeEvent: RealtimeEvent = {
        id: data.id || crypto.randomUUID(),
        type: data.type || "message",
        timestamp: data.timestamp || Date.now(),
        userId: data.userId,
        sessionId: data.sessionId || this.sessionId,
        data: data.data || data,
      } as RealtimeEvent

      // Add to queue if max queue size not exceeded
      if (this.messageQueue.length < (this.options.maxMessageQueue || 100)) {
        this.messageQueue.push(realtimeEvent)
      }

      // Emit to listeners
      this.emit(realtimeEvent)

    } catch (error) {
      handleAsyncError(
        error as Error, 
        "websocket-message-parsing"
      )
    }
  }

  private handleClose(event: CloseEvent): void {
    const wasConnected = this.state === "connected"
    
    trackEvent("websocket_closed", {
      url: this.options.url,
      code: event.code,
      reason: event.reason,
      was_clean: event.wasClean,
      was_connected: wasConnected,
      session_id: this.sessionId,
    })

    if (this.options.reconnectOnError && wasConnected && event.code !== 1000) {
      // Don't reconnect on normal closure (code 1000)
      this.setState("reconnecting")
      this.scheduleReconnect()
    } else {
      this.setState("disconnected")
    }
  }

  private handleError(error: Event): void {
    handleAsyncError(
      new Error(`WebSocket Error: ${error.type}`),
      "websocket-connection"
    )

    if (this.state === "connected") {
      this.setState("reconnecting")
      this.scheduleReconnect()
    } else {
      this.setState("error")
    }
  }

  private scheduleReconnect(): void {
    if (this.retryCount >= this.retryConfig.maxAttempts) {
      this.setState("error")
      
      trackEvent("websocket_max_retries_exceeded", {
        url: this.options.url,
        retry_count: this.retryCount,
        session_id: this.sessionId,
      })
      
      return
    }

    const delay = Math.min(
      this.retryConfig.baseDelay * Math.pow(this.retryConfig.backoffFactor, this.retryCount),
      this.retryConfig.maxDelay
    )

    this.retryTimer = setTimeout(() => {
      this.retryCount++
      this.reconnect()
    }, delay)

    trackEvent("websocket_reconnect_scheduled", {
      url: this.options.url,
      retry_count: this.retryCount,
      delay,
      session_id: this.sessionId,
    })
  }

  private async reconnect(): Promise<void> {
    this.disconnect()
    
    try {
      await this.connect()
    } catch (error) {
      this.handleError(error as Event)
    }
  }

  private emit(event: RealtimeEvent): void {
    // Emit to specific event type listeners
    const listeners = this.listeners.get(event.type)
    if (listeners) {
      listeners.forEach(listener => {
        try {
          listener(event)
        } catch (error) {
          handleAsyncError(
            error as Error,
            `websocket-event-listener:${event.type}`
          )
        }
      })
    }

    // Emit to wildcard listeners
    const wildcardListeners = this.listeners.get("*")
    if (wildcardListeners) {
      wildcardListeners.forEach(listener => {
        try {
          listener(event)
        } catch (error) {
          handleAsyncError(
            error as Error,
            "websocket-wildcard-listener"
          )
        }
      })
    }
  }

  private setState(newState: ConnectionState): void {
    if (this.state !== newState) {
      const oldState = this.state
      this.state = newState
      
      // Emit connection status event
      const connectionEvent: RealtimeEvent = {
        id: crypto.randomUUID(),
        type: "connection.status",
        timestamp: Date.now(),
        sessionId: this.sessionId,
        data: {
          status: newState,
          reason: oldState !== "disconnected" ? `Transitioned from ${oldState}` : undefined,
        },
      } as any

      this.emit(connectionEvent)
    }
  }

  private startHeartbeat(): void {
    if (!this.options.heartbeatInterval) return

    this.lastPong = Date.now()
    
    this.heartbeatTimer = setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        // Send ping
        this.send({ type: "ping", timestamp: Date.now() })
        
        // Check if pong was received
        const now = Date.now()
        const timeSinceLastPong = now - this.lastPong

        // If no pong received in 2x the interval, consider connection stale
        if (timeSinceLastPong > this.options.heartbeatInterval! * 2) {
          this.handleError(new Event("Heartbeat timeout"))
        }
      }
    }, this.options.heartbeatInterval)
  }

  private clearRetryTimer(): void {
    if (this.retryTimer) {
      clearTimeout(this.retryTimer)
      this.retryTimer = null
    }
  }

  private clearHeartbeatTimer(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer)
      this.heartbeatTimer = null
    }
  }
}