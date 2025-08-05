# PyAirtable Synthetic User Tests

Comprehensive synthetic user testing framework for the PyAirtable AI platform with full LGTM stack integration (Loki, Grafana, Tempo, Mimir).

## 🎯 Overview

This testing framework simulates real user behaviors and interactions with the PyAirtable frontend to ensure optimal user experience, performance, and reliability. It includes specialized synthetic agents that mimic different user types and comprehensive monitoring integration.

## 🧪 Test Agents

### 1. New User Agent (`NewUserAgent`)
Simulates a first-time user exploring the platform:
- **Behavior**: Slow, exploratory, curious about features
- **Focus**: Onboarding flows, feature discovery, navigation learning
- **Scenarios**: Landing page exploration, first chat interaction, settings browsing

### 2. Power User Agent (`PowerUserAgent`)
Simulates an experienced user with advanced workflows:
- **Behavior**: Fast, efficient, uses advanced features
- **Focus**: Complex multi-step workflows, batch operations, edge cases
- **Scenarios**: Advanced chat queries, dashboard analytics, settings optimization

### 3. Error-Prone Agent (`ErrorProneAgent`)
Simulates a user who makes common mistakes:
- **Behavior**: Triggers validation errors, tests error handling
- **Focus**: Form validation, error recovery, edge case handling
- **Scenarios**: Invalid inputs, network issues, rapid interactions

### 4. Mobile Agent (`MobileAgent`)
Simulates mobile device usage patterns:
- **Behavior**: Touch interactions, responsive design testing
- **Focus**: Mobile UX, accessibility, gesture support
- **Scenarios**: Touch navigation, mobile forms, orientation changes

## 🚀 Quick Start

### Prerequisites

1. **Node.js 18+** and **npm**
2. **PyAirtable frontend** running at `http://localhost:3000`
3. **LGTM Stack** (optional but recommended):
   - Loki: `http://localhost:3100`
   - Mimir: `http://localhost:9009`
   - Tempo: `http://localhost:3200`
   - Grafana: `http://localhost:3000`

### Installation

```bash
cd /Users/kg/IdeaProjects/pyairtable-compose/monitoring/lgtm-stack/synthetic-user-tests

# Install dependencies
npm install

# Install Playwright browsers
npx playwright install
```

### Running Tests

#### Basic Usage

```bash
# Run all test suites
./run-tests.sh

# Run specific test suite
./run-tests.sh new-user

# Run with specific browser
BROWSER=firefox ./run-tests.sh

# Run against different environment
BASE_URL=https://staging.pyairtable.com ./run-tests.sh
```

#### Advanced Usage

```bash
# Run with custom configuration
WORKERS=5 TIMEOUT=600000 ./run-tests.sh power-user

# Run in headed mode (visible browser)
HEADLESS=false ./run-tests.sh new-user

# Run with full LGTM integration
LOKI_URL=http://localhost:3100 \
MIMIR_URL=http://localhost:9009 \
TEMPO_URL=http://localhost:3200 \
./run-tests.sh all
```

## 🧩 Test Suites

### 1. New User Onboarding (`new-user-onboarding.spec.js`)
- ✅ Landing page exploration and engagement
- ✅ Navigation discovery (desktop + mobile)
- ✅ First chat interaction experience
- ✅ Feature discovery workflows
- ✅ Settings exploration (read-only)
- ✅ Performance and accessibility checks

### 2. Power User Workflows (`power-user-workflows.spec.js`)
- ✅ Advanced multi-turn chat conversations
- ✅ Complex dashboard operations and analytics
- ✅ Advanced settings configuration
- ✅ Cost optimization workflows
- ✅ Edge case and stress testing
- ✅ Performance benchmarking

### 3. Error Handling (`error-handling.spec.js`)
- ✅ Form validation error scenarios
- ✅ Chat input error handling
- ✅ Network error recovery
- ✅ JavaScript error resilience
- ✅ Accessibility error scenarios
- ✅ Data corruption and recovery

### 4. Mobile Responsive (planned)
- 📱 Touch interaction patterns
- 📱 Responsive design validation
- 📱 Mobile-specific features
- 📱 Accessibility on mobile
- 📱 Performance on mobile devices

### 5. Accessibility (planned)
- ♿ Screen reader compatibility
- ♿ Keyboard navigation
- ♿ Color contrast compliance
- ♿ ARIA label validation
- ♿ Focus management

### 6. Performance (planned)
- ⚡ Page load time benchmarks
- ⚡ Interaction response times
- ⚡ Memory usage monitoring
- ⚡ Network efficiency testing
- ⚡ Bundle size analysis

## 📊 Monitoring & Observability

### LGTM Stack Integration

The framework provides comprehensive observability through the LGTM stack:

