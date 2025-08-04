class ApiEndpoints {
  static const String authLogin = '/auth/login';
  static const String authRefresh = '/auth/refresh';
  static const String authLogout = '/auth/logout';
  static const String bases = '/bases';
  
  static String tables(String baseId) => '/bases/$baseId/tables';
  static String records(String baseId, String tableId) => '/bases/$baseId/tables/$tableId/records';
  static String record(String baseId, String tableId, String recordId) => 
      '/bases/$baseId/tables/$tableId/records/$recordId';
  
  static const String formula = '/formula/evaluate';
  static const String filesUpload = '/files/upload';
  static String filesDownload(String fileId) => '/files/$fileId';
  static const String websocket = '/ws';
}

class StorageKeys {
  static const String authTokens = 'pyairtable_auth_tokens';
  static const String userData = 'pyairtable_user_data';
  static const String offlineData = 'pyairtable_offline_data';
  static const String syncQueue = 'pyairtable_sync_queue';
  static const String config = 'pyairtable_config';
}

class DefaultConfig {
  static const int timeout = 30000;
  static const int retryAttempts = 3;
  static const int retryDelay = 1000;
  static const bool enableOfflineSync = true;
  static const bool enableWebSocket = true;
  static const bool enablePushNotifications = false;
}

class SyncIntervals {
  static const int fast = 5000;      // 5 seconds
  static const int normal = 30000;   // 30 seconds  
  static const int slow = 300000;    // 5 minutes
}

class ErrorCodes {
  static const String networkError = 'NETWORK_ERROR';
  static const String authError = 'AUTH_ERROR';
  static const String validationError = 'VALIDATION_ERROR';
  static const String notFound = 'NOT_FOUND';
  static const String permissionDenied = 'PERMISSION_DENIED';
  static const String rateLimited = 'RATE_LIMITED';
  static const String serverError = 'SERVER_ERROR';
  static const String offlineError = 'OFFLINE_ERROR';
  static const String syncError = 'SYNC_ERROR';
}

class HttpStatus {
  static const int ok = 200;
  static const int created = 201;
  static const int noContent = 204;
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int forbidden = 403;
  static const int notFound = 404;
  static const int conflict = 409;
  static const int unprocessableEntity = 422;
  static const int tooManyRequests = 429;
  static const int internalServerError = 500;
  static const int badGateway = 502;
  static const int serviceUnavailable = 503;
}

class WebSocketEvents {
  static const String connect = 'connect';
  static const String disconnect = 'disconnect';
  static const String error = 'error';
  static const String recordCreated = 'record.created';
  static const String recordUpdated = 'record.updated';
  static const String recordDeleted = 'record.deleted';
  static const String tableUpdated = 'table.updated';
  static const String baseUpdated = 'base.updated';
}

class NotificationChannels {
  static const String defaultChannel = 'pyairtable_default';
  static const String sync = 'pyairtable_sync';
  static const String updates = 'pyairtable_updates';
}