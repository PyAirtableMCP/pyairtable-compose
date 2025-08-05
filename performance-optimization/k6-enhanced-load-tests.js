// Enhanced K6 Load Testing Suite for PyAirtable
// Target: 1000 concurrent users, <200ms API response, <3s frontend load

import http from 'k6/http';
import ws from 'k6/ws';
import { check, group, fail } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';
import { jUnit, textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// Custom metrics for PyAirtable specific performance tracking
export const errorRate = new Rate('errors');
export const apiResponseTime = new Trend('api_response_time');
export const dbQueryTime = new Trend('db_query_time');
export const cacheHitRate = new Rate('cache_hits');
export const wsConnectionTime = new Trend('websocket_connection_time');
export const concurrentUsers = new Gauge('concurrent_users');
export const throughputRPS = new Rate('requests_per_second');
export const memoryUsage = new Trend('memory_usage_mb');
export const cpuUsage = new Trend('cpu_usage_percent');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const WS_URL = __ENV.WS_URL || 'ws://localhost:8000';
const API_KEY = __ENV.API_KEY || 'test-api-key';
const TARGET_USERS = parseInt(__ENV.TARGET_USERS) || 1000;
const TEST_DURATION = __ENV.TEST_DURATION || '30m';

// Performance targets
const PERFORMANCE_TARGETS = {
    API_RESPONSE_TIME_MS: 200,
    FRONTEND_LOAD_TIME_MS: 3000,
    ERROR_RATE_THRESHOLD: 0.05,  // 5%
    THROUGHPUT_RPS: 500,
    DATABASE_QUERY_TIME_MS: 100,
    CACHE_HIT_RATE: 0.80  // 80%
};

// Test scenarios configuration for gradual scaling to 1000 users
export const options = {
    scenarios: {
        // Gradual ramp-up to 1000 concurrent users
        gradual_scale_test: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '2m', target: 10 },    // Warm up
                { duration: '5m', target: 50 },    // Initial load
                { duration: '5m', target: 100 },   // Moderate load
                { duration: '5m', target: 250 },   // High load
                { duration: '5m', target: 500 },   // Very high load
                { duration: '10m', target: 1000 }, // Target load
                { duration: '10m', target: 1000 }, // Sustain target
                { duration: '5m', target: 500 },   // Scale down
                { duration: '5m', target: 100 },   // Cool down
                { duration: '2m', target: 0 },     // Complete stop
            ],
            tags: { test_type: 'gradual_scale', target: '1000_users' },
        },
        
        // Spike test - sudden increase to test resilience
        spike_resilience_test: {
            executor: 'ramping-vus',
            startVUs: 50,
            stages: [
                { duration: '30s', target: 50 },   // Baseline
                { duration: '30s', target: 800 },  // Sudden spike
                { duration: '2m', target: 800 },   // Sustain spike
                { duration: '30s', target: 50 },   // Drop back
            ],
            tags: { test_type: 'spike', target: '800_users_spike' },
            startTime: '15m', // Start after gradual test has ramped up
        },
        
        // API-focused high throughput test
        api_throughput_test: {
            executor: 'ramping-arrival-rate',
            startRate: 50,
            timeUnit: '1s',
            preAllocatedVUs: 200,
            maxVUs: 500,
            stages: [
                { duration: '2m', target: 100 },   // 100 RPS
                { duration: '5m', target: 300 },   // 300 RPS
                { duration: '10m', target: 500 },  // 500 RPS target
                { duration: '5m', target: 300 },   // Scale back
                { duration: '2m', target: 100 },   // Cool down
            ],
            tags: { test_type: 'api_throughput', target: '500_rps' },
            startTime: '25m', // Run in parallel with main test
        },
        
        // Database stress test
        database_stress_test: {
            executor: 'constant-vus',
            vus: 100,
            duration: '15m',
            tags: { test_type: 'database_stress' },
            startTime: '10m',
        },
        
        // Cache performance test
        cache_performance_test: {
            executor: 'constant-vus',
            vus: 50,
            duration: '20m',
            tags: { test_type: 'cache_performance' },
            startTime: '5m',
        },
        
        // WebSocket concurrent connections test
        websocket_connections_test: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '2m', target: 50 },    // Ramp up WS connections
                { duration: '10m', target: 200 },  // Sustain 200 WS connections
                { duration: '2m', target: 0 },     // Close connections
            ],
            tags: { test_type: 'websocket_concurrent' },
            startTime: '20m',
        },
    },
    
    // Comprehensive thresholds for 1000 user target
    thresholds: {
        // Overall performance thresholds
        http_req_duration: [
            `p(95)<${PERFORMANCE_TARGETS.API_RESPONSE_TIME_MS}`,
            `p(99)<${PERFORMANCE_TARGETS.API_RESPONSE_TIME_MS * 2.5}`
        ],
        http_req_failed: [`rate<${PERFORMANCE_TARGETS.ERROR_RATE_THRESHOLD}`],
        
        // Custom metrics thresholds
        api_response_time: [`p(95)<${PERFORMANCE_TARGETS.API_RESPONSE_TIME_MS}`],
        db_query_time: [`p(95)<${PERFORMANCE_TARGETS.DATABASE_QUERY_TIME_MS}`],
        cache_hits: [`rate>${PERFORMANCE_TARGETS.CACHE_HIT_RATE}`],
        requests_per_second: [`rate>${PERFORMANCE_TARGETS.THROUGHPUT_RPS}`],
        
        // Scenario-specific thresholds
        'http_req_duration{test_type:gradual_scale}': ['p(95)<300', 'p(99)<1000'],
        'http_req_duration{test_type:spike}': ['p(95)<500', 'p(99)<2000'],
        'http_req_duration{test_type:api_throughput}': ['p(95)<200', 'p(99)<400'],
        'http_req_failed{test_type:gradual_scale}': ['rate<0.05'],
        'http_req_failed{test_type:spike}': ['rate<0.10'],
        'http_req_failed{test_type:api_throughput}': ['rate<0.02'],
        
        // Resource utilization thresholds
        memory_usage_mb: ['p(95)<2048'], // 2GB memory usage
        cpu_usage_percent: ['p(95)<80'], // 80% CPU usage
    },
    
    // Global settings optimized for high load
    userAgent: 'PyAirtable-LoadTest-1000Users/2.0',
    insecureSkipTLSVerify: true,
    noConnectionReuse: false,
    batch: 20, // Batch requests for better performance
    batchPerHost: 10,
    
    // Tags for all requests
    tags: {
        environment: __ENV.ENVIRONMENT || 'performance-test',
        version: __ENV.VERSION || 'baseline',
        target_users: TARGET_USERS,
    },
};

