import NetInfo from '@react-native-community/netinfo';
import { AuthService } from '../auth/AuthService';
import { 
  Record, 
  RecordCreate, 
  RecordUpdate, 
  RecordQuery, 
  Table, 
  Base, 
  ApiResponse,
  PyAirtableConfig 
} from '../types';
import { API_ENDPOINTS } from '../utils/constants';
import { NetworkError, NotFoundError, PyAirtableSDKError } from '../utils/errors';
import { withRetry } from '../utils/retry';

export class ApiClient {
  private authService: AuthService;
  private config: PyAirtableConfig;
  private isOnline: boolean = true;

  constructor(authService: AuthService, config: PyAirtableConfig) {
    this.authService = authService;
    this.config = config;
    this.setupNetworkListener();
  }

  /**
   * Setup network connectivity listener
   */
  private setupNetworkListener(): void {
    NetInfo.addEventListener(state => {
      this.isOnline = state.isConnected ?? false;
    });
  }

  /**
   * Check if device is online
   */
  isDeviceOnline(): boolean {
    return this.isOnline;
  }

  // Base Operations
  
  /**
   * Get all accessible bases
   */
  async getBases(): Promise<Base[]> {
    const response = await this.makeRequest<{ bases: Base[] }>(API_ENDPOINTS.BASES);
    return response.data?.bases || [];
  }

  /**
   * Get a specific base by ID
   */
  async getBase(baseId: string): Promise<Base> {
    const response = await this.makeRequest<Base>(`${API_ENDPOINTS.BASES}/${baseId}`);
    if (!response.success || !response.data) {
      throw new NotFoundError('Base');
    }
    return response.data;
  }

  // Table Operations

  /**
   * Get all tables in a base
   */
  async getTables(baseId: string): Promise<Table[]> {
    const response = await this.makeRequest<{ tables: Table[] }>(API_ENDPOINTS.TABLES(baseId));
    return response.data?.tables || [];
  }

  /**
   * Get a specific table
   */
  async getTable(baseId: string, tableId: string): Promise<Table> {
    const response = await this.makeRequest<Table>(`${API_ENDPOINTS.TABLES(baseId)}/${tableId}`);
    if (!response.success || !response.data) {
      throw new NotFoundError('Table');
    }
    return response.data;
  }

  // Record Operations

  /**
   * List records with optional query parameters
   */
  async listRecords(
    baseId: string, 
    tableId: string, 
    query?: RecordQuery
  ): Promise<{ records: Record[]; offset?: string }> {
    const url = new URL(`${this.config.baseUrl}${API_ENDPOINTS.RECORDS(baseId, tableId)}`);
    
    if (query) {
      if (query.filterByFormula) url.searchParams.set('filterByFormula', query.filterByFormula);
      if (query.maxRecords) url.searchParams.set('maxRecords', query.maxRecords.toString());
      if (query.pageSize) url.searchParams.set('pageSize', query.pageSize.toString());
      if (query.offset) url.searchParams.set('offset', query.offset);
      if (query.view) url.searchParams.set('view', query.view);
      if (query.fields) url.searchParams.set('fields', query.fields.join(','));
      if (query.sort) {
        query.sort.forEach((sort, index) => {
          url.searchParams.set(`sort[${index}][field]`, sort.field);
          url.searchParams.set(`sort[${index}][direction]`, sort.direction);
        });
      }
    }
    
    const response = await this.makeRequest<{ records: Record[]; offset?: string }>(
      url.pathname + url.search
    );
    
    return {
      records: response.data?.records || [],
      offset: response.data?.offset,
    };
  }

  /**
   * Get a specific record by ID
   */
  async getRecord(baseId: string, tableId: string, recordId: string): Promise<Record> {
    const response = await this.makeRequest<Record>(
      API_ENDPOINTS.RECORD(baseId, tableId, recordId)
    );
    
    if (!response.success || !response.data) {
      throw new NotFoundError('Record');
    }
    
    return response.data;
  }

  /**
   * Create a new record
   */
  async createRecord(
    baseId: string, 
    tableId: string, 
    record: RecordCreate
  ): Promise<Record> {
    const response = await this.makeRequest<Record>(
      API_ENDPOINTS.RECORDS(baseId, tableId),
      {
        method: 'POST',
        body: JSON.stringify({ fields: record.fields }),
      }
    );

    if (!response.success || !response.data) {
      throw new PyAirtableSDKError(response.error || 'Failed to create record');
    }

    return response.data;
  }

  /**
   * Create multiple records
   */
  async createRecords(
    baseId: string, 
    tableId: string, 
    records: RecordCreate[]
  ): Promise<Record[]> {
    const response = await this.makeRequest<{ records: Record[] }>(
      API_ENDPOINTS.RECORDS(baseId, tableId),
      {
        method: 'POST',
        body: JSON.stringify({ records: records.map(r => ({ fields: r.fields })) }),
      }
    );

    if (!response.success || !response.data) {
      throw new PyAirtableSDKError(response.error || 'Failed to create records');
    }

    return response.data.records;
  }

