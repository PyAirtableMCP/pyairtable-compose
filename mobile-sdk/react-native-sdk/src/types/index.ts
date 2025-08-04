// Core Types
export interface PyAirtableConfig {
  apiKey: string;
  baseUrl: string;
  timeout?: number;
  retryAttempts?: number;
  retryDelay?: number;
  enableOfflineSync?: boolean;
  enableWebSocket?: boolean;
  enablePushNotifications?: boolean;
}

export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

// Authentication Types
export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

export interface User {
  id: string;
  email: string;
  name: string;
  avatar?: string;
  permissions: string[];
}

export interface LoginCredentials {
  email: string;
  password: string;
}

// Record Types
export interface Record {
  id: string;
  fields: { [key: string]: any };
  createdTime: string;
  updatedTime?: string;
  version?: number;
}

export interface RecordCreate {
  fields: { [key: string]: any };
}

export interface RecordUpdate extends RecordCreate {
  id: string;
}

export interface RecordQuery {
  filterByFormula?: string;
  sort?: Array<{
    field: string;
    direction: 'asc' | 'desc';
  }>;
  maxRecords?: number;
  pageSize?: number;
  offset?: string;
  view?: string;
  fields?: string[];
}

// Table Types
export interface Table {
  id: string;
  name: string;
  description?: string;
  fields: Field[];
  views: View[];
}

export interface Field {
  id: string;
  name: string;
  type: FieldType;
  options?: FieldOptions;
  description?: string;
}

export type FieldType = 
  | 'singleLineText'
  | 'email'
  | 'url'
  | 'multilineText'
  | 'number'
  | 'percent'
  | 'currency'
  | 'singleSelect'
  | 'multipleSelects'
  | 'singleCollaborator'
  | 'multipleCollaborators'
  | 'multipleRecordLinks'
  | 'date'
  | 'dateTime'
  | 'phoneNumber'
  | 'multipleAttachments'
  | 'checkbox'
  | 'formula'
  | 'createdTime'
  | 'rollup'
  | 'count'
  | 'lookup'
  | 'multipleLookupValues'
  | 'autoNumber'
  | 'barcode'
  | 'rating'
  | 'richText'
  | 'duration'
  | 'lastModifiedTime'
  | 'lastModifiedBy'
  | 'createdBy'
  | 'externalSyncSource'
  | 'button';

export interface FieldOptions {
  precision?: number;
  symbol?: string;
  choices?: Array<{
    id: string;
    name: string;
    color?: string;
  }>;
  dateFormat?: {
    name: string;
    format: string;
  };
  timeFormat?: {
    name: string;
    format: string;
  };
  timeZone?: string;
  linkedTableId?: string;
  isReversed?: boolean;
  prefersSingleRecordLink?: boolean;
  inverseLinkFieldId?: string;
  recordLinkUrlFieldId?: string;
  formula?: string;
  referencedFieldIds?: string[];
  result?: {
    type: string;
    options?: any;
  };
}

export interface View {
  id: string;
  name: string;
  type: 'grid' | 'form' | 'calendar' | 'gallery' | 'kanban' | 'timeline';
}

// Base Types
export interface Base {
  id: string;
  name: string;
  permissionLevel: 'none' | 'read' | 'comment' | 'edit' | 'create';
  tables: Table[];
}

// WebSocket Types
export interface WebSocketMessage {
  type: 'recordCreated' | 'recordUpdated' | 'recordDeleted' | 'tableUpdated';
  data: any;
  timestamp: number;
}

// Offline Sync Types
export interface SyncOperation {
  id: string;
  type: 'create' | 'update' | 'delete';
  tableName: string;
  recordId?: string;
  data: any;
  timestamp: number;
  status: 'pending' | 'syncing' | 'completed' | 'failed';
  retryCount: number;
}

export interface OfflineData {
  tables: { [tableId: string]: Record[] };
  lastSync: number;
  pendingOperations: SyncOperation[];
}

// File Types
export interface Attachment {
  id: string;
  url: string;
  filename: string;
  size: number;
  type: string;
  thumbnails?: {
    small: { url: string; width: number; height: number };
    large: { url: string; width: number; height: number };
    full: { url: string; width: number; height: number };
  };
}

export interface FileUploadProgress {
  loaded: number;
  total: number;
  percentage: number;
}

// Error Types
export interface PyAirtableError extends Error {
  code?: string;
  statusCode?: number;
  details?: any;
}

// Notification Types
export interface PushNotificationConfig {
  title: string;
  body: string;
  data?: { [key: string]: any };
  sound?: string;
  badge?: number;
  icon?: string;
  color?: string;
  channelId?: string;
  priority?: 'high' | 'normal' | 'low';
}

// Hook Types
export interface UseRecordsResult {
  records: Record[];
  loading: boolean;
  error: PyAirtableError | null;
  refresh: () => Promise<void>;
  create: (record: RecordCreate) => Promise<Record>;
  update: (record: RecordUpdate) => Promise<Record>;
  delete: (id: string) => Promise<void>;
}

export interface UseAuthResult {
  user: User | null;
  isAuthenticated: boolean;
  loading: boolean;
  login: (credentials: LoginCredentials) => Promise<void>;
  logout: () => Promise<void>;
  refreshToken: () => Promise<void>;
}

// Formula Types
export interface FormulaResult {
  value: any;
  error?: string;
}

export interface FormulaContext {
  record: Record;
  table: Table;
  linkedRecords?: { [fieldId: string]: Record[] };
}