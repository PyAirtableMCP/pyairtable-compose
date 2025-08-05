// Advanced K6 Stress Testing Scenarios for PyAirtable Platform
// Designed to push system beyond normal limits to find breaking points

import http from 'k6/http';
import ws from 'k6/ws';
import { check, group, fail } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// Custom metrics for stress testing
export const errorRate = new Rate('stress_errors');
export const responseTime = new Trend('stress_response_time');
export const concurrentConnections = new Gauge('concurrent_connections');
export const memoryPressure = new Gauge('memory_pressure_indicator');
export const cpuPressure = new Gauge('cpu_pressure_indicator');
export const failurePoints = new Counter('system_failure_points');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const WS_URL = __ENV.WS_URL || 'ws://localhost:8000';
const API_KEY = __ENV.API_KEY || 'test-api-key';
const STRESS_LEVEL = __ENV.STRESS_LEVEL || 'medium'; // low, medium, high, extreme

// Stress test configurations
const stressConfigs = {
  low: {
    maxUsers: 200,
    rampUpTime: '5m',
    plateauTime: '10m',
    rpsTarget: 500,
    dataMultiplier: 2
  },
  medium: {
    maxUsers: 500,
    rampUpTime: '3m',
    plateauTime: '15m',
    rpsTarget: 1500,
    dataMultiplier: 5
  },
  high: {
    maxUsers: 1000,
    rampUpTime: '2m',
    plateauTime: '20m',
    rpsTarget: 3000,
    dataMultiplier: 10
  },
  extreme: {
    maxUsers: 2000,
    rampUpTime: '1m',
    plateauTime: '30m',
    rpsTarget: 5000,
    dataMultiplier: 20
  }
};

const config = stressConfigs[STRESS_LEVEL];

export const options = {
  scenarios: {
    // Gradual stress ramp - find breaking point gradually
    gradual_stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: config.rampUpTime, target: Math.floor(config.maxUsers * 0.3) },
        { duration: '5m', target: Math.floor(config.maxUsers * 0.3) },
        { duration: '2m', target: Math.floor(config.maxUsers * 0.6) },
        { duration: '5m', target: Math.floor(config.maxUsers * 0.6) },
        { duration: '2m', target: config.maxUsers },
        { duration: config.plateauTime, target: config.maxUsers },
        { duration: '5m', target: 0 },
      ],
      tags: { scenario: 'gradual_stress' },
    },

    // Spike stress - sudden load increase
    spike_stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: config.maxUsers },
        { duration: '5m', target: config.maxUsers },
        { duration: '30s', target: 0 },
        { duration: '2m', target: 0 },
        { duration: '30s', target: Math.floor(config.maxUsers * 1.5) }, // Over capacity
        { duration: '3m', target: Math.floor(config.maxUsers * 1.5) },
        { duration: '30s', target: 0 },
      ],
      tags: { scenario: 'spike_stress' },
    },

    // Constant high load
    constant_stress: {
      executor: 'constant-vus',
      vus: Math.floor(config.maxUsers * 0.8),
      duration: '20m',
      tags: { scenario: 'constant_stress' },
    },

    // Rate-based stress test
    rate_stress: {
      executor: 'constant-arrival-rate',
      rate: config.rpsTarget,
      timeUnit: '1s',
      duration: '15m',
      preAllocatedVUs: Math.floor(config.maxUsers * 0.5),
      maxVUs: config.maxUsers,
      tags: { scenario: 'rate_stress' },
    },

    // Memory pressure test
    memory_pressure: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 100 },
        { duration: '10m', target: 100 },
      ],
      tags: { scenario: 'memory_pressure' },
    },

    // Database stress test
    database_stress: {
      executor: 'constant-vus',
      vus: Math.floor(config.maxUsers * 0.4),
      duration: '25m',
      tags: { scenario: 'database_stress' },
    },

    // WebSocket stress test
    websocket_stress: {
      executor: 'constant-vus',
      vus: Math.floor(config.maxUsers * 0.3),
      duration: '15m',
      tags: { scenario: 'websocket_stress' },
    },

    // Cache invalidation stress
    cache_stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 200 },
        { duration: '10m', target: 200 },
        { duration: '1m', target: 0 },
      ],
      tags: { scenario: 'cache_stress' },
    },
  },

  // Aggressive thresholds for stress testing
  thresholds: {
    // System should handle stress but may have degraded performance
    http_req_duration: [
      'p(50)<1000',    // 50% under 1s (degraded from normal)
      'p(95)<5000',    // 95% under 5s (degraded from normal)
      'p(99)<10000'    // 99% under 10s (emergency threshold)
    ],
    http_req_failed: ['rate<0.2'],  // Allow up to 20% errors under extreme stress
    
    // Scenario-specific thresholds
    'http_req_duration{scenario:gradual_stress}': ['p(95)<8000'],
    'http_req_duration{scenario:spike_stress}': ['p(95)<15000'],
    'http_req_duration{scenario:constant_stress}': ['p(95)<6000'],
    'http_req_failed{scenario:gradual_stress}': ['rate<0.15'],
    'http_req_failed{scenario:spike_stress}': ['rate<0.3'],
    'http_req_failed{scenario:constant_stress}': ['rate<0.1'],
  },

  // Extended timeouts for stress conditions
  timeout: '120s',
  insecureSkipTLSVerify: true,
  userAgent: 'K6-StressTesting/1.0',
};

