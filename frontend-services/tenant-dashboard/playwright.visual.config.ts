import { defineConfig, devices } from '@playwright/test'

/**
 * Visual regression testing configuration
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: './e2e',
  
  /* Test visual, auth UI, and Airtable specs */
  testMatch: ['**/visual-regression.spec.ts', '**/auth-ui-validation.spec.ts', '**/airtable-operations.spec.ts'],
  
  /* Output directory for test results */
  outputDir: 'test-results-visual',
  
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
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: 'test-results-visual-html' }],
    ['json', { outputFile: 'test-results-visual/results.json' }]
  ],
  
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    
    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: 'retain-on-failure',
    
    /* Take screenshot on failure */
    screenshot: 'only-on-failure',
    
    /* Record video on failure */
    video: 'retain-on-failure',
    
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

  /* Configure projects for visual testing */
  projects: [
    // Desktop Chrome - primary for visual regression
    {
      name: 'chromium-visual',
      use: { ...devices['Desktop Chrome'] },
    },

    // Mobile testing for responsive design
    {
      name: 'mobile-visual',
      use: { ...devices['Pixel 5'] },
    }
  ],

  /* No global setup/teardown for visual tests */
  globalSetup: undefined,
  globalTeardown: undefined,

  /* Test timeout */
  timeout: 30000,
  
  expect: {
    /* Maximum time expect() should wait for the condition to be met. */
    timeout: 10000,
    
    /* Screenshot comparison threshold */
    threshold: 0.3,
    
    /* Animation handling for consistent screenshots */
    toHaveScreenshot: { 
      animations: 'disabled',
      threshold: 0.3,
      mode: 'css' // Use CSS to disable animations
    },
    toMatchSnapshot: { 
      animations: 'disabled',
      threshold: 0.3
    }
  },

  /* Metadata for test reporting */
  metadata: {
    version: process.env.npm_package_version || '1.0.0',
    environment: process.env.NODE_ENV || 'test',
    browser: 'visual-testing',
    os: process.platform
  }
})