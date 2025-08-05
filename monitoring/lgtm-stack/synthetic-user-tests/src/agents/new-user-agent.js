const UserAgentBase = require('./user-agent-base');

/**
 * Simulates a new user exploring the platform
 * Focuses on onboarding, discovery, and first-time usage patterns
 */
class NewUserAgent extends UserAgentBase {
  constructor(options = {}) {
    super({
      ...options,
      behavior: 'new-user',
      speed: options.speed || 'slow' // New users tend to be slower
    });
    
    this.explorationState = {
      visitedPages: new Set(),
      completedActions: new Set(),
      discoveredFeatures: new Set(),
      onboardingStep: 0
    };
  }

  /**
   * Main execution flow for new user behavior
   */
  async execute(page) {
    this.logAction('new_user_session_start');
    
    try {
      // Landing page exploration
      await this.exploreLandingPage(page);
      
      // Navigation discovery
      await this.discoverNavigation(page);
      
      // Feature exploration
      await this.exploreCoreFeatures(page);
      
      // Chat interaction
      await this.firstChatExperience(page);
      
      // Dashboard exploration
      await this.exploreDashboard(page);
      
      // Settings discovery
      await this.exploreSettings(page);
      
      this.logAction('new_user_session_complete', {
        pagesVisited: this.explorationState.visitedPages.size,
        actionsCompleted: this.explorationState.completedActions.size,
        featuresDiscovered: this.explorationState.discoveredFeatures.size
      });
      
    } catch (error) {
      this.logError(error, { phase: 'new_user_exploration' });
      await this.takeScreenshot(page, 'error');
      throw error;
    }
  }

  /**
   * Explore the landing page like a new user
   */
  async exploreLandingPage(page) {
    this.logAction('exploring_landing_page');
    
    // Navigate to home page
    await page.goto('/');
    await this.waitForPageStability(page);
    this.explorationState.visitedPages.add('/');
    
    // Read hero section
    await this.simulateReading(page, '[data-testid="hero-section"], .hero, h1');
    
    // Scroll and explore features
    const featureCards = page.locator('[data-testid="feature-card"], .feature-card, .card');
    const cardCount = await featureCards.count();
    
    for (let i = 0; i < Math.min(cardCount, 4); i++) {
      const card = featureCards.nth(i);
      await card.scrollIntoViewIfNeeded();
      await this.simulateReading(page);
      
      // Occasionally hover over cards
      if (Math.random() < 0.3) {
        await card.hover();
        await page.waitForTimeout(this.getRandomDelay('action'));
      }
    }
    
    // Look for CTA buttons
    const ctaButtons = page.locator('text="Start Chatting", text="Get Started", text="Try Now"');
    if (await ctaButtons.count() > 0) {
      this.explorationState.discoveredFeatures.add('cta_buttons');
      
      // Sometimes click, sometimes just notice
      if (Math.random() < 0.4) {
        await this.humanClick(page, ctaButtons.first());
        await this.waitForPageStability(page);
        this.explorationState.completedActions.add('clicked_main_cta');
      }
    }
    
    // Explore stats section
    const statsSection = page.locator('[data-testid="stats"], .stats, text="MCP Tools"');
    if (await statsSection.count() > 0) {
      await statsSection.first().scrollIntoViewIfNeeded();
      await this.simulateReading(page);
      this.explorationState.discoveredFeatures.add('stats_section');
    }
  }

  /**
   * Discover and explore navigation
   */
  async discoverNavigation(page) {
    this.logAction('discovering_navigation');
    
    // Look for main navigation
    const nav = page.locator('nav, [data-testid="navigation"], [role="navigation"]');
    
    if (await nav.count() > 0) {
      this.explorationState.discoveredFeatures.add('main_navigation');
      
      // Find navigation links
      const navLinks = nav.locator('a, button').filter({ hasText: /Chat|Dashboard|Settings|Cost/ });
      const linkCount = await navLinks.count();
      
      // Explore 2-3 navigation items
      const linksToExplore = Math.min(linkCount, 3);
      const shuffledIndexes = Array.from({ length: linkCount }, (_, i) => i)
        .sort(() => Math.random() - 0.5)
        .slice(0, linksToExplore);
      
      for (const index of shuffledIndexes) {
        const link = navLinks.nth(index);
        const text = await link.textContent();
        
        if (text) {
          this.logAction('exploring_nav_item', { item: text.trim() });
          
          // Hover first, then sometimes click
          await link.hover();
          await page.waitForTimeout(this.getRandomDelay('action'));
          
          if (Math.random() < 0.6) {
            await this.humanClick(page, link);
            await this.waitForPageStability(page);
            
            const currentUrl = page.url();
            this.explorationState.visitedPages.add(currentUrl);
            this.explorationState.completedActions.add(`visited_${text.trim().toLowerCase()}`);
            
            // Brief exploration of the new page
            await this.simulateReading(page);
            await page.waitForTimeout(this.getRandomDelay('readTime'));
          }
        }
      }
    }
    
    // Check for mobile menu toggle
    const mobileMenuToggle = page.locator('[data-testid="mobile-menu"], .mobile-menu-toggle, text="Menu"');
    if (await mobileMenuToggle.count() > 0) {
      this.explorationState.discoveredFeatures.add('mobile_menu');
    }
  }

