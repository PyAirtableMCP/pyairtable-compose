import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { ChatHelpers } from './helpers/chat-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { testUsers, testData } from './fixtures/test-users'

test.describe('Complete Chat Interface User Journey', () => {
  
  test.beforeEach(async ({ page }) => {
    // Login before each test
    await AuthHelpers.loginUser(page, testUsers.standard)
    
    // Navigate to chat interface
    await page.goto('/chat')
    await ChatHelpers.waitForChatInterface(page)
  })

  test('should complete full chat interaction journey', async ({ page }) => {
    // Step 1: Verify chat interface loads correctly
    await expect(page.getByText(/PyAirtable Assistant/i)).toBeVisible()
    await expect(page.getByPlaceholder(/Ask anything about your data/i)).toBeVisible()
    
    // Verify connection status
    await ChatHelpers.verifyConnectionStatus(page, 'connected')

    // Step 2: Send initial greeting and get response
    const greetingMessage = 'Hello! Can you help me understand my data?'
    await ChatHelpers.sendMessage(page, greetingMessage)
    
    // Wait for AI response
    const response1 = await ChatHelpers.waitForAIResponse(page)
    const responseText1 = await response1.textContent()
    expect(responseText1).toMatch(/help|assist|data|airtable/i)

    // Step 3: Ask about specific data analysis
    const dataQuery = testData.chatMessages.airtableQuery
    await ChatHelpers.sendMessage(page, dataQuery)
    
    const response2 = await ChatHelpers.waitForAIResponse(page)
    const responseText2 = await response2.textContent()
    expect(responseText2).toMatch(/table|records|data|posts/i)

    // Step 4: Request formula creation
    const formulaRequest = testData.chatMessages.formulaRequest
    await ChatHelpers.sendMessage(page, formulaRequest)
    
    const response3 = await ChatHelpers.waitForAIResponse(page)
    const responseText3 = await response3.textContent()
    expect(responseText3).toMatch(/formula|calculation|engagement|rate/i)

    // Step 5: Send complex analysis request
    const complexQuery = testData.chatMessages.complex
    await ChatHelpers.sendMessage(page, complexQuery)
    
    const response4 = await ChatHelpers.waitForAIResponse(page, 45000) // Longer timeout for complex queries
    const responseText4 = await response4.textContent()
    expect(responseText4).toMatch(/analysis|performance|social media|workflow/i)

    // Step 6: Verify chat history is maintained
    await page.reload()
    await ChatHelpers.waitForChatInterface(page)
    
    // All messages should still be visible
    await expect(page.getByText(greetingMessage)).toBeVisible()
    await expect(page.getByText(dataQuery)).toBeVisible()
    await expect(page.getByText(formulaRequest)).toBeVisible()
  })

  test('should handle different types of queries effectively', async ({ page }) => {
    // Test data analysis query
    const analysisResponse = await ChatHelpers.testAirtableQuery(page, 'Show me my top performing posts from last month')
    expect(await analysisResponse.textContent()).toMatch(/posts|performance|data|records/i)

    // Test formula creation
    const formulaResponse = await ChatHelpers.testFormulaCreation(page, 'Create a formula to calculate conversion rate')
    expect(await formulaResponse.textContent()).toMatch(/formula|conversion|rate|calculation/i)

    // Test automation request
    await ChatHelpers.sendMessage(page, 'Help me set up an automation for new leads')
    const automationResponse = await ChatHelpers.waitForAIResponse(page)
    expect(await automationResponse.textContent()).toMatch(/automation|workflow|leads|trigger/i)

    // Test general help query
    await ChatHelpers.sendMessage(page, 'How do I export my data?')
    const helpResponse = await ChatHelpers.waitForAIResponse(page)
    expect(await helpResponse.textContent()).toMatch(/export|data|download|format/i)
  })

  test('should handle real-time features correctly', async ({ page }) => {
    // Verify WebSocket or SSE connection
    await ChatHelpers.verifyConnectionStatus(page, 'connected')
    
    // Send message and verify real-time streaming
    await ChatHelpers.sendMessage(page, 'Explain how Airtable formulas work')
    
    // Look for streaming indicators
    const streamingIndicator = page.locator('.animate-pulse, [data-testid="streaming"]')
    if (await streamingIndicator.isVisible({ timeout: 2000 }).catch(() => false)) {
      // If streaming is implemented, verify it works
      await expect(streamingIndicator).toBeVisible()
      await expect(streamingIndicator).not.toBeVisible({ timeout: 30000 })
    }
    
    // Verify final response is complete
    await ChatHelpers.waitForAIResponse(page)
  })

  test('should maintain chat context across conversation', async ({ page }) => {
    // Start conversation about a specific table
    await ChatHelpers.sendMessage(page, 'I want to analyze my Customer table')
    const response1 = await ChatHelpers.waitForAIResponse(page)
    
    // Follow up with context-dependent question
    await ChatHelpers.sendMessage(page, 'What are the top 5 customers by revenue?')
    const response2 = await ChatHelpers.waitForAIResponse(page)
    
    // The AI should remember we're talking about the Customer table
    const responseText = await response2.textContent()
    expect(responseText).toMatch(/customer|revenue|top/i)
    
    // Another context-dependent follow-up
    await ChatHelpers.sendMessage(page, 'Create a view for just the high-value ones')
    const response3 = await ChatHelpers.waitForAIResponse(page)
    
    const responseText3 = await response3.textContent()
    expect(responseText3).toMatch(/view|high-value|filter|customer/i)
  })

  test('should handle error scenarios gracefully', async ({ page }) => {
    // Test connection loss scenario
    await page.route('**/api/chat/**', route => route.abort())
    
    const errorResponse = await ChatHelpers.testErrorScenario(page, 'This should trigger an error')
    await expect(errorResponse).toBeVisible()
    
    // Restore connection
    await page.unroute('**/api/chat/**')
    
    // Verify recovery
    await ChatHelpers.sendMessage(page, 'Are you back online?')
    await ChatHelpers.waitForAIResponse(page)
  })

  test('should handle empty and invalid inputs', async ({ page }) => {
    const messageInput = page.getByPlaceholder(/Ask anything about your data/i)
    const sendButton = page.getByRole('button', { name: /send/i })
    
    // Try to send empty message
    await messageInput.click()
    if (await sendButton.isVisible()) {
      await expect(sendButton).toBeDisabled()
    }
    
    // Try very long message
    const longMessage = 'A'.repeat(5000)
    await messageInput.fill(longMessage)
    
    // Should either truncate or show warning
    const currentLength = await messageInput.inputValue()
    expect(currentLength.length).toBeLessThanOrEqual(2000) // Based on chat interface limit
  })

  test('should support keyboard shortcuts and accessibility', async ({ page }) => {
    const messageInput = page.getByPlaceholder(/Ask anything about your data/i)
    
    // Test Enter to send
    await messageInput.fill('Test message via Enter key')
    await messageInput.press('Enter')
    
    await expect(page.getByText('Test message via Enter key')).toBeVisible()
    await ChatHelpers.waitForAIResponse(page)
    
    // Test Shift+Enter for new line (if implemented)
    await messageInput.fill('Line 1')
    await messageInput.press('Shift+Enter')
    await messageInput.type('Line 2')
    
    const inputValue = await messageInput.inputValue()
    expect(inputValue).toContain('Line 1')
    expect(inputValue).toContain('Line 2')
    
    // Test accessibility
    await ChatHelpers.verifyAccessibility(page)
  })

  test('should handle file uploads if supported', async ({ page }) => {
    // Check if file upload is available
    const fileUploadSupported = await ChatHelpers.testFileUpload(page, 'test-data.csv')
    
    if (fileUploadSupported) {
      // Verify file processing
      await expect(page.getByText(/file uploaded|processing file/i)).toBeVisible()
      
      // Send follow-up message about the file
      await ChatHelpers.sendMessage(page, 'Can you analyze this uploaded file?')
      const response = await ChatHelpers.waitForAIResponse(page)
      
      expect(await response.textContent()).toMatch(/file|data|analysis|csv/i)
    } else {
      console.log('File upload not supported in current implementation')
    }
  })

  test('should measure and validate response performance', async ({ page }) => {
    // Test response time for simple query
    const simpleResponseTime = await ChatHelpers.measureResponseTime(page, 'What is Airtable?')
    expect(simpleResponseTime).toBeLessThan(10000) // Should respond within 10 seconds
    
    // Test response time for complex query
    const complexResponseTime = await ChatHelpers.measureResponseTime(page, 
      'Analyze my sales data, create a formula for monthly growth rate, and suggest automation workflows')
    expect(complexResponseTime).toBeLessThan(45000) // Complex queries may take longer
    
    console.log(`Simple query response time: ${simpleResponseTime}ms`)
    console.log(`Complex query response time: ${complexResponseTime}ms`)
  })

  test('should handle concurrent messages appropriately', async ({ page }) => {
    const messages = [
      'What is my total revenue?',
      'Show me top customers',
      'Create a sales report'
    ]
    
    // This tests the system's ability to handle rapid successive messages
    await ChatHelpers.testConcurrentMessages(page, messages)
    
    // Verify all responses are received
    // (Implementation may handle this by queuing or showing "please wait" messages)
    for (const message of messages) {
      await expect(page.getByText(message)).toBeVisible()
    }
  })

  test('should support chat features in different viewport sizes', async ({ page }) => {
    // Test responsive design
    await CommonHelpers.testResponsiveDesign(page)
    
    // Verify chat interface works on mobile
    await page.setViewportSize({ width: 375, height: 667 })
    await ChatHelpers.waitForChatInterface(page)
    
    await ChatHelpers.sendMessage(page, 'Mobile test message')
    await ChatHelpers.waitForAIResponse(page)
    
    // Reset to desktop
    await page.setViewportSize({ width: 1920, height: 1080 })
  })

  test('should persist chat across page navigation', async ({ page }) => {
    // Send a message
    const testMessage = 'Test persistence message'
    await ChatHelpers.sendMessage(page, testMessage)
    await ChatHelpers.waitForAIResponse(page)
    
    // Navigate away and back
    await page.goto('/dashboard')
    await CommonHelpers.waitForPageLoad(page)
    
    await page.goto('/chat')
    await ChatHelpers.waitForChatInterface(page)
    
    // Message should still be visible
    await expect(page.getByText(testMessage)).toBeVisible()
  })

  test('should handle session timeout during chat', async ({ page }) => {
    // Start a conversation
    await ChatHelpers.sendMessage(page, 'Start of conversation')
    await ChatHelpers.waitForAIResponse(page)
    
    // Simulate session expiry
    await AuthHelpers.handleSessionExpiry(page)
    
    // Try to send another message
    const messageInput = page.getByPlaceholder(/Ask anything about your data/i)
    await messageInput.fill('Message after session expiry')
    
    // Should either redirect to login or show auth error
    try {
      await messageInput.press('Enter')
      await CommonHelpers.verifyErrorMessage(page, /session expired|please log in|authentication/i)
    } catch (error) {
      // Or it might redirect to login
      await expect(page).toHaveURL(/\/auth\/login/)
    }
  })

  test('should provide helpful suggestions and examples', async ({ page }) => {
    // Look for example prompts or suggestions
    const exampleElements = page.locator('[data-testid="example-prompt"], .example-prompt, button:has-text("Try")')
    
    if (await exampleElements.first().isVisible({ timeout: 2000 }).catch(() => false)) {
      // Click on an example
      await exampleElements.first().click()
      
      // Should populate the input or send the example
      const messageInput = page.getByPlaceholder(/Ask anything about your data/i)
      const inputValue = await messageInput.inputValue()
      
      expect(inputValue.length).toBeGreaterThan(0)
    }
    
    // Verify help text or tooltips are available
    const helpElements = page.locator('[data-testid="help"], .help-text, [title]')
    if (await helpElements.first().isVisible({ timeout: 2000 }).catch(() => false)) {
      await expect(helpElements.first()).toBeVisible()
    }
  })
})