import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../types/types.dart';
import '../utils/constants.dart';
import '../utils/retry.dart';

class AuthService {
  final String baseUrl;
  final String apiKey;
  final FlutterSecureStorage _secureStorage;
  
  AuthTokens? _tokens;
  User? _user;
  Completer<void>? _refreshCompleter;

  AuthService({
    required this.baseUrl,
    required this.apiKey,
  }) : _secureStorage = const FlutterSecureStorage();

  /// Initialize auth state from secure storage
  Future<void> initialize() async {
    try {
      final tokensJson = await _secureStorage.read(key: StorageKeys.authTokens);
      final userJson = await _secureStorage.read(key: StorageKeys.userData);

      if (tokensJson != null) {
        _tokens = AuthTokens.fromJson(jsonDecode(tokensJson));
      }

      if (userJson != null) {
        _user = User.fromJson(jsonDecode(userJson));
      }

      // Check if tokens are expired and refresh if needed
      if (_tokens != null && _tokens!.isExpired) {
        await refreshTokens();
      }
    } catch (error) {
      print('Failed to initialize auth from storage: $error');
      await _clearStoredAuth();
    }
  }

  /// Login with email and password
  Future<void> login(LoginCredentials credentials) async {
    try {
      final response = await _makeRequest<Map<String, dynamic>>(
        ApiEndpoints.authLogin,
        method: 'POST',
        body: credentials.toJson(),
      );

      if (!response.success || response.data == null) {
        throw AuthenticationException(response.error ?? 'Login failed');
      }

      final tokens = AuthTokens.fromJson(response.data!['tokens']);
      final user = User.fromJson(response.data!['user']);
      
      await _setTokens(tokens);
      await _setUser(user);
    } catch (error) {
      if (error is PyAirtableException) {
        rethrow;
      }
      throw AuthenticationException('Login failed: $error');
    }
  }

  /// Logout and clear all stored data
  Future<void> logout() async {
    try {
      if (_tokens != null) {
        await _makeRequest(
          ApiEndpoints.authLogout,
          method: 'POST',
          headers: _getAuthHeaders(),
        );
      }
    } catch (error) {
      print('Logout request failed: $error');
    } finally {
      await _clearStoredAuth();
    }
  }

  /// Refresh access token using refresh token
  Future<void> refreshTokens() async {
    // Prevent multiple simultaneous refresh attempts
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<void>();
    
    try {
      await _performTokenRefresh();
      _refreshCompleter!.complete();
    } catch (error) {
      _refreshCompleter!.completeError(error);
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<void> _performTokenRefresh() async {
    if (_tokens?.refreshToken == null) {
      throw const AuthenticationException('No refresh token available');
    }

    try {
      final response = await _makeRequest<Map<String, dynamic>>(
        ApiEndpoints.authRefresh,
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ${_tokens!.refreshToken}',
        },
      );

      if (!response.success || response.data == null) {
        throw AuthenticationException(response.error ?? 'Token refresh failed');
      }

      final tokens = AuthTokens.fromJson(response.data!['tokens']);
      await _setTokens(tokens);
      
      if (response.data!['user'] != null) {
        final user = User.fromJson(response.data!['user']);
        await _setUser(user);
      }
    } catch (error) {
      await _clearStoredAuth();
      if (error is PyAirtableException) {
        rethrow;
      }
      throw AuthenticationException('Token refresh failed: $error');
    }
  }

  /// Get current user
  User? get user => _user;

  /// Get current tokens
  AuthTokens? get tokens => _tokens;

  /// Check if user is authenticated
  bool get isAuthenticated => _tokens != null && !_tokens!.isExpired;

  /// Get authorization headers for API requests
  Map<String, String> _getAuthHeaders() {
    final headers = <String, String>{
      'X-API-Key': apiKey,
    };

    if (_tokens?.accessToken != null) {
      headers['Authorization'] = 'Bearer ${_tokens!.accessToken}';
    }

    return headers;
  }

  /// Make authenticated API request with automatic token refresh
  Future<ApiResponse<T>> makeAuthenticatedRequest<T>(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
  }) async {
    if (!isAuthenticated) {
      throw const AuthenticationException('Not authenticated');
    }

    // Add auth headers
    final authHeaders = {
      ...?headers,
      ..._getAuthHeaders(),
    };

    try {
      return await _makeRequest<T>(
        endpoint,
        method: method,
        body: body,
        headers: authHeaders,
        fromJson: fromJson,
      );
    } catch (error) {
      // If token expired, try to refresh and retry once
      if (error is AuthenticationException && _tokens?.refreshToken != null) {
        try {
          await refreshTokens();
          
          // Retry with new token
          final newAuthHeaders = {
            ...?headers,
            ..._getAuthHeaders(),
          };
          
          return await _makeRequest<T>(
            endpoint,
            method: method,
            body: body,
            headers: newAuthHeaders,
            fromJson: fromJson,
          );
        } catch (refreshError) {
          rethrow;
        }
      }
      
      rethrow;
    }
  }

