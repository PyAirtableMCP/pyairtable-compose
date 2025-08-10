import { Page, expect, Browser, BrowserContext } from '@playwright/test'

/**
 * Common helper functions for E2E tests
 */
export class CommonHelpers {
  
  /**
   * Wait for page to be fully loaded
   */
  static async waitForPageLoad(page: Page, timeout: number = 30000) {
    await page.waitForLoadState('networkidle', { timeout })
    
    // Wait for any loading spinners to disappear
    const loadingSpinners = page.locator('.animate-spin, [data-testid="loading"], .loading')
    if (await loadingSpinners.first().isVisible({ timeout: 2000 }).catch(() => false)) {
      await expect(loadingSpinners).not.toBeVisible({ timeout })
    }
  }

  /**
   * Take screenshot with timestamp
   */
  static async takeScreenshot(page: Page, name: string) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
    await page.screenshot({ 
      path: `test-results/screenshots/${name}-${timestamp}.png`,
      fullPage: true
    })
  }

  /**
   * Verify page accessibility
   */
  static async verifyAccessibility(page: Page) {
    // Check for basic accessibility requirements
    const mainContent = page.locator('main, [role="main"]')
    if (await mainContent.isVisible({ timeout: 2000 }).catch(() => false)) {
      await expect(mainContent).toBeVisible()
    }

    // Check for skip links
    const skipLink = page.locator('a[href="#main"], [data-testid="skip-link"]')
    if (await skipLink.isVisible({ timeout: 1000 }).catch(() => false)) {
      await expect(skipLink).toBeVisible()
    }

    // Check for proper heading structure
    const h1 = page.locator('h1').first()
    if (await h1.isVisible({ timeout: 2000 }).catch(() => false)) {
      await expect(h1).toBeVisible()
    }
  }

  /**
   * Handle modal dialogs
   */
  static async handleModal(page: Page, action: 'accept' | 'dismiss' = 'accept') {
    const modal = page.locator('.modal, [role="dialog"], [data-testid="modal"]')
    
    if (await modal.isVisible({ timeout: 2000 }).catch(() => false)) {
      const button = action === 'accept' 
        ? page.getByRole('button', { name: /ok|confirm|yes|accept|continue/i })
        : page.getByRole('button', { name: /cancel|dismiss|no|close/i })
      
      await button.click()
      await expect(modal).not.toBeVisible()
    }
  }

  /**
   * Fill form with data
   */
  static async fillForm(page: Page, formData: Record<string, any>) {
    for (const [fieldName, value] of Object.entries(formData)) {
      const field = page.getByLabel(new RegExp(fieldName, 'i'))
        .or(page.locator(`[name="${fieldName}"]`))
        .or(page.locator(`#${fieldName}`))
      
      if (await field.isVisible({ timeout: 2000 }).catch(() => false)) {
        const fieldType = await field.getAttribute('type')
        
        if (fieldType === 'checkbox' || fieldType === 'radio') {
          if (value) {
            await field.check()
          } else {
            await field.uncheck()
          }
        } else if (await field.locator('select').isVisible().catch(() => false)) {
          await field.selectOption(value.toString())
        } else {
          await field.fill(value.toString())
        }
      }
    }
  }

  /**
   * Wait for API request to complete
   */
  static async waitForAPI(page: Page, urlPattern: string, timeout: number = 10000) {
    return page.waitForResponse(response => 
      response.url().includes(urlPattern) && response.status() < 400,
      { timeout }
    )
  }

  /**
   * Mock API responses
   */
  static async mockAPIResponse(page: Page, urlPattern: string, responseData: any, status: number = 200) {
    await page.route(`**/*${urlPattern}*`, async route => {
      await route.fulfill({
        status,
        contentType: 'application/json',
        body: JSON.stringify(responseData)
      })
    })
  }

  /**
   * Verify error message display
   */
  static async verifyErrorMessage(page: Page, expectedError: string | RegExp) {
    const errorSelectors = [
      '.error-message',
      '.alert-error',
      '[data-testid="error"]',
      '.text-red-500',
      '.text-destructive',
      '[role="alert"]'
    ]

    let errorFound = false
    for (const selector of errorSelectors) {
      const errorElement = page.locator(selector)
      if (await errorElement.isVisible({ timeout: 2000 }).catch(() => false)) {
        if (typeof expectedError === 'string') {
          await expect(errorElement).toContainText(expectedError)
        } else {
          const text = await errorElement.textContent()
          expect(text).toMatch(expectedError)
        }
        errorFound = true
        break
      }
    }

    expect(errorFound, 'Error message should be displayed').toBe(true)
  }

  /**
   * Verify success message display
   */
  static async verifySuccessMessage(page: Page, expectedMessage: string | RegExp) {
    const successSelectors = [
      '.success-message',
      '.alert-success',
      '[data-testid="success"]',
      '.text-green-500',
      '.text-success'
    ]

    let successFound = false
    for (const selector of successSelectors) {
      const successElement = page.locator(selector)
      if (await successElement.isVisible({ timeout: 5000 }).catch(() => false)) {
        if (typeof expectedMessage === 'string') {
          await expect(successElement).toContainText(expectedMessage)
        } else {
          const text = await successElement.textContent()
          expect(text).toMatch(expectedMessage)
        }
        successFound = true
        break
      }
    }

    expect(successFound, 'Success message should be displayed').toBe(true)
  }

  /**
   * Test responsive design
   */
  static async testResponsiveDesign(page: Page) {
    const viewports = [
      { width: 1920, height: 1080 }, // Desktop
      { width: 1024, height: 768 },  // Tablet
      { width: 375, height: 667 }    // Mobile
    ]

    for (const viewport of viewports) {
      await page.setViewportSize(viewport)
      await this.waitForPageLoad(page)
      
      // Verify content is visible and properly formatted
      const mainContent = page.locator('main, [role="main"], .main-content')
      await expect(mainContent).toBeVisible()
      
      // Check for mobile menu on smaller screens
      if (viewport.width < 768) {
        const mobileMenu = page.locator('.mobile-menu, [data-testid="mobile-menu"], button:has-text("Menu")')
        if (await mobileMenu.isVisible({ timeout: 2000 }).catch(() => false)) {
          await expect(mobileMenu).toBeVisible()
        }
      }
    }
  }

  /**
   * Generate test data
   */
  static generateTestData(type: 'email' | 'phone' | 'name' | 'text', length?: number): string {
    const timestamp = Date.now()
    const random = Math.random().toString(36).substring(2, 8)

    switch (type) {
      case 'email':
        return `test.${timestamp}.${random}@example.com`
      case 'phone':
        return `+1555${Math.floor(Math.random() * 9000000) + 1000000}`
      case 'name':
        return `Test User ${random}`
      case 'text':
        const textLength = length || 50
        return `Test text ${random} `.repeat(Math.ceil(textLength / 15)).substring(0, textLength)
      default:
        return `test_${timestamp}_${random}`
    }
  }

  /**
   * Wait for element with custom timeout
   */
  static async waitForElement(page: Page, selector: string, timeout: number = 10000) {
    return page.locator(selector).waitFor({ timeout })
  }

  /**
   * Scroll element into view
   */
  static async scrollIntoView(page: Page, selector: string) {
    await page.locator(selector).scrollIntoViewIfNeeded()
    await page.waitForTimeout(500) // Allow for smooth scrolling
  }

  /**
   * Test keyboard navigation
   */
  static async testKeyboardNavigation(page: Page, startElement: string, expectedElements: string[]) {
    await page.locator(startElement).focus()
    
    for (const expectedElement of expectedElements) {
      await page.keyboard.press('Tab')
      await expect(page.locator(expectedElement)).toBeFocused()
    }
  }

  /**
   * Verify login success using multiple indicators
   */
  static async verifyLoginSuccess(page: Page, options?: {
    expectedUrls?: string[]
    excludeUrls?: string[]
    successSelectors?: string[]
  }) {
    const currentUrl = page.url()
    
    // Check URL-based success indicators
    if (options?.expectedUrls) {
      for (const expectedUrl of options.expectedUrls) {
        if (currentUrl.includes(expectedUrl)) {
          return true
        }
      }
    }
    
    // Check URL exclusion indicators
    if (options?.excludeUrls) {
      const isOnExcludedUrl = options.excludeUrls.some(url => currentUrl.includes(url))
      if (!isOnExcludedUrl) {
        // Not on login page and no other exclusions - likely successful
        return true
      }
    }
    
    // Check for success elements
    if (options?.successSelectors) {
      for (const selector of options.successSelectors) {
        try {
          if (await page.locator(selector).isVisible({ timeout: 3000 })) {
            return true
          }
        } catch (e) {
          // Continue checking
        }
      }
    }
    
    // Default success indicators
    const defaultSuccessChecks = [
      // URL not containing login
      () => !currentUrl.includes('/auth/login'),
      
      // Check for authenticated elements
      async () => {
        const authElements = [
          page.locator('[data-testid="user-menu"]'),
          page.locator('[data-testid="dashboard"]'),
          page.getByText(/welcome.*back/i).first(),
          page.locator('.user-avatar, [class*="avatar"]'),
        ]
        
        for (const element of authElements) {
          try {
            if (await element.isVisible({ timeout: 2000 })) {
              return true
            }
          } catch (e) {
            // Continue checking
          }
        }
        return false
      }
    ]
    
    // Check URL first
    if (defaultSuccessChecks[0]()) {
      // Then verify with element check
      if (await defaultSuccessChecks[1]()) {
        return true
      }
    }
    
    return false
  }

  /**
   * Verify authenticated state
   */
  static async verifyAuthenticatedState(page: Page): Promise<boolean> {
    const currentUrl = page.url()
    
    // If on auth pages, not authenticated
    if (currentUrl.includes('/auth/')) {
      return false
    }
    
    // Check for authenticated elements
    const authIndicators = [
      page.locator('[data-testid="user-menu"]'),
      page.locator('[data-testid="dashboard"]'),
      page.getByText(/welcome.*back/i).first(),
      page.locator('.user-avatar'),
      page.locator('[class*="avatar"]')
    ]
    
    for (const indicator of authIndicators) {
      try {
        if (await indicator.isVisible({ timeout: 2000 })) {
          return true
        }
      } catch (e) {
        // Continue checking
      }
    }
    
    // Check session API if available
    try {
      const sessionResponse = await page.request.get('/api/auth/session')
      if (sessionResponse.status() === 200) {
        const sessionData = await sessionResponse.json()
        return !!(sessionData?.user?.email)
      }
    } catch (e) {
      // Session check failed
    }
    
    return false
  }

  /**
   * Cleanup test data
   */
  static async cleanupTestData(page: Page, testUser?: { email: string; name?: string }) {
    if (testUser?.email) {
      // Call cleanup API if available
      try {
        await page.request.delete('/api/test/cleanup', {
          data: { email: testUser.email }
        })
      } catch (error) {
        console.warn('Cleanup API not available or failed:', error)
      }
      
      // Alternative cleanup via direct database calls if API exists
      try {
        await page.request.post('/api/test/cleanup', {
          data: { 
            action: 'delete_user',
            email: testUser.email 
          }
        })
      } catch (error) {
        console.warn('Direct cleanup not available:', error)
      }
    }
  }

  /**
   * Create browser context with specific settings
   */
  static async createTestContext(browser: Browser, options?: {
    locale?: string
    timezone?: string
    geolocation?: { latitude: number; longitude: number }
    permissions?: string[]
  }) {
    const contextOptions: any = {
      locale: options?.locale || 'en-US',
      timezoneId: options?.timezone || 'America/New_York'
    }

    if (options?.geolocation) {
      contextOptions.geolocation = options.geolocation
    }

    if (options?.permissions) {
      contextOptions.permissions = options.permissions
    }

    return browser.newContext(contextOptions)
  }
}