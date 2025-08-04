/**
 * Advanced Zustand State Management Patterns
 * 
 * This module provides sophisticated state management patterns using Zustand
 * with features like persistence, middleware, slices, and reactive subscriptions.
 */

export { useAppStore } from './app-store'
export { useUserStore } from './user-store'
export { useTenantStore } from './tenant-store'
export { useUIStore } from './ui-store'
export { useOfflineStore } from './offline-store'
export { useAnalyticsStore } from './analytics-store'

// Store utilities
export { createStoreSlice } from './utils/create-slice'
export { withDevtools } from './utils/devtools'
export { withPersistence } from './utils/persistence'
export { withImmer } from './utils/immer'
export { createAsyncSlice } from './utils/async-slice'

// Types
export type * from './types'