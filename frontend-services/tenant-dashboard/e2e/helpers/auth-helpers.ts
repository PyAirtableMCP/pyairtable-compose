import { Page, expect } from '@playwright/test'
import { TestUser } from '../fixtures/test-users'

/**
 * Authentication helper functions for E2E tests
 */
export class AuthHelpers {
  
  /**
   * Complete user registration flow
   */
  static async registerUser(page: Page, user: TestUser) {
    await page.goto('/auth/register')
    
    // Wait for registration form to load
    await expect(page.getByRole('heading', { name: /create your account/i })).toBeVisible()
    
    // Fill registration form using placeholder selectors
    await page.getByPlaceholder('Enter your full name').fill(user.name)
    await page.getByPlaceholder('Enter your email').fill(user.email)
    await page.getByPlaceholder('Create a password').fill(user.password)
    await page.getByPlaceholder('Confirm your password').fill(user.password)
    
    // Accept terms checkbox
    await page.getByLabel(/I agree to the Terms of Service and Privacy Policy/i).check()
    
    // Submit registration
    await page.getByRole('button', { name: /create account/i }).click()
    
    // Wait for success or redirect
    await expect(page).toHaveURL(/\/auth\/onboarding/, { timeout: 10000 })
  }

  /**
   * Login user with credentials
   */
  static async loginUser(page: Page, user: TestUser) {
    await page.goto('/auth/login')
    
    // Wait for login form
    await expect(page.getByRole('heading', { name: /welcome back/i })).toBeVisible()
    
    // Fill login form using placeholder selectors
    await page.getByPlaceholder('Enter your email').fill(user.email)
    await page.getByPlaceholder('Enter your password').fill(user.password)
    
    // Submit login
    await page.getByRole('button', { name: /sign in/i }).click()
    
    // Wait for successful login redirect
    await expect(page).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 10000 })
    
    // Verify user is logged in by checking for welcome message or dashboard elements
    try {
      await expect(page.getByText(/Welcome back/i).first()).toBeVisible({ timeout: 5000 })
    } catch {
      // Fallback: check if we're on dashboard/chat page and have session
      const currentUrl = page.url()
      const isOnAuthenticatedPage = currentUrl.includes('/dashboard') || currentUrl.includes('/chat')
      if (!isOnAuthenticatedPage) {
        throw new Error('User is not on an authenticated page')
      }
    }
  }

  /**
   * Login user and navigate to specific page
   */
  static async loginAndNavigate(page: Page, user: TestUser, targetPath: string) {
    await this.loginUser(page, user)
    await page.goto(targetPath)
    await page.waitForLoadState('networkidle')
  }

  /**
   * Logout user
   */
  static async logoutUser(page: Page) {
    // Look for logout button in various locations (header, dropdown menu, etc.)
    const logoutSelectors = [
      'button:has-text("Logout")',
      'button:has-text("Sign out")',
      '[data-testid="logout-button"]',
      '.logout-button'
    ]

    let loggedOut = false
    for (const selector of logoutSelectors) {
      try {
        const button = page.locator(selector).first()
        if (await button.isVisible({ timeout: 2000 })) {
          await button.click()
          loggedOut = true
          break
        }
      } catch (error) {
        // Try next selector
      }
    }

    // If no logout button found, try dropdown menu
    if (!loggedOut) {
      try {
        // Click user menu/avatar
        const userMenu = page.locator('[data-testid="user-menu"], .user-avatar, button:has([role="img"])').first()
        if (await userMenu.isVisible({ timeout: 2000 })) {
          await userMenu.click()
          await page.getByRole('menuitem', { name: /logout|sign out/i }).click()
          loggedOut = true
        }
      } catch (error) {
        // Fallback: navigate to logout endpoint
        await page.goto('/auth/logout')
        loggedOut = true
      }
    }

    if (loggedOut) {
      // Wait for redirect to login page
      await expect(page).toHaveURL(/\/auth\/login/, { timeout: 10000 })
    }
  }

  /**
   * Verify user is authenticated
   */
  static async verifyAuthenticated(page: Page) {
    // Check for authenticated state indicators - more flexible approach
    let isAuthenticated = false
    
    // Try to find welcome message first
    try {
      if (await page.getByText(/Welcome back/i).first().isVisible({ timeout: 3000 })) {
        isAuthenticated = true
      }
    } catch (error) {
      // Continue with other checks
    }
    
    // Check for chat interface elements if on chat page
    if (!isAuthenticated) {
      const chatIndicators = [
        page.getByText(/PyAirtable Assistant/i).first(),
        page.getByText(/Ask anything about your data/i).first(),
        page.getByPlaceholder(/Ask anything about your data/i).first()
      ]
      
      for (const indicator of chatIndicators) {
        try {
          if (await indicator.isVisible({ timeout: 2000 })) {
            isAuthenticated = true
            break
          }
        } catch (error) {
          // Continue checking
        }
      }
    }

    // Alternative: Check if we're on an authenticated page (not login) and verify session
    if (!isAuthenticated) {
      const currentUrl = page.url()
      const isNotOnLoginPage = !currentUrl.includes('/auth/login')
      
      try {
        const sessionResponse = await page.request.get('/api/auth/session')
        const sessionData = await sessionResponse.json()
        const hasValidSession = sessionData?.user?.email
        isAuthenticated = isNotOnLoginPage && !!hasValidSession
      } catch (error) {
        // Session check failed, not authenticated
        isAuthenticated = false
      }
    }

    expect(isAuthenticated, 'User should be authenticated').toBe(true)
  }

  /**
   * Verify user is not authenticated
   */
  static async verifyNotAuthenticated(page: Page) {
    // Should be on login page or redirected to login
    try {
      await expect(page).toHaveURL(/\/auth\/login/, { timeout: 5000 })
    } catch (error) {
      // If not on login page, check for login form
      await expect(page.getByRole('heading', { name: /sign in|login/i })).toBeVisible()
    }
  }

  /**
   * Handle session expiry scenario
   */
  static async handleSessionExpiry(page: Page) {
    // Clear all cookies and storage to simulate session expiry
    await page.context().clearCookies()
    await page.evaluate(() => {
      localStorage.clear()
      sessionStorage.clear()
    })
    
    // Reload page to trigger auth check
    await page.reload()
    
    // Should redirect to login
    await this.verifyNotAuthenticated(page)
  }

  /**
   * Wait for page to be fully loaded and authenticated
   */
  static async waitForAuthenticatedPage(page: Page, timeout: number = 10000) {
    await page.waitForLoadState('networkidle')
    
    // Wait for authentication to complete
    await page.waitForFunction(() => {
      // Check if page has loaded and user is authenticated
      const hasUserData = document.querySelector('[data-testid="user-menu"], .user-avatar') !== null
      const hasMainContent = document.querySelector('main, [role="main"], .main-content') !== null
      const notOnAuthPage = !window.location.pathname.includes('/auth/')
      
      return hasUserData || (hasMainContent && notOnAuthPage)
    }, { timeout })
  }

  /**
   * Mock authentication state for testing
   */
  static async mockAuthState(page: Page, user: TestUser) {
    // Mock session storage/cookies for authenticated state
    await page.addInitScript((userData) => {
      // Mock session data
      window.localStorage.setItem('next-auth.session-token', 'mock-session-token')
      window.localStorage.setItem('user-data', JSON.stringify(userData))
    }, user)

    // Mock API responses for session checks
    await page.route('**/api/auth/session', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          user: {
            id: 'mock-user-id',
            email: user.email,
            name: user.name,
          },
          expires: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
        })
      })
    })
  }
}