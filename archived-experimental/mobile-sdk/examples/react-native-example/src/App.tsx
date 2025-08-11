import React, { useEffect, useState } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { Alert } from 'react-native';

import PyAirtableClient, { useAuth } from '@pyairtable/react-native-sdk';
import LoginScreen from './screens/LoginScreen';
import MainTabNavigator from './navigation/MainTabNavigator';
import LoadingScreen from './screens/LoadingScreen';

const Stack = createStackNavigator();

// Initialize PyAirtable client
const client = new PyAirtableClient({
  apiKey: 'your-api-key', // Replace with your API key
  baseUrl: 'https://your-pyairtable-instance.com', // Replace with your instance URL
  enableOfflineSync: true,
  enableWebSocket: true,
  enablePushNotifications: true,
});

function AppContent() {
  const { user, isAuthenticated, loading } = useAuth(client);
  const [isInitialized, setIsInitialized] = useState(false);

  useEffect(() => {
    const initializeClient = async () => {
      try {
        await client.initialize();
        setIsInitialized(true);
      } catch (error) {
        Alert.alert('Initialization Error', error.message);
      }
    };

    initializeClient();

    // Cleanup on unmount
    return () => {
      client.destroy();
    };
  }, []);

  if (!isInitialized || loading) {
    return <LoadingScreen />;
  }

  return (
    <Stack.Navigator screenOptions={{ headerShown: false }}>
      {isAuthenticated ? (
        <Stack.Screen name="Main">
          {(props) => <MainTabNavigator {...props} client={client} user={user} />}
        </Stack.Screen>
      ) : (
        <Stack.Screen name="Login">
          {(props) => <LoginScreen {...props} client={client} />}
        </Stack.Screen>
      )}
    </Stack.Navigator>
  );
}

export default function App() {
  return (
    <NavigationContainer>
      <AppContent />
    </NavigationContainer>
  );
}