// Database Performance and Connection Pool Testing for PyAirtable Platform
// Tests database query performance, connection pool behavior, and PostgreSQL optimization

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// Database-specific metrics
export const dbMetrics = {
  // Query performance metrics
  simpleQueryTime: new Trend('db_simple_query_time'),
  complexQueryTime: new Trend('db_complex_query_time'),
  aggregationQueryTime: new Trend('db_aggregation_query_time'),
  fullTextSearchTime: new Trend('db_fulltext_search_time'),
  
  // Connection pool metrics
  connectionAcquisitionTime: new Trend('db_connection_acquisition_time'),
  activeConnections: new Gauge('db_active_connections'),
  poolUtilization: new Gauge('db_pool_utilization'),
  connectionTimeouts: new Counter('db_connection_timeouts'),
  connectionErrors: new Rate('db_connection_errors'),
  
  // Transaction metrics
  transactionTime: new Trend('db_transaction_time'),
  deadlocks: new Counter('db_deadlocks'),
  rollbacks: new Counter('db_rollbacks'),
  
  // Index and optimization metrics
  indexHitRate: new Rate('db_index_hit_rate'),
  cacheHitRate: new Rate('db_cache_hit_rate'),
  slowQueries: new Counter('db_slow_queries'),
  
  // Bulk operation metrics
  bulkInsertTime: new Trend('db_bulk_insert_time'),
  bulkUpdateTime: new Trend('db_bulk_update_time'),
  bulkDeleteTime: new Trend('db_bulk_delete_time'),
  
  // Replication and consistency metrics
  replicationLag: new Trend('db_replication_lag'),
  readWriteLatency: new Trend('db_read_write_latency'),
};

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const API_KEY = __ENV.API_KEY || 'test-api-key';
const DB_TEST_MODE = __ENV.DB_TEST_MODE || 'comprehensive'; // light, comprehensive, intensive
const MAX_CONNECTIONS = parseInt(__ENV.MAX_CONNECTIONS || '100');

// Test mode configurations
const testModeConfigs = {
  light: { 
    users: 20, 
    duration: '5m', 
    queryComplexity: 'simple',
    bulkSize: 100,
    maxConcurrentQueries: 10
  },
  comprehensive: { 
    users: 50, 
    duration: '15m', 
    queryComplexity: 'mixed',
    bulkSize: 500,
    maxConcurrentQueries: 25
  },
  intensive: { 
    users: 100, 
    duration: '30m', 
    queryComplexity: 'complex',
    bulkSize: 1000,
    maxConcurrentQueries: 50
  },
};

const config = testModeConfigs[DB_TEST_MODE];

