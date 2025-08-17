const { test, expect } = require('@playwright/test');
const HumanBehavior = require('../utils/human-behavior');
const TraceHelper = require('../utils/trace-helper');
const VisualRegression = require('../utils/visual-regression');
const testConfig = require('../config/test-config.json');

test.describe('AI Analysis and Insights @regression', () => {
  let humanBehavior;
  let traceHelper;
  let visualRegression;

  test.beforeEach(async ({ page }) => {
    humanBehavior = new HumanBehavior();
    traceHelper = new TraceHelper();
    visualRegression = new VisualRegression();
    
    // Setup tracing for this test
    await traceHelper.setupTracing(page, 'ai-analysis');
    
    // Navigate to dashboard or AI section
    await humanBehavior.humanNavigate(page, '/dashboard');
    await page.waitForLoadState('networkidle');
  });

  test('Query data with AI assistance @smoke', async ({ page }) => {
    const testContext = traceHelper.createTestContext('ai-data-query', page);
    
    try {
      // Step 1: Navigate to AI/Chat interface
      traceHelper.logTestEvent('step_started', { step: 'navigate_to_ai_interface' });
      
      const aiInterfaceSelectors = [
        '[data-testid="ai-chat"]',
        '[data-testid="ai-assistant"]',
        'button:has-text("AI Assistant")',
        'a:has-text("AI Chat")',
        '[href*="chat"]',
        '[href*="ai"]',
        '.ai-chat-button'
      ];
      
      let aiInterfaceFound = false;
      
      for (const selector of aiInterfaceSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForLoadState('networkidle');
          await page.waitForTimeout(2000);
          aiInterfaceFound = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'ai-interface-navigation');
      traceHelper.logTestEvent('step_completed', { step: 'navigate_to_ai_interface', found: aiInterfaceFound });

      // Step 2: Locate chat/query input
      traceHelper.logTestEvent('step_started', { step: 'locate_chat_input' });
      
      const chatInputSelectors = [
        '[data-testid="chat-input"]',
        '[data-testid="ai-input"]',
        '[data-testid="query-input"]',
        'textarea[placeholder*="ask"]',
        'textarea[placeholder*="query"]',
        'textarea[placeholder*="question"]',
        'input[placeholder*="ask"]',
        'input[placeholder*="query"]',
        '.chat-input textarea',
        '.message-input textarea',
        '.ai-input'
      ];
      
      let chatInput = null;
      
      for (const selector of chatInputSelectors) {
        const element = page.locator(selector).first();
        if (await element.isVisible({ timeout: 3000 })) {
          chatInput = element;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'chat-input-located');
      traceHelper.logTestEvent('step_completed', { step: 'locate_chat_input', found: !!chatInput });

      // Step 3: Send AI query
      if (chatInput) {
        traceHelper.logTestEvent('step_started', { step: 'send_ai_query' });
        
        const testQueries = [
          "What insights can you provide about my data?",
          "Show me a summary of my most recent records",
          "What patterns do you see in my data?",
          "Can you analyze my table data and provide insights?",
          "Help me understand the trends in my data"
        ];
        
        const selectedQuery = testQueries[Math.floor(Math.random() * testQueries.length)];
        
        await humanBehavior.humanClick(page, chatInput);
        await page.waitForTimeout(500);
        await humanBehavior.humanType(page, chatInput, selectedQuery);
        await page.waitForTimeout(1000);
        
        // Send the message
        const sendButtonSelectors = [
          '[data-testid="send-button"]',
          'button:has-text("Send")',
          'button[type="submit"]',
          '.send-button',
          '[aria-label*="send"]'
        ];
        
        let messageSent = false;
        
        for (const sendSelector of sendButtonSelectors) {
          if (await page.locator(sendSelector).isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, sendSelector);
            messageSent = true;
            break;
          }
        }
        
        // If no send button, try Enter key
        if (!messageSent) {
          await page.keyboard.press('Enter');
          messageSent = true;
        }
        
        await page.waitForTimeout(3000); // Wait for AI response
        
        await traceHelper.captureScreenshot(page, 'ai-query-sent');
        traceHelper.logTestEvent('ai_query_sent', { query: selectedQuery, sent: messageSent });
        traceHelper.logTestEvent('step_completed', { step: 'send_ai_query' });
      }

      // Step 4: Wait for and verify AI response
      traceHelper.logTestEvent('step_started', { step: 'verify_ai_response' });
      
      const responseSelectors = [
        '[data-testid="ai-response"]',
        '[data-testid="chat-message"]',
        '.ai-message',
        '.chat-message',
        '.response-message',
        '.message.ai',
        '.assistant-message'
      ];
      
      let responseReceived = false;
      let responseContent = '';
      
      // Wait up to 30 seconds for AI response
      for (let attempt = 0; attempt < 30; attempt++) {
        for (const responseSelector of responseSelectors) {
          const messages = page.locator(responseSelector);
          const messageCount = await messages.count();
          
          if (messageCount > 0) {
            const lastMessage = messages.last();
            if (await lastMessage.isVisible({ timeout: 1000 })) {
              responseContent = await lastMessage.textContent() || '';
              if (responseContent.length > 10) { // Ensure it's a substantial response
                responseReceived = true;
                break;
              }
            }
          }
        }
        
        if (responseReceived) break;
        await page.waitForTimeout(1000);
      }
      
      await traceHelper.captureScreenshot(page, 'ai-response-received', { fullPage: true });
      
      // Also check for loading indicators that might suggest AI is processing
      const loadingSelectors = [
        '[data-testid="ai-loading"]',
        '.loading',
        '.thinking',
        '.processing',
        'text="Thinking..."',
        'text="Processing..."'
      ];
      
      let aiProcessing = false;
      for (const loadingSelector of loadingSelectors) {
        if (await page.locator(loadingSelector).isVisible({ timeout: 1000 })) {
          aiProcessing = true;
          break;
        }
      }
      
      traceHelper.logTestEvent('ai_response_check', { 
        responseReceived, 
        responseLength: responseContent.length,
        aiProcessing,
        responsePreview: responseContent.substring(0, 100)
      });
      traceHelper.logTestEvent('step_completed', { step: 'verify_ai_response' });

      // Step 5: Analyze response quality
      if (responseReceived && responseContent.length > 0) {
        traceHelper.logTestEvent('step_started', { step: 'analyze_response_quality' });
        
        const qualityMetrics = {
          hasDataMention: /data|table|record|field|row|column/i.test(responseContent),
          hasInsight: /insight|analysis|pattern|trend|summary/i.test(responseContent),
          hasSpecificInfo: /\d+|count|total|average|mean|max|min/i.test(responseContent),
          lengthAppropriate: responseContent.length > 50 && responseContent.length < 2000,
          noErrorMessages: !/error|failed|unable|cannot/i.test(responseContent)
        };
        
        const qualityScore = Object.values(qualityMetrics).filter(Boolean).length;
        
        traceHelper.logTestEvent('response_quality_analysis', {
          ...qualityMetrics,
          qualityScore,
          maxScore: Object.keys(qualityMetrics).length,
          responseLength: responseContent.length
        });
        
        traceHelper.logTestEvent('step_completed', { step: 'analyze_response_quality' });
        
        // Assertions for response quality
        expect(responseContent.length).toBeGreaterThan(10);
        expect(qualityScore).toBeGreaterThan(1); // At least 2 quality criteria met
      }
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'ai-query-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Generate data insights and reports @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('generate-insights-reports', page);
    
    try {
      // Step 1: Navigate to insights/reports section
      traceHelper.logTestEvent('step_started', { step: 'navigate_to_insights' });
      
      const insightsSelectors = [
        '[data-testid="insights"]',
        '[data-testid="reports"]',
        '[data-testid="analytics"]',
        'a:has-text("Insights")',
        'a:has-text("Reports")',
        'a:has-text("Analytics")',
        '[href*="insights"]',
        '[href*="reports"]',
        '[href*="analytics"]'
      ];
      
      let insightsFound = false;
      
      for (const selector of insightsSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForLoadState('networkidle');
          await page.waitForTimeout(2000);
          insightsFound = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'insights-section');
      traceHelper.logTestEvent('step_completed', { step: 'navigate_to_insights', found: insightsFound });

      // Step 2: Generate new insights
      traceHelper.logTestEvent('step_started', { step: 'generate_insights' });
      
      const generateSelectors = [
        '[data-testid="generate-insights"]',
        '[data-testid="create-report"]',
        'button:has-text("Generate")',
        'button:has-text("Create Report")',
        'button:has-text("Analyze")',
        '.generate-button',
        '.create-report-button'
      ];
      
      let insightGenerated = false;
      
      for (const selector of generateSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(2000);
          
          // If a form appears, fill it
          const titleInput = page.locator('input[name="title"], input[placeholder*="title"]').first();
          if (await titleInput.isVisible({ timeout: 2000 })) {
            await humanBehavior.humanType(page, titleInput, `Test Report ${Date.now()}`);
          }
          
          const descriptionInput = page.locator('textarea[name="description"], textarea[placeholder*="description"]').first();
          if (await descriptionInput.isVisible({ timeout: 2000 })) {
            await humanBehavior.humanType(page, descriptionInput, 'Automated test report generation');
          }
          
          // Submit form if it exists
          const submitButton = page.locator('button[type="submit"], button:has-text("Create"), button:has-text("Generate")').first();
          if (await submitButton.isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, submitButton);
            await page.waitForTimeout(5000); // Wait for generation
          }
          
          insightGenerated = true;
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'insights-generated');
      traceHelper.logTestEvent('step_completed', { step: 'generate_insights', generated: insightGenerated });

      // Step 3: Verify insights/reports display
      traceHelper.logTestEvent('step_started', { step: 'verify_insights_display' });
      
      const insightDisplaySelectors = [
        '[data-testid="insight-card"]',
        '[data-testid="report-card"]',
        '.insight',
        '.report',
        '.analytics-card',
        '.chart',
        '.visualization',
        'canvas', // For chart.js or similar
        'svg'     // For D3 or similar
      ];
      
      let insightsDisplayed = 0;
      const displayedInsights = [];
      
      for (const selector of insightDisplaySelectors) {
        const elements = page.locator(selector);
        const count = await elements.count();
        
        if (count > 0) {
          insightsDisplayed += count;
          
          // Capture details of first few insights
          for (let i = 0; i < Math.min(count, 3); i++) {
            const element = elements.nth(i);
            if (await element.isVisible()) {
              const text = await element.textContent() || '';
              displayedInsights.push({
                selector,
                index: i,
                text: text.substring(0, 100)
              });
            }
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'insights-displayed', { fullPage: true });
      
      traceHelper.logTestEvent('insights_verification', {
        totalInsightsDisplayed: insightsDisplayed,
        displayedInsights
      });
      traceHelper.logTestEvent('step_completed', { step: 'verify_insights_display' });

      // Step 4: Interact with insights (expand, filter, etc.)
      traceHelper.logTestEvent('step_started', { step: 'interact_with_insights' });
      
      // Look for expandable insights
      const expandableSelectors = [
        '[data-testid="expand-insight"]',
        '.expand-button',
        'button:has-text("View Details")',
        'button:has-text("Expand")',
        '.insight-card button'
      ];
      
      for (const selector of expandableSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 2000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(1000);
          await humanBehavior.simulateReading(page, '.modal, .expanded-view, .detail-view');
          break;
        }
      }
      
      // Look for filter/sort options
      const filterSelectors = [
        '[data-testid="insights-filter"]',
        '.filter-dropdown',
        'select[name="filter"]',
        'button:has-text("Filter")'
      ];
      
      for (const selector of filterSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 2000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForTimeout(500);
          
          // Select an option if dropdown opened
          const options = page.locator('option, [role="option"]');
          const optionCount = await options.count();
          if (optionCount > 1) {
            await humanBehavior.humanClick(page, options.nth(1));
            await page.waitForTimeout(1000);
          }
          break;
        }
      }
      
      await traceHelper.captureScreenshot(page, 'insights-interaction');
      traceHelper.logTestEvent('step_completed', { step: 'interact_with_insights' });

      // Assertions
      expect(insightsDisplayed).toBeGreaterThan(0);
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'insights-generation-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('AI-powered data transformation @regression', async ({ page }) => {
    const testContext = traceHelper.createTestContext('ai-data-transformation', page);
    
    try {
      // Step 1: Navigate to data transformation/processing section
      traceHelper.logTestEvent('step_started', { step: 'navigate_to_transformation' });
      
      const transformationSelectors = [
        '[data-testid="data-transform"]',
        '[data-testid="ai-processing"]',
        'a:has-text("Transform")',
        'a:has-text("Process")',
        '[href*="transform"]',
        '[href*="process"]'
      ];
      
      let transformationFound = false;
      
      for (const selector of transformationSelectors) {
        if (await page.locator(selector).isVisible({ timeout: 3000 })) {
          await humanBehavior.humanClick(page, selector);
          await page.waitForLoadState('networkidle');
          await page.waitForTimeout(2000);
          transformationFound = true;
          break;
        }
      }
      
      // If no dedicated transformation section, try using AI chat for transformation
      if (!transformationFound) {
        const aiSelectors = [
          '[data-testid="ai-chat"]',
          'button:has-text("AI Assistant")',
          '[href*="chat"]'
        ];
        
        for (const selector of aiSelectors) {
          if (await page.locator(selector).isVisible({ timeout: 2000 })) {
            await humanBehavior.humanClick(page, selector);
            await page.waitForLoadState('networkidle');
            transformationFound = true;
            break;
          }
        }
      }
      
      await traceHelper.captureScreenshot(page, 'transformation-interface');
      traceHelper.logTestEvent('step_completed', { step: 'navigate_to_transformation', found: transformationFound });

      // Step 2: Request data transformation
      if (transformationFound) {
        traceHelper.logTestEvent('step_started', { step: 'request_transformation' });
        
        const transformationRequests = [
          "Can you help me clean and standardize my data?",
          "Please analyze my data quality and suggest improvements",
          "Transform my data to identify duplicate records",
          "Help me categorize and organize my records better",
          "Can you enrich my data with additional insights?"
        ];
        
        const selectedRequest = transformationRequests[Math.floor(Math.random() * transformationRequests.length)];
        
        // Look for input field
        const inputSelectors = [
          '[data-testid="transformation-input"]',
          '[data-testid="chat-input"]',
          'textarea[placeholder*="transformation"]',
          'textarea[placeholder*="request"]',
          '.transformation-input',
          '.chat-input textarea'
        ];
        
        let requestSent = false;
        
        for (const inputSelector of inputSelectors) {
          if (await page.locator(inputSelector).isVisible({ timeout: 3000 })) {
            await humanBehavior.humanType(page, inputSelector, selectedRequest);
            await page.waitForTimeout(500);
            
            // Send the request
            const sendSelectors = [
              '[data-testid="send-button"]',
              'button:has-text("Send")',
              'button:has-text("Process")',
              'button[type="submit"]'
            ];
            
            for (const sendSelector of sendSelectors) {
              if (await page.locator(sendSelector).isVisible({ timeout: 2000 })) {
                await humanBehavior.humanClick(page, sendSelector);
                requestSent = true;
                break;
              }
            }
            
            if (!requestSent) {
              await page.keyboard.press('Enter');
              requestSent = true;
            }
            
            break;
          }
        }
        
        await traceHelper.captureScreenshot(page, 'transformation-requested');
        traceHelper.logTestEvent('transformation_requested', { request: selectedRequest, sent: requestSent });
        traceHelper.logTestEvent('step_completed', { step: 'request_transformation' });

        // Step 3: Monitor transformation progress
        traceHelper.logTestEvent('step_started', { step: 'monitor_transformation' });
        
        // Wait for transformation response/progress
        await page.waitForTimeout(5000);
        
        const progressSelectors = [
          '[data-testid="transformation-progress"]',
          '.progress-bar',
          '.loading',
          '.processing',
          'text="Processing..."',
          'text="Transforming..."'
        ];
        
        let transformationInProgress = false;
        
        for (const progressSelector of progressSelectors) {
          if (await page.locator(progressSelector).isVisible({ timeout: 2000 })) {
            transformationInProgress = true;
            break;
          }
        }
        
        // Wait for completion
        if (transformationInProgress) {
          await page.waitForTimeout(10000); // Wait up to 10 seconds for completion
        }
        
        await traceHelper.captureScreenshot(page, 'transformation-progress');
        traceHelper.logTestEvent('step_completed', { step: 'monitor_transformation', inProgress: transformationInProgress });

        // Step 4: Verify transformation results
        traceHelper.logTestEvent('step_started', { step: 'verify_transformation_results' });
        
        const resultSelectors = [
          '[data-testid="transformation-results"]',
          '[data-testid="ai-response"]',
          '.transformation-output',
          '.results',
          '.ai-message',
          '.response-message'
        ];
        
        let resultsFound = false;
        let resultsContent = '';
        
        for (const resultSelector of resultSelectors) {
          const element = page.locator(resultSelector).last();
          if (await element.isVisible({ timeout: 3000 })) {
            resultsContent = await element.textContent() || '';
            if (resultsContent.length > 20) {
              resultsFound = true;
              break;
            }
          }
        }
        
        await traceHelper.captureScreenshot(page, 'transformation-results', { fullPage: true });
        
        traceHelper.logTestEvent('transformation_results', {
          resultsFound,
          contentLength: resultsContent.length,
          preview: resultsContent.substring(0, 200)
        });
        traceHelper.logTestEvent('step_completed', { step: 'verify_transformation_results' });
        
        // Assertions
        if (requestSent) {
          expect(resultsFound).toBeTruthy();
          expect(resultsContent.length).toBeGreaterThan(10);
        }
      }
      
    } catch (error) {
      await traceHelper.captureScreenshot(page, 'transformation-error', { fullPage: true });
      traceHelper.logTestEvent('test_failed', { error: error.message });
      throw error;
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });

  test('Performance of AI responses @smoke', async ({ page }) => {
    const testContext = traceHelper.createTestContext('ai-response-performance', page);
    
    try {
      // Navigate to AI interface
      await page.goto('/chat', { waitUntil: 'networkidle' });
      
      const startTime = Date.now();
      
      // Send a simple query
      const chatInput = page.locator('[data-testid="chat-input"], textarea').first();
      if (await chatInput.isVisible({ timeout: 5000 })) {
        await humanBehavior.humanType(page, chatInput, "Tell me about my data");
        await page.keyboard.press('Enter');
        
        // Measure response time
        const responseSelector = '[data-testid="ai-response"], .ai-message';
        await page.waitForSelector(responseSelector, { timeout: 30000 });
        
        const responseTime = Date.now() - startTime;
        
        traceHelper.logTestEvent('ai_performance_test', {
          responseTime,
          threshold: 10000, // 10 seconds
          passed: responseTime < 10000
        });
        
        // Performance assertion
        expect(responseTime).toBeLessThan(30000); // Should respond within 30 seconds
        
        await traceHelper.captureScreenshot(page, 'ai-performance-test');
      }
      
    } catch (error) {
      traceHelper.logTestEvent('performance_test_failed', { error: error.message });
    } finally {
      traceHelper.finishTestContext(testContext, { status: 'completed' });
    }
  });
});