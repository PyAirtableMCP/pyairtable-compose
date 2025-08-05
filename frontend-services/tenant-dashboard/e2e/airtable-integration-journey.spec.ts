import { test, expect } from '@playwright/test'
import { AuthHelpers } from './helpers/auth-helpers'
import { ChatHelpers } from './helpers/chat-helpers'
import { CommonHelpers } from './helpers/common-helpers'
import { testUsers, testData } from './fixtures/test-users'

test.describe('Complete Airtable Integration User Journey', () => {
  
  test.beforeEach(async ({ page }) => {
    // Login and setup mock Airtable responses
    await AuthHelpers.loginUser(page, testUsers.standard)
    
    // Mock Airtable API responses for testing
    await mockAirtableAPI(page)
    
    // Navigate to chat interface for Airtable interactions
    await page.goto('/chat')
    await ChatHelpers.waitForChatInterface(page)
  })

  test('should complete full Airtable data query workflow', async ({ page }) => {
    // Step 1: Query for table structure
    await ChatHelpers.sendMessage(page, 'Show me all my tables and their structure')
    const tablesResponse = await ChatHelpers.waitForAIResponse(page)
    
    const tablesText = await tablesResponse.textContent()
    expect(tablesText).toMatch(/tables|structure|fields|Posts|Customers/i)

    // Step 2: Query specific table data
    await ChatHelpers.sendMessage(page, 'Show me the top 10 posts by engagement from my Posts table')
    const postsResponse = await ChatHelpers.waitForAIResponse(page)
    
    const postsText = await postsResponse.textContent()
    expect(postsText).toMatch(/posts|engagement|top|data|records/i)

    // Step 3: Request data filtering
    await ChatHelpers.sendMessage(page, 'Filter my posts to show only those from last month with engagement > 100')
    const filteredResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await filteredResponse.textContent()).toMatch(/filtered|last month|engagement|100/i)

    // Step 4: Request data aggregation
    await ChatHelpers.sendMessage(page, 'Calculate the average engagement rate across all my posts')
    const aggregationResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await aggregationResponse.textContent()).toMatch(/average|engagement rate|calculated|posts/i)

    // Step 5: Request data export or summary
    await ChatHelpers.sendMessage(page, 'Create a summary report of my social media performance')
    const summaryResponse = await ChatHelpers.waitForAIResponse(page, 30000)
    
    expect(await summaryResponse.textContent()).toMatch(/summary|report|performance|social media/i)
  })

  test('should handle Airtable formula creation and validation', async ({ page }) => {
    // Step 1: Request simple formula creation
    await ChatHelpers.sendMessage(page, 'Create a formula to calculate engagement rate (likes + comments) / impressions')
    const formulaResponse = await ChatHelpers.waitForAIResponse(page)
    
    const formulaText = await formulaResponse.textContent()
    expect(formulaText).toMatch(/formula|engagement rate|likes|comments|impressions/i)
    expect(formulaText).toMatch(/\/|\+|calculation/i) // Should contain formula operators

    // Step 2: Request complex formula with conditions
    await ChatHelpers.sendMessage(page, 'Create a formula that assigns priority levels: High if engagement > 1000, Medium if > 500, Low otherwise')
    const conditionalResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await conditionalResponse.textContent()).toMatch(/formula|priority|High|Medium|Low|IF|condition/i)

    // Step 3: Request rollup formula
    await ChatHelpers.sendMessage(page, 'Create a rollup formula to calculate total revenue from linked Customer records')
    const rollupResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await rollupResponse.textContent()).toMatch(/rollup|formula|total|revenue|Customer|linked/i)

    // Step 4: Request date-based formula
    await ChatHelpers.sendMessage(page, 'Create a formula to calculate days since last contact')
    const dateResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await dateResponse.textContent()).toMatch(/formula|days|since|last contact|date|NOW|DATETIME_DIFF/i)
  })

  test('should handle Airtable automation workflow creation', async ({ page }) => {
    // Step 1: Request simple automation
    await ChatHelpers.sendMessage(page, 'Set up an automation that sends an email when a new lead is added')
    const automationResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await automationResponse.textContent()).toMatch(/automation|email|new lead|trigger|workflow/i)

    // Step 2: Request conditional automation
    await ChatHelpers.sendMessage(page, 'Create an automation that updates status to "Hot Lead" when engagement score > 800')
    const conditionalAutomation = await ChatHelpers.waitForAIResponse(page)
    
    expect(await conditionalAutomation.textContent()).toMatch(/automation|status|Hot Lead|engagement|score|800/i)

    // Step 3: Request multi-step automation
    await ChatHelpers.sendMessage(page, 'Build a workflow that: 1) Tags high-value customers, 2) Creates follow-up task, 3) Sends notification to sales team')
    const workflowResponse = await ChatHelpers.waitForAIResponse(page, 45000)
    
    const workflowText = await workflowResponse.textContent()
    expect(workflowText).toMatch(/workflow|high-value|follow-up|task|notification|sales team/i)
  })

  test('should handle Airtable view creation and management', async ({ page }) => {
    // Step 1: Create filtered view
    await ChatHelpers.sendMessage(page, 'Create a view showing only active customers from the last 6 months')
    const viewResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await viewResponse.textContent()).toMatch(/view|active customers|6 months|filtered/i)

    // Step 2: Create grouped view
    await ChatHelpers.sendMessage(page, 'Create a view that groups posts by category and sorts by engagement')
    const groupedResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await groupedResponse.textContent()).toMatch(/view|groups|category|sorts|engagement/i)

    // Step 3: Create summary view
    await ChatHelpers.sendMessage(page, 'Create a view with summary fields showing totals and averages')
    const summaryViewResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await summaryViewResponse.textContent()).toMatch(/view|summary|totals|averages|fields/i)
  })

  test('should handle data import and export operations', async ({ page }) => {
    // Step 1: Request data export
    await ChatHelpers.sendMessage(page, 'Export my customer data to CSV format')
    const exportResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await exportResponse.textContent()).toMatch(/export|customer data|CSV|download/i)

    // Step 2: Request filtered export
    await ChatHelpers.sendMessage(page, 'Export only high-value customers with their contact information')
    const filteredExportResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await filteredExportResponse.textContent()).toMatch(/export|high-value|customers|contact information/i)

    // Step 3: Request data import guidance
    await ChatHelpers.sendMessage(page, 'How can I import product data from a spreadsheet?')
    const importResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await importResponse.textContent()).toMatch(/import|product data|spreadsheet|CSV|mapping/i)
  })

  test('should handle real-time data operations and updates', async ({ page }) => {
    // Step 1: Query current data
    await ChatHelpers.sendMessage(page, 'Show me my most recent posts from today')
    const recentResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await recentResponse.textContent()).toMatch(/recent|posts|today|current/i)

    // Step 2: Request data monitoring
    await ChatHelpers.sendMessage(page, 'Set up monitoring for posts that get high engagement in real-time')
    const monitoringResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await monitoringResponse.textContent()).toMatch(/monitoring|high engagement|real-time|alerts/i)

    // Step 3: Test data refresh
    await ChatHelpers.sendMessage(page, 'Refresh my data and show any changes')
    const refreshResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await refreshResponse.textContent()).toMatch(/refresh|data|changes|updated/i)
  })

  test('should handle Airtable integration errors gracefully', async ({ page }) => {
    // Test API connection error
    await page.route('**/airtable/**', route => route.abort())
    
    await ChatHelpers.sendMessage(page, 'Show me my tables')
    const errorResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await errorResponse.textContent()).toMatch(/error|connection|airtable|unavailable|try again/i)

    // Restore connection
    await page.unroute('**/airtable/**')
    await mockAirtableAPI(page)

    // Test authentication error
    await page.route('**/airtable/**', route => route.fulfill({
      status: 401,
      body: JSON.stringify({ error: 'Unauthorized' })
    }))

    await ChatHelpers.sendMessage(page, 'List my tables again')
    const authErrorResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await authErrorResponse.textContent()).toMatch(/unauthorized|authentication|api key|permission/i)
  })

  test('should handle complex multi-table operations', async ({ page }) => {
    // Step 1: Query across multiple tables
    await ChatHelpers.sendMessage(page, 'Show me customers and their associated orders from the last month')
    const multiTableResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await multiTableResponse.textContent()).toMatch(/customers|orders|associated|linked|last month/i)

    // Step 2: Create cross-table formula
    await ChatHelpers.sendMessage(page, 'Create a formula that calculates customer lifetime value using data from Orders and Customers tables')
    const crossTableFormula = await ChatHelpers.waitForAIResponse(page)
    
    expect(await crossTableFormula.textContent()).toMatch(/formula|lifetime value|Orders|Customers|linked/i)

    // Step 3: Request complex reporting
    await ChatHelpers.sendMessage(page, 'Generate a report showing sales performance by customer segment and product category')
    const complexReport = await ChatHelpers.waitForAIResponse(page, 45000)
    
    expect(await complexReport.textContent()).toMatch(/report|sales performance|customer segment|product category/i)
  })

  test('should validate Airtable field types and constraints', async ({ page }) => {
    // Test field type recognition
    await ChatHelpers.sendMessage(page, 'What field types do I have in my Posts table?')
    const fieldTypesResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await fieldTypesResponse.textContent()).toMatch(/field types|Posts|text|number|date|single select/i)

    // Test constraint validation
    await ChatHelpers.sendMessage(page, 'Can I create a formula that references a field that doesn\'t exist?')
    const validationResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await validationResponse.textContent()).toMatch(/field.*exist|reference|error|invalid/i)

    // Test field relationship understanding
    await ChatHelpers.sendMessage(page, 'Explain the relationship between my Customers and Orders tables')
    const relationshipResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await relationshipResponse.textContent()).toMatch(/relationship|linked|Customers|Orders|foreign key/i)
  })

  test('should handle Airtable permissions and access control', async ({ page }) => {
    // Test permission checking
    await ChatHelpers.sendMessage(page, 'Can I modify records in the Finance table?')
    const permissionResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await permissionResponse.textContent()).toMatch(/permission|modify|Finance|access|allowed/i)

    // Test read-only scenarios
    await ChatHelpers.sendMessage(page, 'Show me data from tables I have read access to')
    const readOnlyResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await readOnlyResponse.textContent()).toMatch(/read access|tables|available|permissions/i)
  })

  test('should support Airtable performance optimization suggestions', async ({ page }) => {
    // Request performance analysis
    await ChatHelpers.sendMessage(page, 'How can I optimize the performance of my large Posts table?')
    const optimizationResponse = await ChatHelpers.waitForAIResponse(page)
    
    expect(await optimizationResponse.textContent()).toMatch(/optimize|performance|Posts|indexing|views|pagination/i)

    // Request formula optimization
    await ChatHelpers.sendMessage(page, 'Are there any slow formulas in my base that I should optimize?')
    const formulaOptimization = await ChatHelpers.waitForAIResponse(page)
    
    expect(await formulaOptimization.textContent()).toMatch(/slow|formulas|optimize|performance|efficient/i)
  })
})