// Realistic test data for 1000 users
const TEST_DATA = {
    users: generateTestUsers(TARGET_USERS),
    workspaces: generateTestWorkspaces(100),
    tables: generateTestTables(500),
    records: generateTestRecords(10000)
};

// Setup function - prepare for high-load testing
export function setup() {
    console.log(`Starting PyAirtable High-Load Test Suite - Target: ${TARGET_USERS} users`);
    console.log(`Target URL: ${BASE_URL}`);
    console.log(`Test Duration: ${TEST_DURATION}`);
    console.log(`Performance Targets:`);
    console.log(`  - API Response Time: <${PERFORMANCE_TARGETS.API_RESPONSE_TIME_MS}ms`);
    console.log(`  - Frontend Load Time: <${PERFORMANCE_TARGETS.FRONTEND_LOAD_TIME_MS}ms`);
    console.log(`  - Error Rate: <${PERFORMANCE_TARGETS.ERROR_RATE_THRESHOLD * 100}%`);
    console.log(`  - Throughput: >${PERFORMANCE_TARGETS.THROUGHPUT_RPS} RPS`);
    
    // System warmup with multiple concurrent requests
    group('System Warmup', () => {
        const warmupRequests = [];
        for (let i = 0; i < 10; i++) {
            warmupRequests.push(['GET', `${BASE_URL}/api/health`]);
        }
        
        const responses = http.batch(warmupRequests);
        const warmupSuccess = responses.every(r => r.status === 200);
        
        check(warmupSuccess, {
            'system warmup successful': () => warmupSuccess,
        });
    });
    
    return {
        baseUrl: BASE_URL,
        apiKey: API_KEY,
        timestamp: new Date().toISOString(),
        testData: TEST_DATA,
        performanceTargets: PERFORMANCE_TARGETS
    };
}

