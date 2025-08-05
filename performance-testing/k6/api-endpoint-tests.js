// Comprehensive API Endpoint Performance Testing for PyAirtable Platform
// Tests individual endpoint performance across all 8 core services

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// Custom metrics per service
export const apiGatewayMetrics = {
  responseTime: new Trend('api_gateway_response_time'),
  errorRate: new Rate('api_gateway_errors'),
  throughput: new Counter('api_gateway_requests'),
};

export const llmOrchestratorMetrics = {
  responseTime: new Trend('llm_orchestrator_response_time'),
  errorRate: new Rate('llm_orchestrator_errors'),
  throughput: new Counter('llm_orchestrator_requests'),
  aiProcessingTime: new Trend('ai_processing_time'),
};

export const mcpServerMetrics = {
  responseTime: new Trend('mcp_server_response_time'),
  errorRate: new Rate('mcp_server_errors'),
  throughput: new Counter('mcp_server_requests'),
  protocolOverhead: new Trend('mcp_protocol_overhead'),
};

export const airtableGatewayMetrics = {
  responseTime: new Trend('airtable_gateway_response_time'),
  errorRate: new Rate('airtable_gateway_errors'),
  throughput: new Counter('airtable_gateway_requests'),
  externalApiLatency: new Trend('external_api_latency'),
};

export const platformServicesMetrics = {
  responseTime: new Trend('platform_services_response_time'),
  errorRate: new Rate('platform_services_errors'),
  throughput: new Counter('platform_services_requests'),
};

export const automationServicesMetrics = {
  responseTime: new Trend('automation_services_response_time'),
  errorRate: new Rate('automation_services_errors'),
  throughput: new Counter('automation_services_requests'),
  workflowExecutionTime: new Trend('workflow_execution_time'),
};

export const sagaOrchestratorMetrics = {
  responseTime: new Trend('saga_orchestrator_response_time'),
  errorRate: new Rate('saga_orchestrator_errors'),
  throughput: new Counter('saga_orchestrator_requests'),
  transactionTime: new Trend('transaction_coordination_time'),
};

export const redisMetrics = {
  responseTime: new Trend('redis_response_time'),
  errorRate: new Rate('redis_errors'),
  throughput: new Counter('redis_requests'),
  cacheHitRate: new Rate('cache_hit_rate'),
};

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const API_KEY = __ENV.API_KEY || 'test-api-key';
const TEST_INTENSITY = __ENV.TEST_INTENSITY || 'medium'; // light, medium, intensive

// Test intensity configurations
const intensityConfigs = {
  light: { users: 20, duration: '5m', rps: 100 },
  medium: { users: 50, duration: '10m', rps: 300 },
  intensive: { users: 100, duration: '20m', rps: 1000 },
};

const config = intensityConfigs[TEST_INTENSITY];

