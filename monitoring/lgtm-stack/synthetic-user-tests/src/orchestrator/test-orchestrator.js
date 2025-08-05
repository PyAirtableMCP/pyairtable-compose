const { spawn } = require('child_process');
const path = require('path');
const winston = require('winston');
const cron = require('node-cron');
const MetricsCollector = require('../monitoring/metrics-collector');
const fs = require('fs').promises;

/**
 * Test Orchestrator for managing synthetic user test execution
 * Coordinates multiple user agents and test scenarios
 */
class TestOrchestrator {
  constructor(options = {}) {
    this.config = {
      maxConcurrentTests: options.maxConcurrentTests || 3,
      testTimeout: options.testTimeout || 300000, // 5 minutes
      retryAttempts: options.retryAttempts || 2,
      scheduleEnabled: options.scheduleEnabled || false,
      cronSchedule: options.cronSchedule || '0 */6 * * *', // Every 6 hours
      outputDir: options.outputDir || path.join(__dirname, '../../test-results'),
      baseUrl: options.baseUrl || 'http://localhost:3000',
      browsers: options.browsers || ['chromium'],
      ...options
    };
    
    this.metricsCollector = new MetricsCollector(options.metrics || {});
    this.activeTests = new Map();
    this.testQueue = [];
    this.setupLogger();
    
    // Test suite configurations
    this.testSuites = {
      'new-user-onboarding': {
        spec: 'tests/user-journeys/new-user-onboarding.spec.js',
        priority: 1,
        timeout: 180000, // 3 minutes
        browsers: ['chromium', 'firefox'],
        agents: ['new-user'],
        description: 'New user onboarding and exploration workflows'
      },
      'power-user-workflows': {
        spec: 'tests/user-journeys/power-user-workflows.spec.js',
        priority: 2,
        timeout: 300000, // 5 minutes
        browsers: ['chromium'],
        agents: ['power-user'],
        description: 'Advanced power user workflows and edge cases'
      },
      'error-handling': {
        spec: 'tests/error-scenarios/error-handling.spec.js',
        priority: 3,
        timeout: 240000, // 4 minutes
        browsers: ['chromium'],
        agents: ['error-prone'],
        description: 'Error scenarios and recovery testing'
      },
      'mobile-responsive': {
        spec: 'tests/mobile/mobile-responsive.spec.js',
        priority: 4,
        timeout: 200000, // 3.5 minutes
        browsers: ['chromium'],
        agents: ['mobile'],
        description: 'Mobile device and responsive design testing'
      },
      'accessibility': {
        spec: 'tests/accessibility/accessibility.spec.js',
        priority: 5,
        timeout: 180000, // 3 minutes
        browsers: ['chromium'],
        agents: ['accessibility'],
        description: 'Accessibility and screen reader compatibility'
      },
      'performance': {
        spec: 'tests/performance/performance.spec.js',
        priority: 6,
        timeout: 240000, // 4 minutes
        browsers: ['chromium'],
        agents: ['performance'],
        description: 'Performance benchmarking and optimization'
      }
    };
  }

