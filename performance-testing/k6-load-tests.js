// K6 Load Testing Suite for PyAirtable
// Comprehensive performance testing with realistic user scenarios

import http from 'k6/http';
import ws from 'k6/ws';
import { check, group, fail } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';
import { jUnit, textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// Custom metrics
export const errorRate = new Rate('errors');
export const apiResponseTime = new Trend('api_response_time');
export const dbQueryTime = new Trend('db_query_time');
export const cacheHitRate = new Rate('cache_hits');
export const wsConnectionTime = new Trend('websocket_connection_time');
export const concurrentUsers = new Gauge('concurrent_users');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const WS_URL = __ENV.WS_URL || 'ws://localhost:8000';
const API_KEY = __ENV.API_KEY || 'test-api-key';

// Test data
const TEST_USERS = JSON.parse(open('./test-data/users.json'));
const TEST_WORKSPACES = JSON.parse(open('./test-data/workspaces.json'));
const TEST_TABLES = JSON.parse(open('./test-data/tables.json'));

// Test scenarios configuration
export const options = {
  scenarios: {
    // Smoke test - minimal load
    smoke_test: {
      executor: 'constant-vus',
      vus: 1,
      duration: '1m',
      tags: { test_type: 'smoke' },
    },
    
    // Load test - normal expected load
    load_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5m', target: 20 },   // Ramp up
        { duration: '10m', target: 20 },  // Stay at 20 users
        { duration: '5m', target: 0 },    // Ramp down
      ],
      tags: { test_type: 'load' },
    },
    
    // Stress test - above normal load
    stress_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },   // Ramp up to stress level
        { duration: '5m', target: 50 },   // Stay at stress level
        { duration: '2m', target: 100 },  // Ramp up to high stress
        { duration: '3m', target: 100 },  // Stay at high stress
        { duration: '2m', target: 0 },    // Ramp down
      ],
      tags: { test_type: 'stress' },
    },
    
    // Spike test - sudden load increase
    spike_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 100 }, // Fast ramp up
        { duration: '1m', target: 100 },  // Stay at spike
        { duration: '10s', target: 0 },   // Fast ramp down
      ],
      tags: { test_type: 'spike' },
    },
    
    // Volume test - large amount of data
    volume_test: {
      executor: 'constant-vus',
      vus: 10,
      duration: '30m',
      tags: { test_type: 'volume' },
    },
    
    // Soak test - extended duration
    soak_test: {
      executor: 'constant-vus',
      vus: 10,
      duration: '2h',
      tags: { test_type: 'soak' },
    },
    
    // API focused test
    api_test: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { duration: '5m', target: 50 },   // Ramp up to 50 RPS
        { duration: '10m', target: 50 },  // Stay at 50 RPS
        { duration: '5m', target: 100 },  // Ramp up to 100 RPS
        { duration: '10m', target: 100 }, // Stay at 100 RPS
        { duration: '5m', target: 0 },    // Ramp down
      ],
      tags: { test_type: 'api' },
    },
    
    // Database intensive test
    database_test: {
      executor: 'constant-vus',
      vus: 15,
      duration: '15m',
      tags: { test_type: 'database' },
    },
    
    // Cache performance test
    cache_test: {
      executor: 'constant-vus',
      vus: 25,
      duration: '10m',
      tags: { test_type: 'cache' },
    },
    
    // WebSocket test
    websocket_test: {
      executor: 'constant-vus',
      vus: 20,
      duration: '10m',
      tags: { test_type: 'websocket' },
    },
  },
  
  // Test thresholds for pass/fail criteria
  thresholds: {
    // Overall system thresholds
    http_req_duration: ['p(95)<2000', 'p(99)<5000'], // 95% under 2s, 99% under 5s
    http_req_failed: ['rate<0.1'],                    // Error rate under 10%
    
    // Custom metrics thresholds
    api_response_time: ['p(95)<1000'],                // API calls under 1s
    db_query_time: ['p(95)<500'],                     // DB queries under 500ms
    cache_hits: ['rate>0.8'],                        // Cache hit rate above 80%
    
    // Scenario-specific thresholds
    'http_req_duration{test_type:smoke}': ['p(95)<1000'],
    'http_req_duration{test_type:load}': ['p(95)<2000'],
    'http_req_duration{test_type:stress}': ['p(95)<5000'],
    'http_req_failed{test_type:smoke}': ['rate<0.01'],
    'http_req_failed{test_type:load}': ['rate<0.05'],
    'http_req_failed{test_type:stress}': ['rate<0.15'],
  },
  
  // Global settings
  userAgent: 'PyAirtable-LoadTest/1.0',
  insecureSkipTLSVerify: true,
  noConnectionReuse: false,
  
  // Tags for all requests
  tags: {
    environment: __ENV.ENVIRONMENT || 'test',
    version: __ENV.VERSION || 'latest',
  },
};