// Helper function to mock Airtable API responses
async function mockAirtableAPI(page) {
  // Mock table listing
  await page.route('**/airtable/tables', async route => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        tables: [
          {
            id: 'tblPosts',
            name: 'Posts',
            fields: [
              { id: 'fldTitle', name: 'Title', type: 'singleLineText' },
              { id: 'fldContent', name: 'Content', type: 'multilineText' },
              { id: 'fldEngagement', name: 'Engagement', type: 'number' },
              { id: 'fldDate', name: 'Date', type: 'date' }
            ]
          },
          {
            id: 'tblCustomers',
            name: 'Customers',
            fields: [
              { id: 'fldName', name: 'Name', type: 'singleLineText' },
              { id: 'fldEmail', name: 'Email', type: 'email' },
              { id: 'fldRevenue', name: 'Revenue', type: 'currency' }
            ]
          }
        ]
      })
    })
  })

  // Mock record queries
  await page.route('**/airtable/records/**', async route => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        records: testData.airtableData.sampleRecords.map((record, index) => ({
          id: `rec${index + 1}`,
          fields: record,
          createdTime: '2024-01-01T00:00:00.000Z'
        }))
      })
    })
  })

  // Mock formula validation
  await page.route('**/airtable/validate-formula', async route => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        valid: true,
        result: 'Formula is valid'
      })
    })
  })

  // Mock automation endpoints
  await page.route('**/airtable/automations', async route => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        message: 'Automation created successfully'
      })
    })
  })
}