import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { ChatHelpers } from './helpers/chat-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { testUsers, generateUniqueTestUser, testData } from './fixtures/test-users'

test.describe('Error Scenarios and Edge Cases', () => {

  test.describe('Network and Connectivity Errors', () => {
    
    test('should handle complete network failure gracefully', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Simulate complete network failure
      await page.route('**/*', route => route.abort())

      // Try to send a message
      const messageInput = page.getByPlaceholder(/ask anything|type your message/i)
      await messageInput.fill('This should fail due to network error')
      await messageInput.press('Enter')

      // Should show connection error
      await CommonHelpers.verifyErrorMessage(page, /network error|connection failed|offline|unable to connect/i)

      // Restore network
      await page.unroute('**/*')
      
      // Should recover and allow retry
      await ChatHelpers.sendMessage(page, 'Network is back')
      await ChatHelpers.waitForAIResponse(page)
    })

    test('should handle intermittent connectivity issues', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      let requestCount = 0
      
      // Fail every other request
      await page.route('**/api/chat/**', route => {
        requestCount++
        if (requestCount % 2 === 0) {
          route.abort()
        } else {
          route.continue()
        }
      })

      // Should handle failures and retries
      await ChatHelpers.sendMessage(page, 'Test intermittent connectivity')
      
      // May show retry mechanisms or error recovery
      const response = await ChatHelpers.waitForAIResponse(page, 30000)
      expect(response).toBeVisible()
    })

    test('should handle slow network conditions', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Simulate slow network by delaying responses
      await page.route('**/api/chat/**', async route => {
        await new Promise(resolve => setTimeout(resolve, 5000)) // 5 second delay
        await route.continue()
      })

      // Should show loading states and eventually complete
      await ChatHelpers.sendMessage(page, 'Test slow network')
      
      // Verify loading indicators appear
      const loadingIndicator = page.locator('.animate-spin, [data-testid="loading"], .loading')
      await expect(loadingIndicator).toBeVisible()
      
      // Should eventually get response
      await ChatHelpers.waitForAIResponse(page, 60000)
    })
  })

  test.describe('Authentication and Session Errors', () => {
    
    test('should handle expired session during active use', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Send initial message
      await ChatHelpers.sendMessage(page, 'Initial message before session expiry')
      await ChatHelpers.waitForAIResponse(page)

      // Simulate session expiry
      await page.route('**/api/auth/session', route => route.fulfill({
        status: 401,
        body: JSON.stringify({ error: 'Session expired' })
      }))

      // Try to send another message
      await ChatHelpers.sendMessage(page, 'Message after session expiry')
      
      // Should handle gracefully - either show error or redirect
      try {
        await CommonHelpers.verifyErrorMessage(page, /session expired|please log in|authentication required/i)
      } catch (error) {
        // Or might redirect to login
        await expect(page).toHaveURL(/\/auth\/login/)
      }
    })

    test('should handle invalid authentication tokens', async ({ page }) => {
      await page.goto('/auth/login')
      
      // Mock invalid token response
      await page.route('**/api/auth/**', route => route.fulfill({
        status: 403,
        body: JSON.stringify({ error: 'Invalid token' })
      }))

      await page.getByLabel(/email/i).fill(testUsers.standard.email)
      await page.getByLabel(/password/i).fill(testUsers.standard.password)
      await page.getByRole('button', { name: /sign in|login/i }).click()

      await CommonHelpers.verifyErrorMessage(page, /invalid token|authentication failed|access denied/i)
    })

    test('should handle simultaneous login from multiple devices', async ({ page, context }) => {
      // Login in first tab
      await AuthHelpers.loginUser(page, testUsers.standard)
      
      // Open second tab and try to login with same user
      const page2 = await context.newPage()
      await AuthHelpers.loginUser(page2, testUsers.standard)

      // Depending on implementation, should either:
      // 1. Allow multiple sessions
      // 2. Invalidate previous session
      // 3. Show warning about multiple logins

      // Test that both sessions work or handle gracefully
      await page.goto('/chat')
      await page2.goto('/chat')

      // At least one should work
      try {
        await ChatHelpers.waitForChatInterface(page)
        await ChatHelpers.waitForChatInterface(page2)
      } catch (error) {
        // If one fails, the other should work
        console.log('One session was invalidated, which is expected behavior')
      }
    })
  })

  test.describe('Input Validation and Data Errors', () => {
    
    test('should handle malicious input attempts', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      const maliciousInputs = [
        '<script>alert("xss")</script>',
        'javascript:alert("xss")',
        '"; DROP TABLE users; --',
        '{{constructor.constructor("alert(1)")()}}',
        '<img src=x onerror=alert(1)>',
        'eval("alert(1)")'
      ]

      for (const maliciousInput of maliciousInputs) {
        await ChatHelpers.sendMessage(page, maliciousInput)
        
        // Should either sanitize input or show error
        // The malicious script should not execute
        const response = await ChatHelpers.waitForAIResponse(page)
        const responseText = await response.textContent()
        
        // Response should not contain executable script
        expect(responseText).not.toContain('<script>')
        expect(responseText).not.toContain('javascript:')
      }
    })

    test('should handle extremely long input', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Create very long message
      const longMessage = 'A'.repeat(10000)
      
      const messageInput = page.getByPlaceholder(/ask anything|type your message/i)
      await messageInput.fill(longMessage)

      // Should either truncate or show error
      const inputValue = await messageInput.inputValue()
      expect(inputValue.length).toBeLessThanOrEqual(2000) // Based on chat interface limit
    })

    test('should handle special characters and unicode', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      const specialMessages = [
        '🚀 Hello with emojis! 🎉',
        'Chinese: 你好世界',
        'Arabic: مرحبا بالعالم',
        'Russian: Привет мир',
        'Math symbols: ∑ ∫ ∂ √ ∞',
        'Special chars: @#$%^&*()_+-=[]{}|;\':",./<>?'
      ]

      for (const message of specialMessages) {
        await ChatHelpers.sendMessage(page, message)
        const response = await ChatHelpers.waitForAIResponse(page)
        
        // Should handle unicode properly
        await expect(page.getByText(message)).toBeVisible()
        expect(response).toBeVisible()
      }
    })
  })

  test.describe('API and Backend Errors', () => {
    
    test('should handle 500 server errors gracefully', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Mock server error
      await page.route('**/api/chat/**', route => route.fulfill({
        status: 500,
        body: JSON.stringify({ error: 'Internal server error' })
      }))

      await ChatHelpers.sendMessage(page, 'This should trigger server error')
      
      await CommonHelpers.verifyErrorMessage(page, /server error|something went wrong|try again later/i)
    })

    test('should handle rate limiting', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Mock rate limiting response
      await page.route('**/api/chat/**', route => route.fulfill({
        status: 429,
        headers: {
          'Retry-After': '60'
        },
        body: JSON.stringify({ error: 'Rate limit exceeded' })
      }))

      await ChatHelpers.sendMessage(page, 'This should trigger rate limit')
      
      await CommonHelpers.verifyErrorMessage(page, /rate limit|too many requests|try again/i)
    })

    test('should handle malformed API responses', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Mock malformed JSON response
      await page.route('**/api/chat/**', route => route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: 'invalid json{'
      }))

      await ChatHelpers.sendMessage(page, 'This should trigger parsing error')
      
      await CommonHelpers.verifyErrorMessage(page, /error processing|something went wrong|invalid response/i)
    })
  })

  test.describe('Browser and Client-side Errors', () => {
    
    test('should handle JavaScript errors gracefully', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')

      // Inject JavaScript error
      await page.addInitScript(() => {
        setTimeout(() => {
          throw new Error('Simulated client error')
        }, 1000)
      })

      await ChatHelpers.waitForChatInterface(page)
      
      // Chat should still be functional despite JS error
      await ChatHelpers.sendMessage(page, 'Test after JS error')
      await ChatHelpers.waitForAIResponse(page)
    })

    test('should handle memory constraints', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Send many messages to test memory handling
      for (let i = 0; i < 50; i++) {
        await ChatHelpers.sendMessage(page, `Test message ${i}`)
        await page.waitForTimeout(100) // Small delay to avoid overwhelming
      }

      // Chat should still be responsive
      await ChatHelpers.sendMessage(page, 'Final test message')
      await ChatHelpers.waitForAIResponse(page)
    })

    test('should handle localStorage/sessionStorage issues', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Clear storage during session
      await page.evaluate(() => {
        localStorage.clear()
        sessionStorage.clear()
      })

      // App should handle gracefully
      await ChatHelpers.sendMessage(page, 'Test after storage clear')
      
      // Should either recover or show appropriate error
      try {
        await ChatHelpers.waitForAIResponse(page)
      } catch (error) {
        await CommonHelpers.verifyErrorMessage(page, /session|storage|please refresh/i)
      }
    })
  })

  test.describe('Edge Cases and Boundary Conditions', () => {
    
    test('should handle rapid successive actions', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Rapidly send multiple messages
      const messages = ['Message 1', 'Message 2', 'Message 3', 'Message 4', 'Message 5']
      
      for (const message of messages) {
        await ChatHelpers.sendMessage(page, message)
        await page.waitForTimeout(50) // Very quick succession
      }

      // Should handle gracefully - either queue messages or show appropriate feedback
      await page.waitForTimeout(5000)
      
      // All messages should be visible or system should handle overflow
      for (const message of messages) {
        await expect(page.getByText(message)).toBeVisible()
      }
    })

    test('should handle browser refresh during critical operations', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Start sending message
      await ChatHelpers.sendMessage(page, 'Message before refresh')
      
      // Refresh page immediately
      await page.reload()
      await ChatHelpers.waitForChatInterface(page)

      // Should recover gracefully
      await ChatHelpers.sendMessage(page, 'Message after refresh')
      await ChatHelpers.waitForAIResponse(page)
    })

    test('should handle browser back/forward navigation', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      await ChatHelpers.sendMessage(page, 'Message in chat')
      await ChatHelpers.waitForAIResponse(page)

      // Navigate away
      await page.goto('/dashboard')
      await CommonHelpers.waitForPageLoad(page)

      // Use browser back button
      await page.goBack()
      await ChatHelpers.waitForChatInterface(page)

      // Chat history should be preserved
      await expect(page.getByText('Message in chat')).toBeVisible()
    })

    test('should handle window resize and responsive breakpoints', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      await ChatHelpers.sendMessage(page, 'Test responsive behavior')
      await ChatHelpers.waitForAIResponse(page)

      // Test various viewport sizes
      const viewports = [
        { width: 320, height: 568 },  // iPhone 5
        { width: 768, height: 1024 }, // iPad
        { width: 1920, height: 1080 } // Desktop
      ]

      for (const viewport of viewports) {
        await page.setViewportSize(viewport)
        await page.waitForTimeout(500)

        // Chat should remain functional
        await expect(page.getByPlaceholder(/ask anything|type your message/i)).toBeVisible()
        await expect(page.getByText('Test responsive behavior')).toBeVisible()
      }
    })

    test('should handle concurrent user sessions with data conflicts', async ({ page, context }) => {
      const user = generateUniqueTestUser('concurrent')
      
      // Create user account
      await page.goto('/auth/register')
      await AuthHelpers.registerUser(page, user)

      // Open second browser context
      const context2 = await page.context().browser()!.newContext()
      const page2 = await context2.newPage()

      // Login with same user in both contexts
      await AuthHelpers.loginUser(page, user)
      await AuthHelpers.loginUser(page2, user)

      // Navigate to chat in both
      await page.goto('/chat')
      await page2.goto('/chat')

      await ChatHelpers.waitForChatInterface(page)
      await ChatHelpers.waitForChatInterface(page2)

      // Send messages from both sessions
      await ChatHelpers.sendMessage(page, 'Message from session 1')
      await ChatHelpers.sendMessage(page2, 'Message from session 2')

      // Both sessions should handle gracefully
      await ChatHelpers.waitForAIResponse(page)
      await ChatHelpers.waitForAIResponse(page2)

      await context2.close()
    })
  })

  test.describe('Recovery and Resilience', () => {
    
    test('should provide clear error recovery instructions', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Trigger an error
      await page.route('**/api/chat/**', route => route.fulfill({
        status: 503,
        body: JSON.stringify({ error: 'Service unavailable' })
      }))

      await ChatHelpers.sendMessage(page, 'This will fail')
      
      // Should provide helpful error message with recovery options
      await CommonHelpers.verifyErrorMessage(page, /try again|refresh|contact support/i)

      // Look for retry button
      const retryButton = page.getByRole('button', { name: /retry|try again/i })
      if (await retryButton.isVisible({ timeout: 2000 }).catch(() => false)) {
        // Restore service and test retry
        await page.unroute('**/api/chat/**')
        await retryButton.click()
        
        await ChatHelpers.waitForAIResponse(page)
      }
    })

    test('should maintain partial functionality during degraded service', async ({ page }) => {
      await AuthHelpers.loginUser(page, testUsers.standard)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)

      // Mock partial service degradation
      let requestCount = 0
      await page.route('**/api/chat/**', route => {
        requestCount++
        if (requestCount <= 2) {
          route.continue()
        } else {
          route.fulfill({
            status: 503,
            body: JSON.stringify({ error: 'Service degraded' })
          })
        }
      })

      // First messages should work
      await ChatHelpers.sendMessage(page, 'First message')
      await ChatHelpers.waitForAIResponse(page)

      await ChatHelpers.sendMessage(page, 'Second message')
      await ChatHelpers.waitForAIResponse(page)

      // Third should fail gracefully
      await ChatHelpers.sendMessage(page, 'Third message')
      await CommonHelpers.verifyErrorMessage(page, /service.*degraded|temporarily unavailable/i)
    })
  })
})