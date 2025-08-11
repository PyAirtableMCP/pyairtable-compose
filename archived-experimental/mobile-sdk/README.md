# PyAirtable Mobile SDK

A comprehensive mobile SDK for PyAirtable that supports both React Native and Flutter platforms.

## Features

- **Cross-Platform Support**: React Native (iOS/Android) and Flutter SDKs
- **Authentication**: JWT-based authentication with automatic token refresh
- **Real-time Updates**: WebSocket support for live data synchronization
- **Offline Support**: Local storage with automatic sync when online
- **CRUD Operations**: Complete record management with optimistic updates
- **Formula Evaluation**: Client-side formula computation
- **File Management**: Upload/download with progress tracking
- **Push Notifications**: Native notification support for both platforms
- **Type Safety**: Full TypeScript/Dart type definitions
- **Error Handling**: Comprehensive error handling with retry logic
- **Performance Optimized**: Efficient data caching and background sync

## Architecture

```
mobile-sdk/
├── react-native-sdk/     # React Native TypeScript SDK
├── flutter-sdk/          # Flutter Dart SDK
├── shared/              # Shared type definitions and specs
├── examples/            # Example applications
└── docs/               # Comprehensive documentation
```

## Quick Start

### React Native

```bash
npm install @pyairtable/react-native-sdk
```

```typescript
import { PyAirtableClient } from '@pyairtable/react-native-sdk';

const client = new PyAirtableClient({
  apiKey: 'your-api-key',
  baseUrl: 'https://your-pyairtable-instance.com'
});

// Authenticate
await client.auth.login('username', 'password');

// Get records
const records = await client.records.list('tableId');
```

### Flutter

```yaml
dependencies:
  pyairtable_sdk: ^1.0.0
```

```dart
import 'package:pyairtable_sdk/pyairtable_sdk.dart';

final client = PyAirtableClient(
  apiKey: 'your-api-key',
  baseUrl: 'https://your-pyairtable-instance.com',
);

// Authenticate
await client.auth.login('username', 'password');

// Get records
final records = await client.records.list('tableId');
```

## Documentation

- [React Native SDK Documentation](./react-native-sdk/README.md)
- [Flutter SDK Documentation](./flutter-sdk/README.md)
- [API Reference](./docs/api-reference.md)
- [Authentication Guide](./docs/authentication.md)
- [Offline Sync Guide](./docs/offline-sync.md)
- [Push Notifications Setup](./docs/push-notifications.md)

## Examples

- [React Native Example App](./examples/react-native-example/)
- [Flutter Example App](./examples/flutter-example/)

## License

MIT License - see [LICENSE](./LICENSE) file for details.