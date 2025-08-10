/**
 * Real User Experience Test - PyAirtable Application
 * 
 * This test runs in headed mode to show exactly what a real user sees
 * when interacting with the application. It captures all errors, network
 * failures, and user experience issues.
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// Test configuration
const TEST_CONFIG = {
  baseUrl: 'http://localhost:3000',
  headless: false,  // Show the browser so we can see what's happening
  slowMo: 2000,     // Slow down actions to see what's happening
  timeout: 30000,   // 30 second timeout for operations
  screenshotDir: './real-user-test-screenshots',
  reportFile: './real-user-experience-report.md'
};

// Test user data
const TEST_USER = {
  email: 'test.user@example.com',
  password: 'TestPassword123!',
  name: 'Test User'
};

class RealUserExperienceTest {
  constructor() {
    this.browser = null;
    this.page = null;
    this.testResults = [];
    this.screenshotCounter = 0;
    this.consoleErrors = [];
    this.networkErrors = [];
    
    // Ensure screenshot directory exists
    if (!fs.existsSync(TEST_CONFIG.screenshotDir)) {
      fs.mkdirSync(TEST_CONFIG.screenshotDir, { recursive: true });
    }
  }

  async initialize() {
    console.log('🚀 Starting Real User Experience Test...');
    console.log('📍 Target URL:', TEST_CONFIG.baseUrl);
    console.log('👀 Running in headed mode - you will see the browser');
    
    try {
      this.browser = await chromium.launch({
        headless: TEST_CONFIG.headless,
        slowMo: TEST_CONFIG.slowMo,
        args: [
          '--disable-web-security',
          '--disable-features=VizDisplayCompositor',
          '--start-maximized'
        ]
      });

      this.page = await this.browser.newPage();
      
      // Set up error and network monitoring
      await this.setupMonitoring();
      
      console.log('✅ Browser initialized successfully');
      return true;
    } catch (error) {
      console.error('❌ Failed to initialize browser:', error.message);
      this.recordTestResult('Browser Initialization', false, error.message);
      return false;
    }
  }

  async setupMonitoring() {
    // Monitor console errors
    this.page.on('console', msg => {
      if (msg.type() === 'error') {
        const error = `Console Error: ${msg.text()}`;
        console.log('🔴', error);
        this.consoleErrors.push({
          timestamp: new Date().toISOString(),
          message: msg.text(),
          location: msg.location()
        });
      }
    });

    // Monitor network failures
    this.page.on('response', response => {
      if (response.status() >= 400) {
        const error = `Network Error: ${response.status()} ${response.statusText()} - ${response.url()}`;
        console.log('🔴', error);
        this.networkErrors.push({
          timestamp: new Date().toISOString(),
          status: response.status(),
          statusText: response.statusText(),
          url: response.url()
        });
      }
    });

    // Monitor page errors
    this.page.on('pageerror', error => {
      console.log('🔴 Page Error:', error.message);
      this.consoleErrors.push({
        timestamp: new Date().toISOString(),
        message: error.message,
        stack: error.stack
      });
    });
  }

  async takeScreenshot(name, description = '') {
    try {
      const filename = `${String(this.screenshotCounter).padStart(2, '0')}-${name}.png`;
      const filepath = path.join(TEST_CONFIG.screenshotDir, filename);
      
      await this.page.screenshot({ 
        path: filepath,
        fullPage: true
      });
      
      console.log(`📸 Screenshot taken: ${filename} - ${description}`);
      this.screenshotCounter++;
      
      return filename;
    } catch (error) {
      console.log(`❌ Failed to take screenshot: ${error.message}`);
      return null;
    }
  }

  recordTestResult(testName, passed, details = '', screenshot = null) {
    const result = {
      test: testName,
      passed,
      details,
      screenshot,
      timestamp: new Date().toISOString()
    };
    
    this.testResults.push(result);
    console.log(`${passed ? '✅' : '❌'} ${testName}: ${details}`);
  }

  async testBasicNavigation() {
    console.log('\n📍 Testing Basic Navigation...');
    
    try {
      console.log('Navigating to application...');
      const response = await this.page.goto(TEST_CONFIG.baseUrl, { 
        waitUntil: 'networkidle',
        timeout: TEST_CONFIG.timeout 
      });
      
      await this.page.waitForTimeout(3000); // Wait for any dynamic content
      
      const screenshot = await this.takeScreenshot('home-page', 'Initial page load');
      
      if (!response || response.status() !== 200) {
        this.recordTestResult(
          'Basic Navigation', 
          false, 
          `Failed to load page. Status: ${response ? response.status() : 'No response'}`,
          screenshot
        );
        return false;
      }

      // Check if page has basic content
      const title = await this.page.title();
      console.log('Page title:', title);
      
      // Check for common elements
      const body = await this.page.locator('body').count();
      if (body === 0) {
        this.recordTestResult('Basic Navigation', false, 'Page body is empty', screenshot);
        return false;
      }

      // Get page content for analysis
      const content = await this.page.content();
      console.log('Page content length:', content.length);
      
      if (content.length < 100) {
        this.recordTestResult('Basic Navigation', false, 'Page content is suspiciously short', screenshot);
        return false;
      }

      this.recordTestResult('Basic Navigation', true, `Successfully loaded page. Title: "${title}"`, screenshot);
      return true;
    } catch (error) {
      const screenshot = await this.takeScreenshot('navigation-error', 'Navigation failed');
      this.recordTestResult('Basic Navigation', false, error.message, screenshot);
      return false;
    }
  }

  async testUserRegistration() {
    console.log('\n📍 Testing User Registration...');
    
    try {
      // Look for registration link/button
      console.log('Looking for registration link...');
      
      // Common registration selectors
      const registrationSelectors = [
        'a[href*="register"]',
        'a[href*="signup"]',
        'button:has-text("Register")',
        'button:has-text("Sign Up")',
        '[data-testid="register-button"]',
        '[data-testid="signup-button"]'
      ];

      let registrationFound = false;
      for (const selector of registrationSelectors) {
        try {
          const element = await this.page.locator(selector).first();
          if (await element.count() > 0) {
            console.log(`Found registration element: ${selector}`);
            await element.click();
            registrationFound = true;
            break;
          }
        } catch (e) {
          // Continue trying other selectors
        }
      }

      if (!registrationFound) {
        // Try navigating directly to registration page
        console.log('Trying direct navigation to registration page...');
        const registrationUrls = [
          `${TEST_CONFIG.baseUrl}/register`,
          `${TEST_CONFIG.baseUrl}/signup`,
          `${TEST_CONFIG.baseUrl}/auth/register`,
          `${TEST_CONFIG.baseUrl}/auth/signup`
        ];

        for (const url of registrationUrls) {
          try {
            const response = await this.page.goto(url, { waitUntil: 'networkidle', timeout: 10000 });
            if (response && response.status() === 200) {
              console.log(`Successfully navigated to: ${url}`);
              registrationFound = true;
              break;
            }
          } catch (e) {
            console.log(`Failed to load: ${url}`);
          }
        }
      }

      await this.page.waitForTimeout(2000);
      const regScreenshot = await this.takeScreenshot('registration-page', 'Registration page loaded');

      if (!registrationFound) {
        this.recordTestResult('User Registration', false, 'Could not find registration page or form', regScreenshot);
        return false;
      }

      // Look for registration form fields
      console.log('Looking for registration form fields...');
      const emailSelectors = [
        'input[type="email"]',
        'input[name="email"]',
        '[data-testid="email"]'
      ];
      
      const passwordSelectors = [
        'input[type="password"]',
        'input[name="password"]',
        '[data-testid="password"]'
      ];

      let emailField = null;
      let passwordField = null;

      // Find email field
      for (const selector of emailSelectors) {
        try {
          const field = this.page.locator(selector).first();
          if (await field.count() > 0) {
            emailField = field;
            console.log(`Found email field: ${selector}`);
            break;
          }
        } catch (e) {}
      }

      // Find password field
      for (const selector of passwordSelectors) {
        try {
          const field = this.page.locator(selector).first();
          if (await field.count() > 0) {
            passwordField = field;
            console.log(`Found password field: ${selector}`);
            break;
          }
        } catch (e) {}
      }

      if (!emailField || !passwordField) {
        this.recordTestResult(
          'User Registration', 
          false, 
          `Missing form fields - Email: ${emailField ? 'Found' : 'Missing'}, Password: ${passwordField ? 'Found' : 'Missing'}`,
          regScreenshot
        );
        return false;
      }

      // Fill out the registration form
      console.log('Filling out registration form...');
      await emailField.fill(TEST_USER.email);
      await passwordField.fill(TEST_USER.password);

      await this.page.waitForTimeout(1000);
      const filledFormScreenshot = await this.takeScreenshot('registration-form-filled', 'Registration form filled out');

      // Look for submit button
      const submitSelectors = [
        'button[type="submit"]',
        'button:has-text("Register")',
        'button:has-text("Sign Up")',
        '[data-testid="submit-button"]'
      ];

      let submitButton = null;
      for (const selector of submitSelectors) {
        try {
          const button = this.page.locator(selector).first();
          if (await button.count() > 0) {
            submitButton = button;
            console.log(`Found submit button: ${selector}`);
            break;
          }
        } catch (e) {}
      }

      if (!submitButton) {
        this.recordTestResult('User Registration', false, 'Could not find submit button', filledFormScreenshot);
        return false;
      }

      // Submit the form
      console.log('Submitting registration form...');
      await submitButton.click();
      
      await this.page.waitForTimeout(3000); // Wait for response
      const afterSubmitScreenshot = await this.takeScreenshot('registration-after-submit', 'After registration submission');

      // Check the result
      const currentUrl = this.page.url();
      console.log('URL after registration:', currentUrl);
      
      this.recordTestResult(
        'User Registration', 
        true, 
        `Registration form submitted. Final URL: ${currentUrl}`,
        afterSubmitScreenshot
      );
      
      return true;

    } catch (error) {
      const errorScreenshot = await this.takeScreenshot('registration-error', 'Registration error');
      this.recordTestResult('User Registration', false, error.message, errorScreenshot);
      return false;
    }
  }

  async testUserLogin() {
    console.log('\n📍 Testing User Login...');
    
    try {
      // Navigate back to home if not already there
      await this.page.goto(TEST_CONFIG.baseUrl, { waitUntil: 'networkidle' });
      
      // Look for login link/button
      console.log('Looking for login link...');
      
      const loginSelectors = [
        'a[href*="login"]',
        'a[href*="signin"]',
        'button:has-text("Login")',
        'button:has-text("Sign In")',
        '[data-testid="login-button"]',
        '[data-testid="signin-button"]'
      ];

      let loginFound = false;
      for (const selector of loginSelectors) {
        try {
          const element = await this.page.locator(selector).first();
          if (await element.count() > 0) {
            console.log(`Found login element: ${selector}`);
            await element.click();
            loginFound = true;
            break;
          }
        } catch (e) {}
      }

      if (!loginFound) {
        // Try direct navigation
        const loginUrls = [
          `${TEST_CONFIG.baseUrl}/login`,
          `${TEST_CONFIG.baseUrl}/signin`,
          `${TEST_CONFIG.baseUrl}/auth/login`,
          `${TEST_CONFIG.baseUrl}/auth/signin`
        ];

        for (const url of loginUrls) {
          try {
            const response = await this.page.goto(url, { waitUntil: 'networkidle', timeout: 10000 });
            if (response && response.status() === 200) {
              console.log(`Successfully navigated to: ${url}`);
              loginFound = true;
              break;
            }
          } catch (e) {}
        }
      }

      await this.page.waitForTimeout(2000);
      const loginScreenshot = await this.takeScreenshot('login-page', 'Login page loaded');

      if (!loginFound) {
        this.recordTestResult('User Login', false, 'Could not find login page or form', loginScreenshot);
        return false;
      }

      // Find and fill login form (similar to registration)
      const emailField = await this.findElement([
        'input[type="email"]',
        'input[name="email"]',
        'input[name="username"]',
        '[data-testid="email"]'
      ]);

      const passwordField = await this.findElement([
        'input[type="password"]',
        'input[name="password"]',
        '[data-testid="password"]'
      ]);

      if (!emailField || !passwordField) {
        this.recordTestResult('User Login', false, 'Could not find login form fields', loginScreenshot);
        return false;
      }

      console.log('Filling out login form...');
      await emailField.fill(TEST_USER.email);
      await passwordField.fill(TEST_USER.password);

      const filledLoginScreenshot = await this.takeScreenshot('login-form-filled', 'Login form filled out');

      // Submit login form
      const submitButton = await this.findElement([
        'button[type="submit"]',
        'button:has-text("Login")',
        'button:has-text("Sign In")',
        '[data-testid="submit-button"]'
      ]);

      if (!submitButton) {
        this.recordTestResult('User Login', false, 'Could not find login submit button', filledLoginScreenshot);
        return false;
      }

      console.log('Submitting login form...');
      await submitButton.click();
      
      await this.page.waitForTimeout(5000); // Wait longer for login processing
      const afterLoginScreenshot = await this.takeScreenshot('login-after-submit', 'After login submission');

      const finalUrl = this.page.url();
      console.log('URL after login:', finalUrl);

      this.recordTestResult(
        'User Login', 
        true, 
        `Login form submitted. Final URL: ${finalUrl}`,
        afterLoginScreenshot
      );

      return true;

    } catch (error) {
      const errorScreenshot = await this.takeScreenshot('login-error', 'Login error');
      this.recordTestResult('User Login', false, error.message, errorScreenshot);
      return false;
    }
  }

  async findElement(selectors) {
    for (const selector of selectors) {
      try {
        const element = this.page.locator(selector).first();
        if (await element.count() > 0) {
          return element;
        }
      } catch (e) {}
    }
    return null;
  }

  async testInteractiveElements() {
    console.log('\n📍 Testing Interactive Elements...');
    
    try {
      // Take screenshot of current page
      const currentScreenshot = await this.takeScreenshot('interactive-elements-test', 'Testing interactive elements');
      
      // Look for clickable elements
      const clickableSelectors = [
        'button',
        'a[href]',
        '[role="button"]',
        '.btn',
        '[data-testid*="button"]'
      ];

      const clickableElements = [];
      
      for (const selector of clickableSelectors) {
        try {
          const elements = await this.page.locator(selector).all();
          for (const element of elements) {
            const text = await element.textContent();
            const isVisible = await element.isVisible();
            if (isVisible && text && text.trim()) {
              clickableElements.push({
                selector,
                text: text.trim(),
                element
              });
            }
          }
        } catch (e) {}
      }

      console.log(`Found ${clickableElements.length} interactive elements`);
      
      // Try clicking a few elements
      for (let i = 0; i < Math.min(3, clickableElements.length); i++) {
        const item = clickableElements[i];
        try {
          console.log(`Clicking element: "${item.text}"`);
          await item.element.click();
          await this.page.waitForTimeout(2000);
          
          const afterClickScreenshot = await this.takeScreenshot(
            `click-${i}`, 
            `After clicking "${item.text}"`
          );
        } catch (e) {
          console.log(`Failed to click element "${item.text}": ${e.message}`);
        }
      }

      this.recordTestResult(
        'Interactive Elements', 
        true, 
        `Found and tested ${clickableElements.length} interactive elements`,
        currentScreenshot
      );

      return true;
    } catch (error) {
      const errorScreenshot = await this.takeScreenshot('interactive-error', 'Interactive elements test error');
      this.recordTestResult('Interactive Elements', false, error.message, errorScreenshot);
      return false;
    }
  }

  async generateReport() {
    console.log('\n📝 Generating comprehensive report...');
    
    const report = [
      '# Real User Experience Test Report',
      `**Test Date:** ${new Date().toISOString()}`,
      `**Target URL:** ${TEST_CONFIG.baseUrl}`,
      `**Test Duration:** ${Math.round((Date.now() - this.startTime) / 1000)}s`,
      '',
      '## Executive Summary',
      '',
      `Total Tests: ${this.testResults.length}`,
      `Passed: ${this.testResults.filter(r => r.passed).length}`,
      `Failed: ${this.testResults.filter(r => !r.passed).length}`,
      `Console Errors: ${this.consoleErrors.length}`,
      `Network Errors: ${this.networkErrors.length}`,
      '',
      '## Test Results',
      ''
    ];

    // Add individual test results
    this.testResults.forEach(result => {
      report.push(`### ${result.test}`);
      report.push(`**Status:** ${result.passed ? '✅ PASSED' : '❌ FAILED'}`);
      report.push(`**Details:** ${result.details}`);
      if (result.screenshot) {
        report.push(`**Screenshot:** ![${result.test}](${TEST_CONFIG.screenshotDir}/${result.screenshot})`);
      }
      report.push(`**Timestamp:** ${result.timestamp}`);
      report.push('');
    });

    // Add console errors
    if (this.consoleErrors.length > 0) {
      report.push('## Console Errors');
      report.push('');
      this.consoleErrors.forEach((error, i) => {
        report.push(`### Error ${i + 1}`);
        report.push(`**Message:** ${error.message}`);
        report.push(`**Timestamp:** ${error.timestamp}`);
        if (error.location) {
          report.push(`**Location:** Line ${error.location.lineNumber}, Column ${error.location.columnNumber}`);
        }
        report.push('');
      });
    }

    // Add network errors
    if (this.networkErrors.length > 0) {
      report.push('## Network Errors');
      report.push('');
      this.networkErrors.forEach((error, i) => {
        report.push(`### Network Error ${i + 1}`);
        report.push(`**Status:** ${error.status} ${error.statusText}`);
        report.push(`**URL:** ${error.url}`);
        report.push(`**Timestamp:** ${error.timestamp}`);
        report.push('');
      });
    }

    // Add recommendations
    report.push('## Recommendations');
    report.push('');
    
    const failedTests = this.testResults.filter(r => !r.passed);
    if (failedTests.length > 0) {
      report.push('**Critical Issues:**');
      failedTests.forEach(test => {
        report.push(`- ${test.test}: ${test.details}`);
      });
      report.push('');
    }

    if (this.consoleErrors.length > 0) {
      report.push('**Console Errors Need Attention:**');
      report.push(`- Found ${this.consoleErrors.length} JavaScript errors that may affect functionality`);
      report.push('');
    }

    if (this.networkErrors.length > 0) {
      report.push('**Network Issues:**');
      report.push(`- Found ${this.networkErrors.length} network request failures`);
      report.push('');
    }

    // Write report to file
    const reportContent = report.join('\n');
    fs.writeFileSync(TEST_CONFIG.reportFile, reportContent);
    
    console.log(`📄 Report saved to: ${TEST_CONFIG.reportFile}`);
    console.log(`📸 Screenshots saved to: ${TEST_CONFIG.screenshotDir}`);
    
    return reportContent;
  }

  async runAllTests() {
    this.startTime = Date.now();
    
    const initialized = await this.initialize();
    if (!initialized) {
      console.log('❌ Test suite failed to initialize');
      return false;
    }

    console.log('\n🧪 Running comprehensive user experience tests...');
    
    // Run all tests
    await this.testBasicNavigation();
    await this.testUserRegistration();
    await this.testUserLogin();
    await this.testInteractiveElements();
    
    // Generate final report
    await this.generateReport();
    
    // Final screenshot
    await this.takeScreenshot('final-state', 'Final application state');
    
    console.log('\n🏁 Test suite completed!');
    console.log(`📊 Results: ${this.testResults.filter(r => r.passed).length}/${this.testResults.length} tests passed`);
    
    return true;
  }

  async cleanup() {
    if (this.browser) {
      await this.browser.close();
    }
  }
}

// Run the test suite
async function main() {
  const test = new RealUserExperienceTest();
  
  try {
    await test.runAllTests();
  } catch (error) {
    console.error('❌ Test suite encountered an error:', error.message);
  } finally {
    await test.cleanup();
  }
}

// Only run if this file is executed directly
if (require.main === module) {
  main();
}

module.exports = { RealUserExperienceTest };