const axios = require('axios');
const winston = require('winston');

/**
 * LGTM Stack Integration for Test Observability
 * Integrates test execution with Loki (Logs), Grafana (Dashboards), Tempo (Traces), Mimir (Metrics)
 */
class LGTMIntegration {
  constructor(options = {}) {
    this.config = {
      loki: {
        url: options.lokiUrl || process.env.LOKI_URL || 'http://localhost:3100',
        enabled: options.lokiEnabled !== false
      },
      mimir: {
        url: options.mimirUrl || process.env.MIMIR_URL || 'http://localhost:9009',
        enabled: options.mimirEnabled !== false
      },
      tempo: {
        url: options.tempoUrl || process.env.TEMPO_URL || 'http://localhost:3200',
        enabled: options.tempoEnabled !== false
      },
      grafana: {
        url: options.grafanaUrl || process.env.GRAFANA_URL || 'http://localhost:3000',
        enabled: options.grafanaEnabled !== false
      }
    };

    this.testRun = {
      id: options.testRunId || `test-run-${Date.now()}`,
      startTime: Date.now(),
      environment: process.env.ENVIRONMENT || 'test',
      browser: process.env.BROWSER || 'chromium',
      baseUrl: process.env.BASE_URL || 'http://localhost:3000'
    };

    this.metrics = {
      testDurations: [],
      errorCounts: {},
      successRates: {},
      serviceResponseTimes: {}
    };

    // Initialize logger for LGTM integration
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
      ),
      transports: [
        new winston.transports.Console(),
        new winston.transports.File({ 
          filename: `logs/lgtm-integration-${this.testRun.id}.log` 
        })
      ]
    });
  }

  /**
   * Initialize LGTM integration
   */
  async initialize() {
    this.logger.info('Initializing LGTM Stack integration', {
      testRunId: this.testRun.id,
      config: this.config
    });

    await this.validateLGTMServices();
    await this.startTestRunTrace();
    
    this.logger.info('LGTM integration initialized successfully');
  }

  /**
   * Validate LGTM services are available
   */
  async validateLGTMServices() {
    const services = [
      { name: 'Loki', url: `${this.config.loki.url}/ready`, enabled: this.config.loki.enabled },
      { name: 'Mimir', url: `${this.config.mimir.url}/ready`, enabled: this.config.mimir.enabled },
      { name: 'Tempo', url: `${this.config.tempo.url}/ready`, enabled: this.config.tempo.enabled },
      { name: 'Grafana', url: `${this.config.grafana.url}/api/health`, enabled: this.config.grafana.enabled }
    ];

    const serviceStatuses = await Promise.allSettled(
      services.map(async (service) => {
        if (!service.enabled) {
          return { name: service.name, status: 'disabled' };
        }

        try {
          const response = await axios.get(service.url, { timeout: 5000 });
          return { 
            name: service.name, 
            status: 'available', 
            statusCode: response.status 
          };
        } catch (error) {
          return { 
            name: service.name, 
            status: 'unavailable', 
            error: error.message 
          };
        }
      })
    );

    const results = serviceStatuses.map(result => result.value || result.reason);
    
    this.logger.info('LGTM services validation', {
      services: results,
      availableServices: results.filter(s => s.status === 'available').length,
      totalServices: results.length
    });

    return results;
  }

  /**
   * Start a test run trace in Tempo
   */
  async startTestRunTrace() {
    if (!this.config.tempo.enabled) return;

    this.testRun.traceId = this.generateTraceId();
    this.testRun.spanId = this.generateSpanId();

    const traceData = {
      traceId: this.testRun.traceId,
      spanId: this.testRun.spanId,
      parentSpanId: null,
      operationName: 'e2e-test-run',
      startTime: this.testRun.startTime * 1000, // microseconds
      tags: {
        'test.run.id': this.testRun.id,
        'test.environment': this.testRun.environment,
        'test.browser': this.testRun.browser,
        'test.base.url': this.testRun.baseUrl,
        'service.name': 'pyairtable-e2e-tests'
      }
    };

    try {
      await this.sendTraceSpan(traceData);
      this.logger.info('Test run trace started', {
        traceId: this.testRun.traceId,
        spanId: this.testRun.spanId
      });
    } catch (error) {
      this.logger.warn('Failed to start test run trace', { error: error.message });
    }
  }

  /**
   * Log test event to Loki
   */
  async logTestEvent(level, message, metadata = {}) {
    if (!this.config.loki.enabled) return;

    const logEntry = {
      streams: [{
        stream: {
          job: 'pyairtable-e2e-tests',
          test_run_id: this.testRun.id,
          level: level,
          environment: this.testRun.environment,
          browser: this.testRun.browser
        },
        values: [[
          `${Date.now() * 1000000}`, // nanoseconds
          JSON.stringify({
            timestamp: new Date().toISOString(),
            level,
            message,
            test_run_id: this.testRun.id,
            trace_id: this.testRun.traceId,
            ...metadata
          })
        ]]
      }]
    };

    try {
      await axios.post(`${this.config.loki.url}/loki/api/v1/push`, logEntry, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000
      });
    } catch (error) {
      this.logger.warn('Failed to send log to Loki', { error: error.message });
    }
  }

  /**
   * Send metrics to Mimir
   */
  async sendMetric(metricName, value, labels = {}) {
    if (!this.config.mimir.enabled) return;

    const timestamp = Date.now();
    const metricData = `${metricName}{${this.formatLabels({
      test_run_id: this.testRun.id,
      environment: this.testRun.environment,
      browser: this.testRun.browser,
      ...labels
    })}} ${value} ${timestamp}\n`;

    try {
      await axios.post(`${this.config.mimir.url}/api/v1/push`, metricData, {
        headers: { 
          'Content-Type': 'application/x-protobuf',
          'X-Prometheus-Remote-Write-Version': '0.1.0'
        },
        timeout: 5000
      });
    } catch (error) {
      this.logger.warn('Failed to send metric to Mimir', { 
        metric: metricName, 
        error: error.message 
      });
    }
  }

  /**
   * Send trace span to Tempo
   */
  async sendTraceSpan(spanData) {
    if (!this.config.tempo.enabled) return;

    try {
      await axios.post(`${this.config.tempo.url}/api/traces`, spanData, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000
      });
    } catch (error) {
      this.logger.warn('Failed to send trace span to Tempo', { error: error.message });
    }
  }

  /**
   * Record test suite start
   */
  async recordTestSuiteStart(suiteName, testCount = 0) {
    const metadata = {
      event: 'test_suite_start',
      suite_name: suiteName,
      test_count: testCount,
      timestamp: new Date().toISOString()
    };

    await this.logTestEvent('info', `Test suite started: ${suiteName}`, metadata);
    await this.sendMetric('e2e_test_suite_started_total', 1, { suite_name: suiteName });

    this.logger.info('Test suite started', metadata);
  }

  /**
   * Record test suite completion
   */
  async recordTestSuiteEnd(suiteName, results = {}) {
    const metadata = {
      event: 'test_suite_end',
      suite_name: suiteName,
      results,
      timestamp: new Date().toISOString()
    };

    await this.logTestEvent('info', `Test suite completed: ${suiteName}`, metadata);
    
    // Send individual metrics
    await this.sendMetric('e2e_test_suite_completed_total', 1, { 
      suite_name: suiteName, 
      status: results.failed > 0 ? 'failed' : 'passed' 
    });
    
    if (results.passed) {
      await this.sendMetric('e2e_tests_passed_total', results.passed, { suite_name: suiteName });
    }
    
    if (results.failed) {
      await this.sendMetric('e2e_tests_failed_total', results.failed, { suite_name: suiteName });
    }
    
    if (results.duration) {
      await this.sendMetric('e2e_test_suite_duration_seconds', results.duration, { suite_name: suiteName });
      this.metrics.testDurations.push({ suite: suiteName, duration: results.duration });
    }

    this.logger.info('Test suite completed', metadata);
  }

  /**
   * Record individual test result
   */
  async recordTestResult(testName, result, duration, error = null) {
    const metadata = {
      event: 'test_result',
      test_name: testName,
      result: result, // 'passed', 'failed', 'skipped'
      duration: duration,
      error: error,
      timestamp: new Date().toISOString()
    };

    const level = result === 'failed' ? 'error' : 'info';
    await this.logTestEvent(level, `Test ${result}: ${testName}`, metadata);
    
    // Send metrics
    await this.sendMetric('e2e_test_result_total', 1, { 
      test_name: testName, 
      result: result 
    });
    
    if (duration) {
      await this.sendMetric('e2e_test_duration_seconds', duration, { test_name: testName });
    }

    // Track error counts
    if (result === 'failed') {
      this.metrics.errorCounts[testName] = (this.metrics.errorCounts[testName] || 0) + 1;
    }

    this.logger.info('Test result recorded', metadata);
  }

  /**
   * Record service health check
   */
  async recordServiceHealth(serviceName, isHealthy, responseTime = null) {
    const metadata = {
      event: 'service_health_check',
      service_name: serviceName,
      healthy: isHealthy,
      response_time: responseTime,
      timestamp: new Date().toISOString()
    };

    const level = isHealthy ? 'info' : 'warn';
    await this.logTestEvent(level, `Service health: ${serviceName}`, metadata);
    
    await this.sendMetric('e2e_service_health', isHealthy ? 1 : 0, { service_name: serviceName });
    
    if (responseTime) {
      await this.sendMetric('e2e_service_response_time_seconds', responseTime / 1000, { 
        service_name: serviceName 
      });
      this.metrics.serviceResponseTimes[serviceName] = responseTime;
    }

    this.logger.info('Service health recorded', metadata);
  }

  /**
   * Record performance metrics
   */
  async recordPerformanceMetric(metricName, value, unit, context = {}) {
    const metadata = {
      event: 'performance_metric',
      metric_name: metricName,
      value: value,
      unit: unit,
      context: context,
      timestamp: new Date().toISOString()
    };

    await this.logTestEvent('info', `Performance metric: ${metricName}`, metadata);
    await this.sendMetric(`e2e_performance_${metricName}`, value, context);

    this.logger.info('Performance metric recorded', metadata);
  }

  /**
   * Create Grafana dashboard annotations
   */
  async createGrafanaAnnotation(text, tags = []) {
    if (!this.config.grafana.enabled) return;

    const annotation = {
      time: Date.now(),
      text: text,
      tags: ['e2e-tests', this.testRun.id, ...tags]
    };

    try {
      await axios.post(`${this.config.grafana.url}/api/annotations`, annotation, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000
      });
      
      this.logger.info('Grafana annotation created', { text, tags });
    } catch (error) {
      this.logger.warn('Failed to create Grafana annotation', { error: error.message });
    }
  }

  /**
   * Finalize test run
   */
  async finalize(summary = {}) {
    const endTime = Date.now();
    const totalDuration = endTime - this.testRun.startTime;

    const finalSummary = {
      test_run_id: this.testRun.id,
      start_time: this.testRun.startTime,
      end_time: endTime,
      duration: totalDuration,
      environment: this.testRun.environment,
      browser: this.testRun.browser,
      base_url: this.testRun.baseUrl,
      ...summary,
      metrics: this.metrics
    };

    await this.logTestEvent('info', 'Test run completed', {
      event: 'test_run_complete',
      ...finalSummary
    });

    // Send final metrics
    await this.sendMetric('e2e_test_run_duration_seconds', totalDuration / 1000);
    
    if (summary.success_rate) {
      await this.sendMetric('e2e_test_run_success_rate', summary.success_rate);
    }

    // Close test run trace
    if (this.testRun.traceId) {
      await this.sendTraceSpan({
        traceId: this.testRun.traceId,
        spanId: this.testRun.spanId,
        operationName: 'e2e-test-run',
        startTime: this.testRun.startTime * 1000,
        finishTime: endTime * 1000,
        duration: totalDuration * 1000,
        tags: {
          'test.run.id': this.testRun.id,
          'test.status': summary.success_rate >= 90 ? 'success' : 'failed',
          'test.total': summary.total_tests || 0,
          'test.passed': summary.passed_tests || 0,
          'test.failed': summary.failed_tests || 0
        }
      });
    }

    // Create Grafana annotation for test completion
    await this.createGrafanaAnnotation(
      `E2E Test Run Completed: ${summary.passed_tests}/${summary.total_tests} passed (${summary.success_rate}%)`,
      ['test-complete', summary.success_rate >= 90 ? 'success' : 'failed']
    );

    this.logger.info('Test run finalized', finalSummary);
    return finalSummary;
  }

  /**
   * Generate random trace ID
   */
  generateTraceId() {
    return Array.from({ length: 16 }, () => 
      Math.floor(Math.random() * 16).toString(16)
    ).join('');
  }

  /**
   * Generate random span ID
   */
  generateSpanId() {
    return Array.from({ length: 8 }, () => 
      Math.floor(Math.random() * 16).toString(16)
    ).join('');
  }

  /**
   * Format labels for Prometheus metrics
   */
  formatLabels(labels) {
    return Object.entries(labels)
      .map(([key, value]) => `${key}="${value}"`)
      .join(',');
  }

  /**
   * Get test run summary
   */
  getTestRunSummary() {
    return {
      id: this.testRun.id,
      startTime: this.testRun.startTime,
      currentDuration: Date.now() - this.testRun.startTime,
      environment: this.testRun.environment,
      browser: this.testRun.browser,
      metrics: this.metrics
    };
  }
}

module.exports = LGTMIntegration;