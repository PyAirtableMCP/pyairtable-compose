import { useState, useRef, type KeyboardEvent } from "react"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { Send, Paperclip, Mic, Square } from "lucide-react"
import { cn } from "@/lib/utils"

interface ChatInputProps {
  onSendMessage: (message: string, attachments?: File[]) => void
  disabled?: boolean
  placeholder?: string
}

export function ChatInput({ 
  onSendMessage, 
  disabled = false,
  placeholder = "Type your message..."
}: ChatInputProps) {
  const [message, setMessage] = useState("")
  const [attachments, setAttachments] = useState<File[]>([])
  const [isRecording, setIsRecording] = useState(false)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleSubmit = () => {
    if (message.trim() || attachments.length > 0) {
      onSendMessage(message.trim(), attachments)
      setMessage("")
      setAttachments([])
      if (textareaRef.current) {
        textareaRef.current.style.height = 'auto'
      }
    }
  }

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSubmit()
    }
  }

  const handleTextareaChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setMessage(e.target.value)
    
    // Auto-resize textarea
    const textarea = e.target
    textarea.style.height = 'auto'
    textarea.style.height = `${Math.min(textarea.scrollHeight, 120)}px`
  }

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || [])
    setAttachments(prev => [...prev, ...files])
  }

  const removeAttachment = (index: number) => {
    setAttachments(prev => prev.filter((_, i) => i !== index))
  }

  const toggleRecording = () => {
    setIsRecording(prev => !prev)
    // TODO: Implement voice recording functionality
  }

  return (
    <div className="border-t bg-background p-4">
      {/* File attachments preview */}
      {attachments.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-2">
          {attachments.map((file, index) => (
            <div
              key={index}
              className="flex items-center gap-1 rounded-md bg-muted px-2 py-1 text-xs"
            >
              <span className="truncate max-w-[100px]">{file.name}</span>
              <button
                onClick={() => removeAttachment(index)}
                className="text-muted-foreground hover:text-foreground"
              >
                ×
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="flex items-end gap-2">
        {/* File upload button */}
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => fileInputRef.current?.click()}
                disabled={disabled}
                className="shrink-0"
              >
                <Paperclip className="h-4 w-4" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>
              <p>Attach file</p>
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>

        {/* Message input */}
        <div className="flex-1 relative">
          <Textarea
            ref={textareaRef}
            value={message}
            onChange={handleTextareaChange}
            onKeyDown={handleKeyDown}
            placeholder={placeholder}
            disabled={disabled}
            className="min-h-[44px] max-h-[120px] resize-none pr-12"
            style={{ height: 'auto' }}
          />
          
          {/* Voice recording button */}
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={toggleRecording}
                  disabled={disabled}
                  className={cn(
                    "absolute right-1 top-1 h-8 w-8",
                    isRecording && "text-destructive"
                  )}
                >
                  {isRecording ? (
                    <Square className="h-4 w-4" />
                  ) : (
                    <Mic className="h-4 w-4" />
                  )}
                </Button>
              </TooltipTrigger>
              <TooltipContent>
                <p>{isRecording ? "Stop recording" : "Voice message"}</p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>

        {/* Send button */}
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                onClick={handleSubmit}
                disabled={disabled || (!message.trim() && attachments.length === 0)}
                size="icon"
                className="shrink-0"
              >
                <Send className="h-4 w-4" />
              </Button>
            </TooltipTrigger>
            <TooltipContent>
              <p>Send message</p>
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
      </div>

      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        onChange={handleFileSelect}
        className="hidden"
      />
    </div>
  )
}