export const API_ENDPOINTS = {
  AUTH_LOGIN: '/auth/login',
  AUTH_REFRESH: '/auth/refresh',
  AUTH_LOGOUT: '/auth/logout',
  BASES: '/bases',
  TABLES: (baseId: string) => `/bases/${baseId}/tables`,
  RECORDS: (baseId: string, tableId: string) => `/bases/${baseId}/tables/${tableId}/records`,
  RECORD: (baseId: string, tableId: string, recordId: string) => 
    `/bases/${baseId}/tables/${tableId}/records/${recordId}`,
  FORMULA: '/formula/evaluate',
  FILES_UPLOAD: '/files/upload',
  FILES_DOWNLOAD: (fileId: string) => `/files/${fileId}`,
  WEBSOCKET: '/ws',
} as const;

export const STORAGE_KEYS = {
  AUTH_TOKENS: '@pyairtable/auth_tokens',
  USER_DATA: '@pyairtable/user_data',
  OFFLINE_DATA: '@pyairtable/offline_data',
  SYNC_QUEUE: '@pyairtable/sync_queue',
  CONFIG: '@pyairtable/config',
} as const;

export const DEFAULT_CONFIG = {
  timeout: 30000,
  retryAttempts: 3,
  retryDelay: 1000,
  enableOfflineSync: true,
  enableWebSocket: true,
  enablePushNotifications: false,
} as const;

export const SYNC_INTERVALS = {
  FAST: 5000,      // 5 seconds
  NORMAL: 30000,   // 30 seconds  
  SLOW: 300000,    // 5 minutes
} as const;

export const ERROR_CODES = {
  NETWORK_ERROR: 'NETWORK_ERROR',
  AUTH_ERROR: 'AUTH_ERROR',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  NOT_FOUND: 'NOT_FOUND',
  PERMISSION_DENIED: 'PERMISSION_DENIED',
  RATE_LIMITED: 'RATE_LIMITED',
  SERVER_ERROR: 'SERVER_ERROR',
  OFFLINE_ERROR: 'OFFLINE_ERROR',
  SYNC_ERROR: 'SYNC_ERROR',
} as const;

export const HTTP_STATUS = {
  OK: 200,
  CREATED: 201,
  NO_CONTENT: 204,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  UNPROCESSABLE_ENTITY: 422,
  TOO_MANY_REQUESTS: 429,
  INTERNAL_SERVER_ERROR: 500,
  BAD_GATEWAY: 502,
  SERVICE_UNAVAILABLE: 503,
} as const;

export const WEBSOCKET_EVENTS = {
  CONNECT: 'connect',
  DISCONNECT: 'disconnect',
  ERROR: 'error',
  RECORD_CREATED: 'record.created',
  RECORD_UPDATED: 'record.updated',
  RECORD_DELETED: 'record.deleted',
  TABLE_UPDATED: 'table.updated',
  BASE_UPDATED: 'base.updated',
} as const;

export const NOTIFICATION_CHANNELS = {
  DEFAULT: 'pyairtable_default',
  SYNC: 'pyairtable_sync',
  UPDATES: 'pyairtable_updates',
} as const;