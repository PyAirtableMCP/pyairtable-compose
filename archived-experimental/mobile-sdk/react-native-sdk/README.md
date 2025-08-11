# PyAirtable React Native SDK

A comprehensive React Native SDK for PyAirtable with TypeScript support, offline capabilities, and real-time updates.

## Features

- **Full TypeScript Support**: Complete type definitions for all APIs
- **Authentication**: JWT-based authentication with automatic token refresh
- **Real-time Updates**: WebSocket support for live data synchronization
- **Offline Support**: Local storage with automatic sync when online
- **CRUD Operations**: Complete record management with optimistic updates
- **React Hooks**: Pre-built hooks for common operations
- **File Management**: Upload/download with progress tracking
- **Push Notifications**: Native notification support
- **Error Handling**: Comprehensive error handling with retry logic

## Installation

```bash
npm install @pyairtable/react-native-sdk
```

### iOS Setup

Add to `ios/Podfile`:

```ruby
pod 'RNCAsyncStorage', :path => '../node_modules/@react-native-async-storage/async-storage'
pod 'react-native-netinfo', :path => '../node_modules/@react-native-community/netinfo'
pod 'RNEncryptedStorage', :path => '../node_modules/react-native-encrypted-storage'
```

### Android Setup

Add to `android/settings.gradle`:

```gradle
include ':@react-native-async-storage_async-storage'
project(':@react-native-async-storage_async-storage').projectDir = new File(rootProject.projectDir, '../node_modules/@react-native-async-storage/async-storage/android')

include ':@react-native-community_netinfo'
project(':@react-native-community_netinfo').projectDir = new File(rootProject.projectDir, '../node_modules/@react-native-community/netinfo/android')
```

## Quick Start

### Initialize the Client

```typescript
import PyAirtableClient from '@pyairtable/react-native-sdk';

const client = new PyAirtableClient({
  apiKey: 'your-api-key',
  baseUrl: 'https://your-pyairtable-instance.com',
  enableOfflineSync: true,
  enableWebSocket: true,
  enablePushNotifications: true,
});

// Initialize the client
await client.initialize();
```

### Authentication

```typescript
import { useAuth } from '@pyairtable/react-native-sdk';

function LoginScreen() {
  const { user, isAuthenticated, loading, login, logout } = useAuth(client);

  const handleLogin = async () => {
    try {
      await login({
        email: 'user@example.com',
        password: 'password123',
      });
    } catch (error) {
      console.error('Login failed:', error);
    }
  };

  if (isAuthenticated) {
    return <MainApp user={user} onLogout={logout} />;
  }

  return (
    <View>
      <Button title="Login" onPress={handleLogin} disabled={loading} />
    </View>
  );
}
```

### Working with Records

```typescript
import { useRecords } from '@pyairtable/react-native-sdk';

function RecordsScreen() {
  const { records, loading, error, refresh, create, update, delete: deleteRecord } = useRecords(client, {
    baseId: 'your-base-id',
    tableId: 'your-table-id',
    enableRealtime: true,
  });

  const handleCreate = async () => {
    try {
      await create({
        fields: {
          Name: 'New Record',
          Status: 'Active',
        },
      });
    } catch (error) {
      console.error('Create failed:', error);
    }
  };

  const handleUpdate = async (recordId: string) => {
    try {
      await update({
        id: recordId,
        fields: {
          Status: 'Completed',
        },
      });
    } catch (error) {
      console.error('Update failed:', error);
    }
  };

  if (loading) return <Loading />;
  if (error) return <Error error={error} onRetry={refresh} />;

  return (
    <FlatList
      data={records}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => (
        <RecordItem
          record={item}
          onUpdate={() => handleUpdate(item.id)}
          onDelete={() => deleteRecord(item.id)}
        />
      )}
      refreshControl={
        <RefreshControl refreshing={loading} onRefresh={refresh} />
      }
    />
  );
}
```

### Offline Sync

```typescript
import { useSync } from '@pyairtable/react-native-sdk';

function SyncStatus() {
  const { isSyncing, isOnline, pendingOperations, lastSyncTime, error, sync } = useSync(client);

  return (
    <View>
      <Text>Status: {isOnline ? 'Online' : 'Offline'}</Text>
      <Text>Pending Operations: {pendingOperations}</Text>
      {lastSyncTime && <Text>Last Sync: {lastSyncTime.toLocaleString()}</Text>}
      {isSyncing && <ActivityIndicator />}
      {error && <Text style={{ color: 'red' }}>Sync Error: {error.message}</Text>}
      <Button title="Force Sync" onPress={sync} disabled={isSyncing || !isOnline} />
    </View>
  );
}
```

### File Upload

