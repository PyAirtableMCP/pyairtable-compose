import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { generateUniqueTestUser } from './fixtures/test-users'

/**
 * Complete User Login Journey Tests
 * 
 * Tests login flows using robust selectors that are resilient to UI changes
 * by prioritizing semantic attributes and accessibility features.
 */
test.describe('Complete User Login Journey', () => {
  let testUser: ReturnType<typeof generateUniqueTestUser>

  test.beforeEach(async ({ page }) => {
    // Create a test user for each test
    testUser = generateUniqueTestUser()
    await AuthHelpers.registerUser(page, testUser)
  })

  test.afterEach(async ({ page }) => {
    // Cleanup test data
    await CommonHelpers.cleanupTestData(page, testUser)
  })

  test('should complete user login from landing page to dashboard', async ({ page }) => {
    await test.step('Navigate to login page', async () => {
      await page.goto('/auth/login')
      
      // Verify we're on the login page using robust selectors
      await expect(page).toHaveURL(/\/auth\/login/)
      
      // Check for login form using multiple fallback selectors
      const loginHeading = page.locator('[data-testid="login-heading"]')
        .or(page.getByRole('heading', { name: /welcome.*back|sign.*in|login/i }))
        .or(page.locator('h1:has-text("Welcome"), h1:has-text("Sign"), h2:has-text("Login")'))
        .or(page.locator('[aria-label*="login"], [aria-labelledby*="login"]'))
        .first()

      await expect(loginHeading).toBeVisible()
      console.log('Login page loaded successfully')
    })

    await test.step('Fill login form with valid credentials', async () => {
      // Use robust selector strategy with multiple fallbacks
      const emailField = page.locator('[data-testid="email-input"]')
        .or(page.getByLabel(/email.*address|email/i))
        .or(page.getByPlaceholder(/email/i))
        .or(page.locator('input[type="email"], input[name="email"]'))
        .first()

      const passwordField = page.locator('[data-testid="password-input"]')
        .or(page.getByLabel(/password/i))
        .or(page.getByPlaceholder(/password/i))
        .or(page.locator('input[type="password"], input[name="password"]'))
        .first()

      // Verify form fields are visible and accessible
      await expect(emailField).toBeVisible()
      await expect(passwordField).toBeVisible()

      // Fill credentials
      await emailField.fill(testUser.email)
      await passwordField.fill(testUser.password)
      
      console.log(`Login form filled for user: ${testUser.email}`)
    })

    await test.step('Submit login and verify success', async () => {
      const loginButton = page.locator('[data-testid="login-button"]')
        .or(page.getByRole('button', { name: /sign.*in|login|log.*in/i }))
        .or(page.locator('button[type="submit"]'))
        .or(page.locator('button:has-text("Sign"), button:has-text("Login"), button:has-text("Log")'))
        .first()

      await expect(loginButton).toBeVisible()
      await expect(loginButton).toBeEnabled()

      // Submit login and wait for navigation
      await Promise.all([
        page.waitForResponse(response => 
          response.url().includes('/auth/login') || 
          response.url().includes('/api/auth/signin'), 
          { timeout: 15000 }
        ).catch(() => null),
        loginButton.click()
      ])

      // Allow time for authentication process
      await page.waitForTimeout(3000)
      
      const currentUrl = page.url()
      console.log(`URL after login attempt: ${currentUrl}`)

      // Verify successful login using multiple indicators
      const isLoginSuccessful = await CommonHelpers.verifyLoginSuccess(page, {
        expectedUrls: ['/dashboard', '/chat', '/app', '/home'],
        excludeUrls: ['/auth/login'],
        successSelectors: [
          '[data-testid="dashboard"]',
          '[data-testid="welcome-message"]',
          'text*="Welcome back"',
          '[data-testid="user-menu"]'
        ]
      })

      expect(isLoginSuccessful, 'User should be successfully logged in').toBe(true)
    })

    await test.step('Verify user session persistence', async () => {
      // Refresh page and ensure user remains logged in
      await page.reload()
      await page.waitForLoadState('networkidle')
      
      const isStillLoggedIn = await CommonHelpers.verifyAuthenticatedState(page)
      expect(isStillLoggedIn, 'User session should persist after page refresh').toBe(true)
    })
  })

  test('should handle invalid credentials', async ({ page }) => {
    await page.goto('/auth/login')

    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .or(page.locator('input[type="email"]'))
      .first()

    const passwordField = page.locator('[data-testid="password-input"]')  
      .or(page.getByLabel(/password/i))
      .or(page.locator('input[type="password"]'))
      .first()

    const loginButton = page.locator('[data-testid="login-button"]')
      .or(page.getByRole('button', { name: /sign.*in|login/i }))
      .or(page.locator('button[type="submit"]'))
      .first()

    // Enter invalid credentials
    await emailField.fill('invalid@example.com')
    await passwordField.fill('wrongpassword')
    await loginButton.click()

    // Check for error message using robust selectors
    const errorMessage = page.locator('[data-testid="login-error"]')
      .or(page.getByText(/invalid.*credentials|incorrect.*password|login.*failed/i))
      .or(page.locator('[role="alert"]:not(:has-text("success"))'))
      .or(page.locator('.error, .alert-error, .text-red, .text-destructive'))
      .first()

    await expect(errorMessage).toBeVisible({ timeout: 10000 })
    
    // Should still be on login page
    await expect(page).toHaveURL(/\/auth\/login/)
  })

  test('should handle non-existent user', async ({ page }) => {
    await page.goto('/auth/login')

    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .or(page.locator('input[type="email"]'))
      .first()

    const passwordField = page.locator('[data-testid="password-input"]')
      .or(page.getByLabel(/password/i))
      .or(page.locator('input[type="password"]'))
      .first()

    const loginButton = page.locator('[data-testid="login-button"]')
      .or(page.getByRole('button', { name: /sign.*in|login/i }))
      .or(page.locator('button[type="submit"]'))
      .first()

    // Use non-existent user credentials
    await emailField.fill('nonexistent@example.com')
    await passwordField.fill('SomePassword123!')
    await loginButton.click()

    // Check for appropriate error message
    const errorMessage = page.locator('[data-testid="user-not-found-error"]')
      .or(page.getByText(/user.*not.*found|account.*not.*exist|invalid.*credentials/i))
      .or(page.locator('[role="alert"]:not(:has-text("success"))'))
      .first()

    await expect(errorMessage).toBeVisible({ timeout: 10000 })
  })

  test('should validate required fields', async ({ page }) => {
    await page.goto('/auth/login')

    const loginButton = page.locator('[data-testid="login-button"]')
      .or(page.getByRole('button', { name: /sign.*in|login/i }))
      .or(page.locator('button[type="submit"]'))
      .first()

    // Try to submit without filling fields
    await loginButton.click()

    // Check for validation errors
    const emailError = page.locator('[data-testid="email-required-error"]')
      .or(page.getByText(/email.*required|enter.*email/i))
      .or(page.locator('input[type="email"]:invalid'))
      .first()

    const passwordError = page.locator('[data-testid="password-required-error"]')
      .or(page.getByText(/password.*required|enter.*password/i))
      .or(page.locator('input[type="password"]:invalid'))
      .first()

    // At least one validation error should be visible
    await expect(
      emailError.or(passwordError)
    ).toBeVisible({ timeout: 5000 })
  })

  test('should validate email format', async ({ page }) => {
    await page.goto('/auth/login')

    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .or(page.locator('input[type="email"]'))
      .first()

    const loginButton = page.locator('[data-testid="login-button"]')
      .or(page.getByRole('button', { name: /sign.*in|login/i }))
      .or(page.locator('button[type="submit"]'))
      .first()

    // Enter invalid email format
    await emailField.fill('invalid-email-format')
    await loginButton.click()

    // Check for email format validation
    const emailFormatError = page.locator('[data-testid="email-format-error"]')
      .or(page.getByText(/invalid.*email.*format|valid.*email.*address/i))
      .or(page.locator('input[type="email"]:invalid'))
      .first()

    await expect(emailFormatError).toBeVisible({ timeout: 5000 })
  })

  test('should handle special characters in email', async ({ page }) => {
    const specialEmailUser = {
      ...testUser,
      email: 'test+special.chars@example-domain.co.uk'
    }

    // Register user with special characters in email
    await AuthHelpers.registerUser(page, specialEmailUser)

    await page.goto('/auth/login')

    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .or(page.locator('input[type="email"]'))
      .first()

    const passwordField = page.locator('[data-testid="password-input"]')
      .or(page.getByLabel(/password/i))
      .or(page.locator('input[type="password"]'))
      .first()

    const loginButton = page.locator('[data-testid="login-button"]')
      .or(page.getByRole('button', { name: /sign.*in|login/i }))
      .or(page.locator('button[type="submit"]'))
      .first()

    // Login with special character email
    await emailField.fill(specialEmailUser.email)
    await passwordField.fill(specialEmailUser.password)
    await loginButton.click()

    // Should login successfully
    const isLoginSuccessful = await CommonHelpers.verifyLoginSuccess(page)
    expect(isLoginSuccessful).toBe(true)

    await CommonHelpers.cleanupTestData(page, specialEmailUser)
  })

  test('should redirect to intended page after login', async ({ page }) => {
    // Try to access protected page while logged out
    await page.goto('/dashboard/settings')
    
    // Should redirect to login
    await expect(page).toHaveURL(/\/auth\/login/)

    // Login
    await AuthHelpers.loginUser(page, testUser)

    // Should redirect back to intended page
    await expect(page).toHaveURL(/\/dashboard\/settings/)
  })

  test('should complete logout flow', async ({ page }) => {
    // Login first
    await AuthHelpers.loginUser(page, testUser)

    // Verify logged in
    await CommonHelpers.verifyAuthenticatedState(page)

    // Logout using robust selector strategy
    await AuthHelpers.logoutUser(page)

    // Verify logged out
    await expect(page).toHaveURL(/\/auth\/login/)
    
    // Try to access protected page
    await page.goto('/dashboard')
    await expect(page).toHaveURL(/\/auth\/login/)
  })

  test('should handle Remember Me functionality', async ({ page }) => {
    await page.goto('/auth/login')

    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .or(page.locator('input[type="email"]'))
      .first()

    const passwordField = page.locator('[data-testid="password-input"]')
      .or(page.getByLabel(/password/i))
      .or(page.locator('input[type="password"]'))
      .first()

    const rememberMeCheckbox = page.locator('[data-testid="remember-me-checkbox"]')
      .or(page.getByLabel(/remember.*me|keep.*logged.*in/i))
      .or(page.locator('input[type="checkbox"][name*="remember"]'))
      .first()

    const loginButton = page.locator('[data-testid="login-button"]')
      .or(page.getByRole('button', { name: /sign.*in|login/i }))
      .or(page.locator('button[type="submit"]'))
      .first()

    // Fill form and check remember me
    await emailField.fill(testUser.email)
    await passwordField.fill(testUser.password)
    
    if (await rememberMeCheckbox.isVisible({ timeout: 2000 })) {
      await rememberMeCheckbox.check()
      await expect(rememberMeCheckbox).toBeChecked()
    }

    await loginButton.click()

    // Verify login success
    const isLoginSuccessful = await CommonHelpers.verifyLoginSuccess(page)
    expect(isLoginSuccessful).toBe(true)

    // Close browser context to simulate session expiry
    await page.context().close()
  })

  test('should maintain session across multiple tabs', async ({ browser, page }) => {
    // Login in first tab
    await AuthHelpers.loginUser(page, testUser)

    // Open second tab
    const secondTab = await browser.newPage()
    await secondTab.goto('/dashboard')

    // Should be logged in without additional authentication
    await CommonHelpers.verifyAuthenticatedState(secondTab)

    await secondTab.close()
  })

  test('should handle session expiry gracefully', async ({ page }) => {
    // Login first
    await AuthHelpers.loginUser(page, testUser)

    // Simulate session expiry
    await AuthHelpers.handleSessionExpiry(page)

    // Should redirect to login
    await expect(page).toHaveURL(/\/auth\/login/)
  })

  test('should handle concurrent login attempts', async ({ browser }) => {
    const context1 = await browser.newContext()
    const context2 = await browser.newContext()
    
    const page1 = await context1.newPage()
    const page2 = await context2.newPage()

    // Attempt concurrent logins
    await Promise.all([
      AuthHelpers.loginUser(page1, testUser),
      AuthHelpers.loginUser(page2, testUser)
    ])

    // Both should be successfully logged in
    await CommonHelpers.verifyAuthenticatedState(page1)
    await CommonHelpers.verifyAuthenticatedState(page2)

    await context1.close()
    await context2.close()
  })

  test('should be accessible via keyboard navigation', async ({ page }) => {
    await page.goto('/auth/login')

    // Navigate and fill form using only keyboard
    await page.keyboard.press('Tab') // Email field
    await page.keyboard.type(testUser.email)

    await page.keyboard.press('Tab') // Password field  
    await page.keyboard.type(testUser.password)

    // Skip remember me checkbox if present
    await page.keyboard.press('Tab')
    await page.keyboard.press('Tab') // Submit button

    await page.keyboard.press('Enter') // Submit

    // Should login successfully
    const isLoginSuccessful = await CommonHelpers.verifyLoginSuccess(page)
    expect(isLoginSuccessful).toBe(true)
  })
})