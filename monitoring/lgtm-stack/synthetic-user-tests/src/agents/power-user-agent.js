const UserAgentBase = require('./user-agent-base');

/**
 * Simulates a power user with advanced usage patterns
 * Focuses on complex workflows, advanced features, and edge cases
 */
class PowerUserAgent extends UserAgentBase {
  constructor(options = {}) {
    super({
      ...options,
      behavior: 'power-user',
      speed: options.speed || 'fast'
    });
    
    this.workflowState = {
      activeWorkflows: new Set(),
      completedTasks: new Set(),
      advancedFeatures: new Set(),
      performanceMetrics: {
        actionsPerMinute: 0,
        successRate: 0,
        complexityScore: 0
      }
    };
    
    this.startTime = Date.now();
  }

  /**
   * Main execution flow for power user behavior
   */
  async execute(page) {
    this.logAction('power_user_session_start');
    
    try {
      // Advanced chat workflows
      await this.executeAdvancedChatWorkflows(page);
      
      // Complex dashboard operations
      await this.performComplexDashboardOperations(page);
      
      // Advanced settings configuration
      await this.configureAdvancedSettings(page);
      
      // Cost optimization workflows
      await this.performCostOptimization(page);
      
      // Edge case testing
      await this.testEdgeCases(page);
      
      // Batch operations
      await this.performBatchOperations(page);
      
      this.calculatePerformanceMetrics();
      
      this.logAction('power_user_session_complete', {
        workflowsExecuted: this.workflowState.activeWorkflows.size,
        tasksCompleted: this.workflowState.completedTasks.size,
        advancedFeaturesUsed: this.workflowState.advancedFeatures.size,
        performanceMetrics: this.workflowState.performanceMetrics
      });
      
    } catch (error) {
      this.logError(error, { phase: 'power_user_execution' });
      await this.takeScreenshot(page, 'power-user-error');
      throw error;
    }
  }

  /**
   * Execute advanced chat workflows
   */
  async executeAdvancedChatWorkflows(page) {
    this.logAction('executing_advanced_chat_workflows');
    
    await page.goto('/chat');
    await this.waitForPageStability(page);
    
    const advancedChatScenarios = [
      {
        name: 'complex_data_analysis',
        messages: [
          'Show me all Airtable bases and their table structures',
          'Analyze sales data trends for the last 6 months with breakdown by region and product category',
          'Create a comprehensive report comparing Q3 vs Q4 performance metrics',
          'Generate data visualizations for customer acquisition funnel'
        ]
      },
      {
        name: 'batch_operations',
        messages: [
          'List all records in the CRM base where status equals "prospects"',
          'Update all prospect records to "qualified" where lead_score > 80',
          'Create follow-up tasks for all qualified prospects',
          'Send automated email notifications to the sales team'
        ]
      },
      {
        name: 'advanced_queries',
        messages: [
          'Find all records created in the last 30 days with missing required fields',
          'Cross-reference customer data between CRM and Orders tables',
          'Identify potential duplicate records based on email and company name',
          'Generate a data quality report with recommendations'
        ]
      }
    ];

    for (const scenario of advancedChatScenarios) {
      this.logAction('executing_chat_scenario', { scenario: scenario.name });
      this.workflowState.activeWorkflows.add(scenario.name);
      
      await this.executeMultiTurnConversation(page, scenario.messages);
      this.workflowState.completedTasks.add(scenario.name);
      this.workflowState.advancedFeatures.add('multi_turn_conversation');
    }
  }

  /**
   * Execute multi-turn conversation
   */
  async executeMultiTurnConversation(page, messages) {
    const chatInput = page.locator('textarea, input[placeholder*="chat"], [data-testid="chat-input"]');
    
    for (let i = 0; i < messages.length; i++) {
      const message = messages[i];
      
      // Wait for previous response to complete
      if (i > 0) {
        await this.waitForChatCompletion(page);
      }
      
      // Type and send message
      await this.typeHumanLike(page, chatInput, message);
      
      const sendButton = page.locator('button[type="submit"], button:has-text("Send"), [data-testid="send-button"]');
      await this.humanClick(page, sendButton);
      
      // Monitor function calls
      await this.monitorFunctionCalls(page);
      
      // Brief wait between messages
      await page.waitForTimeout(this.getRandomDelay('action'));
    }
  }

