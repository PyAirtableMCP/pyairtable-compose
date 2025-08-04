import 'dart:async';
import 'dart:math';
import '../types/types.dart';

typedef RetryCallback<T> = Future<T> Function();
typedef ShouldRetryCallback = bool Function(PyAirtableException error);
typedef OnRetryCallback = void Function(PyAirtableException error, int attempt);

class RetryOptions {
  final int attempts;
  final int delay;
  final ShouldRetryCallback? shouldRetry;
  final OnRetryCallback? onRetry;

  const RetryOptions({
    required this.attempts,
    required this.delay,
    this.shouldRetry,
    this.onRetry,
  });
}

/// Retry a function with exponential backoff
Future<T> withRetry<T>(
  RetryCallback<T> callback,
  RetryOptions options,
) async {
  PyAirtableException? lastError;
  
  for (int attempt = 1; attempt <= options.attempts; attempt++) {
    try {
      return await callback();
    } catch (error) {
      lastError = error is PyAirtableException
          ? error
          : PyAirtableException(error.toString());
      
      // Don't retry on last attempt or if error is not retryable
      if (attempt == options.attempts || 
          (options.shouldRetry != null && !options.shouldRetry!(lastError))) {
        throw lastError;
      }
      
      options.onRetry?.call(lastError, attempt);
      
      // Wait before retrying
      final retryDelay = getRetryDelay(attempt, options.delay);
      await Future.delayed(Duration(milliseconds: retryDelay));
    }
  }
  
  throw lastError!;
}

/// Check if error is retryable
bool isRetryableError(PyAirtableException error) {
  if (error is NetworkException) return true;
  if (error is ServerException) return true;
  if (error is RateLimitException) return true;
  
  // Retry on specific status codes
  if (error.statusCode != null) {
    return [
      HttpStatus.badGateway,
      HttpStatus.serviceUnavailable,
      HttpStatus.tooManyRequests,
    ].contains(error.statusCode);
  }
  
  return false;
}

/// Get retry delay with exponential backoff and jitter
int getRetryDelay(int attempt, int baseDelay) {
  // Exponential backoff with jitter
  final exponentialDelay = baseDelay * pow(2, attempt - 1).toInt();
  final jitter = (Random().nextDouble() * 0.1 * exponentialDelay).toInt();
  return min(exponentialDelay + jitter, 30000); // Max 30 seconds
}

/// Create a timeout future that completes with an error after a given time
Future<T> timeout<T>(Future<T> future, int milliseconds) {
  return future.timeout(
    Duration(milliseconds: milliseconds),
    onTimeout: () => throw const PyAirtableException('Request timeout'),
  );
}

/// Debounce function calls
class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// Throttle function calls
class Throttler {
  final int milliseconds;
  bool _isThrottled = false;

  Throttler({required this.milliseconds});

  void run(VoidCallback action) {
    if (!_isThrottled) {
      action();
      _isThrottled = true;
      Timer(Duration(milliseconds: milliseconds), () {
        _isThrottled = false;
      });
    }
  }
}

typedef VoidCallback = void Function();