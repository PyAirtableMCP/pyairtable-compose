# PyAirtable Flutter Example

A comprehensive Flutter application demonstrating the complete functionality of the PyAirtable Flutter SDK.

## Features Demonstrated

- **Authentication**: Secure login/logout with JWT tokens
- **Real-time Updates**: Live data synchronization via WebSocket
- **Offline Support**: Automatic caching and sync when connectivity returns
- **CRUD Operations**: Complete record lifecycle management
- **File Operations**: Upload and download with progress indicators
- **Push Notifications**: Local and Firebase Cloud Messaging integration
- **State Management**: Riverpod-based reactive state management
- **Error Handling**: Comprehensive error handling with user-friendly messages
- **Material Design**: Modern UI following Material Design 3 principles

## Prerequisites

- Flutter 3.0 or later
- Dart 3.0 or later
- Android Studio / Xcode for device testing
- PyAirtable instance with API access

## Installation

1. **Clone and setup:**
```bash
cd examples/flutter-example
flutter pub get
```

2. **Configure the SDK:**
Edit `lib/providers/pyairtable_provider.dart`:

```dart
final pyairtableClientProvider = Provider<PyAirtableClient>((ref) {
  return PyAirtableClient(
    config: const PyAirtableConfig(
      apiKey: 'your-api-key-here',
      baseUrl: 'https://your-instance.com',
      enableOfflineSync: true,
      enableWebSocket: true,
      enablePushNotifications: true,
    ),
  );
});
```

3. **Run the app:**
```bash
flutter run
```

## Project Structure

```
lib/
├── main.dart                   # App entry point and initialization
├── providers/
│   └── pyairtable_provider.dart # Riverpod providers for state management
├── screens/
│   ├── splash_screen.dart      # Loading screen during initialization
│   ├── login_screen.dart       # Authentication interface
│   ├── home_screen.dart        # Main dashboard with navigation
│   ├── records_screen.dart     # Records CRUD operations
│   ├── sync_screen.dart        # Sync status and controls
│   ├── files_screen.dart       # File management interface
│   └── settings_screen.dart    # App settings and account management
├── widgets/
│   ├── loading_overlay.dart    # Reusable loading indicator
│   ├── record_card.dart        # Individual record display
│   ├── sync_status_banner.dart # Network status indicator
│   ├── file_upload_card.dart   # File upload progress display
│   └── error_widget.dart       # Error state display
├── theme/
│   └── app_theme.dart          # Material Design 3 theme configuration
├── utils/
│   ├── constants.dart          # App-wide constants
│   ├── formatters.dart         # Data formatting utilities
│   └── validators.dart         # Form validation helpers
└── models/
    └── app_models.dart         # Additional app-specific models
```

## Key Features

### 1. Authentication Flow

The app demonstrates secure authentication with automatic token management:

```dart
// Login
await client.login(LoginCredentials(
  email: email,
  password: password,
));

// Automatic token refresh
// SDK handles token expiry automatically

// Logout
await client.logout();
```

### 2. Real-time Data with Riverpod

Records are automatically updated across the app using reactive streams:

```dart
final recordsProvider = StreamProvider.family<List<Record>, RecordsParams>((ref, params) async* {
  final client = ref.watch(pyairtableClientProvider);
  
  // Initial load from cache/API
  final result = await client.listRecords(params.baseId, params.tableId);
  yield result.records;
  
  // Listen for real-time updates
  await for (final event in client.onRecordEvent) {
    if (event.data['baseId'] == params.baseId) {
      // Re-fetch and yield updated records
      final updatedResult = await client.listRecords(params.baseId, params.tableId);
      yield updatedResult.records;
    }
  }
});
```

### 3. Offline-First Architecture

The app works seamlessly offline with automatic synchronization:

```dart
// Operations work offline with optimistic updates
final newRecord = await client.createRecord(baseId, tableId, RecordCreate(
  fields: {'Name': 'New Record', 'Status': 'Active'},
));

// Sync status monitoring
final syncStats = ref.watch(syncStatsProvider);
if (syncStats.pendingOperations > 0) {
  // Show sync indicator
}
```

### 4. File Management

Comprehensive file upload/download with progress tracking:

```dart
final result = await client.uploadFile(
  file.path,
  file.name,
  onProgress: (progress) {
    // Update UI with upload progress
    setState(() {
      uploadProgress = progress.percentage;
    });
  },
);
```

