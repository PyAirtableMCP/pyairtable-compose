/**
 * Unified Design System - Compound Components
 * 
 * This module provides a comprehensive design system with compound components
 * that ensure consistency, accessibility, and reusability across the application.
 */

export { DataTable } from './data-table'
export { CommandPalette, useCommandPalette, CommandPaletteTrigger } from './command-palette'
export { MetricCard, MetricGrid, RevenueCard, UserCard, ConversionCard } from './metric-card'
export { 
  EmptyState, 
  NoDataFound, 
  NoResultsFound, 
  CreateFirstItem, 
  ErrorState, 
  UnauthorizedState, 
  MaintenanceState, 
  ComingSoonState,
  EmptyStateCard 
} from './empty-state'
export { 
  LoadingState, 
  TableLoadingState, 
  CardLoadingState, 
  MetricLoadingState, 
  FormLoadingState, 
  ProgressiveLoading, 
  RetryLoading, 
  LoadingOverlay 
} from './loading-state'

// Re-export all base UI components for consistency
export * from '../ui/button'
export * from '../ui/card'
export * from '../ui/input'
export * from '../ui/badge'
export * from '../ui/alert'
export * from '../ui/progress'
export * from '../ui/dropdown-menu'
export * from '../ui/dialog'
export * from '../ui/command'
export * from '../ui/skeleton'
export * from '../ui/separator'