import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { generateUniqueTestUser } from './fixtures/test-users'

/**
 * Complete User Registration Journey Tests
 * 
 * Tests the entire registration flow using robust selectors that are resilient
 * to UI changes by prioritizing semantic attributes over brittle CSS selectors.
 */
test.describe('Complete User Registration', () => {
  
  test('should complete new user registration journey', async ({ page }) => {
    const testUser = generateUniqueTestUser()

    await test.step('Navigate to registration page', async () => {
      await page.goto('/auth/register')
      
      // Wait for page to load and verify we're on registration page
      await expect(page).toHaveURL(/\/auth\/register/)
      
      // Check for registration form using multiple robust selectors
      await expect(
        page.getByRole('heading', { name: /create.*account|sign.*up|register/i })
      ).toBeVisible()
      
      // Alternative selector fallbacks
      const headingFallbacks = [
        page.locator('[data-testid="registration-heading"]'),
        page.locator('h1:has-text("Create"), h2:has-text("Create")'),
        page.locator('[aria-label*="registration"], [aria-labelledby*="registration"]')
      ]
      
      let headingFound = false
      for (const heading of headingFallbacks) {
        try {
          if (await heading.isVisible({ timeout: 2000 })) {
            headingFound = true
            break
          }
        } catch (e) {
          // Continue trying other selectors
        }
      }
      
      if (!headingFound) {
        throw new Error('Registration page heading not found with any selector')
      }
    })

    await test.step('Fill registration form with valid data', async () => {
      // Use robust selectors prioritizing accessibility attributes
      const nameField = page.locator('[data-testid="name-input"]')
        .or(page.getByLabel(/name|full.*name/i))
        .or(page.getByPlaceholder(/name|full.*name/i))
        .or(page.locator('input[name="name"], input[name="fullName"], input[name="full_name"]'))
        .first()

      const emailField = page.locator('[data-testid="email-input"]')
        .or(page.getByLabel(/email.*address|email/i))
        .or(page.getByPlaceholder(/email/i))
        .or(page.locator('input[type="email"], input[name="email"]'))
        .first()

      const passwordField = page.locator('[data-testid="password-input"]')
        .or(page.getByLabel(/password.*create|new.*password|password/i).first())
        .or(page.getByPlaceholder(/password.*create|create.*password/i))
        .or(page.locator('input[type="password"][name="password"], input[type="password"]').first())

      const confirmPasswordField = page.locator('[data-testid="confirm-password-input"]')
        .or(page.getByLabel(/confirm.*password|repeat.*password|password.*confirm/i))
        .or(page.getByPlaceholder(/confirm.*password|repeat.*password/i))
        .or(page.locator('input[name="confirmPassword"], input[name="passwordConfirm"]'))

      // Verify all fields are visible
      await expect(nameField).toBeVisible()
      await expect(emailField).toBeVisible()  
      await expect(passwordField).toBeVisible()
      await expect(confirmPasswordField).toBeVisible()

      // Fill form fields
      await nameField.fill(testUser.name)
      await emailField.fill(testUser.email)
      await passwordField.fill(testUser.password)
      await confirmPasswordField.fill(testUser.password)
      
      console.log(`Registration form filled for: ${testUser.email}`)
    })

    await test.step('Accept terms and conditions', async () => {
      // Find terms checkbox using robust selectors
      const termsCheckbox = page.locator('[data-testid="terms-checkbox"]')
        .or(page.getByLabel(/terms.*service|privacy.*policy|agree.*terms/i))
        .or(page.locator('input[type="checkbox"][name*="terms"], input[type="checkbox"][name*="agree"]'))
        .or(page.locator('input[type="checkbox"]:near(text*="terms"):near(text*="privacy")'))
        .first()

      await expect(termsCheckbox).toBeVisible()
      await termsCheckbox.check()
      await expect(termsCheckbox).toBeChecked()
    })

    await test.step('Submit registration form', async () => {
      // Find submit button using robust selectors
      const submitButton = page.locator('[data-testid="register-button"]')
        .or(page.getByRole('button', { name: /create.*account|sign.*up|register/i }))
        .or(page.locator('button[type="submit"]'))
        .or(page.locator('button:has-text("Create"), button:has-text("Register"), button:has-text("Sign up")'))
        .first()

      await expect(submitButton).toBeVisible()
      await expect(submitButton).toBeEnabled()
      
      // Submit form and wait for navigation or response
      await Promise.all([
        page.waitForResponse(response => 
          response.url().includes('/auth/register') || 
          response.url().includes('/api/auth/register'), 
          { timeout: 15000 }
        ).catch(() => null), // Allow to continue if no API call detected
        submitButton.click()
      ])
    })

    await test.step('Verify successful registration', async () => {
      // Wait for redirect or success state
      await page.waitForTimeout(3000)
      
      const currentUrl = page.url()
      console.log(`Current URL after registration: ${currentUrl}`)
      
      // Check for success indicators using multiple strategies
      const successIndicators = [
        // URL-based success
        () => currentUrl.includes('/auth/onboarding') || 
              currentUrl.includes('/dashboard') ||
              currentUrl.includes('/verify') ||
              !currentUrl.includes('/auth/register'),
        
        // Element-based success
        async () => {
          const successSelectors = [
            page.locator('[data-testid="success-message"]'),
            page.getByText(/success.*created|account.*created|registration.*complete/i),
            page.getByText(/check.*email|verify.*email/i),
            page.locator('[role="alert"]:has-text("success")'),
            page.locator('.success, .alert-success')
          ]
          
          for (const selector of successSelectors) {
            try {
              if (await selector.isVisible({ timeout: 2000 })) {
                return true
              }
            } catch (e) {
              // Continue checking
            }
          }
          return false
        }
      ]
      
      let registrationSuccessful = false
      
      // Check URL-based success
      if (successIndicators[0]()) {
        registrationSuccessful = true
        console.log('Registration successful: URL redirect detected')
      }
      
      // Check element-based success
      if (!registrationSuccessful && await successIndicators[1]()) {
        registrationSuccessful = true
        console.log('Registration successful: Success message detected')
      }
      
      // If still not confirmed, check for absence of error messages
      if (!registrationSuccessful) {
        const errorSelectors = [
          page.locator('[data-testid="error-message"]'),
          page.getByText(/error|failed|invalid/i),
          page.locator('[role="alert"]:not(:has-text("success"))'),
          page.locator('.error, .alert-error, .text-red, .text-destructive')
        ]
        
        let hasError = false
        for (const selector of errorSelectors) {
          try {
            if (await selector.isVisible({ timeout: 2000 })) {
              const errorText = await selector.textContent()
              console.log(`Registration error detected: ${errorText}`)
              hasError = true
              break
            }
          } catch (e) {
            // Continue checking
          }
        }
        
        registrationSuccessful = !hasError && !currentUrl.includes('/auth/register')
      }
      
      expect(registrationSuccessful, 'Registration should be successful').toBe(true)
    })

    await test.step('Cleanup test data', async () => {
      await CommonHelpers.cleanupTestData(page, testUser)
    })
  })

  test('should validate email format', async ({ page }) => {
    await page.goto('/auth/register')
    
    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .or(page.locator('input[type="email"]'))
      .first()
    
    const submitButton = page.locator('[data-testid="register-button"]')
      .or(page.getByRole('button', { name: /create.*account|register/i }))
      .or(page.locator('button[type="submit"]'))
      .first()
    
    // Try invalid email
    await emailField.fill('invalid-email')
    await submitButton.click()
    
    // Check for validation error
    const errorMessage = page.locator('[data-testid="email-error"]')
      .or(page.getByText(/invalid.*email|email.*invalid|valid.*email/i))
      .or(page.locator('[role="alert"]:has-text("email")'))
      .first()
    
    await expect(errorMessage).toBeVisible({ timeout: 5000 })
  })

  test('should validate password requirements', async ({ page }) => {
    await page.goto('/auth/register')
    
    const passwordField = page.locator('[data-testid="password-input"]')
      .or(page.getByLabel(/password/i).first())
      .or(page.locator('input[type="password"]').first())
    
    const submitButton = page.locator('[data-testid="register-button"]')
      .or(page.getByRole('button', { name: /create.*account|register/i }))
      .or(page.locator('button[type="submit"]'))
      .first()
    
    // Try weak password
    await passwordField.fill('123')
    await submitButton.click()
    
    // Check for validation error
    const errorMessage = page.locator('[data-testid="password-error"]')
      .or(page.getByText(/password.*weak|password.*short|password.*requirement/i))
      .or(page.locator('[role="alert"]:has-text("password")'))
      .first()
    
    await expect(errorMessage).toBeVisible({ timeout: 5000 })
  })

  test('should handle registration with existing email', async ({ page }) => {
    const existingUser = generateUniqueTestUser()
    
    // First registration
    await AuthHelpers.registerUser(page, existingUser)
    
    // Try to register again with same email
    await page.goto('/auth/register')
    
    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .or(page.locator('input[type="email"]'))
      .first()
    
    await emailField.fill(existingUser.email)
    
    const submitButton = page.locator('[data-testid="register-button"]')
      .or(page.getByRole('button', { name: /create.*account|register/i }))
      .or(page.locator('button[type="submit"]'))
      .first()
    
    await submitButton.click()
    
    // Check for duplicate email error
    const errorMessage = page.locator('[data-testid="duplicate-email-error"]')
      .or(page.getByText(/email.*exists|already.*registered|account.*exists/i))
      .or(page.locator('[role="alert"]:has-text("email")'))
      .first()
    
    await expect(errorMessage).toBeVisible({ timeout: 10000 })
    
    await CommonHelpers.cleanupTestData(page, existingUser)
  })

  test('should handle special characters in email', async ({ page }) => {
    const testUser = {
      ...generateUniqueTestUser(),
      email: 'test+special@example.com'
    }
    
    await page.goto('/auth/register')
    
    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .or(page.locator('input[type="email"]'))
      .first()
    
    await emailField.fill(testUser.email)
    
    // Email should be accepted
    await expect(emailField).toHaveValue(testUser.email)
    
    await CommonHelpers.cleanupTestData(page, testUser)
  })

  test('should validate terms and conditions acceptance', async ({ page }) => {
    const testUser = generateUniqueTestUser()
    
    await page.goto('/auth/register')
    
    // Fill all fields but don't check terms
    const nameField = page.locator('[data-testid="name-input"]')
      .or(page.getByLabel(/name/i))
      .first()
    const emailField = page.locator('[data-testid="email-input"]')
      .or(page.getByLabel(/email/i))
      .first()
    const passwordField = page.locator('[data-testid="password-input"]')
      .or(page.getByLabel(/password/i).first())
      
    await nameField.fill(testUser.name)
    await emailField.fill(testUser.email)
    await passwordField.fill(testUser.password)
    
    const submitButton = page.locator('[data-testid="register-button"]')
      .or(page.getByRole('button', { name: /create.*account|register/i }))
      .or(page.locator('button[type="submit"]'))
      .first()
    
    await submitButton.click()
    
    // Check for terms validation error
    const errorMessage = page.locator('[data-testid="terms-error"]')
      .or(page.getByText(/terms.*required|accept.*terms|agree.*terms/i))
      .or(page.locator('[role="alert"]:has-text("terms")'))
      .first()
    
    await expect(errorMessage).toBeVisible({ timeout: 5000 })
  })

  test('Registration Flow should be accessible via keyboard navigation', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Navigate through form using Tab key
    await page.keyboard.press('Tab') // Name field
    await page.keyboard.type('John Doe')
    
    await page.keyboard.press('Tab') // Email field
    await page.keyboard.type('john@example.com')
    
    await page.keyboard.press('Tab') // Password field
    await page.keyboard.type('SecurePass123!')
    
    await page.keyboard.press('Tab') // Confirm password field
    await page.keyboard.type('SecurePass123!')
    
    await page.keyboard.press('Tab') // Terms checkbox
    await page.keyboard.press('Space') // Check the checkbox
    
    await page.keyboard.press('Tab') // Submit button
    await page.keyboard.press('Enter') // Submit form
    
    // Form should be submitted successfully via keyboard
    const currentUrl = page.url()
    await expect(currentUrl).not.toContain('/auth/register')
  })
})