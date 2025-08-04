import AsyncStorage from '@react-native-async-storage/async-storage';
import NetInfo from '@react-native-community/netinfo';
import { EventEmitter } from 'events';
import { 
  Record, 
  RecordCreate, 
  RecordUpdate, 
  SyncOperation, 
  OfflineData,
  ApiResponse 
} from '../types';
import { ApiClient } from '../api/ApiClient';
import { STORAGE_KEYS, SYNC_INTERVALS } from '../utils/constants';
import { SyncError, PyAirtableSDKError } from '../utils/errors';
import { debounce } from '../utils/retry';
import uuid from 'react-native-uuid';

export interface OfflineManagerOptions {
  syncInterval?: number;
  maxRetryAttempts?: number;
  enableOptimisticUpdates?: boolean;
  enableBackgroundSync?: boolean;
}

export class OfflineManager extends EventEmitter {
  private apiClient: ApiClient;
  private options: Required<OfflineManagerOptions>;
  private syncTimer: NodeJS.Timeout | null = null;
  private isOnline = true;
  private isSyncing = false;
  private offlineData: OfflineData = {
    tables: {},
    lastSync: 0,
    pendingOperations: [],
  };

  constructor(apiClient: ApiClient, options: OfflineManagerOptions = {}) {
    super();
    this.apiClient = apiClient;
    this.options = {
      syncInterval: SYNC_INTERVALS.NORMAL,
      maxRetryAttempts: 3,
      enableOptimisticUpdates: true,
      enableBackgroundSync: true,
      ...options,
    };

    this.initialize();
  }

  /**
   * Initialize offline manager
   */
  private async initialize(): Promise<void> {
    await this.loadOfflineData();
    this.setupNetworkListener();
    
    if (this.options.enableBackgroundSync) {
      this.startSyncTimer();
    }
  }

  /**
   * Setup network connectivity listener
   */
  private setupNetworkListener(): void {
    NetInfo.addEventListener(state => {
      const wasOnline = this.isOnline;
      this.isOnline = state.isConnected ?? false;
      
      // When coming back online, trigger sync
      if (!wasOnline && this.isOnline) {
        this.emit('online');
        this.debouncedSync();
      } else if (wasOnline && !this.isOnline) {
        this.emit('offline');
      }
    });
  }

  /**
   * Get cached records for a table
   */
  async getCachedRecords(baseId: string, tableId: string): Promise<Record[]> {
    const tableKey = `${baseId}:${tableId}`;
    return this.offlineData.tables[tableKey] || [];
  }

  /**
   * Cache records for a table
   */
  async cacheRecords(baseId: string, tableId: string, records: Record[]): Promise<void> {
    const tableKey = `${baseId}:${tableId}`;
    this.offlineData.tables[tableKey] = records;
    await this.saveOfflineData();
    this.emit('cacheUpdated', { baseId, tableId, records });
  }

  /**
   * Create record (with offline support)
   */
  async createRecord(
    baseId: string, 
    tableId: string, 
    record: RecordCreate
  ): Promise<Record> {
    const operation: SyncOperation = {
      id: uuid.v4() as string,
      type: 'create',
      tableName: `${baseId}:${tableId}`,
      data: record,
      timestamp: Date.now(),
      status: 'pending',
      retryCount: 0,
    };

    // If online, try immediate sync
    if (this.isOnline) {
      try {
        const result = await this.apiClient.createRecord(baseId, tableId, record);
        
        // Update cache with created record
        await this.updateRecordInCache(baseId, tableId, result);
        
        return result;
      } catch (error) {
        // If failed and optimistic updates enabled, queue for later
        if (this.options.enableOptimisticUpdates) {
          return this.createOptimisticRecord(baseId, tableId, record, operation);
        }
        throw error;
      }
    }

    // Offline: create optimistic record and queue operation
    if (this.options.enableOptimisticUpdates) {
      return this.createOptimisticRecord(baseId, tableId, record, operation);
    }

    throw new SyncError('Cannot create record while offline');
  }

