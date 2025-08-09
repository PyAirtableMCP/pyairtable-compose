import { useState, useEffect, useRef } from "react"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Badge } from "@/components/ui/badge"
import { ChatMessage, type Message } from "./ChatMessage"
import { ChatInput } from "./ChatInput"
import { ChatSidebar, type Conversation } from "./ChatSidebar"
import { Loader2, AlertCircle } from "lucide-react"
import { cn } from "@/lib/utils"
import { useAuth } from "@/contexts/AuthContext"
import { useToast } from "@/components/ui/toast"

interface ChatInterfaceProps {
  className?: string
}

export function ChatInterface({ className }: ChatInterfaceProps) {
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [activeConversationId, setActiveConversationId] = useState<string>("")
  const [messages, setMessages] = useState<Message[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [isConnected] = useState(true)
  const [darkMode, setDarkMode] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)

  // Get user data from auth context
  const { user, logout } = useAuth()
  const { addToast } = useToast()

  // Use authenticated user data
  const userData = user ? {
    name: user.name || `${user.first_name || ''} ${user.last_name || ''}`.trim() || 'User',
    email: user.email,
    avatar: user.avatar
  } : undefined

  // Sample conversations for demo
  useEffect(() => {
    const sampleConversations: Conversation[] = [
      {
        id: "1",
        title: "Getting Started with PyAirtable",
        lastMessage: "How do I connect to my Airtable base?",
        timestamp: new Date(Date.now() - 1000 * 60 * 5),
        unreadCount: 0
      },
      {
        id: "2", 
        title: "Data Analysis Help",
        lastMessage: "Can you help me analyze my sales data?",
        timestamp: new Date(Date.now() - 1000 * 60 * 60 * 2),
        unreadCount: 2
      },
      {
        id: "3",
        title: "API Integration",
        lastMessage: "What's the best way to sync data?",
        timestamp: new Date(Date.now() - 1000 * 60 * 60 * 24),
        unreadCount: 0
      }
    ]
    setConversations(sampleConversations)
    
    // Set first conversation as active
    if (sampleConversations.length > 0) {
      setActiveConversationId(sampleConversations[0].id)
      loadConversationMessages(sampleConversations[0].id)
    }
  }, [])

  // Auto scroll to bottom when new messages arrive
  useEffect(() => {
    scrollToBottom()
  }, [messages])

  // Apply dark mode
  useEffect(() => {
    if (darkMode) {
      document.documentElement.classList.add('dark')
    } else {
      document.documentElement.classList.remove('dark')
    }
  }, [darkMode])

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }

  const loadConversationMessages = (_conversationId: string) => {
    // Mock loading messages for a conversation
    const mockMessages: Message[] = [
      {
        id: "1",
        content: "Hello! I'm your PyAirtable AI assistant. How can I help you today?",
        role: "assistant",
        timestamp: new Date(Date.now() - 1000 * 60 * 10)
      },
      {
        id: "2", 
        content: "Hi! I need help connecting to my Airtable base and analyzing the data.",
        role: "user",
        timestamp: new Date(Date.now() - 1000 * 60 * 5),
        status: "sent"
      },
      {
        id: "3",
        content: "I'd be happy to help you connect to your Airtable base! To get started, I'll need a few things:\n\n1. Your Airtable Personal Access Token\n2. The Base ID you want to connect to\n3. The specific table you want to work with\n\nDo you have your Personal Access Token ready?",
        role: "assistant", 
        timestamp: new Date(Date.now() - 1000 * 60 * 4)
      }
    ]
    setMessages(mockMessages)
  }

  const handleNewConversation = () => {
    const newConversation: Conversation = {
      id: Date.now().toString(),
      title: "New Conversation",
      timestamp: new Date(),
      unreadCount: 0
    }
    setConversations(prev => [newConversation, ...prev])
    setActiveConversationId(newConversation.id)
    setMessages([])
  }

  const handleSelectConversation = (conversationId: string) => {
    setActiveConversationId(conversationId)
    loadConversationMessages(conversationId)
  }

  const handleSendMessage = async (content: string, attachments?: File[]) => {
    if (!content.trim() && (!attachments || attachments.length === 0)) return

    // Add user message
    const userMessage: Message = {
      id: Date.now().toString(),
      content,
      role: "user",
      timestamp: new Date(),
      status: "sending"
    }
    
    setMessages(prev => [...prev, userMessage])
    setIsLoading(true)

    try {
      // Update user message status
      setMessages(prev => 
        prev.map(msg => 
          msg.id === userMessage.id 
            ? { ...msg, status: "sent" }
            : msg
        )
      )

      // Simulate API call to backend
      await new Promise(resolve => setTimeout(resolve, 1500))

      // Add AI response
      const aiResponse: Message = {
        id: (Date.now() + 1).toString(),
        content: "Thank you for your message! I'm processing your request and will provide a detailed response shortly. This is a simulated response - in the real app, this would connect to your PyAirtable backend services.",
        role: "assistant",
        timestamp: new Date()
      }
      
      setMessages(prev => [...prev, aiResponse])
      
      // Update conversation last message
      setConversations(prev => 
        prev.map(conv => 
          conv.id === activeConversationId
            ? { ...conv, lastMessage: content, timestamp: new Date() }
            : conv
        )
      )

    } catch (error) {
      // Mark message as failed
      setMessages(prev => 
        prev.map(msg => 
          msg.id === userMessage.id 
            ? { ...msg, status: "error" }
            : msg
        )
      )
    } finally {
      setIsLoading(false)
    }
  }

  const handleDeleteConversation = (conversationId: string) => {
    setConversations(prev => prev.filter(conv => conv.id !== conversationId))
    if (activeConversationId === conversationId) {
      const remaining = conversations.filter(conv => conv.id !== conversationId)
      if (remaining.length > 0) {
        setActiveConversationId(remaining[0].id)
        loadConversationMessages(remaining[0].id)
      } else {
        setActiveConversationId("")
        setMessages([])
      }
    }
  }

  const handleLogout = async () => {
    try {
      setIsLoading(true)
      await logout()
      addToast({
        type: 'success',
        title: 'Logged out',
        description: 'You have been successfully logged out.'
      })
    } catch (error) {
      console.error('Logout error:', error)
      addToast({
        type: 'error',
        title: 'Logout failed',
        description: 'There was an error logging out. Please try again.'
      })
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className={cn("h-screen flex bg-background", className)}>
      {/* Sidebar */}
      <ChatSidebar
        conversations={conversations}
        activeConversationId={activeConversationId}
        onSelectConversation={handleSelectConversation}
        onNewConversation={handleNewConversation}
        onDeleteConversation={handleDeleteConversation}
        darkMode={darkMode}
        onToggleDarkMode={() => setDarkMode(prev => !prev)}
        onLogout={handleLogout}
        user={userData}
      />

      {/* Main chat area */}
      <div className="flex-1 flex flex-col">
        {/* Connection status bar */}
        {!isConnected && (
          <div className="bg-destructive/10 border-b border-destructive/20 p-2">
            <div className="flex items-center justify-center gap-2 text-sm text-destructive">
              <AlertCircle className="h-4 w-4" />
              Connection lost - attempting to reconnect...
            </div>
          </div>
        )}

        {/* Chat header */}
        <div className="border-b p-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="font-semibold">
                {conversations.find(c => c.id === activeConversationId)?.title || "Select a conversation"}
              </h2>
              {isConnected ? (
                <p className="text-sm text-muted-foreground">
                  Connected to PyAirtable API Gateway
                </p>
              ) : (
                <p className="text-sm text-destructive">Disconnected</p>
              )}
            </div>
            
            <div className="flex items-center gap-2">
              <Badge variant={isConnected ? "default" : "destructive"}>
                {isConnected ? "Online" : "Offline"}
              </Badge>
            </div>
          </div>
        </div>

        {/* Messages area */}
        <ScrollArea className="flex-1">
          <div className="p-4 space-y-4">
            {messages.length === 0 ? (
              <div className="text-center py-12">
                <div className="text-muted-foreground mb-4">
                  <svg className="w-12 h-12 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                  </svg>
                  <p>Start a conversation with your PyAirtable assistant</p>
                  <p className="text-sm mt-1">Ask questions about your data, get help with integrations, or explore your Airtable bases</p>
                </div>
              </div>
            ) : (
              <>
                {messages.map((message) => (
                  <ChatMessage key={message.id} message={message} />
                ))}
                
                {isLoading && (
                  <div className="flex justify-start">
                    <div className="flex items-center gap-2 text-muted-foreground">
                      <Loader2 className="h-4 w-4 animate-spin" />
                      <span className="text-sm">AI is typing...</span>
                    </div>
                  </div>
                )}
                
                <div ref={messagesEndRef} />
              </>
            )}
          </div>
        </ScrollArea>

        {/* Input area */}
        <ChatInput
          onSendMessage={handleSendMessage}
          disabled={!isConnected || isLoading}
          placeholder={
            !isConnected 
              ? "Reconnecting..." 
              : "Ask about your Airtable data, integrations, or get help..."
          }
        />
      </div>
    </div>
  )
}