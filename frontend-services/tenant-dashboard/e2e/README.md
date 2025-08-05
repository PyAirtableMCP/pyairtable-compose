# End-to-End Testing Guide

This directory contains comprehensive end-to-end tests for the PyAirtable Tenant Dashboard application using Playwright. These tests validate complete user journeys from registration to advanced feature usage.

## 🎯 Test Coverage

Our E2E tests cover the following critical user journeys:

### Core User Flows
- **User Registration** (`user-registration.spec.ts`)
  - Complete registration flow from landing page
  - Email verification and onboarding
  - Input validation and error handling
  - Registration with existing accounts
  - Password strength validation

- **Login and Session Management** (`user-login-journey.spec.ts`)
  - Login with valid/invalid credentials
  - Session persistence across page refreshes
  - "Remember me" functionality
  - Session expiry handling
  - Logout functionality
  - Multi-device login scenarios

- **Chat Interface Interaction** (`chat-interface-journey.spec.ts`)
  - Real-time chat functionality
  - AI response handling and streaming
  - Message history persistence
  - Connection status monitoring
  - Error recovery in chat
  - File upload support (if available)

- **Airtable Integration** (`airtable-integration-journey.spec.ts`)
  - Data query and analysis workflows
  - Formula creation and validation
  - Automation setup
  - View creation and management
  - Data import/export operations
  - Real-time data operations
  - Multi-table operations

### Advanced Testing
- **Error Scenarios** (`error-scenarios.spec.ts`)
  - Network connectivity issues
  - Authentication errors
  - API failures and recovery
  - Input validation edge cases
  - Browser compatibility issues
  - Performance under stress

- **Complete User Journey** (`complete-user-journey.spec.ts`)
  - End-to-end workflow from registration to advanced usage
  - Mobile responsiveness validation
  - Accessibility compliance
  - Performance benchmarking
  - Concurrent user scenarios

## 🏗️ Test Architecture

### Helper Classes
- **AuthHelpers** (`helpers/auth-helpers.ts`) - Authentication flow utilities
- **ChatHelpers** (`helpers/chat-helpers.ts`) - Chat interface interactions
- **CommonHelpers** (`helpers/common-helpers.ts`) - Shared utilities and assertions

### Test Fixtures
- **Test Users** (`fixtures/test-users.ts`) - Predefined user data and scenarios
- **Test Data** (`fixtures/test-users.ts`) - Sample data for various test scenarios

### Global Setup
- **Global Setup** (`global-setup.ts`) - Database seeding and environment preparation
- **Global Teardown** (`global-teardown.ts`) - Cleanup and resource disposal

## 🚀 Running Tests

### Prerequisites
```bash
# Install dependencies
npm install

# Install Playwright browsers
npm run test:e2e:install
```

### Test Execution
```bash
# Run all E2E tests
npm run test:e2e

# Run tests with UI (interactive mode)
npm run test:e2e:ui

# Run tests in headed mode (see browser)
npm run test:e2e:headed

# Debug specific test
npm run test:e2e:debug

# Run core functionality tests only
npm run test:e2e:core

# Run extended tests (Airtable integration, error scenarios)
npm run test:e2e:extended

# Run mobile tests
npm run test:e2e:mobile

# Run cross-browser tests
npm run test:e2e:cross-browser
```

### Viewing Reports
```bash
# View HTML test report
npm run test:e2e:report

# View trace for failed tests
npm run test:e2e:trace
```

## 🎭 Test Projects

Our Playwright configuration includes multiple test projects for comprehensive coverage:

### Browser Coverage
- **chromium-core** - Core functionality on Chrome
- **chromium-extended** - Extended features on Chrome
- **firefox** - Cross-browser compatibility
- **webkit** - Safari compatibility

### Device Coverage
- **mobile-chrome** - Mobile Chrome (Pixel 5)
- **mobile-safari** - Mobile Safari (iPhone 12)

## 🔧 Configuration

### Environment Variables
```bash
# Base URL for testing
BASE_URL=http://localhost:3002

# Database URL for test environment
DATABASE_URL=file:./test.db

# Node environment
NODE_ENV=test
```

