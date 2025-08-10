import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { ChatHelpers } from './helpers/chat-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { generateUniqueTestUser, testData } from './fixtures/test-users'

test.describe('Complete End-to-End User Journey', () => {
  
  test('should complete full new user journey from registration to using core features', async ({ page }) => {
    // Generate unique user for this complete journey
    const newUser = generateUniqueTestUser('complete-journey')
    
    test.step('User Registration', async () => {
      console.log('🚀 Starting user registration...')
      
      // Navigate to registration
      await page.goto('/auth/register')
      await expect(page.getByRole('heading', { name: /create account|sign up|register/i })).toBeVisible()
      
      // Complete registration
      await page.getByLabel(/email/i).fill(newUser.email)
      await page.getByLabel(/password/i).fill(newUser.password)
      
      const confirmPasswordField = page.getByLabel(/confirm password|repeat password/i)
      if (await confirmPasswordField.isVisible({ timeout: 1000 }).catch(() => false)) {
        await confirmPasswordField.fill(newUser.password)
      }
      
      await page.getByLabel(/name|full name/i).fill(newUser.name)
      
      const termsCheckbox = page.getByLabel(/terms|privacy|agree/i)
      if (await termsCheckbox.isVisible({ timeout: 1000 }).catch(() => false)) {
        await termsCheckbox.check()
      }
      
      // Submit registration
      await page.getByRole('button', { name: /sign up|register|create account/i }).click()
      
      // Handle post-registration flow
      await expect(page).toHaveURL(/\/(verify-email|onboarding|dashboard|chat)/, { timeout: 15000 })
      
      console.log('✅ User registration completed')
    })

    test.step('Email Verification and Onboarding', async () => {
      console.log('📧 Handling email verification and onboarding...')
      
      // Handle email verification if required
      if (page.url().includes('/verify-email')) {
        await expect(page.getByText(/verify|check your email|confirmation/i)).toBeVisible()
        
        // Mock email verification
        await page.goto('/auth/verify?token=mock-verification-token&email=' + encodeURIComponent(newUser.email))
        await expect(page).toHaveURL(/\/(onboarding|dashboard|chat)/, { timeout: 10000 })
      }
      
      // Complete onboarding if present
      if (page.url().includes('/onboarding')) {
        await expect(page.getByText(/welcome|getting started|setup/i)).toBeVisible()
        
        const continueButton = page.getByRole('button', { name: /continue|next|get started/i })
        if (await continueButton.isVisible()) {
          await continueButton.click()
        }
        
        await page.waitForURL(/\/(dashboard|chat)/, { timeout: 10000 })
      }
      
      await CommonHelpers.waitForPageLoad(page)
      console.log('✅ Onboarding completed')
    })

    test.step('First Login and Dashboard Access', async () => {
      console.log('🏠 Accessing main dashboard...')
      
      // Verify successful authentication
      await AuthHelpers.verifyAuthenticated(page)
      
      // Should be on main dashboard or chat page
      const currentUrl = new URL(page.url()).pathname
      expect(['/dashboard', '/chat', '/']).toContain(currentUrl)
      
      // If redirected to chat (as per application logic), verify it loads
      if (currentUrl === '/chat' || currentUrl === '/') {
        await expect(page.getByText(/PyAirtable Assistant|welcome|chat/i)).toBeVisible()
      }
      
      console.log('✅ Dashboard access verified')
    })

    test.step('Core Chat Interface Interaction', async () => {
      console.log('💬 Testing chat interface...')
      
      // Navigate to chat interface
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)
      
      // Verify interface is ready
      await expect(page.getByText(/PyAirtable Assistant/i)).toBeVisible()
      await ChatHelpers.verifyConnectionStatus(page, 'connected')
      
      // Send welcome message
      const welcomeMessage = 'Hello! I\'m a new user. Can you help me get started with my data?'
      await ChatHelpers.sendMessage(page, welcomeMessage)
      
      const welcomeResponse = await ChatHelpers.waitForAIResponse(page)
      const responseText = await welcomeResponse.textContent()
      expect(responseText).toMatch(/help|welcome|get started|data|airtable/i)
      
      console.log('✅ Chat interface working')
    })

    test.step('Data Query and Analysis', async () => {
      console.log('📊 Testing data analysis features...')
      
      // Query for available data
      await ChatHelpers.sendMessage(page, 'What data do I have access to? Show me my tables.')
      const dataResponse = await ChatHelpers.waitForAIResponse(page)
      expect(await dataResponse.textContent()).toMatch(/tables|data|available|access/i)
      
      // Request specific data analysis
      await ChatHelpers.sendMessage(page, 'Can you analyze my most recent posts and their performance?')
      await ChatHelpers.waitForAIResponse(page, 30000)
      
      // Test formula creation request
      await ChatHelpers.sendMessage(page, 'Create a formula to calculate engagement rate')
      const formulaResponse = await ChatHelpers.waitForAIResponse(page)
      expect(await formulaResponse.textContent()).toMatch(/formula|engagement|rate|calculation/i)
      
      console.log('✅ Data analysis features working')
    })

    test.step('Advanced Feature Usage', async () => {
      console.log('⚡ Testing advanced features...')
      
      // Test automation request
      await ChatHelpers.sendMessage(page, 'Help me set up an automation for high-engagement posts')
      const automationResponse = await ChatHelpers.waitForAIResponse(page, 30000)
      expect(await automationResponse.textContent()).toMatch(/automation|workflow|high-engagement|posts/i)
      
      // Test complex query
      const complexQuery = 'I need to create a comprehensive report showing my social media performance, including top posts, engagement trends, and recommendations for improvement'
      await ChatHelpers.sendMessage(page, complexQuery)
      await ChatHelpers.waitForAIResponse(page, 45000)
      
      console.log('✅ Advanced features working')
    })

    test.step('Navigation and Session Persistence', async () => {
      console.log('🧭 Testing navigation and persistence...')
      
      // Navigate away from chat
      if (await page.locator('[href="/dashboard"], [href="/"]').first().isVisible({ timeout: 2000 }).catch(() => false)) {
        await page.goto('/dashboard')
        await CommonHelpers.waitForPageLoad(page)
      }
      
      // Navigate back to chat
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)
      
      // Verify chat history is preserved
      await expect(page.getByText(welcomeMessage)).toBeVisible()
      
      // Test page refresh
      await page.reload()
      await ChatHelpers.waitForChatInterface(page)
      await AuthHelpers.verifyAuthenticated(page)
      
      console.log('✅ Navigation and persistence working')
    })

    test.step('Mobile Responsiveness', async () => {
      console.log('📱 Testing mobile responsiveness...')
      
      // Test mobile viewport
      await page.setViewportSize({ width: 375, height: 667 })
      await page.waitForTimeout(1000)
      
      // Chat should still be functional
      await ChatHelpers.waitForChatInterface(page)
      await ChatHelpers.sendMessage(page, 'Testing mobile interface')
      await ChatHelpers.waitForAIResponse(page)
      
      // Test tablet viewport
      await page.setViewportSize({ width: 768, height: 1024 })
      await page.waitForTimeout(1000)
      
      await ChatHelpers.sendMessage(page, 'Testing tablet interface')
      await ChatHelpers.waitForAIResponse(page)
      
      // Reset to desktop
      await page.setViewportSize({ width: 1920, height: 1080 })
      
      console.log('✅ Mobile responsiveness verified')
    })

    test.step('Error Handling and Recovery', async () => {
      console.log('🛠️ Testing error handling...')
      
      // Test network error recovery
      await page.route('**/api/chat/**', route => route.abort())
      
      await ChatHelpers.sendMessage(page, 'This should trigger an error')
      await CommonHelpers.verifyErrorMessage(page, /error|connection|network|failed/i)
      
      // Restore connection
      await page.unroute('**/api/chat/**')
      
      // Verify recovery
      await ChatHelpers.sendMessage(page, 'Connection should be restored now')
      await ChatHelpers.waitForAIResponse(page)
      
      console.log('✅ Error handling working')
    })

    test.step('Logout and Session Cleanup', async () => {
      console.log('👋 Testing logout...')
      
      // Test logout functionality
      await AuthHelpers.logoutUser(page)
      
      // Verify logged out
      await AuthHelpers.verifyNotAuthenticated(page)
      
      // Try to access protected page
      await page.goto('/chat')
      await expect(page).toHaveURL(/\/auth\/login/)
      
      console.log('✅ Logout completed')
    })

    test.step('Returning User Login', async () => {
      console.log('🔄 Testing returning user login...')
      
      // Login again as returning user
      await AuthHelpers.loginUser(page, newUser)
      
      // Navigate to chat
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)
      
      // Previous chat history should be preserved
      await expect(page.getByText(welcomeMessage)).toBeVisible()
      
      console.log('✅ Returning user experience verified')
    })

    // Cleanup
    await CommonHelpers.cleanupTestData(page, newUser.email)
    
    console.log('🎉 Complete user journey test passed!')
  })

  test('should handle power user workflow with multiple features', async ({ page }) => {
    const powerUser = generateUniqueTestUser('power-user')
    
    test.step('Quick Setup for Power User', async () => {
      // Register and login quickly
      await AuthHelpers.registerUser(page, powerUser)
      await CommonHelpers.waitForPageLoad(page)
      
      // Navigate to chat
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)
    })

    test.step('Rapid Feature Usage', async () => {
      // Test rapid successive interactions
      const queries = [
        'Show me my data overview',
        'Create a summary of top performing content',
        'What automation opportunities do I have?',
        'Generate a weekly performance report',
        'Help me optimize my data structure'
      ]

      for (const query of queries) {
        await ChatHelpers.sendMessage(page, query)
        await ChatHelpers.waitForAIResponse(page, 30000)
        await page.waitForTimeout(500) // Brief pause between queries
      }
    })

    test.step('Complex Multi-step Workflow', async () => {
      // Simulate complex business workflow
      await ChatHelpers.sendMessage(page, 'I need to: 1) Analyze Q4 performance, 2) Create formulas for growth metrics, 3) Set up automated reports, and 4) Export data for presentation')
      
      const complexResponse = await ChatHelpers.waitForAIResponse(page, 60000)
      expect(await complexResponse.textContent()).toMatch(/Q4|performance|formulas|growth|automated|reports|export/i)
    })

    await CommonHelpers.cleanupTestData(page, powerUser.email)
  })

  test('should handle concurrent user scenarios', async ({ page, context }) => {
    const user1 = generateUniqueTestUser('concurrent-1')
    const user2 = generateUniqueTestUser('concurrent-2')
    
    test.step('Setup Multiple Users', async () => {
      // Register first user
      await AuthHelpers.registerUser(page, user1)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)
      
      // Create second context for second user
      const context2 = await page.context().browser()!.newContext()
      const page2 = await context2.newPage()
      
      await AuthHelpers.registerUser(page2, user2)
      await page2.goto('/chat')
      await ChatHelpers.waitForChatInterface(page2)
      
      // Both users interact simultaneously
      await Promise.all([
        ChatHelpers.sendMessage(page, 'User 1: Analyzing my data'),
        ChatHelpers.sendMessage(page2, 'User 2: Creating formulas')
      ])
      
      await Promise.all([
        ChatHelpers.waitForAIResponse(page),
        ChatHelpers.waitForAIResponse(page2)
      ])
      
      await context2.close()
    })

    await Promise.all([
      CommonHelpers.cleanupTestData(page, user1.email),
      CommonHelpers.cleanupTestData(page, user2.email)
    ])
  })

  test('should validate complete accessibility workflow', async ({ page }) => {
    const accessibilityUser = generateUniqueTestUser('accessibility')
    
    test.step('Accessibility-focused User Journey', async () => {
      await AuthHelpers.registerUser(page, accessibilityUser)
      await page.goto('/chat')
      
      // Test keyboard-only navigation
      await page.keyboard.press('Tab')
      const messageInput = page.getByPlaceholder(/Ask anything about your data/i)
      await expect(messageInput).toBeFocused()
      
      // Send message using only keyboard
      await messageInput.fill('Testing accessibility features')
      await messageInput.press('Enter')
      
      await ChatHelpers.waitForAIResponse(page)
      
      // Verify screen reader compatibility
      await CommonHelpers.verifyAccessibility(page)
      await ChatHelpers.verifyAccessibility(page)
    })

    await CommonHelpers.cleanupTestData(page, accessibilityUser.email)
  })

  test('should handle complete business scenario workflow', async ({ page }) => {
    const businessUser = generateUniqueTestUser('business')
    
    test.step('Business User Complete Workflow', async () => {
      await AuthHelpers.registerUser(page, businessUser)
      await page.goto('/chat')
      await ChatHelpers.waitForChatInterface(page)
      
      // Business scenario: New product launch analysis
      const businessScenario = [
        'I\'m launching a new product. Help me set up tracking for launch metrics.',
        'Create formulas to calculate conversion rates and ROI.',
        'Set up automated alerts for key performance indicators.',
        'Generate a dashboard view for executives.',
        'Export launch data for board presentation.'
      ]
      
      for (const request of businessScenario) {
        await ChatHelpers.sendMessage(page, request)
        await ChatHelpers.waitForAIResponse(page, 30000)
      }
      
      // Verify comprehensive response handling
      await expect(page.getByText(businessScenario[0])).toBeVisible()
    })

    await CommonHelpers.cleanupTestData(page, businessUser.email)
  })
})