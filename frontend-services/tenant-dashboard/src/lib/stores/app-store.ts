/**
 * Main Application Store
 * Combines multiple slices using Zustand with middleware
 */

import { create } from 'zustand'
import { devtools, subscribeWithSelector } from 'zustand/middleware'
import { immer } from 'zustand/middleware/immer'
import { persist } from 'zustand/middleware'

import { User, Tenant, UIState, Notification } from './types'
import { createStoreSlice } from './utils/create-slice'

// UI State Slice
const createUISlice = createStoreSlice<UIState & {
  // Actions
  toggleSidebar: () => void
  setSidebarMobile: (open: boolean) => void
  setTheme: (theme: 'light' | 'dark' | 'system') => void
  toggleCommandPalette: () => void
  setCommandPalette: (open: boolean) => void
  addNotification: (notification: Omit<Notification, 'id'>) => void
  markNotificationRead: (id: string) => void
  removeNotification: (id: string) => void
  clearNotifications: () => void
  openModal: (key: string) => void
  closeModal: (key: string) => void
  setLoading: (key: string, loading: boolean) => void
}>((set, get) => ({
  // State
  sidebarCollapsed: false,
  sidebarMobile: false,
  theme: 'system',
  commandPaletteOpen: false,
  notifications: [],
  modals: {},
  loading: {},

  // Actions
  toggleSidebar: () => set((state) => {
    state.sidebarCollapsed = !state.sidebarCollapsed
  }),

  setSidebarMobile: (open: boolean) => set((state) => {
    state.sidebarMobile = open
  }),

  setTheme: (theme: 'light' | 'dark' | 'system') => set((state) => {
    state.theme = theme
  }),

  toggleCommandPalette: () => set((state) => {
    state.commandPaletteOpen = !state.commandPaletteOpen
  }),

  setCommandPalette: (open: boolean) => set((state) => {
    state.commandPaletteOpen = open
  }),

  addNotification: (notification: Omit<Notification, 'id'>) => set((state) => {
    const newNotification: Notification = {
      ...notification,
      id: `notification-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      read: false,
      createdAt: new Date().toISOString(),
    }
    state.notifications.unshift(newNotification)
    
    // Auto-remove non-persistent notifications after 5 seconds
    if (notification.type !== 'error') {
      setTimeout(() => {
        get().removeNotification(newNotification.id)
      }, 5000)
    }
  }),

  markNotificationRead: (id: string) => set((state) => {
    const notification = state.notifications.find(n => n.id === id)
    if (notification) {
      notification.read = true
    }
  }),

  removeNotification: (id: string) => set((state) => {
    state.notifications = state.notifications.filter(n => n.id !== id)
  }),

  clearNotifications: () => set((state) => {
    state.notifications = []
  }),

  openModal: (key: string) => set((state) => {
    state.modals[key] = true
  }),

  closeModal: (key: string) => set((state) => {
    state.modals[key] = false
  }),

  setLoading: (key: string, loading: boolean) => set((state) => {
    if (loading) {
      state.loading[key] = true
    } else {
      delete state.loading[key]
    }
  }),
}))

// Auth State Slice
const createAuthSlice = createStoreSlice<{
  user: User | null
  isAuthenticated: boolean
  isLoading: boolean
  error: string | null
  
  // Actions
  setUser: (user: User | null) => void
  updateUser: (updates: Partial<User>) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  logout: () => void
}>((set, get) => ({
  // State
  user: null,
  isAuthenticated: false,
  isLoading: false,
  error: null,

  // Actions
  setUser: (user: User | null) => set((state) => {
    state.user = user
    state.isAuthenticated = !!user
    state.error = null
  }),

  updateUser: (updates: Partial<User>) => set((state) => {
    if (state.user) {
      Object.assign(state.user, updates)
    }
  }),

  setLoading: (loading: boolean) => set((state) => {
    state.isLoading = loading
  }),

  setError: (error: string | null) => set((state) => {
    state.error = error
    state.isLoading = false
  }),

  logout: () => set((state) => {
    state.user = null
    state.isAuthenticated = false
    state.error = null
  }),
}))

// Tenant State Slice
const createTenantSlice = createStoreSlice<{
  currentTenant: Tenant | null
  tenants: Tenant[]
  isLoading: boolean
  error: string | null
  
  // Actions
  setCurrentTenant: (tenant: Tenant | null) => void
  setTenants: (tenants: Tenant[]) => void
  updateTenant: (id: string, updates: Partial<Tenant>) => void
  addTenant: (tenant: Tenant) => void
  removeTenant: (id: string) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
}>((set, get) => ({
  // State
  currentTenant: null,
  tenants: [],
  isLoading: false,
  error: null,

  // Actions
  setCurrentTenant: (tenant: Tenant | null) => set((state) => {
    state.currentTenant = tenant
  }),

  setTenants: (tenants: Tenant[]) => set((state) => {
    state.tenants = tenants
  }),

  updateTenant: (id: string, updates: Partial<Tenant>) => set((state) => {
    // Update in tenants array
    const tenantIndex = state.tenants.findIndex(t => t.id === id)
    if (tenantIndex !== -1) {
      Object.assign(state.tenants[tenantIndex], updates)
    }
    
    // Update current tenant if it's the same
    if (state.currentTenant && state.currentTenant.id === id) {
      Object.assign(state.currentTenant, updates)
    }
  }),

  addTenant: (tenant: Tenant) => set((state) => {
    state.tenants.push(tenant)
  }),

  removeTenant: (id: string) => set((state) => {
    state.tenants = state.tenants.filter(t => t.id !== id)
    if (state.currentTenant && state.currentTenant.id === id) {
      state.currentTenant = null
    }
  }),

  setLoading: (loading: boolean) => set((state) => {
    state.isLoading = loading
  }),

  setError: (error: string | null) => set((state) => {
    state.error = error
    state.isLoading = false
  }),
}))

// Combine all slices
export const useAppStore = create<
  ReturnType<typeof createUISlice> &
  ReturnType<typeof createAuthSlice> &
  ReturnType<typeof createTenantSlice>
>()(
  devtools(
    subscribeWithSelector(
      persist(
        immer((...args) => ({
          ...createUISlice(...args),
          ...createAuthSlice(...args),
          ...createTenantSlice(...args),
        })),
        {
          name: 'pyairtable-app-store',
          partialize: (state) => ({
            // Only persist certain parts of the state
            theme: state.theme,
            sidebarCollapsed: state.sidebarCollapsed,
            user: state.user,
            currentTenant: state.currentTenant,
          }),
        }
      )
    ),
    {
      name: 'PyAirtable App Store',
    }
  )
)

// Selectors for better performance
export const useAuth = () => useAppStore((state) => ({
  user: state.user,
  isAuthenticated: state.isAuthenticated,
  isLoading: state.isLoading,
  error: state.error,
  setUser: state.setUser,
  updateUser: state.updateUser,
  setLoading: state.setLoading,
  setError: state.setError,
  logout: state.logout,
}))

export const useUI = () => useAppStore((state) => ({
  sidebarCollapsed: state.sidebarCollapsed,
  sidebarMobile: state.sidebarMobile,
  theme: state.theme,
  commandPaletteOpen: state.commandPaletteOpen,
  notifications: state.notifications,
  modals: state.modals,
  loading: state.loading,
  toggleSidebar: state.toggleSidebar,
  setSidebarMobile: state.setSidebarMobile,
  setTheme: state.setTheme,
  toggleCommandPalette: state.toggleCommandPalette,
  setCommandPalette: state.setCommandPalette,
  addNotification: state.addNotification,
  markNotificationRead: state.markNotificationRead,
  removeNotification: state.removeNotification,
  clearNotifications: state.clearNotifications,
  openModal: state.openModal,
  closeModal: state.closeModal,
  setLoading: state.setLoading,
}))

export const useTenant = () => useAppStore((state) => ({
  currentTenant: state.currentTenant,
  tenants: state.tenants,
  isLoading: state.isLoading,
  error: state.error,
  setCurrentTenant: state.setCurrentTenant,
  setTenants: state.setTenants,
  updateTenant: state.updateTenant,
  addTenant: state.addTenant,
  removeTenant: state.removeTenant,
  setLoading: state.setLoading,
  setError: state.setError,
}))

// Reactive subscriptions for side effects
if (typeof window !== 'undefined') {
  // Theme subscription
  useAppStore.subscribe(
    (state) => state.theme,
    (theme) => {
      const root = document.documentElement
      if (theme === 'dark') {
        root.classList.add('dark')
      } else if (theme === 'light') {
        root.classList.remove('dark')
      } else {
        // System theme
        const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches
        if (isDark) {
          root.classList.add('dark')
        } else {
          root.classList.remove('dark')
        }
      }
    }
  )

  // Notification cleanup subscription
  useAppStore.subscribe(
    (state) => state.notifications,
    (notifications) => {
      // Additional side effects for notifications could go here
      // e.g., browser notifications, analytics events, etc.
    }
  )
}