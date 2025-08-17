# PyAirtable Synthetic Testing System

A comprehensive on-demand synthetic testing system that simulates real user behavior through the UI, tests complete user journeys end-to-end, generates trace IDs for observability correlation, and produces detailed reports with screenshots.

## 🚀 Quick Start

```bash
# Navigate to the synthetic tests directory
cd synthetic-tests

# Install dependencies
npm install
npx playwright install

# Run smoke tests
./run-tests.sh --suite smoke

# Run with headed browser for debugging
./run-tests.sh --suite smoke --headed

# Run full regression suite
./run-tests.sh --suite regression --browser firefox
```

## 📋 Features

### 🎭 Human-like Behavior
- **Variable typing speed** with realistic mistakes and corrections
- **Natural mouse movements** with random delays
- **Reading simulation** based on content length
- **Realistic form filling** with pauses between fields
- **Human-like scrolling** and navigation patterns

### 🔍 Observability Integration
- **Trace ID generation** for request correlation across services
- **Performance metrics collection** (page load times, response times)
- **Network activity monitoring** for debugging
- **Integration with Prometheus** for metrics export
- **Detailed logging** with structured events

### 📊 Visual Regression Testing
- **Screenshot comparison** with pixel-level analysis
- **Baseline management** for visual changes tracking
- **Difference highlighting** in generated reports
- **Configurable tolerance** for acceptable changes

### 📈 Comprehensive Reporting
- **HTML reports** with interactive test results
- **JSON/JUnit outputs** for CI/CD integration
- **Screenshot galleries** organized by test runs
- **Performance dashboards** with metrics visualization
- **Visual regression reports** with before/after comparisons

## 🧪 Test Scenarios

### 1. New User Journey (`@smoke`)
- User registration with form validation
- Airtable integration setup
- Data exploration and navigation
- Performance validation

### 2. Data Operations (`@regression`)
- Browse and explore data tables
- Search and filter functionality
- Record editing and creation
- Data export capabilities

### 3. AI Analysis (`@regression`)
- AI-powered data querying
- Insights and reports generation
- Data transformation requests
- Response quality validation

### 4. Collaboration (`@regression`)
- Workspace sharing
- Real-time collaborative editing
- Comment and notification systems

### 5. Error Recovery (`@regression`)
- Network failure simulation
- Service unavailability handling
- Retry mechanism testing
- Graceful degradation

## 🛠️ Configuration

### Test Configuration (`config/test-config.json`)

```json
{
  "environments": {
    "local": {
      "baseUrl": "http://localhost:3000",
      "apiUrl": "http://localhost:8000",
      "services": {
        "api-gateway": "http://localhost:8000",
        "airtable-gateway": "http://localhost:8002",
        // ... other services
      }
    }
  },
  "humanBehavior": {
    "typing": {
      "minSpeed": 80,      // WPM
      "maxSpeed": 200,     // WPM
      "mistakeRate": 0.02, // 2% chance of typos
      "backspaceChance": 0.1
    }
  },
  "performance": {
    "thresholds": {
      "pageLoad": 3000,              // milliseconds
      "firstContentfulPaint": 1500,  // milliseconds
      "largestContentfulPaint": 2500, // milliseconds
      "cumulativeLayoutShift": 0.1,
      "firstInputDelay": 100          // milliseconds
    }
  }
}
```

### Playwright Configuration (`config/playwright.config.js`)

Supports multiple browsers, environments, and reporting formats. Configured for:
- Cross-browser testing (Chrome, Firefox, Safari, Mobile)
- Multiple test environments (local, staging, production)
- Comprehensive reporting (HTML, JSON, JUnit)
- Screenshot and video capture on failures

## 📊 Usage Examples

### Basic Test Execution

```bash
# Run smoke tests on local environment
./run-tests.sh --suite smoke

# Run regression tests with specific browser
./run-tests.sh --suite regression --browser chromium --env local

# Run tests in headed mode for debugging
./run-tests.sh --suite smoke --headed --sequential

# Run specific test file
./run-tests.sh tests/new-user-journey.spec.js
```

### Advanced Options

```bash
# Dry run to see what would be executed
./run-tests.sh --suite full --dry-run

# Run with custom environment
TEST_ENV=staging ./run-tests.sh --suite regression

# Run with trace correlation disabled
./run-tests.sh --suite smoke --no-trace

# Generate all report formats
./run-tests.sh --suite smoke --format all
```

### Environment Variables

```bash
export TEST_SESSION_ID="custom-session-id"
export API_KEY="your-api-key"
export AIRTABLE_TOKEN="your-airtable-token"
export AIRTABLE_BASE="your-base-id"
```

## 📁 Directory Structure

```
synthetic-tests/
├── config/
│   ├── playwright.config.js      # Playwright configuration
│   └── test-config.json          # Test environment settings
├── tests/
│   ├── new-user-journey.spec.js  # Registration and onboarding
│   ├── data-operations.spec.js   # Data manipulation tests
│   ├── ai-analysis.spec.js       # AI functionality tests
│   ├── collaboration.spec.js     # Workspace collaboration
│   └── error-recovery.spec.js    # Error handling tests
├── utils/
│   ├── human-behavior.js         # Human-like interaction utilities
│   ├── trace-helper.js           # Observability and tracing
│   ├── visual-regression.js      # Screenshot comparison
│   ├── global-setup.js           # Test environment setup
│   └── global-teardown.js        # Cleanup and reporting
├── reports/                      # Generated test reports
├── screenshots/                  # Test screenshots and baselines
├── package.json                  # Dependencies and scripts
├── run-tests.sh                  # Main test runner script
└── README.md                     # This file
```