export const options = {
  scenarios: {
    // Connection pool stress testing
    connection_pool_stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: Math.floor(config.users * 0.5) },
        { duration: '5m', target: config.users },
        { duration: '3m', target: Math.floor(config.users * 1.5) }, // Over capacity
        { duration: '2m', target: config.users },
        { duration: '3m', target: 0 },
      ],
      tags: { test_type: 'connection_pool' },
    },
    
    // Query performance testing
    query_performance: {
      executor: 'constant-vus',
      vus: Math.floor(config.users * 0.6),
      duration: config.duration,
      tags: { test_type: 'query_performance' },
    },
    
    // Transaction testing
    transaction_testing: {
      executor: 'constant-vus',
      vus: Math.floor(config.users * 0.3),
      duration: config.duration,
      tags: { test_type: 'transactions' },
    },
    
    // Bulk operations testing
    bulk_operations: {
      executor: 'constant-vus',
      vus: Math.floor(config.users * 0.2),
      duration: config.duration,
      tags: { test_type: 'bulk_operations' },
    },
    
    // Read/Write split testing
    read_write_split: {
      executor: 'constant-vus',
      vus: Math.floor(config.users * 0.4),
      duration: config.duration,
      tags: { test_type: 'read_write_split' },
    },
    
    // Long-running query testing
    long_running_queries: {
      executor: 'constant-vus',
      vus: Math.floor(config.users * 0.1),
      duration: config.duration,
      tags: { test_type: 'long_queries' },
    },
    
    // Index performance testing
    index_performance: {
      executor: 'constant-vus',
      vus: Math.floor(config.users * 0.3),
      duration: config.duration,
      tags: { test_type: 'index_performance' },
    },
    
    // Concurrent access testing
    concurrent_access: {
      executor: 'constant-arrival-rate',
      rate: config.maxConcurrentQueries,
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.5),
      maxVUs: config.users,
      tags: { test_type: 'concurrent_access' },
    },
  },
  
  // Database-specific thresholds
  thresholds: {
    // Query performance thresholds
    'http_req_duration{test_type:query_performance}': ['p(95)<1000'],
    'http_req_duration{test_type:connection_pool}': ['p(95)<2000'],
    'http_req_duration{test_type:transactions}': ['p(95)<3000'],
    'http_req_duration{test_type:bulk_operations}': ['p(95)<10000'],
    
    // Error rate thresholds
    'http_req_failed{test_type:query_performance}': ['rate<0.01'],
    'http_req_failed{test_type:connection_pool}': ['rate<0.05'],
    'http_req_failed{test_type:transactions}': ['rate<0.02'],
    
    // Custom database metrics thresholds
    db_simple_query_time: ['p(95)<50'],      // Simple queries under 50ms
    db_complex_query_time: ['p(95)<500'],    // Complex queries under 500ms
    db_connection_acquisition_time: ['p(95)<100'], // Connection under 100ms
    db_connection_errors: ['rate<0.01'],      // Connection error rate under 1%
  },
  
  userAgent: 'K6-DatabaseTesting/1.0',
};

// Database query templates
const queryTemplates = {
  simple: [
    { 
      name: 'user_by_id',
      endpoint: '/api/db/users/{id}',
      method: 'GET',
      description: 'Simple SELECT by primary key'
    },
    { 
      name: 'workspace_by_owner',
      endpoint: '/api/db/workspaces/by-owner/{user_id}',
      method: 'GET',
      description: 'SELECT with single WHERE clause'
    },
    { 
      name: 'recent_records',
      endpoint: '/api/db/records/recent?limit=10',
      method: 'GET',
      description: 'SELECT with ORDER BY and LIMIT'
    },
  ],
  
  complex: [
    { 
      name: 'user_workspace_analytics',
      endpoint: '/api/db/analytics/user-workspaces',
      method: 'POST',
      payload: {
        user_id: '{user_id}',
        date_range: '30d',
        include_metrics: true
      },
      description: 'Complex JOIN with aggregations'
    },
    { 
      name: 'workspace_permissions',
      endpoint: '/api/db/permissions/workspace-detailed',
      method: 'POST',
      payload: {
        workspace_ids: ['{workspace_id}'],
        include_inherited: true,
        resolve_groups: true
      },
      description: 'Multiple JOINs with recursive CTEs'
    },
    { 
      name: 'advanced_search',
      endpoint: '/api/db/search/advanced',
      method: 'POST',
      payload: {
        query: 'performance test',
        filters: {
          date_range: { gte: '2024-01-01', lte: '2024-12-31' },
          categories: ['test', 'performance'],
          status: ['active', 'pending']
        },
        sort: [{ field: 'relevance', direction: 'desc' }],
        facets: ['category', 'status', 'owner'],
        limit: 50
      },
      description: 'Full-text search with complex filtering'
    },
  ],
  
  aggregation: [
    { 
      name: 'daily_metrics',
      endpoint: '/api/db/metrics/daily-aggregation',
      method: 'POST',
      payload: {
        date_range: '7d',
        group_by: ['date', 'workspace_id'],
        metrics: ['record_count', 'user_activity', 'api_calls']
      },
      description: 'Time-series aggregation with grouping'
    },
    { 
      name: 'user_statistics',
      endpoint: '/api/db/stats/user-comprehensive',
      method: 'POST',
      payload: {
        user_ids: ['{user_id}'],
        include_historical: true,
        compute_percentiles: true
      },
      description: 'Statistical aggregation with percentiles'
    },
  ],
  
  bulk: [
    {
      name: 'bulk_record_insert',
      endpoint: '/api/db/records/bulk-insert',
      method: 'POST',
      description: 'Bulk INSERT operation'
    },
    {
      name: 'bulk_record_update',
      endpoint: '/api/db/records/bulk-update',
      method: 'PATCH',
      description: 'Bulk UPDATE operation'
    },
  ]
};

