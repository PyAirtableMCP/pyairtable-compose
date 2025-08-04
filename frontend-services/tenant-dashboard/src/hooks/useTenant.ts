"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { tenantApi, handleApiError } from "@/lib/api";
import type { Tenant, FilterOptions } from "@/types";

// Query keys
export const tenantKeys = {
  all: ["tenant"] as const,
  current: () => [...tenantKeys.all, "current"] as const,
  usage: () => [...tenantKeys.all, "usage"] as const,
  members: (filters?: FilterOptions) => [...tenantKeys.all, "members", filters] as const,
  workspaces: (filters?: FilterOptions) => [...tenantKeys.all, "workspaces", filters] as const,
  billing: () => [...tenantKeys.all, "billing"] as const,
  invoices: (filters?: FilterOptions) => [...tenantKeys.all, "invoices", filters] as const,
  settings: () => [...tenantKeys.all, "settings"] as const,
  apiKeys: () => [...tenantKeys.all, "api-keys"] as const,
  webhooks: () => [...tenantKeys.all, "webhooks"] as const,
  activityLogs: (filters?: FilterOptions) => [...tenantKeys.all, "activity", filters] as const,
  auditLogs: (filters?: FilterOptions) => [...tenantKeys.all, "audit", filters] as const,
  sessions: () => [...tenantKeys.all, "sessions"] as const,
};

// Current tenant hook
export function useTenant() {
  return useQuery({
    queryKey: tenantKeys.current(),
    queryFn: async () => {
      const response = await tenantApi.getCurrent();
      return response.data as Tenant;
    },
    staleTime: 5 * 60 * 1000, // 5 minutes
    retry: (failureCount, error) => {
      // Don't retry on auth errors
      if (error && typeof error === "object" && "code" in error) {
        const apiError = error as any;
        if (apiError.code === "UNAUTHORIZED" || apiError.code === "FORBIDDEN") {
          return false;
        }
      }
      return failureCount < 3;
    },
    meta: {
      errorHandler: handleApiError,
    },
  });
}

// Update tenant hook
export function useUpdateTenant() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (data: Partial<Tenant>) => tenantApi.update(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.current() });
    },
    onError: handleApiError,
  });
}

// Usage hook
export function useTenantUsage() {
  return useQuery({
    queryKey: tenantKeys.usage(),
    queryFn: async () => {
      const response = await tenantApi.getUsage();
      return response.data;
    },
    staleTime: 2 * 60 * 1000, // 2 minutes
    refetchInterval: 5 * 60 * 1000, // Refetch every 5 minutes
  });
}

// Members hook
export function useTenantMembers(filters?: FilterOptions) {
  return useQuery({
    queryKey: tenantKeys.members(filters),
    queryFn: async () => {
      const response = await tenantApi.getMembers(filters);
      return response;
    },
    staleTime: 2 * 60 * 1000,
  });
}

// Invite member hook
export function useInviteMember() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (data: any) => tenantApi.inviteMember(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.members() });
      queryClient.invalidateQueries({ queryKey: tenantKeys.current() });
    },
    onError: handleApiError,
  });
}

// Update member role hook
export function useUpdateMemberRole() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ memberId, data }: { memberId: string; data: any }) =>
      tenantApi.updateMemberRole(memberId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.members() });
    },
    onError: handleApiError,
  });
}

// Remove member hook
export function useRemoveMember() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (memberId: string) => tenantApi.removeMember(memberId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.members() });
      queryClient.invalidateQueries({ queryKey: tenantKeys.current() });
    },
    onError: handleApiError,
  });
}

// Workspaces hook
export function useTenantWorkspaces(filters?: FilterOptions) {
  return useQuery({
    queryKey: tenantKeys.workspaces(filters),
    queryFn: async () => {
      const response = await tenantApi.getWorkspaces(filters);
      return response;
    },
    staleTime: 2 * 60 * 1000,
  });
}

// Create workspace hook
export function useCreateWorkspace() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (data: any) => tenantApi.createWorkspace(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.workspaces() });
      queryClient.invalidateQueries({ queryKey: tenantKeys.usage() });
    },
    onError: handleApiError,
  });
}

