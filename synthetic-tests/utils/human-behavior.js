const testConfig = require('../config/test-config.json');

class HumanBehavior {
  constructor() {
    this.config = testConfig.humanBehavior;
  }

  /**
   * Generate a random delay within the specified range
   */
  randomDelay(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }

  /**
   * Human-like typing with variable speed and occasional mistakes
   */
  async humanType(page, selector, text, options = {}) {
    const element = await page.locator(selector);
    await element.focus();
    
    const { 
      minSpeed = this.config.typing.minSpeed,
      maxSpeed = this.config.typing.maxSpeed,
      mistakeRate = this.config.typing.mistakeRate,
      backspaceChance = this.config.typing.backspaceChance
    } = options;

    let currentText = '';
    
    for (let i = 0; i < text.length; i++) {
      // Calculate typing speed for this character
      const charDelay = this.randomDelay(
        60000 / maxSpeed, // Convert WPM to milliseconds per character
        60000 / minSpeed
      );

      // Occasionally make a mistake
      if (Math.random() < mistakeRate && currentText.length > 0) {
        // Type a wrong character
        const wrongChar = String.fromCharCode(text.charCodeAt(i) + 1);
        await element.type(wrongChar, { delay: charDelay });
        currentText += wrongChar;
        
        await page.waitForTimeout(this.randomDelay(200, 500));
        
        // Realize mistake and backspace
        if (Math.random() < backspaceChance) {
          await element.press('Backspace');
          currentText = currentText.slice(0, -1);
          await page.waitForTimeout(this.randomDelay(100, 300));
        }
      }

      // Type the correct character
      await element.type(text[i], { delay: charDelay });
      currentText += text[i];
      
      // Random pause between words
      if (text[i] === ' ' && Math.random() < 0.3) {
        await page.waitForTimeout(this.randomDelay(200, 800));
      }
    }
  }

  /**
   * Human-like mouse movement with delays
   */
  async humanClick(page, selector, options = {}) {
    const element = page.locator(selector);
    
    // Move to element with delay
    await element.hover();
    await page.waitForTimeout(
      this.randomDelay(
        this.config.mouse.moveDelay.min,
        this.config.mouse.moveDelay.max
      )
    );
    
    // Click with delay
    await element.click(options);
    await page.waitForTimeout(
      this.randomDelay(
        this.config.mouse.clickDelay.min,
        this.config.mouse.clickDelay.max
      )
    );
  }

  /**
   * Human-like form filling
   */
  async fillForm(page, formData) {
    for (const [selector, value] of Object.entries(formData)) {
      await this.humanClick(page, selector);
      await page.waitForTimeout(this.randomDelay(100, 300));
      
      // Clear existing content
      await page.locator(selector).selectText();
      await page.keyboard.press('Delete');
      
      await this.humanType(page, selector, value);
      await page.waitForTimeout(this.randomDelay(200, 500));
    }
  }

  /**
   * Human-like navigation with realistic delays
   */
  async humanNavigate(page, url) {
    await page.goto(url);
    
    // Wait for page to start loading
    await page.waitForTimeout(
      this.randomDelay(
        this.config.navigation.pageLoadWait.min,
        this.config.navigation.pageLoadWait.max
      )
    );
    
    // Wait for network to be idle (simulating human reading)
    await page.waitForLoadState('networkidle');
  }

  /**
   * Simulate reading time based on content length
   */
  async simulateReading(page, selector) {
    try {
      const element = page.locator(selector);
      const text = await element.textContent();
      
      if (text) {
        // Assume 200 WPM reading speed
        const readingTime = (text.split(' ').length / 200) * 60 * 1000;
        const actualWait = Math.min(readingTime, 5000); // Cap at 5 seconds
        await page.waitForTimeout(actualWait);
      }
    } catch (error) {
      // If element not found, just wait a bit
      await page.waitForTimeout(1000);
    }
  }

  /**
   * Scroll like a human would
   */
  async humanScroll(page, options = {}) {
    const {
      direction = 'down',
      distance = 300,
      steps = 3
    } = options;

    const stepDistance = distance / steps;
    
    for (let i = 0; i < steps; i++) {
      await page.mouse.wheel(0, direction === 'down' ? stepDistance : -stepDistance);
      await page.waitForTimeout(this.randomDelay(200, 500));
    }
    
    // Pause to "read" content
    await page.waitForTimeout(this.randomDelay(500, 1500));
  }

  /**
   * Generate realistic user data
   */
  generateTestUser() {
    const timestamp = Date.now();
    const randomNum = Math.floor(Math.random() * 1000);
    
    return {
      email: `test.user.${timestamp}.${randomNum}@example.com`,
      password: 'TestPassword123!',
      firstName: `Test${randomNum}`,
      lastName: 'User',
      company: 'Test Company Inc.'
    };
  }

  /**
   * Wait for element with human-like patience
   */
  async waitForElement(page, selector, options = {}) {
    const { timeout = 10000, visible = true } = options;
    
    try {
      const element = page.locator(selector);
      await element.waitFor({ 
        state: visible ? 'visible' : 'attached',
        timeout 
      });
      
      // Add small delay as humans don't react instantly
      await page.waitForTimeout(
        this.randomDelay(
          this.config.navigation.elementWait.min,
          this.config.navigation.elementWait.max
        )
      );
      
      return element;
    } catch (error) {
      throw new Error(`Element ${selector} not found within ${timeout}ms`);
    }
  }
}

module.exports = HumanBehavior;