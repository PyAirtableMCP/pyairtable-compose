import EncryptedStorage from 'react-native-encrypted-storage';
import { AuthTokens, User, LoginCredentials, ApiResponse } from '../types';
import { STORAGE_KEYS, API_ENDPOINTS } from '../utils/constants';
import { AuthenticationError, PyAirtableSDKError } from '../utils/errors';
import { withRetry } from '../utils/retry';

export class AuthService {
  private baseUrl: string;
  private apiKey: string;
  private tokens: AuthTokens | null = null;
  private user: User | null = null;
  private refreshPromise: Promise<void> | null = null;

  constructor(baseUrl: string, apiKey: string) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.initializeFromStorage();
  }

  /**
   * Initialize auth state from encrypted storage
   */
  private async initializeFromStorage(): Promise<void> {
    try {
      const [tokensStr, userStr] = await Promise.all([
        EncryptedStorage.getItem(STORAGE_KEYS.AUTH_TOKENS),
        EncryptedStorage.getItem(STORAGE_KEYS.USER_DATA),
      ]);

      if (tokensStr) {
        this.tokens = JSON.parse(tokensStr);
      }

      if (userStr) {
        this.user = JSON.parse(userStr);
      }

      // Check if tokens are expired and refresh if needed
      if (this.tokens && this.isTokenExpired()) {
        await this.refreshTokens();
      }
    } catch (error) {
      console.warn('Failed to initialize auth from storage:', error);
      await this.clearStoredAuth();
    }
  }

  /**
   * Login with email and password
   */
  async login(credentials: LoginCredentials): Promise<void> {
    try {
      const response = await this.makeRequest<{
        tokens: AuthTokens;
        user: User;
      }>(API_ENDPOINTS.AUTH_LOGIN, {
        method: 'POST',
        body: JSON.stringify(credentials),
        headers: {
          'Content-Type': 'application/json',
        },
      });

      if (!response.success || !response.data) {
        throw new AuthenticationError(response.error || 'Login failed');
      }

      const { tokens, user } = response.data;
      await this.setTokens(tokens);
      await this.setUser(user);
    } catch (error) {
      throw error instanceof PyAirtableSDKError ? error : 
        new AuthenticationError('Login failed: ' + error.message);
    }
  }

  /**
   * Logout and clear all stored data
   */
  async logout(): Promise<void> {
    try {
      if (this.tokens) {
        await this.makeRequest(API_ENDPOINTS.AUTH_LOGOUT, {
          method: 'POST',
          headers: this.getAuthHeaders(),
        });
      }
    } catch (error) {
      console.warn('Logout request failed:', error);
    } finally {
      await this.clearStoredAuth();
    }
  }

  /**
   * Refresh access token using refresh token
   */
  async refreshTokens(): Promise<void> {
    // Prevent multiple simultaneous refresh attempts
    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    this.refreshPromise = this.performTokenRefresh();
    
    try {
      await this.refreshPromise;
    } finally {
      this.refreshPromise = null;
    }
  }

  private async performTokenRefresh(): Promise<void> {
    if (!this.tokens?.refreshToken) {
      throw new AuthenticationError('No refresh token available');
    }

    try {
      const response = await this.makeRequest<{
        tokens: AuthTokens;
        user?: User;
      }>(API_ENDPOINTS.AUTH_REFRESH, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.tokens.refreshToken}`,
        },
      });

      if (!response.success || !response.data) {
        throw new AuthenticationError(response.error || 'Token refresh failed');
      }

      const { tokens, user } = response.data;
      await this.setTokens(tokens);
      
      if (user) {
        await this.setUser(user);
      }
    } catch (error) {
      await this.clearStoredAuth();
      throw error instanceof PyAirtableSDKError ? error : 
        new AuthenticationError('Token refresh failed: ' + error.message);
    }
  }

  /**
   * Get current user
   */
  getUser(): User | null {
    return this.user;
  }

  /**
   * Get current tokens
   */
  getTokens(): AuthTokens | null {
    return this.tokens;
  }

  /**
   * Check if user is authenticated
   */
  isAuthenticated(): boolean {
    return !!this.tokens && !this.isTokenExpired();
  }

  /**
   * Get authorization headers for API requests
   */
  getAuthHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'X-API-Key': this.apiKey,
    };

    if (this.tokens?.accessToken) {
      headers['Authorization'] = `Bearer ${this.tokens.accessToken}`;
    }

    return headers;
  }

  /**
   * Make authenticated API request with automatic token refresh
   */
  async makeAuthenticatedRequest<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<ApiResponse<T>> {
    if (!this.isAuthenticated()) {
      throw new AuthenticationError('Not authenticated');
    }

    // Add auth headers
    const headers = {
      ...options.headers,
      ...this.getAuthHeaders(),
    };

    try {
      return await this.makeRequest<T>(endpoint, { ...options, headers });
    } catch (error) {
      // If token expired, try to refresh and retry once
      if (error instanceof AuthenticationError && this.tokens?.refreshToken) {
        try {
          await this.refreshTokens();
          
          // Retry with new token
          const newHeaders = {
            ...options.headers,
            ...this.getAuthHeaders(),
          };
          
          return await this.makeRequest<T>(endpoint, { ...options, headers: newHeaders });
        } catch (refreshError) {
          throw refreshError;
        }
      }
      
      throw error;
    }
  }

  /**
   * Make basic API request with retry logic
   */
  private async makeRequest<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<ApiResponse<T>> {
    const url = `${this.baseUrl}${endpoint}`;
    
    return withRetry(
      async () => {
        const response = await fetch(url, {
          timeout: 30000,
          ...options,
          headers: {
            'Content-Type': 'application/json',
            ...options.headers,
          },
        });

        const data = await response.json();

        if (!response.ok) {
          const error = new PyAirtableSDKError(
            data.message || response.statusText,
            data.code,
            response.status,
            data
          );
          throw error;
        }

        return data as ApiResponse<T>;
      },
      {
        attempts: 3,
        delay: 1000,
      }
    );
  }

  /**
   * Check if current token is expired
   */
  private isTokenExpired(): boolean {
    if (!this.tokens) return true;
    
    // Add 5 minute buffer
    const expirationBuffer = 5 * 60 * 1000;
    return Date.now() >= (this.tokens.expiresAt - expirationBuffer);
  }

  /**
   * Store tokens in encrypted storage
   */
  private async setTokens(tokens: AuthTokens): Promise<void> {
    this.tokens = tokens;
    await EncryptedStorage.setItem(STORAGE_KEYS.AUTH_TOKENS, JSON.stringify(tokens));
  }

  /**
   * Store user data in encrypted storage
   */
  private async setUser(user: User): Promise<void> {
    this.user = user;
    await EncryptedStorage.setItem(STORAGE_KEYS.USER_DATA, JSON.stringify(user));
  }

  /**
   * Clear all stored authentication data
   */
  private async clearStoredAuth(): Promise<void> {
    this.tokens = null;
    this.user = null;
    
    await Promise.all([
      EncryptedStorage.removeItem(STORAGE_KEYS.AUTH_TOKENS),
      EncryptedStorage.removeItem(STORAGE_KEYS.USER_DATA),
    ]);
  }
}