// Connection pool monitoring
let connectionPoolStats = {
  activeConnections: 0,
  peakConnections: 0,
  totalConnectionsCreated: 0,
  connectionTimeouts: 0,
};

export function setup() {
  console.log('Starting Database Performance Testing');
  console.log(`Test Mode: ${DB_TEST_MODE}`);
  console.log(`Target: ${BASE_URL}`);
  console.log(`Max Connections: ${MAX_CONNECTIONS}`);
  console.log(`Query Complexity: ${config.queryComplexity}`);
  
  // Initialize database for testing
  const initResponse = http.post(`${BASE_URL}/api/db/test/initialize`, 
    JSON.stringify({
      mode: DB_TEST_MODE,
      max_connections: MAX_CONNECTIONS,
      bulk_size: config.bulkSize
    }),
    {
      headers: { 'Content-Type': 'application/json', 'X-API-Key': API_KEY },
      timeout: '60s'
    }
  );
  
  check(initResponse, {
    'database initialized for testing': (r) => r.status === 200,
  });
  
  return {
    baseUrl: BASE_URL,
    apiKey: API_KEY,
    config: config,
    startTime: Date.now(),
  };
}

export default function(data) {
  const testType = __ENV.K6_SCENARIO || 'query_performance';
  
  // Get authentication token
  const authToken = getAuthToken(data);
  const headers = {
    'Authorization': `Bearer ${authToken}`,
    'Content-Type': 'application/json',
    'X-API-Key': data.apiKey,
    'X-DB-Test-Context': testType,
  };
  
  // Execute test based on scenario
  switch (testType) {
    case 'connection_pool_stress':
      connectionPoolStress(data, headers);
      break;
    case 'query_performance':
      queryPerformanceTest(data, headers);
      break;
    case 'transactions':
      transactionTest(data, headers);
      break;
    case 'bulk_operations':
      bulkOperationsTest(data, headers);
      break;
    case 'read_write_split':
      readWriteSplitTest(data, headers);
      break;
    case 'long_queries':
      longRunningQueriesTest(data, headers);
      break;
    case 'index_performance':
      indexPerformanceTest(data, headers);
      break;
    case 'concurrent_access':
      concurrentAccessTest(data, headers);
      break;
    default:
      queryPerformanceTest(data, headers);
  }
  
  // Update connection pool stats
  updateConnectionPoolStats(data, headers);
  
  // Short sleep for database testing
  sleep(Math.random() * 1 + 0.5);
}

function getAuthToken(data) {
  if (!data.authToken || isTokenExpired(data.tokenTimestamp)) {
    const authResponse = http.post(`${data.baseUrl}/api/auth/login`, 
      JSON.stringify({ email: 'dbtest@test.com', password: 'dbtest123' }),
      {
        headers: { 'Content-Type': 'application/json', 'X-API-Key': data.apiKey },
        timeout: '10s'
      }
    );
    
    if (authResponse.status === 200) {
      data.authToken = authResponse.json('token');
      data.tokenTimestamp = Date.now();
    }
  }
  
  return data.authToken || 'fallback-token';
}

