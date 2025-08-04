import 'package:equatable/equatable.dart';

// Configuration
class PyAirtableConfig extends Equatable {
  final String apiKey;
  final String baseUrl;
  final int timeout;
  final int retryAttempts;
  final int retryDelay;
  final bool enableOfflineSync;
  final bool enableWebSocket;
  final bool enablePushNotifications;

  const PyAirtableConfig({
    required this.apiKey,
    required this.baseUrl,
    this.timeout = 30000,
    this.retryAttempts = 3,
    this.retryDelay = 1000,
    this.enableOfflineSync = true,
    this.enableWebSocket = true,
    this.enablePushNotifications = false,
  });

  @override
  List<Object?> get props => [
        apiKey,
        baseUrl,
        timeout,
        retryAttempts,
        retryDelay,
        enableOfflineSync,
        enableWebSocket,
        enablePushNotifications,
      ];
}

// API Response
class ApiResponse<T> extends Equatable {
  final bool success;
  final T? data;
  final String? error;
  final String? message;

  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.message,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse<T>(
      success: json['success'] as bool,
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : json['data'] as T?,
      error: json['error'] as String?,
      message: json['message'] as String?,
    );
  }

  @override
  List<Object?> get props => [success, data, error, message];
}

// Authentication
class AuthTokens extends Equatable {
  final String accessToken;
  final String refreshToken;
  final int expiresAt;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: json['expiresAt'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt,
    };
  }

  bool get isExpired {
    // Add 5 minute buffer
    final expirationBuffer = 5 * 60 * 1000;
    return DateTime.now().millisecondsSinceEpoch >= (expiresAt - expirationBuffer);
  }

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresAt];
}

class User extends Equatable {
  final String id;
  final String email;
  final String name;
  final String? avatar;
  final List<String> permissions;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.avatar,
    required this.permissions,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      avatar: json['avatar'] as String?,
      permissions: List<String>.from(json['permissions'] as List),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'avatar': avatar,
      'permissions': permissions,
    };
  }

  @override
  List<Object?> get props => [id, email, name, avatar, permissions];
}

class LoginCredentials extends Equatable {
  final String email;
  final String password;

  const LoginCredentials({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
    };
  }

  @override
  List<Object?> get props => [email, password];
}

// Records
class Record extends Equatable {
  final String id;
  final Map<String, dynamic> fields;
  final String createdTime;
  final String? updatedTime;
  final int? version;

  const Record({
    required this.id,
    required this.fields,
    required this.createdTime,
    this.updatedTime,
    this.version,
  });

  factory Record.fromJson(Map<String, dynamic> json) {
    return Record(
      id: json['id'] as String,
      fields: Map<String, dynamic>.from(json['fields'] as Map),
      createdTime: json['createdTime'] as String,
      updatedTime: json['updatedTime'] as String?,
      version: json['version'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fields': fields,
      'createdTime': createdTime,
      'updatedTime': updatedTime,
      'version': version,
    };
  }

  Record copyWith({
    String? id,
    Map<String, dynamic>? fields,
    String? createdTime,
    String? updatedTime,
    int? version,
  }) {
    return Record(
      id: id ?? this.id,
      fields: fields ?? this.fields,
      createdTime: createdTime ?? this.createdTime,
      updatedTime: updatedTime ?? this.updatedTime,
      version: version ?? this.version,
    );
  }

  @override
  List<Object?> get props => [id, fields, createdTime, updatedTime, version];
}

class RecordCreate extends Equatable {
  final Map<String, dynamic> fields;

  const RecordCreate({required this.fields});

  Map<String, dynamic> toJson() {
    return {'fields': fields};
  }

  @override
  List<Object?> get props => [fields];
}

class RecordUpdate extends Equatable {
  final String id;
  final Map<String, dynamic> fields;

  const RecordUpdate({
    required this.id,
    required this.fields,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fields': fields,
    };
  }

