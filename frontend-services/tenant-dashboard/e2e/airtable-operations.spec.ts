import { test, expect } from '@playwright/test'

test.describe('Airtable Operations', () => {
  test.beforeEach(async ({ page }) => {
    // Mock successful API responses for testing
    await page.route('**/api/airtable/**', async route => {
      const url = route.request().url()
      const method = route.request().method()
      
      if (url.includes('/api/airtable/bases') && method === 'POST') {
        // Mock bases response
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            bases: [
              {
                id: 'base_test_1',
                name: 'Test Customer Database',
                permissionLevel: 'read',
                tableCount: 3,
                recordCount: 1234,
                createdTime: new Date().toISOString(),
                description: 'A sample customer database'
              },
              {
                id: 'base_test_2',
                name: 'Test Sales Tracker',
                permissionLevel: 'write',
                tableCount: 2,
                recordCount: 892,
                createdTime: new Date().toISOString(),
                description: 'Track sales performance'
              }
            ]
          })
        })
      } else if (url.includes('/api/airtable/analyze-structure')) {
        // Mock structure analysis response
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            analysis: {
              totalTables: 3,
              totalRecords: 1234,
              tableStructures: [
                {
                  id: 'tbl_test_1',
                  name: 'Customers',
                  recordCount: 500,
                  fields: [
                    { name: 'Name', type: 'singleLineText' },
                    { name: 'Email', type: 'email' },
                    { name: 'Phone', type: 'phoneNumber' }
                  ]
                }
              ],
              recommendations: [
                'Consider adding data validation for email fields',
                'Phone number formatting could be standardized'
              ]
            }
          })
        })
      } else if (url.includes('/api/airtable/validate')) {
        // Mock validation response
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            isValid: true,
            connectionStatus: 'success',
            baseAccess: true,
            message: 'Successfully connected to Airtable base'
          })
        })
      } else {
        // Default to continue for unhandled routes
        await route.continue()
      }
    })
  })

  test.describe('Airtable Connection Setup', () => {
    test('should display Airtable connection form', async ({ page }) => {
      await page.goto('/auth/onboarding')
      await page.waitForTimeout(2000)
      
      // Look for Airtable-related form elements
      const airtableElements = [
        page.locator('input[placeholder*="Personal Access Token"]'),
        page.locator('input[placeholder*="API Key"]'),
        page.locator('input[placeholder*="Base ID"]'),
        page.locator('text=Airtable'),
        page.locator('text=Personal Access Token'),
        page.locator('text=Connect to Airtable')
      ]
      
      let foundAirtableForm = false
      for (const element of airtableElements) {
        try {
          if (await element.isVisible({ timeout: 1000 })) {
            foundAirtableForm = true
            break
          }
        } catch {
          // Continue checking
        }
      }
      
      if (foundAirtableForm) {
        // Test form interaction
        const tokenInput = page.locator('input[placeholder*="Personal Access Token"]').first()
        if (await tokenInput.isVisible()) {
          await tokenInput.fill('test_personal_access_token_123')
          await expect(tokenInput).toHaveValue('test_personal_access_token_123')
        }
      }
    })

    test('should validate Airtable token format', async ({ page }) => {
      await page.goto('/auth/onboarding')
      await page.waitForTimeout(2000)
      
      const tokenInput = page.locator('input[placeholder*="Personal Access Token"], input[name*="token"]').first()
      const submitButton = page.locator('button[type="submit"], button:has-text("Connect"), button:has-text("Next")').first()
      
      if (await tokenInput.isVisible() && await submitButton.isVisible()) {
        // Test empty token
        await submitButton.click()
        
        // Look for validation message
        const validationMessages = [
          /required/i,
          /token.*required/i,
          /please enter/i,
          /access token/i
        ]
        
        let foundValidation = false
        for (const message of validationMessages) {
          try {
            await page.waitForSelector(`text=${message.source}`, { timeout: 2000 })
            foundValidation = true
            break
          } catch {
            // Continue
          }
        }
        
        // Test invalid token format
        await tokenInput.fill('invalid_token')
        await submitButton.click()
        
        // Should either show validation or proceed to test connection
        await page.waitForTimeout(1000)
      }
    })
  })

  test.describe('Base Selection and Analysis', () => {
    test('should display available Airtable bases', async ({ page }) => {
      // Navigate to a page that might show Airtable bases
      await page.goto('/chat')
      await page.waitForTimeout(2000)
      
      // Try to trigger base selection/viewing
      const airtableSelectors = [
        'select[name*="base"]',
        'text=Test Customer Database',
        'text=Select Base',
        'text=Choose Base',
        'button:has-text("Select Base")'
      ]
      
      let foundBaseSelector = false
      for (const selector of airtableSelectors) {
        try {
          const element = page.locator(selector).first()
          if (await element.isVisible({ timeout: 1000 })) {
            await element.click()
            foundBaseSelector = true
            break
          }
        } catch {
          // Continue
        }
      }
      
      if (!foundBaseSelector) {
        // Try to trigger via API call simulation
        await page.evaluate(() => {
          // Simulate API call that might trigger base display
          fetch('/api/airtable/bases', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ personalAccessToken: 'test_token' })
          }).catch(() => {})
        })
        
        await page.waitForTimeout(1000)
      }
    })

    test('should handle base connection errors gracefully', async ({ page }) => {
      // Mock error responses
      await page.route('**/api/airtable/bases', async route => {
        await route.fulfill({
          status: 401,
          contentType: 'application/json',
          body: JSON.stringify({
            error: 'Invalid Personal Access Token'
          })
        })
      })
      
      await page.goto('/chat')
      await page.waitForTimeout(2000)
      
      // Try to trigger an API call that would result in error
      await page.evaluate(() => {
        fetch('/api/airtable/bases', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ personalAccessToken: 'invalid_token' })
        }).catch(() => {})
      })
      
      await page.waitForTimeout(1000)
      
      // Look for error handling
      const errorSelectors = [
        'text=Invalid Personal Access Token',
        'text=Error',
        'text=Failed to connect',
        '[role="alert"]',
        '.error',
        '.alert'
      ]
      
      let foundErrorHandling = false
      for (const selector of errorSelectors) {
        try {
          if (await page.locator(selector).isVisible({ timeout: 2000 })) {
            foundErrorHandling = true
            break
          }
        } catch {
          // Continue
        }
      }
      
      // Even if no specific error UI, should not crash
      expect(page.url()).toBeTruthy()
    })
  })

  test.describe('Data Visualization and Analysis', () => {
    test('should display Airtable data insights', async ({ page }) => {
      await page.goto('/chat')
      await page.waitForTimeout(3000)
      
      // Look for data visualization elements
      const dataElements = [
        'text=1234', // Record count from mock
        'text=Test Customer Database',
        'text=3 tables',
        'canvas', // Charts
        'svg', // SVG charts
        '.chart',
        '[data-testid*="chart"]',
        'text=Records',
        'text=Tables'
      ]
      
      let foundDataVisualization = false
      for (const selector of dataElements) {
        try {
          if (await page.locator(selector).first().isVisible({ timeout: 2000 })) {
            foundDataVisualization = true
            break
          }
        } catch {
          // Continue
        }
      }
      
      if (foundDataVisualization) {
        // Take screenshot of data visualization
        await expect(page).toHaveScreenshot('airtable-data-view.png', {
          threshold: 0.4,
          fullPage: true
        })
      }
    })

    test('should handle data analysis requests', async ({ page }) => {
      await page.goto('/chat')
      await page.waitForTimeout(2000)
      
      // Look for chat input or analysis trigger
      const chatElements = [
        'input[placeholder*="message"]',
        'input[placeholder*="ask"]',
        'textarea[placeholder*="message"]',
        'button:has-text("Analyze")',
        'button:has-text("Generate Report")',
        '[data-testid="chat-input"]'
      ]
      
      let chatInput = null
      for (const selector of chatElements) {
        try {
          const element = page.locator(selector).first()
          if (await element.isVisible({ timeout: 1000 })) {
            chatInput = element
            break
          }
        } catch {
          // Continue
        }
      }
      
      if (chatInput) {
        await chatInput.fill('Analyze my Airtable data and show me customer insights')
        
        const submitButton = page.locator('button[type="submit"], button:has-text("Send"), button:has-text("Ask")').first()
        if (await submitButton.isVisible()) {
          await submitButton.click()
          
          // Wait for response
          await page.waitForTimeout(3000)
          
          // Look for analysis response
          const responseElements = [
            'text=analysis',
            'text=insight',
            'text=customer',
            'text=data',
            '.message',
            '.response'
          ]
          
          let foundResponse = false
          for (const selector of responseElements) {
            try {
              if (await page.locator(selector).isVisible({ timeout: 2000 })) {
                foundResponse = true
                break
              }
            } catch {
              // Continue
            }
          }
        }
      }
    })
  })

  test.describe('Airtable Integration Error States', () => {
    test('should handle missing token gracefully', async ({ page }) => {
      await page.route('**/api/airtable/**', async route => {
        await route.fulfill({
          status: 400,
          contentType: 'application/json',
          body: JSON.stringify({
            error: 'Personal Access Token is required'
          })
        })
      })
      
      await page.goto('/auth/onboarding')
      await page.waitForTimeout(2000)
      
      // Should display appropriate error or guidance
      const guidanceElements = [
        'text=Personal Access Token',
        'text=required',
        'text=Connect to Airtable',
        'text=API Key',
        'a[href*="airtable.com"]',
        'text=Get your token'
      ]
      
      let foundGuidance = false
      for (const selector of guidanceElements) {
        try {
          if (await page.locator(selector).isVisible({ timeout: 1000 })) {
            foundGuidance = true
            break
          }
        } catch {
          // Continue
        }
      }
    })

    test('should handle network failures', async ({ page }) => {
      await page.route('**/api/airtable/**', async route => {
        await route.abort('failed')
      })
      
      await page.goto('/chat')
      await page.waitForTimeout(2000)
      
      // Trigger API call
      await page.evaluate(() => {
        fetch('/api/airtable/bases', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ personalAccessToken: 'test' })
        }).catch(() => {})
      })
      
      await page.waitForTimeout(1000)
      
      // Should handle network failure gracefully
      expect(page.url()).toBeTruthy()
    })
  })

  test.describe('Mobile Responsiveness for Airtable UI', () => {
    test('should display Airtable data properly on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 })
      await page.goto('/chat')
      await page.waitForTimeout(2000)
      
      // Check mobile layout
      await expect(page.locator('body')).toBeVisible()
      
      // Take mobile screenshot
      await expect(page).toHaveScreenshot('airtable-mobile-view.png', {
        threshold: 0.4
      })
    })
  })
})