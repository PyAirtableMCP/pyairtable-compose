import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { generateUniqueTestUser } from './fixtures/test-users'

/**
 * Chat Interface Journey Tests
 * 
 * Tests chat functionality using robust selectors that prioritize
 * accessibility and semantic attributes over brittle CSS selectors.
 */
test.describe('Complete Chat Interface Journey', () => {
  let testUser: ReturnType<typeof generateUniqueTestUser>

  test.beforeEach(async ({ page }) => {
    testUser = generateUniqueTestUser()
    await AuthHelpers.registerUser(page, testUser)
    await AuthHelpers.loginUser(page, testUser)
  })

  test.afterEach(async ({ page }) => {
    await CommonHelpers.cleanupTestData(page, testUser)
  })

  test('should complete full chat interaction journey', async ({ page }) => {
    await test.step('Navigate to chat interface', async () => {
      // Navigate to chat using robust selectors
      const chatNavLink = page.locator('[data-testid="chat-nav-link"]')
        .or(page.getByRole('link', { name: /chat|assistant|ai/i }))
        .or(page.locator('a[href*="/chat"], a[href*="/assistant"]'))
        .or(page.getByText(/chat|assistant/i).locator('a'))
        .first()

      if (await chatNavLink.isVisible({ timeout: 3000 })) {
        await chatNavLink.click()
      } else {
        await page.goto('/chat')
      }

      await expect(page).toHaveURL(/\/chat/)
    })

    await test.step('Verify chat interface elements', async () => {
      // Check for chat input using robust selectors
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox', { name: /message|chat|ask/i }))
        .or(page.getByPlaceholder(/ask.*question|type.*message|ask.*anything/i))
        .or(page.locator('input[type="text"], textarea').last())
        .first()

      await expect(chatInput).toBeVisible()

      // Check for send button
      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send|submit/i }))
        .or(page.locator('button[type="submit"]'))
        .or(page.locator('button:has([data-icon="send"]), button:has(.send-icon)'))
        .first()

      await expect(sendButton).toBeVisible()

      // Check for chat messages container
      const messagesContainer = page.locator('[data-testid="chat-messages"]')
        .or(page.locator('[role="log"], [role="feed"]'))
        .or(page.locator('.messages, .chat-history, .conversation'))
        .first()

      await expect(messagesContainer).toBeVisible()
    })

    await test.step('Send a simple chat message', async () => {
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox'))
        .or(page.getByPlaceholder(/ask.*question|type.*message/i))
        .first()

      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .or(page.locator('button[type="submit"]'))
        .first()

      const testMessage = 'Hello, can you help me with my data?'
      
      await chatInput.fill(testMessage)
      await sendButton.click()

      // Verify message appears in chat
      const userMessage = page.locator('[data-testid="user-message"]')
        .or(page.getByText(testMessage))
        .or(page.locator('.message.user, .user-message'))
        .first()

      await expect(userMessage).toBeVisible({ timeout: 5000 })
    })

    await test.step('Wait for and verify AI response', async () => {
      // Look for AI response using robust selectors
      const aiResponse = page.locator('[data-testid="ai-message"]')
        .or(page.locator('[data-testid="assistant-message"]'))
        .or(page.locator('.message.assistant, .ai-message, .bot-message'))
        .or(page.locator('.message:not(.user)').last())
        .first()

      await expect(aiResponse).toBeVisible({ timeout: 30000 })

      // Verify response has content
      const responseText = await aiResponse.textContent()
      expect(responseText?.trim().length).toBeGreaterThan(0)
    })
  })

  test('should handle different types of queries effectively', async ({ page }) => {
    await page.goto('/chat')

    const queries = [
      'What tables do I have in my Airtable base?',
      'Create a formula for calculating engagement rate',
      'Show me records from the last 30 days'
    ]

    for (const query of queries) {
      await test.step(`Handle query: ${query}`, async () => {
        const chatInput = page.locator('[data-testid="chat-input"]')
          .or(page.getByRole('textbox'))
          .or(page.getByPlaceholder(/ask.*question|type.*message/i))
          .first()

        const sendButton = page.locator('[data-testid="send-button"]')
          .or(page.getByRole('button', { name: /send/i }))
          .or(page.locator('button[type="submit"]'))
          .first()

        await chatInput.fill(query)
        await sendButton.click()

        // Wait for response
        const aiResponse = page.locator('[data-testid="ai-message"]')
          .or(page.locator('.message:not(.user)').last())
          .first()

        await expect(aiResponse).toBeVisible({ timeout: 45000 })
      })
    }
  })

  test('should maintain context across conversation', async ({ page }) => {
    await page.goto('/chat')

    await test.step('Send first message', async () => {
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox'))
        .first()

      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .first()

      await chatInput.fill('I have a table called Posts with engagement data')
      await sendButton.click()

      await expect(
        page.locator('[data-testid="ai-message"]').or(page.locator('.message:not(.user)').last())
      ).toBeVisible({ timeout: 30000 })
    })

    await test.step('Send follow-up message referencing context', async () => {
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox'))
        .first()

      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .first()

      await chatInput.fill('Can you create a formula to calculate the average?')
      await sendButton.click()

      // The AI should understand "the average" refers to engagement data from Posts table
      const contextResponse = page.locator('[data-testid="ai-message"]')
        .or(page.locator('.message:not(.user)').last())
        .first()

      await expect(contextResponse).toBeVisible({ timeout: 30000 })
      
      const responseText = await contextResponse.textContent()
      expect(responseText).toMatch(/posts|engagement|average/i)
    })
  })

  test('should handle empty and invalid inputs', async ({ page }) => {
    await page.goto('/chat')

    const chatInput = page.locator('[data-testid="chat-input"]')
      .or(page.getByRole('textbox'))
      .first()

    const sendButton = page.locator('[data-testid="send-button"]')
      .or(page.getByRole('button', { name: /send/i }))
      .first()

    await test.step('Handle empty input', async () => {
      // Try to send empty message
      await chatInput.fill('')
      
      // Button should be disabled or click should not send message
      const isDisabled = await sendButton.isDisabled()
      if (!isDisabled) {
        await sendButton.click()
        
        // Should not create a user message for empty input
        const userMessages = page.locator('[data-testid="user-message"]')
        const initialCount = await userMessages.count()
        
        await page.waitForTimeout(2000)
        const newCount = await userMessages.count()
        expect(newCount).toBe(initialCount)
      }
    })

    await test.step('Handle very long input', async () => {
      const longMessage = 'A'.repeat(5000)
      await chatInput.fill(longMessage)
      
      // Should either truncate or show validation message
      const inputValue = await chatInput.inputValue()
      if (inputValue.length > 1000) {
        // If not truncated, should still handle gracefully
        await sendButton.click()
        await expect(
          page.locator('[data-testid="user-message"]').last()
        ).toBeVisible({ timeout: 5000 })
      }
    })
  })

  test('should validate response performance', async ({ page }) => {
    await page.goto('/chat')

    const chatInput = page.locator('[data-testid="chat-input"]')
      .or(page.getByRole('textbox'))
      .first()

    const sendButton = page.locator('[data-testid="send-button"]')
      .or(page.getByRole('button', { name: /send/i }))
      .first()

    const startTime = Date.now()
    
    await chatInput.fill('Hello')
    await sendButton.click()

    // Wait for AI response
    await expect(
      page.locator('[data-testid="ai-message"]').or(page.locator('.message:not(.user)').last())
    ).toBeVisible({ timeout: 30000 })

    const responseTime = Date.now() - startTime

    // Simple queries should respond within 15 seconds
    expect(responseTime).toBeLessThan(15000)
  })

  test('should handle error scenarios gracefully', async ({ page }) => {
    await page.goto('/chat')

    // Mock network error
    await page.route('**/api/chat/**', route => {
      route.abort('failed')
    })

    const chatInput = page.locator('[data-testid="chat-input"]')
      .or(page.getByRole('textbox'))
      .first()

    const sendButton = page.locator('[data-testid="send-button"]')
      .or(page.getByRole('button', { name: /send/i }))
      .first()

    await chatInput.fill('This should trigger an error')
    await sendButton.click()

    // Should show error message
    const errorMessage = page.locator('[data-testid="error-message"]')
      .or(page.getByText(/error|failed|something.*wrong/i))
      .or(page.locator('.error, .alert-error'))
      .first()

    await expect(errorMessage).toBeVisible({ timeout: 10000 })
  })

  test('should work in different viewport sizes', async ({ page }) => {
    const viewports = [
      { width: 1920, height: 1080 }, // Desktop
      { width: 768, height: 1024 },  // Tablet
      { width: 375, height: 667 }    // Mobile
    ]

    for (const viewport of viewports) {
      await test.step(`Test viewport ${viewport.width}x${viewport.height}`, async () => {
        await page.setViewportSize(viewport)
        await page.goto('/chat')

        // Chat input should be visible and usable
        const chatInput = page.locator('[data-testid="chat-input"]')
          .or(page.getByRole('textbox'))
          .first()

        await expect(chatInput).toBeVisible()

        // Send button should be accessible
        const sendButton = page.locator('[data-testid="send-button"]')
          .or(page.getByRole('button', { name: /send/i }))
          .first()

        await expect(sendButton).toBeVisible()

        // Messages container should be visible
        const messagesContainer = page.locator('[data-testid="chat-messages"]')
          .or(page.locator('[role="log"], [role="feed"]'))
          .or(page.locator('.messages, .chat-history'))
          .first()

        await expect(messagesContainer).toBeVisible()
      })
    }
  })

  test('should handle keyboard shortcuts and accessibility', async ({ page }) => {
    await page.goto('/chat')

    const chatInput = page.locator('[data-testid="chat-input"]')
      .or(page.getByRole('textbox'))
      .first()

    await test.step('Test Enter key to send', async () => {
      await chatInput.fill('Test message via Enter key')
      await chatInput.press('Enter')

      await expect(
        page.locator('[data-testid="user-message"]').last()
      ).toBeVisible({ timeout: 5000 })
    })

    await test.step('Test Shift+Enter for new line', async () => {
      // Clear input
      await chatInput.fill('')
      
      await chatInput.fill('Line 1')
      await chatInput.press('Shift+Enter')
      await chatInput.type('Line 2')

      const inputValue = await chatInput.inputValue()
      expect(inputValue).toContain('\n')
    })

    await test.step('Test keyboard navigation', async () => {
      // Tab should navigate through interactive elements
      await page.keyboard.press('Tab')
      await expect(chatInput).toBeFocused()
    })
  })

  test('should preserve chat across page navigation', async ({ page }) => {
    await page.goto('/chat')

    const chatInput = page.locator('[data-testid="chat-input"]')
      .or(page.getByRole('textbox'))
      .first()

    const sendButton = page.locator('[data-testid="send-button"]')
      .or(page.getByRole('button', { name: /send/i }))
      .first()

    // Send a message
    await chatInput.fill('Test message for persistence')
    await sendButton.click()

    await expect(
      page.locator('[data-testid="user-message"]').last()
    ).toBeVisible({ timeout: 5000 })

    // Navigate away and back
    await page.goto('/dashboard')
    await page.goto('/chat')

    // Message should still be there
    await expect(
      page.getByText('Test message for persistence')
    ).toBeVisible()
  })

  test('should handle session timeout during chat', async ({ page }) => {
    await page.goto('/chat')

    // Simulate session timeout
    await AuthHelpers.handleSessionExpiry(page)

    // Should redirect to login
    await expect(page).toHaveURL(/\/auth\/login/)
  })

  test('should display helpful suggestions and examples', async ({ page }) => {
    await page.goto('/chat')

    // Check for example queries or suggestions
    const suggestions = page.locator('[data-testid="chat-suggestions"]')
      .or(page.locator('.suggestions, .examples, .prompts'))
      .or(page.getByText(/example|suggestion|try.*asking/i))
      .first()

    if (await suggestions.isVisible({ timeout: 3000 })) {
      await expect(suggestions).toBeVisible()
      
      // If suggestions are clickable, test them
      const suggestionItem = suggestions.locator('button, a, .clickable').first()
      if (await suggestionItem.isVisible({ timeout: 2000 })) {
        await suggestionItem.click()
        
        // Should populate chat input or send message
        const chatInput = page.locator('[data-testid="chat-input"]')
          .or(page.getByRole('textbox'))
          .first()
        
        const inputValue = await chatInput.inputValue()
        expect(inputValue.length).toBeGreaterThan(0)
      }
    }
  })
})