const { defineConfig, devices } = require('@playwright/test');
const testConfig = require('./test-config.json');

const environment = process.env.TEST_ENV || 'local';
const envConfig = testConfig.environments[environment];

module.exports = defineConfig({
  testDir: '../tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { outputFolder: '../reports/html-report' }],
    ['json', { outputFile: '../reports/test-results.json' }],
    ['junit', { outputFile: '../reports/test-results.xml' }],
    ['list']
  ],
  use: {
    baseURL: envConfig.baseUrl,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: envConfig.timeouts.action,
    navigationTimeout: envConfig.timeouts.navigation,
    // Enable request/response logging for observability
    extraHTTPHeaders: {
      'User-Agent': 'PyAirtable-SyntheticTests/1.0'
    }
  },
  timeout: 30000,
  expect: {
    timeout: envConfig.timeouts.assertion
  },
  projects: [
    {
      name: 'chromium',
      use: { 
        ...devices['Desktop Chrome'],
        viewport: { width: 1920, height: 1080 }
      },
    },
    {
      name: 'firefox',
      use: { 
        ...devices['Desktop Firefox'],
        viewport: { width: 1920, height: 1080 }
      },
    },
    {
      name: 'webkit',
      use: { 
        ...devices['Desktop Safari'],
        viewport: { width: 1920, height: 1080 }
      },
    },
    {
      name: 'mobile-chrome',
      use: { 
        ...devices['Pixel 5'] 
      },
    },
    {
      name: 'mobile-safari',
      use: { 
        ...devices['iPhone 12'] 
      },
    },
  ],
  webServer: {
    command: 'cd .. && ./start.sh',
    port: 3000,
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
  globalSetup: require.resolve('../utils/global-setup.js'),
  globalTeardown: require.resolve('../utils/global-teardown.js'),
});