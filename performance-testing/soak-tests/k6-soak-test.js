// K6 Soak Testing Suite for PyAirtable Platform
// Long-running tests to identify memory leaks, resource degradation, and stability issues

import http from 'k6/http';
import ws from 'k6/ws';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// Custom metrics for soak testing
export const memoryDegradation = new Trend('memory_degradation');
export const responseTimeDrift = new Trend('response_time_drift');
export const connectionLeaks = new Counter('connection_leaks');
export const resourceUtilization = new Gauge('resource_utilization');
export const stabilityErrors = new Rate('stability_errors');
export const performanceDegradation = new Gauge('performance_degradation_percent');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const WS_URL = __ENV.WS_URL || 'ws://localhost:8000';
const API_KEY = __ENV.API_KEY || 'test-api-key';
const SOAK_DURATION = __ENV.SOAK_DURATION || '4h';
const BASELINE_USERS = parseInt(__ENV.BASELINE_USERS || '30');

// Performance baseline tracking
let baselineResponseTime = null;
let baselineErrorRate = null;
const performanceHistory = [];
const memoryHistory = [];

export const options = {
  scenarios: {
    // Primary soak test - consistent load over extended period
    primary_soak: {
      executor: 'constant-vus',
      vus: BASELINE_USERS,
      duration: SOAK_DURATION,
      tags: { scenario: 'primary_soak' },
    },
    
    // Memory leak detection - gradual increase in data
    memory_leak_detection: {
      executor: 'ramping-vus',
      startVUs: 10,
      stages: [
        { duration: '1h', target: 10 },
        { duration: '1h', target: 15 },
        { duration: '1h', target: 20 },
        { duration: '1h', target: 25 },
      ],
      tags: { scenario: 'memory_leak' },
    },
    
    // Connection pool soak test
    connection_soak: {
      executor: 'constant-vus',
      vus: Math.floor(BASELINE_USERS * 0.3),
      duration: SOAK_DURATION,
      tags: { scenario: 'connection_soak' },
    },
    
    // WebSocket long-term stability
    websocket_soak: {
      executor: 'constant-vus',
      vus: Math.floor(BASELINE_USERS * 0.2),
      duration: SOAK_DURATION,
      tags: { scenario: 'websocket_soak' },
    },
    
    // Database connection soak
    database_soak: {
      executor: 'constant-vus',
      vus: Math.floor(BASELINE_USERS * 0.4),
      duration: SOAK_DURATION,
      tags: { scenario: 'database_soak' },
    },
    
    // Cache stability test
    cache_soak: {
      executor: 'constant-vus',
      vus: Math.floor(BASELINE_USERS * 0.25),
      duration: SOAK_DURATION,
      tags: { scenario: 'cache_soak' },
    },
  },
  
  // Relaxed thresholds for long-running tests
  thresholds: {
    // Allow gradual performance degradation but catch significant issues
    http_req_duration: [
      'p(50)<2000',     // 50% under 2s (degraded from normal)
      'p(95)<8000',     // 95% under 8s (allowing for degradation)
      'p(99)<15000'     // 99% under 15s (emergency threshold)
    ],
    http_req_failed: ['rate<0.05'],    // Error rate under 5%
    
    // Custom soak-specific thresholds
    stability_errors: ['rate<0.02'],   // Stability error rate under 2%
    response_time_drift: ['p(95)<5000'], // Response time drift under 5s
    
    // Scenario-specific thresholds
    'http_req_duration{scenario:primary_soak}': ['p(95)<5000'],
    'http_req_duration{scenario:memory_leak}': ['p(95)<8000'],
    'http_req_failed{scenario:primary_soak}': ['rate<0.02'],
    'http_req_failed{scenario:memory_leak}': ['rate<0.05'],
  },
  
  // Extended settings for soak testing
  timeout: '300s',
  noConnectionReuse: false,
  userAgent: 'K6-SoakTesting/1.0',
  
  // Resource monitoring
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)', 'p(99.9)', 'count'],
};

// Soak test state tracking
class SoakTestState {
  constructor() {
    this.startTime = Date.now();
    this.requestCount = 0;
    this.errorCount = 0;
    this.connectionCount = 0;
    this.memoryAllocations = [];
    this.performanceSnapshots = [];
  }
  
  recordRequest(duration, success) {
    this.requestCount++;
    if (!success) this.errorCount++;
    
    // Track performance over time
    const now = Date.now();
    const elapsed = (now - this.startTime) / 1000 / 3600; // Hours
    
    this.performanceSnapshots.push({
      timestamp: now,
      elapsed: elapsed,
      duration: duration,
      success: success,
    });
    
    // Detect performance degradation
    if (this.performanceSnapshots.length > 100) {
      this.analyzePerformanceTrend();
    }
  }
  