  /**
   * Update record (with offline support)
   */
  async updateRecord(
    baseId: string, 
    tableId: string, 
    record: RecordUpdate
  ): Promise<Record> {
    const operation: SyncOperation = {
      id: uuid.v4() as string,
      type: 'update',
      tableName: `${baseId}:${tableId}`,
      recordId: record.id,
      data: record,
      timestamp: Date.now(),
      status: 'pending',
      retryCount: 0,
    };

    // If online, try immediate sync
    if (this.isOnline) {
      try {
        const result = await this.apiClient.updateRecord(baseId, tableId, record);
        
        // Update cache
        await this.updateRecordInCache(baseId, tableId, result);
        
        return result;
      } catch (error) {
        // If failed and optimistic updates enabled, queue for later
        if (this.options.enableOptimisticUpdates) {
          return this.updateOptimisticRecord(baseId, tableId, record, operation);
        }
        throw error;
      }
    }

    // Offline: create optimistic update and queue operation
    if (this.options.enableOptimisticUpdates) {
      return this.updateOptimisticRecord(baseId, tableId, record, operation);
    }

    throw new SyncError('Cannot update record while offline');
  }

  /**
   * Delete record (with offline support)
   */
  async deleteRecord(baseId: string, tableId: string, recordId: string): Promise<void> {
    const operation: SyncOperation = {
      id: uuid.v4() as string,
      type: 'delete',
      tableName: `${baseId}:${tableId}`,
      recordId,
      data: { id: recordId },
      timestamp: Date.now(),
      status: 'pending',
      retryCount: 0,
    };

    // If online, try immediate sync
    if (this.isOnline) {
      try {
        await this.apiClient.deleteRecord(baseId, tableId, recordId);
        
        // Remove from cache
        await this.removeRecordFromCache(baseId, tableId, recordId);
        
        return;
      } catch (error) {
        // If failed and optimistic updates enabled, queue for later
        if (this.options.enableOptimisticUpdates) {
          await this.deleteOptimisticRecord(baseId, tableId, recordId, operation);
          return;
        }
        throw error;
      }
    }

    // Offline: create optimistic delete and queue operation
    if (this.options.enableOptimisticUpdates) {
      await this.deleteOptimisticRecord(baseId, tableId, recordId, operation);
      return;
    }

    throw new SyncError('Cannot delete record while offline');
  }

