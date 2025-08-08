import { Page, expect, Locator } from '@playwright/test'

/**
 * Chat interface helper functions for E2E tests
 */
export class ChatHelpers {
  
  /**
   * Send a message in the chat interface
   */
  static async sendMessage(page: Page, message: string) {
    // Wait for chat interface to load
    await this.waitForChatInterface(page)
    
    // Find message input
    const messageInput = page.getByPlaceholder(/Ask anything about your data/i)
    await expect(messageInput).toBeVisible()
    
    // Type message
    await messageInput.fill(message)
    
    // Send message (look for send button or press Enter)
    const sendButton = page.getByRole('button', { name: /send/i }).or(page.locator('[data-testid="send-button"]'))
    
    if (await sendButton.isVisible()) {
      await sendButton.click()
    } else {
      await messageInput.press('Enter')
    }
    
    // Wait for message to appear in chat
    await expect(page.getByText(message)).toBeVisible({ timeout: 5000 })
  }

  /**
   * Wait for AI response to complete
   */
  static async waitForAIResponse(page: Page, timeout: number = 30000) {
    // Wait for typing indicator to disappear or response to complete
    const typingIndicator = page.locator('.animate-bounce, [data-testid="typing-indicator"]')
    const streamingIndicator = page.locator('.animate-pulse')
    
    try {
      // Wait for typing/streaming indicators to appear and then disappear
      await expect(typingIndicator.or(streamingIndicator)).toBeVisible({ timeout: 5000 })
      await expect(typingIndicator.or(streamingIndicator)).not.toBeVisible({ timeout })
    } catch (error) {
      // If no indicators found, wait for any new message from assistant
      await page.waitForTimeout(2000) // Give some time for response
    }
    
    // Verify response is present - look for bot messages in the chat
    const assistantMessages = page.locator('div:has(svg[data-id="Bot"])').last()
    await expect(assistantMessages).toBeVisible({ timeout: 5000 })
    
    return assistantMessages
  }

  /**
   * Verify chat interface is loaded and ready
   */
  static async waitForChatInterface(page: Page) {
    // Wait for PyAirtable Assistant heading
    await expect(page.getByText(/PyAirtable Assistant/i)).toBeVisible({ timeout: 10000 })
    
    // Wait for message input to be ready
    const messageInput = page.getByPlaceholder(/Ask anything about your data/i)
    await expect(messageInput).toBeVisible()
    await expect(messageInput).toBeEnabled()
    
    // Wait for initial welcome message or chat history to load
    await page.waitForTimeout(1000)
  }

  /**
   * Verify connection status
   */
  static async verifyConnectionStatus(page: Page, expectedStatus: 'connected' | 'disconnected' | 'connecting') {
    // Look for connection status badge in the chat interface
    const statusBadge = page.locator('[class*="Badge"]').filter({ hasText: new RegExp(expectedStatus, 'i') })
    
    if (await statusBadge.isVisible()) {
      await expect(statusBadge).toContainText(expectedStatus, { ignoreCase: true })
    }
    
    // Also check for connection indicators in the UI
    if (expectedStatus === 'connected') {
      // Should not show connection errors
      await expect(page.getByText(/connection error|disconnected|offline/i)).not.toBeVisible()
    }
  }

  /**
   * Test specific chat functionality
   */
  static async testAirtableQuery(page: Page, query: string) {
    await this.sendMessage(page, query)
    const response = await this.waitForAIResponse(page)
    
    // Verify response contains data-related content
    const responseText = await response.textContent()
    expect(responseText).toMatch(/table|record|data|field|column/i)
    
    return response
  }

  /**
   * Test formula creation request
   */
  static async testFormulaCreation(page: Page, request: string) {
    await this.sendMessage(page, request)
    const response = await this.waitForAIResponse(page)
    
    // Verify response contains formula-related content
    const responseText = await response.textContent()
    expect(responseText).toMatch(/formula|calculation|function|field|expression/i)
    
    return response
  }

  /**
   * Clear chat history
   */
  static async clearChatHistory(page: Page) {
    // Look for clear/reset button
    const clearButton = page.getByRole('button', { name: /clear|reset|new chat/i })
    
    if (await clearButton.isVisible()) {
      await clearButton.click()
      
      // Confirm if dialog appears
      const confirmButton = page.getByRole('button', { name: /confirm|yes|clear/i })
      if (await confirmButton.isVisible({ timeout: 2000 })) {
        await confirmButton.click()
      }
      
      // Verify chat is cleared
      await expect(page.locator('.chat-message, .message')).toHaveCount(1) // Only welcome message
    }
  }

  /**
   * Test error handling in chat
   */
  static async testErrorScenario(page: Page, errorTrigger: string) {
    await this.sendMessage(page, errorTrigger)
    
    // Wait for error message to appear
    const errorMessage = page.locator('.error-message, .message-error, [data-testid="error-message"]')
    await expect(errorMessage).toBeVisible({ timeout: 10000 })
    
    return errorMessage
  }

  /**
   * Verify chat message history persistence
   */
  static async verifyChatPersistence(page: Page, sentMessage: string) {
    // Refresh page
    await page.reload()
    await this.waitForChatInterface(page)
    
    // Verify message is still visible
    await expect(page.getByText(sentMessage)).toBeVisible()
  }

  /**
   * Test file upload in chat (if supported)
   */
  static async testFileUpload(page: Page, filePath: string) {
    const fileInput = page.locator('input[type="file"]')
    
    if (await fileInput.isVisible()) {
      await fileInput.setInputFiles(filePath)
      
      // Wait for file to be processed
      await expect(page.getByText(/uploaded|attached|processing/i)).toBeVisible({ timeout: 10000 })
      
      return true
    }
    
    return false
  }

  /**
   * Verify chat accessibility
   */
  static async verifyAccessibility(page: Page) {
    const messageInput = page.getByPlaceholder(/Ask anything about your data/i)
    
    // Test keyboard navigation
    await messageInput.focus()
    await expect(messageInput).toBeFocused()
    
    // Test screen reader labels
    await expect(messageInput).toHaveAttribute('aria-label')
    
    // Test button accessibility
    const sendButton = page.getByRole('button', { name: /send/i })
    if (await sendButton.isVisible()) {
      await expect(sendButton).toHaveAttribute('aria-label')
    }
  }

  /**
   * Monitor chat performance
   */
  static async measureResponseTime(page: Page, message: string): Promise<number> {
    const startTime = Date.now()
    
    await this.sendMessage(page, message)
    await this.waitForAIResponse(page)
    
    const endTime = Date.now()
    return endTime - startTime
  }

  /**
   * Test concurrent chat messages
   */
  static async testConcurrentMessages(page: Page, messages: string[]) {
    const promises = messages.map(async (message, index) => {
      // Stagger messages slightly to avoid conflicts
      await page.waitForTimeout(index * 100)
      await this.sendMessage(page, message)
    })
    
    await Promise.all(promises)
    
    // Wait for all responses
    await page.waitForTimeout(5000)
    
    // Verify all messages and responses are present
    for (const message of messages) {
      await expect(page.getByText(message)).toBeVisible()
    }
  }
}