  /**
   * Update a record
   */
  async updateRecord(
    baseId: string, 
    tableId: string, 
    record: RecordUpdate
  ): Promise<Record> {
    const response = await this.makeRequest<Record>(
      API_ENDPOINTS.RECORD(baseId, tableId, record.id),
      {
        method: 'PATCH',
        body: JSON.stringify({ fields: record.fields }),
      }
    );

    if (!response.success || !response.data) {
      throw new PyAirtableSDKError(response.error || 'Failed to update record');
    }

    return response.data;
  }

  /**
   * Update multiple records
   */
  async updateRecords(
    baseId: string, 
    tableId: string, 
    records: RecordUpdate[]
  ): Promise<Record[]> {
    const response = await this.makeRequest<{ records: Record[] }>(
      API_ENDPOINTS.RECORDS(baseId, tableId),
      {
        method: 'PATCH',
        body: JSON.stringify({ 
          records: records.map(r => ({ id: r.id, fields: r.fields })) 
        }),
      }
    );

    if (!response.success || !response.data) {
      throw new PyAirtableSDKError(response.error || 'Failed to update records');
    }

    return response.data.records;
  }

  /**
   * Delete a record
   */
  async deleteRecord(baseId: string, tableId: string, recordId: string): Promise<void> {
    const response = await this.makeRequest(
      API_ENDPOINTS.RECORD(baseId, tableId, recordId),
      { method: 'DELETE' }
    );

    if (!response.success) {
      throw new PyAirtableSDKError(response.error || 'Failed to delete record');
    }
  }

  /**
   * Delete multiple records
   */
  async deleteRecords(baseId: string, tableId: string, recordIds: string[]): Promise<void> {
    const url = new URL(`${this.config.baseUrl}${API_ENDPOINTS.RECORDS(baseId, tableId)}`);
    recordIds.forEach(id => url.searchParams.append('records[]', id));
    
    const response = await this.makeRequest(
      url.pathname + url.search,
      { method: 'DELETE' }
    );

    if (!response.success) {
      throw new PyAirtableSDKError(response.error || 'Failed to delete records');
    }
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
  ): Promise<any> {
    const response = await this.makeRequest<{ result: any }>(
      API_ENDPOINTS.FORMULA,
      {
        method: 'POST',
        body: JSON.stringify({
          baseId,
          tableId,
          recordId,
          formula,
        }),
      }
    );

    if (!response.success) {
      throw new PyAirtableSDKError(response.error || 'Formula evaluation failed');
    }

    return response.data?.result;
  }

  // File Operations

  /**
   * Upload a file
   */
  async uploadFile(
    file: File | Blob,
    filename: string,
    onProgress?: (progress: { loaded: number; total: number }) => void
  ): Promise<{ id: string; url: string }> {
    if (!this.isOnline) {
      throw new NetworkError('File upload requires internet connection');
    }

    const formData = new FormData();
    formData.append('file', file, filename);

    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();

      xhr.upload.addEventListener('progress', (event) => {
        if (event.lengthComputable && onProgress) {
          onProgress({
            loaded: event.loaded,
            total: event.total,
          });
        }
      });

      xhr.addEventListener('load', () => {
        try {
          const response = JSON.parse(xhr.responseText);
          
          if (xhr.status >= 200 && xhr.status < 300 && response.success) {
            resolve(response.data);
          } else {
            reject(new PyAirtableSDKError(response.error || 'Upload failed'));
          }
        } catch (error) {
          reject(new PyAirtableSDKError('Invalid response from server'));
        }
      });

      xhr.addEventListener('error', () => {
        reject(new NetworkError('Upload failed'));
      });

      xhr.open('POST', `${this.config.baseUrl}${API_ENDPOINTS.FILES_UPLOAD}`);
      
      // Add auth headers
      const authHeaders = this.authService.getAuthHeaders();
      Object.entries(authHeaders).forEach(([key, value]) => {
        xhr.setRequestHeader(key, value);
      });

      xhr.send(formData);
    });
  }

  /**
   * Download a file
   */
  async downloadFile(fileId: string): Promise<Blob> {
    if (!this.isOnline) {
      throw new NetworkError('File download requires internet connection');
    }

    const response = await fetch(
      `${this.config.baseUrl}${API_ENDPOINTS.FILES_DOWNLOAD(fileId)}`,
      {
        headers: this.authService.getAuthHeaders(),
      }
    );

    if (!response.ok) {
      throw new PyAirtableSDKError('Failed to download file');
    }

    return response.blob();
  }

  /**
   * Make authenticated API request
   */
  private async makeRequest<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<ApiResponse<T>> {
    if (!this.isOnline && !this.config.enableOfflineSync) {
      throw new NetworkError('No internet connection');
    }

    return withRetry(
      () => this.authService.makeAuthenticatedRequest<T>(endpoint, {
        timeout: this.config.timeout,
        ...options,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        },
      }),
      {
        attempts: this.config.retryAttempts || 3,
        delay: this.config.retryDelay || 1000,
      }
    );
  }
}