  /**
   * Force sync with server
   */
  async sync(): Promise<void> {
    if (this.isSyncing || !this.isOnline) {
      return;
    }

    this.isSyncing = true;
    this.emit('syncStart');

    try {
      await this.processPendingOperations();
      this.offlineData.lastSync = Date.now();
      await this.saveOfflineData();
      
      this.emit('syncComplete');
    } catch (error) {
      this.emit('syncError', error);
      throw error;
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * Get pending operations count
   */
  getPendingOperationsCount(): number {
    return this.offlineData.pendingOperations.length;
  }

  /**
   * Get pending operations
   */
  getPendingOperations(): SyncOperation[] {
    return [...this.offlineData.pendingOperations];
  }

  /**
   * Clear all cached data
   */
  async clearCache(): Promise<void> {
    this.offlineData = {
      tables: {},
      lastSync: 0,
      pendingOperations: [],
    };
    await this.saveOfflineData();
    this.emit('cacheCleared');
  }

  /**
   * Create optimistic record
   */
  private async createOptimisticRecord(
    baseId: string,
    tableId: string,
    record: RecordCreate,
    operation: SyncOperation
  ): Promise<Record> {
    const optimisticRecord: Record = {
      id: `temp_${uuid.v4()}`,
      fields: record.fields,
      createdTime: new Date().toISOString(),
      version: 0,
    };

    // Add to cache
    await this.updateRecordInCache(baseId, tableId, optimisticRecord);
    
    // Queue operation
    this.offlineData.pendingOperations.push(operation);
    await this.saveOfflineData();

    return optimisticRecord;
  }

  /**
   * Update optimistic record
   */
  private async updateOptimisticRecord(
    baseId: string,
    tableId: string,
    record: RecordUpdate,
    operation: SyncOperation
  ): Promise<Record> {
    const updatedRecord: Record = {
      id: record.id,
      fields: record.fields,
      createdTime: '', // Will be filled from cache
      updatedTime: new Date().toISOString(),
      version: 0,
    };

    // Get existing record from cache to preserve createdTime
    const existing = await this.getRecordFromCache(baseId, tableId, record.id);
    if (existing) {
      updatedRecord.createdTime = existing.createdTime;
      updatedRecord.version = (existing.version || 0) + 1;
    }

    // Update cache
    await this.updateRecordInCache(baseId, tableId, updatedRecord);
    
    // Queue operation
    this.offlineData.pendingOperations.push(operation);
    await this.saveOfflineData();

    return updatedRecord;
  }

  /**
   * Delete optimistic record
   */
  private async deleteOptimisticRecord(
    baseId: string,
    tableId: string,
    recordId: string,
    operation: SyncOperation
  ): Promise<void> {
    // Remove from cache
    await this.removeRecordFromCache(baseId, tableId, recordId);
    
    // Queue operation
    this.offlineData.pendingOperations.push(operation);
    await this.saveOfflineData();
  }

  /**
   * Process pending sync operations
   */
  private async processPendingOperations(): Promise<void> {
    const operations = [...this.offlineData.pendingOperations];
    
    for (const operation of operations) {
      try {
        operation.status = 'syncing';
        await this.processOperation(operation);
        
        // Remove from pending operations
        this.offlineData.pendingOperations = this.offlineData.pendingOperations
          .filter(op => op.id !== operation.id);
          
      } catch (error) {
        operation.status = 'failed';
        operation.retryCount++;
        
        if (operation.retryCount >= this.options.maxRetryAttempts) {
          // Remove failed operation after max retries
          this.offlineData.pendingOperations = this.offlineData.pendingOperations
            .filter(op => op.id !== operation.id);
          
          this.emit('operationFailed', { operation, error });
        }
      }
    }
  }

  /**
   * Process a single sync operation
   */
  private async processOperation(operation: SyncOperation): Promise<void> {
    const [baseId, tableId] = operation.tableName.split(':');
    
    switch (operation.type) {
      case 'create':
        await this.apiClient.createRecord(baseId, tableId, operation.data);
        break;
        
      case 'update':
        await this.apiClient.updateRecord(baseId, tableId, operation.data);
        break;
        
      case 'delete':
        await this.apiClient.deleteRecord(baseId, tableId, operation.recordId!);
        break;
    }
  }

  /**
   * Update record in cache
   */
  private async updateRecordInCache(
    baseId: string, 
    tableId: string, 
    record: Record
  ): Promise<void> {
    const tableKey = `${baseId}:${tableId}`;
    const records = this.offlineData.tables[tableKey] || [];
    
    const existingIndex = records.findIndex(r => r.id === record.id);
    if (existingIndex >= 0) {
      records[existingIndex] = record;
    } else {
      records.push(record);
    }
    
    this.offlineData.tables[tableKey] = records;
    await this.saveOfflineData();
  }

  /**
   * Get record from cache
   */
  private async getRecordFromCache(
    baseId: string, 
    tableId: string, 
    recordId: string
  ): Promise<Record | null> {
    const tableKey = `${baseId}:${tableId}`;
    const records = this.offlineData.tables[tableKey] || [];
    return records.find(r => r.id === recordId) || null;
  }

  /**
   * Remove record from cache
   */
  private async removeRecordFromCache(
    baseId: string, 
    tableId: string, 
    recordId: string
  ): Promise<void> {
    const tableKey = `${baseId}:${tableId}`;
    const records = this.offlineData.tables[tableKey] || [];
    
    this.offlineData.tables[tableKey] = records.filter(r => r.id !== recordId);
    await this.saveOfflineData();
  }

  /**
   * Load offline data from storage
   */
  private async loadOfflineData(): Promise<void> {
    try {
      const data = await AsyncStorage.getItem(STORAGE_KEYS.OFFLINE_DATA);
      if (data) {
        this.offlineData = JSON.parse(data);
      }
    } catch (error) {
      console.warn('Failed to load offline data:', error);
    }
  }

  /**
   * Save offline data to storage
   */
  private async saveOfflineData(): Promise<void> {
    try {
      await AsyncStorage.setItem(
        STORAGE_KEYS.OFFLINE_DATA, 
        JSON.stringify(this.offlineData)
      );
    } catch (error) {
      console.warn('Failed to save offline data:', error);
    }
  }

  /**
   * Start sync timer
   */
  private startSyncTimer(): void {
    this.syncTimer = setInterval(() => {
      if (this.isOnline && !this.isSyncing && this.offlineData.pendingOperations.length > 0) {
        this.debouncedSync();
      }
    }, this.options.syncInterval);
  }

  /**
   * Debounced sync to prevent too frequent syncs
   */
  private debouncedSync = debounce(() => {
    this.sync().catch(error => {
      console.warn('Background sync failed:', error);
    });
  }, 1000);

  /**
   * Stop sync timer and cleanup
   */
  destroy(): void {
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
    
    this.removeAllListeners();
  }
}