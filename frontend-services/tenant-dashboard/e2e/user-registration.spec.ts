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
    await expect(page.getByRole('heading', { name: /create your account/i })).toBeVisible()

    // Step 2: Fill out registration form using placeholder text selectors
    await page.getByPlaceholder('Enter your full name').fill(newUser.name)
    await page.getByPlaceholder('Enter your email').fill(newUser.email)
    await page.getByPlaceholder('Create a password').fill(newUser.password)
    await page.getByPlaceholder('Confirm your password').fill(newUser.password)

    // Accept terms and conditions checkbox
    await page.getByLabel(/I agree to the Terms of Service and Privacy Policy/i).check()

    // Step 3: Submit registration
    await page.getByRole('button', { name: /create account/i }).click()

    // Step 4: Handle post-registration flow
    // Should redirect to onboarding after successful registration
    await expect(page).toHaveURL(/\/auth\/onboarding/, { timeout: 15000 })

    // Step 5: Complete onboarding flow
    await expect(page.getByText(/welcome|getting started/i)).toBeVisible()
    
    // Look for and complete onboarding steps
    const continueButton = page.getByRole('button', { name: /continue|next|get started|complete setup/i })
    if (await continueButton.isVisible()) {
      await continueButton.click()
      // Wait for redirect after onboarding
      await expect(page).toHaveURL(/\/(dashboard|chat|\/)/,  { timeout: 10000 })
    }

    // Step 6: Verify successful registration and access to main application
    await CommonHelpers.waitForPageLoad(page)
    
    // Verify user is authenticated
    await AuthHelpers.verifyAuthenticated(page)

    // Step 7: Verify access to protected features
    // Navigate to chat interface
    await page.goto('/chat')
    await expect(page.getByText(/PyAirtable Assistant/i)).toBeVisible()

    // Clean up test user
    await CommonHelpers.cleanupTestData(page, newUser.email)
  })

  test('should handle registration with existing email', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Try to register with existing test user email
    await page.getByPlaceholder('Enter your full name').fill('Another User')
    await page.getByPlaceholder('Enter your email').fill(testUsers.standard.email)
    await page.getByPlaceholder('Create a password').fill('NewPassword123!')
    await page.getByPlaceholder('Confirm your password').fill('NewPassword123!')
    
    await page.getByLabel(/I agree to the Terms of Service and Privacy Policy/i).check()
    await page.getByRole('button', { name: /create account/i }).click()

    // Should show error about existing email
    await CommonHelpers.verifyErrorMessage(page, /email already exists|user already registered|email taken/i)
  })

  test('should validate password requirements', async ({ page }) => {
    await page.goto('/auth/register')
    
    const uniqueUser = generateUniqueTestUser('password-test')
    await page.getByPlaceholder('Enter your full name').fill(uniqueUser.name)
    await page.getByPlaceholder('Enter your email').fill(uniqueUser.email)
    
    // Test weak password
    await page.getByPlaceholder('Create a password').fill('123')
    await page.getByLabel(/I agree to the Terms of Service and Privacy Policy/i).check()
    await page.getByRole('button', { name: /create account/i }).click()
    
    // Should show password requirement error
    await CommonHelpers.verifyErrorMessage(page, /password.*requirements|password.*strong|password.*length/i)
  })

  test('should validate email format', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Test invalid email format
    await page.getByPlaceholder('Enter your full name').fill('Test User')
    await page.getByPlaceholder('Enter your email').fill('invalid-email')
    await page.getByPlaceholder('Create a password').fill('ValidPassword123!')
    await page.getByPlaceholder('Confirm your password').fill('ValidPassword123!')
    
    await page.getByLabel(/I agree to the Terms of Service and Privacy Policy/i).check()
    await page.getByRole('button', { name: /create account/i }).click()
    
    // Should show email format error
    await CommonHelpers.verifyErrorMessage(page, /valid email|email format|invalid email/i)
  })

  test('should handle password confirmation mismatch', async ({ page }) => {
    await page.goto('/auth/register')
    
    const uniqueUser = generateUniqueTestUser('mismatch-test')
    
    await page.getByPlaceholder('Enter your full name').fill(uniqueUser.name)
    await page.getByPlaceholder('Enter your email').fill(uniqueUser.email)
    await page.getByPlaceholder('Create a password').fill('Password123!')
    await page.getByPlaceholder('Confirm your password').fill('DifferentPassword123!')
    
    await page.getByLabel(/I agree to the Terms of Service and Privacy Policy/i).check()
    await page.getByRole('button', { name: /create account/i }).click()
    
    // Should show password mismatch error
    await CommonHelpers.verifyErrorMessage(page, /passwords.*match|passwords.*same|password.*mismatch/i)
  })

  test('should require terms and conditions acceptance', async ({ page }) => {
    await page.goto('/auth/register')
    
    const uniqueUser = generateUniqueTestUser('terms-test')
    
    await page.getByPlaceholder('Enter your full name').fill(uniqueUser.name)
    await page.getByPlaceholder('Enter your email').fill(uniqueUser.email)
    await page.getByPlaceholder('Create a password').fill(uniqueUser.password)
    await page.getByPlaceholder('Confirm your password').fill(uniqueUser.password)
    
    // Don't check terms checkbox - leave it unchecked
    await page.getByRole('button', { name: /create account/i }).click()
    
    // Should show terms acceptance error
    await CommonHelpers.verifyErrorMessage(page, /accept.*terms|agree.*terms|terms.*required/i)
  })

  test('should navigate between registration and login pages', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Click link to go to login page
    await page.getByRole('link', { name: /sign in/i }).click()
    
    await expect(page).toHaveURL(/\/auth\/login/)
    await expect(page.getByRole('heading', { name: /welcome back/i })).toBeVisible()
    
    // Navigate back to registration
    await page.getByRole('link', { name: /sign up/i }).click()
    
    await expect(page).toHaveURL(/\/auth\/register/)
    await expect(page.getByRole('heading', { name: /create your account/i })).toBeVisible()
  })

  test('should be accessible', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Test keyboard navigation - first focusable element should be the name field
    await page.keyboard.press('Tab')
    const firstField = page.getByPlaceholder('Enter your full name')
    await expect(firstField).toBeFocused()
    
    // Check form field attributes
    await expect(page.getByPlaceholder('Enter your email')).toHaveAttribute('type', 'email')
    await expect(page.getByPlaceholder('Create a password')).toHaveAttribute('type', 'password')
    await expect(page.getByPlaceholder('Confirm your password')).toHaveAttribute('type', 'password')
    
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
    
    await page.getByPlaceholder('Enter your full name').fill(specialUser.name)
    await page.getByPlaceholder('Enter your email').fill(specialUser.email)
    await page.getByPlaceholder('Create a password').fill(specialUser.password)
    await page.getByPlaceholder('Confirm your password').fill(specialUser.password)
    
    await page.getByLabel(/I agree to the Terms of Service and Privacy Policy/i).check()
    await page.getByRole('button', { name: /create account/i }).click()
    
    // Should handle special characters in email correctly
    await expect(page).toHaveURL(/\/auth\/onboarding/, { timeout: 15000 })
    
    // Clean up
    await CommonHelpers.cleanupTestData(page, specialUser.email)
  })
})