  /**
   * Setup logger
   */
  setupLogger() {
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
      ),
      defaultMeta: { service: 'test-orchestrator' },
      transports: [
        new winston.transports.Console({
          format: winston.format.combine(
            winston.format.colorize(),
            winston.format.simple()
          )
        }),
        new winston.transports.File({
          filename: 'logs/orchestrator.log',
          format: winston.format.json()
        })
      ]
    });
  }

  /**
   * Initialize orchestrator
   */
  async initialize() {
    try {
      // Ensure output directory exists
      await fs.mkdir(this.config.outputDir, { recursive: true });
      await fs.mkdir('logs', { recursive: true });
      
      this.logger.info('Test orchestrator initialized', {
        maxConcurrentTests: this.config.maxConcurrentTests,
        outputDir: this.config.outputDir,
        baseUrl: this.config.baseUrl
      });
      
      // Setup scheduled execution if enabled
      if (this.config.scheduleEnabled) {
        this.setupScheduledExecution();
      }
      
      return true;
    } catch (error) {
      this.logger.error('Failed to initialize orchestrator', { error: error.message });
      throw error;
    }
  }

  /**
   * Setup scheduled test execution
   */
  setupScheduledExecution() {
    this.logger.info('Setting up scheduled execution', { 
      schedule: this.config.cronSchedule 
    });
    
    cron.schedule(this.config.cronSchedule, async () => {
      this.logger.info('Starting scheduled test execution');
      try {
        await this.runAllTests();
      } catch (error) {
        this.logger.error('Scheduled test execution failed', { error: error.message });
      }
    });
  }

  /**
   * Run all test suites
   */
  async runAllTests(options = {}) {
    const startTime = Date.now();
    const results = {
      startTime,
      endTime: null,
      duration: 0,
      totalTests: 0,
      passedTests: 0,
      failedTests: 0,
      suiteResults: new Map(),
      summary: null
    };
    
    this.logger.info('Starting comprehensive test execution', {
      suites: Object.keys(this.testSuites).length,
      maxConcurrent: this.config.maxConcurrentTests
    });
    
    try {
      // Sort test suites by priority
      const sortedSuites = Object.entries(this.testSuites)
        .sort(([,a], [,b]) => a.priority - b.priority);
      
      // Run test suites with concurrency control
      await this.runTestSuitesWithConcurrency(sortedSuites, results, options);
      
      results.endTime = Date.now();
      results.duration = results.endTime - results.startTime;
      
      // Generate comprehensive report
      results.summary = await this.generateExecutionSummary(results);
      
      // Export results
      await this.exportResults(results);
      
      this.logger.info('Test execution completed', {
        duration: results.duration,
        totalTests: results.totalTests,
        passedTests: results.passedTests,
        failedTests: results.failedTests,
        successRate: results.totalTests > 0 ? (results.passedTests / results.totalTests) * 100 : 0
      });
      
      return results;
      
    } catch (error) {
      this.logger.error('Test execution failed', { error: error.message, stack: error.stack });
      results.endTime = Date.now();
      results.duration = results.endTime - results.startTime;
      throw error;
    }
  }

  /**
   * Run test suites with concurrency control
   */
  async runTestSuitesWithConcurrency(sortedSuites, results, options) {
    const runningTests = new Set();
    const pendingSuites = [...sortedSuites];
    
    while (pendingSuites.length > 0 || runningTests.size > 0) {
      // Start new tests if we have capacity
      while (runningTests.size < this.config.maxConcurrentTests && pendingSuites.length > 0) {
        const [suiteName, suiteConfig] = pendingSuites.shift();
        
        if (options.suites && !options.suites.includes(suiteName)) {
          continue; // Skip if not in requested suites
        }
        
        const testPromise = this.runTestSuite(suiteName, suiteConfig)
          .then(result => {
            results.suiteResults.set(suiteName, result);
            results.totalTests += result.totalTests;
            results.passedTests += result.passedTests;
            results.failedTests += result.failedTests;
            runningTests.delete(testPromise);
            return result;
          })
          .catch(error => {
            this.logger.error(`Test suite ${suiteName} failed`, { error: error.message });
            results.suiteResults.set(suiteName, {
              suiteName,
              status: 'failed',
              error: error.message,
              totalTests: 0,
              passedTests: 0,
              failedTests: 1
            });
            results.failedTests += 1;
            runningTests.delete(testPromise);
            return null;
          });
        
        runningTests.add(testPromise);
      }
      
      // Wait for at least one test to complete
      if (runningTests.size > 0) {
        await Promise.race(runningTests);
      }
    }
  }

  /**
   * Run a single test suite
   */
  async runTestSuite(suiteName, suiteConfig) {
    const testId = this.metricsCollector.recordTestStart({
      testType: suiteName,
      userAgent: suiteConfig.agents.join(','),
      page: 'multiple'
    });
    
    this.logger.info(`Starting test suite: ${suiteName}`, {
      description: suiteConfig.description,
      browsers: suiteConfig.browsers,
      timeout: suiteConfig.timeout
    });
    
    const results = {
      suiteName,
      testId,
      status: 'running',
      startTime: Date.now(),
      endTime: null,
      duration: 0,
      totalTests: 0,
      passedTests: 0,
      failedTests: 0,
      browserResults: new Map(),
      artifacts: []
    };
    
    try {
      // Run tests on each configured browser
      for (const browser of suiteConfig.browsers) {
        const browserResult = await this.runTestOnBrowser(
          suiteName, 
          suiteConfig, 
          browser
        );
        
        results.browserResults.set(browser, browserResult);
        results.totalTests += browserResult.totalTests;
        results.passedTests += browserResult.passedTests;
        results.failedTests += browserResult.failedTests;
        
        if (browserResult.artifacts) {
          results.artifacts.push(...browserResult.artifacts);
        }
      }
      
      results.status = results.failedTests === 0 ? 'passed' : 'failed';
      results.endTime = Date.now();
      results.duration = results.endTime - results.startTime;
      
      // Record completion
      this.metricsCollector.recordTestCompletion(testId, {
        testType: suiteName,
        userAgent: suiteConfig.agents.join(','),
        status: results.status,
        duration: results.duration,
        metrics: {
          totalTests: results.totalTests,
          passedTests: results.passedTests,
          failedTests: results.failedTests
        }
      });
      
      this.logger.info(`Test suite completed: ${suiteName}`, {
        status: results.status,
        duration: results.duration,
        totalTests: results.totalTests,
        passedTests: results.passedTests,
        failedTests: results.failedTests
      });
      
      return results;
      
    } catch (error) {
      results.status = 'failed';
      results.error = error.message;
      results.endTime = Date.now();
      results.duration = results.endTime - results.startTime;
      
      this.metricsCollector.recordTestCompletion(testId, {
        testType: suiteName,
        userAgent: suiteConfig.agents.join(','),
        status: 'failed',
        errors: [error.message]
      });
      
      throw error;
    }
  }

  /**
   * Run test on specific browser
   */
  async runTestOnBrowser(suiteName, suiteConfig, browser) {
    const outputFile = path.join(
      this.config.outputDir,
      `${suiteName}-${browser}-${Date.now()}.json`
    );
    
    const playwrightArgs = [
      'test',
      suiteConfig.spec,
      '--project', this.getBrowserProject(browser),
      '--reporter=json',
      '--output', outputFile,
      '--timeout', suiteConfig.timeout.toString()
    ];
    
    // Add base URL if configured
    if (this.config.baseUrl) {
      process.env.BASE_URL = this.config.baseUrl;
    }
    
    return new Promise((resolve, reject) => {
      const playwrightProcess = spawn('npx', ['playwright', ...playwrightArgs], {
        cwd: path.join(__dirname, '../../'),
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env }
      });
      
      let stdout = '';
      let stderr = '';
      
      playwrightProcess.stdout.on('data', (data) => {
        stdout += data.toString();
      });
      
      playwrightProcess.stderr.on('data', (data) => {
        stderr += data.toString();
      });
      
      const timeout = setTimeout(() => {
        playwrightProcess.kill('SIGKILL');
        reject(new Error(`Test suite ${suiteName} on ${browser} timed out after ${suiteConfig.timeout}ms`));
      }, suiteConfig.timeout + 30000); // Add 30s buffer
      
      playwrightProcess.on('close', async (code) => {
        clearTimeout(timeout);
        
        try {
          const result = await this.parseTestResults(outputFile, {
            suiteName,
            browser,
            exitCode: code,
            stdout,
            stderr
          });
          
          resolve(result);
        } catch (error) {
          reject(error);
        }
      });
      
      playwrightProcess.on('error', (error) => {
        clearTimeout(timeout);
        reject(new Error(`Failed to start Playwright process: ${error.message}`));
      });
    });
  }

  /**
   * Get browser project name for Playwright
   */
  getBrowserProject(browser) {
    const projectMap = {
      'chromium': 'Desktop Chrome',
      'firefox': 'Desktop Firefox',
      'webkit': 'Desktop Safari',
      'mobile-chrome': 'Mobile Chrome',
      'mobile-safari': 'Mobile Safari'
    };
    
    return projectMap[browser] || 'Desktop Chrome';
  }

  /**
   * Parse test results from Playwright output
   */
  async parseTestResults(outputFile, context) {
    const result = {
      suiteName: context.suiteName,
      browser: context.browser,
      exitCode: context.exitCode,
      totalTests: 0,
      passedTests: 0,
      failedTests: 0,
      skippedTests: 0,
      testResults: [],
      artifacts: [],
      duration: 0
    };
    
    try {
      // Check if output file exists
      try {
        await fs.access(outputFile);
      } catch {
        // File doesn't exist, parse from stdout/stderr
        this.logger.warn(`Test output file not found: ${outputFile}`);
        result.error = 'No test output file generated';
        result.failedTests = 1;
        return result;
      }
      
      const outputContent = await fs.readFile(outputFile, 'utf8');
      const testOutput = JSON.parse(outputContent);
      
      // Parse Playwright JSON output
      if (testOutput.stats) {
        result.totalTests = testOutput.stats.expected || 0;
        result.passedTests = testOutput.stats.passed || 0;
        result.failedTests = testOutput.stats.failed || 0;
        result.skippedTests = testOutput.stats.skipped || 0;
        result.duration = testOutput.stats.duration || 0;
      }
      
      if (testOutput.suites) {
        result.testResults = this.extractTestDetails(testOutput.suites);
      }
      
      // Collect artifacts
      if (testOutput.config && testOutput.config.outputDir) {
        result.artifacts.push({
          type: 'test-results',
          path: outputFile,
          description: 'Playwright test results JSON'
        });
      }
      
    } catch (error) {
      this.logger.error(`Failed to parse test results: ${error.message}`, {
        outputFile,
        context
      });
      
      result.error = error.message;
      result.failedTests = 1;
    }
    
    return result;
  }

  /**
   * Extract test details from Playwright output
   */
  extractTestDetails(suites) {
    const testDetails = [];
    
    const extractFromSuite = (suite) => {
      if (suite.specs) {
        for (const spec of suite.specs) {
          if (spec.tests) {
            for (const test of spec.tests) {
              testDetails.push({
                title: test.title,
                status: test.outcome,
                duration: test.results?.[0]?.duration || 0,
                error: test.results?.[0]?.error?.message,
                location: spec.file
              });
            }
          }
        }
      }
      
      if (suite.suites) {
        for (const subSuite of suite.suites) {
          extractFromSuite(subSuite);
        }
      }
    };
    
    for (const suite of suites) {
      extractFromSuite(suite);
    }
    
    return testDetails;
  }

  /**
   * Generate execution summary
   */
  async generateExecutionSummary(results) {
    const summary = {
      executionId: `exec-${Date.now()}`,
      timestamp: new Date().toISOString(),
      duration: results.duration,
      totalSuites: results.suiteResults.size,
      totalTests: results.totalTests,
      passedTests: results.passedTests,
      failedTests: results.failedTests,
      successRate: results.totalTests > 0 ? (results.passedTests / results.totalTests) * 100 : 0,
      suiteBreakdown: {},
      performanceMetrics: this.metricsCollector.getMetricsSummary(),
      recommendations: []
    };
    
    // Suite-level breakdown
    for (const [suiteName, suiteResult] of results.suiteResults) {
      summary.suiteBreakdown[suiteName] = {
        status: suiteResult.status,
        duration: suiteResult.duration,
        totalTests: suiteResult.totalTests,
        passedTests: suiteResult.passedTests,
        failedTests: suiteResult.failedTests,
        successRate: suiteResult.totalTests > 0 ? 
          (suiteResult.passedTests / suiteResult.totalTests) * 100 : 0
      };
    }
    
    // Generate recommendations
    summary.recommendations = this.generateRecommendations(summary);
    
    return summary;
  }

  /**
   * Generate recommendations based on test results
   */
  generateRecommendations(summary) {
    const recommendations = [];
    
    // Overall success rate
    if (summary.successRate < 95) {
      recommendations.push({
        category: 'reliability',
        priority: 'high',
        message: `Overall test success rate is ${summary.successRate.toFixed(1)}%. Investigate failing tests to improve application stability.`
      });
    }
    
    // Suite-specific recommendations
    for (const [suiteName, suite] of Object.entries(summary.suiteBreakdown)) {
      if (suite.successRate < 90) {
        recommendations.push({
          category: 'test_quality',
          priority: 'medium',
          message: `Test suite "${suiteName}" has ${suite.successRate.toFixed(1)}% success rate. Review and stabilize failing tests.`
        });
      }
      
      if (suite.duration > 300000) { // 5 minutes
        recommendations.push({
          category: 'performance',
          priority: 'low',
          message: `Test suite "${suiteName}" takes ${(suite.duration / 60000).toFixed(1)} minutes. Consider optimizing test execution time.`
        });
      }
    }
    
    // Performance-based recommendations
    const perfMetrics = summary.performanceMetrics;
    if (perfMetrics && perfMetrics.performance) {
      for (const [metricName, perf] of Object.entries(perfMetrics.performance)) {
        if (metricName.includes('page_load_time') && perf.avg > 8000) {
          recommendations.push({
            category: 'performance',
            priority: 'high',
            message: `Average page load time for ${metricName} is ${(perf.avg / 1000).toFixed(2)}s. Consider performance optimization.`
          });
        }
      }
    }
    
    return recommendations;
  }

  /**
   * Export test results
   */
  async exportResults(results) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    
    try {
      // Export main results
      const resultsFile = path.join(
        this.config.outputDir,
        `execution-results-${timestamp}.json`
      );
      
      await fs.writeFile(resultsFile, JSON.stringify(results, null, 2));
      
      // Generate and export comprehensive report
      await this.metricsCollector.generateTestReport(this.config.outputDir);
      
      // Export metrics for Grafana
      await this.metricsCollector.exportMetricsForGrafana(this.config.outputDir);
      
      this.logger.info('Test results exported', {
        resultsFile,
        outputDir: this.config.outputDir
      });
      
    } catch (error) {
      this.logger.error('Failed to export results', { error: error.message });
    }
  }

  /**
   * Run specific test suites
   */
  async runTestSuites(suiteNames, options = {}) {
    return this.runAllTests({ ...options, suites: suiteNames });
  }

  /**
   * Run single test suite
   */
  async runSingleTestSuite(suiteName, options = {}) {
    if (!this.testSuites[suiteName]) {
      throw new Error(`Test suite not found: ${suiteName}`);
    }
    
    return this.runTestSuites([suiteName], options);
  }

  /**
   * Get test suite information
   */
  getTestSuiteInfo(suiteName) {
    if (suiteName) {
      return this.testSuites[suiteName] || null;
    }
    return this.testSuites;
  }

  /**
   * Add custom test suite
   */
  addTestSuite(name, config) {
    this.testSuites[name] = {
      priority: config.priority || 999,
      timeout: config.timeout || 180000,
      browsers: config.browsers || ['chromium'],
      agents: config.agents || ['custom'],
      description: config.description || 'Custom test suite',
      ...config
    };
    
    this.logger.info(`Added custom test suite: ${name}`);
  }

  /**
   * Stop all running tests
   */
  async stopAllTests() {
    this.logger.info('Stopping all running tests');
    
    for (const [testId, testProcess] of this.activeTests) {
      try {
        testProcess.kill('SIGTERM');
        this.logger.info(`Stopped test: ${testId}`);
      } catch (error) {
        this.logger.error(`Failed to stop test ${testId}`, { error: error.message });
      }
    }
    
    this.activeTests.clear();
    this.testQueue.length = 0;
  }

  /**
   * Get orchestrator status
   */
  getStatus() {
    return {
      activeTests: this.activeTests.size,
      queuedTests: this.testQueue.length,
      availableSlots: this.config.maxConcurrentTests - this.activeTests.size,
      config: {
        maxConcurrentTests: this.config.maxConcurrentTests,
        testTimeout: this.config.testTimeout,
        scheduleEnabled: this.config.scheduleEnabled,
        cronSchedule: this.config.cronSchedule
      },
      testSuites: Object.keys(this.testSuites),
      uptime: process.uptime()
    };
  }

  /**
   * Cleanup resources
   */
  async cleanup() {
    this.logger.info('Orchestrator cleanup starting');
    
    try {
      await this.stopAllTests();
      await this.metricsCollector.cleanup();
      
      this.logger.info('Orchestrator cleanup completed');
    } catch (error) {
      this.logger.error('Error during cleanup', { error: error.message });
    }
  }
}

module.exports = TestOrchestrator;