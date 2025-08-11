import { useState, useEffect, useCallback } from 'react';
import { PyAirtableClient } from '../PyAirtableClient';
import { User, LoginCredentials, UseAuthResult } from '../types';
import { PyAirtableSDKError } from '../utils/errors';

export function useAuth(client: PyAirtableClient): UseAuthResult {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(false);
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  useEffect(() => {
    // Initialize auth state
    const currentUser = client.getCurrentUser();
    setUser(currentUser);
    setIsAuthenticated(client.isAuthenticated());

    // Listen for auth events
    const handleLogin = (user: User) => {
      setUser(user);
      setIsAuthenticated(true);
    };

    const handleLogout = () => {
      setUser(null);
      setIsAuthenticated(false);
    };

    client.on('login', handleLogin);
    client.on('logout', handleLogout);

    return () => {
      client.off('login', handleLogin);
      client.off('logout', handleLogout);
    };
  }, [client]);

  const login = useCallback(async (credentials: LoginCredentials) => {
    setLoading(true);
    try {
      await client.login(credentials);
    } catch (error) {
      throw error;
    } finally {
      setLoading(false);
    }
  }, [client]);

  const logout = useCallback(async () => {
    setLoading(true);
    try {
      await client.logout();
    } catch (error) {
      throw error;
    } finally {
      setLoading(false);
    }
  }, [client]);

  const refreshToken = useCallback(async () => {
    setLoading(true);
    try {
      // Access the auth service through the client's private property
      // This is a workaround since we don't expose authService publicly
      await (client as any).authService.refreshTokens();
      
      const currentUser = client.getCurrentUser();
      setUser(currentUser);
      setIsAuthenticated(client.isAuthenticated());
    } catch (error) {
      setUser(null);
      setIsAuthenticated(false);
      throw error;
    } finally {
      setLoading(false);
    }
  }, [client]);

  return {
    user,
    isAuthenticated,
    loading,
    login,
    logout,
    refreshToken,
  };
}