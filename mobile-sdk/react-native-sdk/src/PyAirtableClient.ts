import { EventEmitter } from 'events';
import { AuthService } from './auth/AuthService';
import { ApiClient } from './api/ApiClient';
import { WebSocketClient } from './websocket/WebSocketClient';
import { OfflineManager } from './offline/OfflineManager';
import { NotificationManager } from './notifications/NotificationManager';
import { 
  PyAirtableConfig,
  LoginCredentials,
  User,
  Base,
  Record,
  RecordCreate,
  RecordUpdate,
  RecordQuery,
  Table,
  FormulaResult,
  FileUploadProgress
} from './types';
import { DEFAULT_CONFIG, WEBSOCKET_EVENTS } from './utils/constants';
import { PyAirtableSDKError, ValidationError } from './utils/errors';

export class PyAirtableClient extends EventEmitter {
  private config: Required<PyAirtableConfig>;
  private authService: AuthService;
  private apiClient: ApiClient;
  private webSocketClient?: WebSocketClient;
  private offlineManager?: OfflineManager;
  private notificationManager?: NotificationManager;
  private isInitialized = false;

  constructor(config: PyAirtableConfig) {
    super();
    
    if (!config.apiKey || !config.baseUrl) {
      throw new ValidationError('API key and base URL are required');
    }

    this.config = { ...DEFAULT_CONFIG, ...config };
    
    // Initialize core services
    this.authService = new AuthService(this.config.baseUrl, this.config.apiKey);
    this.apiClient = new ApiClient(this.authService, this.config);
    
    // Initialize optional services
    if (this.config.enableWebSocket) {
      this.webSocketClient = new WebSocketClient(this.authService, {
        baseUrl: this.config.baseUrl,
      });
      this.setupWebSocketListeners();
    }
    
    if (this.config.enableOfflineSync) {
      this.offlineManager = new OfflineManager(this.apiClient);
      this.setupOfflineListeners();
    }
    
    if (this.config.enablePushNotifications) {
      this.notificationManager = new NotificationManager();
    }
  }

  /**
   * Initialize the client
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;

    try {
      // Initialize notification manager if enabled
      if (this.notificationManager) {
        await this.notificationManager.initialize();
      }

      this.isInitialized = true;
      this.emit('initialized');
    } catch (error) {
      throw new PyAirtableSDKError('Failed to initialize PyAirtable client: ' + error.message);
    }
  }

  // Authentication Methods

  /**
   * Login with credentials
   */
  async login(credentials: LoginCredentials): Promise<User> {
    await this.authService.login(credentials);
    const user = this.authService.getUser();
    
    if (!user) {
      throw new PyAirtableSDKError('Login succeeded but no user data received');
    }

    // Connect WebSocket if enabled
    if (this.webSocketClient) {
      try {
        await this.webSocketClient.connect();
      } catch (error) {
        console.warn('WebSocket connection failed:', error);
      }
    }

    this.emit('login', user);
    return user;
  }

  /**
   * Logout
   */
  async logout(): Promise<void> {
    // Disconnect WebSocket
    if (this.webSocketClient) {
      this.webSocketClient.disconnect();
    }

    // Clear offline data
    if (this.offlineManager) {
      await this.offlineManager.clearCache();
    }

    await this.authService.logout();
    this.emit('logout');
  }

  /**
   * Get current user
   */
  getCurrentUser(): User | null {
    return this.authService.getUser();
  }

  /**
   * Check if authenticated
   */
  isAuthenticated(): boolean {
    return this.authService.isAuthenticated();
  }

  // Base Operations

  /**
   * Get all accessible bases
   */
  async getBases(): Promise<Base[]> {
    return this.apiClient.getBases();
  }

  /**
   * Get a specific base
   */
  async getBase(baseId: string): Promise<Base> {
    return this.apiClient.getBase(baseId);
  }

  // Table Operations

  /**
   * Get all tables in a base
   */
  async getTables(baseId: string): Promise<Table[]> {
    return this.apiClient.getTables(baseId);
  }

  /**
   * Get a specific table
   */
  async getTable(baseId: string, tableId: string): Promise<Table> {
    return this.apiClient.getTable(baseId, tableId);
  }

  // Record Operations

