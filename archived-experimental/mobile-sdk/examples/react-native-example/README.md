# PyAirtable React Native Example

This is a complete example application demonstrating how to use the PyAirtable React Native SDK.

## Features Demonstrated

- **Authentication**: Login/logout with JWT tokens
- **Real-time Data**: Live record updates via WebSocket
- **Offline Support**: Automatic caching and sync when online
- **CRUD Operations**: Create, read, update, delete records
- **File Management**: Upload and download files with progress
- **Push Notifications**: Local and remote notifications
- **Error Handling**: Comprehensive error management
- **Sync Status**: Visual indicators for offline/online state

## Prerequisites

- React Native development environment set up
- Node.js 16 or later
- iOS development: Xcode and iOS Simulator
- Android development: Android Studio and Android Emulator

## Installation

1. Install dependencies:
```bash
npm install
```

2. For iOS, install pods:
```bash
cd ios && pod install && cd ..
```

3. Configure the PyAirtable client in `src/App.tsx`:
```typescript
const client = new PyAirtableClient({
  apiKey: 'your-api-key', // Replace with your API key
  baseUrl: 'https://your-pyairtable-instance.com', // Replace with your instance URL
  enableOfflineSync: true,
  enableWebSocket: true,
  enablePushNotifications: true,
});
```

## Running the App

### iOS
```bash
npm run ios
```

### Android
```bash
npm run android
```

## Project Structure

```
src/
├── App.tsx                 # Main app component with client setup
├── navigation/
│   └── MainTabNavigator.tsx # Tab-based navigation
├── screens/
│   ├── LoginScreen.tsx     # Authentication screen
│   ├── RecordsScreen.tsx   # Records CRUD operations
│   ├── SyncScreen.tsx      # Sync status and controls
│   ├── FilesScreen.tsx     # File upload/download
│   └── LoadingScreen.tsx   # Loading indicator
├── components/
│   ├── SyncStatusBanner.tsx # Network/sync status banner
│   └── RecordItem.tsx      # Individual record component
└── utils/
    └── constants.ts        # App constants and configuration
```

## Key Components

### App.tsx
The main app component that:
- Initializes the PyAirtable client
- Handles authentication state
- Provides navigation between login and main app

### LoginScreen.tsx
Demonstrates:
- User authentication with email/password
- Error handling for auth failures
- Loading states during authentication

### RecordsScreen.tsx
Shows how to:
- List records with real-time updates
- Create new records with optimistic updates
- Update existing records
- Delete records with confirmation
- Handle offline scenarios
- Use React hooks for data management

### SyncScreen.tsx
Provides:
- Visual sync status indicators
- Manual sync trigger
- Pending operations count
- Network connectivity status
- Sync history and error details

### FilesScreen.tsx
Demonstrates:
- File picker integration
- Upload progress tracking
- File download capabilities
- Error handling for file operations

## Configuration

### Environment Variables
Create a `.env` file in the project root:

```env
PYAIRTABLE_API_KEY=your_api_key_here
PYAIRTABLE_BASE_URL=https://your-instance.com
PYAIRTABLE_BASE_ID=your_base_id
PYAIRTABLE_TABLE_ID=your_table_id
```

### Push Notifications Setup

#### iOS
1. Add push notification capability in Xcode
2. Configure APNs certificates
3. Add to `ios/YourApp/AppDelegate.mm`:

```objc
#import <UserNotifications/UserNotifications.h>

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  center.delegate = self;
  
  return YES;
}
```

#### Android
1. Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

2. Configure Firebase Cloud Messaging (optional for remote notifications)

## Testing

The example includes comprehensive error scenarios:

1. **Network Issues**: Airplane mode testing
2. **Authentication**: Invalid credentials, token expiry
3. **Data Sync**: Offline operations, conflict resolution
4. **File Operations**: Large file uploads, network interruptions
5. **Real-time Updates**: Multiple device synchronization

## Customization

### Styling
The app uses a modern, iOS-inspired design. Customize styles in each component's `StyleSheet.create()` section.

### Data Fields
Modify the record structure in `RecordsScreen.tsx` to match your Airtable schema:

```typescript
await create({
  fields: {
    Name: newRecordName,
    Status: 'Active',
    CustomField: 'Custom Value',
    // Add your fields here
  },
});
```

### Navigation
Add new screens by modifying `MainTabNavigator.tsx`:

```typescript
<Tab.Screen 
  name="NewScreen" 
  component={NewScreen}
  options={{
    tabBarIcon: ({ color, size }) => (
      <Icon name="new-icon" size={size} color={color} />
    ),
  }}
/>
```

## Performance Considerations

1. **Caching**: Records are cached locally for offline access
2. **Optimistic Updates**: UI updates immediately, syncs in background
3. **Pagination**: Large datasets are paginated automatically
4. **Debouncing**: Search and sync operations are debounced
5. **Memory Management**: Automatic cleanup of subscriptions and timers

## Troubleshooting

### Common Issues

1. **Metro bundler issues**: Reset cache with `npx react-native start --reset-cache`
2. **iOS build fails**: Clean build folder in Xcode, reinstall pods
3. **Android build fails**: Clean project with `./gradlew clean`
4. **WebSocket connection fails**: Check firewall and SSL certificate
5. **Sync not working**: Verify API endpoints and authentication

### Debug Mode

Enable debug logging by setting:

```typescript
const client = new PyAirtableClient({
  // ... other config
  debug: true, // Enable debug logging
});
```

## License

This example is provided under the MIT License. See the main SDK license for details.