// Setup function - runs once before all scenarios
export function setup() {
  console.log('Starting PyAirtable Load Test Suite');
  console.log(`Target URL: ${BASE_URL}`);
  console.log(`Test Environment: ${__ENV.ENVIRONMENT || 'test'}`);
  
  // Warm up the system
  group('System Warmup', () => {
    const warmupResponse = http.get(`${BASE_URL}/api/health`);
    check(warmupResponse, {
      'warmup successful': (r) => r.status === 200,
    });
  });
  
  // Return data for use in main function
  return {
    baseUrl: BASE_URL,
    apiKey: API_KEY,
    timestamp: new Date().toISOString(),
  };
}

// Main test function
export default function (data) {
  const testType = __ENV.K6_SCENARIO || 'load_test';
  concurrentUsers.add(1);
  
  // Select test user
  const user = TEST_USERS[Math.floor(Math.random() * TEST_USERS.length)];
  
  group('User Authentication Flow', () => {
    authenticationFlow(data, user);
  });
  
  group('Core Application Usage', () => {
    switch (testType) {
      case 'smoke_test':
        smokeTestScenario(data, user);
        break;
      case 'api_test':
        apiTestScenario(data, user);
        break;
      case 'database_test':
        databaseTestScenario(data, user);
        break;
      case 'cache_test':
        cacheTestScenario(data, user);
        break;
      case 'websocket_test':
        websocketTestScenario(data, user);
        break;
      default:
        standardUserScenario(data, user);
    }
  });
  
  // Random think time between actions
  sleep(Math.random() * 3 + 1); // 1-4 seconds
}

// Authentication flow
function authenticationFlow(data, user) {
  const loginPayload = {
    email: user.email,
    password: user.password,
  };
  
  const loginResponse = http.post(`${data.baseUrl}/api/auth/login`, JSON.stringify(loginPayload), {
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': data.apiKey,
    },
    tags: { endpoint: 'auth_login' },
  });
  
  check(loginResponse, {
    'login successful': (r) => r.status === 200,
    'has auth token': (r) => r.json('token') !== undefined,
  }) || errorRate.add(1);
  
  apiResponseTime.add(loginResponse.timings.duration);
  
  if (loginResponse.status === 200) {
    user.token = loginResponse.json('token');
  }
}

