/**
 * Enhanced Authentication Flow Tests for 6-Service Architecture
 * 
 * This test suite addresses the authentication issues blocking current tests
 * by providing comprehensive coverage of:
 * - NextAuth integration with Go Auth Service
 * - Multi-service authentication propagation
 * - Session management across services
 * - JWT token validation and refresh
 */

import { test, expect, Page } from '@playwright/test'
import { TestDataFactory } from '../factories/test-data-factory'
import { ServiceMockManager } from '../mocks/service-mock-manager'
import { AuthTestHelpers } from '../helpers/auth-test-helpers'

interface TestUser {
  id: string
  email: string
  name: string
  tenantId: string
  roles: string[]
}

interface MockSession {
  user: TestUser
  accessToken: string
  refreshToken: string
  expires: string
}

class EnhancedAuthTester {
  constructor(private page: Page) {}

  async setupServiceMocks(): Promise<void> {
    // Mock NextAuth endpoints
    await this.page.route('**/api/auth/session', async route => {
      const mockSession: MockSession = {
        user: TestDataFactory.createTestUser(),
        accessToken: TestDataFactory.createJWTToken(),
        refreshToken: TestDataFactory.createRefreshToken(),
        expires: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
      }
      
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(mockSession)
      })
    })

    // Mock Go Auth Service validation
    await this.page.route('**/auth/verify', async route => {
      const authHeader = route.request().headers()['authorization']
      const isValidToken = authHeader?.startsWith('Bearer ') && authHeader.length > 20
      
      await route.fulfill({
        status: isValidToken ? 200 : 401,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: isValidToken,
          userId: isValidToken ? 'test-user-123' : null,
          tenantId: isValidToken ? 'test-tenant' : null
        })
      })
    })

    // Mock API Gateway authentication
    await this.page.route('**/api/**', async route => {
      const authHeader = route.request().headers()['authorization']
      
      if (!authHeader) {
        await route.fulfill({
          status: 401,
          contentType: 'application/json',
          body: JSON.stringify({ error: 'Authentication required' })
        })
        return
      }

      // Pass through to actual endpoint with mock response
      await route.continue()
    })

    // Mock service health checks with authentication
    const services = ['llm-orchestrator', 'mcp-server', 'airtable-gateway']
    for (const service of services) {
      await this.page.route(`**/${service}/health`, async route => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            status: 'healthy',
            service: service,
            timestamp: new Date().toISOString(),
            authenticated: true
          })
        })
      })
    }
  }

  async mockFailedAuthentication(): Promise<void> {
    await this.page.route('**/api/auth/signin', async route => {
      await route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'Invalid credentials'
        })
      })
    })
  }

  async mockExpiredSession(): Promise<void> {
    await this.page.route('**/api/auth/session', async route => {
      await route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'Session expired'
        })
      })
    })
  }

  async login(email: string = 'test@example.com', password: string = 'password123'): Promise<void> {
    await this.page.goto('/auth/login')
    
    // Use updated selectors with data-testid
    await this.page.getByTestId('email-input').fill(email)
    await this.page.getByTestId('password-input').fill(password)
    await this.page.getByTestId('signin-button').click()
  }

  async waitForDashboard(): Promise<void> {
    await expect(this.page).toHaveURL('/dashboard')
    await expect(this.page.getByTestId('dashboard-welcome')).toBeVisible()
  }

  async verifyServiceAuthentication(): Promise<void> {
    // Verify all services recognize the authenticated session
    const services = [
      { name: 'LLM Orchestrator', testId: 'llm-status' },
      { name: 'MCP Server', testId: 'mcp-status' },
      { name: 'Airtable Gateway', testId: 'airtable-status' }
    ]

    for (const service of services) {
      await expect(this.page.getByTestId(service.testId)).toContainText('Connected')
    }
  }
}