  analyzePerformanceTrend() {
    const recent = this.performanceSnapshots.slice(-50);
    const older = this.performanceSnapshots.slice(-100, -50);
    
    const recentAvg = recent.reduce((sum, s) => sum + s.duration, 0) / recent.length;
    const olderAvg = older.reduce((sum, s) => sum + s.duration, 0) / older.length;
    
    const degradation = ((recentAvg - olderAvg) / olderAvg) * 100;
    performanceDegradation.add(degradation);
    
    if (degradation > 50) { // 50% degradation threshold
      console.log(`Performance degradation detected: ${degradation.toFixed(2)}%`);
    }
  }
  
  recordMemoryUsage(approximateSize) {
    this.memoryAllocations.push({
      timestamp: Date.now(),
      size: approximateSize,
    });
    
    // Keep only recent memory data
    if (this.memoryAllocations.length > 1000) {
      this.memoryAllocations = this.memoryAllocations.slice(-500);
    }
  }
}

const soakState = new SoakTestState();

export function setup() {
  console.log('Starting PyAirtable Soak Test Suite');
  console.log(`Duration: ${SOAK_DURATION}`);
  console.log(`Baseline Users: ${BASELINE_USERS}`);
  console.log(`Target: ${BASE_URL}`);
  
  // Establish baseline performance
  console.log('Establishing performance baseline...');
  const baselineResponses = [];
  
  for (let i = 0; i < 10; i++) {
    const response = http.get(`${BASE_URL}/api/health`);
    if (response.status === 200) {
      baselineResponses.push(response.timings.duration);
    }
    sleep(1);
  }
  
  if (baselineResponses.length > 0) {
    baselineResponseTime = baselineResponses.reduce((a, b) => a + b) / baselineResponses.length;
    console.log(`Baseline response time: ${baselineResponseTime.toFixed(2)}ms`);
  }
  
  return {
    baseUrl: BASE_URL,
    apiKey: API_KEY,
    baselineResponseTime: baselineResponseTime,
    startTime: Date.now(),
  };
}

export default function(data) {
  const scenario = __ENV.K6_SCENARIO || 'primary_soak';
  const startTime = Date.now();
  
  // Authenticate with retry for stability
  const authToken = authenticateForSoak(data);
  if (!authToken) {
    stabilityErrors.add(1);
    return;
  }
  
  const headers = {
    'Authorization': `Bearer ${authToken}`,
    'Content-Type': 'application/json',
    'X-API-Key': data.apiKey,
  };
  
  // Execute scenario-specific soak tests
  let success = true;
  try {
    switch (scenario) {
      case 'primary_soak':
        success = primarySoakScenario(data, headers);
        break;
      case 'memory_leak':
        success = memoryLeakDetectionScenario(data, headers);
        break;
      case 'connection_soak':
        success = connectionSoakScenario(data, headers);
        break;
      case 'websocket_soak':
        success = websocketSoakScenario(data, headers);
        break;
      case 'database_soak':
        success = databaseSoakScenario(data, headers);
        break;
      case 'cache_soak':
        success = cacheSoakScenario(data, headers);
        break;
      default:
        success = primarySoakScenario(data, headers);
    }
  } catch (error) {
    console.log(`Soak test error in ${scenario}: ${error}`);
    stabilityErrors.add(1);
    success = false;
  }
  
  // Record performance data
  const duration = Date.now() - startTime;
  soakState.recordRequest(duration, success);
  
  // Track response time drift
  if (data.baselineResponseTime && duration > 0) {
    const drift = duration - data.baselineResponseTime;
    responseTimeDrift.add(drift);
  }
  
  // Regular think time for soak testing
  sleep(Math.random() * 10 + 5); // 5-15 seconds
}

function authenticateForSoak(data, maxRetries = 5) {
  const soakUsers = [
    { email: 'soak1@test.com', password: 'soak123' },
    { email: 'soak2@test.com', password: 'soak123' },
    { email: 'soak3@test.com', password: 'soak123' },
    { email: 'longrun@test.com', password: 'longrun123' },
  ];
  
  const user = soakUsers[__VU % soakUsers.length]; // Distribute users
  
  for (let retry = 0; retry < maxRetries; retry++) {
    try {
      const response = http.post(`${data.baseUrl}/api/auth/login`, 
        JSON.stringify(user), 
        {
          headers: { 'Content-Type': 'application/json', 'X-API-Key': data.apiKey },
          timeout: '60s',
        }
      );
      
      if (response.status === 200) {
        return response.json('token');
      }
      
      if (response.status >= 500) {
        stabilityErrors.add(1);
      }
      
    } catch (error) {
      console.log(`Auth retry ${retry + 1}: ${error}`);
      stabilityErrors.add(1);
    }
    
    if (retry < maxRetries - 1) {
      sleep(Math.pow(2, retry)); // Exponential backoff
    }
  }
  
  return null;
}

