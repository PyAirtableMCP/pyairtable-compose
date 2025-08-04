"use client"

import React from "react"
import * as Sentry from "@sentry/nextjs"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AlertTriangle, RefreshCw, Home, Bug } from "lucide-react"
import { useSession } from "next-auth/react"
import { trackEvent } from "@/app/posthog-provider"

interface ErrorBoundaryState {
  hasError: boolean
  error: Error | null
  errorInfo: React.ErrorInfo | null
  eventId: string | null
}

interface ErrorBoundaryProps {
  children: React.ReactNode
  fallback?: React.ComponentType<{
    error: Error
    resetError: () => void
    eventId: string | null
  }>
  onError?: (error: Error, errorInfo: React.ErrorInfo) => void
  showDetails?: boolean
}

export class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props)
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
      eventId: null,
    }
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    return {
      hasError: true,
      error,
    }
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    // Capture error with Sentry
    const eventId = Sentry.captureException(error, {
      contexts: {
        react: {
          componentStack: errorInfo.componentStack,
        },
      },
      tags: {
        section: "error-boundary",
      },
    })

    // Track error with PostHog
    trackEvent("error_boundary_triggered", {
      error_message: error.message,
      error_stack: error.stack,
      component_stack: errorInfo.componentStack,
      sentry_event_id: eventId,
    })

    this.setState({
      errorInfo,
      eventId,
    })

    // Call custom error handler if provided
    this.props.onError?.(error, errorInfo)
  }

  resetError = () => {
    this.setState({
      hasError: false,
      error: null,
      errorInfo: null,
      eventId: null,
    })
  }

  render() {
    if (this.state.hasError && this.state.error) {
      // Use custom fallback component if provided
      if (this.props.fallback) {
        const FallbackComponent = this.props.fallback
        return (
          <FallbackComponent
            error={this.state.error}
            resetError={this.resetError}
            eventId={this.state.eventId}
          />
        )
      }

      // Default error UI
      return (
        <DefaultErrorFallback
          error={this.state.error}
          resetError={this.resetError}
          eventId={this.state.eventId}
          showDetails={this.props.showDetails}
          errorInfo={this.state.errorInfo}
        />
      )
    }

    return this.props.children
  }
}

interface DefaultErrorFallbackProps {
  error: Error
  resetError: () => void
  eventId: string | null
  showDetails?: boolean
  errorInfo: React.ErrorInfo | null
}

function DefaultErrorFallback({ 
  error, 
  resetError, 
  eventId, 
  showDetails = false,
  errorInfo 
}: DefaultErrorFallbackProps) {
  const { data: session } = useSession()
  const [detailsExpanded, setDetailsExpanded] = React.useState(false)

  const reportIssue = () => {
    if (eventId) {
      // Open Sentry issue URL
      window.open(`https://sentry.io/organizations/pyairtable/issues/?query=id:${eventId}`, "_blank")
    } else {
      // Fallback to email
      const subject = encodeURIComponent(`Error Report: ${error.message}`)
      const body = encodeURIComponent(
        `Error: ${error.message}\n\nStack Trace:\n${error.stack}\n\nUser: ${session?.user?.email || 'Anonymous'}\n\nTime: ${new Date().toISOString()}`
      )
      window.open(`mailto:support@pyairtable.com?subject=${subject}&body=${body}`)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-red-50 to-orange-100">
      <Card className="w-full max-w-2xl">
        <CardHeader>
          <div className="flex items-center gap-3">
            <AlertTriangle className="h-8 w-8 text-destructive" />
            <div>
              <CardTitle className="text-2xl">Something went wrong</CardTitle>
              <CardDescription>
                We&apos;re sorry, but an unexpected error occurred. Our team has been notified.
              </CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {eventId && (
            <Alert>
              <Bug className="h-4 w-4" />
              <AlertDescription>
                <strong>Error ID:</strong> {eventId}
                <br />
                Reference this ID when contacting support for faster resolution.
              </AlertDescription>
            </Alert>
          )}

          <div className="flex flex-wrap gap-3">
            <Button onClick={resetError} className="flex-1 min-w-32">
              <RefreshCw className="mr-2 h-4 w-4" />
              Try Again
            </Button>
            <Button 
              variant="outline" 
              onClick={() => window.location.href = "/"} 
              className="flex-1 min-w-32"
            >
              <Home className="mr-2 h-4 w-4" />
              Go Home
            </Button>
            <Button 
              variant="outline" 
              onClick={reportIssue}
              className="flex-1 min-w-32"
            >
              <Bug className="mr-2 h-4 w-4" />
              Report Issue
            </Button>
          </div>

          {showDetails && (
            <div className="space-y-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setDetailsExpanded(!detailsExpanded)}
                className="text-muted-foreground"
              >
                {detailsExpanded ? "Hide" : "Show"} Technical Details
              </Button>
              
              {detailsExpanded && (
                <div className="space-y-3">
                  <Alert variant="destructive">
                    <AlertDescription>
                      <strong>Error Message:</strong>
                      <pre className="mt-2 text-sm whitespace-pre-wrap">{error.message}</pre>
                    </AlertDescription>
                  </Alert>
                  
                  {error.stack && (
                    <Alert>
                      <AlertDescription>
                        <strong>Stack Trace:</strong>
                        <pre className="mt-2 text-xs whitespace-pre-wrap overflow-auto max-h-40">
                          {error.stack}
                        </pre>
                      </AlertDescription>
                    </Alert>
                  )}
                  
                  {errorInfo?.componentStack && (
                    <Alert>
                      <AlertDescription>
                        <strong>Component Stack:</strong>
                        <pre className="mt-2 text-xs whitespace-pre-wrap overflow-auto max-h-40">
                          {errorInfo.componentStack}
                        </pre>
                      </AlertDescription>
                    </Alert>
                  )}
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// Hook for using error boundary programmatically
export const useErrorHandler = () => {
  const { data: session } = useSession()

  return React.useCallback((error: Error, errorInfo?: any) => {
    // Capture with Sentry
    const eventId = Sentry.captureException(error, {
      contexts: errorInfo ? { extra: errorInfo } : undefined,
      user: session?.user ? {
        id: session.user.id,
        email: session.user.email,
      } : undefined,
    })

    // Track with PostHog
    trackEvent("manual_error_reported", {
      error_message: error.message,
      error_stack: error.stack,
      sentry_event_id: eventId,
      user_id: session?.user?.id,
    })

    return eventId
  }, [session])
}

// Async error handler for promises
export const handleAsyncError = (error: Error, context?: string) => {
  const eventId = Sentry.captureException(error, {
    tags: {
      section: context || "async-operation",
    },
  })

  trackEvent("async_error_caught", {
    error_message: error.message,
    context: context || "unknown",
    sentry_event_id: eventId,
  })

  console.error(`Async error in ${context}:`, error)
  return eventId
}