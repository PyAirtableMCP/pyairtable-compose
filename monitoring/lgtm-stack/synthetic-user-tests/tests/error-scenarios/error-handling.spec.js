const { test, expect } = require('@playwright/test');
const ErrorProneAgent = require('../../src/agents/error-prone-agent');

test.describe('Error Handling and Recovery', () => {
  let agent;

  test.beforeEach(async () => {
    agent = new ErrorProneAgent({
      id: 'error-handling-test',
      name: 'Error Test Agent',
      errorProne: true
    });
  });

  test.afterEach(async () => {
    if (agent) {
      await agent.cleanup();
    }
  });

  test('Execute complete error testing workflow', async ({ page }) => {
    await test.step('Execute error-prone behavior', async () => {
      await agent.execute(page);
    });

    await test.step('Verify error handling completeness', async () => {
      const summary = agent.getErrorTestingSummary();
      
      // Verify error testing coverage
      expect(summary.errorPatterns.triggeredErrors.length).toBeGreaterThan(3);
      expect(summary.errorPatterns.validationErrors.length).toBeGreaterThan(0);
      expect(summary.errorPatterns.userErrors.length).toBeGreaterThan(0);
      
      console.log('Error Testing Summary:', JSON.stringify(summary, null, 2));
    });
  });

  test('Form validation error scenarios', async ({ page }) => {
    await test.step('Navigate to settings page', async () => {
      await page.goto('/settings');
      await agent.waitForPageStability(page);
    });

    await test.step('Test empty required fields', async () => {
      const requiredInputs = page.locator('input[required], input[aria-required="true"]');
      const submitButtons = page.locator('button[type="submit"], button:has-text("Save")');
      
      if (await requiredInputs.count() > 0 && await submitButtons.count() > 0) {
        // Clear required fields
        const inputCount = await requiredInputs.count();
        for (let i = 0; i < Math.min(inputCount, 3); i++) {
          const input = requiredInputs.nth(i);
          await input.fill('');
        }
        
        // Try to submit
        await submitButtons.first().click();
        await page.waitForTimeout(1000);
        
        // Look for validation messages
        const validationMessages = page.locator(
          '.error, [role="alert"], .validation-error, ' +
          'text*="required", text*="Required", [aria-invalid="true"]'
        );
        
        if (await validationMessages.count() > 0) {
          console.log('Required field validation working');
          
          // Verify error messages are accessible
          const firstError = validationMessages.first();
          const errorText = await firstError.textContent();
          expect(errorText).toBeTruthy();
          expect(errorText.length).toBeGreaterThan(0);
        }
      }
    });

    await test.step('Test invalid email formats', async () => {
      const emailInputs = page.locator('input[type="email"], input[placeholder*="email"]');
      
      if (await emailInputs.count() > 0) {
        const invalidEmails = [
          'invalid-email',
          '@domain.com',
          'user@',
          'user.domain',
          'spaces in@email.com'
        ];
        
        for (const email of invalidEmails.slice(0, 2)) {
          await emailInputs.first().fill(email);
          await page.keyboard.press('Tab');
          await page.waitForTimeout(500);
          
          // Check for email validation
          const emailValidation = page.locator(
            'text*="valid email", text*="invalid email", ' +
            '[aria-invalid="true"], .email-error'
          );
          
          if (await emailValidation.count() > 0) {
            console.log(`Email validation triggered for: ${email}`);
          }
        }
      }
    });

    await test.step('Test number input validation', async () => {
      const numberInputs = page.locator('input[type="number"], input[inputmode="numeric"]');
      
      if (await numberInputs.count() > 0) {
        const invalidNumbers = ['abc', '12.34.56', 'NaN'];
        
        for (const invalidNum of invalidNumbers) {
          await numberInputs.first().fill(invalidNum);
          await page.keyboard.press('Tab');
          await page.waitForTimeout(500);
          
          // Check if browser or custom validation kicks in
          const isValid = await numberInputs.first().evaluate(el => el.validity.valid);
          console.log(`Number validation for "${invalidNum}": ${isValid ? 'passed' : 'failed'}`);
        }
      }
    });

    await test.step('Test maximum length validation', async () => {
      const inputsWithMaxLength = page.locator('input[maxlength], textarea[maxlength]');
      
      if (await inputsWithMaxLength.count() > 0) {
        const input = inputsWithMaxLength.first();
        const maxLength = parseInt(await input.getAttribute('maxlength') || '100');
        const exceedingText = 'a'.repeat(maxLength + 50);
        
        await input.fill(exceedingText);
        await page.waitForTimeout(500);
        
        const actualLength = (await input.inputValue()).length;
        
        // Text should be truncated to maxLength
        expect(actualLength).toBeLessThanOrEqual(maxLength);
        console.log(`Max length validation: ${actualLength}/${maxLength}`);
      }
    });
  });

  test('Chat input error scenarios', async ({ page }) => {
    await test.step('Navigate to chat', async () => {
      await page.goto('/chat');
      await agent.waitForPageStability(page);
    });

    await test.step('Test empty message submission', async () => {
      const chatInput = page.locator('textarea, input[placeholder*="chat"]');
      const sendButton = page.locator('button[type="submit"], button:has-text("Send")');
      
      if (await chatInput.count() > 0 && await sendButton.count() > 0) {
        // Try to send empty message
        await chatInput.fill('');
        await sendButton.click();
        
        // Should either prevent submission or show error
        await page.waitForTimeout(1000);
        
        const errorMessages = page.locator(
          '.error, [role="alert"], text*="empty", text*"required"'
        );
        
        if (await errorMessages.count() > 0) {
          console.log('Empty message validation working');
        } else {
          // Check if button was disabled or no action occurred
          const messages = page.locator('[data-testid="message"], .message');
          const messageCount = await messages.count();
          console.log(`Empty message handling: ${messageCount} messages in chat`);
        }
      }
    });

    await test.step('Test extremely long messages', async () => {
      const chatInput = page.locator('textarea, input[placeholder*="chat"]');
      const sendButton = page.locator('button[type="submit"]');
      
      if (await chatInput.count() > 0) {
        const longMessage = 'This is a very long message. '.repeat(200);
        await chatInput.fill(longMessage);
        
        // Check if there's a character limit indicator
        const charLimitIndicators = page.locator(
          '.char-limit, .character-count, text*="character", text*"limit"'
        );
        
        if (await charLimitIndicators.count() > 0) {
          console.log('Character limit indicator found');
        }
        
        await sendButton.click();
        await page.waitForTimeout(3000);
        
        // Verify system handles long messages
        const errorMessages = page.locator(
          '.error, [role="alert"], text*"too long", text*"limit"'
        );
        
        if (await errorMessages.count() > 0) {
          console.log('Long message validation working');
        }
      }
    });

    await test.step('Test rapid message sending', async ({ page }) => {
      const chatInput = page.locator('textarea, input[placeholder*="chat"]');
      const sendButton = page.locator('button[type="submit"]');
      
      if (await chatInput.count() > 0 && await sendButton.count() > 0) {
        const rapidMessages = ['Msg1', 'Msg2', 'Msg3', 'Msg4'];
        
        for (const message of rapidMessages) {
          await chatInput.fill(message);
          await sendButton.click();
          await page.waitForTimeout(50); // Very short delay
        }
        
        // Check for rate limiting or queue management
        await page.waitForTimeout(2000);
        
        const rateLimitMessages = page.locator(
          'text*"rate limit", text*"too fast", text*"slow down", .rate-limit'
        );
        
        if (await rateLimitMessages.count() > 0) {
          console.log('Rate limiting detected');
        }
        
        const messages = page.locator('[data-testid="message"], .message');
        const messageCount = await messages.count();
        console.log(`Rapid sending test: ${messageCount} messages processed`);
      }
    });
  });

  test('Network error scenarios', async ({ page }) => {
    await test.step('Test slow network conditions', async () => {
      // Simulate slow network
      await page.route('**/*', async (route) => {
        await new Promise(resolve => setTimeout(resolve, 2000)); // 2 second delay
        await route.continue();
      });
      
      const startTime = Date.now();
      await page.goto('/dashboard');
      const loadTime = Date.now() - startTime;
      
      // Should show loading indicators
      const loadingIndicators = page.locator(
        '[data-testid="loading"], .loading, .spinner, text*"Loading"'
      );
      
      console.log(`Slow network load time: ${loadTime}ms`);
      
      // Clean up route
      await page.unroute('**/*');
    });

    await test.step('Test network failure recovery', async () => {
      // Simulate API failures
      await page.route('**/api/**', (route) => {
        route.abort('failed');
      });
      
      await page.goto('/chat');
      await page.waitForTimeout(3000);
      
      // Look for error states
      const errorStates = page.locator(
        '[data-testid="error"], .error, text*"Error", text*"Failed", ' +
        'text*"connection", text*"network"'
      );
      
      if (await errorStates.count() > 0) {
        console.log('Network error handling detected');
        
        // Look for retry mechanisms
        const retryButtons = page.locator(
          'button:has-text("Retry"), button:has-text("Try Again")'
        );
        
        if (await retryButtons.count() > 0) {
          console.log('Retry mechanism available');
          
          // Clean up route before retrying
          await page.unroute('**/api/**');
          
          // Test retry functionality
          await retryButtons.first().click();
          await page.waitForTimeout(2000);
          
          // Verify retry worked
          const successStates = page.locator(
            '.success, text*"Success", [data-testid="success"]'
          );
          
          if (await successStates.count() > 0) {
            console.log('Retry mechanism successful');
          }
        }
      } else {
        // Clean up route if no error states found
        await page.unroute('**/api/**');
      }
    });

    await test.step('Test offline behavior', async () => {
      // Simulate offline
      await page.context().setOffline(true);
      
      await page.goto('/');
      await page.waitForTimeout(2000);
      
      // Look for offline indicators
      const offlineIndicators = page.locator(
        '.offline, text*"offline", text*"Offline", text*"connection"'
      );
      
      if (await offlineIndicators.count() > 0) {
        console.log('Offline state detected');
      }
      
      // Test functionality in offline mode
      const interactiveElements = page.locator('button, a, [role="button"]');
      const elementCount = await interactiveElements.count();
      
      if (elementCount > 0) {
        await interactiveElements.first().click();
        await page.waitForTimeout(1000);
        
        // Should show appropriate offline messages
        const offlineMessages = page.locator(
          'text*"offline", text*"connection required", .offline-message'
        );
        
        if (await offlineMessages.count() > 0) {
          console.log('Offline interaction handling detected');
        }
      }
      
      // Restore online
      await page.context().setOffline(false);
    });
  });

  test('JavaScript error resilience', async ({ page }) => {
    let jsErrors = [];
    let consoleErrors = [];
    
    // Capture JavaScript errors
    page.on('pageerror', (error) => {
      jsErrors.push({
        message: error.message,
        stack: error.stack,
        timestamp: new Date().toISOString()
      });
    });
    
    // Capture console errors
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push({
          text: msg.text(),
          timestamp: new Date().toISOString()
        });
      }
    });

    await test.step('Navigate through application with error monitoring', async () => {
      const pages = ['/', '/chat', '/dashboard', '/cost', '/settings'];
      
      for (const pagePath of pages) {
        await page.goto(pagePath);
        await agent.waitForPageStability(page);
        
        // Interact with page to trigger potential errors
        const interactiveElements = page.locator('button, a, input, select');
        const elementCount = await interactiveElements.count();
        
        for (let i = 0; i < Math.min(elementCount, 3); i++) {
          try {
            const element = interactiveElements.nth(i);
            await element.click({ timeout: 1000 });
            await page.waitForTimeout(500);
          } catch (error) {
            // Ignore interaction errors, we're testing error resilience
          }
        }
      }
    });

    await test.step('Verify error handling resilience', async () => {
      console.log(`JavaScript errors found: ${jsErrors.length}`);
      console.log(`Console errors found: ${consoleErrors.length}`);
      
      if (jsErrors.length > 0) {
        console.log('JavaScript Errors:', jsErrors);
      }
      
      if (consoleErrors.length > 0) {
        console.log('Console Errors:', consoleErrors);
      }
      
      // Filter out non-critical errors
      const criticalJsErrors = jsErrors.filter(error => 
        !error.message.includes('Warning') && 
        !error.message.includes('DevTools') &&
        !error.message.includes('Extension') &&
        !error.message.includes('ResizeObserver')
      );
      
      const criticalConsoleErrors = consoleErrors.filter(error =>
        !error.text.includes('Warning') &&
        !error.text.includes('DevTools') &&
        !error.text.includes('Extension')
      );
      
      // Application should be resilient to errors
      expect(criticalJsErrors.length).toBeLessThan(10);
      expect(criticalConsoleErrors.length).toBeLessThan(15);
      
      // Verify application is still functional despite errors
      await page.goto('/');
      const mainContent = page.locator('main, [role="main"], body');
      await expect(mainContent).toBeVisible();
    });
  });

  test('Accessibility error scenarios', async ({ page }) => {
    await test.step('Test keyboard navigation resilience', async () => {
      await page.goto('/');
      await agent.waitForPageStability(page);
      
      // Test tab navigation
      let tabCount = 0;
      const maxTabs = 20;
      
      while (tabCount < maxTabs) {
        await page.keyboard.press('Tab');
        await page.waitForTimeout(100);
        
        const focusedElement = page.locator(':focus');
        const hasFocus = await focusedElement.count() > 0;
        
        if (!hasFocus) {
          break; // End of tabbable elements
        }
        
        tabCount++;
      }
      
      console.log(`Keyboard navigation: ${tabCount} tabbable elements found`);
      expect(tabCount).toBeGreaterThan(3); // Should have some tabbable elements
    });

    await test.step('Test screen reader compatibility', async () => {
      await page.goto('/');
      
      // Check for ARIA labels and roles
      const ariaElements = page.locator('[aria-label], [aria-labelledby], [role]');
      const ariaCount = await ariaElements.count();
      
      console.log(`ARIA elements found: ${ariaCount}`);
      expect(ariaCount).toBeGreaterThan(5); // Should have basic ARIA support
      
      // Check for heading structure
      const headings = page.locator('h1, h2, h3, h4, h5, h6');
      const headingCount = await headings.count();
      
      console.log(`Headings found: ${headingCount}`);
      expect(headingCount).toBeGreaterThan(0); // Should have proper heading structure
      
      // Check for alt text on images
      const images = page.locator('img');
      const imageCount = await images.count();
      
      if (imageCount > 0) {
        let imagesWithAlt = 0;
        for (let i = 0; i < imageCount; i++) {
          const img = images.nth(i);
          const altText = await img.getAttribute('alt');
          if (altText !== null) {
            imagesWithAlt++;
          }
        }
        
        console.log(`Images with alt text: ${imagesWithAlt}/${imageCount}`);
      }
    });

    await test.step('Test high contrast mode compatibility', async () => {
      // Simulate high contrast mode
      await page.addStyleTag({
        content: `
          * {
            background: black !important;
            color: white !important;
            border-color: white !important;
          }
        `
      });
      
      await page.waitForTimeout(1000);
      
      // Verify content is still readable and interactive
      const interactiveElements = page.locator('button, a, input');
      const elementCount = await interactiveElements.count();
      
      if (elementCount > 0) {
        const firstElement = interactiveElements.first();
        await expect(firstElement).toBeVisible();
        
        console.log('High contrast mode compatibility verified');
      }
    });
  });

  test('Data corruption and recovery', async ({ page }) => {
    await test.step('Test form data persistence during errors', async () => {
      await page.goto('/settings');
      await agent.waitForPageStability(page);
      
      const textInputs = page.locator('input[type="text"], textarea');
      
      if (await textInputs.count() > 0) {
        const testData = 'Test data for persistence';
        await textInputs.first().fill(testData);
        
        // Simulate page refresh
        await page.reload();
        await agent.waitForPageStability(page);
        
        // Check if data persisted (or if there's a recovery mechanism)
        const restoredValue = await textInputs.first().inputValue();
        
        if (restoredValue === testData) {
          console.log('Form data persisted through refresh');
        } else {
          console.log('Form data not persisted (expected behavior)');
        }
      }
    });

    await test.step('Test chat history preservation', async () => {
      await page.goto('/chat');
      await agent.waitForPageStability(page);
      
      const chatInput = page.locator('textarea, input[placeholder*="chat"]');
      const sendButton = page.locator('button[type="submit"]');
      
      if (await chatInput.count() > 0 && await sendButton.count() > 0) {
        const testMessage = 'Test message for history preservation';
        await chatInput.fill(testMessage);
        await sendButton.click();
        
        await page.waitForTimeout(2000);
        
        // Refresh page
        await page.reload();
        await agent.waitForPageStability(page);
        
        // Check if chat history is preserved
        const messages = page.locator('[data-testid="message"], .message');
        const messageCount = await messages.count();
        
        console.log(`Chat messages after refresh: ${messageCount}`);
        
        if (messageCount > 0) {
          console.log('Chat history preserved');
        } else {
          console.log('Chat history cleared (may be expected behavior)');
        }
      }
    });
  });
});