  /**
   * Explore core features as a new user
   */
  async exploreCoreFeatures(page) {
    this.logAction('exploring_core_features');
    
    const featuresToExplore = [
      { name: 'Chat', path: '/chat', selector: '[data-testid="chat-interface"]' },
      { name: 'Dashboard', path: '/dashboard', selector: '[data-testid="dashboard"]' },
      { name: 'Cost Tracking', path: '/cost', selector: '[data-testid="cost-tracking"]' }
    ];
    
    for (const feature of featuresToExplore) {
      try {
        this.logAction('exploring_feature', { feature: feature.name });
        
        await page.goto(feature.path);
        await this.waitForPageStability(page);
        this.explorationState.visitedPages.add(feature.path);
        
        // Look for main feature elements
        if (await this.isElementVisible(page, feature.selector)) {
          this.explorationState.discoveredFeatures.add(feature.name.toLowerCase());
          await this.simulateReading(page, feature.selector);
        }
        
        // Explore page-specific elements
        await this.explorePageElements(page, feature.name);
        
        // Random exploration actions
        await this.performRandomExploration(page);
        
      } catch (error) {
        this.logError(error, { feature: feature.name });
      }
    }
  }

  /**
   * First chat experience for new user
   */
  async firstChatExperience(page) {
    this.logAction('first_chat_experience');
    
    await page.goto('/chat');
    await this.waitForPageStability(page);
    
    // Look for chat input
    const chatInput = page.locator('textarea, input[placeholder*="chat"], [data-testid="chat-input"]');
    
    if (await chatInput.count() > 0) {
      this.explorationState.discoveredFeatures.add('chat_interface');
      
      // First-time user might read instructions or examples
      await this.simulateReading(page);
      
      // Try some suggested prompts or ask simple questions
      const firstMessages = [
        'Hello, what can you help me with?',
        'How do I get started?',
        'Show me what you can do',
        'Help me understand this platform'
      ];
      
      const message = this.getRandomElement(firstMessages);
      
      try {
        await this.typeHumanLike(page, chatInput, message);
        await page.waitForTimeout(this.getRandomDelay('action'));
        
        // Look for send button
        const sendButton = page.locator('button[type="submit"], button:has-text("Send"), [data-testid="send-button"]');
        if (await sendButton.count() > 0) {
          await this.humanClick(page, sendButton);
          this.explorationState.completedActions.add('sent_first_message');
          
          // Wait for response and read it
          await page.waitForTimeout(3000);
          await this.simulateReading(page);
        }
        
      } catch (error) {
        this.logError(error, { action: 'first_chat_message' });
      }
    }
  }

  /**
   * Explore dashboard as new user
   */
  async exploreDashboard(page) {
    this.logAction('exploring_dashboard');
    
    await page.goto('/dashboard');
    await this.waitForPageStability(page);
    
    // Look for dashboard tabs
    const tabs = page.locator('[role="tab"], .tab, [data-testid*="tab"]');
    const tabCount = await tabs.count();
    
    if (tabCount > 0) {
      this.explorationState.discoveredFeatures.add('dashboard_tabs');
      
      // Click through a few tabs
      const tabsToExplore = Math.min(tabCount, 3);
      for (let i = 0; i < tabsToExplore; i++) {
        const tab = tabs.nth(i);
        const tabText = await tab.textContent();
        
        if (tabText) {
          this.logAction('exploring_dashboard_tab', { tab: tabText.trim() });
          await this.humanClick(page, tab);
          await this.waitForPageStability(page);
          await this.simulateReading(page);
          
          this.explorationState.completedActions.add(`viewed_tab_${tabText.trim().toLowerCase()}`);
        }
      }
    }
    
    // Look for metrics cards
    const metricCards = page.locator('.card, [data-testid*="metric"], .metric');
    const cardCount = await metricCards.count();
    
    if (cardCount > 0) {
      this.explorationState.discoveredFeatures.add('metrics_cards');
      
      // Hover over some cards
      for (let i = 0; i < Math.min(cardCount, 4); i++) {
        const card = metricCards.nth(i);
        await card.hover();
        await page.waitForTimeout(this.getRandomDelay('action'));
      }
    }
  }