function isTokenExpired(timestamp) {
  if (!timestamp) return true;
  return (Date.now() - timestamp) > (60 * 60 * 1000); // 1 hour
}

function connectionPoolStress(data, headers) {
  group('Connection Pool Stress Test', () => {
    // Simulate rapid connection acquisition
    const startTime = Date.now();
    
    // Multiple concurrent requests to stress connection pool
    const requests = [];
    const numRequests = Math.floor(Math.random() * 10) + 5; // 5-15 requests
    
    for (let i = 0; i < numRequests; i++) {
      requests.push([
        'GET',
        `${data.baseUrl}/api/db/connection-test/${i}`,
        null,
        { 
          headers: { ...headers, 'X-Connection-Test': `stress_${i}` },
          timeout: '30s',
          tags: { query_type: 'connection_stress' }
        }
      ]);
    }
    
    const responses = http.batch(requests);
    const acquisitionTime = Date.now() - startTime;
    
    dbMetrics.connectionAcquisitionTime.add(acquisitionTime);
    
    let successCount = 0;
    let timeoutCount = 0;
    
    responses.forEach((response, index) => {
      const success = check(response, {
        'connection acquired': (r) => r.status < 500,
        'no connection timeout': (r) => r.status !== 408,
        'pool not exhausted': (r) => r.status !== 503,
      });
      
      if (success) {
        successCount++;
      } else if (response.status === 408) {
        timeoutCount++;
        dbMetrics.connectionTimeouts.add(1);
      }
      
      dbMetrics.connectionErrors.add(!success);
      
      // Extract connection pool metrics from response headers
      if (response.headers['X-Pool-Active']) {
        dbMetrics.activeConnections.add(parseInt(response.headers['X-Pool-Active']));
      }
      if (response.headers['X-Pool-Utilization']) {
        dbMetrics.poolUtilization.add(parseFloat(response.headers['X-Pool-Utilization']));
      }
    });
    
    console.log(`Connection pool stress: ${successCount}/${numRequests} successful, ${timeoutCount} timeouts`);
  });
}

function queryPerformanceTest(data, headers) {
  group('Query Performance Test', () => {
    const queryTypes = config.queryComplexity === 'simple' ? ['simple'] :
                      config.queryComplexity === 'complex' ? ['complex', 'aggregation'] :
                      ['simple', 'complex', 'aggregation'];
    
    const selectedType = queryTypes[Math.floor(Math.random() * queryTypes.length)];
    const queries = queryTemplates[selectedType];
    const query = queries[Math.floor(Math.random() * queries.length)];
    
    executeQuery(data, headers, query, selectedType);
  });
}

function transactionTest(data, headers) {
  group('Database Transaction Test', () => {
    const transactionData = {
      operations: [
        {
          type: 'insert',
          table: 'test_records',
          data: {
            name: `Transaction Test ${Date.now()}`,
            value: Math.floor(Math.random() * 1000),
            status: 'pending'
          }
        },
        {
          type: 'update',
          table: 'test_records',
          condition: { status: 'pending' },
          data: { status: 'processing' }
        },
        {
          type: 'select',
          table: 'test_records',
          condition: { status: 'processing' }
        }
      ],
      isolation_level: 'READ_COMMITTED',
      timeout: 30000
    };
    
    const startTime = Date.now();
    const response = http.post(`${data.baseUrl}/api/db/transaction`,
      JSON.stringify(transactionData),
      {
        headers: { ...headers, 'X-Transaction-Test': 'performance' },
        timeout: '60s',
        tags: { query_type: 'transaction' }
      }
    );
    
    const transactionTime = Date.now() - startTime;
    dbMetrics.transactionTime.add(transactionTime);
    
    const success = check(response, {
      'transaction completed': (r) => r.status === 200,
      'no deadlock': (r) => !r.body.includes('deadlock'),
      'no rollback': (r) => !r.body.includes('rollback'),
      'transaction time acceptable': (r) => r.timings.duration < 30000,
    });
    
    if (!success) {
      if (response.body && response.body.includes('deadlock')) {
        dbMetrics.deadlocks.add(1);
      }
      if (response.body && response.body.includes('rollback')) {
        dbMetrics.rollbacks.add(1);
      }
    }
  });
}

