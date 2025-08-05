const UserAgentBase = require('./user-agent-base');

/**
 * Simulates mobile device usage patterns
 * Focuses on touch interactions, responsive design, and mobile-specific behaviors
 */
class MobileAgent extends UserAgentBase {
  constructor(options = {}) {
    super({
      ...options,
      behavior: 'mobile-user',
      speed: options.speed || 'normal'
    });
    
    this.mobileState = {
      deviceType: options.deviceType || 'phone', // phone, tablet
      orientation: options.orientation || 'portrait', // portrait, landscape
      touchInteractions: new Set(),
      gesturePatterns: new Set(),
      responsiveFeatures: new Set(),
      accessibilityFeatures: new Set()
    };
    
    this.touchPatterns = {
      tap: { duration: 100, pressure: 0.5 },
      longPress: { duration: 800, pressure: 0.7 },
      swipe: { duration: 300, distance: 200 },
      scroll: { duration: 200, velocity: 500 }
    };
  }

  /**
   * Main execution flow for mobile user behavior
   */
  async execute(page) {
    this.logAction('mobile_session_start', { 
      deviceType: this.mobileState.deviceType,
      orientation: this.mobileState.orientation 
    });
    
    try {
      // Configure mobile viewport
      await this.configureMobileViewport(page);
      
      // Test responsive navigation
      await this.testResponsiveNavigation(page);
      
      // Test touch interactions
      await this.testTouchInteractions(page);
      
      // Test mobile gestures
      await this.testMobileGestures(page);
      
      // Test mobile-specific features
      await this.testMobileSpecificFeatures(page);
      
      // Test accessibility features
      await this.testAccessibilityFeatures(page);
      
      // Test orientation changes
      await this.testOrientationChanges(page);
      
      // Test mobile form interactions
      await this.testMobileFormInteractions(page);
      
      this.logAction('mobile_session_complete', {
        touchInteractions: this.mobileState.touchInteractions.size,
        gesturePatterns: this.mobileState.gesturePatterns.size,
        responsiveFeatures: this.mobileState.responsiveFeatures.size,
        accessibilityFeatures: this.mobileState.accessibilityFeatures.size
      });
      
    } catch (error) {
      this.logError(error, { phase: 'mobile_testing' });
      await this.takeScreenshot(page, 'mobile-error');
      throw error;
    }
  }

  /**
   * Configure mobile viewport and device settings
   */
  async configureMobileViewport(page) {
    const viewports = {
      phone: {
        portrait: { width: 375, height: 812 },
        landscape: { width: 812, height: 375 }
      },
      tablet: {
        portrait: { width: 768, height: 1024 },
        landscape: { width: 1024, height: 768 }
      }
    };
    
    const viewport = viewports[this.mobileState.deviceType][this.mobileState.orientation];
    await page.setViewportSize(viewport);
    
    // Add mobile user agent
    await page.setExtraHTTPHeaders({
      'User-Agent': this.getMobileUserAgent()
    });
    
    this.logAction('mobile_viewport_configured', viewport);
  }

  /**
   * Get mobile user agent string
   */
  getMobileUserAgent() {
    const userAgents = {
      phone: 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Mobile/15E148 Safari/604.1',
      tablet: 'Mozilla/5.0 (iPad; CPU OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Mobile/15E148 Safari/604.1'
    };
    
    return userAgents[this.mobileState.deviceType];
  }