  /// Make basic API request with retry logic
  Future<ApiResponse<T>> _makeRequest<T>(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');
    
    return withRetry(
      () async {
        final request = http.Request(method, url);
        
        request.headers.addAll({
          'Content-Type': 'application/json',
          ...?headers,
        });

        if (body != null) {
          request.body = jsonEncode(body);
        }

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
        
        final responseData = jsonDecode(response.body);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _createErrorFromResponse(response, responseData);
        }

        return ApiResponse<T>.fromJson(responseData, fromJson);
      },
      const RetryOptions(
        attempts: 3,
        delay: 1000,
        shouldRetry: isRetryableError,
      ),
    );
  }

  /// Create error from HTTP response
  PyAirtableException _createErrorFromResponse(
    http.Response response,
    dynamic data,
  ) {
    final statusCode = response.statusCode;
    final message = data is Map<String, dynamic> ? data['message'] : response.reasonPhrase;
    
    switch (statusCode) {
      case HttpStatus.badRequest:
        return ValidationException(message ?? 'Bad request', details: data);
      case HttpStatus.unauthorized:
        return AuthenticationException(message ?? 'Unauthorized');
      case HttpStatus.forbidden:
        return PermissionException(message ?? 'Forbidden');
      case HttpStatus.notFound:
        return NotFoundException(message ?? 'Not found');
      case HttpStatus.conflict:
        return ValidationException(message ?? 'Conflict', details: data);
      case HttpStatus.unprocessableEntity:
        return ValidationException(message ?? 'Validation failed', details: data);
      case HttpStatus.tooManyRequests:
        final retryAfter = data is Map<String, dynamic> ? data['retryAfter'] : null;
        return RateLimitException(retryAfter: retryAfter);
      case HttpStatus.internalServerError:
      case HttpStatus.badGateway:
      case HttpStatus.serviceUnavailable:
        return ServerException(message ?? 'Server error', statusCode: statusCode);
      default:
        return PyAirtableException(
          message ?? 'Unknown error',
          code: 'UNKNOWN_ERROR',
          statusCode: statusCode,
          details: data,
        );
    }
  }

  /// Store tokens in secure storage
  Future<void> _setTokens(AuthTokens tokens) async {
    _tokens = tokens;
    await _secureStorage.write(
      key: StorageKeys.authTokens,
      value: jsonEncode(tokens.toJson()),
    );
  }

  /// Store user data in secure storage
  Future<void> _setUser(User user) async {
    _user = user;
    await _secureStorage.write(
      key: StorageKeys.userData,
      value: jsonEncode(user.toJson()),
    );
  }

  /// Clear all stored authentication data
  Future<void> _clearStoredAuth() async {
    _tokens = null;
    _user = null;
    
    await Future.wait([
      _secureStorage.delete(key: StorageKeys.authTokens),
      _secureStorage.delete(key: StorageKeys.userData),
    ]);
  }
}