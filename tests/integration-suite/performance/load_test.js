// PyAirtable Performance Load Testing with K6
// Comprehensive load testing suite covering all service endpoints

import http from 'k6/http';
import { check, group, sleep, fail } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// Custom metrics
const authErrorRate = new Rate('auth_errors');
const apiLatency = new Trend('api_response_time');
const errorCounter = new Counter('total_errors');
const successCounter = new Counter('successful_requests');

// Configuration
const config = {
    baseUrl: __ENV.API_GATEWAY_URL || 'http://localhost:8080',
    authUrl: __ENV.AUTH_SERVICE_URL || 'http://localhost:8083',
    apiKey: __ENV.TEST_API_KEY || 'test-api-key-12345',
    testUser: {
        email: 'admin@alpha.test.com',
        password: 'test123'
    }
};

// Test scenarios configuration
export const options = {
    scenarios: {
        // Smoke test - basic functionality
        smoke: {
            executor: 'constant-vus',
            vus: 1,
            duration: '30s',
            tags: { test_type: 'smoke' },
            exec: 'smokeTest'
        },
        
        // Load test - normal expected load
        load: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '30s', target: 10 },  // Ramp up
                { duration: '2m', target: 10 },   // Stay at load
                { duration: '30s', target: 0 },   // Ramp down
            ],
            tags: { test_type: 'load' },
            exec: 'loadTest'
        },
        
        // Stress test - above normal load
        stress: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '1m', target: 20 },   // Ramp up
                { duration: '3m', target: 20 },   // Stay at stress
                { duration: '1m', target: 50 },   // Peak stress
                { duration: '2m', target: 50 },   // Stay at peak
                { duration: '1m', target: 0 },    // Ramp down
            ],
            tags: { test_type: 'stress' },
            exec: 'stressTest'
        },
        
        // Spike test - sudden load increase
        spike: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '10s', target: 100 }, // Sudden spike
                { duration: '1m', target: 100 },  // Stay at spike
                { duration: '10s', target: 0 },   // Sudden drop
            ],
            tags: { test_type: 'spike' },
            exec: 'spikeTest'
        },
        
        // Volume test - large data operations
        volume: {
            executor: 'constant-vus',
            vus: 5,
            duration: '2m',
            tags: { test_type: 'volume' },
            exec: 'volumeTest'
        },
        
        // Endurance test - long running
        endurance: {
            executor: 'constant-vus',
            vus: 10,
            duration: '10m',
            tags: { test_type: 'endurance' },
            exec: 'enduranceTest'
        }
    },
    
    thresholds: {
        http_req_duration: ['p(95)<500', 'p(99)<1000'],
        http_req_failed: ['rate<0.05'], // 5% error rate threshold
        'http_req_duration{test_type:smoke}': ['p(95)<200'],
        'http_req_duration{test_type:load}': ['p(95)<300'],
        'http_req_duration{test_type:stress}': ['p(95)<800'],
        'http_req_duration{endpoint:auth}': ['p(95)<100'],
        'http_req_duration{endpoint:api}': ['p(95)<200'],
        auth_errors: ['rate<0.01'],
        total_errors: ['count<100']
    }
};

// Test data
let authToken = '';
const testData = {
    tenants: [],
    workspaces: [],
    projects: [],
    users: []
};

// Setup function - runs once before all tests
export function setup() {
    console.log('Setting up load test environment...');
    
    // Authenticate and get token
    const authResponse = authenticate();
    if (!authResponse.token) {
        fail('Failed to authenticate during setup');
    }
    
    // Load test data
    loadTestData(authResponse.token);
    
    return {
        token: authResponse.token,
        testData: testData
    };
}

// Authentication helper
function authenticate() {
    const payload = JSON.stringify({
        email: config.testUser.email,
        password: config.testUser.password
    });
    
    const params = {
        headers: {
            'Content-Type': 'application/json',
        },
        tags: { endpoint: 'auth' }
    };
    
    const response = http.post(`${config.authUrl}/auth/login`, payload, params);
    
    const success = check(response, {
        'Authentication successful': (r) => r.status === 200,
        'Response has token': (r) => {
            try {
                const body = JSON.parse(r.body);
                return body.token !== undefined;
            } catch (e) {
                return false;
            }
        }
    });
    
    if (!success) {
        authErrorRate.add(1);
        errorCounter.add(1);
        return {};
    }
    
    successCounter.add(1);
    const body = JSON.parse(response.body);
    return { token: body.token };
}

// Load test data helper
function loadTestData(token) {
    const headers = {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
    };
    
    // Load tenants
    const tenantsResponse = http.get(`${config.baseUrl}/api/v1/tenants`, { headers });
    if (tenantsResponse.status === 200) {
        testData.tenants = JSON.parse(tenantsResponse.body);
    }
    
    // Load workspaces
    const workspacesResponse = http.get(`${config.baseUrl}/api/v1/workspaces`, { headers });
    if (workspacesResponse.status === 200) {
        testData.workspaces = JSON.parse(workspacesResponse.body);
    }
    
    console.log(`Loaded ${testData.tenants.length} tenants, ${testData.workspaces.length} workspaces`);
}