// Main test function with optimized user simulation
export default function (data) {
    const testType = __ENV.K6_SCENARIO || 'gradual_scale_test';
    const userId = __VU; // Virtual user ID
    
    concurrentUsers.add(1);
    
    // Select user data based on VU ID for consistency
    const user = data.testData.users[userId % data.testData.users.length];
    const workspace = data.testData.workspaces[userId % data.testData.workspaces.length];
    const table = data.testData.tables[userId % data.testData.tables.length];
    
    group('High-Load User Simulation', () => {
        switch (testType) {
            case 'gradual_scale_test':
                realisticUserScenario(data, user, workspace, table);
                break;
            case 'spike':
                spikeTestScenario(data, user);
                break;
            case 'api_throughput':
                apiThroughputScenario(data, user);
                break;
            case 'database_stress':
                databaseStressScenario(data, user, workspace, table);
                break;
            case 'cache_performance':
                cachePerformanceScenario(data, user);
                break;
            case 'websocket_concurrent':
                websocketConcurrentScenario(data, user);
                break;
            default:
                realisticUserScenario(data, user, workspace, table);
        }
    });
    
    // Track throughput
    throughputRPS.add(1);
    
    // Realistic think time based on user behavior patterns
    const thinkTime = getThinkTime(testType);
    sleep(thinkTime);
}

// Realistic user scenario optimized for high concurrency
function realisticUserScenario(data, user, workspace, table) {
    const headers = {
        'Content-Type': 'application/json',
        'X-API-Key': data.apiKey,
    };
    
    // Authentication flow
    group('Authentication', () => {
        const loginStart = Date.now();
        const loginResponse = http.post(`${data.baseUrl}/api/auth/login`, JSON.stringify({
            email: user.email,
            password: user.password,
        }), { headers, tags: { endpoint: 'auth_login' } });
        
        const loginTime = Date.now() - loginStart;
        apiResponseTime.add(loginTime);
        
        const loginSuccess = check(loginResponse, {
            'login successful': (r) => r.status === 200,
            'login response time ok': (r) => loginTime < PERFORMANCE_TARGETS.API_RESPONSE_TIME_MS,
            'has auth token': (r) => r.json('token') !== undefined,
        });
        
        if (!loginSuccess) {
            errorRate.add(1);
            return; // Exit if login fails
        }
        
        user.token = loginResponse.json('token');
        headers['Authorization'] = `Bearer ${user.token}`;
    });
    
    // Core application workflow
    group('Core Application Usage', () => {
        // Batch multiple API calls for efficiency
        const batchRequests = [
            ['GET', `${data.baseUrl}/api/users/profile`, null, { headers, tags: { endpoint: 'user_profile' } }],
            ['GET', `${data.baseUrl}/api/workspaces`, null, { headers, tags: { endpoint: 'list_workspaces' } }],
            ['GET', `${data.baseUrl}/api/notifications/unread-count`, null, { headers, tags: { endpoint: 'notifications' } }],
        ];
        
        const batchStart = Date.now();
        const responses = http.batch(batchRequests);
        const batchTime = Date.now() - batchStart;
        
        responses.forEach((response, index) => {
            apiResponseTime.add(response.timings.duration);
            
            const success = check(response, {
                [`batch request ${index} successful`]: (r) => r.status === 200,
            });
            
            if (!success) errorRate.add(1);
            
            // Check for cache headers
            if (response.headers['X-Cache']) {
                cacheHitRate.add(response.headers['X-Cache'] === 'HIT' ? 1 : 0);
            }
        });
    });
    
    // Workspace operations with database interaction
    group('Workspace Operations', () => {
        // Get workspace details
        const workspaceStart = Date.now();
        const workspaceResponse = http.get(`${data.baseUrl}/api/workspaces/${workspace.id}`, {
            headers,
            tags: { endpoint: 'workspace_details' }
        });
        const workspaceTime = Date.now() - workspaceStart;
        
        dbQueryTime.add(workspaceTime);
        
        check(workspaceResponse, {
            'workspace details loaded': (r) => r.status === 200,
            'workspace query time ok': () => workspaceTime < PERFORMANCE_TARGETS.DATABASE_QUERY_TIME_MS,
        }) || errorRate.add(1);
        
        // Table operations
        tableOperations(data, user, workspace.id, table.id, headers);
    });
    
    // Random additional operations to simulate real usage
    if (Math.random() < 0.3) { // 30% chance
        group('Additional Operations', () => {
            const searchResponse = http.post(`${data.baseUrl}/api/search`, JSON.stringify({
                query: `search term ${user.id}`,
                limit: 10
            }), { headers, tags: { endpoint: 'search' } });
            
            check(searchResponse, {
                'search successful': (r) => r.status === 200,
            }) || errorRate.add(1);
            
            apiResponseTime.add(searchResponse.timings.duration);
        });
    }
}

