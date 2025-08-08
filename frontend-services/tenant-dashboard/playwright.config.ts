import { defineConfig, devices } from '@playwright/test'

/**
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: './e2e',
  
  /* Output directory for test results */
  outputDir: 'test-results',
  
  /* Run tests in files in parallel */
  fullyParallel: true,
  
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  
  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,
  
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 2 : undefined,
  
  /* Maximum number of failures before stopping */
  maxFailures: process.env.CI ? 10 : undefined,
  
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: process.env.CI ? [
    ['github'],
    ['junit', { outputFile: 'test-results/junit.xml' }],
    ['json', { outputFile: 'test-results/results.json' }],
    ['html', { open: 'never', outputFolder: 'test-results/html' }],
    ['blob', { outputDir: 'test-results/blob' }]
  ] : [
    ['list'],
    ['html', { open: 'on-failure', outputFolder: 'test-results/html' }],
    ['json', { outputFile: 'test-results/results.json' }]
  ],
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    
    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: process.env.CI ? 'retain-on-failure' : 'on-first-retry',
    
    /* Take screenshot on failure */
    screenshot: 'only-on-failure',
    
    /* Record video on failure */
    video: process.env.CI ? 'retain-on-failure' : 'on-first-retry',
    
    /* Global timeout for actions */
    actionTimeout: 15000,
    
    /* Navigation timeout */
    navigationTimeout: 30000,
    
    /* Ignore HTTPS errors */
    ignoreHTTPSErrors: true,
    
    /* Locale and timezone */
    locale: 'en-US',
    timezoneId: 'America/New_York',
  },

  /* Configure projects for major browsers */
  projects: [
    // Core functionality tests - run on Chrome for speed
    {
      name: 'chromium-core',
      use: { ...devices['Desktop Chrome'] },
      testMatch: [
        '**/user-registration.spec.ts',
        '**/user-login-journey.spec.ts',
        '**/chat-interface-journey.spec.ts',
        '**/complete-user-journey.spec.ts'
      ]
    },

    // Extended tests - run on Chrome only for comprehensive coverage
    {
      name: 'chromium-extended',
      use: { ...devices['Desktop Chrome'] },
      testMatch: [
        '**/airtable-integration-journey.spec.ts',
        '**/error-scenarios.spec.ts'
      ]
    },

    // Cross-browser compatibility tests - essential flows only
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
      testMatch: '**/complete-user-journey.spec.ts'
    },

    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
      testMatch: '**/complete-user-journey.spec.ts'
    },

    // Mobile testing - core user flows
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 5'] },
      testMatch: [
        '**/user-login-journey.spec.ts',
        '**/chat-interface-journey.spec.ts'
      ]
    },
    
    {
      name: 'mobile-safari',
      use: { ...devices['iPhone 12'] },
      testMatch: [
        '**/user-login-journey.spec.ts',
        '**/chat-interface-journey.spec.ts'
      ]
    }
  ],

  /* Run your local dev server before starting the tests */
  webServer: process.env.CI ? undefined : {
    command: 'npm run start',
    port: 3000,
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
    env: {
      NODE_ENV: 'production',
      DATABASE_URL: process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/pyairtable'
    },
  },

  /* Global setup and teardown */
  globalSetup: require.resolve('./e2e/global-setup.ts'),
  globalTeardown: require.resolve('./e2e/global-teardown.ts'),

  /* Test timeout */
  timeout: process.env.CI ? 60000 : 30000,
  
  expect: {
    /* Maximum time expect() should wait for the condition to be met. */
    timeout: 10000,
    
    /* Screenshot comparison threshold */
    threshold: 0.2,
    
    /* Animation handling */
    toHaveScreenshot: { animations: 'disabled' },
    toMatchSnapshot: { animations: 'disabled' }
  },

  /* Metadata for test reporting */
  metadata: {
    version: process.env.npm_package_version || '1.0.0',
    environment: process.env.NODE_ENV || 'test',
    browser: 'multi',
    os: process.platform
  }
})