### 5. Error Handling

User-friendly error handling with specific error types:

```dart
try {
  await recordOperations.createRecord(baseId, tableId, fields);
} catch (error) {
  String message;
  if (error is AuthenticationException) {
    message = 'Please login again';
  } else if (error is NetworkException) {
    message = 'Check your internet connection';
  } else if (error is ValidationException) {
    message = 'Please check your input: ${error.details}';
  } else {
    message = 'An unexpected error occurred';
  }
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
```

## Configuration

### Environment Setup

Create a `.env` file or configure directly in the provider:

```dart
const PyAirtableConfig(
  apiKey: String.fromEnvironment('PYAIRTABLE_API_KEY', defaultValue: 'your-key'),
  baseUrl: String.fromEnvironment('PYAIRTABLE_BASE_URL', defaultValue: 'your-url'),
  // ... other config
)
```

### Firebase Setup (for Push Notifications)

1. **Add Firebase to your project:**
   - Follow the [FlutterFire setup guide](https://firebase.flutter.dev/docs/overview/)
   - Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)

2. **Configure push notifications:**
```dart
// The SDK handles Firebase integration automatically
// Just ensure Firebase is properly configured in your project
```

### Platform-Specific Configuration

#### Android (`android/app/build.gradle`)
```gradle
android {
    compileSdkVersion 34
    
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
    }
}

dependencies {
    implementation 'androidx.window:window:1.0.0'
    implementation 'androidx.window:window-java:1.0.0'
}
```

#### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to upload photos</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs photo library access to upload images</string>
```

## UI Components

### Material Design 3 Theme

The app uses a modern Material Design 3 theme with dynamic colors:

```dart
class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.blue,
    brightness: Brightness.light,
    // ... custom theme configuration
  );
  
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.blue,
    brightness: Brightness.dark,
    // ... custom dark theme
  );
}
```

### Responsive Design

The app adapts to different screen sizes and orientations:

```dart
Widget build(BuildContext context) {
  final screenSize = MediaQuery.of(context).size;
  final isTablet = screenSize.width > 768;
  
  return isTablet 
    ? TabletLayout(child: content)
    : MobileLayout(child: content);
}
```

## Testing

### Unit Tests
```bash
flutter test
```

### Integration Tests
```bash
flutter test integration_test/
```

### Widget Tests
The app includes comprehensive widget tests for all major components:

```dart
testWidgets('Login screen validates input', (tester) async {
  await tester.pumpWidget(const MyApp());
  
  // Find login button and tap without entering credentials
  final loginButton = find.text('Sign In');
  await tester.tap(loginButton);
  await tester.pump();
  
  // Verify validation messages appear
  expect(find.text('Please enter your email'), findsOneWidget);
  expect(find.text('Please enter your password'), findsOneWidget);
});
```

## Performance Optimizations

### 1. Efficient State Management
- Uses Riverpod for fine-grained reactivity
- Automatic disposal of unused providers
- Optimized rebuild cycles

### 2. Caching Strategy
- Automatic record caching for offline access
- Image caching with `cached_network_image`
- Efficient memory management

### 3. Background Sync
- Intelligent sync scheduling
- Battery-efficient background processing
- Conflict resolution for concurrent edits

## Deployment

### Android
```bash
flutter build appbundle
```

### iOS
```bash
flutter build ipa
```

### Web (if supported)
```bash
flutter build web
```

## Troubleshooting

### Common Issues

1. **Build Errors**
   ```bash
   flutter clean
   flutter pub get
   cd ios && pod install && cd .. # iOS only
   ```

2. **WebSocket Connection Issues**
   - Check firewall settings
   - Verify SSL certificates
   - Test with HTTP first, then HTTPS

3. **Push Notification Problems**
   - Verify Firebase configuration
   - Check platform-specific permissions
   - Test on physical devices (not simulators)

4. **Sync Issues**
   - Check API endpoint availability
   - Verify authentication tokens
   - Review network connectivity

### Debug Mode

Enable debug logging:

```dart
const PyAirtableConfig(
  // ... other config
  debug: true, // Enables verbose logging
)
```

### Logging

The app includes comprehensive logging:

```dart
import 'package:flutter/foundation.dart';

if (kDebugMode) {
  print('Debug: $message');
}
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

## License

This example app is provided under the MIT License. See the main SDK license for complete details.