// Test data generators for high load
function generateLargePayload(multiplier = 1) {
  const baseSize = 1000 * multiplier;
  const data = {
    fields: {},
    metadata: {
      timestamp: new Date().toISOString(),
      source: 'stress-test',
      batch_id: `batch_${__VU}_${__ITER}`,
    }
  };
  
  // Generate large field data
  for (let i = 0; i < baseSize; i++) {
    data.fields[`field_${i}`] = `value_${i}_${'x'.repeat(Math.floor(Math.random() * 100))}`;
  }
  
  return data;
}

function generateBulkRecords(count) {
  const records = [];
  for (let i = 0; i < count; i++) {
    records.push({
      fields: {
        Name: `Stress Record ${i}_${Date.now()}`,
        Description: `Bulk stress test record ${i}`,
        Status: ['Active', 'Pending', 'Processing', 'Completed'][Math.floor(Math.random() * 4)],
        Priority: Math.floor(Math.random() * 10) + 1,
        Category: `Category_${Math.floor(Math.random() * 50)}`,
        Tags: Array.from({length: Math.floor(Math.random() * 10)}, (_, idx) => `tag${idx}`),
        Data: 'x'.repeat(Math.floor(Math.random() * 1000)), // Variable size data
      }
    });
  }
  return records;
}

export function setup() {
  console.log(`Starting Stress Test Suite - Level: ${STRESS_LEVEL}`);
  console.log(`Target: ${BASE_URL}`);
  console.log(`Max Users: ${config.maxUsers}, Target RPS: ${config.rpsTarget}`);
  
  // Pre-warm the system
  const warmupResponse = http.get(`${BASE_URL}/api/health`);
  check(warmupResponse, {
    'system available for stress test': (r) => r.status === 200,
  });
  
  return {
    baseUrl: BASE_URL,
    apiKey: API_KEY,
    config: config,
    startTime: Date.now(),
  };
}

export default function(data) {
  const scenario = __ENV.K6_SCENARIO || 'gradual_stress';
  concurrentConnections.add(1);
  
  // Authenticate (with retry for stress conditions)
  const authToken = authenticateWithRetry(data);
  if (!authToken) {
    failurePoints.add(1);
    return;
  }
  
  const headers = {
    'Authorization': `Bearer ${authToken}`,
    'Content-Type': 'application/json',
    'X-API-Key': data.apiKey,
  };
  
  // Execute scenario-specific stress tests
  switch (scenario) {
    case 'gradual_stress':
      gradualStressScenario(data, headers);
      break;
    case 'spike_stress':
      spikeStressScenario(data, headers);
      break;
    case 'memory_pressure':
      memoryPressureScenario(data, headers);
      break;
    case 'database_stress':
      databaseStressScenario(data, headers);
      break;
    case 'websocket_stress':
      websocketStressScenario(data, headers);
      break;
    case 'cache_stress':
      cacheStressScenario(data, headers);
      break;
    default:
      standardStressScenario(data, headers);
  }
  
  // Minimal think time for stress testing
  sleep(Math.random() * 0.5);
}

function authenticateWithRetry(data, maxRetries = 3) {
  const testUsers = [
    { email: 'stress1@test.com', password: 'stress123' },
    { email: 'stress2@test.com', password: 'stress123' },
    { email: 'stress3@test.com', password: 'stress123' },
  ];
  
  const user = testUsers[Math.floor(Math.random() * testUsers.length)];
  
  for (let retry = 0; retry < maxRetries; retry++) {
    const response = http.post(`${data.baseUrl}/api/auth/login`, JSON.stringify(user), {
      headers: { 'Content-Type': 'application/json', 'X-API-Key': data.apiKey },
      timeout: '30s',
    });
    
    if (response.status === 200) {
      return response.json('token');
    }
    
    if (retry < maxRetries - 1) {
      sleep(Math.pow(2, retry)); // Exponential backoff
    }
  }
  
  return null;
}

