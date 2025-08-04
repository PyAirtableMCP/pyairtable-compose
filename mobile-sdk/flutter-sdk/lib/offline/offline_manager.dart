import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../types/types.dart';
import '../utils/constants.dart';
import '../utils/retry.dart';

class OfflineManagerConfig {
  final int syncInterval;
  final int maxRetryAttempts;
  final bool enableOptimisticUpdates;
  final bool enableBackgroundSync;

  const OfflineManagerConfig({
    this.syncInterval = SyncIntervals.normal,
    this.maxRetryAttempts = 3,
    this.enableOptimisticUpdates = true,
    this.enableBackgroundSync = true,
  });
}

class OfflineManager {
  final ApiClient apiClient;
  final OfflineManagerConfig config;
  final Connectivity _connectivity;
  final Uuid _uuid;
  
  Timer? _syncTimer;
  bool _isOnline = true;
  bool _isSyncing = false;
  
  Map<String, List<Record>> _cachedTables = {};
  List<SyncOperation> _pendingOperations = [];
  int _lastSync = 0;
  
  // Event streams
  final _networkController = StreamController<bool>.broadcast();
  final _syncStartController = StreamController<void>.broadcast();
  final _syncCompleteController = StreamController<void>.broadcast();
  final _syncErrorController = StreamController<PyAirtableException>.broadcast();
  
  Stream<bool> get onNetworkChange => _networkController.stream;
  Stream<void> get onSyncStart => _syncStartController.stream;
  Stream<void> get onSyncComplete => _syncCompleteController.stream;
  Stream<PyAirtableException> get onSyncError => _syncErrorController.stream;

  OfflineManager({
    required this.apiClient,
    required this.config,
  }) : _connectivity = Connectivity(),
       _uuid = const Uuid();

  Future<void> initialize() async {
    await _loadOfflineData();
    _setupNetworkListener();
    
    if (config.enableBackgroundSync) {
      _startSyncTimer();
    }
  }