function bulkOperationsTest(data, headers) {
  group('Bulk Operations Test', () => {
    const operationType = ['insert', 'update', 'delete'][Math.floor(Math.random() * 3)];
    const bulkSize = Math.min(config.bulkSize, 1000); // Cap at 1000 for performance
    
    let bulkData;
    let endpoint;
    let method;
    
    switch (operationType) {
      case 'insert':
        bulkData = generateBulkInsertData(bulkSize);
        endpoint = '/api/db/records/bulk-insert';
        method = 'POST';
        break;
      case 'update':
        bulkData = generateBulkUpdateData(bulkSize);
        endpoint = '/api/db/records/bulk-update';
        method = 'PATCH';
        break;
      case 'delete':
        bulkData = generateBulkDeleteData(bulkSize);
        endpoint = '/api/db/records/bulk-delete';
        method = 'DELETE';
        break;
    }
    
    const startTime = Date.now();
    const response = http.request(method, `${data.baseUrl}${endpoint}`,
      JSON.stringify(bulkData),
      {
        headers: { ...headers, 'X-Bulk-Operation': operationType },
        timeout: '120s',
        tags: { query_type: 'bulk_operation', operation: operationType }
      }
    );
    
    const operationTime = Date.now() - startTime;
    
    switch (operationType) {
      case 'insert':
        dbMetrics.bulkInsertTime.add(operationTime);
        break;
      case 'update':
        dbMetrics.bulkUpdateTime.add(operationTime);
        break;
      case 'delete':
        dbMetrics.bulkDeleteTime.add(operationTime);
        break;
    }
    
    const success = check(response, {
      'bulk operation completed': (r) => r.status === 200,
      'reasonable bulk time': (r) => r.timings.duration < 120000,
      'no bulk operation errors': (r) => !r.body.includes('error'),
    });
    
    if (success && response.json) {
      const result = response.json();
      console.log(`Bulk ${operationType}: processed ${result.processed || 0}/${bulkSize} records in ${operationTime}ms`);
    }
  });
}

function readWriteSplitTest(data, headers) {
  group('Read/Write Split Test', () => {
    // 80% reads, 20% writes typical ratio
    const isRead = Math.random() < 0.8;
    
    if (isRead) {
      // Read operation (potentially from read replica)
      const readQueries = [
        '/api/db/readonly/user-stats',
        '/api/db/readonly/workspace-summary',
        '/api/db/readonly/analytics-dashboard',
        '/api/db/readonly/search-index'
      ];
      
      const endpoint = readQueries[Math.floor(Math.random() * readQueries.length)];
      
      const startTime = Date.now();
      const response = http.get(`${data.baseUrl}${endpoint}`, {
        headers: { ...headers, 'X-Read-Preference': 'replica' },
        timeout: '30s',
        tags: { query_type: 'read_replica' }
      });
      
      const readLatency = Date.now() - startTime;
      dbMetrics.readWriteLatency.add(readLatency);
      
      check(response, {
        'read replica responsive': (r) => r.status === 200,
        'fast read response': (r) => r.timings.duration < 1000,
      });
      
      // Check for replication lag indicators
      if (response.headers['X-Replication-Lag']) {
        const lagMs = parseInt(response.headers['X-Replication-Lag']);
        dbMetrics.replicationLag.add(lagMs);
      }
      
    } else {
      // Write operation (must go to primary)
      const writeData = {
        name: `RW Split Test ${Date.now()}`,
        data: { test: 'read_write_split', timestamp: Date.now() }
      };
      
      const startTime = Date.now();
      const response = http.post(`${data.baseUrl}/api/db/records`,
        JSON.stringify(writeData),
        {
          headers: { ...headers, 'X-Write-Preference': 'primary' },
          timeout: '30s',
          tags: { query_type: 'write_primary' }
        }
      );
      
      const writeLatency = Date.now() - startTime;
      dbMetrics.readWriteLatency.add(writeLatency);
      
      check(response, {
        'write to primary successful': (r) => r.status === 201,
        'reasonable write latency': (r) => r.timings.duration < 2000,
      });
    }
  });
}