  /**
   * Wait for chat completion
   */
  async waitForChatCompletion(page, timeout = 30000) {
    try {
      // Wait for typing indicators to disappear
      await page.waitForSelector('[data-testid="typing-indicator"], .typing-indicator', { 
        state: 'hidden', 
        timeout 
      });
    } catch {
      // Continue if no typing indicator found
    }
    
    // Wait for function calls to complete
    try {
      await page.waitForSelector('[data-testid="function-call"][data-status="executing"]', { 
        state: 'hidden', 
        timeout: timeout / 2 
      });
    } catch {
      // Continue if no active function calls
    }
  }

  /**
   * Monitor function calls during execution
   */
  async monitorFunctionCalls(page) {
    const functionCalls = page.locator('[data-testid="function-call"], .function-call');
    const callCount = await functionCalls.count();
    
    if (callCount > 0) {
      this.workflowState.advancedFeatures.add('function_calls');
      this.logAction('function_calls_detected', { count: callCount });
      
      // Monitor function call statuses
      for (let i = 0; i < callCount; i++) {
        const call = functionCalls.nth(i);
        const status = await call.getAttribute('data-status') || 'unknown';
        const name = await call.getAttribute('data-function-name') || 'unknown';
        
        this.logAction('function_call_status', { 
          name, 
          status, 
          index: i 
        });
      }
    }
  }

  /**
   * Perform complex dashboard operations
   */
  async performComplexDashboardOperations(page) {
    this.logAction('performing_complex_dashboard_operations');
    
    await page.goto('/dashboard');
    await this.waitForPageStability(page);
    
    // Advanced tab navigation and interaction
    const dashboardTabs = ['workspace', 'health', 'metrics', 'activity', 'overview'];
    
    for (const tabName of dashboardTabs) {
      await this.performAdvancedTabOperations(page, tabName);
    }
    
    // Test dashboard refresh and real-time updates
    await this.testDashboardRefresh(page);
    
    // Test dashboard customization
    await this.testDashboardCustomization(page);
    
    this.workflowState.advancedFeatures.add('advanced_dashboard_ops');
  }

  /**
   * Perform advanced operations on dashboard tabs
   */
  async performAdvancedTabOperations(page, tabName) {
    this.logAction('advanced_tab_operations', { tab: tabName });
    
    const tab = page.locator(`[data-value="${tabName}"], [aria-controls*="${tabName}"], text="${tabName}"`);
    
    if (await tab.count() > 0) {
      await this.humanClick(page, tab.first());
      await this.waitForPageStability(page);
      
      // Perform tab-specific advanced operations
      switch (tabName) {
        case 'workspace':
          await this.performWorkspaceOperations(page);
          break;
        case 'health':
          await this.performHealthMonitoringOperations(page);
          break;
        case 'metrics':
          await this.performMetricsAnalysis(page);
          break;
        case 'activity':
          await this.performActivityAnalysis(page);
          break;
        case 'overview':
          await this.performOverviewOperations(page);
          break;
      }
      
      this.workflowState.completedTasks.add(`advanced_${tabName}_ops`);
    }
  }

  /**
   * Perform workspace operations
   */
  async performWorkspaceOperations(page) {
    // Look for workspace-specific controls
    const workspaceControls = page.locator('[data-testid*="workspace"], .workspace-control, .airtable-workspace');
    
    if (await workspaceControls.count() > 0) {
      // Test workspace filtering and sorting
      const filterButtons = page.locator('button:has-text("Filter"), button:has-text("Sort"), select');
      
      for (let i = 0; i < Math.min(await filterButtons.count(), 2); i++) {
        const button = filterButtons.nth(i);
        await this.humanClick(page, button);
        await page.waitForTimeout(this.getRandomDelay('action'));
      }
      
      this.workflowState.advancedFeatures.add('workspace_filtering');
    }
  }

  /**
   * Perform health monitoring operations
   */
  async performHealthMonitoringOperations(page) {
    // Look for service health indicators
    const healthIndicators = page.locator('[data-testid*="health"], .health-indicator, .service-status');
    
    if (await healthIndicators.count() > 0) {
      // Click on service details
      for (let i = 0; i < Math.min(await healthIndicators.count(), 3); i++) {
        const indicator = healthIndicators.nth(i);
        await indicator.hover();
        await page.waitForTimeout(this.getRandomDelay('action'));
        
        // Look for detail views
        if (Math.random() < 0.3) {
          await this.humanClick(page, indicator);
          await page.waitForTimeout(this.getRandomDelay('action'));
        }
      }
      
      this.workflowState.advancedFeatures.add('health_monitoring');
    }
  }

