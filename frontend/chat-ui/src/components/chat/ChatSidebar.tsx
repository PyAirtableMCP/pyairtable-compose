// import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { Badge } from "@/components/ui/badge"
import { 
  Plus, 
  MessageSquare, 
  MoreHorizontal, 
  Settings, 
  User,
  Moon,
  Sun,
  LogOut
} from "lucide-react"
import { cn } from "@/lib/utils"

export interface Conversation {
  id: string
  title: string
  lastMessage?: string
  timestamp: Date
  unreadCount?: number
}

interface ChatSidebarProps {
  conversations: Conversation[]
  activeConversationId?: string
  onSelectConversation: (id: string) => void
  onNewConversation: () => void
  onDeleteConversation?: (id: string) => void
  darkMode: boolean
  onToggleDarkMode: () => void
  onLogout?: () => void
  user?: {
    name: string
    email: string
    avatar?: string
  }
}

export function ChatSidebar({
  conversations,
  activeConversationId,
  onSelectConversation,
  onNewConversation,
  onDeleteConversation,
  darkMode,
  onToggleDarkMode,
  onLogout,
  user
}: ChatSidebarProps) {
  // const [showUserMenu, setShowUserMenu] = useState(false)

  const formatTimestamp = (timestamp: Date) => {
    const now = new Date()
    const diff = now.getTime() - timestamp.getTime()
    const hours = diff / (1000 * 60 * 60)
    
    if (hours < 1) {
      return "Just now"
    } else if (hours < 24) {
      return `${Math.floor(hours)}h ago`
    } else {
      return timestamp.toLocaleDateString([], { 
        month: 'short', 
        day: 'numeric' 
      })
    }
  }

  return (
    <div className="w-80 border-r bg-muted/30 flex flex-col h-full">
      {/* Header */}
      <div className="p-4 border-b">
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-semibold">PyAirtable Chat</h1>
          <Button
            onClick={onNewConversation}
            size="icon"
            variant="ghost"
            className="h-8 w-8"
          >
            <Plus className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Conversations */}
      <ScrollArea className="flex-1">
        <div className="p-2 space-y-1">
          {conversations.length === 0 ? (
            <div className="text-center py-8 px-4">
              <MessageSquare className="h-8 w-8 mx-auto text-muted-foreground mb-2" />
              <p className="text-sm text-muted-foreground">
                No conversations yet
              </p>
              <Button 
                onClick={onNewConversation}
                variant="ghost"
                size="sm"
                className="mt-2"
              >
                Start your first chat
              </Button>
            </div>
          ) : (
            conversations.map((conversation) => (
              <Card
                key={conversation.id}
                className={cn(
                  "p-3 cursor-pointer transition-colors hover:bg-accent/50 group",
                  activeConversationId === conversation.id && "bg-accent"
                )}
                onClick={() => onSelectConversation(conversation.id)}
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1 min-w-0">
                    <h3 className="font-medium text-sm truncate">
                      {conversation.title}
                    </h3>
                    {conversation.lastMessage && (
                      <p className="text-xs text-muted-foreground truncate mt-1">
                        {conversation.lastMessage}
                      </p>
                    )}
                    <p className="text-xs text-muted-foreground mt-1">
                      {formatTimestamp(conversation.timestamp)}
                    </p>
                  </div>
                  
                  <div className="flex items-center gap-1">
                    {conversation.unreadCount && conversation.unreadCount > 0 && (
                      <Badge variant="secondary" className="text-xs h-5 px-1">
                        {conversation.unreadCount}
                      </Badge>
                    )}
                    
                    {onDeleteConversation && (
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-6 w-6 opacity-0 group-hover:opacity-100"
                        onClick={(e) => {
                          e.stopPropagation()
                          onDeleteConversation(conversation.id)
                        }}
                      >
                        <MoreHorizontal className="h-3 w-3" />
                      </Button>
                    )}
                  </div>
                </div>
              </Card>
            ))
          )}
        </div>
      </ScrollArea>

      <Separator />

      {/* User section */}
      <div className="p-4">
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              onClick={onToggleDarkMode}
              className="h-8 w-8"
            >
              {darkMode ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
            </Button>
            
            <Button variant="ghost" size="icon" className="h-8 w-8">
              <Settings className="h-4 w-4" />
            </Button>
            
            <div className="flex-1" />
            
            {user && (
              <div className="flex items-center gap-2 text-sm">
                <div className="text-right">
                  <p className="font-medium truncate max-w-[100px]">
                    {user.name}
                  </p>
                </div>
                <Button variant="ghost" size="icon" className="h-8 w-8">
                  <User className="h-4 w-4" />
                </Button>
              </div>
            )}
            
            <Button 
              variant="ghost" 
              size="icon" 
              className="h-8 w-8 text-muted-foreground hover:text-destructive"
              onClick={onLogout}
              title="Logout"
            >
              <LogOut className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}