test.describe('Enhanced Authentication Flow', () => {
  let authTester: EnhancedAuthTester

  test.beforeEach(async ({ page }) => {
    authTester = new EnhancedAuthTester(page)
    await authTester.setupServiceMocks()
  })

  test('should handle complete authentication flow across all services', async ({ page }) => {
    await authTester.login()
    await authTester.waitForDashboard()
    await authTester.verifyServiceAuthentication()

    // Verify JWT token is properly passed to backend services
    const chatResponse = page.waitForResponse('**/api/chat')
    await page.getByTestId('chat-input').fill('Test authentication')
    await page.getByTestId('chat-send').click()
    
    const response = await chatResponse
    expect(response.status()).toBe(200)
    expect(response.request().headers()['authorization']).toContain('Bearer ')
  })

  test('should handle authentication failures gracefully', async ({ page }) => {
    await authTester.mockFailedAuthentication()
    
    await page.goto('/auth/login')
    await page.getByTestId('email-input').fill('invalid@example.com')
    await page.getByTestId('password-input').fill('wrongpassword')
    await page.getByTestId('signin-button').click()

    await expect(page.getByTestId('error-message')).toContainText('Invalid credentials')
    await expect(page).toHaveURL('/auth/login')
  })

  test('should redirect to login when session expires', async ({ page }) => {
    // First login successfully
    await authTester.login()
    await authTester.waitForDashboard()

    // Mock session expiry
    await authTester.mockExpiredSession()

    // Try to access protected resource
    await page.goto('/dashboard/settings')
    
    // Should redirect to login
    await expect(page).toHaveURL(/\/auth\/login/)
    await expect(page.getByTestId('session-expired-message')).toBeVisible()
  })

  test('should maintain authentication across service failures', async ({ page }) => {
    await authTester.login()
    await authTester.waitForDashboard()

    // Mock one service failure
    await page.route('**/mcp-server/health', async route => {
      await route.fulfill({
        status: 503,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Service unavailable' })
      })
    })

    // Reload page
    await page.reload()

    // Should still be authenticated
    await expect(page).toHaveURL('/dashboard')
    await expect(page.getByTestId('dashboard-welcome')).toBeVisible()
    
    // Should show degraded service status
    await expect(page.getByTestId('mcp-status')).toContainText('Unavailable')
  })

  test('should handle JWT token refresh', async ({ page }) => {
    await authTester.login()
    await authTester.waitForDashboard()

    // Mock token refresh endpoint
    await page.route('**/api/auth/refresh', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          accessToken: TestDataFactory.createJWTToken(),
          expires: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
        })
      })
    })

    // Wait for automatic token refresh (mocked timing)
    await page.waitForTimeout(2000)

    // Verify continued authentication
    const response = await page.request.get('/api/user/profile', {
      headers: {
        'Authorization': `Bearer ${TestDataFactory.createJWTToken()}`
      }
    })
    
    expect(response.status()).toBe(200)
  })

  test('should preserve authentication state across browser refresh', async ({ page }) => {
    await authTester.login()
    await authTester.waitForDashboard()

    // Refresh browser
    await page.reload()

    // Should maintain authenticated state
    await expect(page).toHaveURL('/dashboard')
    await expect(page.getByTestId('dashboard-welcome')).toBeVisible()
    
    // Session should still be valid
    const sessionResponse = await page.request.get('/api/auth/session')
    expect(sessionResponse.status()).toBe(200)
  })

  test('should handle multi-tenant authentication', async ({ page }) => {
    const tenantUser = TestDataFactory.createTestUser({
      tenantId: 'tenant-abc-123',
      roles: ['admin', 'user']
    })

    // Mock tenant-specific session
    await page.route('**/api/auth/session', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          user: tenantUser,
          accessToken: TestDataFactory.createJWTToken({ tenantId: tenantUser.tenantId }),
          expires: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
        })
      })
    })

    await authTester.login()
    await authTester.waitForDashboard()

    // Verify tenant-specific data access
    await expect(page.getByTestId('tenant-selector')).toContainText('tenant-abc-123')
    
    // Verify role-based access
    await expect(page.getByTestId('admin-panel-link')).toBeVisible()
  })

  test('should handle secure logout across all services', async ({ page }) => {
    await authTester.login()
    await authTester.waitForDashboard()

    // Mock logout endpoints
    await page.route('**/api/auth/signout', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ success: true })
      })
    })

    await page.route('**/auth/logout', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ success: true })
      })
    })

    // Perform logout
    await page.getByTestId('user-menu').click()
    await page.getByTestId('logout-button').click()

    // Should redirect to login
    await expect(page).toHaveURL('/auth/login')
    
    // Session should be cleared
    const sessionResponse = await page.request.get('/api/auth/session')
    expect(sessionResponse.status()).toBe(401)
  })

  test('should handle concurrent user sessions', async ({ browser }) => {
    // Create two browser contexts for different users
    const context1 = await browser.newContext()
    const context2 = await browser.newContext()
    
    const page1 = await context1.newPage()
    const page2 = await context2.newPage()
    
    const authTester1 = new EnhancedAuthTester(page1)
    const authTester2 = new EnhancedAuthTester(page2)
    
    await authTester1.setupServiceMocks()
    await authTester2.setupServiceMocks()

    // Login as different users
    await authTester1.login('user1@example.com')
    await authTester2.login('user2@example.com')

    await authTester1.waitForDashboard()
    await authTester2.waitForDashboard()

    // Verify isolated sessions
    await expect(page1.getByTestId('user-email')).toContainText('user1@example.com')
    await expect(page2.getByTestId('user-email')).toContainText('user2@example.com')

    await context1.close()
    await context2.close()
  })

  test('should handle authentication with external services', async ({ page }) => {
    await authTester.login()
    await authTester.waitForDashboard()

    // Mock external service authentication
    await page.route('**/api/airtable/authenticate', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          authenticated: true,
          baseId: 'appTEST123456789',
          permissions: ['read', 'write']
        })
      })
    })

    // Test Airtable authentication
    await page.getByTestId('airtable-connect-button').click()
    await page.getByTestId('airtable-token-input').fill('patABC123DEF456GHI789')
    await page.getByTestId('airtable-base-input').fill('appTEST123456789')
    await page.getByTestId('airtable-submit').click()

    await expect(page.getByTestId('airtable-status')).toContainText('Connected')
    await expect(page.getByTestId('airtable-base-id')).toContainText('appTEST123456789')
  })
})

