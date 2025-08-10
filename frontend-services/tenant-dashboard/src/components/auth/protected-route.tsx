"use client"

import React, { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'
import { Card, CardContent } from '@/components/ui/card'
import { Loader2, Shield } from 'lucide-react'

interface ProtectedRouteProps {
  children: React.ReactNode
  requiredRole?: string | string[]
  fallbackUrl?: string
  loadingComponent?: React.ReactNode
  unauthorizedComponent?: React.ReactNode
}

export function ProtectedRoute({
  children,
  requiredRole,
  fallbackUrl = "/auth/login",
  loadingComponent,
  unauthorizedComponent,
}: ProtectedRouteProps) {
  const { isAuthenticated, isLoading, user } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      const currentUrl = window.location.pathname + window.location.search
      const loginUrl = `${fallbackUrl}?callbackUrl=${encodeURIComponent(currentUrl)}`
      router.push(loginUrl)
    }
  }, [isLoading, isAuthenticated, router, fallbackUrl])

  // Show loading state
  if (isLoading || !isAuthenticated) {
    if (loadingComponent) {
      return <>{loadingComponent}</>
    }

    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
        <Card className="w-full max-w-md">
          <CardContent className="p-8 text-center">
            <Loader2 className="h-8 w-8 animate-spin mx-auto mb-4 text-primary" />
            <h2 className="text-xl font-semibold mb-2">Loading...</h2>
            <p className="text-muted-foreground">
              {!isAuthenticated ? 'Redirecting to login...' : 'Loading your dashboard...'}
            </p>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Check role requirements
  if (requiredRole && user) {
    const userRole = user.role
    const hasRequiredRole = Array.isArray(requiredRole)
      ? requiredRole.includes(userRole)
      : userRole === requiredRole

    if (!hasRequiredRole) {
      if (unauthorizedComponent) {
        return <>{unauthorizedComponent}</>
      }

      return (
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-red-50 to-rose-100 p-4">
          <Card className="w-full max-w-md">
            <CardContent className="p-8 text-center">
              <div className="mx-auto mb-4 h-12 w-12 bg-red-100 rounded-full flex items-center justify-center">
                <Shield className="h-6 w-6 text-red-600" />
              </div>
              <h2 className="text-xl font-semibold mb-2">Access Denied</h2>
              <p className="text-muted-foreground mb-4">
                You don't have permission to access this page.
              </p>
              <p className="text-sm text-muted-foreground">
                Required role: {Array.isArray(requiredRole) ? requiredRole.join(' or ') : requiredRole}
                <br />
                Your role: {userRole}
              </p>
            </CardContent>
          </Card>
        </div>
      )
    }
  }

  return <>{children}</>
}

// Higher-order component version
export function withAuth<T extends object>(
  Component: React.ComponentType<T>,
  options?: Omit<ProtectedRouteProps, 'children'>
) {
  return function AuthenticatedComponent(props: T) {
    return (
      <ProtectedRoute {...options}>
        <Component {...props} />
      </ProtectedRoute>
    )
  }
}

// Hook version for use in components
export function useProtectedRoute(
  requiredRole?: string | string[],
  redirectUrl?: string
) {
  const { isAuthenticated, isLoading, user } = useAuth()
  const router = useRouter()

  const checkAccess = React.useCallback(() => {
    if (!isLoading && !isAuthenticated) {
      const currentUrl = window.location.pathname + window.location.search
      const loginUrl = `${redirectUrl || '/auth/login'}?callbackUrl=${encodeURIComponent(currentUrl)}`
      router.push(loginUrl)
      return false
    }

    if (requiredRole && user) {
      const userRole = user.role
      const hasRequiredRole = Array.isArray(requiredRole)
        ? requiredRole.includes(userRole)
        : userRole === requiredRole

      if (!hasRequiredRole) {
        router.push('/unauthorized')
        return false
      }
    }

    return true
  }, [isLoading, isAuthenticated, user, requiredRole, router, redirectUrl])

  useEffect(() => {
    checkAccess()
  }, [checkAccess])

  return {
    isAuthenticated: isAuthenticated && !isLoading,
    user,
    hasAccess: checkAccess(),
  }
}