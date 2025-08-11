import { useState, useEffect, useCallback } from 'react';
import { PyAirtableClient } from '../PyAirtableClient';
import { PyAirtableError } from '../types';

export interface UseSyncResult {
  isSyncing: boolean;
  isOnline: boolean;
  pendingOperations: number;
  lastSyncTime: Date | null;
  error: PyAirtableError | null;
  sync: () => Promise<void>;
}

export function useSync(client: PyAirtableClient): UseSyncResult {
  const [isSyncing, setIsSyncing] = useState(false);
  const [isOnline, setIsOnline] = useState(true);
  const [pendingOperations, setPendingOperations] = useState(0);
  const [lastSyncTime, setLastSyncTime] = useState<Date | null>(null);
  const [error, setError] = useState<PyAirtableError | null>(null);

  const updateState = useCallback(() => {
    setIsOnline(client.isOnline());
    setPendingOperations(client.getPendingOperationsCount());
  }, [client]);

  const sync = useCallback(async () => {
    try {
      setError(null);
      await client.sync();
      setLastSyncTime(new Date());
    } catch (err) {
      setError(err as PyAirtableError);
      throw err;
    }
  }, [client]);

  useEffect(() => {
    // Initial state
    updateState();

    // Listen for network events
    const handleOnline = () => {
      setIsOnline(true);
      updateState();
    };

    const handleOffline = () => {
      setIsOnline(false);
      updateState();
    };

    // Listen for sync events
    const handleSyncStart = () => {
      setIsSyncing(true);
      setError(null);
    };

    const handleSyncComplete = () => {
      setIsSyncing(false);
      setLastSyncTime(new Date());
      updateState();
    };

    const handleSyncError = (err: PyAirtableError) => {
      setIsSyncing(false);
      setError(err);
      updateState();
    };

    client.on('online', handleOnline);
    client.on('offline', handleOffline);
    client.on('sync:start', handleSyncStart);
    client.on('sync:complete', handleSyncComplete);
    client.on('sync:error', handleSyncError);

    return () => {
      client.off('online', handleOnline);
      client.off('offline', handleOffline);
      client.off('sync:start', handleSyncStart);
      client.off('sync:complete', handleSyncComplete);
      client.off('sync:error', handleSyncError);
    };
  }, [client, updateState]);

  return {
    isSyncing,
    isOnline,
    pendingOperations,
    lastSyncTime,
    error,
    sync,
  };
}