#### 📋 Loki (Logs)
- **Structured logging** of all test events
- **Agent behavior tracking** with detailed context
- **Error logging** with stack traces and metadata
- **Test execution logs** with timing and status

#### 📈 Mimir (Metrics)
- **Test execution metrics** (duration, success rate)
- **User agent performance** (actions per minute, error rate)
- **Page load times** and interaction response times
- **Feature discovery rates** by agent type
- **Error distribution** across different scenarios

#### 🔍 Tempo (Traces)
- **Distributed tracing** of test execution flows
- **User journey tracking** across multiple pages
- **Performance bottleneck identification**
- **Cross-service interaction monitoring**

#### 📊 Grafana (Dashboards)
- **Real-time test metrics** visualization
- **Historical trend analysis**
- **Alert configuration** for test failures
- **Custom dashboard** creation for specific metrics

### Custom Reporters

#### LGTM Reporter (`src/reporters/lgtm-reporter.js`)
- Integrates with Playwright's reporting system
- Sends structured data to all LGTM components
- Exports Prometheus metrics format
- Generates comprehensive HTML reports

#### Metrics Collector (`src/monitoring/metrics-collector.js`)
- Collects and aggregates test metrics
- Provides real-time monitoring capabilities
- Exports data in multiple formats
- Generates actionable recommendations

## 🎛️ Test Orchestration

### Test Orchestrator (`src/orchestrator/test-orchestrator.js`)

The orchestrator provides advanced test management:

- **Concurrent execution** with configurable limits
- **Retry logic** for flaky tests
- **Scheduled execution** via cron expressions
- **Priority-based** test suite ordering
- **Resource management** and cleanup
- **Comprehensive reporting** and metrics collection

#### Usage

```javascript
const TestOrchestrator = require('./src/orchestrator/test-orchestrator');

const orchestrator = new TestOrchestrator({
  maxConcurrentTests: 3,
  testTimeout: 300000,
  scheduleEnabled: true,
  cronSchedule: '0 */6 * * *', // Every 6 hours
  baseUrl: 'http://localhost:3000'
});

await orchestrator.initialize();
await orchestrator.runAllTests();
```

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:3000` | PyAirtable frontend URL |
| `BROWSER` | `chromium` | Browser to use (chromium/firefox/webkit) |
| `HEADLESS` | `true` | Run browser in headless mode |
| `WORKERS` | `3` | Number of parallel test workers |
| `TIMEOUT` | `300000` | Test timeout in milliseconds |
| `OUTPUT_DIR` | `test-results` | Output directory for test artifacts |
| `LOKI_URL` | `http://localhost:3100` | Loki endpoint for logs |
| `MIMIR_URL` | `http://localhost:9009` | Mimir endpoint for metrics |
| `TEMPO_URL` | `http://localhost:3200` | Tempo endpoint for traces |
| `GRAFANA_URL` | `http://localhost:3000` | Grafana dashboard URL |

### Playwright Configuration

The `playwright.config.js` includes:
- **Multi-browser support** (Chrome, Firefox, Safari, Mobile)
- **Custom reporter integration** for LGTM stack
- **Global setup/teardown** hooks
- **Artifact collection** (screenshots, videos, traces)
- **Retry configuration** for stability

## 📁 Project Structure

```
synthetic-user-tests/
├── 📄 package.json                 # Dependencies and scripts
├── 📄 playwright.config.js         # Playwright configuration
├── 📄 run-tests.sh                 # Main test runner script
├── 📄 README.md                    # This file
├── 📁 src/
│   ├── 📁 agents/                  # Synthetic user agents
│   │   ├── 📄 user-agent-base.js   # Base agent class
│   │   ├── 📄 new-user-agent.js    # New user behavior
│   │   ├── 📄 power-user-agent.js  # Power user behavior
│   │   ├── 📄 error-prone-agent.js # Error testing behavior
│   │   └── 📄 mobile-agent.js      # Mobile user behavior
│   ├── 📁 monitoring/              # Monitoring and metrics
│   │   └── 📄 metrics-collector.js # LGTM integration
│   ├── 📁 orchestrator/            # Test orchestration
│   │   └── 📄 test-orchestrator.js # Test execution management
│   ├── 📁 reporters/               # Custom reporters
│   │   └── 📄 lgtm-reporter.js     # LGTM stack reporter
│   └── 📁 setup/                   # Global setup/teardown
├── 📁 tests/                       # Test specifications
│   ├── 📁 user-journeys/           # User journey tests
│   │   ├── 📄 new-user-onboarding.spec.js
│   │   └── 📄 power-user-workflows.spec.js
│   ├── 📁 error-scenarios/         # Error handling tests
│   │   └── 📄 error-handling.spec.js
│   ├── 📁 mobile/                  # Mobile-specific tests
│   ├── 📁 accessibility/           # Accessibility tests
│   └── 📁 performance/             # Performance tests
├── 📁 test-results/                # Test outputs and reports
├── 📁 logs/                        # Application logs
└── 📁 screenshots/                 # Test failure screenshots
```