// Billing hook
export function useTenantBilling() {
  return useQuery({
    queryKey: tenantKeys.billing(),
    queryFn: async () => {
      const response = await tenantApi.getBilling();
      return response.data;
    },
    staleTime: 5 * 60 * 1000,
  });
}

// Update billing hook
export function useUpdateBilling() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (data: any) => tenantApi.updateBilling(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.billing() });
    },
    onError: handleApiError,
  });
}

// Invoices hook
export function useTenantInvoices(filters?: FilterOptions) {
  return useQuery({
    queryKey: tenantKeys.invoices(filters),
    queryFn: async () => {
      const response = await tenantApi.getInvoices(filters);
      return response;
    },
    staleTime: 5 * 60 * 1000,
  });
}

// Settings hook
export function useTenantSettings() {
  return useQuery({
    queryKey: tenantKeys.settings(),
    queryFn: async () => {
      const response = await tenantApi.getSettings();
      return response.data;
    },
    staleTime: 5 * 60 * 1000,
  });
}

// Update settings hook
export function useUpdateSettings() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (data: any) => tenantApi.updateSettings(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.settings() });
    },
    onError: handleApiError,
  });
}

// API keys hook
export function useTenantApiKeys() {
  return useQuery({
    queryKey: tenantKeys.apiKeys(),
    queryFn: async () => {
      const response = await tenantApi.getApiKeys();
      return response.data;
    },
    staleTime: 2 * 60 * 1000,
  });
}

// Create API key hook
export function useCreateApiKey() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (data: any) => tenantApi.createApiKey(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.apiKeys() });
    },
    onError: handleApiError,
  });
}

// Revoke API key hook
export function useRevokeApiKey() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (keyId: string) => tenantApi.revokeApiKey(keyId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.apiKeys() });
    },
    onError: handleApiError,
  });
}

// Webhooks hook
export function useTenantWebhooks() {
  return useQuery({
    queryKey: tenantKeys.webhooks(),
    queryFn: async () => {
      const response = await tenantApi.getWebhooks();
      return response.data;
    },
    staleTime: 2 * 60 * 1000,
  });
}

// Create webhook hook
export function useCreateWebhook() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (data: any) => tenantApi.createWebhook(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.webhooks() });
    },
    onError: handleApiError,
  });
}

// Update webhook hook
export function useUpdateWebhook() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ webhookId, data }: { webhookId: string; data: any }) =>
      tenantApi.updateWebhook(webhookId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.webhooks() });
    },
    onError: handleApiError,
  });
}

// Delete webhook hook
export function useDeleteWebhook() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (webhookId: string) => tenantApi.deleteWebhook(webhookId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.webhooks() });
    },
    onError: handleApiError,
  });
}

// Activity logs hook
export function useTenantActivityLogs(filters?: FilterOptions) {
  return useQuery({
    queryKey: tenantKeys.activityLogs(filters),
    queryFn: async () => {
      const response = await tenantApi.getActivityLogs(filters);
      return response;
    },
    staleTime: 1 * 60 * 1000, // 1 minute
  });
}

// Audit logs hook
export function useTenantAuditLogs(filters?: FilterOptions) {
  return useQuery({
    queryKey: tenantKeys.auditLogs(filters),
    queryFn: async () => {
      const response = await tenantApi.getAuditLogs(filters);
      return response;
    },
    staleTime: 1 * 60 * 1000,
  });
}

// Export data hook
export function useExportData() {
  return useMutation({
    mutationFn: ({ type, format }: { type: string; format: string }) =>
      tenantApi.exportData(type, format),
    onError: handleApiError,
  });
}

// Sessions hook
export function useTenantSessions() {
  return useQuery({
    queryKey: tenantKeys.sessions(),
    queryFn: async () => {
      const response = await tenantApi.getSessions();
      return response.data;
    },
    staleTime: 2 * 60 * 1000,
  });
}

// Revoke session hook
export function useRevokeSession() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (sessionId: string) => tenantApi.revokeSession(sessionId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: tenantKeys.sessions() });
    },
    onError: handleApiError,
  });
}