function primarySoakScenario(data, headers) {
  return group('Primary Soak - Standard Operations', () => {
    let allSuccessful = true;
    
    // Core application flow
    allSuccessful &= performHealthCheck(data, headers);
    allSuccessful &= performUserOperations(data, headers);
    allSuccessful &= performWorkspaceOperations(data, headers);
    allSuccessful &= performRecordOperations(data, headers);
    
    // Periodic analytics (every 10th iteration)
    if (__ITER % 10 === 0) {
      allSuccessful &= performAnalyticsOperations(data, headers);
    }
    
    return allSuccessful;
  });
}

function memoryLeakDetectionScenario(data, headers) {
  return group('Memory Leak Detection', () => {
    let allSuccessful = true;
    
    // Create progressively larger payloads
    const iterationMultiplier = Math.floor(__ITER / 100) + 1;
    const largeData = generateProgressivePayload(iterationMultiplier);
    
    // Track approximate memory usage
    soakState.recordMemoryUsage(JSON.stringify(largeData).length);
    
    // Create large record
    const createResponse = http.post(`${data.baseUrl}/api/records/large`,
      JSON.stringify(largeData),
      { 
        headers,
        timeout: '120s'
      }
    );
    
    const success = check(createResponse, {
      'large record created': (r) => r.status < 400,
      'no memory errors': (r) => !r.body.includes('OutOfMemory'),
    });
    
    if (!success) {
      stabilityErrors.add(1);
      allSuccessful = false;
    }
    
    // Memory-intensive operations
    allSuccessful &= performBulkOperations(data, headers, iterationMultiplier);
    
    // Cleanup attempt (helps detect memory leaks)
    if (__ITER % 50 === 0) {
      http.post(`${data.baseUrl}/api/cleanup/memory`, '{}', { headers });
    }
    
    return allSuccessful;
  });
}

function connectionSoakScenario(data, headers) {
  return group('Connection Pool Soak', () => {
    let allSuccessful = true;
    
    // Multiple concurrent requests to stress connection pool
    const requests = [];
    for (let i = 0; i < 5; i++) {
      requests.push([
        'GET', 
        `${data.baseUrl}/api/connection-test/${i}`, 
        null, 
        { headers, timeout: '30s' }
      ]);
    }
    
    const responses = http.batch(requests);
    
    for (const response of responses) {
      const success = check(response, {
        'connection handled': (r) => r.status < 500,
        'no connection errors': (r) => !r.body.includes('connection'),
      });
      
      if (!success) {
        connectionLeaks.add(1);
        allSuccessful = false;
      }
    }
    
    // Long-running connection simulation
    allSuccessful &= performLongRunningQuery(data, headers);
    
    return allSuccessful;
  });
}

function websocketSoakScenario(data, headers) {
  return group('WebSocket Long-term Stability', () => {
    const wsUrl = `${WS_URL}/ws/soak?token=${headers.Authorization.split(' ')[1]}`;
    let success = true;
    
    const response = ws.connect(wsUrl, {
      tags: { type: 'soak_websocket' },
    }, function (socket) {
      let messageCount = 0;
      let errorCount = 0;
      
      socket.on('open', () => {
        // Send periodic messages
        const messageInterval = setInterval(() => {
          if (messageCount < 100) { // Limit messages per connection
            socket.send(JSON.stringify({
              type: 'soak_ping',
              iteration: __ITER,
              timestamp: Date.now(),
              data: 'soak test data',
            }));
            messageCount++;
          }
        }, 5000); // Every 5 seconds
        
        // Clear interval when done
        socket.setTimeout(() => {
          clearInterval(messageInterval);
          socket.close();
        }, 300000); // 5 minutes per connection
      });
      
      socket.on('message', (message) => {
        try {
          const data = JSON.parse(message);
          const validMessage = check(data, {
            'websocket message valid': (msg) => msg.type !== undefined,
          });
          
          if (!validMessage) errorCount++;
          
        } catch (e) {
          errorCount++;
        }
      });
      
      socket.on('error', (e) => {
        console.log(`WebSocket soak error: ${e}`);
        errorCount++;
        stabilityErrors.add(1);
      });
      
      socket.on('close', () => {
        if (errorCount > messageCount * 0.1) { // More than 10% errors
          success = false;
        }
      });
    });
    
    const connectionSuccess = check(response, {
      'websocket soak connection': (r) => r && r.status === 101,
    });
    
    return success && connectionSuccess;
  });
}