export const options = {
  scenarios: {
    // API Gateway endpoint testing
    api_gateway_endpoints: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(config.rps * 0.3),
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.3),
      maxVUs: Math.floor(config.users * 0.5),
      tags: { service: 'api_gateway' },
    },
    
    // LLM Orchestrator endpoint testing
    llm_orchestrator_endpoints: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(config.rps * 0.15),
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.15),
      maxVUs: Math.floor(config.users * 0.25),
      tags: { service: 'llm_orchestrator' },
    },
    
    // MCP Server endpoint testing
    mcp_server_endpoints: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(config.rps * 0.2),
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.2),
      maxVUs: Math.floor(config.users * 0.3),
      tags: { service: 'mcp_server' },
    },
    
    // Airtable Gateway endpoint testing
    airtable_gateway_endpoints: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(config.rps * 0.1),
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.1),
      maxVUs: Math.floor(config.users * 0.2),
      tags: { service: 'airtable_gateway' },
    },
    
    // Platform Services endpoint testing
    platform_services_endpoints: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(config.rps * 0.15),
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.15),
      maxVUs: Math.floor(config.users * 0.25),
      tags: { service: 'platform_services' },
    },
    
    // Automation Services endpoint testing
    automation_services_endpoints: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(config.rps * 0.05),
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.05),
      maxVUs: Math.floor(config.users * 0.1),
      tags: { service: 'automation_services' },
    },
    
    // Saga Orchestrator endpoint testing
    saga_orchestrator_endpoints: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(config.rps * 0.03),
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.03),
      maxVUs: Math.floor(config.users * 0.08),
      tags: { service: 'saga_orchestrator' },
    },
    
    // Redis cache endpoint testing
    redis_endpoints: {
      executor: 'constant-arrival-rate',
      rate: Math.floor(config.rps * 0.02),
      timeUnit: '1s',
      duration: config.duration,
      preAllocatedVUs: Math.floor(config.users * 0.02),
      maxVUs: Math.floor(config.users * 0.05),
      tags: { service: 'redis' },
    },
  },
  
  // Service-specific thresholds based on SLOs
  thresholds: {
    // API Gateway thresholds
    'http_req_duration{service:api_gateway}': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed{service:api_gateway}': ['rate<0.001'], // 0.1%
    
    // LLM Orchestrator thresholds (AI processing is slower)
    'http_req_duration{service:llm_orchestrator}': ['p(95)<2000', 'p(99)<5000'],
    'http_req_failed{service:llm_orchestrator}': ['rate<0.01'], // 1%
    
    // MCP Server thresholds
    'http_req_duration{service:mcp_server}': ['p(95)<200', 'p(99)<500'],
    'http_req_failed{service:mcp_server}': ['rate<0.0005'], // 0.05%
    
    // Airtable Gateway thresholds (external API dependency)
    'http_req_duration{service:airtable_gateway}': ['p(95)<1000', 'p(99)<2000'],
    'http_req_failed{service:airtable_gateway}': ['rate<0.005'], // 0.5%
    
    // Platform Services thresholds
    'http_req_duration{service:platform_services}': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed{service:platform_services}': ['rate<0.001'], // 0.1%
    
    // Automation Services thresholds
    'http_req_duration{service:automation_services}': ['p(95)<1000', 'p(99)<3000'],
    'http_req_failed{service:automation_services}': ['rate<0.01'], // 1%
    
    // Saga Orchestrator thresholds
    'http_req_duration{service:saga_orchestrator}': ['p(95)<500', 'p(99)<2000'],
    'http_req_failed{service:saga_orchestrator}': ['rate<0.005'], // 0.5%
    
    // Redis thresholds (should be very fast)
    'http_req_duration{service:redis}': ['p(95)<5', 'p(99)<10'],
    'http_req_failed{service:redis}': ['rate<0.0001'], // 0.01%
  },
  
  userAgent: 'K6-API-EndpointTesting/1.0',
};

