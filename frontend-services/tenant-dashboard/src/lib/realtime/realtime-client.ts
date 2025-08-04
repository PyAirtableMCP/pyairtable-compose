import { RealtimeEvent, EventListener, ConnectionState } from "./events"
import { SSEClient } from "./sse-client"
import { WebSocketClient } from "./websocket-client"
import { trackEvent } from "@/app/posthog-provider"

type TransportType = "sse" | "websocket" | "auto"

interface RealtimeClientOptions {
  baseUrl: string
  transport?: TransportType
  fallbackTransport?: boolean
  auth?: {
    getToken: () => Promise<string | null>
    headers?: Record<string, string>
  }
  reconnectOnError?: boolean
  heartbeatInterval?: number
  maxMessageQueue?: number
}

export class RealtimeClient {
  private client: SSEClient | WebSocketClient | null = null
  private currentTransport: TransportType | null = null
  private listeners = new Map<string, Set<EventListener>>()
  private connectionListeners = new Set<(state: ConnectionState) => void>()
  private options: RealtimeClientOptions
  private isConnecting = false

  constructor(options: RealtimeClientOptions) {
    this.options = {
      transport: "auto",
      fallbackTransport: true,
      reconnectOnError: true,
      heartbeatInterval: 30000, // 30 seconds
      maxMessageQueue: 100,
      ...options,
    }
  }

  async connect(): Promise<void> {
    if (this.isConnecting || this.client?.getState() === "connected") {
      return
    }

    this.isConnecting = true

    try {
      const transport = await this.selectTransport()
      await this.connectWithTransport(transport)
      
      trackEvent("realtime_connected", {
        transport: this.currentTransport,
        base_url: this.options.baseUrl,
      })
    } catch (error) {
      if (this.options.fallbackTransport && this.currentTransport !== "sse") {
        // Fallback to SSE if WebSocket fails
        try {
          await this.connectWithTransport("sse")
          
          trackEvent("realtime_fallback_success", {
            original_transport: this.currentTransport,
            fallback_transport: "sse",
          })
        } catch (fallbackError) {
          this.isConnecting = false
          throw fallbackError
        }
      } else {
        this.isConnecting = false
        throw error
      }
    }

    this.isConnecting = false
  }

  disconnect(): void {
    if (this.client) {
      this.client.disconnect()
      this.client = null
      this.currentTransport = null
    }
  }

  send(data: any): boolean {
    if (this.client instanceof WebSocketClient) {
      return this.client.send(data)
    }
    
    // SSE doesn't support sending data
    console.warn("Cannot send data via SSE transport")
    return false
  }

  on<T extends RealtimeEvent>(eventType: string, listener: EventListener<T>): void {
    // Store listener for future connections
    if (!this.listeners.has(eventType)) {
      this.listeners.set(eventType, new Set())
    }
    this.listeners.get(eventType)!.add(listener as EventListener)

    // Forward to current client if connected
    if (this.client) {
      this.client.on(eventType, listener)
    }
  }

  off<T extends RealtimeEvent>(eventType: string, listener: EventListener<T>): void {
    // Remove from stored listeners
    const listeners = this.listeners.get(eventType)
    if (listeners) {
      listeners.delete(listener as EventListener)
      if (listeners.size === 0) {
        this.listeners.delete(eventType)
      }
    }

    // Forward to current client if connected
    if (this.client) {
      this.client.off(eventType, listener)
    }
  }

  onConnectionStateChange(listener: (state: ConnectionState) => void): void {
    this.connectionListeners.add(listener)
  }

  offConnectionStateChange(listener: (state: ConnectionState) => void): void {
    this.connectionListeners.delete(listener)
  }

  getState(): ConnectionState {
    return this.client?.getState() || "disconnected"
  }

  getTransport(): TransportType | null {
    return this.currentTransport
  }

  getQueuedMessages(): readonly RealtimeEvent[] {
    return this.client?.getQueuedMessages() || []
  }

  clearQueue(): void {
    this.client?.clearQueue()
  }

  private async selectTransport(): Promise<TransportType> {
    if (this.options.transport !== "auto") {
      return this.options.transport
    }

    // Auto-detect best transport
    if (typeof WebSocket !== "undefined") {
      // Check if WebSocket is supported and not blocked
      try {
        const testWs = new WebSocket("ws://localhost:0")
        testWs.close()
        return "websocket"
      } catch {
        // WebSocket not available or blocked, fallback to SSE
        return "sse"
      }
    } else {
      // No WebSocket support, use SSE
      return "sse"
    }
  }