  @override
  List<Object?> get props => [id, fields];
}

class RecordQuery extends Equatable {
  final String? filterByFormula;
  final List<SortOption>? sort;
  final int? maxRecords;
  final int? pageSize;
  final String? offset;
  final String? view;
  final List<String>? fields;

  const RecordQuery({
    this.filterByFormula,
    this.sort,
    this.maxRecords,
    this.pageSize,
    this.offset,
    this.view,
    this.fields,
  });

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    
    if (filterByFormula != null) {
      params['filterByFormula'] = filterByFormula!;
    }
    if (maxRecords != null) {
      params['maxRecords'] = maxRecords.toString();
    }
    if (pageSize != null) {
      params['pageSize'] = pageSize.toString();
    }
    if (offset != null) {
      params['offset'] = offset!;
    }
    if (view != null) {
      params['view'] = view!;
    }
    if (fields != null) {
      params['fields'] = fields!.join(',');
    }
    if (sort != null) {
      for (int i = 0; i < sort!.length; i++) {
        params['sort[$i][field]'] = sort![i].field;
        params['sort[$i][direction]'] = sort![i].direction;
      }
    }
    
    return params;
  }

  @override
  List<Object?> get props => [
        filterByFormula,
        sort,
        maxRecords,
        pageSize,
        offset,
        view,
        fields,
      ];
}

class SortOption extends Equatable {
  final String field;
  final String direction;

  const SortOption({
    required this.field,
    required this.direction,
  });

  @override
  List<Object?> get props => [field, direction];
}

// Tables
class Table extends Equatable {
  final String id;
  final String name;
  final String? description;
  final List<Field> fields;
  final List<View> views;

  const Table({
    required this.id,
    required this.name,
    this.description,
    required this.fields,
    required this.views,
  });