function gradualStressScenario(data, headers) {
  group('Gradual Stress - Standard Operations', () => {
    // Mix of operations with increasing complexity
    const operations = [
      () => quickHealthCheck(data, headers),
      () => userProfileOperations(data, headers),
      () => workspaceOperations(data, headers),
      () => recordOperations(data, headers),
      () => searchOperations(data, headers),
    ];
    
    // Execute 2-4 operations per iteration
    const numOps = Math.floor(Math.random() * 3) + 2;
    for (let i = 0; i < numOps; i++) {
      const operation = operations[Math.floor(Math.random() * operations.length)];
      operation();
    }
  });
}

function spikeStressScenario(data, headers) {
  group('Spike Stress - Rapid Operations', () => {
    // Rapid-fire requests
    for (let i = 0; i < 5; i++) {
      quickHealthCheck(data, headers);
    }
    
    // Parallel complex operations
    http.batch([
      ['GET', `${data.baseUrl}/api/workspaces`, null, { headers }],
      ['GET', `${data.baseUrl}/api/users/profile`, null, { headers }],
      ['GET', `${data.baseUrl}/api/analytics/dashboard`, null, { headers }],
      ['POST', `${data.baseUrl}/api/search`, JSON.stringify({
        query: 'spike test',
        limit: 100
      }), { headers }],
    ]);
  });
}

function memoryPressureScenario(data, headers) {
  group('Memory Pressure - Large Payloads', () => {
    // Create large records to pressure memory
    const largePayload = generateLargePayload(data.config.dataMultiplier);
    
    const response = http.post(`${data.baseUrl}/api/stress/large-record`, 
      JSON.stringify(largePayload), 
      { 
        headers,
        timeout: '60s'
      }
    );
    
    check(response, {
      'large payload handled': (r) => r.status < 500,
    }) || errorRate.add(1);
    
    memoryPressure.add(response.timings.duration);
    
    // Bulk operations
    const bulkRecords = generateBulkRecords(50 * data.config.dataMultiplier);
    const bulkResponse = http.post(`${data.baseUrl}/api/records/bulk`,
      JSON.stringify({ records: bulkRecords }),
      { 
        headers,
        timeout: '90s'
      }
    );
    
    check(bulkResponse, {
      'bulk operation handled': (r) => r.status < 500,
    }) || errorRate.add(1);
  });
}

function databaseStressScenario(data, headers) {
  group('Database Stress - Complex Queries', () => {
    // Complex aggregation queries
    const aggregationResponse = http.get(
      `${data.baseUrl}/api/analytics/complex-aggregation?` +
      `groupBy=status,priority,category&` +
      `timeRange=365d&` +
      `limit=10000&` +
      `includeMetadata=true`,
      { headers, timeout: '45s' }
    );
    
    check(aggregationResponse, {
      'complex query handled': (r) => r.status < 500,
    }) || errorRate.add(1);
    
    // Full-text search with complex filters
    const searchResponse = http.post(`${data.baseUrl}/api/search/complex`,
      JSON.stringify({
        query: 'complex database stress test query',
        filters: {
          status: { in: ['active', 'pending', 'processing'] },
          priority: { gte: 5 },
          created_date: { gte: '2023-01-01', lte: '2024-12-31' },
          tags: { contains: ['stress', 'test'] }
        },
        sort: [
          { field: 'priority', direction: 'desc' },
          { field: 'created_date', direction: 'asc' }
        ],
        limit: 1000,
        offset: Math.floor(Math.random() * 10000),
        includeAggregations: true
      }),
      { headers, timeout: '60s' }
    );
    
    check(searchResponse, {
      'complex search handled': (r) => r.status < 500,
    }) || errorRate.add(1);
    
    // Concurrent database operations
    http.batch([
      ['GET', `${data.baseUrl}/api/reports/heavy-query-1`, null, { headers }],
      ['GET', `${data.baseUrl}/api/reports/heavy-query-2`, null, { headers }],
      ['GET', `${data.baseUrl}/api/analytics/time-series?range=1y`, null, { headers }],
    ]);
  });
}

function websocketStressScenario(data, headers) {
  group('WebSocket Stress - Multiple Connections', () => {
    const wsUrl = `${WS_URL}/ws/stress?token=${headers.Authorization.split(' ')[1]}`;
    
    // Create multiple WebSocket connections
    for (let i = 0; i < 3; i++) {
      const response = ws.connect(wsUrl, {
        tags: { type: 'stress_websocket' },
      }, function (socket) {
        
        socket.on('open', () => {
          // Rapid message sending
          for (let j = 0; j < 10; j++) {
            socket.send(JSON.stringify({
              type: 'stress_message',
              id: `${__VU}_${i}_${j}`,
              payload: 'x'.repeat(1000), // 1KB messages
              timestamp: Date.now(),
            }));
          }
        });
        
        socket.on('message', (message) => {
          const data = JSON.parse(message);
          check(data, {
            'websocket message valid': (msg) => msg.type !== undefined,
          }) || errorRate.add(1);
        });
        
        socket.on('error', (e) => {
          console.log('WebSocket stress error:', e);
          errorRate.add(1);
        });
        
        // Keep connection for stress duration
        socket.setTimeout(() => {
          socket.close();
        }, 10000);
      });
      
      check(response, {
        'websocket stress connection': (r) => r && r.status === 101,
      }) || errorRate.add(1);
    }
  });
}

