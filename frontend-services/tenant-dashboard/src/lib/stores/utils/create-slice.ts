/**
 * Utility for creating store slices with Zustand
 * Enables composition of multiple state slices into a single store
 */

import { StateCreator } from 'zustand'

export interface SliceCreator<T, E = T> {
  (set: (partial: T | Partial<T> | ((state: T) => T | Partial<T>)) => void, get: () => T): E
}

export function createStoreSlice<T extends object, E extends T = T>(
  sliceCreator: SliceCreator<T, E>
): StateCreator<T, [], [], E> {
  return (set, get) => sliceCreator(set, get)
}

// Helper for creating async slices
interface AsyncSliceState<TData = any> {
  data: TData | null
  loading: boolean
  error: string | null
  fetch: () => Promise<void>
  setData: (data: TData) => void
  clear: () => void
}

export function createAsyncSlice<T, TData = any>(
  name: string,
  fetchFn: () => Promise<TData>
) {
  return createStoreSlice<T & AsyncSliceState<TData>>((set, get) => {
    const capitalizedName = name.charAt(0).toUpperCase() + name.slice(1)
    
    return {
      [`${name}Data`]: null,
      [`${name}Loading`]: false,
      [`${name}Error`]: null,
      
      [`fetch${capitalizedName}`]: async () => {
        set({ [`${name}Loading`]: true, [`${name}Error`]: null } as any)
        
        try {
          const data = await fetchFn()
          set({ 
            [`${name}Data`]: data, 
            [`${name}Loading`]: false 
          } as any)
        } catch (error) {
          set({ 
            [`${name}Error`]: error instanceof Error ? error.message : 'Unknown error',
            [`${name}Loading`]: false 
          } as any)
        }
      },
      
      [`set${capitalizedName}Data`]: (data: TData) => {
        set({ [`${name}Data`]: data } as any)
      },
      
      [`clear${capitalizedName}`]: () => {
        set({ 
          [`${name}Data`]: null,
          [`${name}Loading`]: false,
          [`${name}Error`]: null 
        } as any)
      }
    } as any
  })
}

// Helper for creating paginated slices
export function createPaginatedSlice<T extends { id: string }>(
  name: string,
  fetchFn: (page: number, pageSize: number) => Promise<{
    data: T[]
    total: number
    hasNextPage: boolean
    hasPreviousPage: boolean
  }>
) {
  return createStoreSlice((set, get) => ({
    [`${name}Data`]: [] as T[],
    [`${name}Total`]: 0,
    [`${name}Page`]: 1,
    [`${name}PageSize`]: 20,
    [`${name}HasNextPage`]: false,
    [`${name}HasPreviousPage`]: false,
    [`${name}Loading`]: false,
    [`${name}Error`]: null as string | null,
    
    [`fetch${name.charAt(0).toUpperCase() + name.slice(1)}Page`]: async (page: number, pageSize?: number) => {
      const state = get() as any
      const currentPageSize = pageSize || state[`${name}PageSize`]
      
      set({ [`${name}Loading`]: true, [`${name}Error`]: null } as any)
      
      try {
        const result = await fetchFn(page, currentPageSize)
        set({
          [`${name}Data`]: result.data,
          [`${name}Total`]: result.total,
          [`${name}Page`]: page,
          [`${name}PageSize`]: currentPageSize,
          [`${name}HasNextPage`]: result.hasNextPage,
          [`${name}HasPreviousPage`]: result.hasPreviousPage,
          [`${name}Loading`]: false
        } as any)
      } catch (error) {
        set({
          [`${name}Error`]: error instanceof Error ? error.message : 'Unknown error',
          [`${name}Loading`]: false
        } as any)
      }
    },
    
    [`add${name.charAt(0).toUpperCase() + name.slice(1)}Item`]: (item: T) => {
      const state = get() as any
      const currentData = state[`${name}Data`]
      set({
        [`${name}Data`]: [item, ...currentData],
        [`${name}Total`]: state[`${name}Total`] + 1
      } as any)
    },
    
    [`update${name.charAt(0).toUpperCase() + name.slice(1)}Item`]: (id: string, updates: Partial<T>) => {
      const state = get() as any
      const currentData = state[`${name}Data`]
      const updatedData = currentData.map((item: T) =>
        item.id === id ? { ...item, ...updates } : item
      )
      set({ [`${name}Data`]: updatedData } as any)
    },
    
    [`remove${name.charAt(0).toUpperCase() + name.slice(1)}Item`]: (id: string) => {
      const state = get() as any
      const currentData = state[`${name}Data`]
      const filteredData = currentData.filter((item: T) => item.id !== id)
      set({
        [`${name}Data`]: filteredData,
        [`${name}Total`]: state[`${name}Total`] - 1
      } as any)
    }
  }))
}

