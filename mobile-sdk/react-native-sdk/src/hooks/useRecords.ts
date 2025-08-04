import { useState, useEffect, useCallback, useRef } from 'react';
import { PyAirtableClient } from '../PyAirtableClient';
import { 
  Record, 
  RecordCreate, 
  RecordUpdate, 
  RecordQuery, 
  UseRecordsResult,
  PyAirtableError 
} from '../types';

export interface UseRecordsOptions {
  baseId: string;
  tableId: string;
  query?: RecordQuery;
  enableRealtime?: boolean;
  refreshInterval?: number;
  useCache?: boolean;
}

export function useRecords(
  client: PyAirtableClient,
  options: UseRecordsOptions
): UseRecordsResult {
  const [records, setRecords] = useState<Record[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<PyAirtableError | null>(null);
  
  const { baseId, tableId, query, enableRealtime = true, refreshInterval, useCache = true } = options;
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  const fetchRecords = useCallback(async () => {
    try {
      setError(null);
      const result = await client.listRecords(baseId, tableId, query, useCache);
      setRecords(result.records);
    } catch (err) {
      setError(err as PyAirtableError);
    } finally {
      setLoading(false);
    }
  }, [client, baseId, tableId, query, useCache]);

  const refresh = useCallback(async () => {
    setLoading(true);
    await fetchRecords();
  }, [fetchRecords]);

  const create = useCallback(async (record: RecordCreate): Promise<Record> => {
    try {
      const newRecord = await client.createRecord(baseId, tableId, record);
      
      // Optimistically update local state
      setRecords(prev => [...prev, newRecord]);
      
      return newRecord;
    } catch (err) {
      setError(err as PyAirtableError);
      throw err;
    }
  }, [client, baseId, tableId]);

  const update = useCallback(async (record: RecordUpdate): Promise<Record> => {
    try {
      const updatedRecord = await client.updateRecord(baseId, tableId, record);
      
      // Optimistically update local state
      setRecords(prev => 
        prev.map(r => r.id === record.id ? updatedRecord : r)
      );
      
      return updatedRecord;
    } catch (err) {
      setError(err as PyAirtableError);
      throw err;
    }
  }, [client, baseId, tableId]);

  const deleteRecord = useCallback(async (id: string): Promise<void> => {
    try {
      await client.deleteRecord(baseId, tableId, id);
      
      // Optimistically update local state
      setRecords(prev => prev.filter(r => r.id !== id));
    } catch (err) {
      setError(err as PyAirtableError);
      throw err;
    }
  }, [client, baseId, tableId]);

  // Initial load
  useEffect(() => {
    fetchRecords();
  }, [fetchRecords]);

  // Setup polling if refreshInterval is specified
  useEffect(() => {
    if (refreshInterval && refreshInterval > 0) {
      intervalRef.current = setInterval(fetchRecords, refreshInterval);
      
      return () => {
        if (intervalRef.current) {
          clearInterval(intervalRef.current);
        }
      };
    }
  }, [fetchRecords, refreshInterval]);

  // Setup real-time listeners
  useEffect(() => {
    if (!enableRealtime) return;

    try {
      client.subscribeToTable(baseId, tableId);
    } catch (err) {
      console.warn('Failed to subscribe to real-time updates:', err);
    }

    const handleRecordCreated = (data: any) => {
      if (data.baseId === baseId && data.tableId === tableId) {
        setRecords(prev => {
          const exists = prev.some(r => r.id === data.record.id);
          return exists ? prev : [...prev, data.record];
        });
      }
    };

    const handleRecordUpdated = (data: any) => {
      if (data.baseId === baseId && data.tableId === tableId) {
        setRecords(prev =>
          prev.map(r => r.id === data.record.id ? data.record : r)
        );
      }
    };

    const handleRecordDeleted = (data: any) => {
      if (data.baseId === baseId && data.tableId === tableId) {
        setRecords(prev => prev.filter(r => r.id !== data.recordId));
      }
    };

    client.on('record:created', handleRecordCreated);
    client.on('record:updated', handleRecordUpdated);
    client.on('record:deleted', handleRecordDeleted);

    return () => {
      try {
        client.unsubscribeFromTable(baseId, tableId);
      } catch (err) {
        console.warn('Failed to unsubscribe from real-time updates:', err);
      }

      client.off('record:created', handleRecordCreated);
      client.off('record:updated', handleRecordUpdated);
      client.off('record:deleted', handleRecordDeleted);
    };
  }, [client, baseId, tableId, enableRealtime]);

  return {
    records,
    loading,
    error,
    refresh,
    create,
    update,
    delete: deleteRecord,
  };
}