import { PyAirtableSDKError, isRetryableError, getRetryDelay } from './errors';

export interface RetryOptions {
  attempts: number;
  delay: number;
  shouldRetry?: (error: PyAirtableSDKError) => boolean;
  onRetry?: (error: PyAirtableSDKError, attempt: number) => void;
}

/**
 * Retry a function with exponential backoff
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions
): Promise<T> {
  const { attempts, delay, shouldRetry = isRetryableError, onRetry } = options;
  
  let lastError: PyAirtableSDKError;
  
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error instanceof PyAirtableSDKError ? error : 
        new PyAirtableSDKError(error.message || 'Unknown error');
      
      // Don't retry on last attempt or if error is not retryable
      if (attempt === attempts || !shouldRetry(lastError)) {
        throw lastError;
      }
      
      onRetry?.(lastError, attempt);
      
      // Wait before retrying
      const retryDelay = getRetryDelay(attempt, delay);
      await sleep(retryDelay);
    }
  }
  
  throw lastError!;
}

/**
 * Sleep for a given number of milliseconds
 */
export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Create a timeout promise that rejects after a given time
 */
export function timeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new PyAirtableSDKError('Request timeout')), ms)
    ),
  ]);
}

/**
 * Debounce a function to prevent multiple rapid calls
 */
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeoutId: NodeJS.Timeout | null = null;
  
  return (...args: Parameters<T>) => {
    if (timeoutId) {
      clearTimeout(timeoutId);
    }
    
    timeoutId = setTimeout(() => {
      func(...args);
    }, wait);
  };
}

/**
 * Throttle a function to limit execution frequency
 */
export function throttle<T extends (...args: any[]) => any>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle = false;
  
  return (...args: Parameters<T>) => {
    if (!inThrottle) {
      func(...args);
      inThrottle = true;
      setTimeout(() => inThrottle = false, limit);
    }
  };
}