function longRunningQueriesTest(data, headers) {
  group('Long Running Queries Test', () => {
    const longQueries = [
      {
        name: 'historical_analytics',
        endpoint: '/api/db/analytics/historical-report',
        payload: {
          date_range: '365d',
          granularity: 'daily',
          include_trends: true,
          compute_forecasts: true
        }
      },
      {
        name: 'data_export',
        endpoint: '/api/db/export/comprehensive',
        payload: {
          format: 'json',
          include_relationships: true,
          include_metadata: true,
          compression: 'gzip'
        }
      },
      {
        name: 'complex_aggregation',
        endpoint: '/api/db/reports/complex-metrics',
        payload: {
          metrics: ['user_engagement', 'workspace_utilization', 'api_performance'],
          group_by: ['date', 'workspace', 'user_type'],
          include_percentiles: true
        }
      }
    ];
    
    const query = longQueries[Math.floor(Math.random() * longQueries.length)];
    
    const startTime = Date.now();
    const response = http.post(`${data.baseUrl}${query.endpoint}`,
      JSON.stringify(query.payload),
      {
        headers: { ...headers, 'X-Long-Query': query.name },
        timeout: '300s', // 5 minutes for long queries
        tags: { query_type: 'long_running' }
      }
    );
    
    const queryTime = Date.now() - startTime;
    
    const success = check(response, {
      'long query completed': (r) => r.status === 200,
      'query within timeout': (r) => r.timings.duration < 300000,
      'no query timeout': (r) => r.status !== 408,
    });
    
    if (queryTime > 30000) { // Queries over 30 seconds are considered slow
      dbMetrics.slowQueries.add(1);
    }
    
    console.log(`Long query ${query.name}: ${queryTime}ms, success: ${success}`);
  });
}

function indexPerformanceTest(data, headers) {
  group('Index Performance Test', () => {
    // Test various query patterns to evaluate index usage
    const indexTests = [
      {
        name: 'primary_key_lookup',
        endpoint: '/api/db/index-test/pk-lookup',
        payload: { id: Math.floor(Math.random() * 1000000) }
      },
      {
        name: 'composite_index',
        endpoint: '/api/db/index-test/composite',
        payload: { 
          workspace_id: Math.floor(Math.random() * 1000),
          status: ['active', 'pending'][Math.floor(Math.random() * 2)],
          created_date: '2024-01-01'
        }
      },
      {
        name: 'partial_index',
        endpoint: '/api/db/index-test/partial',
        payload: { 
          active_only: true,
          category: 'test'
        }
      },
      {
        name: 'full_text_index',
        endpoint: '/api/db/index-test/fulltext',
        payload: { 
          search_query: 'performance test database',
          language: 'english'
        }
      }
    ];
    
    const test = indexTests[Math.floor(Math.random() * indexTests.length)];
    
    const startTime = Date.now();
    const response = http.post(`${data.baseUrl}${test.endpoint}`,
      JSON.stringify(test.payload),
      {
        headers: { ...headers, 'X-Index-Test': test.name },
        timeout: '30s',
        tags: { query_type: 'index_test' }
      }
    );
    
    const queryTime = Date.now() - startTime;
    
    const success = check(response, {
      'index query successful': (r) => r.status === 200,
      'fast index response': (r) => r.timings.duration < 1000,
    });
    
    // Check for index usage indicators in response headers
    if (response.headers['X-Index-Hit']) {
      dbMetrics.indexHitRate.add(response.headers['X-Index-Hit'] === 'true');
    }
    
    if (response.headers['X-Cache-Hit']) {
      dbMetrics.cacheHitRate.add(response.headers['X-Cache-Hit'] === 'true');
    }
    
    // Record query time by index type
    switch (test.name) {
      case 'primary_key_lookup':
        if (queryTime > 10) dbMetrics.slowQueries.add(1); // PK should be <10ms
        break;
      case 'composite_index':
        if (queryTime > 50) dbMetrics.slowQueries.add(1); // Composite <50ms
        break;
      case 'full_text_index':
        if (queryTime > 500) dbMetrics.slowQueries.add(1); // Full-text <500ms
        break;
    }
  });
}

