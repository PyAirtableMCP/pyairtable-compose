import { ApiResponse, PaginatedResponse, ApiError, FilterOptions } from "@/types";

// API Configuration
const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080";
const API_VERSION = "v1";

class ApiClient {
  private baseURL: string;
  private defaultHeaders: Record<string, string>;

  constructor() {
    this.baseURL = `${API_BASE_URL}/api/${API_VERSION}`;
    this.defaultHeaders = {
      "Content-Type": "application/json",
    };
  }

  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const url = `${this.baseURL}${endpoint}`;
    
    // Get auth token from localStorage or auth context
    const token = typeof window !== "undefined" ? localStorage.getItem("auth_token") : null;
    
    const config: RequestInit = {
      ...options,
      headers: {
        ...this.defaultHeaders,
        ...(token && { Authorization: `Bearer ${token}` }),
        ...options.headers,
      },
    };

    try {
      const response = await fetch(url, config);
      
      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new ApiError(
          errorData.code || "API_ERROR",
          errorData.message || `HTTP ${response.status}: ${response.statusText}`,
          errorData.details,
          new Date().toISOString(),
          errorData.requestId || "",
          errorData.field
        );
      }

      const data = await response.json();
      return data;
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      
      throw new ApiError(
        "NETWORK_ERROR",
        "Network error occurred",
        { originalError: error },
        new Date().toISOString(),
        ""
      );
    }
  }

  // Generic CRUD operations
  async get<T>(endpoint: string, params?: Record<string, any>): Promise<ApiResponse<T>> {
    const searchParams = params ? `?${new URLSearchParams(params).toString()}` : "";
    return this.request<ApiResponse<T>>(`${endpoint}${searchParams}`);
  }

  async post<T>(endpoint: string, data?: any): Promise<ApiResponse<T>> {
    return this.request<ApiResponse<T>>(endpoint, {
      method: "POST",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async put<T>(endpoint: string, data?: any): Promise<ApiResponse<T>> {
    return this.request<ApiResponse<T>>(endpoint, {
      method: "PUT",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async patch<T>(endpoint: string, data?: any): Promise<ApiResponse<T>> {
    return this.request<ApiResponse<T>>(endpoint, {
      method: "PATCH",
      body: data ? JSON.stringify(data) : undefined,
    });
  }

  async delete<T>(endpoint: string): Promise<ApiResponse<T>> {
    return this.request<ApiResponse<T>>(endpoint, {
      method: "DELETE",
    });
  }

  // Paginated requests
  async getMany<T>(
    endpoint: string,
    filters?: FilterOptions
  ): Promise<PaginatedResponse<T>> {
    const params: Record<string, string> = {};
    
    if (filters?.search) params.search = filters.search;
    if (filters?.sort) {
      params.sort = filters.sort.field;
      params.order = filters.sort.direction;
    }
    if (filters?.pagination) {
      params.page = filters.pagination.page.toString();
      params.limit = filters.pagination.limit.toString();
    }
    if (filters?.filters) {
      Object.entries(filters.filters).forEach(([key, value]) => {
        params[key] = String(value);
      });
    }
    if (filters?.include) {
      params.include = filters.include.join(",");
    }

    const searchParams = Object.keys(params).length > 0 
      ? `?${new URLSearchParams(params).toString()}` 
      : "";
    
    return this.request<PaginatedResponse<T>>(`${endpoint}${searchParams}`);
  }

  // File upload
  async upload(endpoint: string, file: File, additionalData?: Record<string, any>): Promise<any> {
    const formData = new FormData();
    formData.append("file", file);
    
    if (additionalData) {
      Object.entries(additionalData).forEach(([key, value]) => {
        formData.append(key, String(value));
      });
    }

    const token = typeof window !== "undefined" ? localStorage.getItem("auth_token") : null;
    
    const response = await fetch(`${this.baseURL}${endpoint}`, {
      method: "POST",
      headers: {
        ...(token && { Authorization: `Bearer ${token}` }),
      },
      body: formData,
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new ApiError(
        errorData.code || "UPLOAD_ERROR",
        errorData.message || "File upload failed",
        errorData.details,
        new Date().toISOString(),
        errorData.requestId || ""
      );
    }

    return response.json();
  }
}

// Create a singleton instance
export const apiClient = new ApiClient();

// Tenant-specific API functions
export const tenantApi = {
  // Get current tenant
  getCurrent: () => apiClient.get<any>("/tenant/current"),
  
  // Update tenant
  update: (data: any) => apiClient.put<any>("/tenant", data),
  
  // Get tenant usage
  getUsage: () => apiClient.get<any>("/tenant/usage"),
  
  // Get tenant members
  getMembers: (filters?: FilterOptions) => 
    apiClient.getMany<any>("/tenant/members", filters),
  
  // Invite member
  inviteMember: (data: any) => apiClient.post<any>("/tenant/members/invite", data),
  
  // Update member role
  updateMemberRole: (memberId: string, data: any) => 
    apiClient.put<any>(`/tenant/members/${memberId}/role`, data),
  
  // Remove member
  removeMember: (memberId: string) => 
    apiClient.delete<any>(`/tenant/members/${memberId}`),
  
  // Get workspaces
  getWorkspaces: (filters?: FilterOptions) => 
    apiClient.getMany<any>("/tenant/workspaces", filters),
  
  // Create workspace
  createWorkspace: (data: any) => apiClient.post<any>("/tenant/workspaces", data),
  
  // Get billing info
  getBilling: () => apiClient.get<any>("/tenant/billing"),
  
  // Update billing
  updateBilling: (data: any) => apiClient.put<any>("/tenant/billing", data),
  
  // Get invoices
  getInvoices: (filters?: FilterOptions) => 
    apiClient.getMany<any>("/tenant/billing/invoices", filters),
  
  // Get activity logs
  getActivityLogs: (filters?: FilterOptions) => 
    apiClient.getMany<any>("/tenant/activity", filters),
  
  // Get settings
  getSettings: () => apiClient.get<any>("/tenant/settings"),
  
  // Update settings
  updateSettings: (data: any) => apiClient.put<any>("/tenant/settings", data),
  
  // Get API keys
  getApiKeys: () => apiClient.get<any>("/tenant/api-keys"),
  
  // Create API key
  createApiKey: (data: any) => apiClient.post<any>("/tenant/api-keys", data),
  
  // Revoke API key
  revokeApiKey: (keyId: string) => apiClient.delete<any>(`/tenant/api-keys/${keyId}`),
  
  // Get webhooks
  getWebhooks: () => apiClient.get<any>("/tenant/webhooks"),
  
  // Create webhook
  createWebhook: (data: any) => apiClient.post<any>("/tenant/webhooks", data),
  
  // Update webhook
  updateWebhook: (webhookId: string, data: any) => 
    apiClient.put<any>(`/tenant/webhooks/${webhookId}`, data),
  
  // Delete webhook
  deleteWebhook: (webhookId: string) => 
    apiClient.delete<any>(`/tenant/webhooks/${webhookId}`),
  
  // Get audit logs
  getAuditLogs: (filters?: FilterOptions) => 
    apiClient.getMany<any>("/tenant/audit", filters),
  
  // Export data
  exportData: (type: string, format: string) => 
    apiClient.post<any>("/tenant/export", { type, format }),
  
  // Get sessions
  getSessions: () => apiClient.get<any>("/tenant/sessions"),
  
  // Revoke session
  revokeSession: (sessionId: string) => 
    apiClient.delete<any>(`/tenant/sessions/${sessionId}`),
};

// Error handling utility
export class ApiError extends Error {
  constructor(
    public code: string,
    message: string,
    public details?: Record<string, any>,
    public timestamp: string = new Date().toISOString(),
    public requestId: string = "",
    public field?: string
  ) {
    super(message);
    this.name = "ApiError";
  }
}

// Response interceptor for handling common errors
export const handleApiError = (error: any) => {
  if (error instanceof ApiError) {
    switch (error.code) {
      case "UNAUTHORIZED":
        // Redirect to login
        if (typeof window !== "undefined") {
          localStorage.removeItem("auth_token");
          window.location.href = "/login";
        }
        break;
      case "FORBIDDEN":
        // Show permission denied message
        break;
      case "RATE_LIMITED":
        // Show rate limit message
        break;
      default:
        // Generic error handling
        break;
    }
  }
  
  // Log error for monitoring
  console.error("API Error:", error);
  
  return error;
};