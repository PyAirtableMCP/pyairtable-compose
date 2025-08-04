// Core Tenant Management Types
export interface Tenant {
  id: string;
  name: string;
  slug: string;
  description?: string;
  logo?: string;
  website?: string;
  status: 'active' | 'suspended' | 'pending' | 'archived';
  plan: TenantPlan;
  owner: TenantMember;
  members: TenantMember[];
  usage: TenantUsage;
  settings: TenantSettings;
  billing: BillingInfo;
  security: SecuritySettings;
  integrations: Integration[];
  createdAt: string;
  updatedAt: string;
  lastActivityAt: string;
}

export interface TenantPlan {
  id: string;
  name: string;
  displayName: string;
  tier: 'free' | 'starter' | 'pro' | 'enterprise' | 'custom';
  limits: TenantLimits;
  features: PlanFeature[];
  pricing: PlanPricing;
  isActive: boolean;
  trialEndsAt?: string;
}

export interface TenantLimits {
  users: number;
  workspaces: number;
  storage: number; // in bytes
  apiCalls: number; // per month
  automations: number;
  fileUploads: number; // per month
  dataTransfer: number; // in bytes per month
  customFields: number;
  views: number;
  records: number;
  webhooks: number;
}

export interface PlanFeature {
  id: string;
  name: string;
  description: string;
  category: string;
  enabled: boolean;
  metadata?: Record<string, any>;
}

export interface PlanPricing {
  basePrice: number; // in cents
  currency: string;
  billingCycle: 'monthly' | 'yearly';
  usageTiers: UsageTier[];
  discounts: PricingDiscount[];
}

export interface UsageTier {
  resource: string;
  freeQuota: number;
  unitPrice: number; // in cents
  tierRanges: TierRange[];
}

export interface TierRange {
  from: number;
  to: number | null; // null for unlimited
  pricePerUnit: number; // in cents
}

export interface PricingDiscount {
  type: 'percentage' | 'fixed';
  value: number;
  condition: string;
  validUntil?: string;
}

// Team Management Types
export interface TenantMember {
  id: string;
  userId: string;
  user: User;
  role: MemberRole;
  permissions: Permission[];
  status: 'active' | 'pending' | 'suspended' | 'removed';
  invitedBy?: string;
  joinedAt: string;
  lastActiveAt?: string;
  metadata: Record<string, any>;
}

export interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  fullName: string;
  avatar?: string;
  timezone: string;
  locale: string;
  emailVerified: boolean;
  phoneNumber?: string;
  phoneVerified: boolean;
  twoFactorEnabled: boolean;
  lastLogin?: string;
  loginCount: number;
  preferences: UserPreferences;
  createdAt: string;
  updatedAt: string;
}

export interface UserPreferences {
  theme: 'light' | 'dark' | 'system';
  notifications: NotificationPreferences;
  dateFormat: string;
  timeFormat: '12h' | '24h';
  language: string;
}

export interface NotificationPreferences {
  email: boolean;
  push: boolean;
  sms: boolean;
  inApp: boolean;
  digest: 'never' | 'daily' | 'weekly';
  categories: Record<string, boolean>;
}

export interface MemberRole {
  id: string;
  name: string;
  displayName: string;
  description: string;
  permissions: Permission[];
  isSystemRole: boolean;
  isCustom: boolean;
  color?: string;
  level: number; // For hierarchy
}

export interface Permission {
  id: string;
  name: string;
  displayName: string;
  description: string;
  resource: string;
  action: string;
  scope: 'tenant' | 'workspace' | 'record' | 'field';
  conditions?: PermissionCondition[];
}

export interface PermissionCondition {
  field: string;
  operator: 'equals' | 'not_equals' | 'in' | 'not_in' | 'contains';
  value: any;
}

export interface TeamInvitation {
  id: string;
  email: string;
  role: MemberRole;
  message?: string;
  status: 'pending' | 'accepted' | 'declined' | 'expired';
  invitedBy: string;
  expiresAt: string;
  createdAt: string;
  acceptedAt?: string;
  token: string;
}

