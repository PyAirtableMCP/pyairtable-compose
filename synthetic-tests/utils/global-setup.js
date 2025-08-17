const axios = require('axios');
const testConfig = require('../config/test-config.json');

async function globalSetup() {
  const environment = process.env.TEST_ENV || 'local';
  const envConfig = testConfig.environments[environment];
  
  console.log(`🚀 Starting global setup for environment: ${environment}`);
  
  // Generate test session ID if not provided
  if (!process.env.TEST_SESSION_ID) {
    process.env.TEST_SESSION_ID = `synthetic-test-${Date.now()}-${process.pid}`;
  }
  
  console.log(`📋 Test Session ID: ${process.env.TEST_SESSION_ID}`);
  
  // For local environment, verify services are running
  if (environment === 'local') {
    console.log('🔍 Checking PyAirtable services...');
    
    const servicesToCheck = [
      { name: 'Frontend', url: envConfig.baseUrl },
      { name: 'API Gateway', url: envConfig.services['api-gateway'] },
      { name: 'Airtable Gateway', url: envConfig.services['airtable-gateway'] },
      { name: 'AI Processing', url: envConfig.services['ai-processing'] },
      { name: 'Workspace Service', url: envConfig.services['workspace-service'] }
    ];
    
    const healthChecks = await Promise.allSettled(
      servicesToCheck.map(async (service) => {
        try {
          const response = await axios.get(`${service.url}/health`, {
            timeout: 5000,
            validateStatus: (status) => status < 500
          });
          
          return {
            name: service.name,
            url: service.url,
            status: 'healthy',
            statusCode: response.status
          };
        } catch (error) {
          return {
            name: service.name,
            url: service.url,
            status: 'unhealthy',
            error: error.message
          };
        }
      })
    );
    
    const results = healthChecks.map(result => result.value || result.reason);
    const healthyServices = results.filter(r => r.status === 'healthy');
    const unhealthyServices = results.filter(r => r.status === 'unhealthy');
    
    console.log(`✅ Healthy services: ${healthyServices.length}/${results.length}`);
    
    if (unhealthyServices.length > 0) {
      console.log('⚠️  Unhealthy services:');
      unhealthyServices.forEach(service => {
        console.log(`   - ${service.name} (${service.url}): ${service.error}`);
      });
      
      // Don't fail the tests, just warn
      console.log('⚠️  Some services are not responding. Tests may fail.');
    }
  }
  
  // Setup test data cleanup
  await setupTestDataCleanup();
  
  // Initialize metrics collection
  await initializeMetrics();
  
  console.log('✅ Global setup completed');
}

async function setupTestDataCleanup() {
  // Create cleanup registry for test data
  global.testDataCleanup = [];
  
  // Register cleanup function
  global.registerTestDataCleanup = (cleanupFn) => {
    global.testDataCleanup.push(cleanupFn);
  };
}

async function initializeMetrics() {
  // Initialize metrics collection
  global.testMetrics = {
    sessionId: process.env.TEST_SESSION_ID,
    startTime: Date.now(),
    environment: process.env.TEST_ENV || 'local',
    tests: [],
    performance: [],
    errors: []
  };
  
  // Log test session start
  console.log('📊 Test metrics collection initialized');
}

module.exports = globalSetup;