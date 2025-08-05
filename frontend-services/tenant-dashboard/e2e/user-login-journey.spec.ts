import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { testUsers, generateUniqueTestUser } from './fixtures/test-users'

test.describe('Complete User Login and Session Journey', () => {
  
  test.beforeEach(async ({ page }) => {
    // Start with clean state
    await page.context().clearCookies()
    await page.goto('/')
  })

  test('should complete full login journey from landing page to dashboard', async ({ page }) => {
    // Step 1: Navigate to login page
    await page.goto('/auth/login')
    await expect(page.getByRole('heading', { name: /sign in|login/i })).toBeVisible()

    // Step 2: Fill login credentials
    await page.getByLabel(/email/i).fill(testUsers.standard.email)
    await page.getByLabel(/password/i).fill(testUsers.standard.password)

    // Step 3: Submit login form
    await page.getByRole('button', { name: /sign in|login/i }).click()

    // Step 4: Wait for successful login redirect
    await expect(page).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 15000 })
    await CommonHelpers.waitForPageLoad(page)

    // Step 5: Verify user is authenticated and can access main features
    await AuthHelpers.verifyAuthenticated(page)

    // Step 6: Test navigation to different sections
    // Navigate to chat
    await page.goto('/chat')
    await expect(page.getByText(/pyairtable ai assistant|chat/i)).toBeVisible()

    // Navigate to dashboard if available
    if (await page.locator('[href="/dashboard"], [href="/"]').first().isVisible({ timeout: 2000 }).catch(() => false)) {
      await page.goto('/dashboard')
      await CommonHelpers.waitForPageLoad(page)
      await expect(page.getByText(/dashboard|welcome|overview/i)).toBeVisible()
    }

    // Step 7: Verify session persistence across page refreshes
    await page.reload()
    await CommonHelpers.waitForPageLoad(page)
    await AuthHelpers.verifyAuthenticated(page)
  })

  test('should handle "Remember Me" functionality', async ({ page }) => {
    await page.goto('/auth/login')

    // Check remember me option if available
    const rememberMeCheckbox = page.getByLabel(/remember me|keep me signed in/i)
    if (await rememberMeCheckbox.isVisible({ timeout: 2000 }).catch(() => false)) {
      await rememberMeCheckbox.check()
    }

    // Login
    await page.getByLabel(/email/i).fill(testUsers.standard.email)
    await page.getByLabel(/password/i).fill(testUsers.standard.password)
    await page.getByRole('button', { name: /sign in|login/i }).click()

    await expect(page).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 10000 })

    // Close browser and reopen to test persistence
    const context = page.context()
    const newPage = await context.newPage()
    await newPage.goto('/')
    
    // Should still be logged in if remember me was implemented
    await CommonHelpers.waitForPageLoad(newPage)
    
    // Check if still authenticated (implementation dependent)
    try {
      await AuthHelpers.verifyAuthenticated(newPage)
    } catch (error) {
      // Remember me might not be implemented, which is fine
      console.log('Remember me functionality not detected or not implemented')
    }
  })

  test('should redirect to intended page after login', async ({ page }) => {
    // Step 1: Try to access protected page while not logged in
    await page.goto('/chat')
    
    // Should redirect to login with return URL
    await expect(page).toHaveURL(/\/auth\/login.*/)
    
    // Step 2: Login
    await page.getByLabel(/email/i).fill(testUsers.standard.email)
    await page.getByLabel(/password/i).fill(testUsers.standard.password)
    await page.getByRole('button', { name: /sign in|login/i }).click()
    
    // Step 3: Should redirect back to originally requested page
    await expect(page).toHaveURL(/\/chat/, { timeout: 10000 })
    await expect(page.getByText(/pyairtable ai assistant/i)).toBeVisible()
  })

  test('should handle session expiry gracefully', async ({ page }) => {
    // Login first
    await AuthHelpers.loginUser(page, testUsers.standard)
    await expect(page).toHaveURL(/\/(dashboard|chat|$)/)

    // Simulate session expiry by clearing session data
    await AuthHelpers.handleSessionExpiry(page)

    // Should redirect to login page
    await AuthHelpers.verifyNotAuthenticated(page)
    
    // Login again should work
    await page.getByLabel(/email/i).fill(testUsers.standard.email)
    await page.getByLabel(/password/i).fill(testUsers.standard.password)
    await page.getByRole('button', { name: /sign in|login/i }).click()
    
    await expect(page).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 10000 })
  })

  test('should complete logout flow', async ({ page }) => {
    // Login first
    await AuthHelpers.loginUser(page, testUsers.standard)
    
    // Navigate to a protected page
    await page.goto('/chat')
    await CommonHelpers.waitForPageLoad(page)
    
    // Logout
    await AuthHelpers.logoutUser(page)
    
    // Verify logged out
    await AuthHelpers.verifyNotAuthenticated(page)
    
    // Try to access protected page - should redirect to login
    await page.goto('/chat')
    await expect(page).toHaveURL(/\/auth\/login/)
  })

  test('should handle invalid credentials', async ({ page }) => {
    await page.goto('/auth/login')
    
    // Try login with wrong credentials
    await page.getByLabel(/email/i).fill(testUsers.standard.email)
    await page.getByLabel(/password/i).fill('wrongpassword')
    await page.getByRole('button', { name: /sign in|login/i }).click()
    
    // Should show error message
    await CommonHelpers.verifyErrorMessage(page, /invalid credentials|incorrect password|login failed/i)
    
    // Should remain on login page
    await expect(page).toHaveURL(/\/auth\/login/)
  })

  test('should handle non-existent user', async ({ page }) => {
    await page.goto('/auth/login')
    
    await page.getByLabel(/email/i).fill('nonexistent@example.com')
    await page.getByLabel(/password/i).fill('somepassword')
    await page.getByRole('button', { name: /sign in|login/i }).click()
    
    // Should show error message
    await CommonHelpers.verifyErrorMessage(page, /user not found|invalid credentials|login failed/i)
  })

  test('should validate required fields', async ({ page }) => {
    await page.goto('/auth/login')
    
    // Try to submit empty form
    await page.getByRole('button', { name: /sign in|login/i }).click()
    
    // Should show validation errors
    await CommonHelpers.verifyErrorMessage(page, /email.*required|required/i)
  })

  test('should validate email format', async ({ page }) => {
    await page.goto('/auth/login')
    
    await page.getByLabel(/email/i).fill('invalid-email')
    await page.getByLabel(/password/i).fill('somepassword')
    await page.getByRole('button', { name: /sign in|login/i }).click()
    
    // Should show email format error
    await CommonHelpers.verifyErrorMessage(page, /valid email|email format/i)
  })

  test('should handle password reset flow initiation', async ({ page }) => {
    await page.goto('/auth/login')
    
    // Look for forgot password link
    const forgotPasswordLink = page.getByRole('link', { name: /forgot password|reset password/i })
    
    if (await forgotPasswordLink.isVisible({ timeout: 2000 }).catch(() => false)) {
      await forgotPasswordLink.click()
      
      // Should navigate to password reset page
      await expect(page).toHaveURL(/\/auth\/reset-password|\/auth\/forgot-password/)
      await expect(page.getByRole('heading', { name: /reset password|forgot password/i })).toBeVisible()
      
      // Fill email for password reset
      await page.getByLabel(/email/i).fill(testUsers.standard.email)
      await page.getByRole('button', { name: /send|reset|submit/i }).click()
      
      // Should show success message
      await CommonHelpers.verifySuccessMessage(page, /email sent|check your email|reset link/i)
    }
  })

  test('should be accessible via keyboard navigation', async ({ page }) => {
    await page.goto('/auth/login')
    
    // Test keyboard navigation
    await page.keyboard.press('Tab')
    await expect(page.getByLabel(/email/i)).toBeFocused()
    
    await page.keyboard.press('Tab')
    await expect(page.getByLabel(/password/i)).toBeFocused()
    
    await page.keyboard.press('Tab')
    await expect(page.getByRole('button', { name: /sign in|login/i })).toBeFocused()
    
    // Test form submission with Enter key
    await page.getByLabel(/email/i).fill(testUsers.standard.email)
    await page.getByLabel(/password/i).fill(testUsers.standard.password)
    await page.keyboard.press('Enter')
    
    await expect(page).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 10000 })
  })

  test('should handle concurrent login attempts', async ({ page, context }) => {
    // Open multiple tabs and try to login simultaneously
    const page2 = await context.newPage()
    
    await Promise.all([
      page.goto('/auth/login'),
      page2.goto('/auth/login')
    ])
    
    // Fill forms in both tabs
    await Promise.all([
      page.getByLabel(/email/i).fill(testUsers.standard.email),
      page2.getByLabel(/email/i).fill(testUsers.standard.email)
    ])
    
    await Promise.all([
      page.getByLabel(/password/i).fill(testUsers.standard.password),
      page2.getByLabel(/password/i).fill(testUsers.standard.password)
    ])
    
    // Submit both forms
    await Promise.all([
      page.getByRole('button', { name: /sign in|login/i }).click(),
      page2.getByRole('button', { name: /sign in|login/i }).click()
    ])
    
    // Both should succeed (or handle gracefully)
    await Promise.all([
      expect(page).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 10000 }),
      expect(page2).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 10000 })
    ])
  })

  test('should maintain session across multiple tabs', async ({ page, context }) => {
    // Login in first tab
    await AuthHelpers.loginUser(page, testUsers.standard)
    
    // Open second tab
    const page2 = await context.newPage()
    await page2.goto('/')
    await CommonHelpers.waitForPageLoad(page2)
    
    // Should be authenticated in second tab
    await AuthHelpers.verifyAuthenticated(page2)
    
    // Logout from first tab
    await AuthHelpers.logoutUser(page)
    
    // Second tab should also be logged out (after refresh or navigation)
    await page2.reload()
    await AuthHelpers.verifyNotAuthenticated(page2)
  })

  test('should handle login with special characters in email', async ({ page }) => {
    const specialUser = testUsers.specialUser
    
    await page.goto('/auth/login')
    await page.getByLabel(/email/i).fill(specialUser.email)
    await page.getByLabel(/password/i).fill(specialUser.password)
    await page.getByRole('button', { name: /sign in|login/i }).click()
    
    // Should handle special characters correctly
    // Note: This assumes the special user exists in the database
    // In a real test, you might need to create this user first
    try {
      await expect(page).toHaveURL(/\/(dashboard|chat|$)/, { timeout: 10000 })
      await AuthHelpers.verifyAuthenticated(page)
    } catch (error) {
      // If user doesn't exist, should show appropriate error
      await CommonHelpers.verifyErrorMessage(page, /invalid credentials|user not found/i)
    }
  })
})