  /**
   * Perform metrics analysis
   */
  async performMetricsAnalysis(page) {
    // Look for chart interactions
    const charts = page.locator('canvas, svg, [data-testid*="chart"], .chart');
    
    if (await charts.count() > 0) {
      // Interact with charts
      for (let i = 0; i < Math.min(await charts.count(), 2); i++) {
        const chart = charts.nth(i);
        await chart.hover();
        
        // Try clicking on chart elements
        if (Math.random() < 0.4) {
          const box = await chart.boundingBox();
          if (box) {
            await page.mouse.click(
              box.x + box.width * 0.5,
              box.y + box.height * 0.5
            );
            await page.waitForTimeout(this.getRandomDelay('action'));
          }
        }
      }
      
      this.workflowState.advancedFeatures.add('metrics_analysis');
    }
  }

  /**
   * Perform activity analysis
   */
  async performActivityAnalysis(page) {
    // Look for activity filters and search
    const activityFilters = page.locator('input[placeholder*="search"], select, button:has-text("Filter")');
    
    if (await activityFilters.count() > 0) {
      const searchInput = activityFilters.filter({ hasText: '' }).first();
      
      if (await searchInput.count() > 0) {
        await this.typeHumanLike(page, searchInput, 'error');
        await page.waitForTimeout(this.getRandomDelay('action'));
        
        // Clear search
        await searchInput.fill('');
        await page.waitForTimeout(this.getRandomDelay('action'));
      }
      
      this.workflowState.advancedFeatures.add('activity_filtering');
    }
  }

  /**
   * Perform overview operations
   */
  async performOverviewOperations(page) {
    // Look for metric cards and interact with them
    const metricCards = page.locator('.card, [data-testid*="metric"], .metric-card');
    
    if (await metricCards.count() > 0) {
      // Click through metric cards for details
      for (let i = 0; i < Math.min(await metricCards.count(), 4); i++) {
        const card = metricCards.nth(i);
        await card.hover();
        
        if (Math.random() < 0.3) {
          await this.humanClick(page, card);
          await page.waitForTimeout(this.getRandomDelay('action'));
        }
      }
      
      this.workflowState.advancedFeatures.add('metric_card_interaction');
    }
  }

  /**
   * Test dashboard refresh functionality
   */
  async testDashboardRefresh(page) {
    const refreshButton = page.locator('button:has-text("Refresh"), [data-testid="refresh"], button[title*="refresh"]');
    
    if (await refreshButton.count() > 0) {
      await this.humanClick(page, refreshButton.first());
      await this.waitForPageStability(page);
      this.workflowState.advancedFeatures.add('dashboard_refresh');
      this.logAction('dashboard_refreshed');
    }
  }

  /**
   * Test dashboard customization
   */
  async testDashboardCustomization(page) {
    // Look for customization controls
    const customizationControls = page.locator('button:has-text("Settings"), button:has-text("Customize"), [data-testid*="customize"]');
    
    if (await customizationControls.count() > 0) {
      await this.humanClick(page, customizationControls.first());
      await page.waitForTimeout(this.getRandomDelay('action'));
      this.workflowState.advancedFeatures.add('dashboard_customization');
    }
  }

  /**
   * Configure advanced settings
   */
  async configureAdvancedSettings(page) {
    this.logAction('configuring_advanced_settings');
    
    await page.goto('/settings');
    await this.waitForPageStability(page);
    
    const advancedSettingsTabs = ['models', 'airtable', 'security'];
    
    for (const tabName of advancedSettingsTabs) {
      await this.configureAdvancedSettingsTab(page, tabName);
    }
    
    this.workflowState.advancedFeatures.add('advanced_settings_config');
  }

