import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';

import '../auth/auth_service.dart';
import '../types/types.dart';
import '../utils/constants.dart';
import '../utils/retry.dart';

class ApiClient {
  final AuthService authService;
  final PyAirtableConfig config;
  final Dio _dio;
  final Connectivity _connectivity;
  
  bool _isOnline = true;

  ApiClient({
    required this.authService,
    required this.config,
  }) : _dio = Dio(),
       _connectivity = Connectivity() {
    _setupDio();
    _setupConnectivityListener();
  }

  void _setupDio() {
    _dio.options.baseUrl = config.baseUrl;
    _dio.options.connectTimeout = Duration(milliseconds: config.timeout);
    _dio.options.receiveTimeout = Duration(milliseconds: config.timeout);
    
    // Add retry interceptor
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        options: RetryOptions(
          retryCount: config.retryAttempts,
          retryDelay: Duration(milliseconds: config.retryDelay),
        ),
      ),
    );
  }

  void _setupConnectivityListener() {
    _connectivity.onConnectivityChanged.listen((connectivityResult) {
      _isOnline = connectivityResult != ConnectivityResult.none;
    });
  }

  bool get isOnline => _isOnline;

  // Base Operations

  Future<List<Base>> getBases() async {
    final response = await _makeRequest<Map<String, dynamic>>(ApiEndpoints.bases);
    final data = response.data;
    if (data == null || data['bases'] == null) return [];
    
    return (data['bases'] as List)
        .map((base) => Base.fromJson(base as Map<String, dynamic>))
        .toList();
  }

  Future<Base> getBase(String baseId) async {
    final response = await _makeRequest<Base>(
      '${ApiEndpoints.bases}/$baseId',
      fromJson: (json) => Base.fromJson(json as Map<String, dynamic>),
    );
    
    if (response.data == null) {
      throw const NotFoundException('Base');
    }
    
    return response.data!;
  }

  // Table Operations

  Future<List<Table>> getTables(String baseId) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      ApiEndpoints.tables(baseId),
    );
    
    final data = response.data;
    if (data == null || data['tables'] == null) return [];
    
    return (data['tables'] as List)
        .map((table) => Table.fromJson(table as Map<String, dynamic>))
        .toList();
  }

  Future<Table> getTable(String baseId, String tableId) async {
    final response = await _makeRequest<Table>(
      '${ApiEndpoints.tables(baseId)}/$tableId',
      fromJson: (json) => Table.fromJson(json as Map<String, dynamic>),
    );
    
    if (response.data == null) {
      throw const NotFoundException('Table');
    }
    
    return response.data!;
  }

  // Record Operations

  Future<RecordsResult> listRecords(
    String baseId,
    String tableId, {
    RecordQuery? query,
  }) async {
    final uri = Uri.parse('${config.baseUrl}${ApiEndpoints.records(baseId, tableId)}');
    final queryParams = query?.toQueryParams() ?? <String, String>{};
    
    final finalUri = uri.replace(queryParameters: queryParams);
    
    final response = await _makeRequestWithUri<Map<String, dynamic>>(finalUri);
    
    final data = response.data;
    if (data == null) {
      return const RecordsResult(records: []);
    }
    
    final records = (data['records'] as List? ?? [])
        .map((record) => Record.fromJson(record as Map<String, dynamic>))
        .toList();
    
    return RecordsResult(
      records: records,
      offset: data['offset'] as String?,
    );
  }

  Future<Record> getRecord(String baseId, String tableId, String recordId) async {
    final response = await _makeRequest<Record>(
      ApiEndpoints.record(baseId, tableId, recordId),
      fromJson: (json) => Record.fromJson(json as Map<String, dynamic>),
    );
    
    if (response.data == null) {
      throw const NotFoundException('Record');
    }
    
    return response.data!;
  }

  Future<Record> createRecord(
    String baseId,
    String tableId,
    RecordCreate record,
  ) async {
    final response = await _makeRequest<Record>(
      ApiEndpoints.records(baseId, tableId),
      method: 'POST',
      body: record.toJson(),
      fromJson: (json) => Record.fromJson(json as Map<String, dynamic>),
    );

    if (response.data == null) {
      throw PyAirtableException(response.error ?? 'Failed to create record');
    }

    return response.data!;
  }

  Future<List<Record>> createRecords(
    String baseId,
    String tableId,
    List<RecordCreate> records,
  ) async {
    final body = {
      'records': records.map((r) => r.toJson()).toList(),
    };
    
    final response = await _makeRequest<Map<String, dynamic>>(
      ApiEndpoints.records(baseId, tableId),
      method: 'POST',
      body: body,
    );

    final data = response.data;
    if (data == null || data['records'] == null) {
      throw PyAirtableException(response.error ?? 'Failed to create records');
    }

    return (data['records'] as List)
        .map((record) => Record.fromJson(record as Map<String, dynamic>))
        .toList();
  }

  Future<Record> updateRecord(
    String baseId,
    String tableId,
    RecordUpdate record,
  ) async {
    final response = await _makeRequest<Record>(
      ApiEndpoints.record(baseId, tableId, record.id),
      method: 'PATCH',
      body: {'fields': record.fields},
      fromJson: (json) => Record.fromJson(json as Map<String, dynamic>),
    );

    if (response.data == null) {
      throw PyAirtableException(response.error ?? 'Failed to update record');
    }

    return response.data!;
  }

  Future<List<Record>> updateRecords(
    String baseId,
    String tableId,
    List<RecordUpdate> records,
  ) async {
    final body = {
      'records': records.map((r) => r.toJson()).toList(),
    };
    
    final response = await _makeRequest<Map<String, dynamic>>(
      ApiEndpoints.records(baseId, tableId),
      method: 'PATCH',
      body: body,
    );

    final data = response.data;
    if (data == null || data['records'] == null) {
      throw PyAirtableException(response.error ?? 'Failed to update records');
    }

    return (data['records'] as List)
        .map((record) => Record.fromJson(record as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteRecord(String baseId, String tableId, String recordId) async {
    final response = await _makeRequest(
      ApiEndpoints.record(baseId, tableId, recordId),
      method: 'DELETE',
    );

    if (!response.success) {
      throw PyAirtableException(response.error ?? 'Failed to delete record');
    }
  }

  Future<void> deleteRecords(String baseId, String tableId, List<String> recordIds) async {
    final uri = Uri.parse('${config.baseUrl}${ApiEndpoints.records(baseId, tableId)}');
    final queryParams = <String, String>{};
    
    for (final id in recordIds) {
      queryParams['records[]'] = id;
    }
    
    final finalUri = uri.replace(queryParameters: queryParams);
    
    final response = await _makeRequestWithUri(finalUri, method: 'DELETE');

    if (!response.success) {
      throw PyAirtableException(response.error ?? 'Failed to delete records');
    }
  }

  // Formula Operations

  Future<dynamic> evaluateFormula(
    String baseId,
    String tableId,
    String recordId,
    String formula,
  ) async {
    final body = {
      'baseId': baseId,
      'tableId': tableId,
      'recordId': recordId,
      'formula': formula,
    };
    
    final response = await _makeRequest<Map<String, dynamic>>(
      ApiEndpoints.formula,
      method: 'POST',
      body: body,
    );

    if (!response.success || response.data == null) {
      throw PyAirtableException(response.error ?? 'Formula evaluation failed');
    }

    return response.data!['result'];
  }

  // File Operations

  Future<FileUploadResult> uploadFile(
    String filePath,
    String filename, {
    void Function(FileUploadProgress)? onProgress,
  }) async {
    if (!_isOnline) {
      throw const NetworkException('File upload requires internet connection');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw const PyAirtableException('File does not exist');
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });

    try {
      final response = await _dio.post(
        ApiEndpoints.filesUpload,
        data: formData,
        options: Options(
          headers: authService._getAuthHeaders(),
        ),
        onSendProgress: (sent, total) {
          if (onProgress != null) {
            final progress = FileUploadProgress(
              loaded: sent,
              total: total,
              percentage: (sent / total * 100),
            );
            onProgress(progress);
          }
        },
      );

      if (response.statusCode! >= 200 && response.statusCode! < 300) {
        final data = response.data;
        return FileUploadResult(
          id: data['id'] as String,
          url: data['url'] as String,
        );
      } else {
        throw PyAirtableException('Upload failed: ${response.statusMessage}');
      }
    } catch (error) {
      if (error is DioException) {
        throw NetworkException('Upload failed: ${error.message}');
      }
      rethrow;
    }
  }

  Future<List<int>> downloadFile(String fileId) async {
    if (!_isOnline) {
      throw const NetworkException('File download requires internet connection');
    }

    try {
      final response = await _dio.get(
        ApiEndpoints.filesDownload(fileId),
        options: Options(
          headers: authService._getAuthHeaders(),
          responseType: ResponseType.bytes,
        ),
      );

      if (response.statusCode! >= 200 && response.statusCode! < 300) {
        return response.data as List<int>;
      } else {
        throw const PyAirtableException('Failed to download file');
      }
    } catch (error) {
      if (error is DioException) {
        throw NetworkException('Download failed: ${error.message}');
      }
      rethrow;
    }
  }

  // Private methods

  Future<ApiResponse<T>> _makeRequest<T>(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
  }) async {
    if (!_isOnline && !config.enableOfflineSync) {
      throw const NetworkException('No internet connection');
    }

    return withRetry(
      () => authService.makeAuthenticatedRequest<T>(
        endpoint,
        method: method,
        body: body,
        headers: {
          'Content-Type': 'application/json',
          ...?headers,
        },
        fromJson: fromJson,
      ),
      RetryOptions(
        attempts: config.retryAttempts,
        delay: config.retryDelay,
        shouldRetry: isRetryableError,
      ),
    );
  }

  Future<ApiResponse<T>> _makeRequestWithUri<T>(
    Uri uri, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    T Function(dynamic)? fromJson,
  }) async {
    if (!_isOnline && !config.enableOfflineSync) {
      throw const NetworkException('No internet connection');
    }

    return withRetry(
      () async {
        final request = http.Request(method, uri);
        
        final authHeaders = authService._getAuthHeaders();
        request.headers.addAll({
          'Content-Type': 'application/json',
          ...authHeaders,
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
      RetryOptions(
        attempts: config.retryAttempts,
        delay: config.retryDelay,
        shouldRetry: isRetryableError,
      ),
    );
  }

  PyAirtableException _createErrorFromResponse(http.Response response, dynamic data) {
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
}

// Extension to access private method (temporary workaround)
extension AuthServiceExtension on AuthService {
  Map<String, String> _getAuthHeaders() {
    final headers = <String, String>{
      'X-API-Key': apiKey,
    };

    if (tokens?.accessToken != null) {
      headers['Authorization'] = 'Bearer ${tokens!.accessToken}';
    }

    return headers;
  }
}

// Custom Dio retry interceptor
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final RetryOptions options;

  RetryInterceptor({required this.dio, required this.options});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_shouldRetry(err) && err.requestOptions.extra['retryCount'] == null) {
      err.requestOptions.extra['retryCount'] = 0;
    }

    final retryCount = err.requestOptions.extra['retryCount'] as int? ?? 0;
    
    if (retryCount < options.retryCount && _shouldRetry(err)) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      
      await Future.delayed(options.retryDelay);
      
      try {
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
      } catch (e) {
        super.onError(err, handler);
      }
    } else {
      super.onError(err, handler);
    }
  }

  bool _shouldRetry(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
           error.type == DioExceptionType.receiveTimeout ||
           error.type == DioExceptionType.sendTimeout ||
           (error.response?.statusCode != null && [502, 503, 429].contains(error.response!.statusCode));
  }
}

class RetryOptions {
  final int retryCount;
  final Duration retryDelay;

  const RetryOptions({
    required this.retryCount,
    required this.retryDelay,
  });
}