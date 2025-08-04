// Core Event Sourcing Types
export interface Event {
  id: string;
  aggregateId: string;
  aggregateType: string;
  eventType: string;
  version: number;
  timestamp: Date;
  data: Record<string, any>;
  metadata?: Record<string, any>;
  correlationId?: string;
  causationId?: string;
}

export interface EventFilter {
  aggregateType?: string;
  eventType?: string;
  aggregateId?: string;
  startTime?: Date;
  endTime?: Date;
  correlationId?: string;
  limit?: number;
  offset?: number;
}

// SAGA Types
export interface SagaInstance {
  id: string;
  sagaType: string;
  status: SagaStatus;
  currentStep: string;
  startedAt: Date;
  updatedAt: Date;
  completedAt?: Date;
  data: Record<string, any>;
  compensationData?: Record<string, any>;
  steps: SagaStep[];
  error?: string;
}

export enum SagaStatus {
  STARTED = 'STARTED',
  IN_PROGRESS = 'IN_PROGRESS',
  COMPLETED = 'COMPLETED',
  COMPENSATING = 'COMPENSATING',
  COMPENSATED = 'COMPENSATED',
  FAILED = 'FAILED'
}

export interface SagaStep {
  id: string;
  name: string;
  status: SagaStepStatus;
  startedAt?: Date;
  completedAt?: Date;
  error?: string;
  retryCount: number;
  maxRetries: number;
  compensated?: boolean;
}

export enum SagaStepStatus {
  PENDING = 'PENDING',
  IN_PROGRESS = 'IN_PROGRESS',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  COMPENSATING = 'COMPENSATING',
  COMPENSATED = 'COMPENSATED'
}

// CQRS Projection Types
export interface Projection {
  name: string;
  status: ProjectionStatus;
  lastEventPosition: number;
  lastUpdated: Date;
  eventsProcessed: number;
  lag: number;
  error?: string;
  metadata?: Record<string, any>;
}

export enum ProjectionStatus {
  RUNNING = 'RUNNING',
  STOPPED = 'STOPPED',
  REBUILDING = 'REBUILDING',
  ERROR = 'ERROR',
  INITIALIZING = 'INITIALIZING'
}

export interface ProjectionMetrics {
  eventsPerSecond: number;
  averageProcessingTime: number;
  errorRate: number;
  memoryUsage: number;
}

// System Health Types
export interface ServiceHealth {
  name: string;
  status: ServiceStatus;
  uptime: number;
  version: string;
  dependencies: ServiceDependency[];
  metrics: ServiceMetrics;
  lastChecked: Date;
}

export enum ServiceStatus {
  HEALTHY = 'HEALTHY',
  DEGRADED = 'DEGRADED',
  UNHEALTHY = 'UNHEALTHY',
  UNKNOWN = 'UNKNOWN'
}

export interface ServiceDependency {
  name: string;
  status: ServiceStatus;
  latency: number;
}

export interface ServiceMetrics {
  requestRate: number;
  errorRate: number;
  averageLatency: number;
  p95Latency: number;
  memoryUsage: number;
  cpuUsage: number;
}

// Message Queue Types
export interface QueueMetrics {
  name: string;
  depth: number;
  consumerCount: number;
  messageRate: number;
  errorRate: number;
  oldestMessage?: Date;
}

// Event Schema Types
export interface EventSchema {
  eventType: string;
  version: string;
  schema: JSONSchema;
  examples: Record<string, any>[];
  description?: string;
}

export interface JSONSchema {
  type: string;
  properties: Record<string, JSONSchemaProperty>;
  required?: string[];
  additionalProperties?: boolean;
}

export interface JSONSchemaProperty {
  type: string;
  description?: string;
  enum?: any[];
  items?: JSONSchemaProperty;
  properties?: Record<string, JSONSchemaProperty>;
}

// WebSocket Message Types
export interface WebSocketMessage {
  type: 'EVENT' | 'SAGA_UPDATE' | 'PROJECTION_UPDATE' | 'HEALTH_UPDATE';
  data: any;
  timestamp: Date;
}

// UI State Types
export interface DashboardState {
  selectedTimeRange: TimeRange;
  autoRefresh: boolean;
  refreshInterval: number;
}

export interface TimeRange {
  start: Date;
  end: Date;
  label: string;
}

// Performance Types
export interface PerformanceMetrics {
  timestamp: Date;
  eventThroughput: number;
  sagaCompletionRate: number;
  projectionLag: number;
  systemLatency: number;
  errorRate: number;
}

// Developer Tools Types
export interface EventTest {
  id: string;
  name: string;
  eventType: string;
  aggregateId: string;
  data: Record<string, any>;
  expectedOutcome?: string;
  status: TestStatus;
  result?: TestResult;
}

export enum TestStatus {
  PENDING = 'PENDING',
  RUNNING = 'RUNNING',
  PASSED = 'PASSED',
  FAILED = 'FAILED'
}

export interface TestResult {
  success: boolean;
  message: string;
  actualEvents?: Event[];
  executionTime: number;
}

// Navigation Types
export interface NavigationItem {
  name: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  current: boolean;
  badge?: string | number;
}