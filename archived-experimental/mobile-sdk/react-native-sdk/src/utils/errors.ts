import { PyAirtableError } from '../types';
import { ERROR_CODES, HTTP_STATUS } from './constants';

export class PyAirtableSDKError extends Error implements PyAirtableError {
  public code?: string;
  public statusCode?: number;
  public details?: any;

  constructor(message: string, code?: string, statusCode?: number, details?: any) {
    super(message);
    this.name = 'PyAirtableSDKError';
    this.code = code;
    this.statusCode = statusCode;
    this.details = details;
  }
}

export class NetworkError extends PyAirtableSDKError {
  constructor(message: string = 'Network request failed', details?: any) {
    super(message, ERROR_CODES.NETWORK_ERROR, undefined, details);
    this.name = 'NetworkError';
  }
}

export class AuthenticationError extends PyAirtableSDKError {
  constructor(message: string = 'Authentication failed') {
    super(message, ERROR_CODES.AUTH_ERROR, HTTP_STATUS.UNAUTHORIZED);
    this.name = 'AuthenticationError';
  }
}

export class ValidationError extends PyAirtableSDKError {
  constructor(message: string, details?: any) {
    super(message, ERROR_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST, details);
    this.name = 'ValidationError';
  }
}

export class NotFoundError extends PyAirtableSDKError {
  constructor(resource: string = 'Resource') {
    super(`${resource} not found`, ERROR_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    this.name = 'NotFoundError';
  }
}

export class PermissionError extends PyAirtableSDKError {
  constructor(message: string = 'Permission denied') {
    super(message, ERROR_CODES.PERMISSION_DENIED, HTTP_STATUS.FORBIDDEN);
    this.name = 'PermissionError';
  }
}

export class RateLimitError extends PyAirtableSDKError {
  constructor(retryAfter?: number) {
    super('Rate limit exceeded', ERROR_CODES.RATE_LIMITED, HTTP_STATUS.TOO_MANY_REQUESTS, { retryAfter });
    this.name = 'RateLimitError';
  }
}

export class ServerError extends PyAirtableSDKError {
  constructor(message: string = 'Internal server error', statusCode: number = HTTP_STATUS.INTERNAL_SERVER_ERROR) {
    super(message, ERROR_CODES.SERVER_ERROR, statusCode);
    this.name = 'ServerError';
  }
}

export class OfflineError extends PyAirtableSDKError {
  constructor(message: string = 'Operation not available offline') {
    super(message, ERROR_CODES.OFFLINE_ERROR);
    this.name = 'OfflineError';
  }
}

export class SyncError extends PyAirtableSDKError {
  constructor(message: string, details?: any) {
    super(message, ERROR_CODES.SYNC_ERROR, undefined, details);
    this.name = 'SyncError';
  }
}

export function createErrorFromResponse(response: Response, data?: any): PyAirtableSDKError {
  const { status, statusText } = response;
  
  switch (status) {
    case HTTP_STATUS.BAD_REQUEST:
      return new ValidationError(data?.message || statusText, data);
    case HTTP_STATUS.UNAUTHORIZED:
      return new AuthenticationError(data?.message || statusText);
    case HTTP_STATUS.FORBIDDEN:
      return new PermissionError(data?.message || statusText);
    case HTTP_STATUS.NOT_FOUND:
      return new NotFoundError(data?.message || statusText);
    case HTTP_STATUS.CONFLICT:
      return new ValidationError(data?.message || 'Conflict occurred', data);
    case HTTP_STATUS.UNPROCESSABLE_ENTITY:
      return new ValidationError(data?.message || 'Validation failed', data);
    case HTTP_STATUS.TOO_MANY_REQUESTS:
      return new RateLimitError(data?.retryAfter);
    case HTTP_STATUS.INTERNAL_SERVER_ERROR:
    case HTTP_STATUS.BAD_GATEWAY:
    case HTTP_STATUS.SERVICE_UNAVAILABLE:
      return new ServerError(data?.message || statusText, status);
    default:
      return new PyAirtableSDKError(data?.message || statusText, 'UNKNOWN_ERROR', status, data);
  }
}

export function isRetryableError(error: PyAirtableSDKError): boolean {
  if (error instanceof NetworkError) return true;
  if (error instanceof ServerError) return true;
  if (error instanceof RateLimitError) return true;
  
  // Retry on specific status codes
  if (error.statusCode) {
    return [
      HTTP_STATUS.BAD_GATEWAY,
      HTTP_STATUS.SERVICE_UNAVAILABLE,
      HTTP_STATUS.TOO_MANY_REQUESTS,
    ].includes(error.statusCode);
  }
  
  return false;
}

export function getRetryDelay(attempt: number, baseDelay: number = 1000): number {
  // Exponential backoff with jitter
  const exponentialDelay = baseDelay * Math.pow(2, attempt - 1);
  const jitter = Math.random() * 0.1 * exponentialDelay;
  return Math.min(exponentialDelay + jitter, 30000); // Max 30 seconds
}