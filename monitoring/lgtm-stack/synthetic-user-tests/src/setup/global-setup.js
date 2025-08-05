const { chromium } = require('@playwright/test');

async function globalSetup(config) {
  console.log('🚀 Global setup starting...');
  
  // Setup any global state needed for tests
  const browser = await chromium.launch();
  const page = await browser.newPage();
  
  // Check if the application is available
  const baseURL = process.env.BASE_URL || config.use.baseURL || 'http://localhost:3004';
  console.log(`📍 Testing application availability at: ${baseURL}`);
  
  try {
    await page.goto(baseURL, { waitUntil: 'domcontentloaded', timeout: 10000 });
    console.log('✅ Application is accessible');
  } catch (error) {
    console.warn('⚠️  Application might not be fully ready:', error.message);
  }
  
  await page.close();
  await browser.close();
  
  // Setup test environment
  const fs = require('fs').promises;
  
  // Ensure logs directory exists
  try {
    await fs.mkdir('logs', { recursive: true });
    await fs.mkdir('screenshots', { recursive: true });
    await fs.mkdir('test-results', { recursive: true });
  } catch (error) {
    // Directories might already exist
  }
  
  console.log('✅ Global setup completed');
}

module.exports = globalSetup;