## 🔧 Development

### Adding New Tests

1. Create a new test file in the `tests/` directory
2. Import required utilities:

```javascript
const { test, expect } = require('@playwright/test');
const HumanBehavior = require('../utils/human-behavior');
const TraceHelper = require('../utils/trace-helper');
const VisualRegression = require('../utils/visual-regression');
```

3. Set up test context:

```javascript
test.beforeEach(async ({ page }) => {
  humanBehavior = new HumanBehavior();
  traceHelper = new TraceHelper();
  await traceHelper.setupTracing(page, 'your-test-name');
});
```

4. Use human-like interactions:

```javascript
await humanBehavior.humanNavigate(page, '/dashboard');
await humanBehavior.humanType(page, '#email', 'user@example.com');
await humanBehavior.humanClick(page, 'button[type="submit"]');
```

5. Add observability:

```javascript
const testContext = traceHelper.createTestContext('test-name', page);
traceHelper.logTestEvent('step_started', { step: 'description' });
await traceHelper.captureScreenshot(page, 'screenshot-name');
const metrics = await traceHelper.capturePerformanceMetrics(page);
```

### Extending Human Behavior

Add new human-like behaviors in `utils/human-behavior.js`:

```javascript
async customBehavior(page, options = {}) {
  // Implement realistic interaction patterns
  await this.randomDelay(min, max);
  await this.simulateReading(page, selector);
  // ... more behaviors
}
```

### Custom Assertions

Create domain-specific assertions for PyAirtable:

```javascript
// Performance assertions
expect(metrics.pageLoad).toBeLessThan(testConfig.performance.thresholds.pageLoad);

// Content assertions
expect(await page.textContent('.data-table')).toContain('expected content');

// Visual regression assertions
const comparison = await visualRegression.compareWithBaseline(screenshot, 'test-name');
expect(comparison.status).toBe('passed');
```

## 📊 Monitoring and Observability

### Trace Correlation

Every test generates unique trace IDs that flow through:
- Frontend requests
- API Gateway calls
- Backend service calls
- Database queries

Use trace IDs to correlate test activities with system behavior:

```bash
# Find all logs for a specific test session
grep "TEST_SESSION_ID=synthetic-test-123" /var/log/pyairtable/*.log

# Query Prometheus for test metrics
pyairtable_test_page_load_seconds{trace_id="uuid-here"}
```

### Performance Monitoring

Tests automatically collect and validate:
- **Page Load Times**: Full page rendering
- **First Contentful Paint**: Time to first visible content
- **Largest Contentful Paint**: Time to largest content element
- **Cumulative Layout Shift**: Visual stability metric
- **First Input Delay**: Interactivity metric

### Visual Regression Tracking

Screenshots are automatically captured and compared:
- **Baseline Management**: Automatic baseline creation
- **Pixel-level Comparison**: Configurable tolerance
- **Difference Highlighting**: Visual diff generation
- **Historical Tracking**: Change history over time

## 🚨 Troubleshooting

### Common Issues

1. **Services not responding**:
   ```bash
   # Check if PyAirtable services are running
   cd ../pyairtable-compose && ./start.sh
   # Verify service health
   curl http://localhost:8000/health
   ```

2. **Tests timing out**:
   - Increase timeouts in `config/test-config.json`
   - Run with `--headed` to see what's happening
   - Check network connectivity

3. **Screenshot comparison failures**:
   - Update baselines: `npm run update-baselines`
   - Adjust tolerance in `utils/visual-regression.js`
   - Review diff images in `screenshots/diff/`

4. **Performance test failures**:
   - Check system load during test execution
   - Verify database performance
   - Review network latency

### Debug Mode

Run tests in debug mode for detailed inspection:

```bash
# Headed browser with sequential execution
./run-tests.sh --suite smoke --headed --sequential

# Enable Playwright debug mode
PWDEBUG=1 ./run-tests.sh --suite smoke

# Verbose logging
DEBUG=pw:api ./run-tests.sh --suite smoke
```

### Logs and Reports

Check these locations for detailed information:

- **HTML Reports**: `reports/html-report/index.html`
- **Screenshots**: `screenshots/actual/`, `screenshots/diff/`
- **Performance Metrics**: `reports/metrics-*.json`
- **Test Logs**: Console output during test execution
- **Visual Regression**: `reports/visual-regression-report.html`

## 🤝 Contributing

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/new-test-scenario`
3. **Add tests** following the patterns in existing test files
4. **Update documentation** if adding new features
5. **Run the test suite**: `./run-tests.sh --suite full`
6. **Submit a pull request**

### Code Standards

- Use descriptive test and step names
- Include appropriate `@smoke` or `@regression` tags
- Add comprehensive error handling
- Capture screenshots at key decision points
- Log meaningful events for observability
- Follow the human behavior patterns

## 📚 References

- [Playwright Documentation](https://playwright.dev/)
- [PyAirtable Architecture](../README.md)
- [Observability Stack](../monitoring/README.md)
- [Test Strategy Guide](./docs/test-strategy.md)

---

*Generated by PyAirtable Synthetic Testing System v1.0.0*