  /**
   * List records with optional caching
   */
  async listRecords(
    baseId: string,
    tableId: string,
    query?: RecordQuery,
    useCache: boolean = true
  ): Promise<{ records: Record[]; offset?: string }> {
    // Try to get from cache first if offline or cache enabled
    if (useCache && this.offlineManager && (!this.apiClient.isDeviceOnline() || this.config.enableOfflineSync)) {
      const cachedRecords = await this.offlineManager.getCachedRecords(baseId, tableId);
      if (cachedRecords.length > 0 || !this.apiClient.isDeviceOnline()) {
        return { records: cachedRecords };
      }
    }

    // Fetch from API
    const result = await this.apiClient.listRecords(baseId, tableId, query);
    
    // Cache the results
    if (this.offlineManager) {
      await this.offlineManager.cacheRecords(baseId, tableId, result.records);
    }

    return result;
  }

  /**
   * Get a specific record
   */
  async getRecord(baseId: string, tableId: string, recordId: string): Promise<Record> {
    return this.apiClient.getRecord(baseId, tableId, recordId);
  }

  /**
   * Create a new record (with offline support)
   */
  async createRecord(
    baseId: string,
    tableId: string,
    record: RecordCreate
  ): Promise<Record> {
    if (this.offlineManager) {
      return this.offlineManager.createRecord(baseId, tableId, record);
    }
    
    return this.apiClient.createRecord(baseId, tableId, record);
  }

  /**
   * Create multiple records
   */
  async createRecords(
    baseId: string,
    tableId: string,
    records: RecordCreate[]
  ): Promise<Record[]> {
    // For bulk operations, use API directly (offline manager handles individual records)
    return this.apiClient.createRecords(baseId, tableId, records);
  }

  /**
   * Update a record (with offline support)
   */
  async updateRecord(
    baseId: string,
    tableId: string,
    record: RecordUpdate
  ): Promise<Record> {
    if (this.offlineManager) {
      return this.offlineManager.updateRecord(baseId, tableId, record);
    }
    
    return this.apiClient.updateRecord(baseId, tableId, record);
  }

  /**
   * Update multiple records
   */
  async updateRecords(
    baseId: string,
    tableId: string,
    records: RecordUpdate[]
  ): Promise<Record[]> {
    return this.apiClient.updateRecords(baseId, tableId, records);
  }

  /**
   * Delete a record (with offline support)
   */
  async deleteRecord(baseId: string, tableId: string, recordId: string): Promise<void> {
    if (this.offlineManager) {
      return this.offlineManager.deleteRecord(baseId, tableId, recordId);
    }
    
    return this.apiClient.deleteRecord(baseId, tableId, recordId);
  }

  /**
   * Delete multiple records
   */
  async deleteRecords(baseId: string, tableId: string, recordIds: string[]): Promise<void> {
    return this.apiClient.deleteRecords(baseId, tableId, recordIds);
  }

  // Formula Operations

  /**
   * Evaluate a formula
   */
  async evaluateFormula(
    baseId: string,
    tableId: string,
    recordId: string,
    formula: string
  ): Promise<FormulaResult> {
    try {
      const result = await this.apiClient.evaluateFormula(baseId, tableId, recordId, formula);
      return { value: result };
    } catch (error) {
      return { 
        value: null, 
        error: error instanceof Error ? error.message : 'Formula evaluation failed' 
      };
    }
  }

  // File Operations

  /**
   * Upload a file with progress tracking
   */
  async uploadFile(
    file: File | Blob,
    filename: string,
    onProgress?: (progress: FileUploadProgress) => void
  ): Promise<{ id: string; url: string }> {
    return this.apiClient.uploadFile(file, filename, (progress) => {
      if (onProgress) {
        onProgress({
          loaded: progress.loaded,
          total: progress.total,
          percentage: Math.round((progress.loaded / progress.total) * 100),
        });
      }
    });
  }

  /**
   * Download a file
   */
  async downloadFile(fileId: string): Promise<Blob> {
    return this.apiClient.downloadFile(fileId);
  }

  // WebSocket Operations

  /**
   * Subscribe to real-time updates for a table
   */
  subscribeToTable(baseId: string, tableId: string): void {
    if (!this.webSocketClient) {
      throw new PyAirtableSDKError('WebSocket not enabled');
    }
    
    this.webSocketClient.subscribeToTable(baseId, tableId);
  }

