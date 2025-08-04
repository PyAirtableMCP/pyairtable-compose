import 'dart:async';
import 'package:rxdart/rxdart.dart';

import 'auth/auth_service.dart';
import 'api/api_client.dart';
import 'websocket/websocket_client.dart';
import 'offline/offline_manager.dart';
import 'notifications/notification_manager.dart';
import 'types/types.dart';
import 'utils/constants.dart';

class PyAirtableClient {
  final PyAirtableConfig config;
  late final AuthService _authService;
  late final ApiClient _apiClient;
  WebSocketClient? _webSocketClient;
  OfflineManager? _offlineManager;
  NotificationManager? _notificationManager;
  
  bool _isInitialized = false;
  
  // Event streams
  final _loginController = StreamController<User>.broadcast();
  final _logoutController = StreamController<void>.broadcast();
  final _onlineController = StreamController<bool>.broadcast();
  final _syncController = StreamController<SyncEvent>.broadcast();
  final _recordController = StreamController<RecordEvent>.broadcast();
  final _webSocketController = StreamController<WebSocketEvent>.broadcast();

  // Public streams
  Stream<User> get onLogin => _loginController.stream;
  Stream<void> get onLogout => _logoutController.stream;
  Stream<bool> get onNetworkChange => _onlineController.stream;
  Stream<SyncEvent> get onSyncEvent => _syncController.stream;
  Stream<RecordEvent> get onRecordEvent => _recordController.stream;
  Stream<WebSocketEvent> get onWebSocketEvent => _webSocketController.stream;

  PyAirtableClient({required this.config}) {
    if (config.apiKey.isEmpty || config.baseUrl.isEmpty) {
      throw const ValidationException('API key and base URL are required');
    }

    _authService = AuthService(
      baseUrl: config.baseUrl,
      apiKey: config.apiKey,
    );
    
    _apiClient = ApiClient(
      authService: _authService,
      config: config,
    );
    
    // Initialize optional services
    if (config.enableWebSocket) {
      _webSocketClient = WebSocketClient(
        authService: _authService,
        baseUrl: config.baseUrl,
      );
      _setupWebSocketListeners();
    }
    
    if (config.enableOfflineSync) {
      _offlineManager = OfflineManager(
        apiClient: _apiClient,
        config: const OfflineManagerConfig(),
      );
      _setupOfflineListeners();
    }
    
    if (config.enablePushNotifications) {
      _notificationManager = NotificationManager();
    }
  }

  /// Initialize the client
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize auth service
      await _authService.initialize();
      
      // Initialize notification manager if enabled
      if (_notificationManager != null) {
        await _notificationManager!.initialize();
      }
      
      // Initialize offline manager if enabled
      if (_offlineManager != null) {
        await _offlineManager!.initialize();
      }

