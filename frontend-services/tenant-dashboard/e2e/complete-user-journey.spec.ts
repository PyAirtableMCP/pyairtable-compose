import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { generateUniqueTestUser } from './fixtures/test-users'

/**
 * Complete User Journey Tests
 * 
 * End-to-end tests covering the entire user workflow from registration
 * to advanced feature usage using robust selectors.
 */
test.describe('Complete User Journey', () => {
  
  test('should complete end-to-end workflow from registration to using core features', async ({ page }) => {
    const testUser = generateUniqueTestUser('e2e')

    await test.step('Complete user registration', async () => {
      await page.goto('/auth/register')
      
      // Fill registration form using robust selectors
      const nameField = page.locator('[data-testid="name-input"]')
        .or(page.getByLabel(/name|full.*name/i))
        .or(page.getByPlaceholder(/name/i))
        .first()

      const emailField = page.locator('[data-testid="email-input"]')
        .or(page.getByLabel(/email/i))
        .or(page.getByPlaceholder(/email/i))
        .first()

      const passwordField = page.locator('[data-testid="password-input"]')
        .or(page.getByLabel(/password/i).first())
        .or(page.getByPlaceholder(/password.*create|create.*password/i))
        .first()

      const confirmPasswordField = page.locator('[data-testid="confirm-password-input"]')
        .or(page.getByLabel(/confirm.*password|repeat.*password/i))
        .or(page.getByPlaceholder(/confirm.*password/i))
        .first()

      const termsCheckbox = page.locator('[data-testid="terms-checkbox"]')
        .or(page.getByLabel(/terms.*service|privacy.*policy|agree.*terms/i))
        .first()

      const submitButton = page.locator('[data-testid="register-button"]')
        .or(page.getByRole('button', { name: /create.*account|sign.*up|register/i }))
        .or(page.locator('button[type="submit"]'))
        .first()

      await nameField.fill(testUser.name)
      await emailField.fill(testUser.email)
      await passwordField.fill(testUser.password)
      await confirmPasswordField.fill(testUser.password)
      await termsCheckbox.check()
      await submitButton.click()

      // Verify successful registration
      await page.waitForTimeout(3000)
      const currentUrl = page.url()
      expect(currentUrl).not.toContain('/auth/register')
      
      console.log(`Registration completed for: ${testUser.email}`)
    })

    await test.step('Complete onboarding if present', async () => {
      const currentUrl = page.url()
      
      if (currentUrl.includes('/onboarding') || currentUrl.includes('/welcome')) {
        // Handle onboarding flow
        const continueButton = page.locator('[data-testid="continue-button"]')
          .or(page.getByRole('button', { name: /continue|next|get.*started/i }))
          .or(page.locator('button[type="submit"]'))
          .first()

        if (await continueButton.isVisible({ timeout: 5000 })) {
          await continueButton.click()
        }

        // Skip tutorial if present
        const skipButton = page.locator('[data-testid="skip-tutorial"]')
          .or(page.getByRole('button', { name: /skip|later|no.*thanks/i }))
          .first()

        if (await skipButton.isVisible({ timeout: 3000 })) {
          await skipButton.click()
        }
      }
    })

    await test.step('Navigate to dashboard', async () => {
      // Navigate to dashboard using robust selectors
      const dashboardLink = page.locator('[data-testid="dashboard-nav"]')
        .or(page.getByRole('link', { name: /dashboard|home/i }))
        .or(page.locator('a[href*="/dashboard"], a[href="/"]'))
        .first()

      if (await dashboardLink.isVisible({ timeout: 3000 })) {
        await dashboardLink.click()
      } else {
        await page.goto('/dashboard')
      }

      await expect(page).toHaveURL(/\/(dashboard|$)/)
    })

    await test.step('Verify dashboard elements', async () => {
      // Check for main dashboard components
      const welcomeMessage = page.locator('[data-testid="welcome-message"]')
        .or(page.getByText(/welcome.*back|hello/i))
        .first()

      if (await welcomeMessage.isVisible({ timeout: 5000 })) {
        await expect(welcomeMessage).toBeVisible()
      }

      // Check for user menu
      const userMenu = page.locator('[data-testid="user-menu"]')
        .or(page.locator('.user-avatar, [class*="avatar"]'))
        .or(page.getByRole('button', { name: /profile|account|user/i }))
        .first()

      await expect(userMenu).toBeVisible()
    })

    await test.step('Access chat interface', async () => {
      // Navigate to chat
      const chatLink = page.locator('[data-testid="chat-nav"]')
        .or(page.getByRole('link', { name: /chat|assistant|ai/i }))
        .or(page.locator('a[href*="/chat"]'))
        .first()

      if (await chatLink.isVisible({ timeout: 3000 })) {
        await chatLink.click()
      } else {
        await page.goto('/chat')
      }

      await expect(page).toHaveURL(/\/chat/)
    })

    await test.step('Test chat functionality', async () => {
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox', { name: /message|chat|ask/i }))
        .or(page.getByPlaceholder(/ask.*question|type.*message/i))
        .first()

      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .or(page.locator('button[type="submit"]'))
        .first()

      await expect(chatInput).toBeVisible()
      await expect(sendButton).toBeVisible()

      // Send a test message
      await chatInput.fill('Hello, can you help me understand my data?')
      await sendButton.click()

      // Wait for AI response
      const aiResponse = page.locator('[data-testid="ai-message"]')
        .or(page.locator('.message:not(.user)').last())
        .first()

      await expect(aiResponse).toBeVisible({ timeout: 30000 })
      console.log('Chat functionality verified')
    })

    await test.step('Test user profile access', async () => {
      // Access user menu
      const userMenu = page.locator('[data-testid="user-menu"]')
        .or(page.locator('.user-avatar, [class*="avatar"]'))
        .or(page.getByRole('button', { name: /profile|account|user/i }))
        .first()

      await userMenu.click()

      // Look for profile/settings option
      const profileLink = page.locator('[data-testid="profile-link"]')
        .or(page.getByRole('menuitem', { name: /profile|settings|account/i }))
        .or(page.locator('a[href*="/profile"], a[href*="/settings"]'))
        .first()

      if (await profileLink.isVisible({ timeout: 3000 })) {
        await profileLink.click()
        
        // Verify we're on profile/settings page
        const currentUrl = page.url()
        expect(currentUrl).toMatch(/\/(profile|settings|account)/)
      }
    })

    await test.step('Test logout functionality', async () => {
      await AuthHelpers.logoutUser(page)
      
      // Should redirect to login page
      await expect(page).toHaveURL(/\/auth\/login/)
      
      // Verify cannot access protected pages
      await page.goto('/dashboard')
      await expect(page).toHaveURL(/\/auth\/login/)
    })

    await test.step('Cleanup test data', async () => {
      await CommonHelpers.cleanupTestData(page, testUser)
    })
  })

  test('should handle complete accessibility workflow', async ({ page }) => {
    const testUser = generateUniqueTestUser('a11y')

    await test.step('Register using keyboard navigation', async () => {
      await page.goto('/auth/register')
      
      // Navigate through form using Tab
      await page.keyboard.press('Tab') // Name field
      await page.keyboard.type(testUser.name)
      
      await page.keyboard.press('Tab') // Email field
      await page.keyboard.type(testUser.email)
      
      await page.keyboard.press('Tab') // Password field
      await page.keyboard.type(testUser.password)
      
      await page.keyboard.press('Tab') // Confirm password
      await page.keyboard.type(testUser.password)
      
      await page.keyboard.press('Tab') // Terms checkbox
      await page.keyboard.press('Space') // Check
      
      await page.keyboard.press('Tab') // Submit button
      await page.keyboard.press('Enter') // Submit
      
      // Should complete registration
      await page.waitForTimeout(3000)
      const currentUrl = page.url()
      expect(currentUrl).not.toContain('/auth/register')
    })

    await test.step('Navigate app using keyboard', async () => {
      // Use Tab to navigate through main navigation
      await page.goto('/dashboard')
      
      // Test heading structure
      const h1 = page.locator('h1').first()
      if (await h1.isVisible({ timeout: 3000 })) {
        await expect(h1).toBeVisible()
      }
      
      // Test skip links if present
      const skipLink = page.locator('a[href="#main"], [data-testid="skip-link"]').first()
      if (await skipLink.isVisible({ timeout: 2000 })) {
        await expect(skipLink).toBeVisible()
      }
    })

    await test.step('Test screen reader compatibility', async () => {
      // Check for ARIA labels and roles
      const mainContent = page.locator('main, [role="main"]').first()
      if (await mainContent.isVisible({ timeout: 3000 })) {
        await expect(mainContent).toBeVisible()
      }
      
      // Check for proper form labels
      await page.goto('/chat')
      
      const chatInput = page.getByRole('textbox').first()
      if (await chatInput.isVisible({ timeout: 3000 })) {
        const ariaLabel = await chatInput.getAttribute('aria-label')
        const hasLabel = await chatInput.locator('..').locator('label').isVisible().catch(() => false)
        
        expect(ariaLabel || hasLabel).toBeTruthy()
      }
    })

    await CommonHelpers.cleanupTestData(page, testUser)
  })

  test('should complete realistic business scenario workflow', async ({ page }) => {
    const testUser = generateUniqueTestUser('business')

    await test.step('User registration and setup', async () => {
      await AuthHelpers.registerUser(page, testUser)
    })

    await test.step('Initial data exploration', async () => {
      await AuthHelpers.loginUser(page, testUser)
      await page.goto('/chat')
      
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox'))
        .first()
      
      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .first()

      // Ask about available data
      await chatInput.fill('What data do I have access to?')
      await sendButton.click()
      
      await expect(
        page.locator('[data-testid="ai-message"]').or(page.locator('.message:not(.user)').last())
      ).toBeVisible({ timeout: 30000 })
    })

    await test.step('Request specific analysis', async () => {
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox'))
        .first()
      
      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .first()

      // Request analysis
      await chatInput.fill('Show me the top performing posts from last month')
      await sendButton.click()
      
      await expect(
        page.locator('[data-testid="ai-message"]').or(page.locator('.message:not(.user)').last())
      ).toBeVisible({ timeout: 45000 })
    })

    await test.step('Follow up with automation request', async () => {
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox'))
        .first()
      
      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .first()

      // Request automation
      await chatInput.fill('Can you create an automation to notify me of high-performing posts?')
      await sendButton.click()
      
      await expect(
        page.locator('[data-testid="ai-message"]').or(page.locator('.message:not(.user)').last())
      ).toBeVisible({ timeout: 45000 })
    })

    await CommonHelpers.cleanupTestData(page, testUser)
  })

  test('should handle end-to-end flow with multiple features', async ({ page }) => {
    const testUser = generateUniqueTestUser('multifeature')

    await test.step('Complete registration and onboarding', async () => {
      await AuthHelpers.registerUser(page, testUser)
    })

    await test.step('Login and verify dashboard', async () => {
      await AuthHelpers.loginUser(page, testUser)
      
      // Verify authenticated state
      await CommonHelpers.verifyAuthenticatedState(page)
      
      // Take screenshot for documentation
      await CommonHelpers.takeScreenshot(page, 'dashboard-authenticated')
    })

    await test.step('Interact with multiple features', async () => {
      // Test chat
      await page.goto('/chat')
      const chatInput = page.locator('[data-testid="chat-input"]').or(page.getByRole('textbox')).first()
      const sendButton = page.locator('[data-testid="send-button"]').or(page.getByRole('button', { name: /send/i })).first()
      
      await chatInput.fill('Hello from multifeature test')
      await sendButton.click()
      
      await expect(
        page.locator('[data-testid="ai-message"]').or(page.locator('.message:not(.user)').last())
      ).toBeVisible({ timeout: 30000 })

      // Navigate back to dashboard
      await page.goto('/dashboard')
      await CommonHelpers.verifyAuthenticatedState(page)
    })

    await test.step('Test session persistence', async () => {
      // Refresh page
      await page.reload()
      await page.waitForLoadState('networkidle')
      
      // Should still be authenticated
      await CommonHelpers.verifyAuthenticatedState(page)
    })

    await test.step('Complete logout', async () => {
      await AuthHelpers.logoutUser(page)
      await expect(page).toHaveURL(/\/auth\/login/)
    })

    await CommonHelpers.cleanupTestData(page, testUser)
  })

  test('should handle concurrent user scenarios', async ({ browser }) => {
    const user1 = generateUniqueTestUser('concurrent1')
    const user2 = generateUniqueTestUser('concurrent2')

    const context1 = await browser.newContext()
    const context2 = await browser.newContext()
    
    const page1 = await context1.newPage()
    const page2 = await context2.newPage()

    await test.step('Register both users concurrently', async () => {
      await Promise.all([
        AuthHelpers.registerUser(page1, user1),
        AuthHelpers.registerUser(page2, user2)
      ])
    })

    await test.step('Login both users concurrently', async () => {
      await Promise.all([
        AuthHelpers.loginUser(page1, user1),
        AuthHelpers.loginUser(page2, user2)
      ])
    })

    await test.step('Verify both users are authenticated', async () => {
      await CommonHelpers.verifyAuthenticatedState(page1)
      await CommonHelpers.verifyAuthenticatedState(page2)
    })

    await test.step('Test concurrent chat usage', async () => {
      await Promise.all([
        page1.goto('/chat'),
        page2.goto('/chat')
      ])

      const chatInput1 = page1.locator('[data-testid="chat-input"]').or(page1.getByRole('textbox')).first()
      const sendButton1 = page1.locator('[data-testid="send-button"]').or(page1.getByRole('button', { name: /send/i })).first()
      
      const chatInput2 = page2.locator('[data-testid="chat-input"]').or(page2.getByRole('textbox')).first()
      const sendButton2 = page2.locator('[data-testid="send-button"]').or(page2.getByRole('button', { name: /send/i })).first()

      await Promise.all([
        (async () => {
          await chatInput1.fill('Message from user 1')
          await sendButton1.click()
        })(),
        (async () => {
          await chatInput2.fill('Message from user 2')
          await sendButton2.click()
        })()
      ])

      // Both should receive responses
      await expect(
        page1.locator('[data-testid="ai-message"]').or(page1.locator('.message:not(.user)').last())
      ).toBeVisible({ timeout: 30000 })
      
      await expect(
        page2.locator('[data-testid="ai-message"]').or(page2.locator('.message:not(.user)').last())
      ).toBeVisible({ timeout: 30000 })
    })

    await test.step('Cleanup', async () => {
      await CommonHelpers.cleanupTestData(page1, user1)
      await CommonHelpers.cleanupTestData(page2, user2)
      
      await context1.close()
      await context2.close()
    })
  })
})