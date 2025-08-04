// Common types for store patterns

export interface AsyncState<T> {
  data: T | null
  loading: boolean
  error: string | null
  lastFetch: number | null
}

export interface AsyncActions<T> {
  fetch: () => Promise<void>
  refetch: () => Promise<void>
  setData: (data: T) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  reset: () => void
}

export interface PaginatedState<T> {
  data: T[]
  total: number
  page: number
  pageSize: number
  hasNextPage: boolean
  hasPreviousPage: boolean
  loading: boolean
  error: string | null
}

export interface PaginatedActions<T> {
  fetchPage: (page: number, pageSize?: number) => Promise<void>
  nextPage: () => Promise<void>
  previousPage: () => Promise<void>
  setPageSize: (pageSize: number) => Promise<void>
  refresh: () => Promise<void>
  addItem: (item: T) => void
  updateItem: (id: string, updates: Partial<T>) => void
  removeItem: (id: string) => void
  reset: () => void
}

export interface OptimisticUpdate<T> {
  id: string
  type: 'create' | 'update' | 'delete'
  data: T
  originalData?: T
  timestamp: number
}

export interface OptimisticState<T> {
  pendingUpdates: OptimisticUpdate<T>[]
}

export interface OptimisticActions<T> {
  addOptimisticUpdate: (update: Omit<OptimisticUpdate<T>, 'id' | 'timestamp'>) => string
  confirmUpdate: (id: string) => void
  revertUpdate: (id: string) => void
  clearPendingUpdates: () => void
}

export interface FilterState {
  search: string
  filters: Record<string, any>
  sortBy: string | null
  sortOrder: 'asc' | 'desc'
}

export interface FilterActions {
  setSearch: (search: string) => void
  setFilter: (key: string, value: any) => void
  removeFilter: (key: string) => void
  clearFilters: () => void
  setSorting: (field: string, order?: 'asc' | 'desc') => void
  clearSorting: () => void
  reset: () => void
}

export interface User {
  id: string
  name: string
  email: string
  avatar?: string
  role: string
  permissions: string[]
  preferences: UserPreferences
  createdAt: string
  updatedAt: string
}

export interface UserPreferences {
  theme: 'light' | 'dark' | 'system'
  language: string
  timezone: string
  notifications: {
    email: boolean
    push: boolean
    inApp: boolean
  }
  dashboard: {
    layout: 'grid' | 'list'
    density: 'compact' | 'comfortable' | 'spacious'
    sidebarCollapsed: boolean
  }
}

export interface Tenant {
  id: string
  name: string
  slug: string
  domain?: string
  avatar?: string
  plan: 'free' | 'pro' | 'enterprise'
  status: 'active' | 'inactive' | 'suspended'
  settings: TenantSettings
  usage: TenantUsage
  createdAt: string
  updatedAt: string
}

export interface TenantSettings {
  allowUserRegistration: boolean
  requireEmailVerification: boolean
  enableTwoFactor: boolean
  maxUsers: number
  features: string[]
  integrations: Record<string, any>
}

export interface TenantUsage {
  users: number
  apiCalls: number
  storage: number
  bandwidth: number
  period: {
    start: string
    end: string
  }
  limits: {
    users: number
    apiCalls: number
    storage: number
    bandwidth: number
  }
}

export interface AnalyticsData {
  metrics: {
    totalUsers: number
    activeUsers: number
    apiCalls: number
    revenue: number
    conversionRate: number
  }
  timeSeries: {
    date: string
    users: number
    apiCalls: number
    revenue: number
  }[]
  topPages: {
    path: string
    views: number
    uniqueViews: number
  }[]
  userSegments: {
    segment: string
    count: number
    percentage: number
  }[]
  performanceMetrics: {
    averageResponseTime: number
    errorRate: number
    uptime: number
  }
}

export interface UIState {
  sidebarCollapsed: boolean
  sidebarMobile: boolean
  theme: 'light' | 'dark' | 'system'
  commandPaletteOpen: boolean
  notifications: Notification[]
  modals: {
    [key: string]: boolean
  }
  loading: {
    [key: string]: boolean
  }
}

export interface Notification {
  id: string
  title: string
  message: string
  type: 'info' | 'success' | 'warning' | 'error'
  read: boolean
  createdAt: string
  actions?: NotificationAction[]
}

export interface NotificationAction {
  label: string
  action: () => void
  style?: 'primary' | 'secondary' | 'destructive'
}

export interface OfflineAction {
  id: string
  type: string
  payload: any
  timestamp: number
  retryCount: number
  maxRetries: number
}

export interface CacheEntry<T> {
  data: T
  timestamp: number
  expiresAt: number
  etag?: string
}