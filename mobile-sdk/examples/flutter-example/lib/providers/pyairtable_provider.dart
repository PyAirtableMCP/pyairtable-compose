import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyairtable_sdk/pyairtable_sdk.dart';

// PyAirtable client provider - singleton instance
final pyairtableClientProvider = Provider<PyAirtableClient>((ref) {
  return PyAirtableClient(
    config: const PyAirtableConfig(
      apiKey: 'your-api-key', // Replace with your API key
      baseUrl: 'https://your-pyairtable-instance.com', // Replace with your instance URL
      enableOfflineSync: true,
      enableWebSocket: true,
      enablePushNotifications: true,
    ),
  );
});

// Auth state provider
final authStateProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(pyairtableClientProvider);
  return client.onLogin.map((user) => user);
});

// Network status provider
final networkStatusProvider = StreamProvider<bool>((ref) {
  final client = ref.watch(pyairtableClientProvider);
  return client.onNetworkChange;
});

// Sync status provider
final syncStatusProvider = StreamProvider<SyncEvent>((ref) {
  final client = ref.watch(pyairtableClientProvider);
  return client.onSyncEvent;
});

// Records provider for a specific table
final recordsProvider = StreamProvider.family<List<Record>, RecordsParams>((ref, params) async* {
  final client = ref.watch(pyairtableClientProvider);
  
  // Initial load
  try {
    final result = await client.listRecords(
      params.baseId,
      params.tableId,
      useCache: true,
    );
    yield result.records;
  } catch (error) {
    // Handle error - yield empty list or previous state
    yield [];
  }
  
  // Listen for real-time updates
  await for (final event in client.onRecordEvent) {
    if (event.data['baseId'] == params.baseId && 
        event.data['tableId'] == params.tableId) {
      
      // Re-fetch records after any change
      try {
        final result = await client.listRecords(
          params.baseId,
          params.tableId,
          useCache: true,
        );
        yield result.records;
      } catch (error) {
        // Continue with current state on error
      }
    }
  }
});

// Bases provider
final basesProvider = FutureProvider<List<Base>>((ref) async {
  final client = ref.watch(pyairtableClientProvider);
  return client.getBases();
});

// Tables provider for a specific base
final tablesProvider = FutureProvider.family<List<Table>, String>((ref, baseId) async {
  final client = ref.watch(pyairtableClientProvider);
  return client.getTables(baseId);
});

// Sync statistics provider
final syncStatsProvider = Provider<SyncStats>((ref) {
  final client = ref.watch(pyairtableClientProvider);
  
  return SyncStats(
    isOnline: client.isOnline,
    pendingOperations: client.pendingOperationsCount,
    isWebSocketConnected: client.isWebSocketConnected,
  );
});

// Helper classes
class RecordsParams {
  final String baseId;
  final String tableId;
  final RecordQuery? query;

  const RecordsParams({
    required this.baseId,
    required this.tableId,
    this.query,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordsParams &&
          runtimeType == other.runtimeType &&
          baseId == other.baseId &&
          tableId == other.tableId &&
          query == other.query;

  @override
  int get hashCode => baseId.hashCode ^ tableId.hashCode ^ query.hashCode;
}

class SyncStats {
  final bool isOnline;
  final int pendingOperations;
  final bool isWebSocketConnected;

  const SyncStats({
    required this.isOnline,
    required this.pendingOperations,
    required this.isWebSocketConnected,
  });
}

// Record operations provider
final recordOperationsProvider = Provider<RecordOperations>((ref) {
  final client = ref.watch(pyairtableClientProvider);
  return RecordOperations(client);
});

class RecordOperations {
  final PyAirtableClient _client;

  RecordOperations(this._client);

  Future<Record> createRecord(
    String baseId,
    String tableId,
    Map<String, dynamic> fields,
  ) async {
    return _client.createRecord(
      baseId,
      tableId,
      RecordCreate(fields: fields),
    );
  }

  Future<Record> updateRecord(
    String baseId,
    String tableId,
    String recordId,
    Map<String, dynamic> fields,
  ) async {
    return _client.updateRecord(
      baseId,
      tableId,
      RecordUpdate(id: recordId, fields: fields),
    );
  }

  Future<void> deleteRecord(
    String baseId,
    String tableId,
    String recordId,
  ) async {
    return _client.deleteRecord(baseId, tableId, recordId);
  }

  Future<FileUploadResult> uploadFile(
    String filePath,
    String filename, {
    void Function(FileUploadProgress)? onProgress,
  }) async {
    return _client.uploadFile(filePath, filename, onProgress: onProgress);
  }

  Future<void> sync() async {
    return _client.sync();
  }
}