// Workspace Management Types
export interface Workspace {
  id: string;
  name: string;
  description?: string;
  icon?: string;
  color?: string;
  status: 'active' | 'archived' | 'deleted';
  visibility: 'private' | 'team' | 'tenant';
  owner: TenantMember;
  members: WorkspaceMember[];
  tables: WorkspaceTable[];
  templates: WorkspaceTemplate[];
  settings: WorkspaceSettings;
  usage: WorkspaceUsage;
  permissions: WorkspacePermissions;
  createdAt: string;
  updatedAt: string;
  lastActivityAt: string;
}

export interface WorkspaceMember {
  id: string;
  userId: string;
  user: User;
  role: 'owner' | 'editor' | 'commenter' | 'viewer';
  permissions: Permission[];
  addedBy: string;
  addedAt: string;
}

export interface WorkspaceTable {
  id: string;
  name: string;
  description?: string;
  recordCount: number;
  fieldCount: number;
  viewCount: number;
  lastModified: string;
  permissions: TablePermissions;
}

export interface TablePermissions {
  create: boolean;
  read: boolean;
  update: boolean;
  delete: boolean;
  share: boolean;
}

export interface WorkspaceTemplate {
  id: string;
  name: string;
  description: string;
  category: string;
  tags: string[];
  thumbnail?: string;
  isPublic: boolean;
  createdBy: string;
  usageCount: number;
  rating: number;
  createdAt: string;
}

export interface WorkspaceSettings {
  allowGuestAccess: boolean;
  enableComments: boolean;
  enableVersionHistory: boolean;
  dataRetentionDays: number;
  backupFrequency: 'daily' | 'weekly' | 'monthly';
  allowExport: boolean;
  requireApproval: boolean;
}

export interface WorkspaceUsage {
  records: number;
  storage: number;
  apiCalls: number;
  lastCalculated: string;
}

export interface WorkspacePermissions {
  create: boolean;
  read: boolean;
  update: boolean;
  delete: boolean;
  share: boolean;
  export: boolean;
  manageMembers: boolean;
}

// Usage and Analytics Types
export interface TenantUsage {
  current: UsageMetrics;
  limits: TenantLimits;
  period: {
    start: string;
    end: string;
    type: 'monthly' | 'yearly';
  };
  history: UsageHistory[];
  projections: UsageProjection[];
  lastCalculated: string;
}

export interface UsageMetrics {
  users: number;
  workspaces: number;
  records: number;
  storage: number;
  apiCalls: number;
  automations: number;
  fileUploads: number;
  dataTransfer: number;
  webhooks: number;
  computeHours: number;
}

export interface UsageHistory {
  date: string;
  metrics: UsageMetrics;
}

export interface UsageProjection {
  date: string;
  projectedUsage: Partial<UsageMetrics>;
  confidence: number; // 0-1
}

export interface ActivityLog {
  id: string;
  tenantId: string;
  userId: string;
  user: User;
  action: ActivityAction;
  resource: ActivityResource;
  resourceId: string;
  details: Record<string, any>;
  ipAddress: string;
  userAgent: string;
  timestamp: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
}

export interface ActivityAction {
  type: string;
  category: 'auth' | 'data' | 'admin' | 'billing' | 'security';
  displayName: string;
  description: string;
}

export interface ActivityResource {
  type: string;
  displayName: string;
  category: string;
}

// Billing and Subscription Types
export interface BillingInfo {
  customerId: string;
  subscriptionId?: string;
  status: 'active' | 'trialing' | 'past_due' | 'canceled' | 'unpaid';
  currentPeriod: BillingPeriod;
  nextBilling: BillingPeriod;
  paymentMethod: PaymentMethod;
  invoices: Invoice[];
  credits: BillingCredit[];
  tax: TaxInfo;
}

