import { test, expect } from '@playwright/test'

test.describe('Authentication Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Start with a clean state
    await page.goto('/auth/login')
  })

  test('should display login form', async ({ page }) => {
    await expect(page.getByRole('heading', { name: /sign in/i })).toBeVisible()
    await expect(page.getByLabel(/email/i)).toBeVisible()
    await expect(page.getByLabel(/password/i)).toBeVisible()
    await expect(page.getByRole('button', { name: /sign in/i })).toBeVisible()
  })

  test('should show validation errors for empty form', async ({ page }) => {
    const signInButton = page.getByRole('button', { name: /sign in/i })
    await signInButton.click()

    await expect(page.getByText(/email is required/i)).toBeVisible()
    await expect(page.getByText(/password is required/i)).toBeVisible()
  })

  test('should show validation error for invalid email', async ({ page }) => {
    await page.getByLabel(/email/i).fill('invalid-email')
    await page.getByLabel(/password/i).fill('password123')
    await page.getByRole('button', { name: /sign in/i }).click()

    await expect(page.getByText(/please enter a valid email/i)).toBeVisible()
  })

  test('should successfully login with valid credentials', async ({ page }) => {
    // Fill in valid credentials
    await page.getByLabel(/email/i).fill('test@example.com')
    await page.getByLabel(/password/i).fill('password123')
    
    // Mock successful login response
    await page.route('**/api/auth/signin', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          user: {
            id: 'test-user-id',
            email: 'test@example.com',
            name: 'Test User',
          },
        }),
      })
    })

    // Submit form
    await page.getByRole('button', { name: /sign in/i }).click()

    // Should redirect to dashboard
    await expect(page).toHaveURL('/dashboard')
    await expect(page.getByText(/welcome back/i)).toBeVisible()
  })

  test('should show error for invalid credentials', async ({ page }) => {
    await page.getByLabel(/email/i).fill('test@example.com')
    await page.getByLabel(/password/i).fill('wrongpassword')

    // Mock failed login response
    await page.route('**/api/auth/signin', async route => {
      await route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'Invalid credentials',
        }),
      })
    })

    await page.getByRole('button', { name: /sign in/i }).click()

    await expect(page.getByText(/invalid credentials/i)).toBeVisible()
  })

  test('should navigate to registration page', async ({ page }) => {
    await page.getByRole('link', { name: /sign up/i }).click()
    
    await expect(page).toHaveURL('/auth/register')
    await expect(page.getByRole('heading', { name: /create account/i })).toBeVisible()
  })

  test('should handle password reset flow', async ({ page }) => {
    await page.getByRole('link', { name: /forgot password/i }).click()
    
    await expect(page).toHaveURL('/auth/reset-password')
    await expect(page.getByRole('heading', { name: /reset password/i })).toBeVisible()
    
    await page.getByLabel(/email/i).fill('test@example.com')
    
    // Mock password reset request
    await page.route('**/api/auth/reset-password', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          message: 'Password reset email sent',
        }),
      })
    })
    
    await page.getByRole('button', { name: /send reset email/i }).click()
    
    await expect(page.getByText(/password reset email sent/i)).toBeVisible()
  })

  test('should preserve redirect URL after login', async ({ page }) => {
    // Try to access protected page
    await page.goto('/dashboard/settings')
    
    // Should redirect to login with return URL
    await expect(page).toHaveURL(/\/auth\/login\?.*callbackUrl/)
    
    // Login
    await page.getByLabel(/email/i).fill('test@example.com')
    await page.getByLabel(/password/i).fill('password123')
    
    // Mock successful auth
    await page.route('**/api/auth/signin', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          user: {
            id: 'test-user-id',
            email: 'test@example.com',
            name: 'Test User',
          },
        }),
      })
    })
    
    await page.getByRole('button', { name: /sign in/i }).click()
    
    // Should redirect to original URL
    await expect(page).toHaveURL('/dashboard/settings')
  })

  test('should handle logout', async ({ page }) => {
    // First login
    await page.goto('/dashboard')
    
    // Mock authenticated state
    await page.route('**/api/auth/session', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          user: {
            id: 'test-user-id',
            email: 'test@example.com',
            name: 'Test User',
          },
          expires: '2024-12-31T23:59:59.999Z',
        }),
      })
    })
    
    await page.reload()
    
    // Click logout
    await page.getByRole('button', { name: /logout/i }).click()
    
    // Mock logout response
    await page.route('**/api/auth/signout', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({}),
      })
    })
    
    // Should redirect to login
    await expect(page).toHaveURL('/auth/login')
  })

  test('should handle session expiry', async ({ page }) => {
    // Mock expired session
    await page.route('**/api/auth/session', async route => {
      await route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'Session expired',
        }),
      })
    })
    
    await page.goto('/dashboard')
    
    // Should redirect to login
    await expect(page).toHaveURL('/auth/login')
    await expect(page.getByText(/session expired/i)).toBeVisible()
  })

  test('should be accessible', async ({ page }) => {
    // Check form accessibility
    await expect(page.getByLabel(/email/i)).toHaveAttribute('type', 'email')
    await expect(page.getByLabel(/password/i)).toHaveAttribute('type', 'password')
    
    // Check keyboard navigation
    await page.keyboard.press('Tab')
    await expect(page.getByLabel(/email/i)).toBeFocused()
    
    await page.keyboard.press('Tab')
    await expect(page.getByLabel(/password/i)).toBeFocused()
    
    await page.keyboard.press('Tab')
    await expect(page.getByRole('button', { name: /sign in/i })).toBeFocused()
  })
})