function cacheStressScenario(data, headers) {
  group('Cache Stress - Cache Invalidation', () => {
    // Rapidly access cached endpoints to stress cache layer
    const cachedEndpoints = [
      '/api/users/profile',
      '/api/workspaces',
      '/api/settings',
      '/api/notifications/count',
    ];
    
    // Rapid cache access
    for (let i = 0; i < 20; i++) {
      const endpoint = cachedEndpoints[Math.floor(Math.random() * cachedEndpoints.length)];
      http.get(`${data.baseUrl}${endpoint}`, { headers });
    }
    
    // Cache invalidation operations
    http.post(`${data.baseUrl}/api/cache/invalidate`, 
      JSON.stringify({ pattern: 'user:*' }),
      { headers }
    );
    
    // Immediate re-access to test cache miss handling
    for (const endpoint of cachedEndpoints) {
      http.get(`${data.baseUrl}${endpoint}`, { headers });
    }
  });
}

function standardStressScenario(data, headers) {
  group('Standard Stress Operations', () => {
    userProfileOperations(data, headers);
    workspaceOperations(data, headers);
    recordOperations(data, headers);
  });
}

// Helper functions
function quickHealthCheck(data, headers) {
  const response = http.get(`${data.baseUrl}/api/health`, { headers, timeout: '10s' });
  check(response, {
    'health check ok': (r) => r.status === 200,
    'health response time': (r) => r.timings.duration < 5000,
  }) || errorRate.add(1);
  
  responseTime.add(response.timings.duration);
}

function userProfileOperations(data, headers) {
  const response = http.get(`${data.baseUrl}/api/users/profile`, { headers });
  check(response, {
    'profile loaded': (r) => r.status < 500,
  }) || errorRate.add(1);
  
  responseTime.add(response.timings.duration);
}

function workspaceOperations(data, headers) {
  const response = http.get(`${data.baseUrl}/api/workspaces`, { headers });
  check(response, {
    'workspaces loaded': (r) => r.status < 500,
  }) || errorRate.add(1);
  
  responseTime.add(response.timings.duration);
  
  if (response.status === 200) {
    const workspaces = response.json('data') || [];
    if (workspaces.length > 0) {
      const workspace = workspaces[Math.floor(Math.random() * workspaces.length)];
      http.get(`${data.baseUrl}/api/workspaces/${workspace.id}/tables`, { headers });
    }
  }
}

function recordOperations(data, headers) {
  // Simulate record operations with stress-appropriate timeouts
  const recordData = {
    fields: {
      Name: `Stress Record ${Date.now()}`,
      Description: 'Stress test record',
      Status: 'Active',
      Priority: Math.floor(Math.random() * 10),
    }
  };
  
  const response = http.post(`${data.baseUrl}/api/records`, 
    JSON.stringify(recordData), 
    { headers, timeout: '30s' }
  );
  
  check(response, {
    'record created under stress': (r) => r.status < 500,
  }) || errorRate.add(1);
  
  responseTime.add(response.timings.duration);
}

function searchOperations(data, headers) {
  const searchData = {
    query: `stress test ${Math.random()}`,
    limit: 50,
    filters: { status: 'active' }
  };
  
  const response = http.post(`${data.baseUrl}/api/search`, 
    JSON.stringify(searchData), 
    { headers, timeout: '20s' }
  );
  
  check(response, {
    'search completed under stress': (r) => r.status < 500,
  }) || errorRate.add(1);
  
  responseTime.add(response.timings.duration);
}

export function teardown(data) {
  const duration = (Date.now() - data.startTime) / 1000;
  console.log(`Stress test completed in ${duration}s`);
  console.log(`Stress level: ${STRESS_LEVEL}`);
  console.log(`Max concurrent users: ${config.maxUsers}`);
}

export function handleSummary(data) {
  const stressLevel = STRESS_LEVEL;
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  
  return {
    [`stress-test-report-${stressLevel}-${timestamp}.html`]: htmlReport(data, {
      title: `PyAirtable Stress Test Report - ${stressLevel.toUpperCase()}`,
    }),
    [`stress-test-results-${stressLevel}-${timestamp}.json`]: JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}