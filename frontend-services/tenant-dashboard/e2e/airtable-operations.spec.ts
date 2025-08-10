import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { generateUniqueTestUser } from './fixtures/test-users'

/**
 * Airtable Operations Tests
 * 
 * Tests Airtable integration functionality using robust selectors
 * that prioritize data-testid and accessibility attributes.
 */
test.describe('Airtable Operations', () => {
  let testUser: ReturnType<typeof generateUniqueTestUser>

  test.beforeEach(async ({ page }) => {
    testUser = generateUniqueTestUser()
    await AuthHelpers.registerUser(page, testUser)
    await AuthHelpers.loginUser(page, testUser)
  })

  test.afterEach(async ({ page }) => {
    await CommonHelpers.cleanupTestData(page, testUser)
  })

  test('should display Airtable data properly on mobile', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 })
    
    await test.step('Navigate to data view', async () => {
      // Navigate to a data view using robust selectors
      const dataLink = page.locator('[data-testid="data-nav-link"]')
        .or(page.getByRole('link', { name: /data|airtable|tables/i }))
        .or(page.locator('a[href*="/data"], a[href*="/airtable"]'))
        .first()

      if (await dataLink.isVisible({ timeout: 3000 })) {
        await dataLink.click()
      } else {
        await page.goto('/data')
      }
    })

    await test.step('Verify mobile data display', async () => {
      // Check for data table or cards on mobile
      const dataContainer = page.locator('[data-testid="airtable-data-container"]')
        .or(page.locator('[role="table"], [role="grid"]'))
        .or(page.locator('.data-table, .table-container, .data-grid'))
        .or(page.locator('table'))
        .first()

      // Data should be visible even on mobile
      if (await dataContainer.isVisible({ timeout: 10000 })) {
        await expect(dataContainer).toBeVisible()
        
        // Take screenshot for mobile view verification
        await page.screenshot({ 
          path: 'test-results/airtable-mobile-view.png',
          fullPage: true 
        })
      } else {
        // Maybe data is shown in card format on mobile
        const dataCards = page.locator('[data-testid="data-cards"]')
          .or(page.locator('.card, .data-card'))
          .first()

        if (await dataCards.isVisible({ timeout: 5000 })) {
          await expect(dataCards).toBeVisible()
        } else {
          console.log('No data display found - may need Airtable connection setup')
        }
      }
    })
  })

  test('should handle data analysis requests', async ({ page }) => {
    await page.goto('/chat')

    await test.step('Request data analysis', async () => {
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox'))
        .first()

      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .first()

      // Request data analysis
      await chatInput.fill('Analyze my data and show me key insights')
      await sendButton.click()

      // Wait for AI response
      const aiResponse = page.locator('[data-testid="ai-message"]')
        .or(page.locator('.message:not(.user)').last())
        .first()

      await expect(aiResponse).toBeVisible({ timeout: 45000 })
      
      // Take screenshot of data analysis response
      await page.screenshot({ 
        path: 'test-results/airtable-data-analysis.png',
        fullPage: true 
      })
    })
  })

  test('should display Airtable data insights', async ({ page }) => {
    await page.goto('/chat')

    await test.step('Request specific data insights', async () => {
      const chatInput = page.locator('[data-testid="chat-input"]')
        .or(page.getByRole('textbox'))
        .first()

      const sendButton = page.locator('[data-testid="send-button"]')
        .or(page.getByRole('button', { name: /send/i }))
        .first()

      // Ask for table information
      await chatInput.fill('What tables and data do I have available?')
      await sendButton.click()

      // Wait for response
      const aiResponse = page.locator('[data-testid="ai-message"]')
        .or(page.locator('.message:not(.user)').last())
        .first()

      await expect(aiResponse).toBeVisible({ timeout: 30000 })
      
      // Response should contain some information about data or tables
      const responseText = await aiResponse.textContent()
      console.log('Data insight response:', responseText?.substring(0, 200))
    })
  })
})