  /**
   * Configure advanced settings for specific tab
   */
  async configureAdvancedSettingsTab(page, tabName) {
    const tab = page.locator(`text="${tabName}"`, { exact: false });
    
    if (await tab.count() > 0) {
      await this.humanClick(page, tab.first());
      await this.waitForPageStability(page);
      
      // Make advanced configuration changes
      const advancedControls = page.locator('select, input[type="range"], input[type="number"]');
      const controlCount = await advancedControls.count();
      
      for (let i = 0; i < Math.min(controlCount, 3); i++) {
        const control = advancedControls.nth(i);
        const tagName = await control.evaluate(el => el.tagName);
        
        try {
          if (tagName === 'SELECT') {
            const options = control.locator('option');
            const optionCount = await options.count();
            if (optionCount > 1) {
              const randomOption = options.nth(faker.number.int({ min: 1, max: optionCount - 1 }));
              await this.humanClick(page, control);
              await this.humanClick(page, randomOption);
            }
          } else if (tagName === 'INPUT') {
            const inputType = await control.getAttribute('type');
            if (inputType === 'range') {
              const min = parseFloat(await control.getAttribute('min') || '0');
              const max = parseFloat(await control.getAttribute('max') || '100');
              const newValue = faker.number.float({ min, max });
              await control.fill(newValue.toString());
            } else if (inputType === 'number') {
              const currentValue = await control.inputValue();
              const numValue = parseFloat(currentValue) || 0;
              const newValue = Math.max(0, numValue + faker.number.int({ min: -10, max: 10 }));
              await control.fill(newValue.toString());
            }
          }
          
          await page.waitForTimeout(this.getRandomDelay('action'));
        } catch (error) {
          this.logger.debug('Settings control interaction failed', { error: error.message });
        }
      }
      
      this.workflowState.completedTasks.add(`configured_${tabName}_settings`);
    }
  }

  /**
   * Perform cost optimization workflows
   */
  async performCostOptimization(page) {
    this.logAction('performing_cost_optimization');
    
    await page.goto('/cost');
    await this.waitForPageStability(page);
    
    // Analyze cost trends
    await this.analyzeCostTrends(page);
    
    // Set budget alerts
    await this.configureBudgetAlerts(page);
    
    // Optimize model usage
    await this.optimizeModelUsage(page);
    
    this.workflowState.advancedFeatures.add('cost_optimization');
  }

  /**
   * Analyze cost trends
   */
  async analyzeCostTrends(page) {
    const costCharts = page.locator('canvas, svg, [data-testid*="chart"]');
    
    if (await costCharts.count() > 0) {
      // Interact with cost visualization
      for (let i = 0; i < Math.min(await costCharts.count(), 2); i++) {
        const chart = costCharts.nth(i);
        await chart.hover();
        
        const box = await chart.boundingBox();
        if (box) {
          // Click on different parts of the chart
          const clickPoints = [
            { x: box.x + box.width * 0.25, y: box.y + box.height * 0.5 },
            { x: box.x + box.width * 0.75, y: box.y + box.height * 0.5 }
          ];
          
          for (const point of clickPoints) {
            await page.mouse.click(point.x, point.y);
            await page.waitForTimeout(this.getRandomDelay('action'));
          }
        }
      }
      
      this.workflowState.advancedFeatures.add('cost_trend_analysis');
    }
  }

  /**
   * Configure budget alerts
   */
  async configureBudgetAlerts(page) {
    const budgetControls = page.locator('input[type="number"], button:has-text("Alert"), button:has-text("Budget")');
    
    if (await budgetControls.count() > 0) {
      const budgetInput = budgetControls.filter({ hasText: '' }).first();
      
      if (await budgetInput.count() > 0) {
        const budgetValue = faker.number.int({ min: 50, max: 500 });
        await budgetInput.fill(budgetValue.toString());
        await page.waitForTimeout(this.getRandomDelay('action'));
      }
      
      this.workflowState.advancedFeatures.add('budget_alert_config');
    }
  }

  /**
   * Optimize model usage
   */
  async optimizeModelUsage(page) {
    // Look for model usage breakdown
    const modelBreakdown = page.locator('[data-testid*="model"], .model-usage, text*="Model"');
    
    if (await modelBreakdown.count() > 0) {
      // Analyze model efficiency
      await modelBreakdown.first().scrollIntoViewIfNeeded();
      await this.simulateReading(page);
      
      this.workflowState.advancedFeatures.add('model_usage_optimization');
    }
  }