### Playwright Configuration
The main configuration is in `playwright.config.ts` with:
- Multiple browser projects
- CI-optimized settings
- Comprehensive reporting
- Video and screenshot capture
- Trace collection on failures

## 📊 CI/CD Integration

Tests are automatically run in GitHub Actions with:
- Matrix strategy for different browsers/devices
- Parallel execution for faster feedback
- Artifact collection (videos, screenshots, traces)
- Test result reporting
- Automatic issue creation on failures

### GitHub Actions Workflow
The workflow (`.github/workflows/e2e-tests.yml`) includes:
- **e2e-tests** - Main test execution across all projects
- **performance-tests** - Performance-focused tests (scheduled)
- **accessibility-tests** - A11y compliance validation
- **test-summary** - Consolidated results reporting
- **notify-on-failure** - Automatic issue creation for failures

## 🛠️ Development Workflow

### Adding New Tests
1. Create test file in `/e2e/` directory
2. Use existing helpers and fixtures
3. Follow naming convention: `feature-name.spec.ts`
4. Include proper test steps and assertions
5. Add test to appropriate project in `playwright.config.ts`

### Test Data Management
- Use `generateUniqueTestUser()` for parallel test execution
- Clean up test data using `CommonHelpers.cleanupTestData()`
- Mock external APIs appropriately
- Use fixtures for consistent test data

### Debugging Tests
```bash
# Run specific test with debug
npx playwright test user-login-journey.spec.ts --debug

# Run with browser visible
npx playwright test --headed

# Generate and view traces
npx playwright test --trace on
npx playwright show-trace test-results/trace.zip
```

## 📈 Performance Monitoring

Our tests include performance validation:
- Response time measurement for chat interactions
- Page load performance tracking
- Memory usage monitoring
- Concurrent user handling

### Performance Thresholds
- Simple chat responses: < 10 seconds
- Complex queries: < 45 seconds
- Page navigation: < 5 seconds
- Authentication flows: < 10 seconds

## ♿ Accessibility Testing

Accessibility validation includes:
- Keyboard navigation testing
- Screen reader compatibility
- ARIA label validation
- Color contrast verification
- Focus management

## 🔍 Troubleshooting

### Common Issues

**Tests failing due to timing issues:**
```bash
# Increase timeout in playwright.config.ts
timeout: 60000
```

**Database connection errors:**
```bash
# Ensure test database is properly initialized
npx prisma db push --force-reset
```

**Browser installation issues:**
```bash
# Reinstall browsers
npx playwright install --force
```

### Test Flakiness
- Use proper wait strategies (`waitForSelector`, `waitForLoadState`)
- Implement retry logic for network-dependent operations
- Use `expect.poll()` for dynamic content
- Mock external dependencies consistently

## 📝 Best Practices

### Test Design
1. **Independent Tests** - Each test should be self-contained
2. **Clear Test Steps** - Use `test.step()` for complex workflows
3. **Descriptive Names** - Test names should clearly describe the scenario
4. **Proper Cleanup** - Always clean up test data
5. **Error Handling** - Test both happy path and error scenarios

### Assertions
1. **Specific Selectors** - Use data-testid attributes when possible
2. **Wait Strategies** - Always wait for elements before interacting
3. **Multiple Assertions** - Verify multiple aspects of functionality
4. **Error Messages** - Include helpful error messages in assertions

### Maintenance
1. **Regular Updates** - Keep tests updated with application changes
2. **Performance Monitoring** - Monitor test execution times
3. **Coverage Review** - Regularly review test coverage
4. **Documentation** - Keep this README updated with changes

## 🔗 Related Documentation

- [Playwright Documentation](https://playwright.dev/docs/intro)
- [Application Architecture](../README.md)
- [API Documentation](../docs/api.md)
- [Deployment Guide](../docs/deployment.md)

## 🤝 Contributing

When contributing E2E tests:
1. Follow existing patterns and helper usage
2. Include proper test documentation
3. Ensure tests pass in all browser projects
4. Add performance benchmarks for new features
5. Update this README with significant changes

---

**Note**: These tests validate real user workflows and should reflect actual user behavior. Always test from the user's perspective rather than implementation details.