function databaseSoakScenario(data, headers) {
  return group('Database Connection Soak', () => {
    let allSuccessful = true;
    
    // Long-running database operations
    const queries = [
      '/api/db/long-query-1',
      '/api/db/long-query-2',
      '/api/db/aggregation-query',
      '/api/db/join-query',
    ];
    
    for (const query of queries) {
      const response = http.get(`${data.baseUrl}${query}`, {
        headers,
        timeout: '180s' // Extended timeout for long queries
      });
      
      const success = check(response, {
        'database query completed': (r) => r.status < 500,
        'no database errors': (r) => !r.body.includes('database error'),
        'no timeout errors': (r) => !r.body.includes('timeout'),
      });
      
      if (!success) {
        stabilityErrors.add(1);
        allSuccessful = false;
      }
      
      // Brief pause between queries
      sleep(2);
    }
    
    // Transaction test
    allSuccessful &= performDatabaseTransaction(data, headers);
    
    return allSuccessful;
  });
}

function cacheSoakScenario(data, headers) {
  return group('Cache Stability Soak', () => {
    let allSuccessful = true;
    
    // Cache warming and testing
    const cachedEndpoints = [
      '/api/cache/user-profile',
      '/api/cache/workspace-list',
      '/api/cache/settings',
      '/api/cache/notifications',
    ];
    
    // Test cache hit/miss patterns
    for (let i = 0; i < 10; i++) {
      const endpoint = cachedEndpoints[i % cachedEndpoints.length];
      const response = http.get(`${data.baseUrl}${endpoint}`, { headers });
      
      const success = check(response, {
        'cache endpoint responsive': (r) => r.status < 500,
        'cache headers present': (r) => r.headers['X-Cache'] !== undefined,
      });
      
      if (!success) {
        stabilityErrors.add(1);
        allSuccessful = false;
      }
    }
    
    // Cache invalidation test
    if (__ITER % 20 === 0) {
      http.post(`${data.baseUrl}/api/cache/invalidate-all`, '{}', { headers });
    }
    
    return allSuccessful;
  });
}

// Helper functions
function performHealthCheck(data, headers) {
  const response = http.get(`${data.baseUrl}/api/health`, { headers, timeout: '30s' });
  return check(response, {
    'health check ok': (r) => r.status === 200,
    'health response time reasonable': (r) => r.timings.duration < 10000,
  });
}

function performUserOperations(data, headers) {
  const response = http.get(`${data.baseUrl}/api/users/profile`, { headers });
  return check(response, {
    'user profile loaded': (r) => r.status < 500,
  });
}

function performWorkspaceOperations(data, headers) {
  const response = http.get(`${data.baseUrl}/api/workspaces`, { headers });
  return check(response, {
    'workspaces loaded': (r) => r.status < 500,
  });
}

function performRecordOperations(data, headers) {
  const recordData = {
    fields: {
      Name: `Soak Record ${__ITER}_${Date.now()}`,
      Description: `Long-running soak test record iteration ${__ITER}`,
      Status: 'Active',
      Priority: Math.floor(Math.random() * 5) + 1,
    }
  };
  
  const response = http.post(`${data.baseUrl}/api/records`, 
    JSON.stringify(recordData), 
    { headers, timeout: '60s' }
  );
  
  return check(response, {
    'record operation completed': (r) => r.status < 500,
  });
}

function performAnalyticsOperations(data, headers) {
  const response = http.get(`${data.baseUrl}/api/analytics/dashboard`, { headers });
  return check(response, {
    'analytics loaded': (r) => r.status < 500,
  });
}

function performBulkOperations(data, headers, multiplier) {
  const records = [];
  const count = Math.min(50 * multiplier, 500); // Cap at 500 records
  
  for (let i = 0; i < count; i++) {
    records.push({
      fields: {
        Name: `Bulk Soak ${i}`,
        Data: 'x'.repeat(100 * multiplier), // Growing data size
      }
    });
  }
  
  const response = http.post(`${data.baseUrl}/api/records/bulk`,
    JSON.stringify({ records }),
    { headers, timeout: '180s' }
  );
  
  return check(response, {
    'bulk operation completed': (r) => r.status < 500,
  });
}