export interface BillingPeriod {
  start: string;
  end: string;
  amount: number;
  currency: string;
  status: 'upcoming' | 'current' | 'past';
}

export interface PaymentMethod {
  id: string;
  type: 'card' | 'bank_account' | 'paypal';
  last4?: string;
  brand?: string;
  expiryMonth?: number;
  expiryYear?: number;
  isDefault: boolean;
  billingAddress: Address;
}

export interface Address {
  line1: string;
  line2?: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
}

export interface Invoice {
  id: string;
  number: string;
  status: 'draft' | 'open' | 'paid' | 'void' | 'uncollectible';
  amount: number;
  currency: string;
  dueDate: string;
  paidAt?: string;
  downloadUrl: string;
  items: InvoiceItem[];
  createdAt: string;
}

export interface InvoiceItem {
  id: string;
  description: string;
  quantity: number;
  unitPrice: number;
  amount: number;
  period: {
    start: string;
    end: string;
  };
}

export interface BillingCredit {
  id: string;
  amount: number;
  currency: string;
  reason: string;
  appliedAt?: string;
  expiresAt?: string;
  status: 'pending' | 'applied' | 'expired';
}

export interface TaxInfo {
  taxId?: string;
  vatNumber?: string;
  exemptStatus: boolean;
  rate: number;
  region: string;
}

// Settings and Configuration Types
export interface TenantSettings {
  general: GeneralSettings;
  security: SecuritySettings;
  notifications: NotificationSettings;
  integrations: IntegrationSettings;
  data: DataSettings;
  appearance: AppearanceSettings;
}

export interface GeneralSettings {
  timezone: string;
  dateFormat: string;
  timeFormat: '12h' | '24h';
  language: string;
  currency: string;
  weekStart: 'sunday' | 'monday';
  allowUserRegistration: boolean;
  requireEmailVerification: boolean;
  customDomain?: string;
  domainVerified: boolean;
}

export interface SecuritySettings {
  passwordPolicy: PasswordPolicy;
  sessionTimeout: number; // in minutes
  twoFactorRequired: boolean;
  ipWhitelist: string[];
  ssoEnabled: boolean;
  ssoProvider?: SSOProvider;
  auditLogRetention: number; // in days
  encryptionAtRest: boolean;
  dataResidency: string;
}

export interface PasswordPolicy {
  minLength: number;
  requireUppercase: boolean;
  requireLowercase: boolean;
  requireNumbers: boolean;
  requireSymbols: boolean;
  preventReuse: number;
  maxAge: number; // in days
}

export interface SSOProvider {
  type: 'saml' | 'oauth' | 'oidc';
  name: string;
  entityId?: string;
  loginUrl: string;
  logoutUrl?: string;
  certificate?: string;
  attributeMapping: Record<string, string>;
  isActive: boolean;
}

export interface NotificationSettings {
  channels: NotificationChannel[];
  templates: NotificationTemplate[];
  preferences: TenantNotificationPreferences;
}

export interface NotificationChannel {
  type: 'email' | 'sms' | 'push' | 'webhook' | 'slack';
  enabled: boolean;
  config: Record<string, any>;
  testEndpoint?: string;
}

export interface NotificationTemplate {
  id: string;
  name: string;
  type: string;
  subject: string;
  body: string;
  variables: string[];
  isActive: boolean;
}

export interface TenantNotificationPreferences {
  systemAlerts: boolean;
  billingNotifications: boolean;
  securityAlerts: boolean;
  usageWarnings: boolean;
  maintenanceUpdates: boolean;
  featureUpdates: boolean;
}

export interface IntegrationSettings {
  apiKeys: ApiKey[];
  webhooks: Webhook[];
  connectedApps: ConnectedApp[];
  rateLimits: RateLimit[];
}

export interface ApiKey {
  id: string;
  name: string;
  keyPreview: string; // First 8 characters
  permissions: string[];
  lastUsed?: string;
  usageCount: number;
  rateLimit?: number;
  isActive: boolean;
  expiresAt?: string;
  createdBy: string;
  createdAt: string;
}

