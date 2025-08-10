const { test, expect } = require('@playwright/test');

test('Complete authentication flow test', async ({ page }) => {
  console.log('🧪 Starting authentication flow test...');

  // Test 1: Navigate to login page
  console.log('📍 Step 1: Navigate to login page');
  await page.goto('http://localhost:3000/auth/login');
  await page.waitForLoadState('networkidle');
  
  // Check if login form exists
  const emailInput = page.locator('input[type="email"], input[name="email"]').first();
  const passwordInput = page.locator('input[type="password"], input[name="password"]').first();
  const submitButton = page.locator('button[type="submit"], button:has-text("Sign"), button:has-text("Login")').first();
  
  await expect(emailInput).toBeVisible();
  await expect(passwordInput).toBeVisible();
  await expect(submitButton).toBeVisible();
  console.log('✅ Login form elements are visible');

  // Test 2: Try to register via API first
  console.log('📍 Step 2: Test direct API endpoints');
  
  const registerResponse = await page.request.post('http://localhost:8007/auth/register', {
    data: {
      email: 'playwright@example.com',
      password: 'PlaywrightTest123',
      first_name: 'Playwright',
      last_name: 'Test'
    }
  });
  
  console.log('📊 Registration response status:', registerResponse.status());
  const registerData = await registerResponse.json();
  console.log('📊 Registration response:', registerData);
  
  // Test 3: Try to login via API
  console.log('📍 Step 3: Test API login');
  
  const loginResponse = await page.request.post('http://localhost:8007/auth/login', {
    data: {
      email: 'playwright@example.com',
      password: 'PlaywrightTest123'
    }
  });
  
  console.log('📊 Login response status:', loginResponse.status());
  const loginData = await loginResponse.json();
  console.log('📊 Login response:', loginData);

  // Test 4: Try to fill and submit the login form with existing user
  console.log('📍 Step 4: Test frontend login form');
  
  // Use credentials for the user we know exists
  await emailInput.fill('testuser@example.com');
  await passwordInput.fill('TestPassword123');
  
  console.log('✅ Filled login form with test credentials');
  
  // Take a screenshot before submitting
  await page.screenshot({ path: 'login-form-filled.png', fullPage: true });
  
  // Click submit and wait for response
  await Promise.all([
    page.waitForLoadState('networkidle'),
    submitButton.click()
  ]);
  
  // Check the current URL and page state after login attempt
  const currentUrl = page.url();
  console.log('📍 Current URL after login attempt:', currentUrl);
  
  // Take a screenshot of the result
  await page.screenshot({ path: 'login-attempt-result.png', fullPage: true });
  
  // Test 5: Check for any error messages or success indicators
  const errorElement = page.locator('[data-testid="error"], .error, [class*="error"]').first();
  const successElement = page.locator('[data-testid="success"], .success, [class*="success"]').first();
  
  const hasError = await errorElement.isVisible().catch(() => false);
  const hasSuccess = await successElement.isVisible().catch(() => false);
  
  console.log('📊 Has error message:', hasError);
  console.log('📊 Has success message:', hasSuccess);
  
  if (hasError) {
    const errorText = await errorElement.textContent();
    console.log('❌ Error message:', errorText);
  }
  
  if (hasSuccess) {
    const successText = await successElement.textContent();
    console.log('✅ Success message:', successText);
  }

  // Test 6: Check if we're redirected to dashboard or still on login
  if (currentUrl.includes('/auth/login')) {
    console.log('📍 Still on login page - login may have failed');
    
    // Check for NextAuth error messages
    const nextAuthError = page.locator('[data-testid="error"], p:has-text("error"), div:has-text("error")').first();
    if (await nextAuthError.isVisible().catch(() => false)) {
      const errorText = await nextAuthError.textContent();
      console.log('🔍 NextAuth error detected:', errorText);
    }
  } else {
    console.log('🎉 Redirected away from login page - potentially successful');
    
    // Check if we're on a dashboard or protected page
    if (currentUrl.includes('/dashboard') || currentUrl.includes('/app')) {
      console.log('🎉 Successfully reached dashboard/app page');
    }
  }
  
  console.log('🏁 Authentication flow test completed');
});

test.describe('Authentication API Direct Tests', () => {
  test('Test platform service endpoints directly', async ({ request }) => {
    console.log('🔧 Testing platform service endpoints directly...');
    
    // Test health check
    const healthResponse = await request.get('http://localhost:8007/health');
    console.log('🏥 Health check status:', healthResponse.status());
    
    if (healthResponse.status() === 200) {
      const healthData = await healthResponse.json();
      console.log('🏥 Health check data:', healthData);
    }
    
    // Test registration
    const regResponse = await request.post('http://localhost:8007/auth/register', {
      data: {
        email: 'direct-test@example.com',
        password: 'DirectTest123',
        first_name: 'Direct',
        last_name: 'Test'
      }
    });
    
    console.log('📝 Registration status:', regResponse.status());
    const regData = await regResponse.json();
    console.log('📝 Registration data:', regData);
    
    // Test login
    const loginResponse = await request.post('http://localhost:8007/auth/login', {
      data: {
        email: 'direct-test@example.com',
        password: 'DirectTest123'
      }
    });
    
    console.log('🔑 Login status:', loginResponse.status());
    const loginData = await loginResponse.json();
    console.log('🔑 Login data:', loginData);
  });
});