  /**
   * Test responsive navigation
   */
  async testResponsiveNavigation(page) {
    this.logAction('testing_responsive_navigation');
    
    await page.goto('/');
    await this.waitForPageStability(page);
    
    // Look for mobile menu toggle
    const mobileMenuToggle = page.locator(
      'button[aria-label*="menu"], button[aria-label*="Menu"], ' +
      '[data-testid="mobile-menu"], .mobile-menu-toggle, ' +
      'button:has-text("Menu"), button:has(svg):not(:has-text(""))'
    );
    
    if (await mobileMenuToggle.count() > 0) {
      this.mobileState.responsiveFeatures.add('mobile_menu_toggle');
      
      // Test mobile menu opening
      await this.simulateTouchTap(page, mobileMenuToggle.first());
      await page.waitForTimeout(500);
      
      // Look for opened menu
      const openMenu = page.locator(
        '[data-testid="mobile-menu"][data-state="open"], ' +
        '.mobile-menu.open, .mobile-menu:not([hidden]), ' +
        'nav[aria-expanded="true"]'
      );
      
      if (await openMenu.count() > 0) {
        this.mobileState.touchInteractions.add('menu_open');
        
        // Test navigation links in mobile menu
        const navLinks = openMenu.locator('a, button').filter({ hasText: /Chat|Dashboard|Settings/ });
        const linkCount = await navLinks.count();
        
        if (linkCount > 0) {
          // Tap on a navigation link
          const randomLink = navLinks.nth(faker.number.int({ min: 0, max: Math.min(linkCount - 1, 2) }));
          await this.simulateTouchTap(page, randomLink);
          await this.waitForPageStability(page);
          
          this.mobileState.touchInteractions.add('mobile_nav_link');
        }
        
        // Close menu by tapping outside or close button
        const closeButton = page.locator('button[aria-label*="close"], button:has-text("×"), [data-testid="close"]');
        if (await closeButton.count() > 0) {
          await this.simulateTouchTap(page, closeButton.first());
        } else {
          // Tap outside menu
          await page.mouse.click(50, 50);
        }
        
        this.mobileState.touchInteractions.add('menu_close');
      }
    }
  }

  /**
   * Test touch interactions
   */
  async testTouchInteractions(page) {
    this.logAction('testing_touch_interactions');
    
    // Test different pages for touch interactions
    const pages = ['/', '/chat', '/dashboard'];
    
    for (const pagePath of pages) {
      await page.goto(pagePath);
      await this.waitForPageStability(page);
      
      await this.testTouchInteractionsOnPage(page, pagePath);
    }
  }

  /**
   * Test touch interactions on specific page
   */
  async testTouchInteractionsOnPage(page, pagePath) {
    // Test tap interactions
    await this.testTapInteractions(page);
    
    // Test long press interactions
    await this.testLongPressInteractions(page);
    
    // Test double tap
    await this.testDoubleTapInteractions(page);
    
    this.logAction('touch_interactions_tested', { page: pagePath });
  }

  /**
   * Test tap interactions
   */
  async testTapInteractions(page) {
    const tappableElements = page.locator(
      'button, a, [role="button"], [role="link"], ' +
      '.card, [data-testid*="card"], [onclick], [tabindex="0"]'
    );
    
    const elementCount = await tappableElements.count();
    
    if (elementCount > 0) {
      // Test tapping on multiple elements
      const elementsToTap = Math.min(elementCount, 3);
      
      for (let i = 0; i < elementsToTap; i++) {
        const element = tappableElements.nth(i);
        
        if (await element.isVisible()) {
          await this.simulateTouchTap(page, element);
          await page.waitForTimeout(this.getRandomDelay('action'));
          
          this.mobileState.touchInteractions.add('tap_interaction');
        }
      }
    }
  }

  /**
   * Test long press interactions
   */
  async testLongPressInteractions(page) {
    const longPressElements = page.locator(
      '.card, [data-testid*="card"], [data-testid*="item"], ' +
      'li, .list-item, [role="menuitem"]'
    );
    
    const elementCount = await longPressElements.count();
    
    if (elementCount > 0) {
      const element = longPressElements.first();
      
      if (await element.isVisible()) {
        await this.simulateLongPress(page, element);
        await page.waitForTimeout(1000);
        
        // Look for context menu or long press actions
        const contextMenu = page.locator(
          '[role="menu"], .context-menu, .dropdown-menu, ' +
          '[data-testid="context-menu"]'
        );
        
        if (await contextMenu.count() > 0) {
          this.mobileState.touchInteractions.add('long_press_context_menu');
        }
        
        this.mobileState.touchInteractions.add('long_press');
      }
    }
  }

  /**
   * Test double tap interactions
   */
  async testDoubleTapInteractions(page) {
    const doubleTapElements = page.locator(
      'img, .image, [data-testid*="image"], ' +
      '.zoomable, [data-testid*="zoom"]'
    );
    
    if (await doubleTapElements.count() > 0) {
      const element = doubleTapElements.first();
      
      if (await element.isVisible()) {
        await this.simulateDoubleTap(page, element);
        await page.waitForTimeout(500);
        
        this.mobileState.touchInteractions.add('double_tap');
      }
    }
  }

  /**
   * Test mobile gestures
   */
  async testMobileGestures(page) {
    this.logAction('testing_mobile_gestures');
    
    // Test scrolling gestures
    await this.testScrollGestures(page);
    
    // Test swipe gestures
    await this.testSwipeGestures(page);
    
    // Test pinch gestures
    await this.testPinchGestures(page);
  }