// Service endpoint definitions
const serviceEndpoints = {
  api_gateway: [
    { method: 'GET', path: '/api/health', weight: 0.3, timeout: '5s' },
    { method: 'GET', path: '/api/status', weight: 0.2, timeout: '5s' },
    { method: 'POST', path: '/api/auth/login', weight: 0.15, timeout: '10s', payload: { email: 'test@test.com', password: 'test123' } },
    { method: 'GET', path: '/api/version', weight: 0.1, timeout: '5s' },
    { method: 'GET', path: '/api/metrics', weight: 0.1, timeout: '10s' },
    { method: 'POST', path: '/api/auth/refresh', weight: 0.05, timeout: '10s' },
    { method: 'POST', path: '/api/auth/logout', weight: 0.05, timeout: '10s' },
    { method: 'GET', path: '/api/config', weight: 0.05, timeout: '5s' },
  ],
  
  llm_orchestrator: [
    { method: 'POST', path: '/api/llm/chat', weight: 0.4, timeout: '30s', payload: { message: 'Hello, test message', context: 'testing' } },
    { method: 'POST', path: '/api/llm/analyze', weight: 0.25, timeout: '45s', payload: { data: 'sample data for analysis' } },
    { method: 'GET', path: '/api/llm/models', weight: 0.15, timeout: '10s' },
    { method: 'POST', path: '/api/llm/summarize', weight: 0.1, timeout: '30s', payload: { text: 'Long text to summarize...' } },
    { method: 'GET', path: '/api/llm/status', weight: 0.05, timeout: '5s' },
    { method: 'POST', path: '/api/llm/embeddings', weight: 0.05, timeout: '20s', payload: { text: 'text for embeddings' } },
  ],
  
  mcp_server: [
    { method: 'POST', path: '/mcp/initialize', weight: 0.3, timeout: '10s', payload: { version: '1.0' } },
    { method: 'POST', path: '/mcp/call', weight: 0.25, timeout: '15s', payload: { method: 'test_method', params: {} } },
    { method: 'GET', path: '/mcp/capabilities', weight: 0.2, timeout: '5s' },
    { method: 'POST', path: '/mcp/list_tools', weight: 0.1, timeout: '10s' },
    { method: 'GET', path: '/mcp/health', weight: 0.1, timeout: '5s' },
    { method: 'POST', path: '/mcp/ping', weight: 0.05, timeout: '5s', payload: { timestamp: Date.now() } },
  ],
  
  airtable_gateway: [
    { method: 'GET', path: '/airtable/bases', weight: 0.25, timeout: '15s' },
    { method: 'GET', path: '/airtable/tables', weight: 0.2, timeout: '15s' },
    { method: 'GET', path: '/airtable/records', weight: 0.2, timeout: '20s' },
    { method: 'POST', path: '/airtable/records', weight: 0.15, timeout: '25s', payload: { fields: { Name: 'Test Record' } } },
    { method: 'PATCH', path: '/airtable/records/test123', weight: 0.1, timeout: '20s', payload: { fields: { Status: 'Updated' } } },
    { method: 'GET', path: '/airtable/schema', weight: 0.05, timeout: '15s' },
    { method: 'DELETE', path: '/airtable/records/test123', weight: 0.05, timeout: '15s' },
  ],
  
  platform_services: [
    { method: 'GET', path: '/platform/users', weight: 0.25, timeout: '10s' },
    { method: 'GET', path: '/platform/workspaces', weight: 0.2, timeout: '10s' },
    { method: 'POST', path: '/platform/workspaces', weight: 0.15, timeout: '15s', payload: { name: 'Test Workspace' } },
    { method: 'GET', path: '/platform/permissions', weight: 0.15, timeout: '10s' },
    { method: 'POST', path: '/platform/users', weight: 0.1, timeout: '15s', payload: { email: 'test@example.com' } },
    { method: 'GET', path: '/platform/analytics', weight: 0.1, timeout: '20s' },
    { method: 'PATCH', path: '/platform/users/123', weight: 0.05, timeout: '10s', payload: { status: 'active' } },
  ],
  
  automation_services: [
    { method: 'GET', path: '/automation/workflows', weight: 0.3, timeout: '15s' },
    { method: 'POST', path: '/automation/trigger', weight: 0.25, timeout: '60s', payload: { workflow_id: 'test_workflow' } },
    { method: 'GET', path: '/automation/status', weight: 0.2, timeout: '10s' },
    { method: 'POST', path: '/automation/schedule', weight: 0.1, timeout: '15s', payload: { cron: '0 */1 * * *' } },
    { method: 'GET', path: '/automation/history', weight: 0.1, timeout: '15s' },
    { method: 'DELETE', path: '/automation/workflows/test123', weight: 0.05, timeout: '10s' },
  ],
  
  saga_orchestrator: [
    { method: 'POST', path: '/saga/start', weight: 0.4, timeout: '30s', payload: { transaction_id: 'test_tx', steps: [] } },
    { method: 'GET', path: '/saga/status/test123', weight: 0.25, timeout: '10s' },
    { method: 'POST', path: '/saga/compensate', weight: 0.15, timeout: '30s', payload: { transaction_id: 'test_tx' } },
    { method: 'GET', path: '/saga/transactions', weight: 0.1, timeout: '15s' },
    { method: 'POST', path: '/saga/rollback', weight: 0.05, timeout: '30s', payload: { transaction_id: 'test_tx' } },
    { method: 'GET', path: '/saga/health', weight: 0.05, timeout: '5s' },
  ],
  
  redis: [
    { method: 'GET', path: '/cache/get/test_key', weight: 0.4, timeout: '2s' },
    { method: 'POST', path: '/cache/set', weight: 0.3, timeout: '2s', payload: { key: 'test_key', value: 'test_value' } },
    { method: 'DELETE', path: '/cache/delete/test_key', weight: 0.15, timeout: '2s' },
    { method: 'GET', path: '/cache/keys', weight: 0.1, timeout: '5s' },
    { method: 'POST', path: '/cache/flush', weight: 0.03, timeout: '5s' },
    { method: 'GET', path: '/cache/stats', weight: 0.02, timeout: '2s' },
  ]
};

export function setup() {
  console.log('Starting API Endpoint Performance Testing');
  console.log(`Test Intensity: ${TEST_INTENSITY}`);
  console.log(`Target: ${BASE_URL}`);
  console.log(`RPS Target: ${config.rps}`);
  
  return {
    baseUrl: BASE_URL,
    apiKey: API_KEY,
    startTime: Date.now(),
  };
}

export default function(data) {
  const service = __ENV.K6_SCENARIO?.replace('_endpoints', '') || 'api_gateway';
  const endpoints = serviceEndpoints[service] || serviceEndpoints.api_gateway;
  
  // Get authentication token
  const authToken = getAuthToken(data);
  const headers = {
    'Authorization': `Bearer ${authToken}`,
    'Content-Type': 'application/json',
    'X-API-Key': data.apiKey,
  };
  
  // Select endpoint based on weight
  const endpoint = selectWeightedEndpoint(endpoints);
  
  // Execute API endpoint test
  testEndpoint(data, service, endpoint, headers);
  
  // Minimal sleep for high-throughput testing
  sleep(0.1);
}

