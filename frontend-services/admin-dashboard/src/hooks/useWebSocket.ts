import { useEffect, useRef, useState, useCallback } from 'react'
import { io, Socket } from 'socket.io-client'
import { RealtimeUpdate, WebSocketMessage } from '@/types'

interface UseWebSocketOptions {
  url?: string
  autoConnect?: boolean
  onMessage?: (message: WebSocketMessage) => void
  onConnect?: () => void
  onDisconnect?: () => void
  onError?: (error: any) => void
}

export function useWebSocket(options: UseWebSocketOptions = {}) {
  const {
    url = process.env.NEXT_PUBLIC_WS_URL || 'ws://localhost:8080',
    autoConnect = true,
    onMessage,
    onConnect,
    onDisconnect,
    onError,
  } = options

  const [isConnected, setIsConnected] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const socketRef = useRef<Socket | null>(null)

  const connect = useCallback(() => {
    if (socketRef.current?.connected) return

    try {
      const token = localStorage.getItem('auth_token')
      socketRef.current = io(url, {
        auth: { token },
        transports: ['websocket'],
      })

      socketRef.current.on('connect', () => {
        setIsConnected(true)
        setError(null)
        onConnect?.()
      })

      socketRef.current.on('disconnect', () => {
        setIsConnected(false)
        onDisconnect?.()
      })

      socketRef.current.on('connect_error', (err) => {
        setError(err.message)
        setIsConnected(false)
        onError?.(err)
      })

      socketRef.current.on('message', (message: WebSocketMessage) => {
        onMessage?.(message)
      })

      // Listen for specific update types
      socketRef.current.on('realtime_update', (update: RealtimeUpdate) => {
        onMessage?.({
          type: 'realtime_update',
          payload: update,
          timestamp: new Date().toISOString(),
        })
      })

    } catch (err) {
      setError(err instanceof Error ? err.message : 'Connection failed')
      onError?.(err)
    }
  }, [url, onConnect, onDisconnect, onError, onMessage])

  const disconnect = useCallback(() => {
    socketRef.current?.disconnect()
    socketRef.current = null
    setIsConnected(false)
  }, [])

  const send = (event: string, data: any) => {
    if (socketRef.current?.connected) {
      socketRef.current.emit(event, data)
    }
  }

  const subscribe = (room: string) => {
    if (socketRef.current?.connected) {
      socketRef.current.emit('join_room', room)
    }
  }

  const unsubscribe = (room: string) => {
    if (socketRef.current?.connected) {
      socketRef.current.emit('leave_room', room)
    }
  }

  useEffect(() => {
    if (autoConnect) {
      connect()
    }

    return () => {
      disconnect()
    }
  }, [autoConnect, url, connect, disconnect])

  return {
    isConnected,
    error,
    connect,
    disconnect,
    send,
    subscribe,
    unsubscribe,
  }
}