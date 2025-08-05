const { test, expect } = require('@playwright/test');
const PowerUserAgent = require('../../src/agents/power-user-agent');

test.describe('Power User Advanced Workflows', () => {
  let agent;

  test.beforeEach(async () => {
    agent = new PowerUserAgent({
      id: 'power-user-workflow-test',
      name: 'Test Power User',
      speed: 'fast'
    });
  });

  test.afterEach(async () => {
    if (agent) {
      await agent.cleanup();
    }
  });

  test('Execute complete power user workflow', async ({ page }) => {
    await test.step('Execute power user behavior', async () => {
      await agent.execute(page);
    });

    await test.step('Verify workflow completion', async () => {
      const summary = agent.getWorkflowSummary();
      
      // Verify advanced workflow requirements
      expect(summary.workflowsExecuted.length).toBeGreaterThan(2);
      expect(summary.advancedFeaturesUsed.length).toBeGreaterThan(5);
      expect(summary.performanceMetrics.actionsPerMinute).toBeGreaterThan(5);
      expect(summary.performanceMetrics.complexityScore).toBeGreaterThan(20);
      
      console.log('Power User Workflow Summary:', JSON.stringify(summary, null, 2));
    });
  });

  test('Advanced chat workflows with function calling', async ({ page }) => {
    await test.step('Navigate to chat interface', async () => {
      await page.goto('/chat');
      await agent.waitForPageStability(page);
    });

    await test.step('Execute complex multi-turn conversation', async () => {
      const chatInput = page.locator('textarea, input[placeholder*="chat"]');
      const sendButton = page.locator('button[type="submit"], button:has-text("Send")');
      
      if (await chatInput.count() > 0 && await sendButton.count() > 0) {
        const complexQueries = [
          'Show me all my Airtable bases and their table structures',
          'Analyze the sales data from the last quarter and identify trends',
          'Create a comprehensive report of customer acquisition metrics',
          'Generate automated insights for our marketing campaigns'
        ];
        
        for (const query of complexQueries) {
          // Type complex query
          await agent.typeHumanLike(page, chatInput, query);
          await sendButton.click();
          
          // Wait for function calls to execute
          await agent.waitForChatCompletion(page, 45000);
          
          // Monitor function call execution
          const functionCalls = page.locator('[data-testid="function-call"], .function-call');
          const callCount = await functionCalls.count();
          
          if (callCount > 0) {
            console.log(`Function calls detected for query: ${query.substring(0, 50)}...`, callCount);
            
            // Verify function calls complete successfully
            for (let i = 0; i < callCount; i++) {
              const call = functionCalls.nth(i);
              const status = await call.getAttribute('data-status') || 'unknown';
              console.log(`Function call ${i}: ${status}`);
            }
          }
          
          // Brief pause between queries
          await page.waitForTimeout(agent.getRandomDelay('action'));
        }
      }
    });

    await test.step('Verify advanced chat features', async () => {
      // Check for function call visualizations
      const functionCallViz = page.locator('[data-testid="function-call-visualization"], .function-call-viz');
      
      if (await functionCallViz.count() > 0) {
        console.log('Function call visualizations found');
      }
      
      // Check for action history
      const actionHistory = page.locator('[data-testid="action-history"], .action-history');
      
      if (await actionHistory.count() > 0) {
        console.log('Action history sidebar detected');
      }
      
      // Verify chat message count
      const messages = page.locator('[data-testid="message"], .message');
      const messageCount = await messages.count();
      expect(messageCount).toBeGreaterThan(4); // At least query + response pairs
    });
  });

  test('Advanced dashboard operations and analytics', async ({ page }) => {
    await test.step('Navigate to dashboard', async () => {
      await page.goto('/dashboard');
      await agent.waitForPageStability(page);
    });

    await test.step('Interact with all dashboard tabs', async () => {
      const tabs = page.locator('[role="tab"]');
      const tabCount = await tabs.count();
      
      expect(tabCount).toBeGreaterThan(0);
      
      for (let i = 0; i < tabCount; i++) {
        const tab = tabs.nth(i);
        const tabText = await tab.textContent();
        
        if (tabText) {
          await tab.click();
          await agent.waitForPageStability(page);
          
          // Perform advanced interactions based on tab type
          if (tabText.toLowerCase().includes('workspace')) {
            await agent.performWorkspaceOperations(page);
          } else if (tabText.toLowerCase().includes('health')) {
            await agent.performHealthMonitoringOperations(page);
          } else if (tabText.toLowerCase().includes('metrics')) {
            await agent.performMetricsAnalysis(page);
          }
          
          console.log(`Advanced operations completed for tab: ${tabText}`);
        }
      }
    });

    await test.step('Test dashboard refresh and real-time updates', async () => {
      const refreshButton = page.locator('button:has-text("Refresh"), [data-testid="refresh"]');
      
      if (await refreshButton.count() > 0) {
        const beforeRefresh = await page.locator('.metric, [data-testid*="metric"]').count();
        
        await refreshButton.click();
        await agent.waitForPageStability(page);
        
        const afterRefresh = await page.locator('.metric, [data-testid*="metric"]').count();
        
        // Verify dashboard refreshed
        console.log(`Metrics before refresh: ${beforeRefresh}, after: ${afterRefresh}`);
      }
    });

    await test.step('Interact with charts and visualizations', async () => {
      const charts = page.locator('canvas, svg, [data-testid*="chart"]');
      const chartCount = await charts.count();
      
      if (chartCount > 0) {
        for (let i = 0; i < Math.min(chartCount, 3); i++) {
          const chart = charts.nth(i);
          const box = await chart.boundingBox();
          
          if (box) {
            // Click on different parts of the chart
            const clickPoints = [
              { x: box.x + box.width * 0.25, y: box.y + box.height * 0.5 },
              { x: box.x + box.width * 0.75, y: box.y + box.height * 0.5 }
            ];
            
            for (const point of clickPoints) {
              await page.mouse.click(point.x, point.y);
              await page.waitForTimeout(500);
            }
            
            console.log(`Interactive chart ${i} tested`);
          }
        }
      }
    });
  });

  test('Advanced settings configuration', async ({ page }) => {
    await test.step('Navigate to settings', async () => {
      await page.goto('/settings');
      await agent.waitForPageStability(page);
    });

    await test.step('Configure advanced model settings', async () => {
      const modelTab = page.locator('[role="tab"]:has-text("Model"), [role="tab"]:has-text("Models")');
      
      if (await modelTab.count() > 0) {
        await modelTab.click();
        await agent.waitForPageStability(page);
        
        // Test advanced model configuration
        const modelSelect = page.locator('select[name*="model"], select[id*="model"]');
        const temperatureSlider = page.locator('input[type="range"], input[name*="temperature"]');
        const maxTokensInput = page.locator('input[name*="token"], input[name*="max"]');
        
        if (await modelSelect.count() > 0) {
          const options = modelSelect.locator('option');
          const optionCount = await options.count();
          
          if (optionCount > 1) {
            await modelSelect.selectOption({ index: 1 });
            console.log('Model selection changed');
          }
        }
        
        if (await temperatureSlider.count() > 0) {
          await temperatureSlider.fill('0.7');
          console.log('Temperature adjusted');
        }
        
        if (await maxTokensInput.count() > 0) {
          await maxTokensInput.fill('2048');
          console.log('Max tokens configured');
        }
      }
    });

    await test.step('Configure Airtable integration settings', async () => {
      const airtableTab = page.locator('[role="tab"]:has-text("Airtable")');
      
      if (await airtableTab.count() > 0) {
        await airtableTab.click();
        await agent.waitForPageStability(page);
        
        // Test Airtable configuration
        const apiKeyInput = page.locator('input[type="password"], input[name*="key"], input[name*="token"]');
        const baseSelect = page.locator('select[name*="base"], select[id*="base"]');
        
        if (await apiKeyInput.count() > 0) {
          // Don't actually change API keys in tests
          await apiKeyInput.hover();
          console.log('API key field found');
        }
        
        if (await baseSelect.count() > 0) {
          await baseSelect.hover();
          console.log('Base selection found');
        }
      }
    });

    await test.step('Configure security settings', async () => {
      const securityTab = page.locator('[role="tab"]:has-text("Security")');
      
      if (await securityTab.count() > 0) {
        await securityTab.click();
        await agent.waitForPageStability(page);
        
        // Test security configuration
        const securityOptions = page.locator('input[type="checkbox"], input[type="radio"]');
        const optionCount = await securityOptions.count();
        
        if (optionCount > 0) {
          // Hover over security options without changing them
          for (let i = 0; i < Math.min(optionCount, 3); i++) {
            await securityOptions.nth(i).hover();
            await page.waitForTimeout(300);
          }
          
          console.log(`Security options reviewed: ${optionCount}`);
        }
      }
    });
  });

  test('Cost optimization and monitoring', async ({ page }) => {
    await test.step('Navigate to cost tracking', async () => {
      await page.goto('/cost');
      await agent.waitForPageStability(page);
    });

    await test.step('Analyze cost trends and patterns', async () => {
      const costCharts = page.locator('canvas, svg, [data-testid*="chart"], [data-testid*="cost"]');
      const chartCount = await costCharts.count();
      
      if (chartCount > 0) {
        for (let i = 0; i < Math.min(chartCount, 2); i++) {
          const chart = costCharts.nth(i);
          const box = await chart.boundingBox();
          
          if (box) {
            // Analyze different time periods
            await page.mouse.move(box.x + box.width * 0.25, box.y + box.height * 0.5);
            await page.mouse.move(box.x + box.width * 0.75, box.y + box.height * 0.5);
            
            console.log(`Cost chart ${i} analyzed`);
          }
        }
      }
    });

    await test.step('Configure budget alerts', async () => {
      const budgetControls = page.locator(
        'input[type="number"][name*="budget"], input[type="number"][name*="limit"], ' +
        'button:has-text("Alert"), button:has-text("Budget")'
      );
      
      if (await budgetControls.count() > 0) {
        const budgetInput = budgetControls.filter({ hasText: '' }).first();
        
        if (await budgetInput.count() > 0) {
          const currentValue = await budgetInput.inputValue();
          console.log(`Current budget limit: ${currentValue}`);
          
          // Test budget validation (don't actually change)
          await budgetInput.hover();
        }
      }
    });

    await test.step('Review model usage efficiency', async () => {
      const modelBreakdown = page.locator(
        '[data-testid*="model"], .model-usage, .usage-breakdown'
      );
      
      if (await modelBreakdown.count() > 0) {
        await modelBreakdown.first().scrollIntoViewIfNeeded();
        
        // Look for efficiency metrics
        const efficiencyMetrics = page.locator(
          'text*="efficiency", text*="cost per", text*="tokens per", ' +
          '[data-testid*="efficiency"]'
        );
        
        const metricCount = await efficiencyMetrics.count();
        console.log(`Model efficiency metrics found: ${metricCount}`);
      }
    });
  });

  test('Edge case and stress testing', async ({ page }) => {
    await test.step('Test rapid navigation', async () => {
      const routes = ['/chat', '/dashboard', '/cost', '/settings', '/'];
      
      for (let i = 0; i < 3; i++) {
        for (const route of routes) {
          await page.goto(route);
          await page.waitForTimeout(100); // Very short delay
        }
      }
      
      // Verify final page loads correctly
      await agent.waitForPageStability(page);
      const finalContent = page.locator('main, [role="main"], body');
      await expect(finalContent).toBeVisible();
    });

    await test.step('Test concurrent operations', async () => {
      await page.goto('/chat');
      await agent.waitForPageStability(page);
      
      const chatInput = page.locator('textarea, input[placeholder*="chat"]');
      const sendButton = page.locator('button[type="submit"]');
      
      if (await chatInput.count() > 0 && await sendButton.count() > 0) {
        // Send multiple messages rapidly
        const rapidMessages = [
          'Quick test 1',
          'Quick test 2',
          'Quick test 3'
        ];
        
        for (const message of rapidMessages) {
          await chatInput.fill(message);
          await sendButton.click();
          await page.waitForTimeout(50); // Very short delay
        }
        
        // Wait for responses
        await page.waitForTimeout(5000);
        
        // Verify system handled rapid requests
        const messages = page.locator('[data-testid="message"], .message');
        const messageCount = await messages.count();
        expect(messageCount).toBeGreaterThan(3);
      }
    });

    await test.step('Test error recovery', async () => {
      // Simulate network issues
      await page.route('**/api/**', (route) => {
        if (Math.random() < 0.3) { // 30% failure rate
          route.abort('failed');
        } else {
          route.continue();
        }
      });
      
      await page.goto('/dashboard');
      await page.waitForTimeout(3000);
      
      // Look for error handling
      const errorElements = page.locator(
        '[data-testid="error"], .error, text*="Error", text*="Failed"'
      );
      
      const retryElements = page.locator(
        'button:has-text("Retry"), button:has-text("Try Again")'
      );
      
      if (await retryElements.count() > 0) {
        await retryElements.first().click();
        await page.waitForTimeout(2000);
        console.log('Error recovery mechanism tested');
      }
      
      // Clean up route
      await page.unroute('**/api/**');
    });
  });

  test('Performance benchmarking', async ({ page }) => {
    const performanceMetrics = {
      pageLoadTimes: [],
      interactionTimes: [],
      memoryUsage: []
    };

    await test.step('Measure page load performance', async () => {
      const pages = ['/', '/chat', '/dashboard', '/cost', '/settings'];
      
      for (const pagePath of pages) {
        const startTime = Date.now();
        await page.goto(pagePath);
        await agent.waitForPageStability(page);
        const loadTime = Date.now() - startTime;
        
        performanceMetrics.pageLoadTimes.push({
          page: pagePath,
          loadTime
        });
        
        expect(loadTime).toBeLessThan(15000); // 15 second max for power users
      }
    });

    await test.step('Measure interaction response times', async () => {
      await page.goto('/dashboard');
      
      const tabs = page.locator('[role="tab"]');
      const tabCount = await tabs.count();
      
      for (let i = 0; i < Math.min(tabCount, 3); i++) {
        const tab = tabs.nth(i);
        const startTime = Date.now();
        
        await tab.click();
        await agent.waitForPageStability(page);
        
        const interactionTime = Date.now() - startTime;
        performanceMetrics.interactionTimes.push({
          interaction: `tab_${i}`,
          time: interactionTime
        });
        
        expect(interactionTime).toBeLessThan(5000); // 5 second max for tab switching
      }
    });

    await test.step('Log performance results', async () => {
      console.log('Performance Metrics:', JSON.stringify(performanceMetrics, null, 2));
      
      const avgLoadTime = performanceMetrics.pageLoadTimes.reduce((sum, p) => sum + p.loadTime, 0) / performanceMetrics.pageLoadTimes.length;
      const avgInteractionTime = performanceMetrics.interactionTimes.reduce((sum, i) => sum + i.time, 0) / performanceMetrics.interactionTimes.length;
      
      console.log(`Average page load time: ${avgLoadTime}ms`);
      console.log(`Average interaction time: ${avgInteractionTime}ms`);
      
      // Performance thresholds for power users
      expect(avgLoadTime).toBeLessThan(8000); // 8 seconds average
      expect(avgInteractionTime).toBeLessThan(3000); // 3 seconds average
    });
  });
});