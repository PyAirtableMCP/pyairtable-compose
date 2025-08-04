"use client"

import * as React from "react"
import { Loader2, RefreshCw } from "lucide-react"

import { cn } from "@/lib/utils"
import { Card, CardContent, CardHeader } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { Button } from "@/components/ui/button"

interface LoadingStateProps {
  message?: string
  showSpinner?: boolean
  size?: "sm" | "md" | "lg"
  className?: string
}

export function LoadingState({
  message = "Loading...",
  showSpinner = true,
  size = "md",
  className,
}: LoadingStateProps) {
  const getSizeClasses = () => {
    switch (size) {
      case "sm":
        return {
          container: "py-8",
          spinner: "h-6 w-6",
          message: "text-sm",
          spacing: "space-y-2",
        }
      case "lg":
        return {
          container: "py-16",
          spinner: "h-12 w-12",
          message: "text-lg",
          spacing: "space-y-4",
        }
      default:
        return {
          container: "py-12",
          spinner: "h-8 w-8",
          message: "text-base",
          spacing: "space-y-3",
        }
    }
  }

  const sizeClasses = getSizeClasses()

  return (
    <div className={cn("flex items-center justify-center", sizeClasses.container, className)}>
      <div className={cn("text-center", sizeClasses.spacing)}>
        {showSpinner && (
          <div className="flex justify-center">
            <Loader2 className={cn(sizeClasses.spinner, "animate-spin text-muted-foreground")} />
          </div>
        )}
        <p className={cn("text-muted-foreground font-medium", sizeClasses.message)}>
          {message}
        </p>
      </div>
    </div>
  )
}

// Specialized loading states
export function TableLoadingState({ columns = 4, rows = 5 }: { columns?: number; rows?: number }) {
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-8 w-24" />
      </div>
      <div className="rounded-md border">
        <div className="grid grid-cols-4 gap-4 p-4 border-b bg-muted/50">
          {Array.from({ length: columns }).map((_, index) => (
            <Skeleton key={index} className="h-4" />
          ))}
        </div>
        {Array.from({ length: rows }).map((_, rowIndex) => (
          <div key={rowIndex} className="grid grid-cols-4 gap-4 p-4 border-b last:border-b-0">
            {Array.from({ length: columns }).map((_, colIndex) => (
              <Skeleton key={colIndex} className="h-4" />
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}

export function CardLoadingState() {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <Skeleton className="h-5 w-32" />
          <Skeleton className="h-4 w-4" />
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <Skeleton className="h-8 w-24" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-3/4" />
      </CardContent>
    </Card>
  )
}

export function MetricLoadingState() {
  return (
    <Card>
      <CardContent className="p-6">
        <div className="flex items-center justify-between">
          <div className="space-y-2">
            <Skeleton className="h-4 w-24" />
            <Skeleton className="h-8 w-16" />
            <Skeleton className="h-3 w-32" />
          </div>
          <Skeleton className="h-6 w-6" />
        </div>
      </CardContent>
    </Card>
  )
}

export function FormLoadingState() {
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-10 w-full" />
      </div>
      <div className="space-y-2">
        <Skeleton className="h-4 w-32" />
        <Skeleton className="h-10 w-full" />
      </div>
      <div className="space-y-2">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="h-24 w-full" />
      </div>
      <div className="flex gap-2">
        <Skeleton className="h-10 w-24" />
        <Skeleton className="h-10 w-20" />
      </div>
    </div>
  )
}

// Progressive loading component
interface ProgressiveLoadingProps {
  stages: Array<{
    message: string
    duration?: number
  }>
  onComplete?: () => void
  className?: string
}

export function ProgressiveLoading({ 
  stages, 
  onComplete, 
  className 
}: ProgressiveLoadingProps) {
  const [currentStage, setCurrentStage] = React.useState(0)

  React.useEffect(() => {
    if (currentStage >= stages.length) {
      onComplete?.()
      return
    }

    const stage = stages[currentStage]
    const timer = setTimeout(() => {
      setCurrentStage((prev) => prev + 1)
    }, stage.duration || 2000)

    return () => clearTimeout(timer)
  }, [currentStage, stages, onComplete])

  if (currentStage >= stages.length) {
    return null
  }

  return (
    <LoadingState
      message={stages[currentStage].message}
      className={className}
    />
  )
}

// Retry loading component
interface RetryLoadingProps {
  message?: string
  error?: string
  onRetry: () => void
  retrying?: boolean
  className?: string
}

export function RetryLoading({
  message = "Failed to load",
  error,
  onRetry,
  retrying = false,
  className,
}: RetryLoadingProps) {
  return (
    <div className={cn("flex items-center justify-center py-12", className)}>
      <div className="text-center space-y-4 max-w-md">
        <div className="flex justify-center">
          <div className="rounded-full bg-destructive/10 p-4">
            <RefreshCw className="h-8 w-8 text-destructive" />
          </div>
        </div>
        
        <div className="space-y-2">
          <h3 className="font-semibold text-foreground">{message}</h3>
          {error && (
            <p className="text-sm text-muted-foreground">{error}</p>
          )}
        </div>

        <Button
          onClick={onRetry}
          disabled={retrying}
          variant="outline"
        >
          {retrying ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Retrying...
            </>
          ) : (
            <>
              <RefreshCw className="mr-2 h-4 w-4" />
              Try again
            </>
          )}
        </Button>
      </div>
    </div>
  )
}

// Loading overlay component
interface LoadingOverlayProps {
  visible: boolean
  message?: string
  className?: string
}

export function LoadingOverlay({
  visible,
  message = "Loading...",
  className,
}: LoadingOverlayProps) {
  if (!visible) return null

  return (
    <div className={cn(
      "absolute inset-0 bg-background/80 backdrop-blur-sm flex items-center justify-center z-50",
      className
    )}>
      <LoadingState message={message} />
    </div>
  )
}