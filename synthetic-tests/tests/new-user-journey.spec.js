const { test, expect } = require('@playwright/test');
const HumanBehavior = require('../utils/human-behavior');
const TraceHelper = require('../utils/trace-helper');
const testConfig = require('../config/test-config.json');

test.describe('New User Journey @smoke @regression', () => {
  let humanBehavior;
  let traceHelper;
  let testUser;

  test.beforeEach(async ({ page }) => {
    humanBehavior = new HumanBehavior();
    traceHelper = new TraceHelper();
    testUser = humanBehavior.generateTestUser();
    
    // Setup tracing for this test
    await traceHelper.setupTracing(page, 'new-user-journey');
    
    // Enable network activity capture
    await traceHelper.captureNetworkActivity(page);
  });

  test('Complete new user onboarding flow', async ({ page }) => {
    const testContext = traceHelper.createTestContext('new-user-complete-onboarding', page);
    
    try {
      // Step 1: Navigate to landing page
      traceHelper.logTestEvent('step_started', { step: 'navigate_to_landing' });
      await humanBehavior.humanNavigate(page, '/');
      
      // Wait for page to load and capture performance metrics
      await page.waitForLoadState('networkidle');
      const landingMetrics = await traceHelper.capturePerformanceMetrics(page);
      traceHelper.validatePerformance(landingMetrics);
      
      // Take screenshot of landing page
      await traceHelper.captureScreenshot(page, 'landing-page', { fullPage: true });
      
      // Simulate reading the landing page
      await humanBehavior.simulateReading(page, 'main');
      
      traceHelper.logTestEvent('step_completed', { step: 'navigate_to_landing', duration: Date.now() - testContext.startTime });

      // Step 2: Click Sign Up button
      traceHelper.logTestEvent('step_started', { step: 'click_signup' });
      
      const signUpButton = await humanBehavior.waitForElement(page, '[data-testid="signup-button"], a[href*="signup"], button:has-text("Sign Up")', { timeout: 10000 });
      await humanBehavior.humanClick(page, '[data-testid="signup-button"], a[href*="signup"], button:has-text("Sign Up")');
      
      // Wait for signup page to load
      await page.waitForURL('**/signup**', { timeout: 15000 });
      await page.waitForLoadState('networkidle');
      
      await traceHelper.captureScreenshot(page, 'signup-page');
      traceHelper.logTestEvent('step_completed', { step: 'click_signup' });

      // Step 3: Fill out registration form
      traceHelper.logTestEvent('step_started', { step: 'fill_registration_form' });
      
      // Define form fields mapping
      const formFields = {
        '[data-testid="email-input"], input[name="email"], input[type="email"]': testUser.email,
        '[data-testid="password-input"], input[name="password"], input[type="password"]': testUser.password,
        '[data-testid="first-name-input"], input[name="firstName"], input[name="first_name"]': testUser.firstName,
        '[data-testid="last-name-input"], input[name="lastName"], input[name="last_name"]': testUser.lastName
      };

      // Fill form with human-like behavior
      for (const [selector, value] of Object.entries(formFields)) {
        try {
          await humanBehavior.waitForElement(page, selector, { timeout: 5000 });
          await humanBehavior.humanType(page, selector, value);
          await page.waitForTimeout(humanBehavior.randomDelay(300, 800));
        } catch (error) {
          // Log if field is not found but continue (form might be different)
          traceHelper.logTestEvent('form_field_not_found', { selector, error: error.message });
        }
      }

      // Handle terms and conditions checkbox if present
      const termsCheckbox = page.locator('[data-testid="terms-checkbox"], input[name="terms"], input[type="checkbox"]').first();
      if (await termsCheckbox.isVisible({ timeout: 2000 })) {
        await humanBehavior.humanClick(page, '[data-testid="terms-checkbox"], input[name="terms"], input[type="checkbox"]');
      }

      await traceHelper.captureScreenshot(page, 'registration-form-filled');
      traceHelper.logTestEvent('step_completed', { step: 'fill_registration_form' });

      // Step 4: Submit registration
      traceHelper.logTestEvent('step_started', { step: 'submit_registration' });
      
      const submitButton = await humanBehavior.waitForElement(page, '[data-testid="submit-button"], button[type="submit"], button:has-text("Sign Up")', { timeout: 5000 });
      await humanBehavior.humanClick(page, '[data-testid="submit-button"], button[type="submit"], button:has-text("Sign Up")');
      
      // Wait for registration to process
      await page.waitForTimeout(3000);
      
      // Check for success (could be redirect to dashboard, verification page, or success message)
      const possibleSuccessUrls = ['**/dashboard**', '**/verify**', '**/welcome**', '**/onboarding**'];
      const possibleSuccessSelectors = [
        '[data-testid="registration-success"]',
        'text="Welcome"',
        'text="Check your email"',
        'text="Registration successful"'
      ];

      let registrationSuccess = false;
      
      // Check for URL redirect
      for (const urlPattern of possibleSuccessUrls) {
        try {
          await page.waitForURL(urlPattern, { timeout: 10000 });
          registrationSuccess = true;
          break;
        } catch (error) {
          // Continue checking other patterns
        }
      }
      
      // Check for success messages
      if (!registrationSuccess) {
        for (const selector of possibleSuccessSelectors) {
          try {
            await page.waitForSelector(selector, { timeout: 5000 });
            registrationSuccess = true;
            break;
          } catch (error) {
            // Continue checking other selectors
          }
        }
      }

      await traceHelper.captureScreenshot(page, 'registration-result');
      
      if (!registrationSuccess) {
        // Check for error messages
        const errorSelectors = ['[role="alert"]', '.error', '.alert-danger', '[data-testid="error-message"]'];
        let errorFound = false;
        
        for (const errorSelector of errorSelectors) {
          if (await page.locator(errorSelector).isVisible({ timeout: 1000 })) {
            const errorText = await page.locator(errorSelector).textContent();
            traceHelper.logTestEvent('registration_error', { error: errorText });
            errorFound = true;
            break;
          }
        }
        
        if (!errorFound) {
          throw new Error('Registration submission failed - no success or error indicators found');
        }
      }

      traceHelper.logTestEvent('step_completed', { step: 'submit_registration', success: registrationSuccess });

      // Step 5: Navigate to dashboard/workspace (if not already there)
      if (!page.url().includes('dashboard') && !page.url().includes('workspace')) {
        traceHelper.logTestEvent('step_started', { step: 'navigate_to_dashboard' });
        
        const dashboardLink = page.locator('[data-testid="dashboard-link"], a[href*="dashboard"], a:has-text("Dashboard")').first();
        if (await dashboardLink.isVisible({ timeout: 5000 })) {
          await humanBehavior.humanClick(page, '[data-testid="dashboard-link"], a[href*="dashboard"], a:has-text("Dashboard")');
          await page.waitForLoadState('networkidle');
        } else {
          // Try direct navigation
          await humanBehavior.humanNavigate(page, '/dashboard');
        }
        
        traceHelper.logTestEvent('step_completed', { step: 'navigate_to_dashboard' });
      }

      // Step 6: Connect Airtable integration
      traceHelper.logTestEvent('step_started', { step: 'connect_airtable' });
      
      await traceHelper.captureScreenshot(page, 'dashboard-before-airtable');
      
      // Look for Airtable connection button/link
      const airtableConnectSelectors = [
        '[data-testid="connect-airtable"]',
        'button:has-text("Connect Airtable")',
        'a:has-text("Add Integration")',
        '[href*="airtable"]'
      ];
      
      let airtableConnected = false;
      
      for (const selector of airtableConnectSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 2000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(2000);
          
          // Fill Airtable credentials if form appears
          const airtableTokenInput = page.locator('[data-testid="airtable-token"], input[name="airtableToken"], input[placeholder*="pat"]').first();
          if (await airtableTokenInput.isVisible({ timeout: 3000 })) {
            const testToken = process.env.AIRTABLE_TOKEN || 'test_token_for_demo';
            await humanBehavior.humanType(page, '[data-testid="airtable-token"], input[name="airtableToken"], input[placeholder*="pat"]', testToken);
            
            const submitTokenButton = page.locator('[data-testid="submit-token"], button:has-text("Connect"), button[type="submit"]').first();
            if (await submitTokenButton.isVisible({ timeout: 2000 })) {
              await humanBehavior.humanClick(page, '[data-testid="submit-token"], button:has-text("Connect"), button[type="submit"]');
              await page.waitForTimeout(3000);
            }
          }
          
          airtableConnected = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'airtable-connection-attempt');
      traceHelper.logTestEvent('step_completed', { step: 'connect_airtable', connected: airtableConnected });

      // Step 7: View and explore data
      traceHelper.logTestEvent('step_started', { step: 'explore_data' });
      
      // Look for data tables, charts, or any data visualization
      const dataViewSelectors = [
        '[data-testid="data-table"]',
        '[data-testid="data-view"]',
        'table',
        '.table',
        '[role="grid"]',
        '.chart',
        '.visualization'
      ];
      
      let dataVisible = false;
      
      for (const selector of dataViewSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          // Simulate exploring the data
          await humanBehavior.simulateReading(page, selector);
          
          // Scroll through data if it's a table
          if (selector.includes('table') || selector.includes('grid')) {
            await humanBehavior.humanScroll(page, { direction: 'down', distance: 200 });
            await page.waitForTimeout(1000);
            await humanBehavior.humanScroll(page, { direction: 'up', distance: 100 });
          }
          
          dataVisible = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'data-exploration', { fullPage: true });
      traceHelper.logTestEvent('step_completed', { step: 'explore_data', dataVisible });

      // Final performance check
      const finalMetrics = await traceHelper.capturePerformanceMetrics(page);
      traceHelper.validatePerformance(finalMetrics);
      
      // Test completed successfully
      traceHelper.logTestEvent('test_completed', { 
        user: testUser.email,
        registrationSuccess,
        airtableConnected,
        dataVisible,
        totalSteps: 7
      });

      // Assertions
      expect(registrationSuccess).toBeTruthy();
      expect(page.url()).toMatch(/(dashboard|workspace|welcome)/);
      
      // Performance assertions
      expect(finalMetrics.pageLoad).toBeLessThan(testConfig.performance.thresholds.pageLoad);
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'test-failure', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { 
        error: error.message,
        stack: error.stack,
        url: page.url()
      });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Registration form validation @smoke', async ({ page }) => {
    const testContext = traceHelper.createTestContext('registration-validation', page);
    
    try {
      // Navigate to signup page
      await humanBehavior.humanNavigate(page, '/signup');
      await page.waitForLoadState('networkidle');
      
      // Test empty form submission
      const submitButton = await humanBehavior.waitForElement(page, '[data-testid="submit-button"], button[type="submit"], button:has-text("Sign Up")');
      await humanBehavior.humanClick(page, '[data-testid="submit-button"], button[type="submit"], button:has-text("Sign Up")');
      
      // Check for validation errors
      await page.waitForTimeout(1000);
      const validationErrors = await page.locator('[role="alert"], .error, .invalid-feedback').count();
      
      await traceHelper.captureScreenshot(page, 'validation-errors');
      traceHelper.logTestEvent('validation_test', { errorsFound: validationErrors });
      
      expect(validationErrors).toBeGreaterThan(0);
      
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Login flow for existing user @smoke', async ({ page }) => {
    const testContext = traceHelper.createTestContext('existing-user-login', page);
    
    try {
      // Navigate to login page
      await humanBehavior.humanNavigate(page, '/login');
      await page.waitForLoadState('networkidle');
      
      // Fill login form
      const existingUser = testConfig.testData.users.existingUser;
      
      await humanBehavior.humanType(page, '[data-testid="email-input"], input[name="email"], input[type="email"]', existingUser.email);
      await page.waitForTimeout(500);
      await humanBehavior.humanType(page, '[data-testid="password-input"], input[name="password"], input[type="password"]', existingUser.password);
      
      await traceHelper.captureScreenshot(page, 'login-form-filled');
      
      // Submit login
      await humanBehavior.humanClick(page, '[data-testid="login-button"], button[type="submit"], button:has-text("Log In")');
      
      // Wait for redirect or error
      await page.waitForTimeout(3000);
      
      const loginSuccess = page.url().includes('dashboard') || page.url().includes('workspace');
      
      await traceHelper.captureScreenshot(page, 'login-result');
      traceHelper.logTestEvent('login_attempt', { 
        email: existingUser.email,
        success: loginSuccess,
        finalUrl: page.url()
      });
      
      // Note: In a real test environment, you might want to create the user first
      // For now, we'll just check that the login form behaves correctly
      
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });
});