  void _setupNetworkListener() {
    _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;
      
      _networkController.add(_isOnline);
      
      // When coming back online, trigger sync
      if (!wasOnline && _isOnline) {
        _debouncedSync();
      }
    });
  }

  Future<List<Record>> getCachedRecords(String baseId, String tableId) async {
    final tableKey = '$baseId:$tableId';
    return _cachedTables[tableKey] ?? [];
  }

  Future<void> cacheRecords(String baseId, String tableId, List<Record> records) async {
    final tableKey = '$baseId:$tableId';
    _cachedTables[tableKey] = records;
    await _saveOfflineData();
  }

  Future<Record> createRecord(String baseId, String tableId, RecordCreate record) async {
    final operation = SyncOperation(
      id: _uuid.v4(),
      type: 'create',
      tableName: '$baseId:$tableId',
      data: record.toJson(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'pending',
      retryCount: 0,
    );

    // If online, try immediate sync
    if (_isOnline) {
      try {
        final result = await apiClient.createRecord(baseId, tableId, record);
        await _updateRecordInCache(baseId, tableId, result);
        return result;
      } catch (error) {
        // If failed and optimistic updates enabled, queue for later
        if (config.enableOptimisticUpdates) {
          return _createOptimisticRecord(baseId, tableId, record, operation);
        }
        rethrow;
      }
    }

    // Offline: create optimistic record and queue operation
    if (config.enableOptimisticUpdates) {
      return _createOptimisticRecord(baseId, tableId, record, operation);
    }

    throw const SyncException('Cannot create record while offline');
  }

  Future<Record> updateRecord(String baseId, String tableId, RecordUpdate record) async {
    final operation = SyncOperation(
      id: _uuid.v4(),
      type: 'update',
      tableName: '$baseId:$tableId',
      recordId: record.id,
      data: record.toJson(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'pending',
      retryCount: 0,
    );

    // If online, try immediate sync
    if (_isOnline) {
      try {
        final result = await apiClient.updateRecord(baseId, tableId, record);
        await _updateRecordInCache(baseId, tableId, result);
        return result;
      } catch (error) {
        // If failed and optimistic updates enabled, queue for later
        if (config.enableOptimisticUpdates) {
          return _updateOptimisticRecord(baseId, tableId, record, operation);
        }
        rethrow;
      }
    }

    // Offline: create optimistic update and queue operation
    if (config.enableOptimisticUpdates) {
      return _updateOptimisticRecord(baseId, tableId, record, operation);
    }

    throw const SyncException('Cannot update record while offline');
  }

  Future<void> deleteRecord(String baseId, String tableId, String recordId) async {
    final operation = SyncOperation(
      id: _uuid.v4(),
      type: 'delete',
      tableName: '$baseId:$tableId',
      recordId: recordId,
      data: {'id': recordId},
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'pending',
      retryCount: 0,
    );

    // If online, try immediate sync
    if (_isOnline) {
      try {
        await apiClient.deleteRecord(baseId, tableId, recordId);
        await _removeRecordFromCache(baseId, tableId, recordId);
        return;
      } catch (error) {
        // If failed and optimistic updates enabled, queue for later
        if (config.enableOptimisticUpdates) {
          await _deleteOptimisticRecord(baseId, tableId, recordId, operation);
          return;
        }
        rethrow;
      }
    }

    // Offline: create optimistic delete and queue operation
    if (config.enableOptimisticUpdates) {
      await _deleteOptimisticRecord(baseId, tableId, recordId, operation);
      return;
    }

    throw const SyncException('Cannot delete record while offline');
  }

  Future<void> sync() async {
    if (_isSyncing || !_isOnline) return;

    _isSyncing = true;
    _syncStartController.add(null);

    try {
      await _processPendingOperations();
      _lastSync = DateTime.now().millisecondsSinceEpoch;
      await _saveOfflineData();
      
      _syncCompleteController.add(null);
    } catch (error) {
      final exception = error is PyAirtableException
          ? error
          : PyAirtableException(error.toString());
      _syncErrorController.add(exception);
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  int get pendingOperationsCount => _pendingOperations.length;

  List<SyncOperation> get pendingOperations => List.unmodifiable(_pendingOperations);

  Future<void> clearCache() async {
    _cachedTables.clear();
    _pendingOperations.clear();
    _lastSync = 0;
    await _saveOfflineData();
  }

  // Private methods

  Future<Record> _createOptimisticRecord(
    String baseId,
    String tableId,
    RecordCreate record,
    SyncOperation operation,
  ) async {
    final optimisticRecord = Record(
      id: 'temp_${_uuid.v4()}',
      fields: record.fields,
      createdTime: DateTime.now().toIso8601String(),
      version: 0,
    );

    await _updateRecordInCache(baseId, tableId, optimisticRecord);
    _pendingOperations.add(operation);
    await _saveOfflineData();

    return optimisticRecord;
  }

  Future<Record> _updateOptimisticRecord(
    String baseId,
    String tableId,
    RecordUpdate record,
    SyncOperation operation,
  ) async {
    final existing = await _getRecordFromCache(baseId, tableId, record.id);
    
    final updatedRecord = Record(
      id: record.id,
      fields: record.fields,
      createdTime: existing?.createdTime ?? DateTime.now().toIso8601String(),
      updatedTime: DateTime.now().toIso8601String(),
      version: (existing?.version ?? 0) + 1,
    );

    await _updateRecordInCache(baseId, tableId, updatedRecord);
    _pendingOperations.add(operation);
    await _saveOfflineData();

    return updatedRecord;
  }

  Future<void> _deleteOptimisticRecord(
    String baseId,
    String tableId,
    String recordId,
    SyncOperation operation,
  ) async {
    await _removeRecordFromCache(baseId, tableId, recordId);
    _pendingOperations.add(operation);
    await _saveOfflineData();
  }

  Future<void> _processPendingOperations() async {
    final operations = List<SyncOperation>.from(_pendingOperations);
    
    for (final operation in operations) {
      try {
        final updatedOperation = operation.copyWith(status: 'syncing');
        await _processOperation(updatedOperation);
        
        // Remove from pending operations
        _pendingOperations.removeWhere((op) => op.id == operation.id);
      } catch (error) {
        final updatedOperation = operation.copyWith(
          status: 'failed',
          retryCount: operation.retryCount + 1,
        );
        
        if (updatedOperation.retryCount >= config.maxRetryAttempts) {
          // Remove failed operation after max retries
          _pendingOperations.removeWhere((op) => op.id == operation.id);
        } else {
          // Update operation with new retry count
          final index = _pendingOperations.indexWhere((op) => op.id == operation.id);
          if (index >= 0) {
            _pendingOperations[index] = updatedOperation;
          }
        }
      }
    }
  }

  Future<void> _processOperation(SyncOperation operation) async {
    final parts = operation.tableName.split(':');
    final baseId = parts[0];
    final tableId = parts[1];
    
    switch (operation.type) {
      case 'create':
        final recordCreate = RecordCreate(fields: operation.data['fields']);
        await apiClient.createRecord(baseId, tableId, recordCreate);
        break;
        
      case 'update':
        final recordUpdate = RecordUpdate(
          id: operation.recordId!,
          fields: operation.data['fields'],
        );
        await apiClient.updateRecord(baseId, tableId, recordUpdate);
        break;
        
      case 'delete':
        await apiClient.deleteRecord(baseId, tableId, operation.recordId!);
        break;
    }
  }

  Future<void> _updateRecordInCache(String baseId, String tableId, Record record) async {
    final tableKey = '$baseId:$tableId';
    final records = _cachedTables[tableKey] ?? <Record>[];
    
    final existingIndex = records.indexWhere((r) => r.id == record.id);
    if (existingIndex >= 0) {
      records[existingIndex] = record;
    } else {
      records.add(record);
    }
    
    _cachedTables[tableKey] = records;
    await _saveOfflineData();
  }

  Future<Record?> _getRecordFromCache(String baseId, String tableId, String recordId) async {
    final tableKey = '$baseId:$tableId';
    final records = _cachedTables[tableKey] ?? <Record>[];
    try {
      return records.firstWhere((r) => r.id == recordId);
    } catch (e) {
      return null;
    }
  }

  Future<void> _removeRecordFromCache(String baseId, String tableId, String recordId) async {
    final tableKey = '$baseId:$tableId';
    final records = _cachedTables[tableKey] ?? <Record>[];
    
    records.removeWhere((r) => r.id == recordId);
    _cachedTables[tableKey] = records;
    await _saveOfflineData();
  }

  Future<void> _loadOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(StorageKeys.offlineData);
      
      if (data != null) {
        final jsonData = jsonDecode(data) as Map<String, dynamic>;
        
        // Load cached tables
        final tablesData = jsonData['tables'] as Map<String, dynamic>? ?? {};
        _cachedTables = tablesData.map((key, value) => MapEntry(
          key,
          (value as List).map((record) => Record.fromJson(record)).toList(),
        ));
        
        // Load pending operations
        final operationsData = jsonData['pendingOperations'] as List? ?? [];
        _pendingOperations = operationsData
            .map((op) => SyncOperation.fromJson(op))
            .toList();
        
        _lastSync = jsonData['lastSync'] as int? ?? 0;
      }
    } catch (error) {
      print('Failed to load offline data: $error');
    }
  }

  Future<void> _saveOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final data = {
        'tables': _cachedTables.map((key, value) =>
            MapEntry(key, value.map((record) => record.toJson()).toList())),
        'pendingOperations': _pendingOperations.map((op) => op.toJson()).toList(),
        'lastSync': _lastSync,
      };
      
      await prefs.setString(StorageKeys.offlineData, jsonEncode(data));
    } catch (error) {
      print('Failed to save offline data: $error');
    }
  }

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(
      Duration(milliseconds: config.syncInterval),
      (_) {
        if (_isOnline && !_isSyncing && _pendingOperations.isNotEmpty) {
          _debouncedSync();
        }
      },
    );
  }

  late final Debouncer _syncDebouncer = Debouncer(milliseconds: 1000);
  
  void _debouncedSync() {
    _syncDebouncer.run(() {
      sync().catchError((error) {
        print('Background sync failed: $error');
      });
    });
  }

  Future<void> dispose() async {
    _syncTimer?.cancel();
    _syncDebouncer.dispose();
    
    await _networkController.close();
    await _syncStartController.close();
    await _syncCompleteController.close();
    await _syncErrorController.close();
  }
}