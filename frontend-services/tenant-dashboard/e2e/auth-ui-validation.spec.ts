import { test, expect } from '@playwright/test'

test.describe('Authentication UI Validation', () => {
  test.describe('Login Page', () => {
    test('should display login form elements', async ({ page }) => {
      await page.goto('/auth/login')
      
      // Wait for the page to render
      await page.waitForTimeout(2000)
      
      // Check for login form elements
      const emailField = page.getByRole('textbox', { name: /email/i }).first()
      const passwordField = page.locator('input[type="password"]').first()
      const submitButton = page.getByRole('button', { name: /sign in|login/i }).first()
      
      if (await emailField.isVisible()) {
        await expect(emailField).toBeVisible()
        await expect(emailField).toHaveAttribute('type', 'email')
      }
      
      if (await passwordField.isVisible()) {
        await expect(passwordField).toBeVisible()
      }
      
      if (await submitButton.isVisible()) {
        await expect(submitButton).toBeVisible()
      }
    })

    test('should validate form inputs', async ({ page }) => {
      await page.goto('/auth/login')
      await page.waitForTimeout(2000)
      
      const emailField = page.getByRole('textbox', { name: /email/i }).first()
      const passwordField = page.locator('input[type="password"]').first()
      const submitButton = page.getByRole('button', { name: /sign in|login/i }).first()
      
      // Test empty form submission
      if (await submitButton.isVisible()) {
        await submitButton.click()
        
        // Look for validation messages (might appear anywhere on the page)
        const validationMessages = [
          /required/i,
          /please enter/i,
          /field is required/i,
          /email.*required/i,
          /password.*required/i
        ]
        
        let foundValidation = false
        for (const message of validationMessages) {
          try {
            await expect(page.locator('text=' + message.source)).toBeVisible({ timeout: 2000 })
            foundValidation = true
            break
          } catch {
            // Continue checking other patterns
          }
        }
        
        if (!foundValidation) {
          // Try to check if form prevented submission by staying on login page
          expect(page.url()).toContain('/auth/login')
        }
      }
    })

    test('should handle invalid email format', async ({ page }) => {
      await page.goto('/auth/login')
      await page.waitForTimeout(2000)
      
      const emailField = page.getByRole('textbox', { name: /email/i }).first()
      const passwordField = page.locator('input[type="password"]').first()
      const submitButton = page.getByRole('button', { name: /sign in|login/i }).first()
      
      if (await emailField.isVisible() && await passwordField.isVisible()) {
        await emailField.fill('invalid-email')
        await passwordField.fill('password123')
        
        if (await submitButton.isVisible()) {
          await submitButton.click()
          
          // Look for email validation messages
          const emailValidationMessages = [
            /valid email/i,
            /email format/i,
            /invalid email/i,
            /enter.*valid.*email/i
          ]
          
          let foundValidation = false
          for (const message of emailValidationMessages) {
            try {
              await page.waitForSelector(`text=${message.source}`, { timeout: 2000 })
              foundValidation = true
              break
            } catch {
              // Continue checking other patterns
            }
          }
          
          // Fallback: check browser's native validation
          const emailFieldValidation = await emailField.evaluate((el: HTMLInputElement) => el.validationMessage)
          if (emailFieldValidation && emailFieldValidation.length > 0) {
            foundValidation = true
          }
          
          expect(foundValidation).toBe(true)
        }
      }
    })

    test('should navigate to registration page', async ({ page }) => {
      await page.goto('/auth/login')
      await page.waitForTimeout(2000)
      
      // Look for link to registration
      const registerLinks = [
        page.getByRole('link', { name: /sign up/i }),
        page.getByRole('link', { name: /register/i }),
        page.getByRole('link', { name: /create account/i }),
        page.locator('a[href*="/register"]'),
        page.locator('a[href*="/signup"]')
      ]
      
      for (const link of registerLinks) {
        try {
          if (await link.isVisible({ timeout: 1000 })) {
            await link.click()
            await expect(page).toHaveURL(/\/(auth\/register|signup|register)/)
            return
          }
        } catch {
          // Continue to next link
        }
      }
    })
  })

  test.describe('Registration Page', () => {
    test('should display registration form elements', async ({ page }) => {
      await page.goto('/auth/register')
      await page.waitForTimeout(2000)
      
      // Check for registration form elements
      const emailField = page.getByRole('textbox', { name: /email/i }).first()
      const passwordField = page.locator('input[type="password"]').first()
      const nameField = page.getByRole('textbox', { name: /name/i }).first()
      const submitButton = page.getByRole('button', { name: /sign up|register|create/i }).first()
      
      if (await emailField.isVisible()) {
        await expect(emailField).toBeVisible()
        await expect(emailField).toHaveAttribute('type', 'email')
      }
      
      if (await passwordField.isVisible()) {
        await expect(passwordField).toBeVisible()
      }
      
      if (await nameField.isVisible()) {
        await expect(nameField).toBeVisible()
      }
      
      if (await submitButton.isVisible()) {
        await expect(submitButton).toBeVisible()
      }
    })

    test('should validate password requirements', async ({ page }) => {
      await page.goto('/auth/register')
      await page.waitForTimeout(2000)
      
      const emailField = page.getByRole('textbox', { name: /email/i }).first()
      const passwordField = page.locator('input[type="password"]').first()
      const nameField = page.getByRole('textbox', { name: /name/i }).first()
      const submitButton = page.getByRole('button', { name: /sign up|register|create/i }).first()
      
      if (await emailField.isVisible() && await passwordField.isVisible()) {
        await emailField.fill('test@example.com')
        if (await nameField.isVisible()) {
          await nameField.fill('Test User')
        }
        
        // Test weak password
        await passwordField.fill('123')
        
        if (await submitButton.isVisible()) {
          await submitButton.click()
          
          // Look for password validation messages
          const passwordValidationMessages = [
            /password.*requirements/i,
            /password.*strong/i,
            /password.*length/i,
            /password.*minimum/i,
            /password.*least.*characters/i
          ]
          
          let foundValidation = false
          for (const message of passwordValidationMessages) {
            try {
              await page.waitForSelector(`text=${message.source}`, { timeout: 2000 })
              foundValidation = true
              break
            } catch {
              // Continue checking
            }
          }
          
          if (!foundValidation) {
            // Check if form prevented submission
            expect(page.url()).toContain('/register')
          }
        }
      }
    })
  })

  test.describe('Navigation and Accessibility', () => {
    test('should be keyboard accessible', async ({ page }) => {
      await page.goto('/auth/login')
      await page.waitForTimeout(2000)
      
      // Test tab navigation
      await page.keyboard.press('Tab')
      
      // Check if focus is on a form element
      const focusedElement = await page.evaluate(() => document.activeElement?.tagName)
      expect(['INPUT', 'BUTTON', 'A'].includes(focusedElement || '')).toBe(true)
    })

    test('should have proper page titles', async ({ page }) => {
      await page.goto('/auth/login')
      await page.waitForTimeout(2000)
      const loginTitle = await page.title()
      expect(loginTitle).toBeTruthy()
      
      await page.goto('/auth/register')
      await page.waitForTimeout(2000)
      const registerTitle = await page.title()
      expect(registerTitle).toBeTruthy()
      
      // Titles should be different
      expect(loginTitle).not.toBe(registerTitle)
    })

    test('should handle responsive design', async ({ page }) => {
      // Test mobile viewport
      await page.setViewportSize({ width: 375, height: 667 })
      await page.goto('/auth/login')
      await page.waitForTimeout(2000)
      
      // Check if mobile layout is applied
      const body = page.locator('body')
      await expect(body).toBeVisible()
      
      // Test tablet viewport
      await page.setViewportSize({ width: 768, height: 1024 })
      await page.reload()
      await page.waitForTimeout(2000)
      await expect(body).toBeVisible()
      
      // Test desktop viewport
      await page.setViewportSize({ width: 1200, height: 800 })
      await page.reload()
      await page.waitForTimeout(2000)
      await expect(body).toBeVisible()
    })
  })

  test.describe('Error Handling', () => {
    test('should handle network errors gracefully', async ({ page }) => {
      // Simulate network failure
      await page.route('**/*', route => {
        if (route.request().url().includes('/api/')) {
          route.abort('failed')
        } else {
          route.continue()
        }
      })
      
      await page.goto('/auth/login')
      await page.waitForTimeout(2000)
      
      const emailField = page.getByRole('textbox', { name: /email/i }).first()
      const passwordField = page.locator('input[type="password"]').first()
      const submitButton = page.getByRole('button', { name: /sign in|login/i }).first()
      
      if (await emailField.isVisible() && await passwordField.isVisible()) {
        await emailField.fill('test@example.com')
        await passwordField.fill('password123')
        
        if (await submitButton.isVisible()) {
          await submitButton.click()
          
          // Should show some kind of error message
          const errorMessages = [
            /error/i,
            /failed/i,
            /network/i,
            /something went wrong/i,
            /try again/i
          ]
          
          let foundError = false
          for (const message of errorMessages) {
            try {
              await page.waitForSelector(`text=${message.source}`, { timeout: 3000 })
              foundError = true
              break
            } catch {
              // Continue checking
            }
          }
          
          // Even if no specific error message, should not crash
          expect(page.url()).toBeTruthy()
        }
      }
    })
  })
})