// Table operations with performance tracking
function tableOperations(data, user, workspaceId, tableId, headers) {
    group('Table CRUD Operations', () => {
        // Get records with pagination
        const recordsStart = Date.now();
        const recordsResponse = http.get(
            `${data.baseUrl}/api/workspaces/${workspaceId}/tables/${tableId}/records?limit=50&offset=${Math.floor(Math.random() * 1000)}`,
            { headers, tags: { endpoint: 'get_records' } }
        );
        const recordsTime = Date.now() - recordsStart;
        
        dbQueryTime.add(recordsTime);
        
        check(recordsResponse, {
            'records loaded': (r) => r.status === 200,
            'records query time ok': () => recordsTime < PERFORMANCE_TARGETS.DATABASE_QUERY_TIME_MS,
        }) || errorRate.add(1);
        
        // Create record (simulate data creation)
        if (Math.random() < 0.2) { // 20% chance to create
            const newRecord = generateTestRecord(user.id);
            const createStart = Date.now();
            const createResponse = http.post(
                `${data.baseUrl}/api/workspaces/${workspaceId}/tables/${tableId}/records`,
                JSON.stringify(newRecord),
                { headers, tags: { endpoint: 'create_record' } }
            );
            const createTime = Date.now() - createStart;
            
            dbQueryTime.add(createTime);
            
            check(createResponse, {
                'record created': (r) => r.status === 201,
                'create time ok': () => createTime < PERFORMANCE_TARGETS.DATABASE_QUERY_TIME_MS * 2,
            }) || errorRate.add(1);
        }
    });
}

// Spike test scenario - sudden high load
function spikeTestScenario(data, user) {
    const headers = {
        'Content-Type': 'application/json',
        'X-API-Key': data.apiKey,
        'Authorization': `Bearer ${generateTemporaryToken()}`,
    };
    
    // Rapid-fire requests to test system resilience
    const spikeRequests = [
        ['GET', `${data.baseUrl}/api/health`, null, { headers }],
        ['GET', `${data.baseUrl}/api/users/profile`, null, { headers }],
        ['GET', `${data.baseUrl}/api/workspaces`, null, { headers }],
    ];
    
    const responses = http.batch(spikeRequests);
    responses.forEach(response => {
        apiResponseTime.add(response.timings.duration);
        check(response, {
            'spike request successful': (r) => r.status >= 200 && r.status < 500, // Allow some degradation
        }) || errorRate.add(1);
    });
}

// API throughput scenario - focused on API performance
function apiThroughputScenario(data, user) {
    const headers = {
        'Content-Type': 'application/json',
        'X-API-Key': data.apiKey,
    };
    
    // High-frequency API calls
    const endpoints = [
        '/api/health',
        '/api/users/profile',
        '/api/workspaces',
        '/api/notifications/unread-count',
        '/api/settings',
    ];
    
    const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
    const response = http.get(`${data.baseUrl}${endpoint}`, {
        headers,
        tags: { endpoint: 'throughput_test' }
    });
    
    apiResponseTime.add(response.timings.duration);
    throughputRPS.add(1);
    
    check(response, {
        'throughput request successful': (r) => r.status === 200,
        'response time within target': (r) => r.timings.duration < PERFORMANCE_TARGETS.API_RESPONSE_TIME_MS,
    }) || errorRate.add(1);
}

// Database stress scenario
function databaseStressScenario(data, user, workspace, table) {
    const headers = {
        'Content-Type': 'application/json',
        'X-API-Key': data.apiKey,
        'Authorization': `Bearer ${generateTemporaryToken()}`,
    };
    
    // Complex database operations
    group('Database Stress Operations', () => {
        // Large data query
        const largeQueryStart = Date.now();
        const largeQueryResponse = http.get(
            `${data.baseUrl}/api/analytics/reports/large-dataset?limit=1000&offset=${Math.floor(Math.random() * 10000)}`,
            { headers, tags: { endpoint: 'large_query' } }
        );
        const largeQueryTime = Date.now() - largeQueryStart;
        
        dbQueryTime.add(largeQueryTime);
        
        check(largeQueryResponse, {
            'large query successful': (r) => r.status === 200,
        }) || errorRate.add(1);
        
        // Aggregation query
        const aggregationResponse = http.get(
            `${data.baseUrl}/api/analytics/aggregations?groupBy=status&timeRange=7d`,
            { headers, tags: { endpoint: 'aggregation' } }
        );
        
        dbQueryTime.add(aggregationResponse.timings.duration);
        
        check(aggregationResponse, {
            'aggregation query successful': (r) => r.status === 200,
        }) || errorRate.add(1);
    });
}

