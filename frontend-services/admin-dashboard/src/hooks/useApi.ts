import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'react-hot-toast'
import { apiClient } from '@/lib/api'
import { FilterOptions } from '@/types'

// System Health & Monitoring Hooks
export function useSystemHealth() {
  return useQuery({
    queryKey: ['system', 'health'],
    queryFn: () => apiClient.getSystemHealth(),
    refetchInterval: 30000, // Refetch every 30 seconds
  })
}

export function useResourceMetrics() {
  return useQuery({
    queryKey: ['system', 'metrics'],
    queryFn: () => apiClient.getResourceMetrics(),
    refetchInterval: 15000, // Refetch every 15 seconds
  })
}

export function useServiceStatus() {
  return useQuery({
    queryKey: ['system', 'services'],
    queryFn: () => apiClient.getServiceStatus(),
    refetchInterval: 30000,
  })
}

export function useAlerts() {
  return useQuery({
    queryKey: ['system', 'alerts'],
    queryFn: () => apiClient.getAlerts(),
    refetchInterval: 10000, // Refetch every 10 seconds for alerts
  })
}

export function useAcknowledgeAlert() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (alertId: string) => apiClient.acknowledgeAlert(alertId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system', 'alerts'] })
      toast.success('Alert acknowledged successfully')
    },
    onError: (error) => {
      toast.error(`Failed to acknowledge alert: ${error}`)
    },
  })
}

// Tenant Management Hooks
export function useTenants(options?: FilterOptions) {
  return useQuery({
    queryKey: ['tenants', options],
    queryFn: () => apiClient.getTenants(options),
    keepPreviousData: true,
  })
}

export function useTenant(tenantId: string, enabled: boolean = true) {
  return useQuery({
    queryKey: ['tenants', tenantId],
    queryFn: () => apiClient.getTenant(tenantId),
    enabled: enabled && !!tenantId,
  })
}

export function useCreateTenant() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (tenant: any) => apiClient.createTenant(tenant),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] })
      toast.success('Tenant created successfully')
    },
    onError: (error) => {
      toast.error(`Failed to create tenant: ${error}`)
    },
  })
}

export function useUpdateTenant() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: ({ tenantId, updates }: { tenantId: string; updates: any }) =>
      apiClient.updateTenant(tenantId, updates),
    onSuccess: (_, { tenantId }) => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] })
      queryClient.invalidateQueries({ queryKey: ['tenants', tenantId] })
      toast.success('Tenant updated successfully')
    },
    onError: (error) => {
      toast.error(`Failed to update tenant: ${error}`)
    },
  })
}

export function useSuspendTenant() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (tenantId: string) => apiClient.suspendTenant(tenantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] })
      toast.success('Tenant suspended successfully')
    },
    onError: (error) => {
      toast.error(`Failed to suspend tenant: ${error}`)
    },
  })
}

export function useReactivateTenant() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (tenantId: string) => apiClient.reactivateTenant(tenantId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] })
      toast.success('Tenant reactivated successfully')
    },
    onError: (error) => {
      toast.error(`Failed to reactivate tenant: ${error}`)
    },
  })
}

export function useTenantUsage(tenantId: string, enabled: boolean = true) {
  return useQuery({
    queryKey: ['tenants', tenantId, 'usage'],
    queryFn: () => apiClient.getTenantUsage(tenantId),
    enabled: enabled && !!tenantId,
    refetchInterval: 60000, // Refetch every minute
  })
}

// User Management Hooks
export function useUsers(options?: FilterOptions) {
  return useQuery({
    queryKey: ['users', options],
    queryFn: () => apiClient.getUsers(options),
    keepPreviousData: true,
  })
}

export function useUser(userId: string, enabled: boolean = true) {
  return useQuery({
    queryKey: ['users', userId],
    queryFn: () => apiClient.getUser(userId),
    enabled: enabled && !!userId,
  })
}

export function useUpdateUser() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: ({ userId, updates }: { userId: string; updates: any }) =>
      apiClient.updateUser(userId, updates),
    onSuccess: (_, { userId }) => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
      queryClient.invalidateQueries({ queryKey: ['users', userId] })
      toast.success('User updated successfully')
    },
    onError: (error) => {
      toast.error(`Failed to update user: ${error}`)
    },
  })
}

export function useSuspendUser() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (userId: string) => apiClient.suspendUser(userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
      toast.success('User suspended successfully')
    },
    onError: (error) => {
      toast.error(`Failed to suspend user: ${error}`)
    },
  })
}

export function useReactivateUser() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (userId: string) => apiClient.reactivateUser(userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
      toast.success('User reactivated successfully')
    },
    onError: (error) => {
      toast.error(`Failed to reactivate user: ${error}`)
    },
  })
}

export function useUserActivity(userId: string, enabled: boolean = true) {
  return useQuery({
    queryKey: ['users', userId, 'activity'],
    queryFn: () => apiClient.getUserActivity(userId),
    enabled: enabled && !!userId,
  })
}

export function useRoles() {
  return useQuery({
    queryKey: ['roles'],
    queryFn: () => apiClient.getRoles(),
  })
}

export function usePermissions() {
  return useQuery({
    queryKey: ['permissions'],
    queryFn: () => apiClient.getPermissions(),
  })
}

// System Configuration Hooks
export function useFeatureFlags() {
  return useQuery({
    queryKey: ['config', 'feature-flags'],
    queryFn: () => apiClient.getFeatureFlags(),
  })
}

