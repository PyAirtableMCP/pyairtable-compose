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
    await expect(page.getByRole('heading', { name: /create account|sign up|register/i })).toBeVisible()
    
    // Fill registration form
    await page.getByLabel(/email/i).fill(user.email)
    await page.getByLabel(/password/i).fill(user.password)
    await page.getByLabel(/confirm password|repeat password/i).fill(user.password)
    await page.getByLabel(/name|full name/i).fill(user.name)
    
    // Accept terms if checkbox exists
    const termsCheckbox = page.getByLabel(/terms|privacy|agree/i)
    if (await termsCheckbox.isVisible()) {
      await termsCheckbox.check()
    }
    
    // Submit registration
    await page.getByRole('button', { name: /sign up|register|create account/i }).click()
    
    // Wait for success or redirect
    await expect(page).toHaveURL(/\/(dashboard|onboarding|verify-email)/, { timeout: 10000 })
  }

  /**
   * Login user with credentials
   */
  static async loginUser(page: Page, user: TestUser) {
    await page.goto('/auth/login')
    
    // Wait for login form
    await expect(page.getByRole('heading', { name: /sign in|login/i })).toBeVisible()
    
    // Fill login form
    await page.getByLabel(/email/i).fill(user.email)
    await page.getByLabel(/password/i).fill(user.password)
    
    // Submit login
    await page.getByRole('button', { name: /sign in|login/i }).click()
    
    // Wait for successful login redirect
    await expect(page).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 10000 })
    
    // Verify user is logged in by checking for user-specific elements
    await expect(page.getByText(/welcome|dashboard|logout/i)).toBeVisible({ timeout: 10000 })
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
    // Check for authenticated state indicators
    const authIndicators = [
      page.getByText(/welcome/i),
      page.getByText(/dashboard/i),
      page.getByRole('button', { name: /logout/i }),
      page.locator('[data-testid="user-menu"]')
    ]

    let isAuthenticated = false
    for (const indicator of authIndicators) {
      try {
        if (await indicator.isVisible({ timeout: 2000 })) {
          isAuthenticated = true
          break
        }
      } catch (error) {
        // Continue checking
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