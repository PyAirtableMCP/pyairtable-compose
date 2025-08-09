import { createContext, useContext, useState, useEffect, type ReactNode } from 'react'
import { apiClient } from '@/lib/api'

interface User {
  id: string
  email: string
  name: string
  first_name?: string
  last_name?: string
  role: string
  tenant_id?: string
  avatar?: string
}

interface AuthContextType {
  user: User | null
  isLoading: boolean
  isAuthenticated: boolean
  error: string | null
  login: (email: string, password: string) => Promise<boolean>
  register: (name: string, email: string, password: string) => Promise<boolean>
  logout: () => void
  refreshToken: () => Promise<boolean>
  clearError: () => void
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    // Check if user is authenticated on app load
    initializeAuth()
  }, [])

  const initializeAuth = async () => {
    const token = localStorage.getItem('auth_token')
    if (token) {
      // Set token in API client
      apiClient.setToken(token)
      // Validate current token by fetching user data
      await validateToken()
    } else {
      setIsLoading(false)
    }
  }

  const validateToken = async () => {
    try {
      const response = await apiClient.request('/api/v1/auth/me')
      if (response.success && response.data) {
        const responseData = response.data as any
        const userData = responseData?.user || responseData
        if (userData && typeof userData === 'object' && 'id' in userData) {
          setUser(userData as User)
          setError(null)
        } else {
          clearAuthData()
        }
      } else {
        // Token is invalid, clear it
        clearAuthData()
      }
    } catch (error) {
      console.error('Token validation failed:', error)
      clearAuthData()
    } finally {
      setIsLoading(false)
    }
  }

  const clearAuthData = () => {
    localStorage.removeItem('auth_token')
    localStorage.removeItem('refresh_token')
    apiClient.setToken(null)
    setUser(null)
    setError(null)
  }

  const login = async (email: string, password: string): Promise<boolean> => {
    try {
      setIsLoading(true)
      setError(null)

      const response = await apiClient.login({ email, password })
      
      if (response.success && response.data) {
        const data = response.data as any
        const { access_token, refresh_token, token, user: userData } = data
        
        // Handle both possible response formats
        const authToken = access_token || token
        const userInfo = userData || data.user || data
        
        if (authToken && userInfo && typeof userInfo === 'object') {
          localStorage.setItem('auth_token', authToken)
          if (refresh_token) {
            localStorage.setItem('refresh_token', refresh_token)
          }
          apiClient.setToken(authToken)
          setUser(userInfo as User)
          setError(null)
          return true
        } else {
          throw new Error('No authentication token received')
        }
      } else {
        const errorMessage = response.error || response.message || 'Login failed'
        setError(errorMessage)
        return false
      }
    } catch (error) {
      console.error('Login error:', error)
      const errorMessage = error instanceof Error ? error.message : 'An unexpected error occurred'
      setError(errorMessage)
      return false
    } finally {
      setIsLoading(false)
    }
  }

  const register = async (name: string, email: string, password: string): Promise<boolean> => {
    try {
      setIsLoading(true)
      setError(null)

      const response = await apiClient.register({ name, email, password })
      
      if (response.success && response.data) {
        // Registration successful - could auto-login or require manual login
        // For now, we'll require manual login after registration
        setError(null)
        return true
      } else {
        const errorMessage = response.error || response.message || 'Registration failed'
        setError(errorMessage)
        return false
      }
    } catch (error) {
      console.error('Registration error:', error)
      const errorMessage = error instanceof Error ? error.message : 'An unexpected error occurred'
      setError(errorMessage)
      return false
    } finally {
      setIsLoading(false)
    }
  }

  const logout = async () => {
    try {
      setIsLoading(true)
      
      // Attempt to call logout endpoint to invalidate tokens server-side
      const refreshToken = localStorage.getItem('refresh_token')
      if (refreshToken) {
        await apiClient.request('/api/v1/auth/logout', {
          method: 'POST',
          body: JSON.stringify({ refresh_token: refreshToken })
        })
      }
    } catch (error) {
      console.error('Logout API call failed:', error)
      // Continue with client-side cleanup even if server logout fails
    } finally {
      clearAuthData()
      setIsLoading(false)
    }
  }

  const refreshToken = async (): Promise<boolean> => {
    try {
      const refreshToken = localStorage.getItem('refresh_token')
      if (!refreshToken) {
        clearAuthData()
        return false
      }

      const response = await apiClient.request('/api/v1/auth/refresh', {
        method: 'POST',
        body: JSON.stringify({ refresh_token: refreshToken })
      })

      if (response.success && response.data) {
        const data = response.data as any
        const { access_token, refresh_token: newRefreshToken } = data
        
        if (access_token) {
          localStorage.setItem('auth_token', access_token)
          if (newRefreshToken) {
            localStorage.setItem('refresh_token', newRefreshToken)
          }
          apiClient.setToken(access_token)
          setError(null)
          return true
        }
      }
      
      // Refresh failed, clear auth data
      clearAuthData()
      return false
    } catch (error) {
      console.error('Token refresh failed:', error)
      clearAuthData()
      return false
    }
  }

  const clearError = () => {
    setError(null)
  }

  // Set up automatic token refresh
  useEffect(() => {
    if (user && !isLoading) {
      // Check token expiration every 23 hours (tokens expire in 24h)
      const refreshInterval = setInterval(() => {
        refreshToken()
      }, 23 * 60 * 60 * 1000) // 23 hours

      return () => clearInterval(refreshInterval)
    }
  }, [user, isLoading])

  const value: AuthContextType = {
    user,
    isLoading,
    isAuthenticated: !!user,
    error,
    login,
    register,
    logout,
    refreshToken,
    clearError
  }

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  )
}

export const useAuth = () => {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}