test.describe('Authentication Performance Tests', () => {
  test('should login within acceptable time limits', async ({ page }) => {
    const authTester = new EnhancedAuthTester(page)
    await authTester.setupServiceMocks()

    const startTime = Date.now()
    await authTester.login()
    await authTester.waitForDashboard()
    const endTime = Date.now()

    const loginDuration = endTime - startTime
    expect(loginDuration).toBeLessThan(3000) // Should login within 3 seconds
  })

  test('should handle multiple concurrent authentications', async ({ browser }) => {
    const contexts = await Promise.all(
      Array.from({ length: 5 }, () => browser.newContext())
    )
    
    const loginPromises = contexts.map(async (context, index) => {
      const page = await context.newPage()
      const authTester = new EnhancedAuthTester(page)
      await authTester.setupServiceMocks()
      
      const startTime = Date.now()
      await authTester.login(`user${index}@example.com`)
      await authTester.waitForDashboard()
      const endTime = Date.now()
      
      await context.close()
      return endTime - startTime
    })

    const loginTimes = await Promise.all(loginPromises)
    
    // All logins should complete within 5 seconds
    loginTimes.forEach(time => {
      expect(time).toBeLessThan(5000)
    })

    // Average login time should be reasonable
    const averageTime = loginTimes.reduce((a, b) => a + b, 0) / loginTimes.length
    expect(averageTime).toBeLessThan(3000)
  })
})