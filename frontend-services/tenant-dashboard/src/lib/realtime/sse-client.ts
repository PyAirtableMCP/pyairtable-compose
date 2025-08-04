import { RealtimeEvent, EventListener, ConnectionState, RetryConfig } from "./events"
import { trackEvent } from "@/app/posthog-provider"
import { handleAsyncError } from "@/components/error-boundary"

interface SSEClientOptions {
  url: string
  headers?: Record<string, string>
  retry?: Partial<RetryConfig>
  reconnectOnError?: boolean
  heartbeatInterval?: number
  maxMessageQueue?: number
}

const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxAttempts: 5,
  baseDelay: 1000,
  maxDelay: 30000,
  backoffFactor: 2,
}

export class SSEClient {
  private eventSource: EventSource | null = null
  private listeners = new Map<string, Set<EventListener>>()
  private state: ConnectionState = "disconnected"
  private retryConfig: RetryConfig
  private retryCount = 0
  private retryTimer: NodeJS.Timeout | null = null
  private heartbeatTimer: NodeJS.Timeout | null = null
  private messageQueue: RealtimeEvent[] = []
  private lastHeartbeat = 0

  constructor(private options: SSEClientOptions) {
    this.retryConfig = { ...DEFAULT_RETRY_CONFIG, ...options.retry }
  }

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.state === "connected" || this.state === "connecting") {
        resolve()
        return
      }

      this.setState("connecting")
      
      try {
        // Construct URL with authentication if available
        const url = new URL(this.options.url)
        
        // Add session ID for tracking
        const sessionId = crypto.randomUUID()
        url.searchParams.set("sessionId", sessionId)
        
        this.eventSource = new EventSource(url.toString())

        // Connection opened
        this.eventSource.onopen = () => {
          this.setState("connected")
          this.retryCount = 0
          this.startHeartbeat()
          
          trackEvent("sse_connected", {
            url: this.options.url,
            retry_count: this.retryCount,
          })
          
          resolve()
        }

        // Message received
        this.eventSource.onmessage = (event) => {
          this.handleMessage(event)
        }

        // Error occurred
        this.eventSource.onerror = (error) => {
          this.handleError(error)
          
          if (this.state === "connecting") {
            reject(new Error("Failed to connect to SSE endpoint"))
          }
        }

        // Handle custom event types
        this.setupCustomEventHandlers()

      } catch (error) {
        this.setState("error")
        reject(error)
      }
    })
  }

  disconnect(): void {
    this.clearRetryTimer()
    this.clearHeartbeatTimer()
    
    if (this.eventSource) {
      this.eventSource.close()
      this.eventSource = null
    }
    
    this.setState("disconnected")
    
    trackEvent("sse_disconnected", {
      url: this.options.url,
      was_connected: this.state === "connected",
    })
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

  private setupCustomEventHandlers(): void {
    if (!this.eventSource) return

    // Handle different event types
    const eventTypes = [
      "chat.message",
      "chat.stream", 
      "chat.typing",
      "notification",
      "data.update",
      "sync.status",
      "feature.flag",
      "auth.status"
    ]

    eventTypes.forEach(eventType => {
      this.eventSource!.addEventListener(eventType, (event) => {
        this.handleMessage(event as MessageEvent, eventType)
      })
    })

    // Handle heartbeat
    this.eventSource.addEventListener("heartbeat", () => {
      this.lastHeartbeat = Date.now()
    })
  }

  private handleMessage(event: MessageEvent, eventType?: string): void {
    try {
      const data = JSON.parse(event.data)
      
      const realtimeEvent: RealtimeEvent = {
        id: data.id || crypto.randomUUID(),
        type: eventType || data.type || "unknown",
        timestamp: data.timestamp || Date.now(),
        userId: data.userId,
        sessionId: data.sessionId,
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
        `sse-message-parsing:${eventType || "unknown"}`
      )
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
            `sse-event-listener:${event.type}`
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
            "sse-wildcard-listener"
          )
        }
      })
    }
  }

  private handleError(error: Event): void {
    const errorEvent = error as any
    
    handleAsyncError(
      new Error(`SSE Connection Error: ${errorEvent.message || "Unknown error"}`),
      "sse-connection"
    )

    if (this.options.reconnectOnError && this.state === "connected") {
      this.setState("reconnecting")
      this.scheduleReconnect()
    } else {
      this.setState("error")
    }
  }

  private scheduleReconnect(): void {
    if (this.retryCount >= this.retryConfig.maxAttempts) {
      this.setState("error")
      
      trackEvent("sse_max_retries_exceeded", {
        url: this.options.url,
        retry_count: this.retryCount,
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

    trackEvent("sse_reconnect_scheduled", {
      url: this.options.url,
      retry_count: this.retryCount,
      delay,
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

  private setState(newState: ConnectionState): void {
    if (this.state !== newState) {
      const oldState = this.state
      this.state = newState
      
      // Emit connection status event
      const connectionEvent: RealtimeEvent = {
        id: crypto.randomUUID(),
        type: "connection.status",
        timestamp: Date.now(),
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

    this.heartbeatTimer = setInterval(() => {
      const now = Date.now()
      const timeSinceLastHeartbeat = now - this.lastHeartbeat

      // If no heartbeat received in 2x the interval, consider connection stale
      if (timeSinceLastHeartbeat > this.options.heartbeatInterval! * 2) {
        this.handleError(new Event("Heartbeat timeout"))
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