      _isInitialized = true;
    } catch (error) {
      throw PyAirtableException('Failed to initialize PyAirtable client: $error');
    }
  }

  // Authentication Methods

  /// Login with credentials
  Future<User> login(LoginCredentials credentials) async {
    await _authService.login(credentials);
    final user = _authService.user;
    
    if (user == null) {
      throw const PyAirtableException('Login succeeded but no user data received');
    }

    // Connect WebSocket if enabled
    if (_webSocketClient != null) {
      try {
        await _webSocketClient!.connect();
      } catch (error) {
        print('WebSocket connection failed: $error');
      }
    }

    _loginController.add(user);
    return user;
  }

  /// Logout
  Future<void> logout() async {
    // Disconnect WebSocket
    _webSocketClient?.disconnect();

    // Clear offline data
    if (_offlineManager != null) {
      await _offlineManager!.clearCache();
    }

    await _authService.logout();
    _logoutController.add(null);
  }

  /// Get current user
  User? get currentUser => _authService.user;

  /// Check if authenticated
  bool get isAuthenticated => _authService.isAuthenticated;

  // Base Operations

  /// Get all accessible bases
  Future<List<Base>> getBases() async {
    return _apiClient.getBases();
  }

  /// Get a specific base
  Future<Base> getBase(String baseId) async {
    return _apiClient.getBase(baseId);
  }

  // Table Operations

  /// Get all tables in a base
  Future<List<Table>> getTables(String baseId) async {
    return _apiClient.getTables(baseId);
  }

  /// Get a specific table
  Future<Table> getTable(String baseId, String tableId) async {
    return _apiClient.getTable(baseId, tableId);
  }

  // Record Operations

  /// List records with optional caching
  Future<RecordsResult> listRecords(
    String baseId,
    String tableId, {
    RecordQuery? query,
    bool useCache = true,
  }) async {
    // Try to get from cache first if offline manager is enabled
    if (useCache && _offlineManager != null && (!_apiClient.isOnline || config.enableOfflineSync)) {
      final cachedRecords = await _offlineManager!.getCachedRecords(baseId, tableId);
      if (cachedRecords.isNotEmpty || !_apiClient.isOnline) {
        return RecordsResult(records: cachedRecords);
      }
    }

    // Fetch from API
    final result = await _apiClient.listRecords(baseId, tableId, query: query);
    
    // Cache the results
    if (_offlineManager != null) {
      await _offlineManager!.cacheRecords(baseId, tableId, result.records);
    }

    return result;
  }

  /// Get a specific record
  Future<Record> getRecord(String baseId, String tableId, String recordId) async {
    return _apiClient.getRecord(baseId, tableId, recordId);
  }

  /// Create a new record (with offline support)
  Future<Record> createRecord(
    String baseId,
    String tableId,
    RecordCreate record,
  ) async {
    if (_offlineManager != null) {
      return _offlineManager!.createRecord(baseId, tableId, record);
    }
    
    return _apiClient.createRecord(baseId, tableId, record);
  }

  /// Create multiple records
  Future<List<Record>> createRecords(
    String baseId,
    String tableId,
    List<RecordCreate> records,
  ) async {
    return _apiClient.createRecords(baseId, tableId, records);
  }

  /// Update a record (with offline support)
  Future<Record> updateRecord(
    String baseId,
    String tableId,
    RecordUpdate record,
  ) async {
    if (_offlineManager != null) {
      return _offlineManager!.updateRecord(baseId, tableId, record);
    }
    
    return _apiClient.updateRecord(baseId, tableId, record);
  }

  /// Update multiple records
  Future<List<Record>> updateRecords(
    String baseId,
    String tableId,
    List<RecordUpdate> records,
  ) async {
    return _apiClient.updateRecords(baseId, tableId, records);
  }

  /// Delete a record (with offline support)
  Future<void> deleteRecord(String baseId, String tableId, String recordId) async {
    if (_offlineManager != null) {
      return _offlineManager!.deleteRecord(baseId, tableId, recordId);
    }
    
    return _apiClient.deleteRecord(baseId, tableId, recordId);
  }

  /// Delete multiple records
  Future<void> deleteRecords(String baseId, String tableId, List<String> recordIds) async {
    return _apiClient.deleteRecords(baseId, tableId, recordIds);
  }

  // Formula Operations

  /// Evaluate a formula
  Future<FormulaResult> evaluateFormula(
    String baseId,
    String tableId,
    String recordId,
    String formula,
  ) async {
    try {
      final result = await _apiClient.evaluateFormula(baseId, tableId, recordId, formula);
      return FormulaResult(value: result);
    } catch (error) {
      return FormulaResult(
        value: null,
        error: error is Exception ? error.toString() : 'Formula evaluation failed',
      );
    }
  }

  // File Operations

  /// Upload a file with progress tracking
  Future<FileUploadResult> uploadFile(
    String filePath,
    String filename, {
    void Function(FileUploadProgress)? onProgress,
  }) async {
    return _apiClient.uploadFile(filePath, filename, onProgress: onProgress);
  }

  /// Download a file
  Future<List<int>> downloadFile(String fileId) async {
    return _apiClient.downloadFile(fileId);
  }

  // WebSocket Operations

  /// Subscribe to real-time updates for a table
  void subscribeToTable(String baseId, String tableId) {
    if (_webSocketClient == null) {
      throw const PyAirtableException('WebSocket not enabled');
    }
    
    _webSocketClient!.subscribeToTable(baseId, tableId);
  }

  /// Unsubscribe from real-time updates for a table
  void unsubscribeFromTable(String baseId, String tableId) {
    if (_webSocketClient == null) {
      throw const PyAirtableException('WebSocket not enabled');
    }
    
    _webSocketClient!.unsubscribeFromTable(baseId, tableId);
  }

  /// Check if WebSocket is connected
  bool get isWebSocketConnected => _webSocketClient?.isConnected ?? false;

  // Offline Operations

  /// Force sync with server
  Future<void> sync() async {
    if (_offlineManager == null) {
      throw const PyAirtableException('Offline sync not enabled');
    }
    
    return _offlineManager!.sync();
  }

  /// Get pending operations count
  int get pendingOperationsCount => _offlineManager?.pendingOperationsCount ?? 0;

  /// Check if device is online
  bool get isOnline => _apiClient.isOnline;

  // Notification Operations

  /// Show a notification
  Future<void> showNotification(String title, String body, {Map<String, dynamic>? data}) async {
    if (_notificationManager == null) {
      throw const PyAirtableException('Push notifications not enabled');
    }
    
    return _notificationManager!.showNotification(title, body, data: data);
  }

  // Event Setup

  void _setupWebSocketListeners() {
    if (_webSocketClient == null) return;

    _webSocketClient!.onConnect.listen((_) {
      _webSocketController.add(const WebSocketEvent('connect', {}));
    });

    _webSocketClient!.onDisconnect.listen((_) {
      _webSocketController.add(const WebSocketEvent('disconnect', {}));
    });

    _webSocketClient!.onError.listen((error) {
      _webSocketController.add(WebSocketEvent('error', {'error': error.toString()}));
    });

    _webSocketClient!.onMessage.listen((message) {
      switch (message.type) {
        case WebSocketEvents.recordCreated:
          _recordController.add(RecordEvent('created', message.data));
          if (_notificationManager != null) {
            _showRecordNotification('created', message.data['tableName'] ?? 'table');
          }
          break;
        case WebSocketEvents.recordUpdated:
          _recordController.add(RecordEvent('updated', message.data));
          if (_notificationManager != null) {
            _showRecordNotification('updated', message.data['tableName'] ?? 'table');
          }
          break;
        case WebSocketEvents.recordDeleted:
          _recordController.add(RecordEvent('deleted', message.data));
          if (_notificationManager != null) {
            _showRecordNotification('deleted', message.data['tableName'] ?? 'table');
          }
          break;
      }
    });
  }

  void _setupOfflineListeners() {
    if (_offlineManager == null) return;

    _offlineManager!.onNetworkChange.listen((isOnline) {
      _onlineController.add(isOnline);
    });

    _offlineManager!.onSyncStart.listen((_) {
      _syncController.add(const SyncEvent('start', {}));
      if (_notificationManager != null) {
        _showSyncNotification('syncing');
      }
    });

    _offlineManager!.onSyncComplete.listen((_) {
      _syncController.add(const SyncEvent('complete', {}));
      if (_notificationManager != null) {
        _showSyncNotification('completed');
      }
    });

    _offlineManager!.onSyncError.listen((error) {
      _syncController.add(SyncEvent('error', {'error': error.toString()}));
      if (_notificationManager != null) {
        _showSyncNotification('failed', error.toString());
      }
    });
  }

  void _showRecordNotification(String action, String tableName) {
    _notificationManager?.showNotification(
      'Record ${action.toUpperCase()}',
      'A record was $action in $tableName',
      data: {'type': 'record_update', 'action': action, 'tableName': tableName},
    );
  }

  void _showSyncNotification(String status, [String? details]) {
    final messages = {
      'syncing': 'Syncing data with server...',
      'completed': details ?? 'Data synchronized successfully',
      'failed': details ?? 'Sync failed. Will retry automatically.',
    };

    _notificationManager?.showNotification(
      'PyAirtable Sync',
      messages[status] ?? 'Sync status update',
      data: {'type': 'sync', 'status': status},
    );
  }

  /// Cleanup and destroy all resources
  Future<void> dispose() async {
    _webSocketClient?.disconnect();
    await _offlineManager?.dispose();
    await _notificationManager?.dispose();
    
    await _loginController.close();
    await _logoutController.close();
    await _onlineController.close();
    await _syncController.close();
    await _recordController.close();
    await _webSocketController.close();
    
    _isInitialized = false;
  }
}

// Helper classes for events
class SyncEvent {
  final String type;
  final Map<String, dynamic> data;

  const SyncEvent(this.type, this.data);
}

class RecordEvent {
  final String type;
  final Map<String, dynamic> data;

  const RecordEvent(this.type, this.data);
}

class WebSocketEvent {
  final String type;
  final Map<String, dynamic> data;

  const WebSocketEvent(this.type, this.data);
}

class RecordsResult {
  final List<Record> records;
  final String? offset;

  const RecordsResult({required this.records, this.offset});
}

class FormulaResult {
  final dynamic value;
  final String? error;

  const FormulaResult({this.value, this.error});
}

class FileUploadResult {
  final String id;
  final String url;

  const FileUploadResult({required this.id, required this.url});
}