function concurrentAccessTest(data, headers) {
  group('Concurrent Access Test', () => {
    // Simulate concurrent access to the same resources
    const resourceId = Math.floor(Math.random() * 100); // Limited resource pool
    const operations = ['read', 'update', 'delete'];
    const operation = operations[Math.floor(Math.random() * operations.length)];
    
    let endpoint, method, payload;
    
    switch (operation) {
      case 'read':
        endpoint = `/api/db/concurrent/resource/${resourceId}`;
        method = 'GET';
        break;
      case 'update':
        endpoint = `/api/db/concurrent/resource/${resourceId}`;
        method = 'PATCH';
        payload = { 
          data: `concurrent_update_${Date.now()}`,
          version: Math.floor(Math.random() * 10) // Optimistic locking
        };
        break;
      case 'delete':
        endpoint = `/api/db/concurrent/resource/${resourceId}`;
        method = 'DELETE';
        break;
    }
    
    const startTime = Date.now();
    const response = http.request(method, `${data.baseUrl}${endpoint}`,
      payload ? JSON.stringify(payload) : null,
      {
        headers: { 
          ...headers, 
          'X-Concurrent-Test': operation,
          'X-Resource-ID': resourceId.toString()
        },
        timeout: '30s',
        tags: { query_type: 'concurrent_access', operation: operation }
      }
    );
    
    const success = check(response, {
      'concurrent operation successful': (r) => r.status < 500,
      'no deadlock detected': (r) => r.status !== 409,
      'no lock timeout': (r) => r.status !== 408,
    });
    
    if (!success) {
      if (response.status === 409) {
        console.log(`Concurrent access conflict on resource ${resourceId}`);
      } else if (response.status === 408) {
        console.log(`Lock timeout on resource ${resourceId}`);
      }
    }
  });
}

function executeQuery(data, headers, query, queryType) {
  const url = query.endpoint.replace('{id}', Math.floor(Math.random() * 1000))
                           .replace('{user_id}', Math.floor(Math.random() * 100))
                           .replace('{workspace_id}', Math.floor(Math.random() * 50));
  
  const startTime = Date.now();
  let response;
  
  if (query.method === 'GET') {
    response = http.get(`${data.baseUrl}${url}`, {
      headers: { ...headers, 'X-Query-Type': queryType },
      timeout: '60s',
      tags: { query_type: queryType, query_name: query.name }
    });
  } else {
    response = http.post(`${data.baseUrl}${url}`,
      JSON.stringify(query.payload || {}),
      {
        headers: { ...headers, 'X-Query-Type': queryType },
        timeout: '60s',
        tags: { query_type: queryType, query_name: query.name }
      }
    );
  }
  
  const queryTime = Date.now() - startTime;
  
  // Record metrics based on query type
  switch (queryType) {
    case 'simple':
      dbMetrics.simpleQueryTime.add(queryTime);
      break;
    case 'complex':
      dbMetrics.complexQueryTime.add(queryTime);
      break;
    case 'aggregation':
      dbMetrics.aggregationQueryTime.add(queryTime);
      break;
  }
  
  if (query.name && query.name.includes('search')) {
    dbMetrics.fullTextSearchTime.add(queryTime);
  }
  
  const success = check(response, {
    'query executed successfully': (r) => r.status === 200,
    'query within expected time': (r) => {
      const expectedTime = queryType === 'simple' ? 100 : 
                          queryType === 'complex' ? 1000 : 5000;
      return r.timings.duration < expectedTime;
    },
  });
  
  if (!success) {
    console.log(`Query failed: ${query.name} (${queryType}) - ${response.status}: ${response.body?.substring(0, 100)}`);
  }
}

