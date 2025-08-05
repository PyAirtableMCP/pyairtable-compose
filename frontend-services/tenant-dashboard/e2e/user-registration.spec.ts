import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { testUsers, generateUniqueTestUser, testData } from './fixtures/test-users'

test.describe('Complete User Registration Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Start with clean state
    await page.goto('/')
  })

  test('should complete full new user registration journey', async ({ page }) => {
    // Generate unique user for this test run
    const newUser = generateUniqueTestUser('registration')

    // Step 1: Navigate to registration from landing page
    await page.goto('/auth/register')
    await expect(page.getByRole('heading', { name: /create account|sign up|register/i })).toBeVisible()

    // Step 2: Fill out registration form
    await page.getByLabel(/email/i).fill(newUser.email)
    await page.getByLabel(/password/i).fill(newUser.password)
    
    // Handle confirm password field if present
    const confirmPasswordField = page.getByLabel(/confirm password|repeat password/i)
    if (await confirmPasswordField.isVisible({ timeout: 1000 }).catch(() => false)) {
      await confirmPasswordField.fill(newUser.password)
    }
    
    await page.getByLabel(/name|full name/i).fill(newUser.name)

    // Accept terms and conditions if present
    const termsCheckbox = page.getByLabel(/terms|privacy|agree/i)
    if (await termsCheckbox.isVisible({ timeout: 1000 }).catch(() => false)) {
      await termsCheckbox.check()
    }

    // Step 3: Submit registration
    await page.getByRole('button', { name: /sign up|register|create account/i }).click()

    // Step 4: Handle post-registration flow
    // Could redirect to email verification, onboarding, or directly to dashboard
    await expect(page).toHaveURL(/\/(verify-email|onboarding|dashboard|chat)/, { timeout: 15000 })

    // Step 5: If email verification required, simulate verification
    if (page.url().includes('/verify-email')) {
      // Look for verification message
      await expect(page.getByText(/verify|check your email|confirmation/i)).toBeVisible()
      
      // Mock email verification (in real scenario, would click email link)
      await page.goto('/auth/verify?token=mock-verification-token&email=' + encodeURIComponent(newUser.email))
      
      // Should redirect to dashboard or onboarding
      await expect(page).toHaveURL(/\/(onboarding|dashboard|chat)/, { timeout: 10000 })
    }

    // Step 6: Complete onboarding if present
    if (page.url().includes('/onboarding')) {
      // Handle onboarding steps
      await expect(page.getByText(/welcome|getting started|setup/i)).toBeVisible()
      
      // Fill onboarding form if present
      const continueButton = page.getByRole('button', { name: /continue|next|get started/i })
      if (await continueButton.isVisible()) {
        await continueButton.click()
      }
      
      // Complete any additional onboarding steps
      await page.waitForURL(/\/(dashboard|chat)/, { timeout: 10000 })
    }

    // Step 7: Verify successful registration and access to main application
    await CommonHelpers.waitForPageLoad(page)
    
    // Should be on main dashboard or chat page
    expect(['/dashboard', '/chat', '/']).toContain(new URL(page.url()).pathname)
    
    // Verify user is authenticated
    await AuthHelpers.verifyAuthenticated(page)

    // Step 8: Verify access to protected features
    // Navigate to chat interface
    await page.goto('/chat')
    await expect(page.getByText(/pyairtable ai assistant|welcome|chat/i)).toBeVisible()

    // Clean up test user
    await CommonHelpers.cleanupTestData(page, newUser.email)
  })

  test('should handle registration with existing email', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Try to register with existing test user email
    await page.getByLabel(/email/i).fill(testUsers.standard.email)
    await page.getByLabel(/password/i).fill('NewPassword123!')
    await page.getByLabel(/name/i).fill('Another User')
    
    const confirmPasswordField = page.getByLabel(/confirm password/i)
    if (await confirmPasswordField.isVisible({ timeout: 1000 }).catch(() => false)) {
      await confirmPasswordField.fill('NewPassword123!')
    }

    await page.getByRole('button', { name: /sign up|register/i }).click()

    // Should show error about existing email
    await CommonHelpers.verifyErrorMessage(page, /email already exists|user already registered|email taken/i)
  })

  test('should validate password requirements', async ({ page }) => {
    await page.goto('/auth/register')
    
    const uniqueUser = generateUniqueTestUser('password-test')
    await page.getByLabel(/email/i).fill(uniqueUser.email)
    await page.getByLabel(/name/i).fill(uniqueUser.name)
    
    // Test weak password
    await page.getByLabel(/password/i).fill('123')
    await page.getByRole('button', { name: /sign up|register/i }).click()
    
    // Should show password requirement error
    await CommonHelpers.verifyErrorMessage(page, /password.*requirements|password.*strong|password.*length/i)
  })

  test('should validate email format', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Test invalid email format
    await page.getByLabel(/email/i).fill('invalid-email')
    await page.getByLabel(/password/i).fill('ValidPassword123!')
    await page.getByLabel(/name/i).fill('Test User')
    
    await page.getByRole('button', { name: /sign up|register/i }).click()
    
    // Should show email format error
    await CommonHelpers.verifyErrorMessage(page, /valid email|email format|invalid email/i)
  })

  test('should handle password confirmation mismatch', async ({ page }) => {
    await page.goto('/auth/register')
    
    const uniqueUser = generateUniqueTestUser('mismatch-test')
    
    await page.getByLabel(/email/i).fill(uniqueUser.email)
    await page.getByLabel(/name/i).fill(uniqueUser.name)
    await page.getByLabel(/^password/i).fill('Password123!')
    
    const confirmField = page.getByLabel(/confirm password|repeat password/i)
    if (await confirmField.isVisible({ timeout: 1000 }).catch(() => false)) {
      await confirmField.fill('DifferentPassword123!')
      
      await page.getByRole('button', { name: /sign up|register/i }).click()
      
      // Should show password mismatch error
      await CommonHelpers.verifyErrorMessage(page, /passwords.*match|passwords.*same|password.*mismatch/i)
    }
  })

  test('should require terms and conditions acceptance', async ({ page }) => {
    await page.goto('/auth/register')
    
    const uniqueUser = generateUniqueTestUser('terms-test')
    
    await page.getByLabel(/email/i).fill(uniqueUser.email)
    await page.getByLabel(/password/i).fill(uniqueUser.password)
    await page.getByLabel(/name/i).fill(uniqueUser.name)
    
    // Don't check terms checkbox
    const termsCheckbox = page.getByLabel(/terms|privacy|agree/i)
    if (await termsCheckbox.isVisible({ timeout: 1000 }).catch(() => false)) {
      await page.getByRole('button', { name: /sign up|register/i }).click()
      
      // Should show terms acceptance error
      await CommonHelpers.verifyErrorMessage(page, /accept.*terms|agree.*terms|terms.*required/i)
    }
  })

  test('should navigate between registration and login pages', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Click link to go to login page
    await page.getByRole('link', { name: /sign in|login|already have account/i }).click()
    
    await expect(page).toHaveURL(/\/auth\/login/)
    await expect(page.getByRole('heading', { name: /sign in|login/i })).toBeVisible()
    
    // Navigate back to registration
    await page.getByRole('link', { name: /sign up|register|create account/i }).click()
    
    await expect(page).toHaveURL(/\/auth\/register/)
    await expect(page.getByRole('heading', { name: /create account|sign up|register/i })).toBeVisible()
  })

  test('should be accessible', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Test keyboard navigation
    await page.keyboard.press('Tab')
    const firstField = page.getByLabel(/email/i)
    await expect(firstField).toBeFocused()
    
    // Check form labels and accessibility
    await expect(firstField).toHaveAttribute('type', 'email')
    await expect(page.getByLabel(/password/i)).toHaveAttribute('type', 'password')
    
    // Verify aria-labels and form structure
    await CommonHelpers.verifyAccessibility(page)
  })

  test('should handle registration with special characters in email', async ({ page }) => {
    await page.goto('/auth/register')
    
    const specialUser = {
      email: 'test.user+special@example.com',
      password: 'SpecialPassword123!',
      name: 'Special Test User'
    }
    
    await page.getByLabel(/email/i).fill(specialUser.email)
    await page.getByLabel(/password/i).fill(specialUser.password)
    await page.getByLabel(/name/i).fill(specialUser.name)
    
    const confirmField = page.getByLabel(/confirm password/i)
    if (await confirmField.isVisible({ timeout: 1000 }).catch(() => false)) {
      await confirmField.fill(specialUser.password)
    }

    const termsCheckbox = page.getByLabel(/terms|privacy|agree/i)
    if (await termsCheckbox.isVisible({ timeout: 1000 }).catch(() => false)) {
      await termsCheckbox.check()
    }
    
    await page.getByRole('button', { name: /sign up|register/i }).click()
    
    // Should handle special characters in email correctly
    await expect(page).toHaveURL(/\/(verify-email|onboarding|dashboard|chat)/, { timeout: 15000 })
    
    // Clean up
    await CommonHelpers.cleanupTestData(page, specialUser.email)
  })
})