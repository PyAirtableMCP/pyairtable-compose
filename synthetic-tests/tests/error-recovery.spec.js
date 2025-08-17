const { test, expect } = require('@playwright/test');
const HumanBehavior = require('../utils/human-behavior');
const TraceHelper = require('../utils/trace-helper');
const testConfig = require('../config/test-config.json');

test.describe('Error Recovery and Resilience @regression', () => {
  let humanBehavior;
  let traceHelper;

  test.beforeEach(async ({ page }) => {
    humanBehavior = new HumanBehavior();
    traceHelper = new TraceHelper();
    
    // Setup tracing for this test
    await traceHelper.setupTracing(page, 'error-recovery');
  });

  test('Network connectivity issues handling @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('network-connectivity-issues', page);
    
    try {
      // Step 1: Establish baseline connectivity
      traceHelper.logTestEvent('step_started', { step: 'establish_baseline' });
      
      await humanBehavior.humanNavigate(page, '/dashboard');
      await page.waitForLoadState('networkidle');
      
      // Verify normal functionality
      const healthCheckUrl = testConfig.environments.local.services['api-gateway'] + '/health';
      let baselineConnected = false;
      
      try {
        const response = await page.evaluate(async (url) => {
          const resp = await fetch(url);
          return resp.ok;
        }, healthCheckUrl);
        baselineConnected = response;
      } catch (error) {
        traceHelper.logTestEvent('baseline_check_failed', { error: error.message });
      }
      
      await traceHelper.captureScreenshot(page, 'baseline-connectivity');
      traceHelper.logTestEvent('step_completed', { step: 'establish_baseline', connected: baselineConnected });

      // Step 2: Simulate network issues
      traceHelper.logTestEvent('step_started', { step: 'simulate_network_issues' });
      
      // Block network requests to specific services
      await page.route('**/api/**', route => {
        traceHelper.logTestEvent('network_request_blocked', { url: route.request().url() });
        route.abort('internetdisconnected');
      });
      
      // Try to perform an action that requires network
      const actionSelectors = [
        '[data-testid="refresh-button"]',
        'button:has-text("Refresh")',
        'button:has-text("Load")',
        'button:has-text("Save")'
      ];
      
      let actionAttempted = false;
      
      for (const selector of actionSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(2000);
          actionAttempted = true;
          break;
        }
      }
      
      // If no action buttons, try navigation
      if (!actionAttempted) {
        await page.click('a[href*="data"], a[href*="tables"]', { timeout: 2000 }).catch(() => {});
        actionAttempted = true;
      }
      
      await traceHelper.captureScreenshot(page, 'network-blocked');
      traceHelper.logTestEvent('step_completed', { step: 'simulate_network_issues', actionAttempted });

      // Step 3: Check error handling
      traceHelper.logTestEvent('step_started', { step: 'check_error_handling' });
      
      // Wait for error messages or retry indicators
      await page.waitForTimeout(3000);
      
      const errorIndicators = [
        '[data-testid="error-message"]',
        '[data-testid="network-error"]',
        '.error-message',
        '.alert-danger',
        '.error-banner',
        'text="Network error"',
        'text="Connection failed"',
        'text="Unable to connect"'
      ];
      
      let errorDisplayed = false;
      let errorMessage = '';
      
      for (const errorSelector of errorIndicators) {
        if (await page.locator(errorSelector).isVisible({ timeout: 2000 })) {
          errorMessage = await page.locator(errorSelector).textContent() || '';
          errorDisplayed = true;
          break;
        }
      }
      
      // Check for retry mechanisms
      const retryIndicators = [
        '[data-testid="retry-button"]',
        'button:has-text("Retry")',
        'button:has-text("Try Again")',
        '.retry-button',
        '.reconnect-button'
      ];
      
      let retryAvailable = false;
      
      for (const retrySelector of retryIndicators) {
        if (await page.locator(retrySelector).isVisible({ timeout: 2000 })) {
          retryAvailable = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'error-handling');
      traceHelper.logTestEvent('error_handling_check', {
        errorDisplayed,
        retryAvailable,
        errorMessage: errorMessage.substring(0, 100)
      });
      traceHelper.logTestEvent('step_completed', { step: 'check_error_handling' });

      // Step 4: Restore connectivity and verify recovery
      traceHelper.logTestEvent('step_started', { step: 'restore_connectivity' });
      
      // Remove network blocking
      await page.unroute('**/api/**');
      
      // Try retry mechanism if available
      if (retryAvailable) {
        await humanBehavior.humanClick(page, '[data-testid="retry-button"], button:has-text("Retry"), button:has-text("Try Again")');
        await page.waitForTimeout(3000);
      } else {
        // Refresh page to restore connectivity
        await page.reload({ waitUntil: 'networkidle' });
      }
      
      // Verify recovery
      let recoverySuccessful = false;
      
      // Check if error messages are gone
      let errorsCleared = true;
      for (const errorSelector of errorIndicators) {
        if (await page.locator(errorSelector).isVisible({ timeout: 1000 })) {
          errorsCleared = false;
          break;
        }
      }
      
      // Check if normal functionality is restored
      const functionalitySelectors = [
        '[data-testid="data-table"]',
        'table',
        '.dashboard-content',
        '.main-content'
      ];
      
      for (const funcSelector of functionalitySelectors) {
        if (await page.locator(funcSelector).isVisible({ timeout: 3000 })) {
          recoverySuccessful = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'connectivity-restored');
      traceHelper.logTestEvent('connectivity_recovery', {
        errorsCleared,
        functionalityRestored: recoverySuccessful
      });
      traceHelper.logTestEvent('step_completed', { step: 'restore_connectivity' });
      
      // Assertions
      expect(errorDisplayed).toBeTruthy(); // Error should be displayed when network fails
      expect(recoverySuccessful).toBeTruthy(); // Should recover when connectivity is restored
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'network-recovery-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Service unavailability and failover @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('service-unavailability', page);
    
    try {
      // Step 1: Normal operation
      traceHelper.logTestEvent('step_started', { step: 'normal_operation' });
      
      await humanBehavior.humanNavigate(page, '/dashboard');
      await page.waitForLoadState('networkidle');
      
      await traceHelper.captureScreenshot(page, 'normal-operation');
      traceHelper.logTestEvent('step_completed', { step: 'normal_operation' });

      // Step 2: Simulate specific service failures
      traceHelper.logTestEvent('step_started', { step: 'simulate_service_failure' });
      
      // Block specific backend services
      const servicesToBlock = [
        '**/api/airtable/**',
        '**/api/ai/**',
        '**/api/workspace/**'
      ];
      
      for (const servicePattern of servicesToBlock) {
        await page.route(servicePattern, route => {
          traceHelper.logTestEvent('service_request_blocked', { 
            service: servicePattern,
            url: route.request().url()
          });
          route.fulfill({
            status: 503,
            contentType: 'application/json',
            body: JSON.stringify({ error: 'Service Unavailable', code: 503 })
          });
        });
      }
      
      // Try to use functionality that depends on these services
      const dependentActions = [
        { selector: '[data-testid="ai-chat"]', service: 'AI Processing' },
        { selector: 'button:has-text("Connect Airtable")', service: 'Airtable Gateway' },
        { selector: '[data-testid="share-workspace"]', service: 'Workspace Service' }
      ];
      
      let serviceFailuresDetected = 0;
      
      for (const action of dependentActions) {
        if (await page.locator(action.selector).isVisible({ timeout: 2000 })) {
          await humanBehavior.humanClick(page, action.selector);
          await page.waitForTimeout(2000);
          
          // Check for service-specific error handling
          const serviceErrorSelectors = [
            `[data-testid="${action.service.toLowerCase()}-error"]`,
            '.service-error',
            '.unavailable-message'
          ];
          
          for (const errorSelector of serviceErrorSelectors) {
            if (await page.locator(errorSelector).isVisible({ timeout: 1000 })) {
              serviceFailuresDetected++;
              break;
            }
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'service-failures');
      traceHelper.logTestEvent('service_failures', { detected: serviceFailuresDetected });
      traceHelper.logTestEvent('step_completed', { step: 'simulate_service_failure' });

      // Step 3: Check graceful degradation
      traceHelper.logTestEvent('step_started', { step: 'check_graceful_degradation' });
      
      // Verify that core functionality still works
      const coreFeatures = [
        '[data-testid="navigation"]',
        '[data-testid="user-menu"]',
        '.main-navigation',
        '.sidebar'
      ];
      
      let coreFeaturesWorking = 0;
      
      for (const feature of coreFeatures) {
        if (await page.locator(feature).isVisible({ timeout: 2000 })) {
          coreFeaturesWorking++;
        }
      }
      
      // Check for degraded mode indicators
      const degradedModeSelectors = [
        '[data-testid="degraded-mode"]',
        '.limited-functionality',
        '.offline-mode',
        'text="Limited functionality"',
        'text="Some features unavailable"'
      ];
      
      let degradedModeIndicator = false;
      
      for (const selector of degradedModeSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 2000 })) {
          degradedModeIndicator = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'graceful-degradation');
      traceHelper.logTestEvent('graceful_degradation', {
        coreFeaturesWorking,
        degradedModeIndicator
      });
      traceHelper.logTestEvent('step_completed', { step: 'check_graceful_degradation' });

      // Step 4: Restore services and verify recovery
      traceHelper.logTestEvent('step_started', { step: 'restore_services' });
      
      // Remove service blocks
      for (const servicePattern of servicesToBlock) {
        await page.unroute(servicePattern);
      }
      
      // Trigger refresh or retry
      await page.reload({ waitUntil: 'networkidle' });
      
      // Verify services are working again
      let servicesRestored = true;
      
      // Try the dependent actions again
      for (const action of dependentActions) {
        if (await page.locator(action.selector).isVisible({ timeout: 2000 })) {
          await humanBehavior.humanClick(page, action.selector);
          await page.waitForTimeout(1000);
          
          // Should not see error messages anymore
          const errorSelectors = [
            '.service-error',
            '.error-message',
            'text="Service Unavailable"'
          ];
          
          for (const errorSelector of errorSelectors) {
            if (await page.locator(errorSelector).isVisible({ timeout: 1000 })) {
              servicesRestored = false;
              break;
            }
          }
          
          break; // Test one action
        }
      }
      
      await traceHelper.captureScreenshot(page, 'services-restored');
      traceHelper.logTestEvent('services_recovery', { restored: servicesRestored });
      traceHelper.logTestEvent('step_completed', { step: 'restore_services' });
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'service-failover-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Data validation and error handling @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('data-validation-errors', page);
    
    try {
      // Step 1: Navigate to data entry form
      traceHelper.logTestEvent('step_started', { step: 'navigate_to_data_entry' });
      
      await humanBehavior.humanNavigate(page, '/dashboard');
      await page.waitForLoadState('networkidle');
      
      // Look for data entry opportunities
      const dataEntrySelectors = [
        '[data-testid="add-record"]',
        '[data-testid="create-entry"]',
        'button:has-text("Add")',
        'button:has-text("New")',
        'button:has-text("Create")'
      ];
      
      let dataEntryFound = false;
      
      for (const selector of dataEntrySelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(2000);
          dataEntryFound = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'data-entry-form');
      traceHelper.logTestEvent('step_completed', { step: 'navigate_to_data_entry', found: dataEntryFound });

      // Step 2: Test invalid data submission
      if (dataEntryFound) {
        traceHelper.logTestEvent('step_started', { step: 'test_invalid_data' });
        
        const formInputs = page.locator('input:not([type="hidden"]), textarea, select');
        const inputCount = await formInputs.count();
        
        if (inputCount > 0) {
          // Fill with intentionally invalid data
          const invalidData = [
            'invalid-email-format',  // For email fields
            'abc',                   // For numeric fields
            '12345678901234567890123456789012345678901234567890', // Too long text
            '<script>alert("xss")</script>', // XSS attempt
            'SELECT * FROM users',   // SQL injection attempt
          ];
          
          for (let i = 0; i < Math.min(inputCount, invalidData.length); i++) {
            const input = formInputs.nth(i);
            const inputType = await input.getAttribute('type') || 'text';
            const inputName = await input.getAttribute('name') || `field_${i}`;
            
            // Skip hidden and submit inputs
            if (inputType !== 'hidden' && inputType !== 'submit') {
              await humanBehavior.humanType(page, input, invalidData[i]);
              await page.waitForTimeout(300);
              
              traceHelper.logTestEvent('invalid_data_entered', {
                field: inputName,
                type: inputType,
                value: invalidData[i].substring(0, 20)
              });
            }
          }
          
          // Submit the form
          const submitSelectors = [
            'button[type="submit"]',
            'button:has-text("Save")',
            'button:has-text("Submit")',
            'button:has-text("Create")'
          ];
          
          for (const submitSelector of submitSelectors) {
            if (await page.locator(submitSelector).isVisible({ timeout: 2000 })) {
              await humanBehavior.humanClick(page, submitSelector);
              await page.waitForTimeout(2000);
              break;
            }
          }
        }
        
        await traceHelper.captureScreenshot(page, 'invalid-data-submitted');
        traceHelper.logTestEvent('step_completed', { step: 'test_invalid_data' });

        // Step 3: Verify validation errors
        traceHelper.logTestEvent('step_started', { step: 'verify_validation_errors' });
        
        const validationErrorSelectors = [
          '[data-testid="validation-error"]',
          '.validation-error',
          '.error-message',
          '.field-error',
          '.invalid-feedback',
          '[role="alert"]'
        ];
        
        let validationErrorsFound = 0;
        const errorMessages = [];
        
        for (const errorSelector of validationErrorSelectors) {
          const elements = page.locator(errorSelector);
          const count = await elements.count();
          
          if (count > 0) {
            validationErrorsFound += count;
            
            // Collect error messages
            for (let i = 0; i < count; i++) {
              const errorText = await elements.nth(i).textContent() || '';
              if (errorText.length > 0) {
                errorMessages.push(errorText.substring(0, 50));
              }
            }
          }
        }
        
        await traceHelper.captureScreenshot(page, 'validation-errors');
        traceHelper.logTestEvent('validation_errors_check', {
          errorsFound: validationErrorsFound,
          errorMessages
        });
        traceHelper.logTestEvent('step_completed', { step: 'verify_validation_errors' });

        // Step 4: Test error correction
        traceHelper.logTestEvent('step_started', { step: 'test_error_correction' });
        
        if (validationErrorsFound > 0) {
          // Try to correct the first few fields
          const inputs = page.locator('input:not([type="hidden"]), textarea');
          const inputCount = await inputs.count();
          
          const validData = [
            'user@example.com',
            '12345',
            'Valid text content',
            'Normal data entry',
            'Test value'
          ];
          
          for (let i = 0; i < Math.min(inputCount, 3, validData.length); i++) {
            const input = inputs.nth(i);
            if (await input.isVisible()) {
              await input.clear();
              await humanBehavior.humanType(page, input, validData[i]);
              await page.waitForTimeout(300);
            }
          }
          
          // Submit again
          const submitButton = page.locator('button[type="submit"], button:has-text("Save")').first();
          if (await submitButton.isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, submitButton);
            await page.waitForTimeout(3000);
          }
          
          // Check if errors are cleared
          let errorsCleared = true;
          for (const errorSelector of validationErrorSelectors) {
            if (await page.locator(errorSelector).isVisible({ timeout: 1000 })) {
              errorsCleared = false;
              break;
            }
          }
          
          await traceHelper.captureScreenshot(page, 'errors-corrected');
          traceHelper.logTestEvent('error_correction', { errorsCleared });
        }
        
        traceHelper.logTestEvent('step_completed', { step: 'test_error_correction' });
        
        // Assertions
        expect(validationErrorsFound).toBeGreaterThan(0); // Should show validation errors for invalid data
      }
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'data-validation-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Browser compatibility and feature detection @smoke', async ({ page, browserName }) => {
    const testContext = traceHelper.createTestContext('browser-compatibility', page);
    
    try {
      // Step 1: Detect browser capabilities
      traceHelper.logTestEvent('step_started', { step: 'detect_browser_capabilities' });
      
      const browserInfo = await page.evaluate(() => {
        return {
          userAgent: navigator.userAgent,
          language: navigator.language,
          cookieEnabled: navigator.cookieEnabled,
          onLine: navigator.onLine,
          platform: navigator.platform,
          vendor: navigator.vendor,
          features: {
            localStorage: typeof(Storage) !== 'undefined',
            sessionStorage: typeof(Storage) !== 'undefined',
            webSocket: typeof(WebSocket) !== 'undefined',
            fetch: typeof(fetch) !== 'undefined',
            promises: typeof(Promise) !== 'undefined'
          }
        };
      });
      
      traceHelper.logTestEvent('browser_capabilities', {
        browserName,
        ...browserInfo
      });
      
      await humanBehavior.humanNavigate(page, '/dashboard');
      await page.waitForLoadState('networkidle');
      
      await traceHelper.captureScreenshot(page, `browser-${browserName}-compatibility`);
      traceHelper.logTestEvent('step_completed', { step: 'detect_browser_capabilities' });

      // Step 2: Test essential features
      traceHelper.logTestEvent('step_started', { step: 'test_essential_features' });
      
      const essentialFeatures = [
        { name: 'navigation', selector: 'nav, .navigation, .nav' },
        { name: 'forms', selector: 'form, input, button' },
        { name: 'tables', selector: 'table, .table, [role="grid"]' },
        { name: 'modals', selector: '.modal, [role="dialog"]' },
        { name: 'dropdowns', selector: 'select, .dropdown' }
      ];
      
      const featureResults = {};
      
      for (const feature of essentialFeatures) {
        const elements = page.locator(feature.selector);
        const count = await elements.count();
        featureResults[feature.name] = {
          present: count > 0,
          count
        };
        
        if (count > 0) {
          // Test basic interaction
          const firstElement = elements.first();
          if (await firstElement.isVisible({ timeout: 2000 })) {
            try {
              await firstElement.hover({ timeout: 1000 });
              featureResults[feature.name].interactive = true;
            } catch (error) {
              featureResults[feature.name].interactive = false;
            }
          }
        }
      }
      
      traceHelper.logTestEvent('essential_features_test', featureResults);
      traceHelper.logTestEvent('step_completed', { step: 'test_essential_features' });

      // Step 3: Test responsive behavior
      traceHelper.logTestEvent('step_started', { step: 'test_responsive_behavior' });
      
      const viewports = [
        { width: 1920, height: 1080, name: 'desktop' },
        { width: 768, height: 1024, name: 'tablet' },
        { width: 375, height: 667, name: 'mobile' }
      ];
      
      const responsiveResults = {};
      
      for (const viewport of viewports) {
        await page.setViewportSize({ width: viewport.width, height: viewport.height });
        await page.waitForTimeout(1000);
        
        // Check if layout adapts
        const layoutElements = page.locator('.sidebar, .main-content, .navigation');
        const layoutVisible = await layoutElements.first().isVisible({ timeout: 2000 });
        
        await traceHelper.captureScreenshot(page, `responsive-${viewport.name}`);
        
        responsiveResults[viewport.name] = {
          width: viewport.width,
          height: viewport.height,
          layoutVisible
        };
      }
      
      // Reset to original viewport
      await page.setViewportSize({ width: 1920, height: 1080 });
      
      traceHelper.logTestEvent('responsive_behavior_test', responsiveResults);
      traceHelper.logTestEvent('step_completed', { step: 'test_responsive_behavior' });

      // Step 4: Check for browser-specific issues
      traceHelper.logTestEvent('step_started', { step: 'check_browser_specific_issues' });
      
      // Look for browser compatibility warnings
      const compatibilityWarnings = [
        '[data-testid="browser-warning"]',
        '.browser-compatibility-warning',
        '.unsupported-browser',
        'text="Your browser"',
        'text="Please update"'
      ];
      
      let warningsFound = false;
      
      for (const warningSelector of compatibilityWarnings) {
        if (await page.locator(warningSelector).isVisible({ timeout: 2000 })) {
          warningsFound = true;
          break;
        }
      }
      
      // Check console errors
      const consoleErrors = [];
      page.on('console', msg => {
        if (msg.type() === 'error') {
          consoleErrors.push(msg.text());
        }
      });
      
      // Trigger some interactions to capture console errors
      await page.click('body').catch(() => {});
      await page.waitForTimeout(1000);
      
      traceHelper.logTestEvent('browser_issues_check', {
        warningsFound,
        consoleErrorCount: consoleErrors.length,
        consoleErrors: consoleErrors.slice(0, 3) // First 3 errors
      });
      traceHelper.logTestEvent('step_completed', { step: 'check_browser_specific_issues' });
      
      // Assertions
      expect(browserInfo.features.localStorage).toBeTruthy();
      expect(browserInfo.features.fetch).toBeTruthy();
      expect(featureResults.navigation.present).toBeTruthy();
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'browser-compatibility-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });
});