// Standard user scenario - typical user behavior
function standardUserScenario(data, user) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.token}`,
    'X-API-Key': data.apiKey,
  };
  
  // 1. Get user profile
  group('Get User Profile', () => {
    const response = http.get(`${data.baseUrl}/api/users/profile`, {
      headers,
      tags: { endpoint: 'user_profile' },
    });
    
    check(response, {
      'profile loaded': (r) => r.status === 200,
    }) || errorRate.add(1);
    
    apiResponseTime.add(response.timings.duration);
  });
  
  // 2. List workspaces
  group('List Workspaces', () => {
    const response = http.get(`${data.baseUrl}/api/workspaces`, {
      headers,
      tags: { endpoint: 'list_workspaces' },
    });
    
    check(response, {
      'workspaces loaded': (r) => r.status === 200,
      'has workspaces': (r) => r.json('data.length') > 0,
    }) || errorRate.add(1);
    
    apiResponseTime.add(response.timings.duration);
    user.workspaces = response.json('data') || [];
  });
  
  // 3. Select and work with a workspace
  if (user.workspaces && user.workspaces.length > 0) {
    const workspace = user.workspaces[Math.floor(Math.random() * user.workspaces.length)];
    
    group('Workspace Operations', () => {
      // Get workspace details
      const workspaceResponse = http.get(`${data.baseUrl}/api/workspaces/${workspace.id}`, {
        headers,
        tags: { endpoint: 'workspace_details' },
      });
      
      check(workspaceResponse, {
        'workspace details loaded': (r) => r.status === 200,
      }) || errorRate.add(1);
      
      // List tables in workspace
      const tablesResponse = http.get(`${data.baseUrl}/api/workspaces/${workspace.id}/tables`, {
        headers,
        tags: { endpoint: 'list_tables' },
      });
      
      check(tablesResponse, {
        'tables loaded': (r) => r.status === 200,
      }) || errorRate.add(1);
      
      const tables = tablesResponse.json('data') || [];
      
      // Work with a table if available
      if (tables.length > 0) {
        const table = tables[Math.floor(Math.random() * tables.length)];
        tableOperations(data, user, workspace.id, table.id, headers);
      }
    });
  }
  
  sleep(1 + Math.random() * 2); // Think time
}

// Table operations - CRUD operations on tables
function tableOperations(data, user, workspaceId, tableId, headers) {
  group('Table Operations', () => {
    // Get table records
    const recordsResponse = http.get(
      `${data.baseUrl}/api/workspaces/${workspaceId}/tables/${tableId}/records`,
      {
        headers,
        tags: { endpoint: 'get_records' },
      }
    );
    
    check(recordsResponse, {
      'records loaded': (r) => r.status === 200,
    }) || errorRate.add(1);
    
    dbQueryTime.add(recordsResponse.timings.duration);
    
    // Create a new record
    const newRecord = {
      fields: {
        Name: `Test Record ${Date.now()}`,
        Description: 'Generated by load test',
        Status: 'Active',
        Priority: Math.floor(Math.random() * 5) + 1,
      },
    };
    
    const createResponse = http.post(
      `${data.baseUrl}/api/workspaces/${workspaceId}/tables/${tableId}/records`,
      JSON.stringify(newRecord),
      {
        headers,
        tags: { endpoint: 'create_record' },
      }
    );
    
    check(createResponse, {
      'record created': (r) => r.status === 201,
      'has record id': (r) => r.json('id') !== undefined,
    }) || errorRate.add(1);
    
    dbQueryTime.add(createResponse.timings.duration);
    
    // Update the record if creation was successful
    if (createResponse.status === 201) {
      const recordId = createResponse.json('id');
      const updateData = {
        fields: {
          Description: 'Updated by load test',
          Status: 'Updated',
        },
      };
      
      const updateResponse = http.patch(
        `${data.baseUrl}/api/workspaces/${workspaceId}/tables/${tableId}/records/${recordId}`,
        JSON.stringify(updateData),
        {
          headers,
          tags: { endpoint: 'update_record' },
        }
      );
      
      check(updateResponse, {
        'record updated': (r) => r.status === 200,
      }) || errorRate.add(1);
      
      dbQueryTime.add(updateResponse.timings.duration);
    }
  });
}

// API-focused test scenario
function apiTestScenario(data, user) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.token}`,
    'X-API-Key': data.apiKey,
  };
  
  // Test various API endpoints with different loads
  const endpoints = [
    { method: 'GET', url: '/api/users/profile', weight: 0.3 },
    { method: 'GET', url: '/api/workspaces', weight: 0.2 },
    { method: 'GET', url: '/api/analytics/dashboard', weight: 0.15 },
    { method: 'GET', url: '/api/notifications', weight: 0.1 },
    { method: 'POST', url: '/api/search', weight: 0.15, payload: { query: 'test', limit: 10 } },
    { method: 'GET', url: '/api/settings', weight: 0.1 },
  ];
  
  // Select endpoint based on weight
  const random = Math.random();
  let cumulativeWeight = 0;
  let selectedEndpoint = endpoints[0];
  
  for (const endpoint of endpoints) {
    cumulativeWeight += endpoint.weight;
    if (random <= cumulativeWeight) {
      selectedEndpoint = endpoint;
      break;
    }
  }
  
  // Make API call
  let response;
  if (selectedEndpoint.method === 'GET') {
    response = http.get(`${data.baseUrl}${selectedEndpoint.url}`, {
      headers,
      tags: { endpoint: selectedEndpoint.url },
    });
  } else {
    response = http.post(
      `${data.baseUrl}${selectedEndpoint.url}`,
      JSON.stringify(selectedEndpoint.payload || {}),
      {
        headers,
        tags: { endpoint: selectedEndpoint.url },
      }
    );
  }
  
  check(response, {
    'api call successful': (r) => r.status >= 200 && r.status < 300,
  }) || errorRate.add(1);
  
  apiResponseTime.add(response.timings.duration);
  
  // Check for cache headers
  if (response.headers['X-Cache']) {
    cacheHitRate.add(response.headers['X-Cache'] === 'HIT' ? 1 : 0);
  }
}

