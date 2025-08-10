"use client"

import { useAuth } from '@/contexts/auth-context'
import { authClient, type ApiError } from '@/lib/auth-client'
import { useCallback } from 'react'
import toast from 'react-hot-toast'

interface ApiOptions extends RequestInit {
  showErrorToast?: boolean
  showSuccessToast?: boolean
  successMessage?: string
}

export function useApi() {
  const { accessToken, isAuthenticated, refreshTokens, logout } = useAuth()

  const makeRequest = useCallback(
    async <T>(
      url: string,
      options: ApiOptions = {}
    ): Promise<T> => {
      const {
        showErrorToast = true,
        showSuccessToast = false,
        successMessage = 'Success!',
        ...requestOptions
      } = options

      try {
        // Ensure user is authenticated for protected endpoints
        if (!isAuthenticated) {
          throw new Error('Authentication required')
        }

        // Prepare headers
        const headers = {
          'Content-Type': 'application/json',
          ...requestOptions.headers,
        }

        // Add authorization header if we have a token
        if (accessToken) {
          headers['Authorization'] = `Bearer ${accessToken}`
        }

        // Make the request
        const response = await fetch(url, {
          ...requestOptions,
          headers,
        })

        // Handle token expiration
        if (response.status === 401) {
          console.log('Token expired, attempting refresh...')
          const refreshed = await refreshTokens()
          
          if (refreshed) {
            // Retry the request with new token
            headers['Authorization'] = `Bearer ${accessToken}`
            const retryResponse = await fetch(url, {
              ...requestOptions,
              headers,
            })
            
            if (!retryResponse.ok) {
              const errorData = await retryResponse.json()
              throw {
                error: errorData.error || 'Request failed',
                message: errorData.message,
                status_code: retryResponse.status,
              } as ApiError
            }
            
            const data = await retryResponse.json()
            
            if (showSuccessToast) {
              toast.success(successMessage)
            }
            
            return data as T
          } else {
            // Refresh failed, logout user
            await logout()
            throw new Error('Session expired. Please sign in again.')
          }
        }

        // Handle other errors
        if (!response.ok) {
          const errorData = await response.json()
          throw {
            error: errorData.error || 'Request failed',
            message: errorData.message,
            status_code: response.status,
          } as ApiError
        }

        // Parse successful response
        const data = await response.json()
        
        if (showSuccessToast) {
          toast.success(successMessage)
        }
        
        return data as T
      } catch (error) {
        console.error('API request error:', error)
        
        if (showErrorToast) {
          const message = (error as ApiError)?.error || 
                         (error as Error)?.message || 
                         'An unexpected error occurred'
          toast.error(message)
        }
        
        throw error
      }
    },
    [accessToken, isAuthenticated, refreshTokens, logout]
  )

  // HTTP method helpers
  const get = useCallback(
    <T>(url: string, options?: Omit<ApiOptions, 'method' | 'body'>) =>
      makeRequest<T>(url, { ...options, method: 'GET' }),
    [makeRequest]
  )

  const post = useCallback(
    <T>(
      url: string,
      data?: any,
      options?: Omit<ApiOptions, 'method' | 'body'>
    ) =>
      makeRequest<T>(url, {
        ...options,
        method: 'POST',
        body: data ? JSON.stringify(data) : undefined,
      }),
    [makeRequest]
  )

  const put = useCallback(
    <T>(
      url: string,
      data?: any,
      options?: Omit<ApiOptions, 'method' | 'body'>
    ) =>
      makeRequest<T>(url, {
        ...options,
        method: 'PUT',
        body: data ? JSON.stringify(data) : undefined,
      }),
    [makeRequest]
  )

  const patch = useCallback(
    <T>(
      url: string,
      data?: any,
      options?: Omit<ApiOptions, 'method' | 'body'>
    ) =>
      makeRequest<T>(url, {
        ...options,
        method: 'PATCH',
        body: data ? JSON.stringify(data) : undefined,
      }),
    [makeRequest]
  )

  const del = useCallback(
    <T>(url: string, options?: Omit<ApiOptions, 'method'>) =>
      makeRequest<T>(url, { ...options, method: 'DELETE' }),
    [makeRequest]
  )

  return {
    request: makeRequest,
    get,
    post,
    put,
    patch,
    delete: del,
  }
}

// Hook for auth-specific API calls
export function useAuthApi() {
  const api = useApi()

  const changePassword = useCallback(
    async (currentPassword: string, newPassword: string) => {
      return api.post(
        `${process.env.NEXT_PUBLIC_AUTH_SERVICE_URL || 'http://localhost:8009'}/auth/change-password`,
        { current_password: currentPassword, new_password: newPassword },
        {
          showSuccessToast: true,
          successMessage: 'Password changed successfully!',
        }
      )
    },
    [api]
  )

  const getCurrentUser = useCallback(async () => {
    return api.get(
      `${process.env.NEXT_PUBLIC_AUTH_SERVICE_URL || 'http://localhost:8009'}/auth/me`
    )
  }, [api])

  return {
    changePassword,
    getCurrentUser,
  }
}

// Hook for making authenticated requests to any service
export function useAuthenticatedRequest() {
  const { accessToken, isAuthenticated } = useAuth()

  const makeAuthenticatedRequest = useCallback(
    async <T>(url: string, options: RequestInit = {}): Promise<T> => {
      if (!isAuthenticated || !accessToken) {
        throw new Error('Authentication required')
      }

      const headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
        ...options.headers,
      }

      const response = await fetch(url, {
        ...options,
        headers,
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Request failed')
      }

      return response.json() as T
    },
    [accessToken, isAuthenticated]
  )

  return { makeAuthenticatedRequest }
}