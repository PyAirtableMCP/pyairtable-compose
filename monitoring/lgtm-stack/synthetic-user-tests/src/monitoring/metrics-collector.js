const winston = require('winston');
const client = require('prom-client');
const axios = require('axios');
const fs = require('fs').promises;
const path = require('path');

/**
 * Metrics Collector for synthetic user tests
 * Integrates with LGTM stack (Loki, Grafana, Tempo, Mimir)
 */
class MetricsCollector {
  constructor(options = {}) {
    this.config = {
      lokiUrl: options.lokiUrl || 'http://localhost:3100',
      mimirUrl: options.mimirUrl || 'http://localhost:9009',
      tempoUrl: options.tempoUrl || 'http://localhost:3200',
      pushgatewayUrl: options.pushgatewayUrl || 'http://localhost:9091',
      serviceName: options.serviceName || 'pyairtable-synthetic-tests',
      environment: options.environment || 'test',
      ...options
    };
    
    // Initialize Prometheus metrics
    this.setupPrometheusMetrics();
    
    // Initialize logger with Loki transport
    this.setupLogger();
    
    // Test execution metrics
    this.testMetrics = {
      totalTests: 0,
      passedTests: 0,
      failedTests: 0,
      testDuration: new Map(),
      userAgentMetrics: new Map(),
      errorCounts: new Map(),
      performanceMetrics: new Map()
    };
  }

  /**
   * Setup Prometheus metrics
   */
  setupPrometheusMetrics() {
    // Clear default metrics
    client.register.clear();
    
    // Test execution metrics
    this.testCounter = new client.Counter({
      name: 'synthetic_tests_total',
      help: 'Total number of synthetic tests executed',
      labelNames: ['test_type', 'user_agent', 'status', 'environment']
    });
    
    this.testDurationHistogram = new client.Histogram({
      name: 'synthetic_test_duration_seconds',
      help: 'Duration of synthetic tests in seconds',
      labelNames: ['test_type', 'user_agent', 'environment'],
      buckets: [0.1, 0.5, 1, 5, 10, 30, 60, 120, 300]
    });
    
    // User agent behavior metrics
    this.userAgentActionsCounter = new client.Counter({
      name: 'user_agent_actions_total',
      help: 'Total number of actions performed by user agents',
      labelNames: ['agent_type', 'action_type', 'page', 'environment']
    });
    
    this.userAgentErrorsCounter = new client.Counter({
      name: 'user_agent_errors_total',
      help: 'Total number of errors encountered by user agents',
      labelNames: ['agent_type', 'error_type', 'page', 'environment']
    });
    
    // Performance metrics
    this.pageLoadTimeHistogram = new client.Histogram({
      name: 'synthetic_page_load_duration_seconds',
      help: 'Page load times measured by synthetic tests',
      labelNames: ['page', 'user_agent', 'environment'],
      buckets: [0.5, 1, 2, 5, 10, 15, 30]
    });
    
    this.interactionTimeHistogram = new client.Histogram({
      name: 'synthetic_interaction_duration_seconds',
      help: 'Interaction response times measured by synthetic tests',
      labelNames: ['interaction_type', 'page', 'user_agent', 'environment'],
      buckets: [0.1, 0.5, 1, 2, 5, 10]
    });
    
    // Availability metrics
    this.availabilityGauge = new client.Gauge({
      name: 'synthetic_availability_ratio',
      help: 'Availability ratio measured by synthetic tests',
      labelNames: ['service', 'endpoint', 'environment']
    });
    
    // Feature discovery metrics
    this.featureDiscoveryGauge = new client.Gauge({
      name: 'synthetic_feature_discovery_count',
      help: 'Number of features discovered by synthetic users',
      labelNames: ['agent_type', 'feature_category', 'environment']
    });
    
    // Error rate metrics
    this.errorRateGauge = new client.Gauge({
      name: 'synthetic_error_rate',
      help: 'Error rate observed by synthetic tests',
      labelNames: ['error_category', 'page', 'environment']
    });
    
    // Register all metrics
    client.register.registerMetric(this.testCounter);
    client.register.registerMetric(this.testDurationHistogram);
    client.register.registerMetric(this.userAgentActionsCounter);
    client.register.registerMetric(this.userAgentErrorsCounter);
    client.register.registerMetric(this.pageLoadTimeHistogram);
    client.register.registerMetric(this.interactionTimeHistogram);
    client.register.registerMetric(this.availabilityGauge);
    client.register.registerMetric(this.featureDiscoveryGauge);
    client.register.registerMetric(this.errorRateGauge);
  }