// Cache performance scenario
function cachePerformanceScenario(data, user) {
    const headers = {
        'Content-Type': 'application/json',
        'X-API-Key': data.apiKey,
    };
    
    // Test cache efficiency with repeated requests
    const cacheableEndpoints = [
        '/api/users/profile',
        '/api/workspaces',
        '/api/settings',
        '/api/notifications/unread-count',
    ];
    
    const endpoint = cacheableEndpoints[Math.floor(Math.random() * cacheableEndpoints.length)];
    
    // Make request and check for cache headers
    const response = http.get(`${data.baseUrl}${endpoint}`, {
        headers,
        tags: { endpoint: 'cache_test' }
    });
    
    apiResponseTime.add(response.timings.duration);
    
    // Track cache performance
    if (response.headers['X-Cache']) {
        cacheHitRate.add(response.headers['X-Cache'] === 'HIT' ? 1 : 0);
    }
    
    check(response, {
        'cache request successful': (r) => r.status === 200,
    }) || errorRate.add(1);
}

// WebSocket concurrent connections scenario
function websocketConcurrentScenario(data, user) {
    const wsUrl = `${WS_URL}/ws?token=${generateTemporaryToken()}`;
    
    const response = ws.connect(wsUrl, {
        tags: { endpoint: 'websocket_concurrent' },
    }, function (socket) {
        const startTime = Date.now();
        
        socket.on('open', () => {
            wsConnectionTime.add(Date.now() - startTime);
            
            // Send periodic messages
            const interval = setInterval(() => {
                socket.send(JSON.stringify({
                    type: 'heartbeat',
                    timestamp: Date.now(),
                    userId: user.id,
                }));
            }, 5000);
            
            // Clean up interval when socket closes
            socket.on('close', () => {
                clearInterval(interval);
            });
        });
        
        socket.on('message', (message) => {
            try {
                const data = JSON.parse(message);
                check(data, {
                    'websocket message valid': (msg) => msg.type !== undefined,
                }) || errorRate.add(1);
            } catch (e) {
                errorRate.add(1);
            }
        });
        
        socket.on('error', (e) => {
            console.log('WebSocket error:', e);
            errorRate.add(1);
        });
        
        // Keep connection open for test duration
        socket.setTimeout(() => {
            socket.close();
        }, 60000); // 1 minute
    });
    
    check(response, {
        'websocket connection successful': (r) => r && r.status === 101,
    }) || errorRate.add(1);
}

// Utility functions
function generateTestUsers(count) {
    const users = [];
    for (let i = 0; i < count; i++) {
        users.push({
            id: i + 1,
            email: `testuser${i + 1}@example.com`,
            password: 'testpassword123',
            name: `Test User ${i + 1}`,
        });
    }
    return users;
}

function generateTestWorkspaces(count) {
    const workspaces = [];
    for (let i = 0; i < count; i++) {
        workspaces.push({
            id: `workspace-${i + 1}`,
            name: `Test Workspace ${i + 1}`,
            type: i % 3 === 0 ? 'enterprise' : 'standard',
        });
    }
    return workspaces;
}

function generateTestTables(count) {
    const tables = [];
    for (let i = 0; i < count; i++) {
        tables.push({
            id: `table-${i + 1}`,
            name: `Test Table ${i + 1}`,
            recordCount: Math.floor(Math.random() * 10000) + 100,
        });
    }
    return tables;
}

function generateTestRecords(count) {
    const records = [];
    for (let i = 0; i < count; i++) {
        records.push({
            id: `record-${i + 1}`,
            fields: {
                Name: `Test Record ${i + 1}`,
                Status: ['Active', 'Inactive', 'Pending'][i % 3],
                Priority: Math.floor(Math.random() * 5) + 1,
                CreatedAt: new Date().toISOString(),
            },
        });
    }
    return records;
}

