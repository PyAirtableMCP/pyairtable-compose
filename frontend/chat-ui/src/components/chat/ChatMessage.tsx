import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"

export interface Message {
  id: string
  content: string
  role: 'user' | 'assistant' | 'system'
  timestamp: Date
  status?: 'sending' | 'sent' | 'error'
}

interface ChatMessageProps {
  message: Message
}

export function ChatMessage({ message }: ChatMessageProps) {
  const isUser = message.role === 'user'
  const isSystem = message.role === 'system'
  
  if (isSystem) {
    return (
      <div className="flex justify-center my-4">
        <Badge variant="secondary" className="text-xs">
          {message.content}
        </Badge>
      </div>
    )
  }

  return (
    <div className={cn(
      "flex gap-3 mb-4",
      isUser ? "justify-end" : "justify-start"
    )}>
      {!isUser && (
        <Avatar className="w-8 h-8 mt-1">
          <AvatarImage src="/api/placeholder/32/32" alt="AI Assistant" />
          <AvatarFallback className="text-xs">AI</AvatarFallback>
        </Avatar>
      )}
      
      <div className={cn(
        "flex flex-col gap-1 max-w-[70%]",
        isUser && "items-end"
      )}>
        <Card className={cn(
          "p-3",
          isUser 
            ? "bg-primary text-primary-foreground" 
            : "bg-muted"
        )}>
          <p className="text-sm leading-relaxed whitespace-pre-wrap">
            {message.content}
          </p>
        </Card>
        
        <div className="flex items-center gap-1 text-xs text-muted-foreground">
          <span>
            {message.timestamp.toLocaleTimeString([], {
              hour: '2-digit',
              minute: '2-digit'
            })}
          </span>
          
          {isUser && message.status && (
            <>
              <span>•</span>
              <span className={cn(
                message.status === 'error' && "text-destructive",
                message.status === 'sending' && "animate-pulse"
              )}>
                {message.status === 'sending' && "Sending..."}
                {message.status === 'sent' && "Sent"}
                {message.status === 'error' && "Failed"}
              </span>
            </>
          )}
        </div>
      </div>
      
      {isUser && (
        <Avatar className="w-8 h-8 mt-1">
          <AvatarImage src="/api/placeholder/32/32" alt="You" />
          <AvatarFallback className="text-xs">You</AvatarFallback>
        </Avatar>
      )}
    </div>
  )
}