// Smoke test - basic functionality validation
export function smokeTest(data) {
    group('Smoke Test - Basic Functionality', () => {
        // Health check
        group('Health Checks', () => {
            const services = [
                { name: 'API Gateway', url: `${config.baseUrl}/health` },
                { name: 'Auth Service', url: `${config.authUrl}/health` }
            ];
            
            services.forEach(service => {
                const response = http.get(service.url, { tags: { endpoint: 'health' } });
                check(response, {
                    [`${service.name} is healthy`]: (r) => r.status === 200,
                });
            });
        });
        
        // Basic API operations
        group('Basic API Operations', () => {
            const headers = {
                'Authorization': `Bearer ${data.token}`,
                'Content-Type': 'application/json'
            };
            
            // Get tenants
            const tenantsResponse = http.get(`${config.baseUrl}/api/v1/tenants`, { 
                headers, 
                tags: { endpoint: 'api', operation: 'list_tenants' } 
            });
            
            check(tenantsResponse, {
                'Get tenants successful': (r) => r.status === 200,
                'Response is JSON': (r) => {
                    try {
                        JSON.parse(r.body);
                        return true;
                    } catch (e) {
                        return false;
                    }
                }
            });
            
            apiLatency.add(tenantsResponse.timings.duration);
        });
    });
    
    sleep(1);
}

// Load test - normal expected traffic
export function loadTest(data) {
    group('Load Test - Normal Traffic', () => {
        const headers = {
            'Authorization': `Bearer ${data.token}`,
            'Content-Type': 'application/json'
        };
        
        // Simulate realistic user workflow
        simulateUserWorkflow(headers, data.testData);
    });
    
    sleep(Math.random() * 2 + 1); // 1-3 seconds
}

// Stress test - above normal load
export function stressTest(data) {
    group('Stress Test - High Load', () => {
        const headers = {
            'Authorization': `Bearer ${data.token}`,
            'Content-Type': 'application/json'
        };
        
        // More intensive operations
        simulateIntensiveWorkflow(headers, data.testData);
    });
    
    sleep(Math.random() * 1 + 0.5); // 0.5-1.5 seconds
}

// Spike test - sudden load increase
export function spikeTest(data) {
    group('Spike Test - Sudden Load', () => {
        const headers = {
            'Authorization': `Bearer ${data.token}`,
            'Content-Type': 'application/json'
        };
        
        // Burst of requests
        simulateBurstWorkflow(headers, data.testData);
    });
    
    sleep(Math.random() * 0.5); // 0-0.5 seconds
}

// Volume test - large data operations
export function volumeTest(data) {
    group('Volume Test - Large Data Operations', () => {
        const headers = {
            'Authorization': `Bearer ${data.token}`,
            'Content-Type': 'application/json'
        };
        
        // Large data operations
        simulateVolumeWorkflow(headers, data.testData);
    });
    
    sleep(2);
}

// Endurance test - long running stability
export function enduranceTest(data) {
    group('Endurance Test - Long Running', () => {
        const headers = {
            'Authorization': `Bearer ${data.token}`,
            'Content-Type': 'application/json'
        };
        
        // Continuous operations
        simulateUserWorkflow(headers, data.testData);
        
        // Occasional memory intensive operations
        if (Math.random() < 0.1) { // 10% chance
            simulateVolumeWorkflow(headers, data.testData);
        }
    });
    
    sleep(Math.random() * 3 + 1); // 1-4 seconds
}

// Workflow simulation functions
function simulateUserWorkflow(headers, testData) {
    // List workspaces
    let response = http.get(`${config.baseUrl}/api/v1/workspaces`, { 
        headers, 
        tags: { endpoint: 'api', operation: 'list_workspaces' } 
    });
    
    check(response, {
        'List workspaces successful': (r) => r.status === 200
    });
    
    if (response.status !== 200) {
        errorCounter.add(1);
        return;
    }
    
    const workspaces = JSON.parse(response.body);
    if (workspaces.length === 0) return;
    
    // Get workspace details
    const workspace = workspaces[Math.floor(Math.random() * workspaces.length)];
    response = http.get(`${config.baseUrl}/api/v1/workspaces/${workspace.id}`, { 
        headers, 
        tags: { endpoint: 'api', operation: 'get_workspace' } 
    });
    
    check(response, {
        'Get workspace successful': (r) => r.status === 200
    });
    
    // List projects in workspace
    response = http.get(`${config.baseUrl}/api/v1/workspaces/${workspace.id}/projects`, { 
        headers, 
        tags: { endpoint: 'api', operation: 'list_projects' } 
    });
    
    check(response, {
        'List projects successful': (r) => r.status === 200
    });
    
    successCounter.add(3);
    apiLatency.add(response.timings.duration);
}