function getAuthToken(data) {
  // Use cached token or authenticate
  if (!data.authToken || isTokenExpired(data.tokenTimestamp)) {
    const authResponse = http.post(`${data.baseUrl}/api/auth/login`, 
      JSON.stringify({ email: 'perf@test.com', password: 'perf123' }),
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
  const hourInMs = 60 * 60 * 1000;
  return (Date.now() - timestamp) > hourInMs;
}

function selectWeightedEndpoint(endpoints) {
  const random = Math.random();
  let cumulativeWeight = 0;
  
  for (const endpoint of endpoints) {
    cumulativeWeight += endpoint.weight;
    if (random <= cumulativeWeight) {
      return endpoint;
    }
  }
  
  return endpoints[0]; // Fallback
}

function testEndpoint(data, service, endpoint, headers) {
  const startTime = Date.now();
  const url = `${data.baseUrl}${endpoint.path}`;
  
  let response;
  const requestOptions = {
    headers: headers,
    timeout: endpoint.timeout || '30s',
    tags: { 
      service: service, 
      endpoint: endpoint.path,
      method: endpoint.method 
    }
  };
  
  // Execute HTTP request
  switch (endpoint.method) {
    case 'GET':
      response = http.get(url, requestOptions);
      break;
    case 'POST':
      response = http.post(url, 
        endpoint.payload ? JSON.stringify(endpoint.payload) : '{}', 
        requestOptions
      );
      break;
    case 'PATCH':
      response = http.patch(url, 
        endpoint.payload ? JSON.stringify(endpoint.payload) : '{}', 
        requestOptions
      );
      break;
    case 'DELETE':
      response = http.del(url, null, requestOptions);
      break;
    default:
      response = http.get(url, requestOptions);
  }
  
  const endTime = Date.now();
  const duration = endTime - startTime;
  
  // Record service-specific metrics
  recordServiceMetrics(service, response, duration);
  
  // Perform endpoint-specific checks
  performEndpointChecks(service, endpoint, response);
  
  // Record additional performance data
  recordAdditionalMetrics(service, endpoint, response);
}

function recordServiceMetrics(service, response, duration) {
  const isSuccess = response.status >= 200 && response.status < 400;
  
  switch (service) {
    case 'api_gateway':
      apiGatewayMetrics.responseTime.add(duration);
      apiGatewayMetrics.errorRate.add(!isSuccess);
      apiGatewayMetrics.throughput.add(1);
      break;
      
    case 'llm_orchestrator':
      llmOrchestratorMetrics.responseTime.add(duration);
      llmOrchestratorMetrics.errorRate.add(!isSuccess);
      llmOrchestratorMetrics.throughput.add(1);
      if (response.headers['X-AI-Processing-Time']) {
        llmOrchestratorMetrics.aiProcessingTime.add(
          parseInt(response.headers['X-AI-Processing-Time'])
        );
      }
      break;
      
    case 'mcp_server':
      mcpServerMetrics.responseTime.add(duration);
      mcpServerMetrics.errorRate.add(!isSuccess);
      mcpServerMetrics.throughput.add(1);
      if (response.headers['X-Protocol-Overhead']) {
        mcpServerMetrics.protocolOverhead.add(
          parseInt(response.headers['X-Protocol-Overhead'])
        );
      }
      break;
      
    case 'airtable_gateway':
      airtableGatewayMetrics.responseTime.add(duration);
      airtableGatewayMetrics.errorRate.add(!isSuccess);
      airtableGatewayMetrics.throughput.add(1);
      if (response.headers['X-External-API-Time']) {
        airtableGatewayMetrics.externalApiLatency.add(
          parseInt(response.headers['X-External-API-Time'])
        );
      }
      break;
      
    case 'platform_services':
      platformServicesMetrics.responseTime.add(duration);
      platformServicesMetrics.errorRate.add(!isSuccess);
      platformServicesMetrics.throughput.add(1);
      break;
      
    case 'automation_services':
      automationServicesMetrics.responseTime.add(duration);
      automationServicesMetrics.errorRate.add(!isSuccess);
      automationServicesMetrics.throughput.add(1);
      if (response.headers['X-Workflow-Execution-Time']) {
        automationServicesMetrics.workflowExecutionTime.add(
          parseInt(response.headers['X-Workflow-Execution-Time'])
        );
      }
      break;
      
    case 'saga_orchestrator':
      sagaOrchestratorMetrics.responseTime.add(duration);
      sagaOrchestratorMetrics.errorRate.add(!isSuccess);
      sagaOrchestratorMetrics.throughput.add(1);
      if (response.headers['X-Transaction-Time']) {
        sagaOrchestratorMetrics.transactionTime.add(
          parseInt(response.headers['X-Transaction-Time'])
        );
      }
      break;
      
    case 'redis':
      redisMetrics.responseTime.add(duration);
      redisMetrics.errorRate.add(!isSuccess);
      redisMetrics.throughput.add(1);
      if (response.headers['X-Cache-Hit']) {
        redisMetrics.cacheHitRate.add(response.headers['X-Cache-Hit'] === 'true');
      }
      break;
  }
}

function performEndpointChecks(service, endpoint, response) {
  const commonChecks = {
    'response received': (r) => r !== undefined,
    'status not 5xx': (r) => r.status < 500,
    'response time acceptable': (r) => r.timings.duration < 60000, // 60s max
  };
  
  // Service-specific checks
  const serviceChecks = {
    api_gateway: {
      'gateway response ok': (r) => r.status < 400,
      'has request id': (r) => r.headers['X-Request-ID'] !== undefined,
    },
    
    llm_orchestrator: {
      'ai service responsive': (r) => r.status !== 503,
      'reasonable ai response time': (r) => endpoint.path.includes('chat') ? 
        r.timings.duration < 30000 : r.timings.duration < 45000,
    },
    
    mcp_server: {
      'mcp protocol compliant': (r) => r.status < 400,
      'fast protocol response': (r) => r.timings.duration < 15000,
    },
    
    airtable_gateway: {
      'external api connection ok': (r) => r.status !== 502,
      'airtable rate limit ok': (r) => r.status !== 429,
    },
    
    platform_services: {
      'platform service ok': (r) => r.status < 400,
      'consistent response time': (r) => r.timings.duration < 20000,
    },
    
    automation_services: {
      'automation service ok': (r) => r.status < 400,
      'workflow responsive': (r) => endpoint.path.includes('trigger') ? 
        r.timings.duration < 60000 : r.timings.duration < 20000,
    },
    
    saga_orchestrator: {
      'saga service ok': (r) => r.status < 400,
      'transaction handling ok': (r) => endpoint.path.includes('start') ? 
        r.timings.duration < 30000 : r.timings.duration < 15000,
    },
    
    redis: {
      'cache service ok': (r) => r.status < 400,
      'very fast cache response': (r) => r.timings.duration < 100, // 100ms
    },
  };
  
  const checksToRun = { ...commonChecks, ...(serviceChecks[service] || {}) };
  
  const checkResults = check(response, checksToRun);
  
  if (!checkResults) {
    console.log(`Endpoint check failed: ${service} ${endpoint.method} ${endpoint.path} - Status: ${response.status}`);
  }
}

function recordAdditionalMetrics(service, endpoint, response) {
  // Record response size
  if (response.body) {
    // Could add response size metrics here
  }
  
  // Record endpoint-specific metrics
  if (endpoint.path.includes('health') && response.status === 200) {
    // Health check specific metrics
  }
  
  // Record error details for failed requests
  if (response.status >= 400) {
    console.log(`API Error: ${service} ${endpoint.method} ${endpoint.path} - ${response.status}: ${response.body?.substring(0, 200)}`);
  }
}

export function teardown(data) {
  const duration = (Date.now() - data.startTime) / 1000;
  console.log(`\nAPI Endpoint Testing completed in ${duration}s`);
  console.log(`Test Intensity: ${TEST_INTENSITY}`);
  
  // Print service-specific summary
  console.log('\nService Performance Summary:');
  console.log('- API Gateway: Core routing and authentication');
  console.log('- LLM Orchestrator: AI processing and chat');
  console.log('- MCP Server: Protocol implementation');
  console.log('- Airtable Gateway: External API integration');
  console.log('- Platform Services: Core business logic');
  console.log('- Automation Services: Workflow processing');
  console.log('- Saga Orchestrator: Transaction coordination');
  console.log('- Redis: Caching and session storage');
}

export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const intensity = TEST_INTENSITY;
  
  return {
    [`api-endpoint-report-${intensity}-${timestamp}.html`]: htmlReport(data, {
      title: `PyAirtable API Endpoint Performance Report - ${intensity.toUpperCase()}`,
      description: 'Comprehensive API endpoint performance testing across all services'
    }),
    [`api-endpoint-results-${intensity}-${timestamp}.json`]: JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}