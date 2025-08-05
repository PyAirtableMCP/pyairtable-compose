"use client"

import React, { useState, useRef, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ScrollArea } from "@/components/ui/scroll-area"
import { 
  Send, 
  Loader2, 
  Bot, 
  User, 
  AlertCircle, 
  Wifi, 
  WifiOff,
  Zap
} from "lucide-react"
import { useRealtimeClient } from "@/lib/realtime/realtime-client"
import { ChatMessageEvent, ChatStreamEvent, ConnectionState } from "@/lib/realtime/events"
import { useSession } from "next-auth/react"
// Temporarily disabled: import { trackEvent } from "@/app/posthog-provider"
import { cn } from "@/lib/utils"

interface ChatMessage {
  id: string
  content: string
  role: "user" | "assistant" | "system"
  timestamp: number
  status: "pending" | "streaming" | "completed" | "error"
  metadata?: Record<string, any>
}

interface ChatInterfaceProps {
  className?: string
  placeholder?: string
  maxMessages?: number
  showConnectionStatus?: boolean
  autoScroll?: boolean
}

export function ChatInterface({
  className,
  placeholder = "Ask anything about your data...",
  maxMessages = 100,
  showConnectionStatus = true,
  autoScroll = true,
}: ChatInterfaceProps) {
  const { data: session } = useSession()
  const { connectionState, send, subscribe, transport } = useRealtimeClient()
  
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: "welcome",
      content: "Hello! I'm your PyAirtable AI assistant. I can help you query your data, create formulas, and analyze information. What would you like to know?",
      role: "assistant",
      timestamp: Date.now(),
      status: "completed",
    }
  ])
  
  const [inputValue, setInputValue] = useState("")
  const [isTyping, setIsTyping] = useState(false)
  const [currentStreamingMessage, setCurrentStreamingMessage] = useState<string | null>(null)
  
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  // Subscribe to real-time events
  useEffect(() => {
    const unsubscribeChatMessage = subscribe<ChatMessageEvent>("chat.message", (event) => {
      setMessages(prev => {
        const existing = prev.find(m => m.id === event.data.id)
        if (existing) {
          // Update existing message
          return prev.map(m => 
            m.id === event.data.id 
              ? { ...m, ...event.data, timestamp: event.timestamp }
              : m
          )
        } else {
          // Add new message
          const newMessage: ChatMessage = {
            id: event.data.id,
            content: event.data.content,
            role: event.data.role,
            timestamp: event.timestamp,
            status: event.data.status,
            metadata: event.data.metadata,
          }
          
          return [...prev.slice(-maxMessages + 1), newMessage]
        }
      })
    })

    const unsubscribeChatStream = subscribe<ChatStreamEvent>("chat.stream", (event) => {
      if (event.data.isComplete) {
        setCurrentStreamingMessage(null)
        setIsTyping(false)
        
        // Update message status to completed
        setMessages(prev => 
          prev.map(m => 
            m.id === event.data.messageId 
              ? { ...m, status: "completed" }
              : m
          )
        )
      } else {
        // Update streaming content
        setMessages(prev => 
          prev.map(m => {
            if (m.id === event.data.messageId) {
              return {
                ...m,
                content: m.content + event.data.chunk,
                status: "streaming"
              }
            }
            return m
          })
        )
        
        setCurrentStreamingMessage(event.data.messageId)
        setIsTyping(true)
      }
    })

    return () => {
      unsubscribeChatMessage()
      unsubscribeChatStream()
    }
  }, [subscribe, maxMessages])

  // Auto-scroll to bottom
  useEffect(() => {
    if (autoScroll && messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: "smooth" })
    }
  }, [messages, autoScroll])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!inputValue.trim() || connectionState !== "connected") {
      return
    }

    const messageId = crypto.randomUUID()
    const userMessage: ChatMessage = {
      id: messageId,
      content: inputValue.trim(),
      role: "user",
      timestamp: Date.now(),
      status: "completed",
    }

    // Add user message immediately
    setMessages(prev => [...prev.slice(-maxMessages + 1), userMessage])
    setInputValue("")
    setIsTyping(true)

    // Track chat interaction
    // Temporarily disabled: trackEvent("chat_message_sent", {
    //   message_length: userMessage.content.length,
    //   user_id: session?.user?.id,
    // })

    // Send message via real-time connection
    const success = send({
      type: "chat.message",
      data: {
        id: messageId,
        content: userMessage.content,
        role: "user",
        metadata: {
          sessionId: session?.user?.id,
          timestamp: Date.now(),
        },
      },
    })

    if (!success) {
      // Fallback to HTTP API if real-time fails
      try {
        const response = await fetch("/api/chat/message", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: userMessage.content,
            messageId,
          }),
        })

        if (!response.ok) {
          throw new Error("Failed to send message")
        }

        // Response will come via real-time events
      } catch (error) {
        console.error("Failed to send chat message:", error)
        
        // Add error message
        const errorMessage: ChatMessage = {
          id: crypto.randomUUID(),
          content: "Sorry, I couldn't process your message. Please try again.",
          role: "assistant",
          timestamp: Date.now(),
          status: "error",
        }
        
        setMessages(prev => [...prev, errorMessage])
        setIsTyping(false)
      }
    }

    // Focus back to input
    setTimeout(() => inputRef.current?.focus(), 100)
  }

  const getConnectionStatusColor = (state: ConnectionState) => {
    switch (state) {
      case "connected": return "text-green-600"
      case "connecting": return "text-yellow-600"
      case "reconnecting": return "text-orange-600"
      case "disconnected": return "text-gray-600"
      case "error": return "text-red-600"
      default: return "text-gray-600"
    }
  }

  const getConnectionStatusIcon = (state: ConnectionState) => {
    switch (state) {
      case "connected": return <Wifi className="h-4 w-4" />
      case "connecting": return <Loader2 className="h-4 w-4 animate-spin" />
      case "reconnecting": return <Loader2 className="h-4 w-4 animate-spin" />
      case "disconnected": return <WifiOff className="h-4 w-4" />
      case "error": return <AlertCircle className="h-4 w-4" />
      default: return <WifiOff className="h-4 w-4" />
    }
  }

  return (
    <Card className={cn("flex flex-col h-full max-h-[600px]", className)}>
      <CardHeader className="flex-shrink-0 pb-4">
        <div className="flex items-center justify-between">
          <CardTitle className="flex items-center gap-2">
            <Bot className="h-5 w-5" />
            PyAirtable Assistant
          </CardTitle>
          
          {showConnectionStatus && (
            <div className="flex items-center gap-2">
              <Badge 
                variant="outline" 
                className={cn("text-xs", getConnectionStatusColor(connectionState))}
              >
                {getConnectionStatusIcon(connectionState)}
                <span className="ml-1 capitalize">{connectionState}</span>
              </Badge>
              
              {transport && (
                <Badge variant="secondary" className="text-xs">
                  {transport === "websocket" ? "WS" : "SSE"}
                </Badge>
              )}
            </div>
          )}
        </div>
      </CardHeader>

      <CardContent className="flex-1 flex flex-col min-h-0 p-0">
        <ScrollArea className="flex-1 p-4">
          <div className="space-y-4">
            {messages.map((message) => (
              <div
                key={message.id}
                className={cn(
                  "flex gap-3 max-w-full",
                  message.role === "user" ? "justify-end" : "justify-start"
                )}
              >
                {message.role !== "user" && (
                  <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                    <Bot className="h-4 w-4 text-primary" />
                  </div>
                )}
                
                <div
                  className={cn(
                    "rounded-lg px-4 py-2 max-w-[80%] break-words",
                    message.role === "user"
                      ? "bg-primary text-primary-foreground ml-auto"
                      : "bg-muted",
                    message.status === "error" && "bg-destructive/10 border border-destructive/20"
                  )}
                >
                  <div className="text-sm">
                    {message.content}
                    {message.status === "streaming" && (
                      <span className="inline-block w-2 h-4 bg-current animate-pulse ml-1" />
                    )}
                  </div>
                  
                  {message.status === "error" && (
                    <div className="flex items-center gap-1 mt-1 text-xs text-destructive">
                      <AlertCircle className="h-3 w-3" />
                      <span>Failed to send</span>
                    </div>
                  )}
                  
                  {message.metadata?.actions && message.metadata.actions.length > 0 && (
                    <div className="flex gap-2 mt-2">
                      {message.metadata.actions.map((action: any, index: number) => (
                        <Button
                          key={index}
                          size="sm"
                          variant="outline"
                          className="h-6 text-xs"
                          onClick={() => {
                            // Temporarily disabled: trackEvent("chat_action_clicked", {
                            //   action: action.action,
                            //   message_id: message.id,
                            // })
                            // Handle action
                          }}
                        >
                          {action.label}
                        </Button>
                      ))}
                    </div>
                  )}
                </div>

                {message.role === "user" && (
                  <div className="flex-shrink-0 w-8 h-8 rounded-full bg-secondary flex items-center justify-center">
                    <User className="h-4 w-4" />
                  </div>
                )}
              </div>
            ))}
            
            {isTyping && !currentStreamingMessage && (
              <div className="flex gap-3 justify-start">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                  <Bot className="h-4 w-4 text-primary" />
                </div>
                <div className="bg-muted rounded-lg px-4 py-2">
                  <div className="flex space-x-1">
                    <div className="w-2 h-2 bg-muted-foreground rounded-full animate-bounce" />
                    <div className="w-2 h-2 bg-muted-foreground rounded-full animate-bounce" style={{animationDelay: "0.1s"}} />
                    <div className="w-2 h-2 bg-muted-foreground rounded-full animate-bounce" style={{animationDelay: "0.2s"}} />
                  </div>
                </div>
              </div>
            )}
            
            <div ref={messagesEndRef} />
          </div>
        </ScrollArea>

        <div className="flex-shrink-0 p-4 border-t">
          {connectionState !== "connected" && (
            <Alert className="mb-4">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>
                {connectionState === "connecting" && "Connecting to assistant..."}
                {connectionState === "reconnecting" && "Reconnecting to assistant..."}
                {connectionState === "disconnected" && "Disconnected from assistant. Some features may not work."}
                {connectionState === "error" && "Connection error. Please refresh the page."}
              </AlertDescription>
            </Alert>
          )}
          
          <form onSubmit={handleSubmit} className="flex gap-2">
            <Input
              ref={inputRef}
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              placeholder={placeholder}
              disabled={connectionState !== "connected" || isTyping}
              className="flex-1"
              maxLength={2000}
            />
            <Button 
              type="submit" 
              disabled={!inputValue.trim() || connectionState !== "connected" || isTyping}
              size="icon"
            >
              {isTyping ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Send className="h-4 w-4" />
              )}
            </Button>
          </form>
          
          <div className="flex items-center justify-between mt-2 text-xs text-muted-foreground">
            <span>
              {inputValue.length}/2000 characters
            </span>
            <div className="flex items-center gap-1">
              <Zap className="h-3 w-3" />
              <span>Powered by AI</span>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}