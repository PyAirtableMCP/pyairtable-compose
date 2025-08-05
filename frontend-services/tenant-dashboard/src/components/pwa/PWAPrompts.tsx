"use client"

import React from "react"
import { Download, X, RefreshCw, Smartphone, Monitor } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { usePWA } from "@/hooks/usePWA"

interface PWAPromptsProps {
  showInstallBanner?: boolean
  autoShowInstallDialog?: boolean
}

export function PWAPrompts({ 
  showInstallBanner = true, 
  autoShowInstallDialog = false 
}: PWAPromptsProps) {
  const {
    isInstallable,
    isInstalled,
    isUpdateAvailable,
    showInstallPrompt,
    dismissInstallPrompt,
    updateApp,
  } = usePWA()

  const [showInstallDialog, setShowInstallDialog] = React.useState(false)
  const [installDismissed, setInstallDismissed] = React.useState(false)

  // Auto-show install dialog if enabled
  React.useEffect(() => {
    if (autoShowInstallDialog && isInstallable && !installDismissed) {
      const timer = setTimeout(() => {
        setShowInstallDialog(true)
      }, 3000) // Show after 3 seconds

      return () => clearTimeout(timer)
    }
  }, [autoShowInstallDialog, isInstallable, installDismissed])

  const handleInstall = async () => {
    const installed = await showInstallPrompt()
    if (installed) {
      setShowInstallDialog(false)
    }
  }

  const handleDismissInstall = () => {
    dismissInstallPrompt()
    setInstallDismissed(true)
    setShowInstallDialog(false)
  }

  const handleUpdate = () => {
    updateApp()
  }

  if (isInstalled) {
    return (
      <>
        {/* Update Available Prompt */}
        {isUpdateAvailable && (
          <div className="fixed bottom-4 right-4 z-50">
            <Card className="w-80 shadow-lg border-primary">
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <RefreshCw className="h-5 w-5 text-primary" />
                    <CardTitle className="text-base">Update Available</CardTitle>
                  </div>
                  <Badge variant="default" className="text-xs">
                    New
                  </Badge>
                </div>
              </CardHeader>
              <CardContent className="pt-0">
                <p className="text-sm text-muted-foreground mb-4">
                  A new version of the app is available with bug fixes and improvements.
                </p>
                <div className="flex gap-2">
                  <Button onClick={handleUpdate} size="sm" className="flex-1">
                    <RefreshCw className="mr-2 h-4 w-4" />
                    Update Now
                  </Button>
                </div>
              </CardContent>
            </Card>
          </div>
        )}
      </>
    )
  }

  return (
    <>
      {/* Install Banner */}
      {showInstallBanner && isInstallable && !installDismissed && (
        <Alert className="border-primary bg-primary/5">
          <Smartphone className="h-4 w-4" />
          <AlertDescription className="flex items-center justify-between w-full">
            <span className="text-sm">
              Install PyAirtable Dashboard for quick access and offline use.
            </span>
            <div className="flex gap-2 ml-4">
              <Button
                size="sm"
                onClick={() => setShowInstallDialog(true)}
                className="h-7 text-xs"
              >
                Install
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={handleDismissInstall}
                className="h-7 w-7 p-0"
              >
                <X className="h-3 w-3" />
              </Button>
            </div>
          </AlertDescription>
        </Alert>
      )}

      {/* Install Dialog */}
      <Dialog open={showInstallDialog} onOpenChange={setShowInstallDialog}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Download className="h-5 w-5" />
              Install PyAirtable Dashboard
            </DialogTitle>
            <DialogDescription>
              Get app-like experience with offline access and faster loading times.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            {/* Features */}
            <div className="space-y-3">
              <h4 className="font-medium text-sm">Benefits of installing:</h4>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li className="flex items-center gap-2">
                  <div className="w-1 h-1 bg-primary rounded-full" />
                  Works offline - access cached data without internet
                </li>
                <li className="flex items-center gap-2">
                  <div className="w-1 h-1 bg-primary rounded-full" />
                  Faster loading - resources cached locally
                </li>
                <li className="flex items-center gap-2">
                  <div className="w-1 h-1 bg-primary rounded-full" />
                  App-like experience - no browser UI
                </li>
                <li className="flex items-center gap-2">
                  <div className="w-1 h-1 bg-primary rounded-full" />
                  Desktop shortcuts and taskbar integration
                </li>
                <li className="flex items-center gap-2">
                  <div className="w-1 h-1 bg-primary rounded-full" />
                  Push notifications for important updates
                </li>
              </ul>
            </div>

            {/* Device Preview */}
            <div className="flex items-center justify-center gap-4 py-4 bg-muted/30 rounded-lg">
              <div className="text-center">
                <Monitor className="h-8 w-8 mx-auto mb-2 text-muted-foreground" />
                <p className="text-xs text-muted-foreground">Desktop</p>
              </div>
              <div className="text-center">
                <Smartphone className="h-8 w-8 mx-auto mb-2 text-muted-foreground" />
                <p className="text-xs text-muted-foreground">Mobile</p>
              </div>
            </div>
          </div>

          <DialogFooter className="flex-col sm:flex-row gap-2">
            <Button
              variant="outline"
              onClick={handleDismissInstall}
              className="w-full sm:w-auto"
            >
              Not Now
            </Button>
            <Button
              onClick={handleInstall}
              className="w-full sm:w-auto"
            >
              <Download className="mr-2 h-4 w-4" />
              Install App
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Update Available Prompt for non-installed users */}
      {isUpdateAvailable && (
        <div className="fixed bottom-4 right-4 z-50">
          <Card className="w-80 shadow-lg border-primary">
            <CardHeader className="pb-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <RefreshCw className="h-5 w-5 text-primary" />
                  <CardTitle className="text-base">Update Available</CardTitle>
                </div>
                <Badge variant="default" className="text-xs">
                  New
                </Badge>
              </div>
            </CardHeader>
            <CardContent className="pt-0">
              <p className="text-sm text-muted-foreground mb-4">
                A new version is available. Refresh to get the latest features.
              </p>
              <div className="flex gap-2">
                <Button onClick={handleUpdate} size="sm" className="flex-1">
                  <RefreshCw className="mr-2 h-4 w-4" />
                  Refresh Now
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </>
  )
}

// Standalone Install Button Component
interface InstallButtonProps {
  variant?: "default" | "outline" | "ghost"
  size?: "sm" | "default" | "lg"
  className?: string
}

export function InstallButton({ 
  variant = "default", 
  size = "default",
  className 
}: InstallButtonProps) {
  const { isInstallable, isInstalled, showInstallPrompt } = usePWA()

  if (!isInstallable || isInstalled) {
    return null
  }

  const handleClick = async () => {
    await showInstallPrompt()
  }

  return (
    <Button
      variant={variant}
      size={size}
      onClick={handleClick}
      className={className}
    >
      <Download className="mr-2 h-4 w-4" />
      Install App
    </Button>
  )
}

// Connection Status Indicator
export function ConnectionStatus() {
  const { isOnline } = usePWA()

  if (isOnline) {
    return null
  }

  return (
    <div className="fixed top-0 left-0 right-0 z-50">
      <Alert variant="destructive" className="rounded-none border-x-0 border-t-0">
        <AlertDescription className="text-center">
          You&apos;re currently offline. Some features may not be available.
        </AlertDescription>
      </Alert>
    </div>
  )
}