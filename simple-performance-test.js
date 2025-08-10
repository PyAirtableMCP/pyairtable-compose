// Simple K6 Performance Test for PyAirtable E2E
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    smoke_test: {
      executor: 'constant-vus',
      vus: 2,
      duration: '30s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.1'],
  },
};

const BASE_URL = 'http://localhost:8000';
const API_KEY = 'pya_efe1764855b2300ebc87363fb26b71da645a1e6c';

export default function () {
  const headers = {
    'X-API-Key': API_KEY,
    'Content-Type': 'application/json',
  };

  // Test health endpoint
  const healthResponse = http.get(`${BASE_URL}/api/health`, { headers });
  check(healthResponse, {
    'health check successful': (r) => r.status === 200,
    'response time under 1s': (r) => r.timings.duration < 1000,
  });

  sleep(0.5);

  // Test tools endpoint
  const toolsResponse = http.get(`${BASE_URL}/api/tools`, { headers });
  check(toolsResponse, {
    'tools endpoint successful': (r) => r.status === 200,
    'has tools data': (r) => r.json('tools') !== undefined,
  });

  sleep(0.5);

  // Test MCP tool execution
  const toolExecution = http.post(
    `${BASE_URL}/api/execute-tool`,
    JSON.stringify({
      tool_name: 'list_tables',
      arguments: { base_id: 'appVLUAubH5cFWhMV' }
    }),
    { headers }
  );
  
  check(toolExecution, {
    'tool execution successful': (r) => r.status === 200,
    'tool execution under 3s': (r) => r.timings.duration < 3000,
    'has result': (r) => r.json('result') !== undefined,
  });

  sleep(1);
}