export interface Webhook {
  id: string;
  name: string;
  url: string;
  events: string[];
  secret?: string;
  status: 'active' | 'inactive' | 'failed';
  lastTriggered?: string;
  successCount: number;
  failureCount: number;
  retryCount: number;
  headers: Record<string, string>;
  createdAt: string;
}

export interface ConnectedApp {
  id: string;
  name: string;
  description: string;
  icon?: string;
  category: string;
  permissions: string[];
  isActive: boolean;
  connectedAt: string;
  lastSync?: string;
  config: Record<string, any>;
}

export interface RateLimit {
  id: string;
  name: string;
  endpoint: string;
  method: string;
  limit: number;
  window: number; // in seconds
  scope: 'global' | 'tenant' | 'user' | 'api_key';
  enabled: boolean;
  burst?: number;
}

export interface DataSettings {
  backupEnabled: boolean;
  backupFrequency: 'daily' | 'weekly' | 'monthly';
  backupRetention: number; // in days
  exportFormats: string[];
  dataResidency: string;
  encryptionEnabled: boolean;
  complianceMode: 'gdpr' | 'ccpa' | 'hipaa' | 'sox' | 'none';
  retentionPolicies: RetentionPolicy[];
}

export interface RetentionPolicy {
  id: string;
  name: string;
  resource: string;
  retentionDays: number;
  isActive: boolean;
  conditions: Record<string, any>;
}

export interface AppearanceSettings {
  theme: 'light' | 'dark' | 'auto';
  primaryColor: string;
  logo?: string;
  favicon?: string;
  customCss?: string;
  branding: BrandingSettings;
}

export interface BrandingSettings {
  companyName: string;
  logoUrl?: string;
  primaryColor: string;
  secondaryColor: string;
  fontFamily: string;
  hideFooter: boolean;
  customDomain?: string;
}

// Integration Types
export interface Integration {
  id: string;
  name: string;
  type: string;
  category: string;
  status: 'active' | 'inactive' | 'error' | 'pending';
  config: Record<string, any>;
  lastSync?: string;
  syncStatus: 'success' | 'failed' | 'partial';
  errorMessage?: string;
  usage: IntegrationUsage;
  createdAt: string;
  updatedAt: string;
}

export interface IntegrationUsage {
  requests: number;
  successRate: number;
  avgResponseTime: number;
  lastRequest?: string;
  dataTransferred: number;
}

// Security and Compliance Types
export interface AuditLog {
  id: string;
  tenantId: string;
  userId: string;
  user: User;
  action: string;
  resource: string;
  resourceId: string;
  changes: AuditChange[];
  ipAddress: string;
  userAgent: string;
  location?: GeoLocation;
  riskScore: number;
  timestamp: string;
  sessionId: string;
}

export interface AuditChange {
  field: string;
  oldValue: any;
  newValue: any;
  action: 'created' | 'updated' | 'deleted';
}

export interface GeoLocation {
  country: string;
  region: string;
  city: string;
  latitude: number;
  longitude: number;
}

export interface Session {
  id: string;
  userId: string;
  deviceInfo: DeviceInfo;
  ipAddress: string;
  location?: GeoLocation;
  isActive: boolean;
  isCurrent: boolean;
  startedAt: string;
  lastActiveAt: string;
  expiresAt: string;
  revokedAt?: string;
}

export interface DeviceInfo {
  browser: string;
  os: string;
  device: string;
  isMobile: boolean;
  fingerprint: string;
}

export interface TwoFactorAuth {
  isEnabled: boolean;
  method: 'totp' | 'sms' | 'backup_codes';
  backupCodes: string[];
  qrCodeUrl?: string;
  secretKey?: string;
  verifiedAt?: string;
}

