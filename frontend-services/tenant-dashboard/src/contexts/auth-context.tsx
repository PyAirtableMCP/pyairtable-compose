"use client"

import React, { createContext, useContext, useEffect, useState } from 'react'
import { useSession, signOut } from 'next-auth/react'
import { authClient, type ApiError } from '@/lib/auth-client'
import toast from 'react-hot-toast'

export interface User {
  id: string
  email: string
  name?: string
  role: string
  tenantId?: string
  emailVerified: boolean
}

export interface AuthState {
  user: User | null
  isLoading: boolean
  isAuthenticated: boolean
  accessToken: string | null
  refreshToken: string | null
}

export interface AuthContextType extends AuthState {
  logout: () => Promise<void>
  refreshTokens: () => Promise<boolean>
  updateUser: (user: Partial<User>) => void
  checkTokenExpiry: () => boolean
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

interface AuthProviderProps {
  children: React.ReactNode
}

export function AuthProvider({ children }: AuthProviderProps) {
  const { data: session, status } = useSession()
  const [authState, setAuthState] = useState<AuthState>({
    user: null,
    isLoading: true,
    isAuthenticated: false,
    accessToken: null,
    refreshToken: null,
  })

  // Initialize auth state from session
  useEffect(() => {
    if (status === 'loading') {
      setAuthState(prev => ({ ...prev, isLoading: true }))
      return
    }

    if (status === 'unauthenticated' || !session) {
      setAuthState({
        user: null,
        isLoading: false,
        isAuthenticated: false,
        accessToken: null,
        refreshToken: null,
      })
      return
    }

    if (session) {
      const user: User = {
        id: session.user.id,
        email: session.user.email,
        name: session.user.name || undefined,
        role: session.user.role || 'user',
        tenantId: session.user.tenantId,
        emailVerified: true, // Assume verified if session exists
      }

      setAuthState({
        user,
        isLoading: false,
        isAuthenticated: true,
        accessToken: session.accessToken || null,
        refreshToken: session.refreshToken || null,
      })
    }
  }, [session, status])

  const logout = async () => {
    try {
      // Call backend logout if we have an access token
      if (authState.accessToken) {
        try {
          await authClient.logout(authState.accessToken)
        } catch (error) {
          console.warn('Backend logout failed:', error)
          // Continue with frontend logout even if backend fails
        }
      }

      // Sign out from NextAuth
      await signOut({
        redirect: false,
      })

      // Clear auth state
      setAuthState({
        user: null,
        isLoading: false,
        isAuthenticated: false,
        accessToken: null,
        refreshToken: null,
      })

      toast.success('Signed out successfully')
    } catch (error) {
      console.error('Logout error:', error)
      toast.error('Error during logout')
    }
  }

  const refreshTokens = async (): Promise<boolean> => {
    try {
      if (!authState.refreshToken) {
        console.warn('No refresh token available')
        return false
      }

      const response = await authClient.refreshToken(authState.refreshToken)
      
      // Update auth state with new tokens
      setAuthState(prev => ({
        ...prev,
        accessToken: response.access_token,
        refreshToken: response.refresh_token,
        user: prev.user ? {
          ...prev.user,
          ...response.user,
        } : {
          id: response.user.id,
          email: response.user.email,
          name: response.user.name,
          role: response.user.role,
          tenantId: response.user.tenant_id,
          emailVerified: response.user.email_verified,
        },
      }))

      return true
    } catch (error) {
      console.error('Token refresh failed:', error)
      
      // If refresh fails, logout user
      await logout()
      return false
    }
  }

  const updateUser = (updates: Partial<User>) => {
    setAuthState(prev => ({
      ...prev,
      user: prev.user ? { ...prev.user, ...updates } : null,
    }))
  }

  const checkTokenExpiry = (): boolean => {
    if (!authState.accessToken) return false
    
    try {
      return !authClient.isTokenExpired(authState.accessToken)
    } catch {
      return false
    }
  }

  // Auto-refresh tokens when they're about to expire
  useEffect(() => {
    if (!authState.isAuthenticated || !authState.accessToken) return

    const checkAndRefreshToken = () => {
      const tokenPayload = authClient.decodeToken(authState.accessToken!)
      if (!tokenPayload) return

      // Refresh if token expires in less than 5 minutes
      const expirationTime = tokenPayload.exp * 1000
      const currentTime = Date.now()
      const timeUntilExpiry = expirationTime - currentTime
      const refreshThreshold = 5 * 60 * 1000 // 5 minutes

      if (timeUntilExpiry <= refreshThreshold && timeUntilExpiry > 0) {
        console.log('Token expiring soon, refreshing...')
        refreshTokens()
      }
    }

    // Check immediately and then every minute
    checkAndRefreshToken()
    const interval = setInterval(checkAndRefreshToken, 60 * 1000)

    return () => clearInterval(interval)
  }, [authState.isAuthenticated, authState.accessToken])

  const value: AuthContextType = {
    ...authState,
    logout,
    refreshTokens,
    updateUser,
    checkTokenExpiry,
  }

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth(): AuthContextType {
  const context = useContext(AuthContext)
  
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  
  return context
}

// Hook for protected components
export function useRequireAuth(): AuthContextType {
  const auth = useAuth()
  
  useEffect(() => {
    if (!auth.isLoading && !auth.isAuthenticated) {
      // Redirect to login will be handled by middleware
      toast.error('Please sign in to access this page')
    }
  }, [auth.isLoading, auth.isAuthenticated])
  
  return auth
}

// Hook with automatic token refresh
export function useAuthWithRefresh(): AuthContextType {
  const auth = useAuth()
  
  useEffect(() => {
    const ensureValidToken = async () => {
      if (auth.isAuthenticated && auth.accessToken) {
        const isValid = auth.checkTokenExpiry()
        if (!isValid) {
          console.log('Token expired, attempting refresh...')
          await auth.refreshTokens()
        }
      }
    }
    
    ensureValidToken()
  }, [auth])
  
  return auth
}