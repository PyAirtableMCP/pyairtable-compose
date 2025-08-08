import { test, expect } from '@playwright/test'

test.describe('Visual Regression Testing', () => {
  test.beforeEach(async ({ page }) => {
    // Disable animations for consistent screenshots
    await page.addInitScript(() => {
      document.addEventListener('DOMContentLoaded', () => {
        const style = document.createElement('style')
        style.textContent = `
          *, *::before, *::after {
            animation-duration: 0s !important;
            animation-delay: 0s !important;
            transition-duration: 0s !important;
            transition-delay: 0s !important;
          }
        `
        document.head.appendChild(style)
      })
    })
  })

  test('should capture homepage screenshot', async ({ page }) => {
    await page.goto('/')
    
    // Wait for page to load completely
    await page.waitForLoadState('networkidle')
    
    // Take full page screenshot
    await expect(page).toHaveScreenshot('homepage-full.png', {
      fullPage: true,
      threshold: 0.3 // Allow some variation in rendering
    })
  })

  test('should capture login page screenshot', async ({ page }) => {
    await page.goto('/auth/login')
    
    // Wait for the page to load
    await page.waitForLoadState('networkidle')
    
    // Wait for the main heading to be visible
    await page.waitForSelector('h1, h2, [role="heading"]', { timeout: 10000 })
    
    // Take screenshot of login page
    await expect(page).toHaveScreenshot('login-page.png', {
      fullPage: true,
      threshold: 0.3
    })
  })

  test('should capture registration page screenshot', async ({ page }) => {
    await page.goto('/auth/register')
    
    // Wait for the page to load
    await page.waitForLoadState('networkidle')
    
    // Wait for the main heading to be visible
    await page.waitForSelector('h1, h2, [role="heading"]', { timeout: 10000 })
    
    // Take screenshot of registration page
    await expect(page).toHaveScreenshot('register-page.png', {
      fullPage: true,
      threshold: 0.3
    })
  })

  test('should capture onboarding page screenshot', async ({ page }) => {
    await page.goto('/auth/onboarding')
    
    // Wait for the page to load
    await page.waitForLoadState('networkidle')
    
    // Take screenshot of onboarding page
    await expect(page).toHaveScreenshot('onboarding-page.png', {
      fullPage: true,
      threshold: 0.3
    })
  })

  test('should capture chat interface screenshot', async ({ page }) => {
    await page.goto('/chat')
    
    // Wait for the page to load
    await page.waitForLoadState('networkidle')
    
    // Wait for chat interface elements to load
    await page.waitForTimeout(2000) // Give time for any async loading
    
    // Take screenshot of chat interface
    await expect(page).toHaveScreenshot('chat-interface.png', {
      fullPage: true,
      threshold: 0.3
    })
  })

  test('should capture demo page screenshot', async ({ page }) => {
    await page.goto('/demo')
    
    // Wait for the page to load
    await page.waitForLoadState('networkidle')
    
    // Take screenshot of demo page
    await expect(page).toHaveScreenshot('demo-page.png', {
      fullPage: true,
      threshold: 0.3
    })
  })

  test('should capture error states - 404 page', async ({ page }) => {
    await page.goto('/non-existent-page')
    
    // Wait for the page to load
    await page.waitForLoadState('networkidle')
    
    // Take screenshot of 404 error page
    await expect(page).toHaveScreenshot('404-error.png', {
      fullPage: true,
      threshold: 0.3
    })
  })

  test('should capture mobile viewport screenshots', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 }) // iPhone SE size
    
    // Homepage mobile
    await page.goto('/')
    await page.waitForLoadState('networkidle')
    await expect(page).toHaveScreenshot('homepage-mobile.png', {
      threshold: 0.3
    })

    // Login mobile
    await page.goto('/auth/login')
    await page.waitForLoadState('networkidle')
    await page.waitForSelector('h1, h2, [role="heading"]', { timeout: 10000 })
    await expect(page).toHaveScreenshot('login-page-mobile.png', {
      threshold: 0.3
    })

    // Chat interface mobile
    await page.goto('/chat')
    await page.waitForLoadState('networkidle')
    await page.waitForTimeout(2000)
    await expect(page).toHaveScreenshot('chat-interface-mobile.png', {
      threshold: 0.3
    })
  })

  test('should capture form states and interactions', async ({ page }) => {
    await page.goto('/auth/login')
    await page.waitForLoadState('networkidle')
    
    // Empty form state
    await expect(page).toHaveScreenshot('login-form-empty.png', {
      clip: { x: 0, y: 0, width: 800, height: 600 }
    })
    
    // Filled form state
    const emailField = page.getByRole('textbox', { name: /email/i }).first()
    const passwordField = page.getByRole('textbox', { name: /password/i }).first()
    
    if (await emailField.isVisible()) {
      await emailField.fill('test@example.com')
    }
    
    if (await passwordField.isVisible()) {
      await passwordField.fill('password123')
    }
    
    await expect(page).toHaveScreenshot('login-form-filled.png', {
      clip: { x: 0, y: 0, width: 800, height: 600 }
    })
  })

  test('should capture loading states', async ({ page }) => {
    // Go to a page and capture loading state if possible
    await page.goto('/chat')
    
    // Try to capture any loading spinners or skeleton states
    const loadingSelector = '[data-testid="loading"], .loading, .spinner, .skeleton'
    
    try {
      await page.waitForSelector(loadingSelector, { timeout: 2000 })
      await expect(page).toHaveScreenshot('loading-state.png', {
        threshold: 0.3
      })
    } catch (error) {
      // No loading state found, that's okay
      console.log('No loading state detected')
    }
    
    // Ensure page is fully loaded
    await page.waitForLoadState('networkidle')
    await expect(page).toHaveScreenshot('chat-loaded-state.png', {
      threshold: 0.3
    })
  })
})