## 🎨 Customization

### Adding Custom Agents

```javascript
const UserAgentBase = require('./src/agents/user-agent-base');

class CustomAgent extends UserAgentBase {
  constructor(options) {
    super({
      ...options,
      behavior: 'custom-behavior',
      speed: 'normal'
    });
  }

  async execute(page) {
    // Implement custom behavior
    await this.customWorkflow(page);
  }

  async customWorkflow(page) {
    // Custom test logic
  }
}

module.exports = CustomAgent;
```

### Adding Custom Test Suites

```javascript
// In your test orchestrator
orchestrator.addTestSuite('custom-suite', {
  spec: 'tests/custom/custom-suite.spec.js',
  priority: 10,
  timeout: 240000,
  browsers: ['chromium'],
  agents: ['custom'],
  description: 'Custom test suite description'
});
```

## 🔍 Troubleshooting

### Common Issues

1. **Frontend not available**
   ```bash
   # Check if PyAirtable frontend is running
   curl http://localhost:3000
   ```

2. **Browser installation issues**
   ```bash
   # Reinstall browsers
   npx playwright install --force
   ```

3. **LGTM stack connection issues**
   ```bash
   # Check stack availability
   curl http://localhost:3100/ready  # Loki
   curl http://localhost:9009/ready  # Mimir
   curl http://localhost:3200/ready  # Tempo
   ```

4. **Test timeouts**
   ```bash
   # Increase timeout for slow environments
   TIMEOUT=600000 ./run-tests.sh
   ```

### Debug Mode

```bash
# Run with debug output
DEBUG=1 ./run-tests.sh new-user

# Run single test with browser visible
HEADLESS=false npx playwright test tests/user-journeys/new-user-onboarding.spec.js --debug
```

## 📈 Metrics and KPIs

### Test Health Metrics
- **Success Rate**: Percentage of tests passing
- **Execution Time**: Average test suite duration
- **Flakiness Rate**: Tests that pass/fail inconsistently
- **Coverage**: Features covered by synthetic tests

### User Experience Metrics
- **Page Load Time**: Time to interactive for each page
- **Interaction Response**: Time from user action to response
- **Error Recovery**: Time to recover from errors
- **Feature Discovery**: Percentage of features found by new users

### Application Performance
- **Memory Usage**: Browser memory consumption during tests
- **Network Efficiency**: API call patterns and response times
- **JavaScript Errors**: Frequency and types of client-side errors
- **Accessibility Score**: WCAG compliance metrics

## 🎯 Best Practices

### Test Design
- **Realistic User Flows**: Mirror actual user behavior patterns
- **Gradual Complexity**: Start simple, build to complex scenarios
- **Error Recovery**: Always test recovery paths
- **Cross-Browser**: Validate core flows across browsers

### Monitoring
- **Alert Thresholds**: Set meaningful alert levels
- **Trend Analysis**: Monitor metrics over time
- **Root Cause Analysis**: Use traces to debug issues
- **Proactive Monitoring**: Catch issues before users do

### Maintenance
- **Regular Updates**: Keep agents current with UI changes
- **Performance Baselines**: Update benchmarks regularly
- **Test Hygiene**: Remove obsolete tests, fix flaky ones
- **Documentation**: Keep scenarios and expectations current

## 🤝 Contributing

1. **Add new test scenarios** to existing agents
2. **Create specialized agents** for specific user types
3. **Enhance monitoring capabilities** with new metrics
4. **Improve error handling** and recovery scenarios
5. **Add performance benchmarks** for new features

## 📋 Roadmap

### Phase 1 (Completed)
- ✅ Core agent framework
- ✅ Basic test suites (new user, power user, error handling)
- ✅ LGTM stack integration
- ✅ Test orchestration system

### Phase 2 (Planned)
- 📱 Mobile agent implementation
- ♿ Accessibility testing suite
- ⚡ Performance benchmarking suite
- 🔄 CI/CD integration
- 📊 Advanced Grafana dashboards

### Phase 3 (Future)
- 🤖 AI-powered test generation
- 🔄 Self-healing test scenarios
- 📈 Predictive analytics
- 🌐 Multi-region testing
- 🔐 Security testing integration

## 📞 Support

For questions or issues:
1. Check the **troubleshooting section** above
2. Review **test logs** in the `logs/` directory
3. Examine **test artifacts** in `test-results/`
4. Check **Grafana dashboards** for metrics insights

---

*This synthetic user testing framework ensures PyAirtable delivers exceptional user experiences through comprehensive, automated testing that mirrors real-world usage patterns.*