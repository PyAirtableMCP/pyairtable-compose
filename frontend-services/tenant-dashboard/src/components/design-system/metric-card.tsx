"use client"

import * as React from "react"
import { TrendingUp, TrendingDown, Minus, MoreHorizontal } from "lucide-react"
import { cn } from "@/lib/utils"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

interface MetricCardProps {
  title: string
  value: string | number
  description?: string
  icon?: React.ComponentType<{ className?: string }>
  change?: {
    value: number
    label: string
    trend: "up" | "down" | "neutral"
  }
  actions?: Array<{
    label: string
    onClick: () => void
    destructive?: boolean
  }>
  loading?: boolean
  className?: string
  size?: "sm" | "md" | "lg"
  variant?: "default" | "outline" | "success" | "warning" | "destructive"
}

export function MetricCard({
  title,
  value,
  description,
  icon: Icon,
  change,
  actions,
  loading = false,
  className,
  size = "md",
  variant = "default",
}: MetricCardProps) {
  const formatValue = (val: string | number) => {
    if (typeof val === "number") {
      if (val >= 1000000) {
        return `${(val / 1000000).toFixed(1)}M`
      } else if (val >= 1000) {
        return `${(val / 1000).toFixed(1)}K`
      }
      return val.toLocaleString()
    }
    return val
  }

  const getTrendIcon = (trend: "up" | "down" | "neutral") => {
    switch (trend) {
      case "up":
        return <TrendingUp className="h-3 w-3" />
      case "down":
        return <TrendingDown className="h-3 w-3" />
      default:
        return <Minus className="h-3 w-3" />
    }
  }

  const getTrendColor = (trend: "up" | "down" | "neutral") => {
    switch (trend) {
      case "up":
        return "text-green-600 dark:text-green-400"
      case "down":
        return "text-red-600 dark:text-red-400"
      default:
        return "text-muted-foreground"
    }
  }

  const getCardVariant = () => {
    switch (variant) {
      case "outline":
        return "border-2"
      case "success":
        return "border-green-200 bg-green-50 dark:border-green-800 dark:bg-green-950"
      case "warning":
        return "border-yellow-200 bg-yellow-50 dark:border-yellow-800 dark:bg-yellow-950"
      case "destructive":
        return "border-red-200 bg-red-50 dark:border-red-800 dark:bg-red-950"
      default:
        return ""
    }
  }

  const getSizeClasses = () => {
    switch (size) {
      case "sm":
        return {
          card: "p-4",
          title: "text-sm",
          value: "text-xl",
          description: "text-xs",
        }
      case "lg":
        return {
          card: "p-8",
          title: "text-lg",
          value: "text-4xl",
          description: "text-base",
        }
      default:
        return {
          card: "p-6",
          title: "text-base",
          value: "text-2xl",
          description: "text-sm",
        }
    }
  }

  const sizeClasses = getSizeClasses()

  if (loading) {
    return (
      <Card className={cn(getCardVariant(), className)}>
        <CardContent className={sizeClasses.card}>
          <div className="flex items-center justify-between">
            <div className="space-y-2 flex-1">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-8 w-16" />
              <Skeleton className="h-3 w-32" />
            </div>
            {Icon && <Skeleton className="h-6 w-6" />}
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card className={cn(getCardVariant(), className)}>
      <CardContent className={sizeClasses.card}>
        <div className="flex items-start justify-between">
          <div className="space-y-2 flex-1">
            <div className="flex items-center justify-between">
              <p className={cn("font-medium text-muted-foreground", sizeClasses.title)}>
                {title}
              </p>
              {actions && actions.length > 0 && (
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="ghost" size="sm" className="h-6 w-6 p-0">
                      <MoreHorizontal className="h-4 w-4" />
                      <span className="sr-only">Open menu</span>
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    {actions.map((action, index) => (
                      <DropdownMenuItem
                        key={index}
                        onClick={action.onClick}
                        className={action.destructive ? "text-destructive" : ""}
                      >
                        {action.label}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
            </div>

            <div className="flex items-baseline gap-2">
              <p className={cn("font-bold text-foreground", sizeClasses.value)}>
                {formatValue(value)}
              </p>
              {change && (
                <Badge
                  variant="secondary"
                  className={cn(
                    "flex items-center gap-1 text-xs font-medium",
                    getTrendColor(change.trend)
                  )}
                >
                  {getTrendIcon(change.trend)}
                  {Math.abs(change.value)}%
                </Badge>
              )}
            </div>

            {description && (
              <p className={cn("text-muted-foreground", sizeClasses.description)}>
                {description}
              </p>
            )}

            {change && (
              <p className={cn("text-muted-foreground", sizeClasses.description)}>
                {change.label}
              </p>
            )}
          </div>

          {Icon && (
            <div className="flex-shrink-0">
              <Icon className="h-6 w-6 text-muted-foreground" />
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// Compound component for multiple metrics
interface MetricGridProps {
  children: React.ReactNode
  columns?: 1 | 2 | 3 | 4
  className?: string
}

export function MetricGrid({ children, columns = 4, className }: MetricGridProps) {
  const getGridColumns = () => {
    switch (columns) {
      case 1:
        return "grid-cols-1"
      case 2:
        return "grid-cols-1 md:grid-cols-2"
      case 3:
        return "grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
      default:
        return "grid-cols-1 md:grid-cols-2 lg:grid-cols-4"
    }
  }

  return (
    <div className={cn("grid gap-4", getGridColumns(), className)}>
      {children}
    </div>
  )
}

// Specialized metric cards
export function RevenueCard({ amount, change, loading }: { 
  amount: number
  change?: MetricCardProps["change"]
  loading?: boolean 
}) {
  return (
    <MetricCard
      title="Revenue"
      value={`$${amount.toLocaleString()}`}
      change={change}
      loading={loading}
      variant="success"
    />
  )
}

export function UserCard({ count, change, loading }: { 
  count: number
  change?: MetricCardProps["change"]
  loading?: boolean 
}) {
  return (
    <MetricCard
      title="Active Users"
      value={count}
      change={change}
      loading={loading}
    />
  )
}

export function ConversionCard({ rate, change, loading }: { 
  rate: number
  change?: MetricCardProps["change"]
  loading?: boolean 
}) {
  return (
    <MetricCard
      title="Conversion Rate"
      value={`${rate}%`}
      change={change}
      loading={loading}
      variant="outline"
    />
  )
}