  /**
   * Test scroll gestures
   */
  async testScrollGestures(page) {
    // Vertical scrolling
    await this.simulateVerticalScroll(page, 'down', 300);
    await page.waitForTimeout(500);
    
    await this.simulateVerticalScroll(page, 'up', 200);
    await page.waitForTimeout(500);
    
    // Horizontal scrolling (if applicable)
    await this.simulateHorizontalScroll(page, 'right', 100);
    await page.waitForTimeout(500);
    
    this.mobileState.gesturePatterns.add('scroll_gestures');
  }

  /**
   * Test swipe gestures
   */
  async testSwipeGestures(page) {
    // Look for swipeable elements
    const swipeableElements = page.locator(
      '[data-swipeable], .swipeable, .carousel, ' +
      '.slider, [data-testid*="swipe"]'
    );
    
    if (await swipeableElements.count() > 0) {
      const element = swipeableElements.first();
      const box = await element.boundingBox();
      
      if (box) {
        // Swipe left
        await this.simulateSwipe(page, 
          { x: box.x + box.width * 0.8, y: box.y + box.height * 0.5 },
          { x: box.x + box.width * 0.2, y: box.y + box.height * 0.5 }
        );
        
        await page.waitForTimeout(500);
        
        // Swipe right
        await this.simulateSwipe(page,
          { x: box.x + box.width * 0.2, y: box.y + box.height * 0.5 },
          { x: box.x + box.width * 0.8, y: box.y + box.height * 0.5 }
        );
        
        this.mobileState.gesturePatterns.add('swipe_gestures');
      }
    }
  }

  /**
   * Test pinch gestures
   */
  async testPinchGestures(page) {
    // Look for zoomable content
    const zoomableElements = page.locator(
      'img, canvas, [data-zoomable], .zoomable, ' +
      '[data-testid*="zoom"], .chart'
    );
    
    if (await zoomableElements.count() > 0) {
      const element = zoomableElements.first();
      
      if (await element.isVisible()) {
        await this.simulatePinchZoom(page, element, 'out');
        await page.waitForTimeout(500);
        
        await this.simulatePinchZoom(page, element, 'in');
        await page.waitForTimeout(500);
        
        this.mobileState.gesturePatterns.add('pinch_gestures');
      }
    }
  }

  /**
   * Test mobile-specific features
   */
  async testMobileSpecificFeatures(page) {
    this.logAction('testing_mobile_specific_features');
    
    // Test pull-to-refresh
    await this.testPullToRefresh(page);
    
    // Test mobile keyboard behavior
    await this.testMobileKeyboard(page);
    
    // Test mobile-specific UI elements
    await this.testMobileUIElements(page);
  }

  /**
   * Test pull-to-refresh
   */
  async testPullToRefresh(page) {
    // Simulate pull gesture from top
    await page.mouse.move(200, 50);
    await page.mouse.down();
    await page.mouse.move(200, 200, { steps: 10 });
    await page.waitForTimeout(500);
    await page.mouse.up();
    
    // Look for refresh indicators
    const refreshIndicators = page.locator(
      '[data-testid="refresh"], .refresh-indicator, ' +
      '.pull-to-refresh, [aria-label*="refresh"]'
    );
    
    if (await refreshIndicators.count() > 0) {
      this.mobileState.responsiveFeatures.add('pull_to_refresh');
    }
  }

  /**
   * Test mobile keyboard behavior
   */
  async testMobileKeyboard(page) {
    await page.goto('/chat');
    await this.waitForPageStability(page);
    
    const textInputs = page.locator('input[type="text"], textarea, [contenteditable]');
    
    if (await textInputs.count() > 0) {
      const input = textInputs.first();
      
      // Focus on input to trigger mobile keyboard
      await this.simulateTouchTap(page, input);
      await page.waitForTimeout(500);
      
      // Type some text
      await this.typeHumanLike(page, input, 'Mobile keyboard test');
      
      // Simulate keyboard dismiss
      await page.keyboard.press('Escape');
      await page.waitForTimeout(500);
      
      this.mobileState.responsiveFeatures.add('mobile_keyboard');
    }
  }