  factory Table.fromJson(Map<String, dynamic> json) {
    return Table(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      fields: (json['fields'] as List)
          .map((field) => Field.fromJson(field as Map<String, dynamic>))
          .toList(),
      views: (json['views'] as List)
          .map((view) => View.fromJson(view as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [id, name, description, fields, views];
}

class Field extends Equatable {
  final String id;
  final String name;
  final String type;
  final Map<String, dynamic>? options;
  final String? description;

  const Field({
    required this.id,
    required this.name,
    required this.type,
    this.options,
    this.description,
  });

  factory Field.fromJson(Map<String, dynamic> json) {
    return Field(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      options: json['options'] as Map<String, dynamic>?,
      description: json['description'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name, type, options, description];
}

class View extends Equatable {
  final String id;
  final String name;
  final String type;

  const View({
    required this.id,
    required this.name,
    required this.type,
  });

  factory View.fromJson(Map<String, dynamic> json) {
    return View(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
    );
  }

  @override
  List<Object?> get props => [id, name, type];
}

// Base
class Base extends Equatable {
  final String id;
  final String name;
  final String permissionLevel;
  final List<Table> tables;

  const Base({
    required this.id,
    required this.name,
    required this.permissionLevel,
    required this.tables,
  });

  factory Base.fromJson(Map<String, dynamic> json) {
    return Base(
      id: json['id'] as String,
      name: json['name'] as String,
      permissionLevel: json['permissionLevel'] as String,
      tables: (json['tables'] as List)
          .map((table) => Table.fromJson(table as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [id, name, permissionLevel, tables];
}

// WebSocket
class WebSocketMessage extends Equatable {
  final String type;
  final Map<String, dynamic> data;
  final int timestamp;

  const WebSocketMessage({
    required this.type,
    required this.data,
    required this.timestamp,
  });

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
      timestamp: json['timestamp'] as int,
    );
  }

  @override
  List<Object?> get props => [type, data, timestamp];
}

// Sync
class SyncOperation extends Equatable {
  final String id;
  final String type;
  final String tableName;
  final String? recordId;
  final Map<String, dynamic> data;
  final int timestamp;
  final String status;
  final int retryCount;

  const SyncOperation({
    required this.id,
    required this.type,
    required this.tableName,
    this.recordId,
    required this.data,
    required this.timestamp,
    required this.status,
    required this.retryCount,
  });

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] as String,
      type: json['type'] as String,
      tableName: json['tableName'] as String,
      recordId: json['recordId'] as String?,
      data: Map<String, dynamic>.from(json['data'] as Map),
      timestamp: json['timestamp'] as int,
      status: json['status'] as String,
      retryCount: json['retryCount'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'tableName': tableName,
      'recordId': recordId,
      'data': data,
      'timestamp': timestamp,
      'status': status,
      'retryCount': retryCount,
    };
  }

  SyncOperation copyWith({
    String? id,
    String? type,
    String? tableName,
    String? recordId,
    Map<String, dynamic>? data,
    int? timestamp,
    String? status,
    int? retryCount,
  }) {
    return SyncOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      tableName: tableName ?? this.tableName,
      recordId: recordId ?? this.recordId,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        tableName,
        recordId,
        data,
        timestamp,
        status,
        retryCount,
      ];
}

// Exceptions
class PyAirtableException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final dynamic details;

  const PyAirtableException(
    this.message, {
    this.code,
    this.statusCode,
    this.details,
  });

  @override
  String toString() => 'PyAirtableException: $message';
}

class NetworkException extends PyAirtableException {
  const NetworkException(String message, {dynamic details})
      : super(message, code: 'NETWORK_ERROR', details: details);
}

class AuthenticationException extends PyAirtableException {
  const AuthenticationException(String message)
      : super(message, code: 'AUTH_ERROR', statusCode: 401);
}

class ValidationException extends PyAirtableException {
  const ValidationException(String message, {dynamic details})
      : super(message, code: 'VALIDATION_ERROR', statusCode: 400, details: details);
}

class NotFoundException extends PyAirtableException {
  const NotFoundException(String resource)
      : super('$resource not found', code: 'NOT_FOUND', statusCode: 404);
}

class PermissionException extends PyAirtableException {
  const PermissionException(String message)
      : super(message, code: 'PERMISSION_DENIED', statusCode: 403);
}

class RateLimitException extends PyAirtableException {
  const RateLimitException({int? retryAfter})
      : super(
          'Rate limit exceeded',
          code: 'RATE_LIMITED',
          statusCode: 429,
          details: {'retryAfter': retryAfter},
        );
}

class ServerException extends PyAirtableException {
  const ServerException(String message, {int statusCode = 500})
      : super(message, code: 'SERVER_ERROR', statusCode: statusCode);
}

class OfflineException extends PyAirtableException {
  const OfflineException(String message)
      : super(message, code: 'OFFLINE_ERROR');
}

class SyncException extends PyAirtableException {
  const SyncException(String message, {dynamic details})
      : super(message, code: 'SYNC_ERROR', details: details);
}

// File Upload
class FileUploadProgress extends Equatable {
  final int loaded;
  final int total;
  final double percentage;

  const FileUploadProgress({
    required this.loaded,
    required this.total,
    required this.percentage,
  });

  @override
  List<Object?> get props => [loaded, total, percentage];
}

class Attachment extends Equatable {
  final String id;
  final String url;
  final String filename;
  final int size;
  final String type;
  final Map<String, dynamic>? thumbnails;

  const Attachment({
    required this.id,
    required this.url,
    required this.filename,
    required this.size,
    required this.type,
    this.thumbnails,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as String,
      url: json['url'] as String,
      filename: json['filename'] as String,
      size: json['size'] as int,
      type: json['type'] as String,
      thumbnails: json['thumbnails'] as Map<String, dynamic>?,
    );
  }

  @override
  List<Object?> get props => [id, url, filename, size, type, thumbnails];
}