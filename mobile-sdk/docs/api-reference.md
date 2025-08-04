# PyAirtable Mobile SDK API Reference

Complete API reference for both React Native and Flutter SDKs.

## Table of Contents

1. [Client Configuration](#client-configuration)
2. [Authentication](#authentication)
3. [Base Operations](#base-operations)
4. [Table Operations](#table-operations)
5. [Record Operations](#record-operations)
6. [File Operations](#file-operations)
7. [Formula Operations](#formula-operations)
8. [WebSocket Operations](#websocket-operations)
9. [Offline Operations](#offline-operations)
10. [Notification Operations](#notification-operations)
11. [Error Handling](#error-handling)
12. [Events and Streams](#events-and-streams)

## Client Configuration

### React Native

```typescript
import PyAirtableClient from '@pyairtable/react-native-sdk';

const client = new PyAirtableClient({
  apiKey: string;                    // Required: Your PyAirtable API key
  baseUrl: string;                   // Required: Your PyAirtable instance URL
  timeout?: number;                  // Optional: Request timeout in ms (default: 30000)
  retryAttempts?: number;            // Optional: Number of retry attempts (default: 3)
  retryDelay?: number;               // Optional: Delay between retries in ms (default: 1000)
  enableOfflineSync?: boolean;       // Optional: Enable offline support (default: true)
  enableWebSocket?: boolean;         // Optional: Enable real-time updates (default: true)
  enablePushNotifications?: boolean; // Optional: Enable push notifications (default: false)
});
```

### Flutter

```dart
import 'package:pyairtable_sdk/pyairtable_sdk.dart';

final client = PyAirtableClient(
  config: PyAirtableConfig(
    apiKey: 'your-api-key',                    // Required
    baseUrl: 'https://your-instance.com',     // Required
    timeout: 30000,                           // Optional
    retryAttempts: 3,                         // Optional
    retryDelay: 1000,                         // Optional
    enableOfflineSync: true,                  // Optional
    enableWebSocket: true,                    // Optional
    enablePushNotifications: false,           // Optional
  ),
);
```

## Authentication

### Login

**React Native:**
```typescript
await client.login({
  email: string;
  password: string;
});
```

**Flutter:**
```dart
await client.login(LoginCredentials(
  email: 'user@example.com',
  password: 'password123',
));
```

### Logout

**React Native:**
```typescript
await client.logout();
```

**Flutter:**
```dart
await client.logout();
```

### Get Current User

**React Native:**
```typescript
const user = client.getCurrentUser();
// Returns: User | null
```

**Flutter:**
```dart
final user = client.currentUser;
// Returns: User?
```

### Check Authentication Status

**React Native:**
```typescript
const isAuthenticated = client.isAuthenticated();
// Returns: boolean
```

**Flutter:**
```dart
final isAuthenticated = client.isAuthenticated;
// Returns: bool
```

## Base Operations

### Get All Bases

**React Native:**
```typescript
const bases = await client.getBases();
// Returns: Promise<Base[]>
```

**Flutter:**
```dart
final bases = await client.getBases();
// Returns: Future<List<Base>>
```

### Get Specific Base

**React Native:**
```typescript
const base = await client.getBase('baseId');
// Returns: Promise<Base>
```

**Flutter:**
```dart
final base = await client.getBase('baseId');
// Returns: Future<Base>
```

## Table Operations

### Get Tables in Base

**React Native:**
```typescript
const tables = await client.getTables('baseId');
// Returns: Promise<Table[]>
```

**Flutter:**
```dart
final tables = await client.getTables('baseId');
// Returns: Future<List<Table>>
```

### Get Specific Table

**React Native:**
```typescript
const table = await client.getTable('baseId', 'tableId');
// Returns: Promise<Table>
```

**Flutter:**
```dart
final table = await client.getTable('baseId', 'tableId');
// Returns: Future<Table>
```

## Record Operations

### List Records

**React Native:**
```typescript
const result = await client.listRecords(
  'baseId',
  'tableId',
  {
    filterByFormula?: string;
    sort?: Array<{
      field: string;
      direction: 'asc' | 'desc';
    }>;
    maxRecords?: number;
    pageSize?: number;
    offset?: string;
    view?: string;
    fields?: string[];
  },
  useCache: boolean = true
);
// Returns: Promise<{ records: Record[]; offset?: string }>
```

**Flutter:**
```dart
final result = await client.listRecords(
  'baseId',
  'tableId',
  query: RecordQuery(
    filterByFormula: 'Status = "Active"',
    sort: [SortOption(field: 'Name', direction: 'asc')],
    maxRecords: 100,
    fields: ['Name', 'Status'],
  ),
  useCache: true,
);
// Returns: Future<RecordsResult>
```

### Get Single Record

**React Native:**
```typescript
const record = await client.getRecord('baseId', 'tableId', 'recordId');
// Returns: Promise<Record>
```

**Flutter:**
```dart
final record = await client.getRecord('baseId', 'tableId', 'recordId');
// Returns: Future<Record>
```

### Create Record

**React Native:**
```typescript
const record = await client.createRecord('baseId', 'tableId', {
  fields: {
    Name: 'New Record',
    Status: 'Active',
  },
});
// Returns: Promise<Record>
```

**Flutter:**
```dart
final record = await client.createRecord(
  'baseId',
  'tableId',
  RecordCreate(fields: {
    'Name': 'New Record',
    'Status': 'Active',
  }),
);
// Returns: Future<Record>
```

### Create Multiple Records

**React Native:**
```typescript
const records = await client.createRecords('baseId', 'tableId', [
  { fields: { Name: 'Record 1' } },
  { fields: { Name: 'Record 2' } },
]);
// Returns: Promise<Record[]>
```

**Flutter:**
```dart
final records = await client.createRecords('baseId', 'tableId', [
  RecordCreate(fields: {'Name': 'Record 1'}),
  RecordCreate(fields: {'Name': 'Record 2'}),
]);
// Returns: Future<List<Record>>
```

### Update Record

**React Native:**
```typescript
const record = await client.updateRecord('baseId', 'tableId', {
  id: 'recordId',
  fields: {
    Status: 'Completed',
  },
});
// Returns: Promise<Record>
```

**Flutter:**
```dart
final record = await client.updateRecord(
  'baseId',
  'tableId',
  RecordUpdate(
    id: 'recordId',
    fields: {'Status': 'Completed'},
  ),
);
// Returns: Future<Record>
```

### Delete Record

**React Native:**
```typescript
await client.deleteRecord('baseId', 'tableId', 'recordId');
// Returns: Promise<void>
```

**Flutter:**
```dart
await client.deleteRecord('baseId', 'tableId', 'recordId');
// Returns: Future<void>
```

## File Operations

### Upload File

**React Native:**
```typescript
const result = await client.uploadFile(
  file: File | Blob,
  filename: string,
  onProgress?: (progress: FileUploadProgress) => void
);
// Returns: Promise<{ id: string; url: string }>
```

**Flutter:**
```dart
final result = await client.uploadFile(
  '/path/to/file.jpg',
  'filename.jpg',
  onProgress: (progress) {
    print('Upload progress: ${progress.percentage}%');
  },
);
// Returns: Future<FileUploadResult>
```

### Download File

**React Native:**
```typescript
const blob = await client.downloadFile('fileId');
// Returns: Promise<Blob>
```

**Flutter:**
```dart
final bytes = await client.downloadFile('fileId');
// Returns: Future<List<int>>
```

## Formula Operations

### Evaluate Formula

**React Native:**
```typescript
const result = await client.evaluateFormula(
  'baseId',
  'tableId',
  'recordId',
  'CONCATENATE({Name}, " - ", {Status})'
);
// Returns: Promise<FormulaResult>
```

**Flutter:**
```dart
final result = await client.evaluateFormula(
  'baseId',
  'tableId',
  'recordId',
  'CONCATENATE({Name}, " - ", {Status})',
);
// Returns: Future<FormulaResult>
```

## WebSocket Operations

### Subscribe to Table Updates

**React Native:**
```typescript
client.subscribeToTable('baseId', 'tableId');
```

**Flutter:**
```dart
client.subscribeToTable('baseId', 'tableId');
```

### Unsubscribe from Table Updates

**React Native:**
```typescript
client.unsubscribeFromTable('baseId', 'tableId');
```

**Flutter:**
```dart
client.unsubscribeFromTable('baseId', 'tableId');
```

### Check WebSocket Connection

**React Native:**
```typescript
const isConnected = client.isWebSocketConnected();
// Returns: boolean
```

**Flutter:**
```dart
final isConnected = client.isWebSocketConnected;
// Returns: bool
```

## Offline Operations

### Force Sync

**React Native:**
```typescript
await client.sync();
// Returns: Promise<void>
```

**Flutter:**
```dart
await client.sync();
// Returns: Future<void>
```

### Get Pending Operations Count

**React Native:**
```typescript
const count = client.getPendingOperationsCount();
// Returns: number
```

**Flutter:**
```dart
final count = client.pendingOperationsCount;
// Returns: int
```

### Check Online Status

**React Native:**
```typescript
const isOnline = client.isOnline();
// Returns: boolean
```

**Flutter:**
```dart
final isOnline = client.isOnline;
// Returns: bool
```

## Notification Operations

### Show Notification

**React Native:**
```typescript
client.showNotification('Title', 'Body', { key: 'value' });
```

**Flutter:**
```dart
await client.showNotification('Title', 'Body', data: {'key': 'value'});
```

### Set Badge Number (iOS)

**React Native:**
```typescript
client.setBadgeNumber(5);
```

**Flutter:**
```dart
// Handled automatically by the notification manager
```

## Error Handling

### Error Types

**React Native:**
```typescript
import {
  PyAirtableSDKError,
  NetworkError,
  AuthenticationError,
  ValidationError,
  NotFoundError,
  PermissionError,
  RateLimitError,
  ServerError,
  OfflineError,
  SyncError,
} from '@pyairtable/react-native-sdk';
```

**Flutter:**
```dart
// Exception types
PyAirtableException
NetworkException
AuthenticationException
ValidationException
NotFoundException
PermissionException
RateLimitException
ServerException
OfflineException
SyncException
```

### Error Handling Example

**React Native:**
```typescript
try {
  await client.createRecord(baseId, tableId, record);
} catch (error) {
  if (error instanceof AuthenticationError) {
    // Handle auth errors
  } else if (error instanceof NetworkError) {
    // Handle network errors
  } else if (error instanceof ValidationError) {
    // Handle validation errors
    console.log('Validation details:', error.details);
  }
}
```

**Flutter:**
```dart
try {
  await client.createRecord(baseId, tableId, record);
} catch (error) {
  if (error is AuthenticationException) {
    // Handle auth errors
  } else if (error is NetworkException) {
    // Handle network errors
  } else if (error is ValidationException) {
    // Handle validation errors
    print('Validation details: ${error.details}');
  }
}
```

## Events and Streams

### React Native Events

```typescript
// Authentication events
client.on('login', (user: User) => { });
client.on('logout', () => { });

// Network events
client.on('online', () => { });
client.on('offline', () => { });

// Sync events
client.on('sync:start', () => { });
client.on('sync:complete', () => { });
client.on('sync:error', (error: PyAirtableError) => { });

// Record events (real-time)
client.on('record:created', (data: any) => { });
client.on('record:updated', (data: any) => { });
client.on('record:deleted', (data: any) => { });

// WebSocket events
client.on('websocket:connect', () => { });
client.on('websocket:disconnect', () => { });
client.on('websocket:error', (error: PyAirtableError) => { });
```

### Flutter Streams

```dart
// Authentication stream
client.onLogin.listen((user) => { });
client.onLogout.listen((_) => { });

// Network stream
client.onNetworkChange.listen((isOnline) => { });

// Sync streams
client.onSyncEvent.listen((event) => {
  switch (event.type) {
    case 'start':
      // Sync started
      break;
    case 'complete':
      // Sync completed
      break;
    case 'error':
      // Sync error
      break;
  }
});

// Record streams (real-time)
client.onRecordEvent.listen((event) => {
  switch (event.type) {
    case 'created':
      // Record created
      break;
    case 'updated':
      // Record updated
      break;
    case 'deleted':
      // Record deleted
      break;
  }
});

// WebSocket streams
client.onWebSocketEvent.listen((event) => { });
```

## Data Types

### User

```typescript
// React Native
interface User {
  id: string;
  email: string;
  name: string;
  avatar?: string;
  permissions: string[];
}
```

```dart
// Flutter
class User {
  final String id;
  final String email;
  final String name;
  final String? avatar;
  final List<String> permissions;
}
```

### Record

```typescript
// React Native
interface Record {
  id: string;
  fields: { [key: string]: any };
  createdTime: string;
  updatedTime?: string;
  version?: number;
}
```

```dart
// Flutter
class Record {
  final String id;
  final Map<String, dynamic> fields;
  final String createdTime;
  final String? updatedTime;
  final int? version;
}
```

### Base

```typescript
// React Native
interface Base {
  id: string;
  name: string;
  permissionLevel: 'none' | 'read' | 'comment' | 'edit' | 'create';
  tables: Table[];
}
```

```dart
// Flutter
class Base {
  final String id;
  final String name;
  final String permissionLevel;
  final List<Table> tables;
}
```

### Table

```typescript
// React Native
interface Table {
  id: string;
  name: string;
  description?: string;
  fields: Field[];
  views: View[];
}
```

```dart
// Flutter
class Table {
  final String id;
  final String name;
  final String? description;
  final List<Field> fields;
  final List<View> views;
}
```

This API reference provides comprehensive documentation for both React Native and Flutter implementations of the PyAirtable Mobile SDK. Both SDKs maintain feature parity while following platform-specific conventions and patterns.