function simulateIntensiveWorkflow(headers, testData) {
    // Multiple concurrent operations
    const operations = [
        () => http.get(`${config.baseUrl}/api/v1/workspaces`, { headers }),
        () => http.get(`${config.baseUrl}/api/v1/users/profile`, { headers }),
        () => http.get(`${config.baseUrl}/api/v1/tenants/current`, { headers }),
        () => http.get(`${config.baseUrl}/api/v1/permissions/my`, { headers })
    ];
    
    // Execute operations
    operations.forEach(op => {
        const response = op();
        check(response, {
            'Operation successful': (r) => r.status === 200 || r.status === 404
        });
        
        if (response.status >= 400) {
            errorCounter.add(1);
        } else {
            successCounter.add(1);
        }
    });
}

function simulateBurstWorkflow(headers, testData) {
    // Rapid fire requests
    for (let i = 0; i < 5; i++) {
        const response = http.get(`${config.baseUrl}/health`, { 
            headers, 
            tags: { endpoint: 'health', burst: 'true' } 
        });
        
        check(response, {
            'Burst request successful': (r) => r.status === 200
        });
        
        if (response.status !== 200) {
            errorCounter.add(1);
        } else {
            successCounter.add(1);
        }
    }
}

function simulateVolumeWorkflow(headers, testData) {
    // Create large workspace
    const largeWorkspace = {
        name: `Load Test Workspace ${Date.now()}`,
        description: 'A'.repeat(1000), // Large description
        settings: {
            visibility: 'private',
            collaboration: true,
            tags: Array.from({ length: 50 }, (_, i) => `tag-${i}`)
        }
    };
    
    const response = http.post(`${config.baseUrl}/api/v1/workspaces`, 
        JSON.stringify(largeWorkspace), 
        { 
            headers, 
            tags: { endpoint: 'api', operation: 'create_workspace', volume: 'true' } 
        }
    );
    
    check(response, {
        'Create large workspace successful': (r) => r.status === 201 || r.status === 200
    });
    
    if (response.status >= 400) {
        errorCounter.add(1);
    } else {
        successCounter.add(1);
    }
    
    // If successful, clean up
    if (response.status < 400) {
        try {
            const created = JSON.parse(response.body);
            if (created.id) {
                // Delete the workspace
                const deleteResponse = http.del(`${config.baseUrl}/api/v1/workspaces/${created.id}`, { headers });
                check(deleteResponse, {
                    'Cleanup successful': (r) => r.status === 200 || r.status === 204
                });
            }
        } catch (e) {
            console.log('Cleanup error:', e);
        }
    }
}

// Report generation
export function handleSummary(data) {
    const summary = {
        'summary.html': htmlReport(data),
        'summary.json': JSON.stringify(data),
        stdout: textSummary(data, { indent: ' ', enableColors: true })
    };
    
    // Add custom metrics to summary
    console.log('\n=== Performance Test Summary ===');
    console.log(`Total Requests: ${data.metrics.http_reqs.values.count}`);
    console.log(`Failed Requests: ${data.metrics.http_req_failed.values.passes}`);
    console.log(`Success Rate: ${((1 - data.metrics.http_req_failed.values.rate) * 100).toFixed(2)}%`);
    console.log(`Average Response Time: ${data.metrics.http_req_duration.values.avg.toFixed(2)}ms`);
    console.log(`95th Percentile: ${data.metrics.http_req_duration.values['p(95)'].toFixed(2)}ms`);
    console.log(`99th Percentile: ${data.metrics.http_req_duration.values['p(99)'].toFixed(2)}ms`);
    
    // Threshold validation
    const thresholdsPassed = Object.keys(data.metrics).every(metric => {
        const metricData = data.metrics[metric];
        return !metricData.thresholds || Object.values(metricData.thresholds).every(t => t.ok);
    });
    
    console.log(`\nThresholds: ${thresholdsPassed ? 'PASSED' : 'FAILED'}`);
    
    if (!thresholdsPassed) {
        console.log('\nFailed Thresholds:');
        Object.keys(data.metrics).forEach(metric => {
            const metricData = data.metrics[metric];
            if (metricData.thresholds) {
                Object.entries(metricData.thresholds).forEach(([threshold, result]) => {
                    if (!result.ok) {
                        console.log(`  ${metric}: ${threshold} - ${result.value}`);
                    }
                });
            }
        });
    }
    
    return summary;
}

// Teardown function - runs once after all tests
export function teardown(data) {
    console.log('Cleaning up load test environment...');
    
    // Perform any necessary cleanup
    if (data && data.token) {
        // Logout or invalidate token if needed
        const headers = {
            'Authorization': `Bearer ${data.token}`,
            'Content-Type': 'application/json'
        };
        
        // Optional: Logout
        http.post(`${config.authUrl}/auth/logout`, '', { headers });
    }
    
    console.log('Load test cleanup completed');
}