"use client"

import React from "react"
import { Wifi, WifiOff, RefreshCw } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"

export default function OfflinePage() {
  const [isOnline, setIsOnline] = React.useState(true)
  const [retryCount, setRetryCount] = React.useState(0)

  React.useEffect(() => {
    // Check initial online status
    setIsOnline(navigator.onLine)

    // Listen for online/offline events
    const handleOnline = () => {
      setIsOnline(true)
      // Auto-redirect when back online
      setTimeout(() => {
        window.location.href = '/'
      }, 1000)
    }
    
    const handleOffline = () => setIsOnline(false)

    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)

    return () => {
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
    }
  }, [])

  const handleRetry = () => {
    setRetryCount(prev => prev + 1)
    
    // Check if we're online and reload
    if (navigator.onLine) {
      window.location.reload()
    } else {
      // Show offline message
      setTimeout(() => {
        alert('Still offline. Please check your internet connection.')
      }, 500)
    }
  }

  const handleGoHome = () => {
    window.location.href = '/'
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardContent className="pt-6">
          <div className="text-center space-y-6">
            {/* Status Icon */}
            <div className="flex justify-center">
              <div className={`p-4 rounded-full ${isOnline ? 'bg-green-100 dark:bg-green-900' : 'bg-red-100 dark:bg-red-900'}`}>
                {isOnline ? (
                  <Wifi className="h-8 w-8 text-green-600 dark:text-green-400" />
                ) : (
                  <WifiOff className="h-8 w-8 text-red-600 dark:text-red-400" />
                )}
              </div>
            </div>

            {/* Status Badge */}
            <Badge 
              variant={isOnline ? "default" : "destructive"}
              className="text-sm px-3 py-1"
            >
              {isOnline ? "Back Online" : "Offline"}
            </Badge>

            {/* Title and Description */}
            <div className="space-y-2">
              <h1 className="text-2xl font-bold text-foreground">
                {isOnline ? "Connection Restored!" : "You're Offline"}
              </h1>
              <p className="text-muted-foreground">
                {isOnline 
                  ? "Your internet connection has been restored. Redirecting you back to the dashboard..."
                  : "This page isn't available offline. Please check your internet connection and try again."
                }
              </p>
            </div>

            {/* Cached Data Notice */}
            {!isOnline && (
              <div className="bg-muted/50 rounded-lg p-4">
                <p className="text-sm text-muted-foreground">
                  <strong>Note:</strong> Some previously visited pages and data may still be available offline. 
                  You can navigate using the browser back button to access cached content.
                </p>
              </div>
            )}

            {/* Action Buttons */}
            <div className="space-y-3">
              {isOnline ? (
                <Button onClick={handleGoHome} className="w-full">
                  Go to Dashboard
                </Button>
              ) : (
                <>
                  <Button 
                    onClick={handleRetry} 
                    className="w-full"
                    disabled={retryCount >= 3}
                  >
                    <RefreshCw className="mr-2 h-4 w-4" />
                    {retryCount >= 3 ? "Connection Failed" : "Try Again"}
                  </Button>
                  
                  <Button 
                    variant="outline" 
                    onClick={handleGoHome}
                    className="w-full"
                  >
                    Go to Dashboard (Cached)
                  </Button>
                </>
              )}
            </div>

            {/* Retry Counter */}
            {retryCount > 0 && (
              <p className="text-xs text-muted-foreground">
                Retry attempts: {retryCount}/3
              </p>
            )}

            {/* Tips */}
            {!isOnline && (
              <div className="text-left bg-muted/30 rounded-lg p-4 space-y-2">
                <h3 className="font-medium text-sm">Troubleshooting Tips:</h3>
                <ul className="text-xs text-muted-foreground space-y-1">
                  <li>• Check your WiFi or mobile data connection</li>
                  <li>• Make sure airplane mode is turned off</li>
                  <li>• Try refreshing the page</li>
                  <li>• Contact your network administrator if the problem persists</li>
                </ul>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}