import WebSocket from 'ws';
import { EventEmitter } from 'events';
import { AuthService } from '../auth/AuthService';
import { WebSocketMessage } from '../types';
import { API_ENDPOINTS, WEBSOCKET_EVENTS } from '../utils/constants';
import { NetworkError, PyAirtableSDKError } from '../utils/errors';
import { sleep } from '../utils/retry';

export interface WebSocketOptions {
  baseUrl: string;
  reconnectInterval?: number;
  maxReconnectAttempts?: number;
  heartbeatInterval?: number;
  enableCompression?: boolean;
}

export class WebSocketClient extends EventEmitter {
  private ws: WebSocket | null = null;
  private authService: AuthService;
  private options: Required<WebSocketOptions>;
  private reconnectAttempts = 0;
  private isConnecting = false;
  private isManuallyDisconnected = false;
  private heartbeatTimer: NodeJS.Timeout | null = null;
  private reconnectTimer: NodeJS.Timeout | null = null;

  constructor(authService: AuthService, options: WebSocketOptions) {
    super();
    this.authService = authService;
    this.options = {
      reconnectInterval: 5000,
      maxReconnectAttempts: 10,
      heartbeatInterval: 30000,
      enableCompression: true,
      ...options,
    };
  }

  /**
   * Connect to WebSocket server
   */
  async connect(): Promise<void> {
    if (this.isConnecting || (this.ws && this.ws.readyState === WebSocket.OPEN)) {
      return;
    }

    if (!this.authService.isAuthenticated()) {
      throw new PyAirtableSDKError('Must be authenticated to connect to WebSocket');
    }

    this.isConnecting = true;
    this.isManuallyDisconnected = false;

    try {
      const wsUrl = this.buildWebSocketUrl();
      
      this.ws = new WebSocket(wsUrl, {
        headers: this.authService.getAuthHeaders(),
        compression: this.options.enableCompression,
      });

      this.setupEventListeners();
      
      await this.waitForConnection();
      
      this.reconnectAttempts = 0;
      this.startHeartbeat();
      
      this.emit(WEBSOCKET_EVENTS.CONNECT);
    } catch (error) {
      this.isConnecting = false;
      throw new NetworkError('Failed to connect to WebSocket: ' + error.message);
    }
  }

  /**
   * Disconnect from WebSocket server
   */
  disconnect(): void {
    this.isManuallyDisconnected = true;
    this.cleanup();
    
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    
    this.emit(WEBSOCKET_EVENTS.DISCONNECT);
  }

  /**
   * Check if WebSocket is connected
   */
  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  /**
   * Send a message through WebSocket
   */
  send(data: any): void {
    if (!this.isConnected()) {
      throw new NetworkError('WebSocket is not connected');
    }

    try {
      this.ws!.send(JSON.stringify(data));
    } catch (error) {
      throw new NetworkError('Failed to send WebSocket message: ' + error.message);
    }
  }

  /**
   * Subscribe to real-time updates for a table
   */
  subscribeToTable(baseId: string, tableId: string): void {
    this.send({
      type: 'subscribe',
      data: {
        baseId,
        tableId,
      },
    });
  }

  /**
   * Unsubscribe from real-time updates for a table
   */
  unsubscribeFromTable(baseId: string, tableId: string): void {
    this.send({
      type: 'unsubscribe',
      data: {
        baseId,
        tableId,
      },
    });
  }

  /**
   * Build WebSocket URL with authentication
   */
  private buildWebSocketUrl(): string {
    const wsProtocol = this.options.baseUrl.startsWith('https') ? 'wss' : 'ws';
    const baseUrl = this.options.baseUrl.replace(/^https?/, wsProtocol);
    
    const tokens = this.authService.getTokens();
    if (!tokens?.accessToken) {
      throw new PyAirtableSDKError('No access token available');
    }

    const url = new URL(`${baseUrl}${API_ENDPOINTS.WEBSOCKET}`);
    url.searchParams.set('token', tokens.accessToken);
    
    return url.toString();
  }

  /**
   * Setup WebSocket event listeners
   */
  private setupEventListeners(): void {
    if (!this.ws) return;

    this.ws.on('open', () => {
      this.isConnecting = false;
    });

    this.ws.on('message', (data: WebSocket.Data) => {
      try {
        const message: WebSocketMessage = JSON.parse(data.toString());
        this.handleMessage(message);
      } catch (error) {
        this.emit(WEBSOCKET_EVENTS.ERROR, new PyAirtableSDKError('Invalid WebSocket message'));
      }
    });

    this.ws.on('close', (code: number, reason: string) => {
      this.cleanup();
      
      if (!this.isManuallyDisconnected) {
        this.emit(WEBSOCKET_EVENTS.DISCONNECT, { code, reason });
        this.scheduleReconnect();
      }
    });

    this.ws.on('error', (error: Error) => {
      this.emit(WEBSOCKET_EVENTS.ERROR, new NetworkError('WebSocket error: ' + error.message));
    });

    this.ws.on('pong', () => {
      // Heartbeat response received
    });
  }

  /**
   * Handle incoming WebSocket messages
   */
  private handleMessage(message: WebSocketMessage): void {
    switch (message.type) {
      case 'recordCreated':
        this.emit(WEBSOCKET_EVENTS.RECORD_CREATED, message.data);
        break;
        
      case 'recordUpdated':
        this.emit(WEBSOCKET_EVENTS.RECORD_UPDATED, message.data);
        break;
        
      case 'recordDeleted':
        this.emit(WEBSOCKET_EVENTS.RECORD_DELETED, message.data);
        break;
        
      case 'tableUpdated':
        this.emit(WEBSOCKET_EVENTS.TABLE_UPDATED, message.data);
        break;
        
      default:
        this.emit('message', message);
    }
  }

  /**
   * Wait for WebSocket connection to open
   */
  private async waitForConnection(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.ws) {
        reject(new NetworkError('WebSocket not initialized'));
        return;
      }

      const timeout = setTimeout(() => {
        reject(new NetworkError('WebSocket connection timeout'));
      }, 10000);

      this.ws.once('open', () => {
        clearTimeout(timeout);
        resolve();
      });

      this.ws.once('error', (error) => {
        clearTimeout(timeout);
        reject(new NetworkError('WebSocket connection failed: ' + error.message));
      });
    });
  }

  /**
   * Start heartbeat to keep connection alive
   */
  private startHeartbeat(): void {
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnected()) {
        this.ws!.ping();
      }
    }, this.options.heartbeatInterval);
  }

  /**
   * Schedule reconnection attempt
   */
  private scheduleReconnect(): void {
    if (this.isManuallyDisconnected || 
        this.reconnectAttempts >= this.options.maxReconnectAttempts) {
      return;
    }

    this.reconnectAttempts++;
    
    const delay = Math.min(
      this.options.reconnectInterval * Math.pow(2, this.reconnectAttempts - 1),
      30000 // Max 30 seconds
    );

    this.reconnectTimer = setTimeout(async () => {
      try {
        await this.connect();
      } catch (error) {
        this.emit(WEBSOCKET_EVENTS.ERROR, error);
        this.scheduleReconnect();
      }
    }, delay);
  }

  /**
   * Cleanup timers and resources
   */
  private cleanup(): void {
    this.isConnecting = false;
    
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  /**
   * Destroy WebSocket client and cleanup all resources
   */
  destroy(): void {
    this.isManuallyDisconnected = true;
    this.cleanup();
    
    if (this.ws) {
      this.ws.terminate();
      this.ws = null;
    }
    
    this.removeAllListeners();
  }
}