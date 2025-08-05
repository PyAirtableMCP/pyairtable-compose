const faker = require('../utils/faker-mock');
const winston = require('winston');

/**
 * Base class for synthetic user agents
 * Provides common functionality for user behavior simulation
 */
class UserAgentBase {
  constructor(options = {}) {
    this.id = options.id || faker.string.uuid();
    this.name = options.name || faker.person.fullName();
    this.email = options.email || faker.internet.email();
    this.behavior = options.behavior || 'standard';
    this.speed = options.speed || 'normal'; // slow, normal, fast
    this.errorProne = options.errorProne || false;
    this.sessionData = {};
    
    // Initialize logger
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
      ),
      defaultMeta: { 
        agentId: this.id, 
        agentName: this.name,
        behavior: this.behavior 
      },
      transports: [
        new winston.transports.File({ 
          filename: `logs/agent-${this.id}.log` 
        }),
        new winston.transports.Console({
          format: winston.format.simple()
        })
      ]
    });
    
    // Behavior configurations
    this.behaviorConfig = {
      slow: {
        actionDelay: { min: 2000, max: 5000 },
        typingSpeed: { min: 50, max: 200 },
        readTime: { min: 3000, max: 8000 }
      },
      normal: {
        actionDelay: { min: 500, max: 2000 },
        typingSpeed: { min: 20, max: 100 },
        readTime: { min: 1000, max: 3000 }
      },
      fast: {
        actionDelay: { min: 100, max: 500 },
        typingSpeed: { min: 10, max: 50 },
        readTime: { min: 200, max: 1000 }
      }
    };
  }

  /**
   * Get random delay based on agent speed
   */
  getRandomDelay(type = 'action') {
    const config = this.behaviorConfig[this.speed];
    const range = config[type] || config.action;
    return faker.number.int({ min: range.min, max: range.max });
  }

  /**
   * Simulate human-like typing
   */
  async typeHumanLike(page, selector, text) {
    const typingDelay = this.getRandomDelay('typingSpeed');
    
    // Clear existing text first
    await page.fill(selector, '');
    
    // Type character by character with random delays
    for (const char of text) {
      await page.type(selector, char, { delay: typingDelay + faker.number.int({ min: -10, max: 10 }) });
      
      // Occasional longer pauses (thinking)
      if (Math.random() < 0.1) {
        await page.waitForTimeout(faker.number.int({ min: 500, max: 1500 }));
      }
    }
  }

  /**
   * Simulate reading content
   */
  async simulateReading(page, selector = null) {
    const readTime = this.getRandomDelay('readTime');
    
    if (selector) {
      // Scroll to element and read
      await page.locator(selector).scrollIntoViewIfNeeded();
    }
    
    // Simulate random scrolling while reading
    const scrollCount = faker.number.int({ min: 1, max: 3 });
    for (let i = 0; i < scrollCount; i++) {
      await page.mouse.wheel(0, faker.number.int({ min: 100, max: 300 }));
      await page.waitForTimeout(readTime / scrollCount);
    }
  }

  /**
   * Generate realistic mouse movements
   */
  async moveMouseToElement(page, selector) {
    const element = page.locator(selector);
    const box = await element.boundingBox();
    
    if (box) {
      // Add slight randomness to click position
      const x = box.x + box.width * (0.3 + Math.random() * 0.4);
      const y = box.y + box.height * (0.3 + Math.random() * 0.4);
      
      // Hover before clicking
      await page.mouse.move(x, y);
      await page.waitForTimeout(faker.number.int({ min: 100, max: 500 }));
    }
  }

  /**
   * Simulate clicking with human-like behavior
   */
  async humanClick(page, selector) {
    await this.moveMouseToElement(page, selector);
    await page.click(selector);
  }

  /**
   * Log agent action
   */
  logAction(action, details = {}) {
    this.logger.info(`Agent action: ${action}`, {
      action,
      timestamp: new Date().toISOString(),
      ...details
    });
  }

  /**
   * Log error with context
   */
  logError(error, context = {}) {
    this.logger.error('Agent error', {
      error: error.message,
      stack: error.stack,
      context,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Simulate network issues or errors
   */
  shouldSimulateError() {
    return this.errorProne && Math.random() < 0.1;
  }

  /**
   * Generate realistic form data
   */
  generateFormData() {
    return {
      firstName: faker.person.firstName(),
      lastName: faker.person.lastName(),
      email: faker.internet.email(),
      company: faker.company.name(),
      jobTitle: faker.person.jobTitle(),
      phone: faker.phone.number(),
      message: faker.lorem.paragraph()
    };
  }

  /**
   * Generate realistic search queries
   */
  generateSearchQuery() {
    const queries = [
      'sales data analysis',
      'customer records',
      'monthly revenue report',
      'product inventory',
      'user analytics',
      'project status',
      'team performance',
      'financial metrics',
      'workflow automation',
      'data visualization'
    ];
    
    return faker.helpers.arrayElement(queries);
  }

  /**
   * Generate realistic chat messages
   */
  generateChatMessage() {
    const messageTypes = [
      'question',
      'request',
      'greeting',
      'command'
    ];
    
    const type = faker.helpers.arrayElement(messageTypes);
    
    const messages = {
      question: [
        'How many records are in my sales table?',
        'What was our revenue last month?',
        'Can you show me all customers from California?',
        'Which products have low inventory?',
        'How many active projects do we have?'
      ],
      request: [
        'Create a new customer record',
        'Update the project status to completed',
        'Generate a sales report for Q4',
        'Export all data to CSV',
        'Send a notification to the team'
      ],
      greeting: [
        'Hello, can you help me with my data?',
        'Hi there, I need assistance with Airtable',
        'Good morning, I have some questions'
      ],
      command: [
        'Show me all my Airtable bases',
        'List all tables in the CRM base',
        'Filter records by status equals active',
        'Sort customers by creation date',
        'Search for records containing "urgent"'
      ]
    };
    
    return faker.helpers.arrayElement(messages[type]);
  }

  /**
   * Wait for page to be stable
   */
  async waitForPageStability(page, timeout = 5000) {
    try {
      await page.waitForLoadState('networkidle', { timeout });
    } catch (error) {
      this.logger.warn('Page did not reach network idle state', { timeout });
    }
  }

  /**
   * Take screenshot for debugging
   */
  async takeScreenshot(page, name) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const filename = `screenshots/${this.id}-${name}-${timestamp}.png`;
    await page.screenshot({ path: filename });
    this.logger.info(`Screenshot taken: ${filename}`);
    return filename;
  }

  /**
   * Check if element exists and is visible
   */
  async isElementVisible(page, selector, timeout = 5000) {
    try {
      await page.waitForSelector(selector, { state: 'visible', timeout });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Get random element from array
   */
  getRandomElement(array) {
    return faker.helpers.arrayElement(array);
  }

  /**
   * Cleanup agent resources
   */
  async cleanup() {
    this.logger.info('Agent cleanup completed');
  }
}

module.exports = UserAgentBase;