  /**
   * Setup logger with Loki integration
   */
  setupLogger() {
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
      ),
      defaultMeta: {
        service: this.config.serviceName,
        environment: this.config.environment
      },
      transports: [
        new winston.transports.Console({
          format: winston.format.simple()
        }),
        new winston.transports.File({
          filename: 'logs/synthetic-tests.log',
          format: winston.format.json()
        })
      ]
    });
  }

  /**
   * Record test start
   */
  recordTestStart(testInfo) {
    const testId = testInfo.testId || `${testInfo.testType}-${Date.now()}`;
    
    this.testMetrics.totalTests++;
    this.testMetrics.testDuration.set(testId, Date.now());
    
    this.logger.info('Test started', {
      testId,
      testType: testInfo.testType,
      userAgent: testInfo.userAgent,
      page: testInfo.page,
      timestamp: new Date().toISOString()
    });
    
    return testId;
  }

  /**
   * Record test completion
   */
  recordTestCompletion(testId, result) {
    const startTime = this.testMetrics.testDuration.get(testId);
    const duration = startTime ? (Date.now() - startTime) / 1000 : 0;
    
    this.testMetrics.testDuration.delete(testId);
    
    if (result.status === 'passed') {
      this.testMetrics.passedTests++;
    } else {
      this.testMetrics.failedTests++;
    }
    
    // Update Prometheus metrics
    this.testCounter.inc({
      test_type: result.testType || 'unknown',
      user_agent: result.userAgent || 'unknown',
      status: result.status,
      environment: this.config.environment
    });
    
    this.testDurationHistogram.observe({
      test_type: result.testType || 'unknown',
      user_agent: result.userAgent || 'unknown',
      environment: this.config.environment
    }, duration);
    
    this.logger.info('Test completed', {
      testId,
      status: result.status,
      duration,
      errors: result.errors || [],
      metrics: result.metrics || {},
      timestamp: new Date().toISOString()
    });
    
    // Send to Loki
    this.sendToLoki({
      level: 'info',
      message: 'Test completed',
      testId,
      status: result.status,
      duration,
      testType: result.testType,
      userAgent: result.userAgent,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Record user agent action
   */
  recordUserAgentAction(agentInfo, action) {
    const agentId = agentInfo.agentId;
    
    if (!this.testMetrics.userAgentMetrics.has(agentId)) {
      this.testMetrics.userAgentMetrics.set(agentId, {
        actions: 0,
        errors: 0,
        startTime: Date.now()
      });
    }
    
    const agentMetrics = this.testMetrics.userAgentMetrics.get(agentId);
    agentMetrics.actions++;
    
    // Update Prometheus metrics
    this.userAgentActionsCounter.inc({
      agent_type: agentInfo.agentType || 'unknown',
      action_type: action.type || 'unknown',
      page: action.page || 'unknown',
      environment: this.config.environment
    });
    
    this.logger.debug('User agent action', {
      agentId,
      agentType: agentInfo.agentType,
      action: action.type,
      page: action.page,
      details: action.details,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Record user agent error
   */
  recordUserAgentError(agentInfo, error) {
    const agentId = agentInfo.agentId;
    
    if (!this.testMetrics.userAgentMetrics.has(agentId)) {
      this.testMetrics.userAgentMetrics.set(agentId, {
        actions: 0,
        errors: 0,
        startTime: Date.now()
      });
    }
    
    const agentMetrics = this.testMetrics.userAgentMetrics.get(agentId);
    agentMetrics.errors++;
    
    // Update error counts
    const errorKey = `${error.type || 'unknown'}-${error.page || 'unknown'}`;
    const currentCount = this.testMetrics.errorCounts.get(errorKey) || 0;
    this.testMetrics.errorCounts.set(errorKey, currentCount + 1);
    
    // Update Prometheus metrics
    this.userAgentErrorsCounter.inc({
      agent_type: agentInfo.agentType || 'unknown',
      error_type: error.type || 'unknown',
      page: error.page || 'unknown',
      environment: this.config.environment
    });
    
    this.logger.error('User agent error', {
      agentId,
      agentType: agentInfo.agentType,
      errorType: error.type,
      page: error.page,
      message: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });
    
    // Send error to Loki
    this.sendToLoki({
      level: 'error',
      message: 'User agent error',
      agentId,
      agentType: agentInfo.agentType,
      errorType: error.type,
      errorMessage: error.message,
      page: error.page,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Record performance metrics
   */
  recordPerformanceMetric(metric) {
    const metricKey = `${metric.type}-${metric.page || 'unknown'}`;
    
    if (!this.testMetrics.performanceMetrics.has(metricKey)) {
      this.testMetrics.performanceMetrics.set(metricKey, []);
    }
    
    this.testMetrics.performanceMetrics.get(metricKey).push({
      value: metric.value,
      timestamp: Date.now(),
      userAgent: metric.userAgent
    });
    
    // Update Prometheus metrics
    if (metric.type === 'page_load_time') {
      this.pageLoadTimeHistogram.observe({
        page: metric.page || 'unknown',
        user_agent: metric.userAgent || 'unknown',
        environment: this.config.environment
      }, metric.value / 1000); // Convert to seconds
    } else if (metric.type === 'interaction_time') {
      this.interactionTimeHistogram.observe({
        interaction_type: metric.interactionType || 'unknown',
        page: metric.page || 'unknown',
        user_agent: metric.userAgent || 'unknown',
        environment: this.config.environment
      }, metric.value / 1000); // Convert to seconds
    }
    
    this.logger.info('Performance metric recorded', {
      type: metric.type,
      value: metric.value,
      page: metric.page,
      userAgent: metric.userAgent,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Record feature discovery
   */
  recordFeatureDiscovery(agentInfo, features) {
    for (const feature of features) {
      this.featureDiscoveryGauge.inc({
        agent_type: agentInfo.agentType || 'unknown',
        feature_category: feature.category || 'unknown',
        environment: this.config.environment
      });
    }
    
    this.logger.info('Features discovered', {
      agentId: agentInfo.agentId,
      agentType: agentInfo.agentType,
      features: features.map(f => f.name),
      count: features.length,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Record availability metric
   */
  recordAvailability(service, endpoint, isAvailable) {
    this.availabilityGauge.set({
      service,
      endpoint,
      environment: this.config.environment
    }, isAvailable ? 1 : 0);
    
    this.logger.info('Availability recorded', {
      service,
      endpoint,
      available: isAvailable,
      timestamp: new Date().toISOString()
    });
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
            String(Date.now() * 1000000), // Nanosecond timestamp
            JSON.stringify(logEntry)
          ]]
        }]
      };
      
      await axios.post(`${this.config.lokiUrl}/loki/api/v1/push`, lokiPayload, {
        headers: {
          'Content-Type': 'application/json'
        },
        timeout: 5000
      });
    } catch (error) {
      // Don't let Loki errors break the tests
      console.warn('Failed to send log to Loki:', error.message);
    }
  }

  /**
   * Push metrics to Pushgateway
   */
  async pushMetrics() {
    try {
      const gateway = new client.Pushgateway(this.config.pushgatewayUrl);
      await gateway.pushAdd({ jobName: 'synthetic-tests' });
      
      this.logger.info('Metrics pushed to Pushgateway');
    } catch (error) {
      this.logger.warn('Failed to push metrics to Pushgateway', { error: error.message });
    }
  }

  /**
   * Get current metrics summary
   */
  getMetricsSummary() {
    const summary = {
      tests: {
        total: this.testMetrics.totalTests,
        passed: this.testMetrics.passedTests,
        failed: this.testMetrics.failedTests,
        successRate: this.testMetrics.totalTests > 0 
          ? (this.testMetrics.passedTests / this.testMetrics.totalTests) * 100 
          : 0
      },
      userAgents: {},
      errors: {},
      performance: {},
      timestamp: new Date().toISOString()
    };
    
    // User agent metrics
    for (const [agentId, metrics] of this.testMetrics.userAgentMetrics) {
      const duration = (Date.now() - metrics.startTime) / 1000;
      summary.userAgents[agentId] = {
        actions: metrics.actions,
        errors: metrics.errors,
        actionsPerSecond: duration > 0 ? metrics.actions / duration : 0,
        errorRate: metrics.actions > 0 ? (metrics.errors / metrics.actions) * 100 : 0
      };
    }
    
    // Error summary
    for (const [errorKey, count] of this.testMetrics.errorCounts) {
      summary.errors[errorKey] = count;
    }
    
    // Performance summary
    for (const [metricKey, values] of this.testMetrics.performanceMetrics) {
      if (values.length > 0) {
        const nums = values.map(v => v.value);
        summary.performance[metricKey] = {
          count: values.length,
          min: Math.min(...nums),
          max: Math.max(...nums),
          avg: nums.reduce((a, b) => a + b, 0) / nums.length,
          p95: this.calculatePercentile(nums, 95),
          p99: this.calculatePercentile(nums, 99)
        };
      }
    }
    
    return summary;
  }

  /**
   * Calculate percentile
   */
  calculatePercentile(values, percentile) {
    const sorted = values.sort((a, b) => a - b);
    const index = Math.ceil((percentile / 100) * sorted.length) - 1;
    return sorted[index];
  }

  /**
   * Export metrics for Grafana dashboard
   */
  async exportMetricsForGrafana(outputPath) {
    const summary = this.getMetricsSummary();
    const grafanaData = {
      dashboard: {
        title: 'PyAirtable Synthetic User Tests',
        panels: [],
        time: {
          from: 'now-1h',
          to: 'now'
        },
        refresh: '30s'
      },
      metrics: summary,
      exportTime: new Date().toISOString()
    };
    
    try {
      await fs.writeFile(
        path.join(outputPath, 'grafana-metrics.json'),
        JSON.stringify(grafanaData, null, 2)
      );
      
      this.logger.info('Metrics exported for Grafana', { outputPath });
    } catch (error) {
      this.logger.error('Failed to export metrics for Grafana', { error: error.message });
    }
  }

  /**
   * Generate test report
   */
  async generateTestReport(outputPath) {
    const summary = this.getMetricsSummary();
    const report = {
      title: 'PyAirtable Synthetic User Test Report',
      generatedAt: new Date().toISOString(),
      environment: this.config.environment,
      summary,
      recommendations: this.generateRecommendations(summary),
      charts: await this.generateChartData(summary)
    };
    
    try {
      await fs.writeFile(
        path.join(outputPath, 'test-report.json'),
        JSON.stringify(report, null, 2)
      );
      
      // Generate HTML report
      const htmlReport = this.generateHTMLReport(report);
      await fs.writeFile(
        path.join(outputPath, 'test-report.html'),
        htmlReport
      );
      
      this.logger.info('Test report generated', { outputPath });
      return report;
    } catch (error) {
      this.logger.error('Failed to generate test report', { error: error.message });
      throw error;
    }
  }

  /**
   * Generate recommendations based on metrics
   */
  generateRecommendations(summary) {
    const recommendations = [];
    
    // Success rate recommendations
    if (summary.tests.successRate < 95) {
      recommendations.push({
        category: 'reliability',
        priority: 'high',
        message: `Test success rate is ${summary.tests.successRate.toFixed(1)}%. Investigate failing tests and improve error handling.`
      });
    }
    
    // Performance recommendations
    for (const [metricKey, perf] of Object.entries(summary.performance)) {
      if (metricKey.includes('page_load_time') && perf.avg > 5000) {
        recommendations.push({
          category: 'performance',
          priority: 'medium',
          message: `Average page load time for ${metricKey} is ${(perf.avg / 1000).toFixed(2)}s. Consider optimization.`
        });
      }
      
      if (metricKey.includes('interaction_time') && perf.avg > 2000) {
        recommendations.push({
          category: 'performance',
          priority: 'medium',
          message: `Average interaction time for ${metricKey} is ${(perf.avg / 1000).toFixed(2)}s. Consider UX improvements.`
        });
      }
    }
    
    // Error rate recommendations
    for (const [agentId, metrics] of Object.entries(summary.userAgents)) {
      if (metrics.errorRate > 10) {
        recommendations.push({
          category: 'user_experience',
          priority: 'high',
          message: `User agent ${agentId} encountered ${metrics.errorRate.toFixed(1)}% error rate. Review error scenarios.`
        });
      }
    }
    
    return recommendations;
  }

  /**
   * Generate chart data for visualization
   */
  async generateChartData(summary) {
    return {
      testResults: {
        labels: ['Passed', 'Failed'],
        data: [summary.tests.passed, summary.tests.failed]
      },
      performanceTrends: {
        // This would be populated with time series data
        timestamps: [],
        pageLoadTimes: [],
        interactionTimes: []
      },
      errorDistribution: {
        labels: Object.keys(summary.errors),
        data: Object.values(summary.errors)
      }
    };
  }

  /**
   * Generate HTML report
   */
  generateHTMLReport(report) {
    return `
<!DOCTYPE html>
<html>
<head>
    <title>${report.title}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .metric { display: inline-block; margin: 10px; padding: 15px; background: #e7f3ff; border-radius: 5px; }
        .recommendation { margin: 10px 0; padding: 10px; border-left: 4px solid #ffa500; background: #fff8e1; }
        .high-priority { border-left-color: #f44336; }
        .medium-priority { border-left-color: #ff9800; }
        .low-priority { border-left-color: #4caf50; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>${report.title}</h1>
        <p>Generated: ${report.generatedAt}</p>
        <p>Environment: ${report.environment}</p>
    </div>
    
    <h2>Test Summary</h2>
    <div class="metric">
        <h3>Total Tests</h3>
        <p>${report.summary.tests.total}</p>
    </div>
    <div class="metric">
        <h3>Success Rate</h3>
        <p>${report.summary.tests.successRate.toFixed(1)}%</p>
    </div>
    <div class="metric">
        <h3>Failed Tests</h3>
        <p>${report.summary.tests.failed}</p>
    </div>
    
    <h2>Performance Metrics</h2>
    <table>
        <tr><th>Metric</th><th>Count</th><th>Avg</th><th>Min</th><th>Max</th><th>P95</th><th>P99</th></tr>
        ${Object.entries(report.summary.performance).map(([key, perf]) => `
        <tr>
            <td>${key}</td>
            <td>${perf.count}</td>
            <td>${(perf.avg / 1000).toFixed(2)}s</td>
            <td>${(perf.min / 1000).toFixed(2)}s</td>
            <td>${(perf.max / 1000).toFixed(2)}s</td>
            <td>${(perf.p95 / 1000).toFixed(2)}s</td>
            <td>${(perf.p99 / 1000).toFixed(2)}s</td>
        </tr>
        `).join('')}
    </table>
    
    <h2>Recommendations</h2>
    ${report.recommendations.map(rec => `
    <div class="recommendation ${rec.priority}-priority">
        <strong>${rec.category.toUpperCase()}</strong> (${rec.priority}): ${rec.message}
    </div>
    `).join('')}
    
    <h2>User Agent Metrics</h2>
    <table>
        <tr><th>Agent</th><th>Actions</th><th>Errors</th><th>Error Rate</th><th>Actions/sec</th></tr>
        ${Object.entries(report.summary.userAgents).map(([agent, metrics]) => `
        <tr>
            <td>${agent}</td>
            <td>${metrics.actions}</td>
            <td>${metrics.errors}</td>
            <td>${metrics.errorRate.toFixed(1)}%</td>
            <td>${metrics.actionsPerSecond.toFixed(2)}</td>
        </tr>
        `).join('')}
    </table>
</body>
</html>
    `;
  }

  /**
   * Cleanup resources
   */
  async cleanup() {
    try {
      await this.pushMetrics();
      this.logger.info('Metrics collector cleanup completed');
    } catch (error) {
      this.logger.error('Error during cleanup', { error: error.message });
    }
  }
}

module.exports = MetricsCollector;