function performLongRunningQuery(data, headers) {
  const response = http.get(`${data.baseUrl}/api/reports/long-running`, {
    headers,
    timeout: '300s'
  });
  
  return check(response, {
    'long query completed': (r) => r.status < 500,
  });
}

function performDatabaseTransaction(data, headers) {
  const transactionData = {
    operations: [
      { type: 'create', table: 'soak_test', data: { name: 'test' } },
      { type: 'update', table: 'soak_test', id: 1, data: { status: 'updated' } },
      { type: 'read', table: 'soak_test', id: 1 },
    ]
  };
  
  const response = http.post(`${data.baseUrl}/api/db/transaction`,
    JSON.stringify(transactionData),
    { headers, timeout: '120s' }
  );
  
  return check(response, {
    'database transaction completed': (r) => r.status < 500,
  });
}

function generateProgressivePayload(multiplier) {
  const baseSize = 100 * multiplier;
  const payload = {
    fields: {},
    metadata: {
      iteration: __ITER,
      multiplier: multiplier,
      timestamp: new Date().toISOString(),
      size_indicator: baseSize,
    }
  };
  
  // Progressive data growth
  for (let i = 0; i < baseSize; i++) {
    payload.fields[`progressive_field_${i}`] = `data_${i}_${'x'.repeat(multiplier * 10)}`;
  }
  
  return payload;
}

export function teardown(data) {
  const totalDuration = (Date.now() - data.startTime) / 1000 / 3600; // Hours
  console.log(`\nSoak test completed after ${totalDuration.toFixed(2)} hours`);
  console.log(`Total requests: ${soakState.requestCount}`);
  console.log(`Total errors: ${soakState.errorCount}`);
  
  if (soakState.errorCount > 0) {
    const errorRate = (soakState.errorCount / soakState.requestCount) * 100;
    console.log(`Overall error rate: ${errorRate.toFixed(2)}%`);
  }
  
  // Memory analysis
  if (soakState.memoryAllocations.length > 0) {
    const memoryGrowth = analyzeMemoryGrowth(soakState.memoryAllocations);
    console.log(`Memory growth analysis: ${memoryGrowth}`);
  }
  
  // Performance degradation analysis
  if (soakState.performanceSnapshots.length > 100) {
    const degradation = analyzeOverallDegradation(soakState.performanceSnapshots);
    console.log(`Performance degradation: ${degradation.toFixed(2)}%`);
  }
}

function analyzeMemoryGrowth(allocations) {
  if (allocations.length < 10) return 'Insufficient data';
  
  const early = allocations.slice(0, 10);
  const late = allocations.slice(-10);
  
  const earlyAvg = early.reduce((sum, a) => sum + a.size, 0) / early.length;
  const lateAvg = late.reduce((sum, a) => sum + a.size, 0) / late.length;
  
  const growth = ((lateAvg - earlyAvg) / earlyAvg) * 100;
  
  return growth > 50 ? `Potential memory leak detected (${growth.toFixed(2)}% growth)` : 
         `Normal memory usage (${growth.toFixed(2)}% growth)`;
}

function analyzeOverallDegradation(snapshots) {
  const firstHour = snapshots.filter(s => s.elapsed < 1);
  const lastHour = snapshots.filter(s => s.elapsed > Math.max(0, snapshots[snapshots.length - 1].elapsed - 1));
  
  if (firstHour.length === 0 || lastHour.length === 0) return 0;
  
  const firstAvg = firstHour.reduce((sum, s) => sum + s.duration, 0) / firstHour.length;
  const lastAvg = lastHour.reduce((sum, s) => sum + s.duration, 0) / lastHour.length;
  
  return ((lastAvg - firstAvg) / firstAvg) * 100;
}

export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const duration = SOAK_DURATION.replace('h', 'hr').replace('m', 'min');
  
  return {
    [`soak-test-report-${duration}-${timestamp}.html`]: htmlReport(data, {
      title: `PyAirtable Soak Test Report - ${duration}`,
      description: 'Long-running stability and memory leak detection test'
    }),
    [`soak-test-results-${duration}-${timestamp}.json`]: JSON.stringify({
      ...data,
      soakAnalysis: {
        totalRequests: soakState.requestCount,
        totalErrors: soakState.errorCount,
        memoryAllocations: soakState.memoryAllocations.length,
        performanceSnapshots: soakState.performanceSnapshots.length,
      }
    }, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}