  /**
   * Test mobile UI elements
   */
  async testMobileUIElements(page) {
    // Test bottom navigation
    const bottomNav = page.locator(
      '.bottom-navigation, [data-testid="bottom-nav"], ' +
      '.mobile-nav-bottom, .tab-bar'
    );
    
    if (await bottomNav.count() > 0) {
      this.mobileState.responsiveFeatures.add('bottom_navigation');
    }
    
    // Test floating action buttons
    const fab = page.locator(
      '.fab, .floating-action-button, [data-testid="fab"], ' +
      'button[class*="float"]'
    );
    
    if (await fab.count() > 0) {
      await this.simulateTouchTap(page, fab.first());
      this.mobileState.responsiveFeatures.add('floating_action_button');
    }
    
    // Test mobile-specific modals
    const mobileModals = page.locator(
      '.mobile-modal, .bottom-sheet, [data-testid="bottom-sheet"], ' +
      '.drawer, [role="dialog"][class*="mobile"]'
    );
    
    if (await mobileModals.count() > 0) {
      this.mobileState.responsiveFeatures.add('mobile_modals');
    }
  }

  /**
   * Test accessibility features
   */
  async testAccessibilityFeatures(page) {
    this.logAction('testing_accessibility_features');
    
    // Test screen reader compatibility
    await this.testScreenReaderFeatures(page);
    
    // Test high contrast mode
    await this.testHighContrastMode(page);
    
    // Test font size scaling
    await this.testFontSizeScaling(page);
    
    // Test touch target sizes
    await this.testTouchTargetSizes(page);
  }

  /**
   * Test screen reader features
   */
  async testScreenReaderFeatures(page) {
    // Check for ARIA labels and roles
    const ariaElements = page.locator(
      '[aria-label], [aria-labelledby], [aria-describedby], ' +
      '[role], [aria-expanded], [aria-hidden]'
    );
    
    const ariaCount = await ariaElements.count();
    
    if (ariaCount > 0) {
      this.mobileState.accessibilityFeatures.add('aria_support');
      this.logAction('aria_elements_found', { count: ariaCount });
    }
    
    // Test focus management
    await page.keyboard.press('Tab');
    const focusedElement = page.locator(':focus');
    
    if (await focusedElement.count() > 0) {
      this.mobileState.accessibilityFeatures.add('focus_management');
    }
  }

  /**
   * Test high contrast mode
   */
  async testHighContrastMode(page) {
    // Look for theme toggles or contrast settings
    const themeToggles = page.locator(
      'button:has-text("theme"), button:has-text("Theme"), ' +
      '[data-testid="theme"], .theme-toggle, ' +
      'button[aria-label*="theme"]'
    );
    
    if (await themeToggles.count() > 0) {
      await this.simulateTouchTap(page, themeToggles.first());
      await page.waitForTimeout(500);
      
      this.mobileState.accessibilityFeatures.add('theme_support');
    }
  }

  /**
   * Test font size scaling
   */
  async testFontSizeScaling(page) {
    // Simulate system font size scaling
    await page.addStyleTag({
      content: `
        * { 
          font-size: 150% !important; 
        }
      `
    });
    
    await page.waitForTimeout(1000);
    
    // Check if layout adapts
    const textElements = page.locator('p, span, div, h1, h2, h3');
    if (await textElements.count() > 0) {
      this.mobileState.accessibilityFeatures.add('font_scaling_support');
    }
  }

  /**
   * Test touch target sizes
   */
  async testTouchTargetSizes(page) {
    const touchTargets = page.locator('button, a, [role="button"], input');
    const targetCount = await touchTargets.count();
    let adequateSizeCount = 0;
    
    for (let i = 0; i < Math.min(targetCount, 10); i++) {
      const target = touchTargets.nth(i);
      const box = await target.boundingBox();
      
      if (box && box.width >= 44 && box.height >= 44) {
        adequateSizeCount++;
      }
    }
    
    if (adequateSizeCount > 0) {
      this.mobileState.accessibilityFeatures.add('adequate_touch_targets');
      this.logAction('touch_target_sizes_checked', { 
        adequate: adequateSizeCount, 
        total: Math.min(targetCount, 10) 
      });
    }
  }