  /**
   * Unsubscribe from real-time updates for a table
   */
  unsubscribeFromTable(baseId: string, tableId: string): void {
    if (!this.webSocketClient) {
      throw new PyAirtableSDKError('WebSocket not enabled');
    }
    
    this.webSocketClient.unsubscribeFromTable(baseId, tableId);
  }

  /**
   * Check if WebSocket is connected
   */
  isWebSocketConnected(): boolean {
    return this.webSocketClient?.isConnected() ?? false;
  }

  // Offline Operations

  /**
   * Force sync with server
   */
  async sync(): Promise<void> {
    if (!this.offlineManager) {
      throw new PyAirtableSDKError('Offline sync not enabled');
    }
    
    return this.offlineManager.sync();
  }

  /**
   * Get pending operations count
   */
  getPendingOperationsCount(): number {
    return this.offlineManager?.getPendingOperationsCount() ?? 0;
  }

  /**
   * Check if device is online
   */
  isOnline(): boolean {
    return this.apiClient.isDeviceOnline();
  }

  // Notification Operations

  /**
   * Show a notification
   */
  showNotification(title: string, body: string, data?: any): void {
    if (!this.notificationManager) {
      throw new PyAirtableSDKError('Push notifications not enabled');
    }
    
    this.notificationManager.showNotification({
      title,
      body,
      data,
    });
  }

  /**
   * Set badge number (iOS)
   */
  setBadgeNumber(number: number): void {
    if (!this.notificationManager) {
      throw new PyAirtableSDKError('Push notifications not enabled');
    }
    
    this.notificationManager.setBadgeNumber(number);
  }

  // Event Setup

  /**
   * Setup WebSocket event listeners
   */
  private setupWebSocketListeners(): void {
    if (!this.webSocketClient) return;

    this.webSocketClient.on(WEBSOCKET_EVENTS.CONNECT, () => {
      this.emit('websocket:connect');
    });

    this.webSocketClient.on(WEBSOCKET_EVENTS.DISCONNECT, () => {
      this.emit('websocket:disconnect');
    });

    this.webSocketClient.on(WEBSOCKET_EVENTS.ERROR, (error) => {
      this.emit('websocket:error', error);
    });

    this.webSocketClient.on(WEBSOCKET_EVENTS.RECORD_CREATED, (data) => {
      this.emit('record:created', data);
      
      if (this.notificationManager) {
        this.notificationManager.showRecordUpdateNotification('created', data.tableName);
      }
    });

    this.webSocketClient.on(WEBSOCKET_EVENTS.RECORD_UPDATED, (data) => {
      this.emit('record:updated', data);
      
      if (this.notificationManager) {
        this.notificationManager.showRecordUpdateNotification('updated', data.tableName);
      }
    });

    this.webSocketClient.on(WEBSOCKET_EVENTS.RECORD_DELETED, (data) => {
      this.emit('record:deleted', data);
      
      if (this.notificationManager) {
        this.notificationManager.showRecordUpdateNotification('deleted', data.tableName);
      }
    });
  }

  /**
   * Setup offline manager event listeners
   */
  private setupOfflineListeners(): void {
    if (!this.offlineManager) return;

    this.offlineManager.on('online', () => {
      this.emit('online');
    });

    this.offlineManager.on('offline', () => {
      this.emit('offline');
    });

    this.offlineManager.on('syncStart', () => {
      this.emit('sync:start');
      
      if (this.notificationManager) {
        this.notificationManager.showSyncNotification('syncing');
      }
    });

    this.offlineManager.on('syncComplete', () => {
      this.emit('sync:complete');
      
      if (this.notificationManager) {
        this.notificationManager.showSyncNotification('completed');
      }
    });

    this.offlineManager.on('syncError', (error) => {
      this.emit('sync:error', error);
      
      if (this.notificationManager) {
        this.notificationManager.showSyncNotification('failed', error.message);
      }
    });
  }

  /**
   * Cleanup and destroy all resources
   */
  destroy(): void {
    this.webSocketClient?.destroy();
    this.offlineManager?.destroy();
    this.notificationManager?.destroy();
    
    this.removeAllListeners();
    this.isInitialized = false;
  }
}