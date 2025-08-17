const { v4: uuidv4 } = require('uuid');
const axios = require('axios');
const testConfig = require('../config/test-config.json');

class TraceHelper {
  constructor() {
    this.config = testConfig.observability;
    this.currentTraceId = null;
  }

  /**
   * Generate a new trace ID for request correlation
   */
  generateTraceId() {
    this.currentTraceId = uuidv4();
    return this.currentTraceId;
  }

  /**
   * Get the current trace ID
   */
  getCurrentTraceId() {
    return this.currentTraceId;
  }

  /**
   * Add trace headers to page requests
   */
  async setupTracing(page, testName) {
    const traceId = this.generateTraceId();
    
    // Add trace headers to all requests
    await page.route('**/*', async (route, request) => {
      const headers = {
        ...request.headers(),
        [this.config.traceIdHeader]: traceId,
        'X-Test-Name': testName,
        'X-Test-Session': process.env.TEST_SESSION_ID || 'local-test'
      };
      
      await route.continue({ headers });
    });

    return traceId;
  }

  /**
   * Log test event with trace correlation
   */
  logTestEvent(event, data = {}) {
    const logEntry = {
      timestamp: new Date().toISOString(),
      traceId: this.currentTraceId,
      event,
      data,
      testSession: process.env.TEST_SESSION_ID || 'local-test'
    };
    
    console.log('TEST_EVENT:', JSON.stringify(logEntry));
    return logEntry;
  }

  /**
   * Capture performance metrics with trace correlation
   */
  async capturePerformanceMetrics(page) {
    const metrics = await page.evaluate(() => {
      const perfData = performance.getEntriesByType('navigation')[0];
      const paintEntries = performance.getEntriesByType('paint');
      
      return {
        pageLoad: perfData ? perfData.loadEventEnd - perfData.fetchStart : null,
        domContentLoaded: perfData ? perfData.domContentLoadedEventEnd - perfData.fetchStart : null,
        firstPaint: paintEntries.find(entry => entry.name === 'first-paint')?.startTime || null,
        firstContentfulPaint: paintEntries.find(entry => entry.name === 'first-contentful-paint')?.startTime || null,
        url: window.location.href,
        timestamp: Date.now()
      };
    });

    this.logTestEvent('performance_metrics', {
      ...metrics,
      thresholds: testConfig.performance.thresholds
    });

    return metrics;
  }

  /**
   * Validate performance against thresholds
   */
  validatePerformance(metrics) {
    const thresholds = testConfig.performance.thresholds;
    const violations = [];

    if (metrics.pageLoad && metrics.pageLoad > thresholds.pageLoad) {
      violations.push({
        metric: 'pageLoad',
        actual: metrics.pageLoad,
        threshold: thresholds.pageLoad
      });
    }

    if (metrics.firstContentfulPaint && metrics.firstContentfulPaint > thresholds.firstContentfulPaint) {
      violations.push({
        metric: 'firstContentfulPaint',
        actual: metrics.firstContentfulPaint,
        threshold: thresholds.firstContentfulPaint
      });
    }

    if (violations.length > 0) {
      this.logTestEvent('performance_violations', { violations });
    }

    return violations;
  }

  /**
   * Capture visual regression screenshot with metadata
   */
  async captureScreenshot(page, name, options = {}) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const filename = `${name}-${timestamp}-${this.currentTraceId}.png`;
    const path = `screenshots/${filename}`;

    await page.screenshot({
      path: `../screenshots/${filename}`,
      fullPage: options.fullPage || false,
      ...options
    });

    this.logTestEvent('screenshot_captured', {
      name,
      filename,
      path,
      fullPage: options.fullPage || false
    });

    return { filename, path };
  }

  /**
   * Send metrics to Prometheus if available
   */
  async sendMetricsToPrometheus(metrics) {
    if (!this.config.enableMetrics || !this.config.prometheusUrl) {
      return;
    }

    try {
      const prometheusMetrics = this.formatPrometheusMetrics(metrics);
      
      // Note: This would typically use a proper Prometheus client
      // For now, we'll log the metrics in Prometheus format
      this.logTestEvent('prometheus_metrics', { prometheusMetrics });
      
    } catch (error) {
      console.warn('Failed to send metrics to Prometheus:', error.message);
    }
  }

  /**
   * Format metrics for Prometheus
   */
  formatPrometheusMetrics(metrics) {
    const timestamp = Date.now();
    const labels = `{trace_id="${this.currentTraceId}",test_session="${process.env.TEST_SESSION_ID || 'local-test'}"}`;
    
    return [
      `pyairtable_test_page_load_seconds${labels} ${(metrics.pageLoad || 0) / 1000} ${timestamp}`,
      `pyairtable_test_first_contentful_paint_seconds${labels} ${(metrics.firstContentfulPaint || 0) / 1000} ${timestamp}`,
      `pyairtable_test_dom_content_loaded_seconds${labels} ${(metrics.domContentLoaded || 0) / 1000} ${timestamp}`
    ].join('\n');
  }

  /**
   * Create test context with tracing
   */
  createTestContext(testName, page) {
    const traceId = this.generateTraceId();
    
    this.logTestEvent('test_started', {
      testName,
      url: page.url(),
      browser: page.context().browser()?.browserType()?.name()
    });

    return {
      traceId,
      startTime: Date.now(),
      testName
    };
  }

  /**
   * Finish test context
   */
  finishTestContext(context, result) {
    const duration = Date.now() - context.startTime;
    
    this.logTestEvent('test_finished', {
      testName: context.testName,
      duration,
      result: result.status || 'unknown',
      error: result.error?.message
    });

    return { duration };
  }

  /**
   * Capture network activity for debugging
   */
  async captureNetworkActivity(page) {
    const requests = [];
    const responses = [];

    page.on('request', request => {
      requests.push({
        url: request.url(),
        method: request.method(),
        headers: request.headers(),
        timestamp: Date.now(),
        traceId: this.currentTraceId
      });
    });

    page.on('response', response => {
      responses.push({
        url: response.url(),
        status: response.status(),
        headers: response.headers(),
        timestamp: Date.now(),
        traceId: this.currentTraceId
      });
    });

    return { requests, responses };
  }
}

module.exports = TraceHelper;