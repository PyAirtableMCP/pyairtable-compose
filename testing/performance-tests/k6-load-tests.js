import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const authLoginDuration = new Trend('auth_login_duration');
const apiResponseDuration = new Trend('api_response_duration');
const workspaceOperationDuration = new Trend('workspace_operation_duration');

// Test configuration
export const options = {
  stages: [
    { duration: '2m', target: 10 }, // Ramp up to 10 users
    { duration: '5m', target: 10 }, // Sustain 10 users
    { duration: '2m', target: 30 }, // Ramp up to 30 users
    { duration: '5m', target: 30 }, // Sustain 30 users
    { duration: '2m', target: 50 }, // Ramp up to 50 users
    { duration: '5m', target: 50 }, // Sustain 50 users
    { duration: '3m', target: 0 },  // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(99)<2000'], // 99% of requests under 2s
    http_req_failed: ['rate<0.1'],     // Error rate under 10%
    errors: ['rate<0.05'],            // Custom error rate under 5%
    auth_login_duration: ['p(95)<1000'], // 95% of logins under 1s
    api_response_duration: ['p(90)<500'], // 90% of API calls under 500ms
    workspace_operation_duration: ['p(95)<1500'], // 95% of workspace ops under 1.5s
  },
};

// Environment variables
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const API_KEY = __ENV.API_KEY || 'test-api-key';

// Test data
const TEST_USERS = [
  { email: 'user1@example.com', password: 'TestPassword123!' },
  { email: 'user2@example.com', password: 'TestPassword123!' },
  { email: 'user3@example.com', password: 'TestPassword123!' },
  { email: 'user4@example.com', password: 'TestPassword123!' },
  { email: 'user5@example.com', password: 'TestPassword123!' },
];

// Helper functions
function getRandomUser() {
  return TEST_USERS[Math.floor(Math.random() * TEST_USERS.length)];
}

function generateRandomData() {
  return {
    workspace: {
      name: `Workspace ${Math.random().toString(36).substr(2, 9)}`,
      description: `Test workspace created at ${new Date().toISOString()}`,
    },
    table: {
      name: `Table ${Math.random().toString(36).substr(2, 9)}`,
      fields: [
        { name: 'Name', type: 'singleLineText' },
        { name: 'Status', type: 'singleSelect', options: { choices: ['Active', 'Inactive'] } },
        { name: 'Created', type: 'date' }
      ]
    },
    record: {
      fields: {
        Name: `Record ${Math.random().toString(36).substr(2, 9)}`,
        Status: Math.random() > 0.5 ? 'Active' : 'Inactive',
        Created: new Date().toISOString().split('T')[0]
      }
    }
  };
}

// Authentication function
function authenticate() {
  const user = getRandomUser();
  const payload = JSON.stringify({
    email: user.email,
    password: user.password,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': API_KEY,
    },
  };

  const response = http.post(`${BASE_URL}/api/v1/auth/login`, payload, params);
  
  authLoginDuration.add(response.timings.duration);
  
  const success = check(response, {
    'auth: status is 200': (r) => r.status === 200,
    'auth: response has access_token': (r) => r.json('data.tokens.access_token') !== undefined,
    'auth: response time < 1000ms': (r) => r.timings.duration < 1000,
  });

  if (!success) {
    errorRate.add(1);
    return null;
  }

  errorRate.add(0);
  return response.json('data.tokens.access_token');
}

// API request helper
function makeAuthenticatedRequest(method, endpoint, token, payload = null) {
  const params = {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'X-API-Key': API_KEY,
    },
  };

  let response;
  const startTime = Date.now();

  switch (method.toLowerCase()) {
    case 'get':
      response = http.get(`${BASE_URL}${endpoint}`, params);
      break;
    case 'post':
      response = http.post(`${BASE_URL}${endpoint}`, JSON.stringify(payload), params);
      break;
    case 'put':
      response = http.put(`${BASE_URL}${endpoint}`, JSON.stringify(payload), params);
      break;
    case 'delete':
      response = http.del(`${BASE_URL}${endpoint}`, null, params);
      break;
    default:
      throw new Error(`Unsupported HTTP method: ${method}`);
  }

  const duration = Date.now() - startTime;
  apiResponseDuration.add(duration);

  return response;
}

// Test scenarios
export function testUserRegistration() {
  const userData = {
    email: `test${Math.random().toString(36).substr(2, 9)}@example.com`,
    password: 'TestPassword123!',
    name: 'Test User',
    tenant_id: 'test-tenant'
  };

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': API_KEY,
    },
  };

  const response = http.post(`${BASE_URL}/api/v1/auth/register`, JSON.stringify(userData), params);
  
  const success = check(response, {
    'registration: status is 201': (r) => r.status === 201,
    'registration: response has user data': (r) => r.json('data.user') !== undefined,
    'registration: response time < 2000ms': (r) => r.timings.duration < 2000,
  });

  errorRate.add(success ? 0 : 1);
}

export function testUserAuthentication() {
  const token = authenticate();
  
  if (token) {
    // Test getting current user
    const response = makeAuthenticatedRequest('GET', '/api/v1/auth/me', token);
    
    const success = check(response, {
      'get_user: status is 200': (r) => r.status === 200,
      'get_user: response has user data': (r) => r.json('data.user') !== undefined,
      'get_user: response time < 500ms': (r) => r.timings.duration < 500,
    });

    errorRate.add(success ? 0 : 1);
  }
}

