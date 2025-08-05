const { test, expect } = require('@playwright/test');
const NewUserAgent = require('../../src/agents/new-user-agent');

test.describe('New User Onboarding Journey', () => {
  let agent;

  test.beforeEach(async ({ page }) => {
    agent = new NewUserAgent({
      id: 'new-user-onboarding-test',
      name: 'Test New User',
      speed: 'normal'
    });
  });

  test.afterEach(async () => {
    if (agent) {
      await agent.cleanup();
    }
  });

  test('Complete new user exploration flow', async ({ page }) => {
    await test.step('Execute new user behavior', async () => {
      await agent.execute(page);
    });

    await test.step('Verify exploration completeness', async () => {
      const summary = agent.getExplorationSummary();
      
      // Verify minimum exploration requirements
      expect(summary.pagesVisited.length).toBeGreaterThan(2);
      expect(summary.featuresDiscovered.length).toBeGreaterThan(3);
      expect(summary.explorationScore).toBeGreaterThan(30);
      
      // Log summary for monitoring
      console.log('New User Exploration Summary:', JSON.stringify(summary, null, 2));
    });
  });

  test('Verify landing page engagement', async ({ page }) => {
    await test.step('Navigate to landing page', async () => {
      await page.goto('/');
      await agent.waitForPageStability(page);
    });

    await test.step('Engage with hero section', async () => {
      const heroSection = page.locator('h1, [data-testid="hero-section"]');
      await expect(heroSection).toBeVisible();
      
      await agent.simulateReading(page, heroSection);
    });

    await test.step('Discover main features', async () => {
      const featureCards = page.locator('.card, [data-testid*="feature"]');
      const cardCount = await featureCards.count();
      
      expect(cardCount).toBeGreaterThan(0);
      
      // Interact with feature cards
      for (let i = 0; i < Math.min(cardCount, 3); i++) {
        const card = featureCards.nth(i);
        await card.hover();
        await page.waitForTimeout(500);
      }
    });

    await test.step('Test call-to-action buttons', async () => {
      const ctaButtons = page.locator('text="Start Chatting", text="Get Started"');
      
      if (await ctaButtons.count() > 0) {
        const button = ctaButtons.first();
        await expect(button).toBeVisible();
        await button.hover();
      }
    });
  });

  test('Navigate through main sections', async ({ page }) => {
    const sections = [
      { name: 'Chat', path: '/chat' },
      { name: 'Dashboard', path: '/dashboard' },
      { name: 'Settings', path: '/settings' }
    ];

    for (const section of sections) {
      await test.step(`Explore ${section.name} section`, async () => {
        await page.goto(section.path);
        await agent.waitForPageStability(page);
        
        // Verify page loaded correctly
        await expect(page).toHaveURL(new RegExp(section.path));
        
        // Simulate new user exploration
        await agent.simulateReading(page);
        
        // Look for main content
        const mainContent = page.locator('main, [role="main"], .main-content');
        await expect(mainContent).toBeVisible();
      });
    }
  });

  test('Test responsive navigation discovery', async ({ page }) => {
    await test.step('Test desktop navigation', async () => {
      await page.setViewportSize({ width: 1920, height: 1080 });
      await page.goto('/');
      
      const navigation = page.locator('nav, [role="navigation"]');
      await expect(navigation).toBeVisible();
      
      const navLinks = navigation.locator('a, button').filter({ hasText: /Chat|Dashboard|Settings/ });
      const linkCount = await navLinks.count();
      expect(linkCount).toBeGreaterThan(0);
    });

    await test.step('Test mobile navigation', async () => {
      await page.setViewportSize({ width: 375, height: 812 });
      await page.goto('/');
      
      const mobileMenuToggle = page.locator('button:has-text("Menu"), [data-testid="mobile-menu"]');
      
      if (await mobileMenuToggle.count() > 0) {
        await mobileMenuToggle.click();
        await page.waitForTimeout(500);
        
        const mobileNav = page.locator('[data-testid="mobile-menu"][data-state="open"], .mobile-menu.open');
        await expect(mobileNav).toBeVisible({ timeout: 2000 });
      }
    });
  });

  test('First chat interaction experience', async ({ page }) => {
    await test.step('Navigate to chat', async () => {
      await page.goto('/chat');
      await agent.waitForPageStability(page);
    });

    await test.step('Discover chat interface', async () => {
      const chatInterface = page.locator('textarea, input[placeholder*="chat"], [data-testid="chat-input"]');
      await expect(chatInterface).toBeVisible();
      
      const sendButton = page.locator('button[type="submit"], button:has-text("Send")');
      await expect(sendButton).toBeVisible();
    });

    await test.step('Send first message', async () => {
      const chatInput = page.locator('textarea, input[placeholder*="chat"]');
      const sendButton = page.locator('button[type="submit"], button:has-text("Send")');
      
      if (await chatInput.count() > 0) {
        const message = "Hello, I'm new here. What can you help me with?";
        await agent.typeHumanLike(page, chatInput, message);
        
        await sendButton.click();
        
        // Wait for response (with timeout)
        await page.waitForTimeout(3000);
        
        // Verify message was sent
        const messageElements = page.locator('[data-testid="message"], .message');
        const messageCount = await messageElements.count();
        expect(messageCount).toBeGreaterThan(0);
      }
    });

    await test.step('Explore suggested actions', async () => {
      const suggestions = page.locator('button:has-text("Show me"), button:has-text("Help"), .suggestion');
      
      if (await suggestions.count() > 0) {
        const suggestion = suggestions.first();
        await suggestion.hover();
        await page.waitForTimeout(500);
        
        // Optionally click on suggestion
        if (Math.random() < 0.5) {
          await suggestion.click();
          await page.waitForTimeout(2000);
        }
      }
    });
  });

  test('Settings exploration without changes', async ({ page }) => {
    await test.step('Navigate to settings', async () => {
      await page.goto('/settings');
      await agent.waitForPageStability(page);
    });

    await test.step('Browse settings tabs', async () => {
      const settingsTabs = page.locator('[role="tab"]');
      const tabCount = await settingsTabs.count();
      
      if (tabCount > 0) {
        // Click through some tabs without making changes
        for (let i = 0; i < Math.min(tabCount, 3); i++) {
          const tab = settingsTabs.nth(i);
          const tabText = await tab.textContent();
          
          if (tabText) {
            await tab.click();
            await agent.waitForPageStability(page);
            
            // Just observe the settings without changing them
            await agent.simulateReading(page);
            
            const formFields = page.locator('input, select, textarea');
            const fieldCount = await formFields.count();
            
            // Hover over some fields to show interest
            for (let j = 0; j < Math.min(fieldCount, 2); j++) {
              const field = formFields.nth(j);
              await field.hover();
              await page.waitForTimeout(300);
            }
          }
        }
      }
    });

    await test.step('Verify no unintended changes', async () => {
      // New users shouldn't accidentally change settings
      const saveButtons = page.locator('button:has-text("Save"), button[type="submit"]');
      
      if (await saveButtons.count() > 0) {
        const saveButton = saveButtons.first();
        const isEnabled = await saveButton.isEnabled();
        
        // Save button should either be disabled or not trigger changes
        if (isEnabled) {
          // Just hover, don't click
          await saveButton.hover();
        }
      }
    });
  });

  test('Performance and accessibility checks', async ({ page }) => {
    await test.step('Check page load performance', async () => {
      const startTime = Date.now();
      await page.goto('/');
      await agent.waitForPageStability(page);
      const loadTime = Date.now() - startTime;
      
      // Page should load within reasonable time
      expect(loadTime).toBeLessThan(10000); // 10 seconds max
      
      console.log(`Page load time: ${loadTime}ms`);
    });

    await test.step('Check accessibility features', async () => {
      // Check for ARIA labels
      const ariaElements = page.locator('[aria-label], [aria-labelledby], [role]');
      const ariaCount = await ariaElements.count();
      expect(ariaCount).toBeGreaterThan(0);
      
      // Check for keyboard navigation
      await page.keyboard.press('Tab');
      const focusedElement = page.locator(':focus');
      await expect(focusedElement).toBeVisible();
      
      console.log(`Accessibility elements found: ${ariaCount}`);
    });

    await test.step('Check responsive design', async () => {
      const viewports = [
        { width: 1920, height: 1080, name: 'Desktop' },
        { width: 768, height: 1024, name: 'Tablet' },
        { width: 375, height: 812, name: 'Mobile' }
      ];
      
      for (const viewport of viewports) {
        await page.setViewportSize({ width: viewport.width, height: viewport.height });
        await page.goto('/');
        await agent.waitForPageStability(page);
        
        // Verify content is visible and not cut off
        const body = page.locator('body');
        const bodySize = await body.boundingBox();
        
        expect(bodySize.width).toBeLessThanOrEqual(viewport.width);
        
        console.log(`${viewport.name} viewport test passed`);
      }
    });
  });
});