// Database-intensive test scenario
function databaseTestScenario(data, user) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.token}`,
    'X-API-Key': data.apiKey,
  };
  
  // Complex database operations
  group('Complex Database Queries', () => {
    // Large dataset query
    const largeQueryResponse = http.get(
      `${data.baseUrl}/api/analytics/reports/large-dataset?limit=1000&offset=${Math.floor(Math.random() * 10000)}`,
      {
        headers,
        tags: { endpoint: 'large_query' },
      }
    );
    
    check(largeQueryResponse, {
      'large query successful': (r) => r.status === 200,
    }) || errorRate.add(1);
    
    dbQueryTime.add(largeQueryResponse.timings.duration);
    
    // Aggregation query
    const aggregationResponse = http.get(
      `${data.baseUrl}/api/analytics/aggregations?groupBy=status&timeRange=30d`,
      {
        headers,
        tags: { endpoint: 'aggregation_query' },
      }
    );
    
    check(aggregationResponse, {
      'aggregation query successful': (r) => r.status === 200,
    }) || errorRate.add(1);
    
    dbQueryTime.add(aggregationResponse.timings.duration);
    
    // Full-text search
    const searchResponse = http.post(
      `${data.baseUrl}/api/search/fulltext`,
      JSON.stringify({
        query: 'test search query',
        filters: { status: 'active' },
        limit: 50,
      }),
      {
        headers,
        tags: { endpoint: 'fulltext_search' },
      }
    );
    
    check(searchResponse, {
      'search query successful': (r) => r.status === 200,
    }) || errorRate.add(1);
    
    dbQueryTime.add(searchResponse.timings.duration);
  });
}

// Cache performance test scenario
function cacheTestScenario(data, user) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.token}`,
    'X-API-Key': data.apiKey,
  };
  
  // Test cache behavior with repeated requests
  const cacheableEndpoints = [
    '/api/users/profile',
    '/api/workspaces',
    '/api/settings',
    '/api/notifications/unread-count',
  ];
  
  const endpoint = cacheableEndpoints[Math.floor(Math.random() * cacheableEndpoints.length)];
  
  // Make multiple requests to test cache
  for (let i = 0; i < 3; i++) {
    const response = http.get(`${data.baseUrl}${endpoint}`, {
      headers,
      tags: { endpoint: 'cache_test' },
    });
    
    check(response, {
      'cache request successful': (r) => r.status === 200,
    }) || errorRate.add(1);
    
    // Track cache hits
    if (response.headers['X-Cache']) {
      cacheHitRate.add(response.headers['X-Cache'] === 'HIT' ? 1 : 0);
    }
    
    apiResponseTime.add(response.timings.duration);
    
    // Small delay between requests
    sleep(0.1);
  }
}

// WebSocket test scenario
function websocketTestScenario(data, user) {
  const wsUrl = `${WS_URL}/ws?token=${user.token}`;
  
  const response = ws.connect(wsUrl, {
    tags: { endpoint: 'websocket' },
  }, function (socket) {
    const startTime = new Date().getTime();
    
    socket.on('open', () => {
      wsConnectionTime.add(new Date().getTime() - startTime);
      
      // Send some messages
      socket.send(JSON.stringify({
        type: 'subscribe',
        channels: ['workspace.updates', 'notifications'],
      }));
      
      socket.send(JSON.stringify({
        type: 'ping',
        timestamp: Date.now(),
      }));
    });
    
    socket.on('message', (message) => {
      const data = JSON.parse(message);
      
      check(data, {
        'websocket message valid': (msg) => msg.type !== undefined,
      }) || errorRate.add(1);
      
      if (data.type === 'pong') {
        const latency = Date.now() - data.timestamp;
        wsConnectionTime.add(latency);
      }
    });
    
    socket.on('error', (e) => {
      console.log('WebSocket error:', e);
      errorRate.add(1);
    });
    
    // Keep connection open for a while
    socket.setTimeout(() => {
      socket.close();
    }, 30000); // 30 seconds
  });
  
  check(response, {
    'websocket connection successful': (r) => r && r.status === 101,
  }) || errorRate.add(1);
}

// Smoke test scenario - basic functionality check
function smokeTestScenario(data, user) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.token}`,
    'X-API-Key': data.apiKey,
  };
  
  // Basic health checks
  const healthResponse = http.get(`${data.baseUrl}/api/health`, {
    headers,
    tags: { endpoint: 'health_check' },
  });
  
  check(healthResponse, {
    'health check successful': (r) => r.status === 200,
    'response time under 500ms': (r) => r.timings.duration < 500,
  }) || errorRate.add(1);
  
  // Basic user profile check
  const profileResponse = http.get(`${data.baseUrl}/api/users/profile`, {
    headers,
    tags: { endpoint: 'profile_check' },
  });
  
  check(profileResponse, {
    'profile check successful': (r) => r.status === 200,
    'response time under 1s': (r) => r.timings.duration < 1000,
  }) || errorRate.add(1);
}

// Teardown function - runs once after all scenarios
export function teardown(data) {
  console.log('PyAirtable Load Test Suite completed');
  console.log(`Test duration: ${new Date().toISOString()}`);
}

// Custom summary report
export function handleSummary(data) {
  return {
    'performance-test-report.html': htmlReport(data),
    'performance-test-results.xml': jUnit(data),
    'performance-test-summary.txt': textSummary(data, { indent: ' ', enableColors: true }),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}

// Utility function for sleep
function sleep(duration) {
  if (typeof duration === 'number') {
    k6.sleep(duration);
  }
}