  /**
   * Test orientation changes
   */
  async testOrientationChanges(page) {
    this.logAction('testing_orientation_changes');
    
    // Switch to landscape
    const landscapeViewport = {
      phone: { width: 812, height: 375 },
      tablet: { width: 1024, height: 768 }
    };
    
    await page.setViewportSize(landscapeViewport[this.mobileState.deviceType]);
    this.mobileState.orientation = 'landscape';
    
    await page.waitForTimeout(1000);
    
    // Test layout in landscape
    await this.testLayoutAdaptation(page, 'landscape');
    
    // Switch back to portrait
    const portraitViewport = {
      phone: { width: 375, height: 812 },
      tablet: { width: 768, height: 1024 }
    };
    
    await page.setViewportSize(portraitViewport[this.mobileState.deviceType]);
    this.mobileState.orientation = 'portrait';
    
    await page.waitForTimeout(1000);
    
    // Test layout in portrait
    await this.testLayoutAdaptation(page, 'portrait');
    
    this.mobileState.responsiveFeatures.add('orientation_changes');
  }

  /**
   * Test layout adaptation
   */
  async testLayoutAdaptation(page, orientation) {
    // Check if navigation adapts
    const navigation = page.locator('nav, [role="navigation"], .navigation');
    
    if (await navigation.count() > 0) {
      const navBox = await navigation.first().boundingBox();
      if (navBox) {
        this.logAction('layout_adaptation_tested', { 
          orientation, 
          navWidth: navBox.width,
          navHeight: navBox.height 
        });
      }
    }
    
    // Check if content reflows properly
    const contentElements = page.locator('.content, main, [data-testid="content"]');
    
    if (await contentElements.count() > 0) {
      const isOverflowing = await contentElements.first().evaluate(el => {
        return el.scrollWidth > el.clientWidth;
      });
      
      if (!isOverflowing) {
        this.mobileState.responsiveFeatures.add(`responsive_${orientation}`);
      }
    }
  }

  /**
   * Test mobile form interactions
   */
  async testMobileFormInteractions(page) {
    this.logAction('testing_mobile_form_interactions');
    
    await page.goto('/settings');
    await this.waitForPageStability(page);
    
    // Test different input types
    await this.testMobileInputTypes(page);
    
    // Test form validation on mobile
    await this.testMobileFormValidation(page);
    
    // Test mobile-specific input behaviors
    await this.testMobileInputBehaviors(page);
  }

  /**
   * Test mobile input types
   */
  async testMobileInputTypes(page) {
    const inputTypes = [
      'email', 'tel', 'number', 'url', 'search', 'date'
    ];
    
    for (const inputType of inputTypes) {
      const inputs = page.locator(`input[type="${inputType}"]`);
      
      if (await inputs.count() > 0) {
        const input = inputs.first();
        await this.simulateTouchTap(page, input);
        await page.waitForTimeout(300);
        
        // Type appropriate content
        const testValues = {
          email: 'test@example.com',
          tel: '+1234567890',
          number: '123',
          url: 'https://example.com',
          search: 'search term',
          date: '2024-01-01'
        };
        
        await input.fill(testValues[inputType] || 'test');
        await page.waitForTimeout(300);
        
        this.mobileState.touchInteractions.add(`mobile_input_${inputType}`);
      }
    }
  }

  /**
   * Test mobile form validation
   */
  async testMobileFormValidation(page) {
    const forms = page.locator('form');
    
    if (await forms.count() > 0) {
      const form = forms.first();
      const requiredInputs = form.locator('input[required]');
      
      if (await requiredInputs.count() > 0) {
        // Try to submit form without filling required fields
        const submitButton = form.locator('button[type="submit"], input[type="submit"]');
        
        if (await submitButton.count() > 0) {
          await this.simulateTouchTap(page, submitButton.first());
          await page.waitForTimeout(1000);
          
          // Look for validation messages
          const validationMessages = page.locator(
            '.error, [role="alert"], .validation-error, ' +
            'input:invalid + *, [aria-invalid="true"] + *'
          );
          
          if (await validationMessages.count() > 0) {
            this.mobileState.responsiveFeatures.add('mobile_form_validation');
          }
        }
      }
    }
  }

  /**
   * Test mobile input behaviors
   */
  async testMobileInputBehaviors(page) {
    // Test auto-complete
    const inputs = page.locator('input[autocomplete]');
    
    if (await inputs.count() > 0) {
      const input = inputs.first();
      await this.simulateTouchTap(page, input);
      await this.typeHumanLike(page, input, 'test');
      
      // Look for autocomplete suggestions
      const suggestions = page.locator(
        '[role="listbox"], .autocomplete, .suggestions, ' +
        'datalist option'
      );
      
      if (await suggestions.count() > 0) {
        this.mobileState.responsiveFeatures.add('mobile_autocomplete');
      }
    }
  }

