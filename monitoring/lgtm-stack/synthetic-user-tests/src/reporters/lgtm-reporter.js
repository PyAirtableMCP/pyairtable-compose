const fs = require('fs').promises;
const path = require('path');
const axios = require('axios');

/**
 * Custom Playwright reporter for LGTM stack integration
 * Sends test results to Loki, metrics to Mimir, and traces to Tempo
 */
class LGTMReporter {
  constructor(options = {}) {
    this.config = {
      lokiUrl: options.lokiUrl || process.env.LOKI_URL || 'http://localhost:3100',
      mimirUrl: options.mimirUrl || process.env.MIMIR_URL || 'http://localhost:9009',
      tempoUrl: options.tempoUrl || process.env.TEMPO_URL || 'http://localhost:3200',
      serviceName: options.serviceName || 'pyairtable-synthetic-tests',
      environment: options.environment || process.env.NODE_ENV || 'test',
      outputDir: options.outputDir || 'test-results',
      ...options
    };
    
    this.testResults = [];
    this.metrics = new Map();
    this.traces = [];
    this.startTime = Date.now();
  }

  /**
   * Called when test run begins
   */
  onBegin(config, suite) {
    console.log(`Starting test run with ${suite.allTests().length} tests`);
    
    this.sendToLoki({
      level: 'info',
      message: 'Test run started',
      testCount: suite.allTests().length,
      environment: this.config.environment,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Called when test begins
   */
  onTestBegin(test, result) {
    const testInfo = {
      testId: test.id,
      title: test.title,
      file: test.location.file,
      line: test.location.line,
      project: test.parent.project().name,
      startTime: Date.now()
    };
    
    this.testResults.push(testInfo);
    
    // Start tracing
    this.startTrace(testInfo);
  }

  /**
   * Called when test ends
   */
  onTestEnd(test, result) {
    const testIndex = this.testResults.findIndex(t => t.testId === test.id);
    if (testIndex === -1) return;
    
    const testInfo = this.testResults[testIndex];
    testInfo.endTime = Date.now();
    testInfo.duration = testInfo.endTime - testInfo.startTime;
    testInfo.status = result.status;
    testInfo.error = result.error?.message;
    testInfo.retry = result.retry;
    testInfo.workerIndex = result.workerIndex;
    
    // Record metrics
    this.recordTestMetrics(testInfo, result);
    
    // End tracing
    this.endTrace(testInfo, result);
    
    // Send to Loki
    this.sendTestLogToLoki(testInfo, result);
  }

  /**
   * Called when test run ends
   */
  async onEnd(result) {
    const endTime = Date.now();
    const totalDuration = endTime - this.startTime;
    
    const summary = {
      status: result.status,
      startTime: this.startTime,
      endTime,
      duration: totalDuration,
      totalTests: this.testResults.length,
      passed: this.testResults.filter(t => t.status === 'passed').length,
      failed: this.testResults.filter(t => t.status === 'failed').length,
      skipped: this.testResults.filter(t => t.status === 'skipped').length,
      flaky: this.testResults.filter(t => t.status === 'flaky').length
    };
    
    console.log(`Test run completed: ${summary.passed}/${summary.totalTests} passed`);
    
    // Send final summary
    await this.sendSummaryToLoki(summary);
    await this.exportMetrics(summary);
    await this.exportResults(summary);
  }

  /**
   * Record test metrics
   */
  recordTestMetrics(testInfo, result) {
    const metricKey = `${testInfo.project}_${this.extractTestType(testInfo.title)}`;
    
    if (!this.metrics.has(metricKey)) {
      this.metrics.set(metricKey, {
        project: testInfo.project,
        testType: this.extractTestType(testInfo.title),
        totalTests: 0,
        passedTests: 0,
        failedTests: 0,
        totalDuration: 0,
        durations: []
      });
    }
    
    const metric = this.metrics.get(metricKey);
    metric.totalTests++;
    metric.totalDuration += testInfo.duration;
    metric.durations.push(testInfo.duration);
    
    if (testInfo.status === 'passed') {
      metric.passedTests++;
    } else if (testInfo.status === 'failed') {
      metric.failedTests++;
    }
  }

  /**
   * Extract test type from title
   */
  extractTestType(title) {
    const lowerTitle = title.toLowerCase();
    
    if (lowerTitle.includes('new user') || lowerTitle.includes('onboarding')) {
      return 'new-user';
    } else if (lowerTitle.includes('power user') || lowerTitle.includes('advanced')) {
      return 'power-user';
    } else if (lowerTitle.includes('error') || lowerTitle.includes('handling')) {
      return 'error-handling';
    } else if (lowerTitle.includes('mobile') || lowerTitle.includes('responsive')) {
      return 'mobile';
    } else if (lowerTitle.includes('accessibility')) {
      return 'accessibility';
    } else if (lowerTitle.includes('performance')) {
      return 'performance';
    }
    
    return 'general';
  }

  /**
   * Start distributed trace
   */
  startTrace(testInfo) {
    const traceId = this.generateTraceId();
    const spanId = this.generateSpanId();
    
    const trace = {
      traceId,
      spanId,
      operationName: testInfo.title,
      startTime: testInfo.startTime * 1000, // microseconds
      tags: {
        'test.id': testInfo.testId,
        'test.file': testInfo.file,
        'test.project': testInfo.project,
        'service.name': this.config.serviceName,
        'environment': this.config.environment
      },
      logs: []
    };
    
    testInfo.trace = trace;
    this.traces.push(trace);
  }

  /**
   * End distributed trace
   */
  endTrace(testInfo, result) {
    if (!testInfo.trace) return;
    
    testInfo.trace.duration = testInfo.duration * 1000; // microseconds
    testInfo.trace.tags['test.status'] = testInfo.status;
    testInfo.trace.tags['test.duration'] = testInfo.duration;
    
    if (testInfo.error) {
      testInfo.trace.tags['error'] = true;
      testInfo.trace.tags['error.message'] = testInfo.error;
    }
    
    // Add logs for key events
    if (result.steps) {
      result.steps.forEach(step => {
        testInfo.trace.logs.push({
          timestamp: step.startTime * 1000,
          fields: {
            event: 'test.step',
            'step.title': step.title,
            'step.duration': step.duration
          }
        });
      });
    }
  }

  /**
   * Send log to Loki
   */
  async sendToLoki(logEntry) {
    try {
      const lokiPayload = {
        streams: [{
          stream: {
            job: 'synthetic-tests',
            service: this.config.serviceName,
            environment: this.config.environment,
            level: logEntry.level || 'info'
          },
          values: [[
            String(Date.now() * 1000000), // nanosecond timestamp
            JSON.stringify(logEntry)
          ]]
        }]
      };
      
      await axios.post(`${this.config.lokiUrl}/loki/api/v1/push`, lokiPayload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000
      });
    } catch (error) {
      console.warn('Failed to send log to Loki:', error.message);
    }
  }

  /**
   * Send test log to Loki
   */
  async sendTestLogToLoki(testInfo, result) {
    const logEntry = {
      level: testInfo.status === 'failed' ? 'error' : 'info',
      message: 'Test completed',
      testId: testInfo.testId,
      testTitle: testInfo.title,
      testFile: testInfo.file,
      project: testInfo.project,
      status: testInfo.status,
      duration: testInfo.duration,
      retry: testInfo.retry,
      error: testInfo.error,
      timestamp: new Date(testInfo.endTime).toISOString()
    };
    
    await this.sendToLoki(logEntry);
  }

  /**
   * Send summary to Loki
   */
  async sendSummaryToLoki(summary) {
    const logEntry = {
      level: 'info',
      message: 'Test run completed',
      status: summary.status,
      duration: summary.duration,
      totalTests: summary.totalTests,
      passed: summary.passed,
      failed: summary.failed,
      skipped: summary.skipped,
      flaky: summary.flaky,
      successRate: summary.totalTests > 0 ? (summary.passed / summary.totalTests) * 100 : 0,
      timestamp: new Date(summary.endTime).toISOString()
    };
    
    await this.sendToLoki(logEntry);
  }

  /**
   * Export metrics to Prometheus format for Mimir
   */
  async exportMetrics(summary) {
    const metricsContent = this.generatePrometheusMetrics(summary);
    
    try {
      const metricsFile = path.join(this.config.outputDir, 'prometheus-metrics.txt');
      await fs.writeFile(metricsFile, metricsContent);
      
      // Also try to push to Pushgateway if available
      await this.pushMetricsToGateway(metricsContent);
    } catch (error) {
      console.warn('Failed to export metrics:', error.message);
    }
  }

  /**
   * Generate Prometheus metrics format
   */
  generatePrometheusMetrics(summary) {
    const timestamp = Date.now();
    let content = '';
    
    // Overall test metrics
    content += `# HELP synthetic_tests_total Total number of synthetic tests executed\n`;
    content += `# TYPE synthetic_tests_total counter\n`;
    content += `synthetic_tests_total{environment="${this.config.environment}",status="passed"} ${summary.passed} ${timestamp}\n`;
    content += `synthetic_tests_total{environment="${this.config.environment}",status="failed"} ${summary.failed} ${timestamp}\n`;
    content += `synthetic_tests_total{environment="${this.config.environment}",status="skipped"} ${summary.skipped} ${timestamp}\n`;
    
    content += `# HELP synthetic_test_duration_seconds Duration of test execution in seconds\n`;
    content += `# TYPE synthetic_test_duration_seconds histogram\n`;
    
    // Per-project metrics
    for (const [metricKey, metric] of this.metrics) {
      const labels = `environment="${this.config.environment}",project="${metric.project}",test_type="${metric.testType}"`;
      
      content += `synthetic_tests_total{${labels},status="passed"} ${metric.passedTests} ${timestamp}\n`;
      content += `synthetic_tests_total{${labels},status="failed"} ${metric.failedTests} ${timestamp}\n`;
      
      // Duration histogram buckets
      const buckets = [100, 500, 1000, 5000, 10000, 30000, 60000, 120000, 300000];
      let cumulativeCount = 0;
      
      for (const bucket of buckets) {
        const count = metric.durations.filter(d => d <= bucket).length;
        cumulativeCount = count;
        content += `synthetic_test_duration_seconds_bucket{${labels},le="${bucket / 1000}"} ${count} ${timestamp}\n`;
      }
      
      content += `synthetic_test_duration_seconds_bucket{${labels},le="+Inf"} ${metric.totalTests} ${timestamp}\n`;
      content += `synthetic_test_duration_seconds_count{${labels}} ${metric.totalTests} ${timestamp}\n`;
      content += `synthetic_test_duration_seconds_sum{${labels}} ${metric.totalDuration / 1000} ${timestamp}\n`;
    }
    
    // Success rate gauge
    content += `# HELP synthetic_success_rate Success rate of synthetic tests\n`;
    content += `# TYPE synthetic_success_rate gauge\n`;
    const successRate = summary.totalTests > 0 ? (summary.passed / summary.totalTests) : 0;
    content += `synthetic_success_rate{environment="${this.config.environment}"} ${successRate} ${timestamp}\n`;
    
    return content;
  }

  /**
   * Push metrics to Pushgateway
   */
  async pushMetricsToGateway(metricsContent) {
    try {
      const pushgatewayUrl = process.env.PUSHGATEWAY_URL || 'http://localhost:9091';
      const jobName = 'synthetic-tests';
      
      await axios.post(
        `${pushgatewayUrl}/metrics/job/${jobName}/instance/${this.config.serviceName}`,
        metricsContent,
        {
          headers: { 'Content-Type': 'text/plain' },
          timeout: 10000
        }
      );
      
      console.log('Metrics pushed to Pushgateway');
    } catch (error) {
      console.warn('Failed to push metrics to Pushgateway:', error.message);
    }
  }

  /**
   * Export traces to Tempo
   */
  async exportTraces() {
    if (this.traces.length === 0) return;
    
    try {
      const jaegerPayload = {
        data: [{
          traceID: this.generateTraceId(),
          spans: this.traces.map(trace => ({
            traceID: trace.traceId,
            spanID: trace.spanId,
            operationName: trace.operationName,
            startTime: trace.startTime,
            duration: trace.duration,
            tags: Object.entries(trace.tags).map(([key, value]) => ({
              key,
              type: typeof value === 'string' ? 'string' : 'number',
              value: value.toString()
            })),
            logs: trace.logs,
            process: {
              serviceName: this.config.serviceName,
              tags: [
                { key: 'environment', value: this.config.environment, type: 'string' }
              ]
            }
          }))
        }]
      };
      
      await axios.post(`${this.config.tempoUrl}/api/traces`, jaegerPayload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 10000
      });
      
      console.log('Traces exported to Tempo');
    } catch (error) {
      console.warn('Failed to export traces to Tempo:', error.message);
    }
  }

  /**
   * Export comprehensive results
   */
  async exportResults(summary) {
    const results = {
      summary,
      testResults: this.testResults,
      metrics: Object.fromEntries(this.metrics),
      traces: this.traces.length,
      config: this.config,
      exportTime: new Date().toISOString()
    };
    
    try {
      await fs.mkdir(this.config.outputDir, { recursive: true });
      
      const resultsFile = path.join(
        this.config.outputDir,
        `lgtm-results-${Date.now()}.json`
      );
      
      await fs.writeFile(resultsFile, JSON.stringify(results, null, 2));
      
      // Export traces
      await this.exportTraces();
      
      console.log(`Results exported to ${resultsFile}`);
    } catch (error) {
      console.error('Failed to export results:', error.message);
    }
  }

  /**
   * Generate trace ID
   */
  generateTraceId() {
    return Math.random().toString(16).substr(2, 16);
  }

  /**
   * Generate span ID
   */
  generateSpanId() {
    return Math.random().toString(16).substr(2, 8);
  }

  /**
   * Print results summary
   */
  printsummary() {
    // This method is called by Playwright to print the summary
    const passed = this.testResults.filter(t => t.status === 'passed').length;
    const failed = this.testResults.filter(t => t.status === 'failed').length;
    const total = this.testResults.length;
    
    console.log(`\n📊 LGTM Reporter Summary:`);
    console.log(`   Tests: ${passed}/${total} passed`);
    console.log(`   Logs sent to Loki: ${this.config.lokiUrl}`);
    console.log(`   Metrics exported for Mimir`);
    console.log(`   Traces exported to Tempo: ${this.config.tempoUrl}`);
    
    if (failed > 0) {
      console.log(`\n❌ Failed tests:`);
      this.testResults
        .filter(t => t.status === 'failed')
        .forEach(t => console.log(`   - ${t.title} (${t.duration}ms)`));
    }
  }
}

module.exports = LGTMReporter;