```typescript
import { useState } from 'react';
import { launchImageLibrary } from 'react-native-image-picker';

function FileUpload() {
  const [uploadProgress, setUploadProgress] = useState(0);

  const handleFileUpload = async () => {
    launchImageLibrary({ mediaType: 'photo' }, async (response) => {
      if (response.assets?.[0]) {
        const asset = response.assets[0];
        
        try {
          const result = await client.uploadFile(
            asset.uri,
            asset.fileName || 'image.jpg',
            (progress) => {
              setUploadProgress(progress.percentage);
            }
          );
          
          console.log('File uploaded:', result);
        } catch (error) {
          console.error('Upload failed:', error);
        }
      }
    });
  };

  return (
    <View>
      <Button title="Upload File" onPress={handleFileUpload} />
      {uploadProgress > 0 && (
        <Progress.Bar progress={uploadProgress / 100} width={200} />
      )}
    </View>
  );
}
```

### Real-time Updates

```typescript
useEffect(() => {
  // Subscribe to table updates
  client.subscribeToTable('baseId', 'tableId');

  // Listen for real-time events
  const handleRecordCreated = (data) => {
    console.log('New record created:', data);
    // Show notification or update UI
  };

  const handleRecordUpdated = (data) => {
    console.log('Record updated:', data);
    // Update UI accordingly
  };

  client.on('record:created', handleRecordCreated);
  client.on('record:updated', handleRecordUpdated);

  return () => {
    client.unsubscribeFromTable('baseId', 'tableId');
    client.off('record:created', handleRecordCreated);
    client.off('record:updated', handleRecordUpdated);
  };
}, []);
```

### Push Notifications

```typescript
useEffect(() => {
  // Request notification permissions
  const requestPermissions = async () => {
    const hasPermission = await client.requestNotificationPermissions();
    if (!hasPermission) {
      console.warn('Notification permissions denied');
    }
  };

  requestPermissions();

  // Listen for sync events to show notifications
  const handleSyncComplete = () => {
    client.showNotification('Sync Complete', 'Your data has been synchronized');
  };

  client.on('sync:complete', handleSyncComplete);

  return () => {
    client.off('sync:complete', handleSyncComplete);
  };
}, []);
```

## API Reference

### PyAirtableClient

The main client class that provides access to all PyAirtable functionality.

#### Constructor Options

```typescript
interface PyAirtableConfig {
  apiKey: string;
  baseUrl: string;
  timeout?: number;
  retryAttempts?: number;
  retryDelay?: number;
  enableOfflineSync?: boolean;
  enableWebSocket?: boolean;
  enablePushNotifications?: boolean;
}
```

#### Methods

- `initialize()`: Initialize the client
- `login(credentials)`: Authenticate user
- `logout()`: Logout user
- `getBases()`: Get all accessible bases
- `getTables(baseId)`: Get tables in a base
- `listRecords(baseId, tableId, query?)`: Get records from a table
- `createRecord(baseId, tableId, record)`: Create a new record
- `updateRecord(baseId, tableId, record)`: Update an existing record
- `deleteRecord(baseId, tableId, recordId)`: Delete a record
- `uploadFile(file, filename, onProgress?)`: Upload a file
- `sync()`: Force synchronization with server

### Hooks

#### useAuth(client)

Provides authentication state and methods.

```typescript
interface UseAuthResult {
  user: User | null;
  isAuthenticated: boolean;
  loading: boolean;
  login: (credentials: LoginCredentials) => Promise<void>;
  logout: () => Promise<void>;
  refreshToken: () => Promise<void>;
}
```

#### useRecords(client, options)

Manages records for a specific table with real-time updates.

```typescript
interface UseRecordsOptions {
  baseId: string;
  tableId: string;
  query?: RecordQuery;
  enableRealtime?: boolean;
  refreshInterval?: number;
  useCache?: boolean;
}

interface UseRecordsResult {
  records: Record[];
  loading: boolean;
  error: PyAirtableError | null;
  refresh: () => Promise<void>;
  create: (record: RecordCreate) => Promise<Record>;
  update: (record: RecordUpdate) => Promise<Record>;
  delete: (id: string) => Promise<void>;
}
```

#### useSync(client)

Provides sync status and controls.

```typescript
interface UseSyncResult {
  isSyncing: boolean;
  isOnline: boolean;
  pendingOperations: number;
  lastSyncTime: Date | null;
  error: PyAirtableError | null;
  sync: () => Promise<void>;
}
```

## Error Handling

The SDK provides comprehensive error handling with specific error types:

```typescript
try {
  await client.createRecord(baseId, tableId, record);
} catch (error) {
  if (error instanceof AuthenticationError) {
    // Handle auth errors
    console.log('Please login again');
  } else if (error instanceof NetworkError) {
    // Handle network errors
    console.log('Check your internet connection');
  } else if (error instanceof ValidationError) {
    // Handle validation errors
    console.log('Invalid data:', error.details);
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