function updateConnectionPoolStats(data, headers) {
  // Periodically get connection pool statistics
  if (__ITER % 10 === 0) {
    const response = http.get(`${data.baseUrl}/api/db/pool/stats`, {
      headers,
      timeout: '5s'
    });
    
    if (response.status === 200 && response.json) {
      const stats = response.json();
      connectionPoolStats.activeConnections = stats.active || 0;
      connectionPoolStats.peakConnections = Math.max(
        connectionPoolStats.peakConnections, 
        stats.active || 0
      );
      
      dbMetrics.activeConnections.add(stats.active || 0);
      dbMetrics.poolUtilization.add((stats.active || 0) / MAX_CONNECTIONS);
    }
  }
}

// Helper functions for bulk data generation
function generateBulkInsertData(size) {
  const records = [];
  for (let i = 0; i < size; i++) {
    records.push({
      name: `Bulk Insert Record ${i}_${Date.now()}`,
      value: Math.floor(Math.random() * 1000),
      category: `category_${Math.floor(Math.random() * 10)}`,
      status: ['active', 'pending', 'processing'][Math.floor(Math.random() * 3)],
      data: {
        test_field: `test_value_${i}`,
        numeric_field: Math.random() * 100,
        boolean_field: Math.random() > 0.5
      }
    });
  }
  return { records };
}

function generateBulkUpdateData(size) {
  const updates = [];
  for (let i = 0; i < size; i++) {
    updates.push({
      id: Math.floor(Math.random() * 10000),
      data: {
        status: 'updated',
        last_modified: new Date().toISOString(),
        update_count: Math.floor(Math.random() * 10)
      }
    });
  }
  return { updates };
}

function generateBulkDeleteData(size) {
  const ids = [];
  for (let i = 0; i < size; i++) {
    ids.push(Math.floor(Math.random() * 10000));
  }
  return { ids };
}

export function teardown(data) {
  const duration = (Date.now() - data.startTime) / 1000;
  console.log(`\nDatabase Performance Testing completed in ${duration}s`);
  console.log(`Test Mode: ${DB_TEST_MODE}`);
  console.log(`Peak Connections: ${connectionPoolStats.peakConnections}/${MAX_CONNECTIONS}`);
  console.log(`Connection Timeouts: ${connectionPoolStats.connectionTimeouts}`);
  
  // Cleanup test data
  http.post(`${data.baseUrl}/api/db/test/cleanup`, '{}', {
    headers: { 'Content-Type': 'application/json', 'X-API-Key': data.apiKey },
    timeout: '60s'
  });
}

export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const mode = DB_TEST_MODE;
  
  return {
    [`database-performance-report-${mode}-${timestamp}.html`]: htmlReport(data, {
      title: `PyAirtable Database Performance Report - ${mode.toUpperCase()}`,
      description: 'Comprehensive database performance and connection pool testing'
    }),
    [`database-performance-results-${mode}-${timestamp}.json`]: JSON.stringify({
      ...data,
      connectionPoolStats: connectionPoolStats,
      testConfiguration: {
        mode: DB_TEST_MODE,
        maxConnections: MAX_CONNECTIONS,
        bulkSize: config.bulkSize,
        queryComplexity: config.queryComplexity
      }
    }, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}