export function useUpdateFeatureFlag() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: ({ flagId, updates }: { flagId: string; updates: any }) =>
      apiClient.updateFeatureFlag(flagId, updates),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['config', 'feature-flags'] })
      toast.success('Feature flag updated successfully')
    },
    onError: (error) => {
      toast.error(`Failed to update feature flag: ${error}`)
    },
  })
}

export function useSystemSettings() {
  return useQuery({
    queryKey: ['config', 'settings'],
    queryFn: () => apiClient.getSystemSettings(),
  })
}

export function useUpdateSystemSetting() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: ({ settingId, value }: { settingId: string; value: any }) =>
      apiClient.updateSystemSetting(settingId, value),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['config', 'settings'] })
      toast.success('Setting updated successfully')
    },
    onError: (error) => {
      toast.error(`Failed to update setting: ${error}`)
    },
  })
}

export function useRateLimits() {
  return useQuery({
    queryKey: ['config', 'rate-limits'],
    queryFn: () => apiClient.getRateLimits(),
  })
}

export function useUpdateRateLimit() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: ({ limitId, updates }: { limitId: string; updates: any }) =>
      apiClient.updateRateLimit(limitId, updates),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['config', 'rate-limits'] })
      toast.success('Rate limit updated successfully')
    },
    onError: (error) => {
      toast.error(`Failed to update rate limit: ${error}`)
    },
  })
}

// Analytics Hooks
export function useAnalytics(metric: string, timeRange: string) {
  return useQuery({
    queryKey: ['analytics', metric, timeRange],
    queryFn: () => apiClient.getAnalytics(metric, timeRange),
    enabled: !!metric && !!timeRange,
  })
}

export function useUsageReports(startDate: string, endDate: string) {
  return useQuery({
    queryKey: ['reports', 'usage', startDate, endDate],
    queryFn: () => apiClient.getUsageReports(startDate, endDate),
    enabled: !!startDate && !!endDate,
  })
}

export function useFinancialReport(startDate: string, endDate: string) {
  return useQuery({
    queryKey: ['reports', 'financial', startDate, endDate],
    queryFn: () => apiClient.getFinancialReport(startDate, endDate),
    enabled: !!startDate && !!endDate,
  })
}

export function useExportReport() {
  return useMutation({
    mutationFn: ({ reportType, format, filters }: { reportType: string; format: string; filters: any }) =>
      apiClient.exportReport(reportType, format, filters),
    onSuccess: () => {
      toast.success('Report export initiated')
    },
    onError: (error) => {
      toast.error(`Failed to export report: ${error}`)
    },
  })
}

// Operational Tools Hooks
export function useSearchLogs() {
  return useMutation({
    mutationFn: (query: any) => apiClient.searchLogs(query),
  })
}

export function useExecuteDatabaseQuery() {
  return useMutation({
    mutationFn: ({ query, database }: { query: string; database: string }) =>
      apiClient.executeDatabaseQuery(query, database),
    onError: (error) => {
      toast.error(`Query failed: ${error}`)
    },
  })
}

export function useDatabaseConnections() {
  return useQuery({
    queryKey: ['database', 'connections'],
    queryFn: () => apiClient.getDatabaseConnections(),
  })
}

export function useJobQueues() {
  return useQuery({
    queryKey: ['jobs', 'queues'],
    queryFn: () => apiClient.getJobQueues(),
    refetchInterval: 30000,
  })
}

export function useJobs(queueName: string, status?: string) {
  return useQuery({
    queryKey: ['jobs', queueName, status],
    queryFn: () => apiClient.getJobs(queueName, status),
    enabled: !!queueName,
    refetchInterval: 15000,
  })
}

export function useRetryJob() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (jobId: string) => apiClient.retryJob(jobId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['jobs'] })
      toast.success('Job retry initiated')
    },
    onError: (error) => {
      toast.error(`Failed to retry job: ${error}`)
    },
  })
}

export function useCancelJob() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (jobId: string) => apiClient.cancelJob(jobId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['jobs'] })
      toast.success('Job cancelled successfully')
    },
    onError: (error) => {
      toast.error(`Failed to cancel job: ${error}`)
    },
  })
}

export function useCacheStats() {
  return useQuery({
    queryKey: ['cache', 'stats'],
    queryFn: () => apiClient.getCacheStats(),
    refetchInterval: 30000,
  })
}

export function useClearCache() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: (pattern?: string) => apiClient.clearCache(pattern),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cache'] })
      toast.success('Cache cleared successfully')
    },
    onError: (error) => {
      toast.error(`Failed to clear cache: ${error}`)
    },
  })
}

// Authentication Hooks
export function useLogin() {
  return useMutation({
    mutationFn: ({ email, password }: { email: string; password: string }) =>
      apiClient.login(email, password),
    onSuccess: () => {
      toast.success('Login successful')
    },
    onError: (error) => {
      toast.error(`Login failed: ${error}`)
    },
  })
}

export function useLogout() {
  const queryClient = useQueryClient()
  
  return useMutation({
    mutationFn: () => apiClient.logout(),
    onSuccess: () => {
      queryClient.clear() // Clear all cached data
      toast.success('Logged out successfully')
    },
  })
}

export function useCurrentUser() {
  return useQuery({
    queryKey: ['auth', 'user'],
    queryFn: () => apiClient.getCurrentUser(),
    retry: false,
  })
}