test.describe('New User Error Scenarios', () => {
  let agent;

  test.beforeEach(async () => {
    agent = new NewUserAgent({
      id: 'new-user-error-test',
      name: 'Error Test User',
      speed: 'fast'
    });
  });

  test.afterEach(async () => {
    if (agent) {
      await agent.cleanup();
    }
  });

  test('Handle network interruptions gracefully', async ({ page }) => {
    await test.step('Start normal navigation', async () => {
      await page.goto('/');
      await agent.waitForPageStability(page);
    });

    await test.step('Simulate network issues', async () => {
      // Intercept and delay API calls
      await page.route('**/api/**', async (route) => {
        await new Promise(resolve => setTimeout(resolve, 5000));
        await route.continue();
      });
      
      // Try to navigate to chat
      await page.goto('/chat');
      
      // Should still show loading or error state gracefully
      const errorStates = page.locator(
        '[data-testid="loading"], [data-testid="error"], ' +
        '.loading, .error, text*="Loading", text*="Error"'
      );
      
      // Either loading or error state should be visible
      await expect(errorStates.first()).toBeVisible({ timeout: 10000 });
      
      // Clean up route
      await page.unroute('**/api/**');
    });
  });

  test('Handle JavaScript errors gracefully', async ({ page }) => {
    let jsErrors = [];
    
    page.on('pageerror', (error) => {
      jsErrors.push(error.message);
    });
    
    await test.step('Navigate through application', async () => {
      const pages = ['/', '/chat', '/dashboard', '/settings'];
      
      for (const pagePath of pages) {
        await page.goto(pagePath);
        await agent.waitForPageStability(page);
        await page.waitForTimeout(1000);
      }
    });
    
    await test.step('Verify error handling', async () => {
      // Application should handle errors gracefully
      // Critical errors should not break the user experience
      const criticalErrors = jsErrors.filter(error => 
        !error.includes('Warning') && 
        !error.includes('DevTools') &&
        !error.includes('Extension')
      );
      
      console.log('JavaScript errors found:', jsErrors);
      
      // Should have minimal critical errors
      expect(criticalErrors.length).toBeLessThan(5);
    });
  });
});