function generateTestRecord(userId) {
    return {
        fields: {
            Name: `Load Test Record ${Date.now()}`,
            Description: `Generated by user ${userId} during load test`,
            Status: 'Active',
            Priority: Math.floor(Math.random() * 5) + 1,
            Tags: ['load-test', 'performance', 'auto-generated'],
            CreatedAt: new Date().toISOString(),
        },
    };
}

function generateTemporaryToken() {
    // Generate a temporary token for testing (in real scenario, this would be from auth)
    return `temp-token-${Math.random().toString(36).substr(2, 9)}`;
}

function getThinkTime(testType) {
    // Realistic think times based on test type
    switch (testType) {
        case 'spike':
            return Math.random() * 0.5; // Very fast for spike test
        case 'api_throughput':
            return Math.random() * 0.2; // Fast for throughput test
        case 'database_stress':
            return Math.random() * 1; // Moderate for database test
        case 'cache_performance':
            return Math.random() * 0.3; // Fast for cache test
        case 'websocket_concurrent':
            return Math.random() * 2; // Longer for WebSocket test
        default:
            return Math.random() * 3 + 1; // 1-4 seconds for realistic user behavior
    }
}

function sleep(duration) {
    if (typeof duration === 'number') {
        // Use k6's sleep function
        const k6 = require('k6');
        k6.sleep(duration);
    }
}

// Teardown function
export function teardown(data) {
    console.log('PyAirtable High-Load Test Suite completed');
    console.log(`Test completed at: ${new Date().toISOString()}`);
    console.log(`Target users: ${TARGET_USERS}`);
    console.log(`Performance targets:`);
    console.log(`  - API Response Time: <${PERFORMANCE_TARGETS.API_RESPONSE_TIME_MS}ms`);
    console.log(`  - Error Rate: <${PERFORMANCE_TARGETS.ERROR_RATE_THRESHOLD * 100}%`);
    console.log(`  - Throughput: >${PERFORMANCE_TARGETS.THROUGHPUT_RPS} RPS`);
}

// Enhanced summary report with performance analysis
export function handleSummary(data) {
    const report = generatePerformanceReport(data);
    
    return {
        'performance-test-1000-users-report.html': htmlReport(data),
        'performance-test-1000-users-results.xml': jUnit(data),
        'performance-test-1000-users-summary.txt': textSummary(data, { indent: ' ', enableColors: true }),
        'performance-analysis-report.json': JSON.stringify(report, null, 2),
        stdout: textSummary(data, { indent: ' ', enableColors: true }),
    };
}

function generatePerformanceReport(data) {
    const report = {
        testSummary: {
            targetUsers: TARGET_USERS,
            testDuration: TEST_DURATION,
            timestamp: new Date().toISOString(),
        },
        performanceTargets: PERFORMANCE_TARGETS,
        results: {
            totalRequests: data.metrics.http_reqs ? data.metrics.http_reqs.count : 0,
            failedRequests: data.metrics.http_req_failed ? data.metrics.http_req_failed.count : 0,
            averageResponseTime: data.metrics.http_req_duration ? data.metrics.http_req_duration.avg : 0,
            p95ResponseTime: data.metrics.http_req_duration ? data.metrics.http_req_duration['p(95)'] : 0,
            p99ResponseTime: data.metrics.http_req_duration ? data.metrics.http_req_duration['p(99)'] : 0,
            throughputRPS: data.metrics.http_reqs ? data.metrics.http_reqs.rate : 0,
            errorRate: data.metrics.http_req_failed ? data.metrics.http_req_failed.rate : 0,
        },
        customMetrics: {
            apiResponseTime: data.metrics.api_response_time || {},
            dbQueryTime: data.metrics.db_query_time || {},
            cacheHitRate: data.metrics.cache_hits || {},
            wsConnectionTime: data.metrics.websocket_connection_time || {},
        },
        performanceAnalysis: {
            targetsAchieved: {
                apiResponseTime: (data.metrics.http_req_duration && data.metrics.http_req_duration['p(95)'] < PERFORMANCE_TARGETS.API_RESPONSE_TIME_MS),
                errorRate: (data.metrics.http_req_failed && data.metrics.http_req_failed.rate < PERFORMANCE_TARGETS.ERROR_RATE_THRESHOLD),
                throughput: (data.metrics.http_reqs && data.metrics.http_reqs.rate > PERFORMANCE_TARGETS.THROUGHPUT_RPS),
            },
        },
    };
    
    return report;
}