// Helper for creating filter slices
export function createFilterSlice(name: string) {
  return createStoreSlice((set, get) => ({
    [`${name}Search`]: '',
    [`${name}Filters`]: {} as Record<string, any>,
    [`${name}SortBy`]: null as string | null,
    [`${name}SortOrder`]: 'asc' as 'asc' | 'desc',
    
    [`set${name.charAt(0).toUpperCase() + name.slice(1)}Search`]: (search: string) => {
      set({ [`${name}Search`]: search } as any)
    },
    
    [`set${name.charAt(0).toUpperCase() + name.slice(1)}Filter`]: (key: string, value: any) => {
      const state = get() as any
      const currentFilters = state[`${name}Filters`]
      set({
        [`${name}Filters`]: { ...currentFilters, [key]: value }
      } as any)
    },
    
    [`remove${name.charAt(0).toUpperCase() + name.slice(1)}Filter`]: (key: string) => {
      const state = get() as any
      const currentFilters = state[`${name}Filters`]
      const { [key]: removed, ...remainingFilters } = currentFilters
      set({ [`${name}Filters`]: remainingFilters } as any)
    },
    
    [`clear${name.charAt(0).toUpperCase() + name.slice(1)}Filters`]: () => {
      set({ 
        [`${name}Search`]: '',
        [`${name}Filters`]: {},
        [`${name}SortBy`]: null,
        [`${name}SortOrder`]: 'asc'
      } as any)
    },
    
    [`set${name.charAt(0).toUpperCase() + name.slice(1)}Sorting`]: (field: string, order: 'asc' | 'desc' = 'asc') => {
      set({
        [`${name}SortBy`]: field,
        [`${name}SortOrder`]: order
      } as any)
    }
  }))
}

// Helper for creating optimistic update slices
export function createOptimisticSlice<T extends { id: string }>(name: string) {
  return createStoreSlice((set, get) => ({
    [`${name}PendingUpdates`]: [] as Array<{
      id: string
      type: 'create' | 'update' | 'delete'
      data: T
      originalData?: T
      timestamp: number
    }>,
    
    [`add${name.charAt(0).toUpperCase() + name.slice(1)}OptimisticUpdate`]: (
      type: 'create' | 'update' | 'delete',
      data: T,
      originalData?: T
    ) => {
      const state = get() as any
      const currentUpdates = state[`${name}PendingUpdates`]
      const updateId = `${type}-${data.id}-${Date.now()}`
      
      const newUpdate = {
        id: updateId,
        type,
        data,
        originalData,
        timestamp: Date.now()
      }
      
      set({
        [`${name}PendingUpdates`]: [...currentUpdates, newUpdate]
      } as any)
      
      return updateId
    },
    
    [`confirm${name.charAt(0).toUpperCase() + name.slice(1)}Update`]: (updateId: string) => {
      const state = get() as any
      const currentUpdates = state[`${name}PendingUpdates`]
      const filteredUpdates = currentUpdates.filter((update: any) => update.id !== updateId)
      
      set({ [`${name}PendingUpdates`]: filteredUpdates } as any)
    },
    
    [`revert${name.charAt(0).toUpperCase() + name.slice(1)}Update`]: (updateId: string) => {
      const state = get() as any
      const currentUpdates = state[`${name}PendingUpdates`]
      const update = currentUpdates.find((u: any) => u.id === updateId)
      
      if (update && update.originalData) {
        // Revert the optimistic update
        // This would typically involve updating the main data store
        // Implementation depends on your specific store structure
      }
      
      const filteredUpdates = currentUpdates.filter((u: any) => u.id !== updateId)
      set({ [`${name}PendingUpdates`]: filteredUpdates } as any)
    },
    
    [`clear${name.charAt(0).toUpperCase() + name.slice(1)}PendingUpdates`]: () => {
      set({ [`${name}PendingUpdates`]: [] } as any)
    }
  }))
}