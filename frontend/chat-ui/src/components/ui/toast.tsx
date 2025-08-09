import { createContext, useContext, useState, useEffect, type ReactNode } from 'react'
import { X, AlertCircle, CheckCircle, Info, AlertTriangle } from 'lucide-react'
import { cn } from '@/lib/utils'

export type ToastType = 'success' | 'error' | 'info' | 'warning'

export interface Toast {
  id: string
  type: ToastType
  title: string
  description?: string
  duration?: number
}

interface ToastContextType {
  toasts: Toast[]
  addToast: (toast: Omit<Toast, 'id'>) => void
  removeToast: (id: string) => void
  clearToasts: () => void
}

const ToastContext = createContext<ToastContextType | undefined>(undefined)

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])

  const addToast = (toast: Omit<Toast, 'id'>) => {
    const id = Math.random().toString(36).substring(2, 9)
    const newToast: Toast = {
      ...toast,
      id,
      duration: toast.duration ?? 5000
    }

    setToasts(prev => [...prev, newToast])

    // Auto-remove toast after duration
    if (newToast.duration && newToast.duration > 0) {
      setTimeout(() => {
        removeToast(id)
      }, newToast.duration)
    }
  }

  const removeToast = (id: string) => {
    setToasts(prev => prev.filter(toast => toast.id !== id))
  }

  const clearToasts = () => {
    setToasts([])
  }

  return (
    <ToastContext.Provider value={{ toasts, addToast, removeToast, clearToasts }}>
      {children}
      <ToastContainer />
    </ToastContext.Provider>
  )
}

function ToastContainer() {
  const { toasts } = useToast()

  return (
    <div className="fixed top-0 right-0 z-[100] flex max-h-screen w-full flex-col-reverse p-4 sm:top-4 sm:right-4 sm:max-w-[420px]">
      {toasts.map(toast => (
        <ToastComponent key={toast.id} toast={toast} />
      ))}
    </div>
  )
}

function ToastComponent({ toast }: { toast: Toast }) {
  const { removeToast } = useToast()
  const [isVisible, setIsVisible] = useState(false)

  useEffect(() => {
    // Trigger enter animation
    setIsVisible(true)
  }, [])

  const handleRemove = () => {
    setIsVisible(false)
    setTimeout(() => removeToast(toast.id), 150) // Wait for exit animation
  }

  const getIcon = () => {
    switch (toast.type) {
      case 'success':
        return <CheckCircle className="h-4 w-4" />
      case 'error':
        return <AlertCircle className="h-4 w-4" />
      case 'warning':
        return <AlertTriangle className="h-4 w-4" />
      case 'info':
      default:
        return <Info className="h-4 w-4" />
    }
  }

  const getColorClasses = () => {
    switch (toast.type) {
      case 'success':
        return 'border-green-200 bg-green-50 text-green-800'
      case 'error':
        return 'border-red-200 bg-red-50 text-red-800'
      case 'warning':
        return 'border-yellow-200 bg-yellow-50 text-yellow-800'
      case 'info':
      default:
        return 'border-blue-200 bg-blue-50 text-blue-800'
    }
  }

  return (
    <div
      className={cn(
        'pointer-events-auto relative flex w-full items-center justify-between space-x-4 overflow-hidden rounded-md border p-6 pr-8 shadow-lg transition-all',
        getColorClasses(),
        isVisible
          ? 'translate-x-0 opacity-100'
          : 'translate-x-full opacity-0',
        'mb-2'
      )}
    >
      <div className="flex items-center space-x-2">
        {getIcon()}
        <div className="grid gap-1">
          <div className="text-sm font-semibold">{toast.title}</div>
          {toast.description && (
            <div className="text-sm opacity-90">{toast.description}</div>
          )}
        </div>
      </div>
      <button
        onClick={handleRemove}
        className="absolute right-2 top-2 rounded-md p-1 hover:opacity-70 focus:opacity-70 focus:outline-none"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  )
}

export const useToast = () => {
  const context = useContext(ToastContext)
  if (context === undefined) {
    throw new Error('useToast must be used within a ToastProvider')
  }
  return context
}

// Convenience functions
export const toast = {
  success: (title: string, description?: string, duration?: number) => {
    const { addToast } = useToast()
    addToast({ type: 'success', title, description, duration })
  },
  error: (title: string, description?: string, duration?: number) => {
    const { addToast } = useToast()
    addToast({ type: 'error', title, description, duration })
  },
  info: (title: string, description?: string, duration?: number) => {
    const { addToast } = useToast()
    addToast({ type: 'info', title, description, duration })
  },
  warning: (title: string, description?: string, duration?: number) => {
    const { addToast } = useToast()
    addToast({ type: 'warning', title, description, duration })
  }
}