export function testWorkspaceOperations() {
  const token = authenticate();
  
  if (!token) return;

  const testData = generateRandomData();
  let workspaceId = null;

  // Create workspace
  const createStart = Date.now();
  const createResponse = makeAuthenticatedRequest('POST', '/api/v1/workspaces', token, testData.workspace);
  
  const createSuccess = check(createResponse, {
    'create_workspace: status is 201': (r) => r.status === 201,
    'create_workspace: response has workspace data': (r) => r.json('data.workspace') !== undefined,
  });

  if (createSuccess) {
    workspaceId = createResponse.json('data.workspace.id');
    
    // List workspaces
    const listResponse = makeAuthenticatedRequest('GET', '/api/v1/workspaces', token);
    
    check(listResponse, {
      'list_workspaces: status is 200': (r) => r.status === 200,
      'list_workspaces: response has data': (r) => r.json('data') !== undefined,
      'list_workspaces: response time < 300ms': (r) => r.timings.duration < 300,
    });

    // Get specific workspace
    if (workspaceId) {
      const getResponse = makeAuthenticatedRequest('GET', `/api/v1/workspaces/${workspaceId}`, token);
      
      check(getResponse, {
        'get_workspace: status is 200': (r) => r.status === 200,
        'get_workspace: response has workspace data': (r) => r.json('data.workspace') !== undefined,
      });

      // Update workspace
      const updateData = { ...testData.workspace, name: `Updated ${testData.workspace.name}` };
      const updateResponse = makeAuthenticatedRequest('PUT', `/api/v1/workspaces/${workspaceId}`, token, updateData);
      
      check(updateResponse, {
        'update_workspace: status is 200': (r) => r.status === 200,
        'update_workspace: name is updated': (r) => r.json('data.workspace.name').includes('Updated'),
      });

      // Delete workspace
      const deleteResponse = makeAuthenticatedRequest('DELETE', `/api/v1/workspaces/${workspaceId}`, token);
      
      check(deleteResponse, {
        'delete_workspace: status is 204 or 200': (r) => r.status === 204 || r.status === 200,
      });
    }
  }

  const totalDuration = Date.now() - createStart;
  workspaceOperationDuration.add(totalDuration);
  
  errorRate.add(createSuccess ? 0 : 1);
}

export function testAirtableIntegration() {
  const token = authenticate();
  
  if (!token) return;

  // Test Airtable base listing
  const basesResponse = makeAuthenticatedRequest('GET', '/api/v1/airtable/bases', token);
  
  const basesSuccess = check(basesResponse, {
    'airtable_bases: status is 200': (r) => r.status === 200,
    'airtable_bases: response time < 1000ms': (r) => r.timings.duration < 1000,
  });

  if (basesSuccess && basesResponse.json('data.bases').length > 0) {
    const baseId = basesResponse.json('data.bases.0.id');
    
    // Test table listing
    const tablesResponse = makeAuthenticatedRequest('GET', `/api/v1/airtable/bases/${baseId}/tables`, token);
    
    const tablesSuccess = check(tablesResponse, {
      'airtable_tables: status is 200': (r) => r.status === 200,
      'airtable_tables: response time < 800ms': (r) => r.timings.duration < 800,
    });

    if (tablesSuccess && tablesResponse.json('data.tables').length > 0) {
      const tableId = tablesResponse.json('data.tables.0.id');
      
      // Test record listing
      const recordsResponse = makeAuthenticatedRequest('GET', `/api/v1/airtable/bases/${baseId}/tables/${tableId}/records`, token);
      
      check(recordsResponse, {
        'airtable_records: status is 200': (r) => r.status === 200,
        'airtable_records: response time < 1500ms': (r) => r.timings.duration < 1500,
      });
    }
  }

  errorRate.add(basesSuccess ? 0 : 1);
}

export function testChatAPI() {
  const token = authenticate();
  
  if (!token) return;

  const chatPayload = {
    message: "List all my workspaces",
    session_id: `session_${Math.random().toString(36).substr(2, 9)}`,
    context: {
      user_preferences: {
        language: "en",
        format: "structured"
      }
    }
  };

  const chatResponse = makeAuthenticatedRequest('POST', '/api/v1/chat', token, chatPayload);
  
  const chatSuccess = check(chatResponse, {
    'chat: status is 200': (r) => r.status === 200,
    'chat: response has message': (r) => r.json('data.response') !== undefined,
    'chat: response time < 3000ms': (r) => r.timings.duration < 3000,
  });

  errorRate.add(chatSuccess ? 0 : 1);
}

// Main test function
export default function () {
  const scenarios = [
    testUserAuthentication,
    testWorkspaceOperations,
    testAirtableIntegration,
    testChatAPI,
  ];

  // Occasionally test registration (lower frequency)
  if (Math.random() < 0.1) {
    testUserRegistration();
  }

  // Run a random scenario
  const scenario = scenarios[Math.floor(Math.random() * scenarios.length)];
  scenario();

  // Random sleep between 1-3 seconds
  sleep(Math.random() * 2 + 1);
}

// Setup function (runs once per VU)
export function setup() {
  console.log('Starting performance test setup...');
  
  // Verify API is accessible
  const healthResponse = http.get(`${BASE_URL}/api/health`);
  
  if (healthResponse.status !== 200) {
    throw new Error(`API health check failed: ${healthResponse.status}`);
  }

  console.log('API health check passed');
  
  return {
    timestamp: new Date().toISOString(),
    baseUrl: BASE_URL,
    testUsers: TEST_USERS.length,
  };
}

// Teardown function (runs once after all VUs finish)
export function teardown(data) {
  console.log(`Performance test completed at ${new Date().toISOString()}`);
  console.log(`Test started at: ${data.timestamp}`);
  console.log(`Total test users: ${data.testUsers}`);
}