  /**
   * Explore settings as new user
   */
  async exploreSettings(page) {
    this.logAction('exploring_settings');
    
    await page.goto('/settings');
    await this.waitForPageStability(page);
    
    // Look for settings tabs
    const settingsTabs = page.locator('[role="tab"], .tab').filter({ hasText: /General|Model|Notification|Airtable|Security/ });
    const tabCount = await settingsTabs.count();
    
    if (tabCount > 0) {
      this.explorationState.discoveredFeatures.add('settings_tabs');
      
      // Browse through settings tabs without making changes
      for (let i = 0; i < Math.min(tabCount, 2); i++) {
        const tab = settingsTabs.nth(i);
        const tabText = await tab.textContent();
        
        if (tabText) {
          this.logAction('viewing_settings_tab', { tab: tabText.trim() });
          await this.humanClick(page, tab);
          await this.waitForPageStability(page);
          await this.simulateReading(page);
          
          // Look at form fields without changing them
          const formFields = page.locator('input, select, textarea');
          const fieldCount = await formFields.count();
          
          if (fieldCount > 0) {
            // Just hover over a few fields to show interest
            for (let j = 0; j < Math.min(fieldCount, 3); j++) {
              const field = formFields.nth(j);
              await field.hover();
              await page.waitForTimeout(this.getRandomDelay('action'));
            }
          }
          
          this.explorationState.completedActions.add(`viewed_settings_${tabText.trim().toLowerCase()}`);
        }
      }
    }
  }

  /**
   * Explore page-specific elements
   */
  async explorePageElements(page, featureName) {
    // Look for buttons, links, and interactive elements
    const interactiveElements = page.locator('button, a, [role="button"]').filter({ hasNotText: /^\\s*$/ });
    const elementCount = await interactiveElements.count();
    
    if (elementCount > 0) {
      // Hover over some elements to show curiosity
      const elementsToHover = Math.min(elementCount, 3);
      for (let i = 0; i < elementsToHover; i++) {
        const element = interactiveElements.nth(i);
        if (await element.isVisible()) {
          await element.hover();
          await page.waitForTimeout(this.getRandomDelay('action') / 2);
        }
      }
    }
  }

  /**
   * Perform random exploration actions
   */
  async performRandomExploration(page) {
    const actions = [
      async () => {
        // Random scrolling
        await page.mouse.wheel(0, faker.number.int({ min: 200, max: 800 }));
        await page.waitForTimeout(this.getRandomDelay('action'));
      },
      async () => {
        // Look for help or info buttons
        const helpButtons = page.locator('button:has-text("Help"), button:has-text("Info"), [title*="help"], [title*="info"]');
        if (await helpButtons.count() > 0) {
          await helpButtons.first().hover();
          await page.waitForTimeout(this.getRandomDelay('action'));
        }
      },
      async () => {
        // Check for tooltips by hovering over icons
        const icons = page.locator('svg, .icon, [data-testid*="icon"]');
        if (await icons.count() > 0) {
          const randomIcon = icons.nth(faker.number.int({ min: 0, max: Math.min(await icons.count() - 1, 2) }));
          await randomIcon.hover();
          await page.waitForTimeout(this.getRandomDelay('action'));
        }
      }
    ];
    
    // Perform 1-2 random actions
    const actionsToPerform = Math.min(actions.length, faker.number.int({ min: 1, max: 2 }));
    for (let i = 0; i < actionsToPerform; i++) {
      const action = this.getRandomElement(actions);
      try {
        await action();
      } catch (error) {
        // Ignore errors in random exploration
        this.logger.debug('Random exploration action failed', { error: error.message });
      }
    }
  }

  /**
   * Get exploration summary
   */
  getExplorationSummary() {
    return {
      agentId: this.id,
      behavior: this.behavior,
      pagesVisited: Array.from(this.explorationState.visitedPages),
      actionsCompleted: Array.from(this.explorationState.completedActions),
      featuresDiscovered: Array.from(this.explorationState.discoveredFeatures),
      explorationScore: this.calculateExplorationScore()
    };
  }

  /**
   * Calculate exploration score based on discovered features and completed actions
   */
  calculateExplorationScore() {
    const maxFeatures = 10;
    const maxActions = 15;
    
    const featureScore = (this.explorationState.discoveredFeatures.size / maxFeatures) * 60;
    const actionScore = (this.explorationState.completedActions.size / maxActions) * 40;
    
    return Math.min(100, Math.round(featureScore + actionScore));
  }
}

module.exports = NewUserAgent;