export interface DataExport {
  id: string;
  type: 'full' | 'partial';
  format: 'json' | 'csv' | 'excel';
  status: 'pending' | 'processing' | 'completed' | 'failed';
  downloadUrl?: string;
  expiresAt?: string;
  requestedBy: string;
  requestedAt: string;
  completedAt?: string;
  fileSize?: number;
  recordCount?: number;
}

// API Response Types
export interface ApiResponse<T> {
  data: T;
  message?: string;
  success: boolean;
  meta?: ResponseMeta;
}

export interface ResponseMeta {
  timestamp: string;
  requestId: string;
  version: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: Pagination;
  meta?: ResponseMeta;
}

export interface Pagination {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
  hasNext: boolean;
  hasPrev: boolean;
}

export interface FilterOptions {
  search?: string;
  sort?: SortOption;
  filters?: Record<string, any>;
  pagination?: PaginationOptions;
  include?: string[];
}

export interface SortOption {
  field: string;
  direction: 'asc' | 'desc';
}

export interface PaginationOptions {
  page: number;
  limit: number;
}

// UI Component Types
export interface TableColumn<T = any> {
  key: keyof T;
  title: string;
  sortable?: boolean;
  filterable?: boolean;
  render?: (value: any, record: T, index: number) => React.ReactNode;
  width?: number | string;
  align?: 'left' | 'center' | 'right';
  className?: string;
}

export interface ChartDataPoint {
  x: string | number;
  y: number;
  label?: string;
  color?: string;
  metadata?: Record<string, any>;
}

export interface DashboardMetric {
  id: string;
  title: string;
  value: number | string;
  change?: number;
  changeType?: 'increase' | 'decrease';
  format?: 'number' | 'currency' | 'percentage' | 'bytes';
  description?: string;
  trend?: ChartDataPoint[];
  color?: string;
  icon?: string;
}

export interface NavigationItem {
  id: string;
  label: string;
  href: string;
  icon?: string;
  badge?: string | number;
  children?: NavigationItem[];
  permissions?: string[];
  isActive?: boolean;
  isExternal?: boolean;
}

// Form Types
export interface FormField {
  name: string;
  label: string;
  type: 'text' | 'email' | 'password' | 'number' | 'select' | 'multiselect' | 'checkbox' | 'radio' | 'textarea' | 'date' | 'file';
  placeholder?: string;
  description?: string;
  required?: boolean;
  disabled?: boolean;
  validation?: FormValidation;
  options?: FormOption[];
  dependencies?: FormDependency[];
}

export interface FormOption {
  value: any;
  label: string;
  description?: string;
  disabled?: boolean;
  group?: string;
}

export interface FormValidation {
  min?: number;
  max?: number;
  pattern?: string;
  custom?: (value: any) => string | null;
}

export interface FormDependency {
  field: string;
  condition: 'equals' | 'not_equals' | 'in' | 'not_in';
  value: any;
  action: 'show' | 'hide' | 'enable' | 'disable';
}

// Error Types
export interface ApiError {
  code: string;
  message: string;
  details?: Record<string, any>;
  timestamp: string;
  requestId: string;
  field?: string;
}

export interface ValidationError {
  field: string;
  message: string;
  code: string;
  value: any;
}

// WebSocket Types
export interface WebSocketMessage {
  type: string;
  payload: any;
  timestamp: string;
  id?: string;
}

export interface RealtimeUpdate {
  type: 'tenant_update' | 'usage_update' | 'member_activity' | 'billing_update' | 'security_alert' | 'system_notification';
  data: any;
  tenantId: string;
  timestamp: string;
}

// Theme Types
export interface Theme {
  colors: {
    primary: string;
    secondary: string;
    accent: string;
    background: string;
    surface: string;
    text: string;
    textSecondary: string;
    border: string;
    success: string;
    warning: string;
    error: string;
    info: string;
  };
  fonts: {
    sans: string;
    mono: string;
  };
  spacing: Record<string, string>;
  borderRadius: Record<string, string>;
  shadows: Record<string, string>;
}