  // Touch simulation methods

  /**
   * Simulate touch tap
   */
  async simulateTouchTap(page, element) {
    const box = await element.boundingBox();
    if (box) {
      const x = box.x + box.width * 0.5;
      const y = box.y + box.height * 0.5;
      
      await page.mouse.move(x, y);
      await page.mouse.down();
      await page.waitForTimeout(this.touchPatterns.tap.duration);
      await page.mouse.up();
    }
  }

  /**
   * Simulate long press
   */
  async simulateLongPress(page, element) {
    const box = await element.boundingBox();
    if (box) {
      const x = box.x + box.width * 0.5;
      const y = box.y + box.height * 0.5;
      
      await page.mouse.move(x, y);
      await page.mouse.down();
      await page.waitForTimeout(this.touchPatterns.longPress.duration);
      await page.mouse.up();
    }
  }

  /**
   * Simulate double tap
   */
  async simulateDoubleTap(page, element) {
    await this.simulateTouchTap(page, element);
    await page.waitForTimeout(100);
    await this.simulateTouchTap(page, element);
  }

  /**
   * Simulate vertical scroll
   */
  async simulateVerticalScroll(page, direction, distance) {
    const centerX = page.viewportSize().width / 2;
    const centerY = page.viewportSize().height / 2;
    
    const deltaY = direction === 'down' ? distance : -distance;
    
    await page.mouse.move(centerX, centerY);
    await page.mouse.down();
    await page.mouse.move(centerX, centerY + deltaY, { steps: 10 });
    await page.mouse.up();
  }

  /**
   * Simulate horizontal scroll
   */
  async simulateHorizontalScroll(page, direction, distance) {
    const centerX = page.viewportSize().width / 2;
    const centerY = page.viewportSize().height / 2;
    
    const deltaX = direction === 'right' ? distance : -distance;
    
    await page.mouse.move(centerX, centerY);
    await page.mouse.down();
    await page.mouse.move(centerX + deltaX, centerY, { steps: 10 });
    await page.mouse.up();
  }

  /**
   * Simulate swipe gesture
   */
  async simulateSwipe(page, startPoint, endPoint) {
    await page.mouse.move(startPoint.x, startPoint.y);
    await page.mouse.down();
    await page.mouse.move(endPoint.x, endPoint.y, { steps: 15 });
    await page.mouse.up();
  }

  /**
   * Simulate pinch zoom
   */
  async simulatePinchZoom(page, element, direction) {
    const box = await element.boundingBox();
    if (box) {
      const centerX = box.x + box.width * 0.5;
      const centerY = box.y + box.height * 0.5;
      
      // Simulate two-finger pinch
      const distance = direction === 'in' ? 50 : 100;
      
      // First finger
      await page.mouse.move(centerX - distance/2, centerY);
      await page.mouse.down();
      
      // Move fingers
      if (direction === 'in') {
        await page.mouse.move(centerX - distance, centerY, { steps: 10 });
      } else {
        await page.mouse.move(centerX - distance/4, centerY, { steps: 10 });
      }
      
      await page.mouse.up();
    }
  }

  /**
   * Get mobile testing summary
   */
  getMobileTestingSummary() {
    return {
      agentId: this.id,
      behavior: this.behavior,
      deviceType: this.mobileState.deviceType,
      orientation: this.mobileState.orientation,
      interactions: {
        touchInteractions: Array.from(this.mobileState.touchInteractions),
        gesturePatterns: Array.from(this.mobileState.gesturePatterns),
        responsiveFeatures: Array.from(this.mobileState.responsiveFeatures),
        accessibilityFeatures: Array.from(this.mobileState.accessibilityFeatures)
      },
      mobileScore: this.calculateMobileScore()
    };
  }

  /**
   * Calculate mobile compatibility score
   */
  calculateMobileScore() {
    const totalFeatures = 
      this.mobileState.touchInteractions.size +
      this.mobileState.gesturePatterns.size +
      this.mobileState.responsiveFeatures.size +
      this.mobileState.accessibilityFeatures.size;
    
    const maxFeatures = 25; // Estimated maximum features
    
    return Math.min(100, Math.round((totalFeatures / maxFeatures) * 100));
  }
}

module.exports = MobileAgent;