  /**
   * Test edge cases
   */
  async testEdgeCases(page) {
    this.logAction('testing_edge_cases');
    
    const edgeCases = [
      async () => await this.testEmptyStates(page),
      async () => await this.testErrorHandling(page),
      async () => await this.testPerformanceLimits(page),
      async () => await this.testConcurrentOperations(page)
    ];
    
    for (const edgeCase of edgeCases) {
      try {
        await edgeCase();
      } catch (error) {
        this.logError(error, { context: 'edge_case_testing' });
      }
    }
    
    this.workflowState.advancedFeatures.add('edge_case_testing');
  }

  /**
   * Test empty states
   */
  async testEmptyStates(page) {
    // Try to trigger empty states by clearing data or accessing empty views
    await page.goto('/chat');
    
    // Clear chat history if possible
    const clearButton = page.locator('button:has-text("Clear"), button:has-text("New Chat"), [data-testid="clear"]');
    if (await clearButton.count() > 0) {
      await this.humanClick(page, clearButton.first());
      await this.waitForPageStability(page);
    }
  }

  /**
   * Test error handling
   */
  async testErrorHandling(page) {
    // Try to trigger errors with invalid inputs
    await page.goto('/chat');
    
    const chatInput = page.locator('textarea, input[placeholder*="chat"]');
    if (await chatInput.count() > 0) {
      // Send extremely long message
      const longMessage = 'a'.repeat(10000);
      await chatInput.fill(longMessage);
      
      const sendButton = page.locator('button[type="submit"], button:has-text("Send")');
      if (await sendButton.count() > 0) {
        await this.humanClick(page, sendButton.first());
        await page.waitForTimeout(2000);
      }
    }
  }

  /**
   * Test performance limits
   */
  async testPerformanceLimits(page) {
    // Send rapid-fire requests
    await page.goto('/chat');
    
    const chatInput = page.locator('textarea, input[placeholder*="chat"]');
    const sendButton = page.locator('button[type="submit"], button:has-text("Send")');
    
    if (await chatInput.count() > 0 && await sendButton.count() > 0) {
      for (let i = 0; i < 3; i++) {
        await chatInput.fill(`Performance test message ${i + 1}`);
        await this.humanClick(page, sendButton.first());
        await page.waitForTimeout(100); // Very short delay
      }
    }
  }

  /**
   * Test concurrent operations
   */
  async testConcurrentOperations(page) {
    // Open multiple tabs/operations simultaneously
    const tabs = ['dashboard', 'cost', 'settings'];
    
    for (const tab of tabs) {
      // Simulate rapid navigation
      await page.goto(`/${tab}`);
      await page.waitForTimeout(100);
    }
  }

  /**
   * Perform batch operations
   */
  async performBatchOperations(page) {
    this.logAction('performing_batch_operations');
    
    await page.goto('/chat');
    await this.waitForPageStability(page);
    
    const batchCommands = [
      'List all my Airtable bases',
      'For each base, show me the table count and record count',
      'Identify tables with more than 1000 records',
      'Generate a summary report of database usage'
    ];
    
    await this.executeMultiTurnConversation(page, batchCommands);
    this.workflowState.advancedFeatures.add('batch_operations');
  }

  /**
   * Calculate performance metrics
   */
  calculatePerformanceMetrics() {
    const duration = (Date.now() - this.startTime) / 1000 / 60; // minutes
    const totalActions = this.workflowState.completedTasks.size + this.workflowState.advancedFeatures.size;
    
    this.workflowState.performanceMetrics = {
      actionsPerMinute: Math.round(totalActions / duration),
      successRate: Math.min(100, (this.workflowState.completedTasks.size / totalActions) * 100),
      complexityScore: this.workflowState.advancedFeatures.size * 5 // Each advanced feature adds 5 points
    };
  }

  /**
   * Get workflow summary
   */
  getWorkflowSummary() {
    return {
      agentId: this.id,
      behavior: this.behavior,
      workflowsExecuted: Array.from(this.workflowState.activeWorkflows),
      tasksCompleted: Array.from(this.workflowState.completedTasks),
      advancedFeaturesUsed: Array.from(this.workflowState.advancedFeatures),
      performanceMetrics: this.workflowState.performanceMetrics,
      duration: Date.now() - this.startTime
    };
  }
}

module.exports = PowerUserAgent;