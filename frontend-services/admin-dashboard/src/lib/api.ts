import { toast } from 'react-hot-toast'
import { PaginatedResponse, FilterOptions, SystemHealth, ResourceMetrics, ServiceHealth, FeatureFlag, Tenant, User } from '@/types'

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:8080/api/v1'

class ApiClient {
  private baseURL: string
  private token: string | null = null

  constructor(baseURL: string) {
    this.baseURL = baseURL
    this.token = typeof window !== 'undefined' ? localStorage.getItem('auth_token') : null
  }

  setToken(token: string) {
    this.token = token
    if (typeof window !== 'undefined') {
      localStorage.setItem('auth_token', token)
    }
  }

  clearToken() {
    this.token = null
    if (typeof window !== 'undefined') {
      localStorage.removeItem('auth_token')
    }
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const url = `${this.baseURL}${endpoint}`
    
    const config: RequestInit = {
      headers: {
        'Content-Type': 'application/json',
        ...(this.token && { Authorization: `Bearer ${this.token}` }),
        ...options.headers,
      },
      ...options,
    }

    try {
      const response = await fetch(url, config)
      
      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.message || `HTTP ${response.status}: ${response.statusText}`)
      }

      return await response.json()
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Network error occurred'
      toast.error(message)
      throw error
    }
  }

  // System Health & Monitoring
  async getSystemHealth(): Promise<SystemHealth> {
    return this.request<SystemHealth>('/admin/system/health')
  }

  async getResourceMetrics(): Promise<ResourceMetrics> {
    return this.request<ResourceMetrics>('/admin/system/metrics')
  }

  async getServiceStatus(): Promise<ServiceHealth[]> {
    return this.request<ServiceHealth[]>('/admin/system/services')
  }

  async getAlerts() {
    return this.request('/admin/system/alerts')
  }

  async acknowledgeAlert(alertId: string) {
    return this.request(`/admin/system/alerts/${alertId}/acknowledge`, {
      method: 'POST',
    })
  }

  // Tenant Management
  async getTenants(options?: FilterOptions): Promise<PaginatedResponse<Tenant>> {
    const params = new URLSearchParams()
    if (options?.search) params.append('search', options.search)
    if (options?.sort) {
      params.append('sort', options.sort.field)
      params.append('order', options.sort.direction)
    }
    if (options?.pagination) {
      params.append('page', options.pagination.page.toString())
      params.append('limit', options.pagination.limit.toString())
    }
    
    return this.request(`/admin/tenants?${params.toString()}`)
  }

  async getTenant(tenantId: string) {
    return this.request(`/admin/tenants/${tenantId}`)
  }

  async createTenant(tenant: any) {
    return this.request('/admin/tenants', {
      method: 'POST',
      body: JSON.stringify(tenant),
    })
  }

  async updateTenant(tenantId: string, updates: any) {
    return this.request(`/admin/tenants/${tenantId}`, {
      method: 'PUT',
      body: JSON.stringify(updates),
    })
  }

  async suspendTenant(tenantId: string) {
    return this.request(`/admin/tenants/${tenantId}/suspend`, {
      method: 'POST',
    })
  }

  async reactivateTenant(tenantId: string) {
    return this.request(`/admin/tenants/${tenantId}/reactivate`, {
      method: 'POST',
    })
  }

  async getTenantUsage(tenantId: string) {
    return this.request(`/admin/tenants/${tenantId}/usage`)
  }

  // User Management
  async getUsers(options?: FilterOptions): Promise<PaginatedResponse<User>> {
    const params = new URLSearchParams()
    if (options?.search) params.append('search', options.search)
    if (options?.sort) {
      params.append('sort', options.sort.field)
      params.append('order', options.sort.direction)
    }
    if (options?.pagination) {
      params.append('page', options.pagination.page.toString())
      params.append('limit', options.pagination.limit.toString())
    }
    
    return this.request(`/admin/users?${params.toString()}`)
  }

  async getUser(userId: string) {
    return this.request(`/admin/users/${userId}`)
  }

  async updateUser(userId: string, updates: any) {
    return this.request(`/admin/users/${userId}`, {
      method: 'PUT',
      body: JSON.stringify(updates),
    })
  }

  async suspendUser(userId: string) {
    return this.request(`/admin/users/${userId}/suspend`, {
      method: 'POST',
    })
  }

  async reactivateUser(userId: string) {
    return this.request(`/admin/users/${userId}/reactivate`, {
      method: 'POST',
    })
  }

  async getUserActivity(userId: string) {
    return this.request(`/admin/users/${userId}/activity`)
  }

  async getRoles() {
    return this.request('/admin/roles')
  }

  async getPermissions() {
    return this.request('/admin/permissions')
  }

  // System Configuration
  async getFeatureFlags(): Promise<FeatureFlag[]> {
    return this.request<FeatureFlag[]>('/admin/config/feature-flags')
  }

  async updateFeatureFlag(flagId: string, updates: any) {
    return this.request(`/admin/config/feature-flags/${flagId}`, {
      method: 'PUT',
      body: JSON.stringify(updates),
    })
  }

  async getSystemSettings() {
    return this.request('/admin/config/settings')
  }

  async updateSystemSetting(settingId: string, value: any) {
    return this.request(`/admin/config/settings/${settingId}`, {
      method: 'PUT',
      body: JSON.stringify({ value }),
    })
  }

  async getRateLimits() {
    return this.request('/admin/config/rate-limits')
  }

  async updateRateLimit(limitId: string, updates: any) {
    return this.request(`/admin/config/rate-limits/${limitId}`, {
      method: 'PUT',
      body: JSON.stringify(updates),
    })
  }

  // Analytics & Reporting
  async getAnalytics(metric: string, timeRange: string) {
    return this.request(`/admin/analytics/${metric}?timeRange=${timeRange}`)
  }

  async getUsageReports(startDate: string, endDate: string) {
    return this.request(`/admin/reports/usage?start=${startDate}&end=${endDate}`)
  }

  async getFinancialReport(startDate: string, endDate: string) {
    return this.request(`/admin/reports/financial?start=${startDate}&end=${endDate}`)
  }

  async exportReport(reportType: string, format: string, filters: any) {
    return this.request('/admin/reports/export', {
      method: 'POST',
      body: JSON.stringify({ reportType, format, filters }),
    })
  }

  // Operational Tools
  async searchLogs(query: any) {
    return this.request('/admin/logs/search', {
      method: 'POST',
      body: JSON.stringify(query),
    })
  }

  async executeDatabaseQuery(query: string, database: string) {
    return this.request('/admin/database/query', {
      method: 'POST',
      body: JSON.stringify({ query, database }),
    })
  }

  async getDatabaseConnections() {
    return this.request('/admin/database/connections')
  }

  async getJobQueues() {
    return this.request('/admin/jobs/queues')
  }

  async getJobs(queueName: string, status?: string) {
    const params = new URLSearchParams()
    if (status) params.append('status', status)
    return this.request(`/admin/jobs/queues/${queueName}/jobs?${params.toString()}`)
  }

  async retryJob(jobId: string) {
    return this.request(`/admin/jobs/${jobId}/retry`, {
      method: 'POST',
    })
  }

  async cancelJob(jobId: string) {
    return this.request(`/admin/jobs/${jobId}/cancel`, {
      method: 'POST',
    })
  }

  async getCacheStats() {
    return this.request('/admin/cache/stats')
  }

  async clearCache(pattern?: string) {
    return this.request('/admin/cache/clear', {
      method: 'POST',
      body: JSON.stringify({ pattern }),
    })
  }

  // Authentication
  async login(email: string, password: string) {
    const response = await this.request<{ token: string; user: any }>('/auth/admin/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    })
    
    if (response.token) {
      this.setToken(response.token)
    }
    
    return response
  }

  async logout() {
    try {
      await this.request('/auth/logout', { method: 'POST' })
    } finally {
      this.clearToken()
    }
  }

  async refreshToken() {
    const response = await this.request<{ token: string }>('/auth/refresh', {
      method: 'POST',
    })
    
    if (response.token) {
      this.setToken(response.token)
    }
    
    return response
  }

  async getCurrentUser() {
    return this.request('/users/me')
  }
}

export const apiClient = new ApiClient(API_BASE_URL)
export default apiClient