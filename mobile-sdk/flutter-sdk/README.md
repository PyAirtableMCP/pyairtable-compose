# PyAirtable Flutter SDK

A comprehensive Flutter SDK for PyAirtable with offline capabilities, real-time updates, and native platform integration.

## Features

- **Full Dart/Flutter Support**: Native Dart implementation with Flutter integration
- **Authentication**: JWT-based authentication with automatic token refresh
- **Real-time Updates**: WebSocket support for live data synchronization  
- **Offline Support**: Local storage with automatic sync when online
- **CRUD Operations**: Complete record management with optimistic updates
- **File Management**: Upload/download with progress tracking
- **Push Notifications**: Firebase Cloud Messaging integration
- **Error Handling**: Comprehensive error handling with retry logic
- **Reactive Streams**: RxDart-powered event streams for real-time updates

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  pyairtable_sdk: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Setup

### Android Setup

Add to `android/app/build.gradle`:

```gradle
android {
    compileSdkVersion 34
    
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
    }
}
```

### iOS Setup

Add to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### Firebase Setup (Optional)

For push notifications, follow the [Firebase setup guide](https://firebase.flutter.dev/docs/overview/).

## Quick Start

### Initialize the Client

```dart
import 'package:pyairtable_sdk/pyairtable_sdk.dart';

final client = PyAirtableClient(
  config: PyAirtableConfig(
    apiKey: 'your-api-key',
    baseUrl: 'https://your-pyairtable-instance.com',
    enableOfflineSync: true,
    enableWebSocket: true,
    enablePushNotifications: true,
  ),
);

// Initialize the client
await client.initialize();
```

### Authentication

```dart
class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    
    try {
      final user = await client.login(LoginCredentials(
        email: _emailController.text,
        password: _passwordController.text,
      ));
      
      // Navigate to main app
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainApp(user: user)),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $error')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _login,
              child: _isLoading
                  ? CircularProgressIndicator()
                  : Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Working with Records

```dart
class RecordsPage extends StatefulWidget {
  final String baseId;
  final String tableId;

  RecordsPage({required this.baseId, required this.tableId});

  @override
  _RecordsPageState createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  List<Record> _records = [];
  bool _isLoading = true;
  StreamSubscription? _recordSubscription;

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _setupRealTimeUpdates();
  }

  Future<void> _loadRecords() async {
    try {
      final result = await client.listRecords(
        widget.baseId,
        widget.tableId,
        useCache: true,
      );
      
      setState(() {
        _records = result.records;
        _isLoading = false;
      });
    } catch (error) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load records: $error')),
      );
    }
  }

  void _setupRealTimeUpdates() {
    // Subscribe to table updates
    client.subscribeToTable(widget.baseId, widget.tableId);

    // Listen for record events
    _recordSubscription = client.onRecordEvent.listen((event) {
      if (event.data['baseId'] == widget.baseId && 
          event.data['tableId'] == widget.tableId) {
        _handleRecordEvent(event);
      }
    });
  }

  void _handleRecordEvent(RecordEvent event) {
    setState(() {
      switch (event.type) {
        case 'created':
          final record = Record.fromJson(event.data['record']);
          _records.add(record);
          break;
        case 'updated':
          final record = Record.fromJson(event.data['record']);
          final index = _records.indexWhere((r) => r.id == record.id);
          if (index >= 0) {
            _records[index] = record;
          }
          break;
        case 'deleted':
          final recordId = event.data['recordId'] as String;
          _records.removeWhere((r) => r.id == recordId);
          break;
      }
    });
  }

  Future<void> _createRecord() async {
    try {
      final record = await client.createRecord(
        widget.baseId,
        widget.tableId,
        RecordCreate(fields: {
          'Name': 'New Record',
          'Status': 'Active',
        }),
      );
      
      setState(() => _records.add(record));
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create record: $error')),
      );
    }
  }

  Future<void> _updateRecord(Record record) async {
    try {
      final updatedRecord = await client.updateRecord(
        widget.baseId,
        widget.tableId,
        RecordUpdate(
          id: record.id,
          fields: {...record.fields, 'Status': 'Completed'},
        ),
      );
      
      setState(() {
        final index = _records.indexWhere((r) => r.id == record.id);
        if (index >= 0) {
          _records[index] = updatedRecord;
        }
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update record: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Records'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadRecords,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final record = _records[index];
                return ListTile(
                  title: Text(record.fields['Name']?.toString() ?? 'Unnamed'),
                  subtitle: Text(record.fields['Status']?.toString() ?? ''),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'update',
                        child: Text('Update'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                    onSelected: (value) async {
                      if (value == 'update') {
                        await _updateRecord(record);
                      } else if (value == 'delete') {
                        await client.deleteRecord(
                          widget.baseId,
                          widget.tableId,
                          record.id,
                        );
                        setState(() {
                          _records.removeWhere((r) => r.id == record.id);
                        });
                      }
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createRecord,
        child: Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    client.unsubscribeFromTable(widget.baseId, widget.tableId);
    _recordSubscription?.cancel();
    super.dispose();
  }
}
```

### Sync Status Widget

```dart
class SyncStatusWidget extends StatefulWidget {
  @override
  _SyncStatusWidgetState createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  bool _isOnline = true;
  bool _isSyncing = false;
  int _pendingOperations = 0;
  StreamSubscription? _networkSubscription;
  StreamSubscription? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _updateStatus();
  }

  void _setupListeners() {
    _networkSubscription = client.onNetworkChange.listen((isOnline) {
      setState(() => _isOnline = isOnline);
    });

    _syncSubscription = client.onSyncEvent.listen((event) {
      setState(() {
        switch (event.type) {
          case 'start':
            _isSyncing = true;
            break;
          case 'complete':
          case 'error':
            _isSyncing = false;
            break;
        }
      });
      _updateStatus();
    });
  }

  void _updateStatus() {
    setState(() {
      _pendingOperations = client.pendingOperationsCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: _isOnline ? Colors.green : Colors.red,
                ),
                SizedBox(width: 8),
                Text(_isOnline ? 'Online' : 'Offline'),
              ],
            ),
            SizedBox(height: 8),
            Text('Pending operations: $_pendingOperations'),
            if (_isSyncing) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Syncing...'),
                ],
              ),
            ],
            if (_pendingOperations > 0 && _isOnline) ...[
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => client.sync(),
                child: Text('Force Sync'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }
}
```

### File Upload

```dart
class FileUploadWidget extends StatefulWidget {
  @override
  _FileUploadWidgetState createState() => _FileUploadWidgetState();
}

class _FileUploadWidgetState extends State<FileUploadWidget> {
  double _uploadProgress = 0.0;
  bool _isUploading = false;

  Future<void> _pickAndUploadFile() async {
    // Use file_picker package to pick file
    final result = await FilePicker.platform.pickFiles();
    
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      try {
        final uploadResult = await client.uploadFile(
          file.path!,
          file.name,
          onProgress: (progress) {
            setState(() {
              _uploadProgress = progress.percentage / 100;
            });
          },
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File uploaded successfully')),
        );
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $error')),
        );
      } finally {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _isUploading ? null : _pickAndUploadFile,
          child: Text('Upload File'),
        ),
        if (_isUploading) ...[
          SizedBox(height: 16),
          LinearProgressIndicator(value: _uploadProgress),
          SizedBox(height: 8),
          Text('${(_uploadProgress * 100).toInt()}%'),
        ],
      ],
    );
  }
}
```

## API Reference

### PyAirtableClient

The main client class that provides access to all PyAirtable functionality.

#### Configuration

```dart
PyAirtableConfig(
  apiKey: 'your-api-key',
  baseUrl: 'https://your-instance.com',
  timeout: 30000,
  retryAttempts: 3,
  retryDelay: 1000,
  enableOfflineSync: true,
  enableWebSocket: true,
  enablePushNotifications: false,
)
```

#### Methods

- `initialize()`: Initialize the client
- `login(LoginCredentials)`: Authenticate user
- `logout()`: Logout user
- `getBases()`: Get all accessible bases
- `getTables(baseId)`: Get tables in a base
- `listRecords(baseId, tableId, {query, useCache})`: Get records from a table
- `createRecord(baseId, tableId, record)`: Create a new record
- `updateRecord(baseId, tableId, record)`: Update an existing record
- `deleteRecord(baseId, tableId, recordId)`: Delete a record
- `uploadFile(filePath, filename, {onProgress})`: Upload a file
- `sync()`: Force synchronization with server

#### Event Streams

- `onLogin`: User authentication events
- `onLogout`: User logout events
- `onNetworkChange`: Network connectivity changes
- `onSyncEvent`: Sync status updates
- `onRecordEvent`: Real-time record updates
- `onWebSocketEvent`: WebSocket connection events

## Error Handling

The SDK provides comprehensive error handling with specific exception types:

```dart
try {
  await client.createRecord(baseId, tableId, record);
} catch (error) {
  if (error is AuthenticationException) {
    // Handle auth errors
    print('Please login again');
  } else if (error is NetworkException) {
    // Handle network errors
    print('Check your internet connection');
  } else if (error is ValidationException) {
    // Handle validation errors
    print('Invalid data: ${error.details}');
  }
}
```

## Performance Tips

1. **Use caching**: Enable `useCache: true` for frequently accessed data
2. **Batch operations**: Use `createRecords` and `updateRecords` for bulk operations
3. **Optimize queries**: Use specific field selections and filters
4. **Manage subscriptions**: Unsubscribe from tables when not needed
5. **Handle offline gracefully**: Design UI to work with cached data

## License

MIT License - see [LICENSE](./LICENSE) file for details.