  private async connectWithTransport(transport: TransportType): Promise<void> {
    this.currentTransport = transport

    // Get authentication headers
    const headers: Record<string, string> = {}
    
    if (this.options.auth?.getToken) {
      const token = await this.options.auth.getToken()
      if (token) {
        headers.Authorization = `Bearer ${token}`
      }
    }

    if (this.options.auth?.headers) {
      Object.assign(headers, this.options.auth.headers)
    }

    // Create appropriate client
    if (transport === "websocket") {
      const wsUrl = this.options.baseUrl.replace(/^http/, "ws") + "/ws"
      
      this.client = new WebSocketClient({
        url: wsUrl,
        headers,
        reconnectOnError: this.options.reconnectOnError,
        heartbeatInterval: this.options.heartbeatInterval,
        maxMessageQueue: this.options.maxMessageQueue,
      })
    } else {
      const sseUrl = this.options.baseUrl + "/events"
      
      this.client = new SSEClient({
        url: sseUrl,
        headers,
        reconnectOnError: this.options.reconnectOnError,
        heartbeatInterval: this.options.heartbeatInterval,
        maxMessageQueue: this.options.maxMessageQueue,
      })
    }

    // Forward stored listeners to new client
    this.listeners.forEach((listeners, eventType) => {
      listeners.forEach(listener => {
        this.client!.on(eventType, listener)
      })
    })

    // Set up connection state monitoring
    this.client.on("connection.status", (event) => {
      this.connectionListeners.forEach(listener => {
        try {
          listener(event.data.status)
        } catch (error) {
          console.error("Connection state listener error:", error)
        }
      })
    })

    // Connect
    await this.client.connect()
  }
}

// React hook for using realtime client
import { useEffect, useRef, useState } from "react"
import { useSession } from "next-auth/react"

export function useRealtimeClient(options?: Partial<RealtimeClientOptions>) {
  const { data: session } = useSession()
  const clientRef = useRef<RealtimeClient | null>(null)
  const [connectionState, setConnectionState] = useState<ConnectionState>("disconnected")
  const [isConnecting, setIsConnecting] = useState(false)

  // Initialize client
  useEffect(() => {
    if (!clientRef.current && session?.user) {
      const client = new RealtimeClient({
        baseUrl: process.env.NEXT_PUBLIC_REALTIME_URL || "http://localhost:8080/realtime",
        auth: {
          getToken: async () => {
            // Get fresh access token for real-time connection
            return session.accessToken || null
          },
          headers: {
            "X-User-ID": session.user.id,
            "X-Session-ID": crypto.randomUUID(),
          },
        },
        ...options,
      })

      client.onConnectionStateChange(setConnectionState)
      clientRef.current = client
    }

    return () => {
      if (clientRef.current) {
        clientRef.current.disconnect()
        clientRef.current = null
      }
    }
  }, [session, options])

  // Auto-connect when authenticated
  useEffect(() => {
    if (clientRef.current && session?.user && connectionState === "disconnected") {
      setIsConnecting(true)
      clientRef.current.connect()
        .catch(error => {
          console.error("Failed to connect to realtime service:", error)
        })
        .finally(() => {
          setIsConnecting(false)
        })
    }
  }, [session, connectionState])

  const connect = async () => {
    if (clientRef.current) {
      setIsConnecting(true)
      try {
        await clientRef.current.connect()
      } finally {
        setIsConnecting(false)
      }
    }
  }

  const disconnect = () => {
    if (clientRef.current) {
      clientRef.current.disconnect()
    }
  }

  const send = (data: any) => {
    return clientRef.current?.send(data) || false
  }

  const subscribe = <T extends RealtimeEvent>(
    eventType: string, 
    listener: EventListener<T>
  ) => {
    if (clientRef.current) {
      clientRef.current.on(eventType, listener)
      
      return () => {
        clientRef.current?.off(eventType, listener)
      }
    }
    
    return () => {}
  }

  return {
    client: clientRef.current,
    connectionState,
    isConnecting,
    transport: clientRef.current?.getTransport(),
    connect,
    disconnect,
    send,
    subscribe,
  }
}