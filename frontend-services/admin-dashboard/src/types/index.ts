// System Health Types
export interface SystemHealth {
  status: 'healthy' | 'degraded' | 'critical';
  uptime: number;
  lastChecked: string;
  services: ServiceHealth[];
}

export interface ServiceHealth {
  name: string;
  status: 'online' | 'offline' | 'warning';
  endpoint: string;
  responseTime: number;
  lastChecked: string;
  version?: string;
  dependencies?: string[];
}

// Resource Monitoring Types
export interface ResourceMetrics {
  cpu: {
    usage: number;
    cores: number;
    load: number[];
  };
  memory: {
    used: number;
    total: number;
    percentage: number;
  };
  disk: {
    used: number;
    total: number;
    percentage: number;
  };
  network: {
    inbound: number;
    outbound: number;
  };
}

// Tenant Management Types
export interface Tenant {
  id: string;
  name: string;
  slug: string;
  status: 'active' | 'suspended' | 'pending';
  plan: TenantPlan;
  owner: User;
  members: TenantMember[];
  usage: TenantUsage;
  settings: TenantSettings;
  createdAt: string;
  updatedAt: string;
}

export interface TenantPlan {
  id: string;
  name: string;
  tier: 'free' | 'pro' | 'enterprise';
  limits: {
    users: number;
    workspaces: number;
    storage: number; // in bytes
    apiCalls: number; // per month
    automations: number;
  };
  features: string[];
  price: number; // in cents
}

export interface TenantMember {
  id: string;
  user: User;
  role: 'owner' | 'admin' | 'member';
  permissions: string[];
  joinedAt: string;
}

export interface TenantUsage {
  users: number;
  workspaces: number;
  storage: number;
  apiCalls: number;
  automations: number;
  lastCalculated: string;
}

export interface TenantSettings {
  allowUserRegistration: boolean;
  requireEmailVerification: boolean;
  enableAuditLogs: boolean;
  dataRetentionDays: number;
  customDomain?: string;
  ssoEnabled: boolean;
  ssoProvider?: string;
}

// User Management Types
export interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  avatar?: string;
  status: 'active' | 'inactive' | 'suspended';
  role: UserRole;
  permissions: string[];
  lastLogin?: string;
  loginCount: number;
  emailVerified: boolean;
  twoFactorEnabled: boolean;
  tenants: UserTenant[];
  metadata: Record<string, any>;
  createdAt: string;
  updatedAt: string;
}

export interface UserRole {
  id: string;
  name: string;
  description: string;
  permissions: Permission[];
  isSystemRole: boolean;
}

export interface Permission {
  id: string;
  name: string;
  description: string;
  resource: string;
  action: string;
}

export interface UserTenant {
  tenantId: string;
  tenantName: string;
  role: string;
  joinedAt: string;
}

// System Configuration Types
export interface FeatureFlag {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
  conditions?: FeatureFlagCondition[];
  rolloutPercentage: number;
  environments: string[];
  createdBy: string;
  createdAt: string;
  updatedAt: string;
}

export interface FeatureFlagCondition {
  type: 'user' | 'tenant' | 'plan' | 'custom';
  operator: 'equals' | 'contains' | 'in' | 'matches';
  value: string;
}

export interface SystemSetting {
  id: string;
  key: string;
  value: any;
  description: string;
  category: string;
  type: 'string' | 'number' | 'boolean' | 'json';
  validation?: string;
  isSecret: boolean;
  updatedBy: string;
  updatedAt: string;
}

export interface RateLimit {
  id: string;
  name: string;
  endpoint: string;
  limit: number;
  window: number; // in seconds
  scope: 'global' | 'tenant' | 'user';
  enabled: boolean;
  burst?: number;
  createdAt: string;
  updatedAt: string;
}

// Analytics Types
export interface AnalyticsData {
  timeRange: 'hour' | 'day' | 'week' | 'month' | 'year';
  metrics: AnalyticsMetric[];
  aggregations: Record<string, number>;
}

export interface AnalyticsMetric {
  timestamp: string;
  value: number;
  label?: string;
  metadata?: Record<string, any>;
}

export interface UsageReport {
  tenantId: string;
  tenantName: string;
  period: string;
  usage: {
    apiCalls: number;
    storage: number;
    users: number;
    automations: number;
  };
  costs: {
    compute: number;
    storage: number;
    bandwidth: number;
    total: number;
  };
}

// Log Management Types
export interface LogEntry {
  id: string;
  timestamp: string;
  level: 'debug' | 'info' | 'warn' | 'error' | 'fatal';
  service: string;
  message: string;
  metadata?: Record<string, any>;
  traceId?: string;
  userId?: string;
  tenantId?: string;
}

export interface LogQuery {
  query?: string;
  level?: string[];
  service?: string[];
  timeRange: {
    start: string;
    end: string;
  };
  limit: number;
  offset: number;
}

// Database Operations Types
export interface DatabaseQuery {
  id: string;
  query: string;
  database: string;
  status: 'running' | 'completed' | 'failed';
  results?: any[];
  error?: string;
  executionTime: number;
  rowCount?: number;
  executedBy: string;
  executedAt: string;
}

export interface DatabaseConnection {
  id: string;
  name: string;
  type: 'postgresql' | 'redis' | 'elasticsearch';
  host: string;
  port: number;
  database: string;
  status: 'connected' | 'disconnected' | 'error';
  connectionPool?: {
    active: number;
    idle: number;
    total: number;
  };
}

// Job Queue Types
export interface JobQueue {
  name: string;
  status: 'active' | 'paused' | 'error';
  jobs: {
    waiting: number;
    active: number;
    completed: number;
    failed: number;
    delayed: number;
  };
  throughput: number; // jobs per minute
  lastProcessed?: string;
}

export interface Job {
  id: string;
  queue: string;
  name: string;
  status: 'waiting' | 'active' | 'completed' | 'failed' | 'delayed';
  data: any;
  result?: any;
  error?: string;
  progress: number;
  attempts: number;
  maxAttempts: number;
  createdAt: string;
  processedAt?: string;
  completedAt?: string;
}

// API Types
export interface ApiResponse<T> {
  data: T;
  message?: string;
  success: boolean;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
  };
}

export interface FilterOptions {
  search?: string;
  sort?: {
    field: string;
    direction: 'asc' | 'desc';
  };
  filters?: Record<string, any>;
  pagination?: {
    page: number;
    limit: number;
  };
}

// WebSocket Types
export interface WebSocketMessage {
  type: string;
  payload: any;
  timestamp: string;
}

export interface RealtimeUpdate {
  type: 'system_health' | 'user_activity' | 'tenant_update' | 'log_entry' | 'metric_update';
  data: any;
}

// Dashboard Types
export interface DashboardCard {
  id: string;
  title: string;
  type: 'metric' | 'chart' | 'table' | 'status';
  size: 'small' | 'medium' | 'large';
  position: { x: number; y: number };
  config: Record<string, any>;
  refreshInterval?: number;
}

export interface Alert {
  id: string;
  title: string;
  message: string;
  severity: 'info' | 'warning' | 'error' | 'critical';
  source: string;
  status: 'active' | 'acknowledged' | 'resolved';
  createdAt: string;
  acknowledgedBy?: string;
  acknowledgedAt?: string;
  resolvedAt?: string;
}

// Component Props Types
export interface TableColumn<T = any> {
  key: keyof T;
  title: string;
  sortable?: boolean;
  filterable?: boolean;
  render?: (value: any, record: T) => React.ReactNode;
  width?: number;
}