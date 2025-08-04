"use client"

import * as React from "react"
import { 
  Database, 
  Search, 
  Plus, 
  FileText, 
  Users, 
  Building2, 
  BarChart3,
  Settings,
  AlertCircle,
  Inbox,
  Shield,
  Zap,
} from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"

interface EmptyStateProps {
  title: string
  description: string
  icon?: React.ComponentType<{ className?: string }> | keyof typeof iconMap
  action?: {
    label: string
    onClick: () => void
    variant?: "default" | "outline" | "secondary"
  }
  secondaryAction?: {
    label: string
    onClick: () => void
  }
  illustration?: React.ReactNode
  size?: "sm" | "md" | "lg"
  className?: string
}

// Predefined icons for common scenarios
const iconMap = {
  database: Database,
  search: Search,
  add: Plus,
  document: FileText,
  users: Users,
  building: Building2,
  analytics: BarChart3,
  settings: Settings,
  error: AlertCircle,
  inbox: Inbox,
  security: Shield,
  feature: Zap,
} as const

export function EmptyState({
  title,
  description,
  icon = "database",
  action,
  secondaryAction,
  illustration,
  size = "md",
  className,
}: EmptyStateProps) {
  // Determine the icon component
  const IconComponent = React.useMemo(() => {
    if (typeof icon === "string") {
      return iconMap[icon] || Database
    }
    return icon
  }, [icon])

  const getSizeClasses = () => {
    switch (size) {
      case "sm":
        return {
          container: "py-8",
          icon: "h-12 w-12",
          title: "text-lg",
          description: "text-sm",
          spacing: "space-y-3",
        }
      case "lg":
        return {
          container: "py-16",
          icon: "h-20 w-20",
          title: "text-3xl",
          description: "text-lg",
          spacing: "space-y-6",
        }
      default:
        return {
          container: "py-12",
          icon: "h-16 w-16",
          title: "text-xl",
          description: "text-base",
          spacing: "space-y-4",
        }
    }
  }

  const sizeClasses = getSizeClasses()

  return (
    <div className={cn("flex items-center justify-center", sizeClasses.container, className)}>
      <div className={cn("text-center max-w-md mx-auto", sizeClasses.spacing)}>
        {illustration ? (
          <div className="flex justify-center mb-4">
            {illustration}
          </div>
        ) : (
          <div className="flex justify-center">
            <div className="rounded-full bg-muted p-4">
              <IconComponent className={cn(sizeClasses.icon, "text-muted-foreground")} />
            </div>
          </div>
        )}

        <div className="space-y-2">
          <h3 className={cn("font-semibold text-foreground", sizeClasses.title)}>
            {title}
          </h3>
          <p className={cn("text-muted-foreground", sizeClasses.description)}>
            {description}
          </p>
        </div>

        {(action || secondaryAction) && (
          <div className="flex flex-col sm:flex-row gap-2 justify-center">
            {action && (
              <Button
                onClick={action.onClick}
                variant={action.variant || "default"}
                size={size === "sm" ? "sm" : "default"}
              >
                {action.label}
              </Button>
            )}
            {secondaryAction && (
              <Button
                onClick={secondaryAction.onClick}
                variant="outline"
                size={size === "sm" ? "sm" : "default"}
              >
                {secondaryAction.label}
              </Button>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

// Specialized empty states for common scenarios
export function NoDataFound({ onRefresh }: { onRefresh?: () => void }) {
  return (
    <EmptyState
      icon="search"
      title="No data found"
      description="We couldn't find any data matching your criteria. Try adjusting your filters or search terms."
      action={onRefresh ? {
        label: "Refresh",
        onClick: onRefresh,
        variant: "outline",
      } : undefined}
    />
  )
}

export function NoResultsFound({ onClear }: { onClear?: () => void }) {
  return (
    <EmptyState
      icon="search"
      title="No results found"
      description="Your search didn't return any results. Try different keywords or check your spelling."
      action={onClear ? {
        label: "Clear search",
        onClick: onClear,
        variant: "outline",
      } : undefined}
      size="sm"
    />
  )
}

export function CreateFirstItem({ 
  title, 
  description, 
  onCreateClick,
  createLabel = "Create first item",
}: { 
  title: string
  description: string
  onCreateClick: () => void
  createLabel?: string
}) {
  return (
    <EmptyState
      icon="add"
      title={title}
      description={description}
      action={{
        label: createLabel,
        onClick: onCreateClick,
      }}
    />
  )
}

export function ErrorState({ 
  error, 
  onRetry 
}: { 
  error: string
  onRetry?: () => void 
}) {
  return (
    <EmptyState
      icon="error"
      title="Something went wrong"
      description={error || "An unexpected error occurred. Please try again."}
      action={onRetry ? {
        label: "Try again",
        onClick: onRetry,
        variant: "outline",
      } : undefined}
    />
  )
}

export function UnauthorizedState({ onLogin }: { onLogin?: () => void }) {
  return (
    <EmptyState
      icon="security"
      title="Access denied"
      description="You don't have permission to view this content. Please contact your administrator or sign in with appropriate credentials."
      action={onLogin ? {
        label: "Sign in",
        onClick: onLogin,
      } : undefined}
    />
  )
}

export function MaintenanceState() {
  return (
    <EmptyState
      icon="settings"
      title="Under maintenance"
      description="This feature is temporarily unavailable while we perform maintenance. Please check back later."
      size="lg"
    />
  )
}

export function ComingSoonState({ feature }: { feature: string }) {
  return (
    <EmptyState
      icon="feature"
      title="Coming soon"
      description={`${feature} is currently under development and will be available in a future update.`}
    />
  )
}

// Card wrapper for empty states in constrained spaces
export function EmptyStateCard(props: EmptyStateProps) {
  return (
    <Card>
      <CardContent className="p-0">
        <EmptyState {...props} size="sm" />
      </CardContent>
    </Card>
  )
}