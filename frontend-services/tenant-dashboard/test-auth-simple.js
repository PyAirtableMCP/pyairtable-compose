// Simple authentication test
const { chromium } = require('@playwright/test');

async function testAuth() {
  console.log('🧪 Starting simple authentication test...');
  
  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage();
  
  try {
    // Test 1: Check platform service health
    console.log('📍 Step 1: Testing platform service health');
    
    const healthResponse = await fetch('http://localhost:8007/health');
    const healthData = await healthResponse.json();
    console.log('🏥 Platform service health:', healthData.status);
    
    // Test 2: Test registration API
    console.log('📍 Step 2: Testing registration API');
    
    const registerResponse = await fetch('http://localhost:8007/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'playwright-test@example.com',
        password: 'TestPassword123',
        first_name: 'Playwright',
        last_name: 'Test'
      })
    });
    
    const registerData = await registerResponse.json();
    console.log('📝 Registration response:', registerResponse.status, registerData);
    
    // Test 3: Test login API
    console.log('📍 Step 3: Testing login API');
    
    const loginResponse = await fetch('http://localhost:8007/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'testuser@example.com',
        password: 'TestPassword123'
      })
    });
    
    const loginData = await loginResponse.json();
    console.log('🔑 Login response:', loginResponse.status, loginData);
    
    // Test 4: Test frontend
    console.log('📍 Step 4: Testing frontend login page');
    
    await page.goto('http://localhost:3000/auth/login');
    await page.waitForLoadState('networkidle');
    
    // Check if page loaded
    const title = await page.title();
    console.log('🌐 Page title:', title);
    
    // Check for login form
    const hasEmailInput = await page.locator('input[type="email"]').count() > 0;
    const hasPasswordInput = await page.locator('input[type="password"]').count() > 0;
    const hasSubmitButton = await page.locator('button[type="submit"]').count() > 0;
    
    console.log('📝 Form elements found:');
    console.log('  - Email input:', hasEmailInput);
    console.log('  - Password input:', hasPasswordInput);
    console.log('  - Submit button:', hasSubmitButton);
    
    if (hasEmailInput && hasPasswordInput && hasSubmitButton) {
      console.log('✅ All form elements found - proceeding with login test');
      
      // Fill the form
      await page.fill('input[type="email"]', 'testuser@example.com');
      await page.fill('input[type="password"]', 'TestPassword123');
      
      // Take screenshot before submitting
      await page.screenshot({ path: 'login-before-submit.png' });
      console.log('📸 Screenshot taken: login-before-submit.png');
      
      // Submit the form
      await page.click('button[type="submit"]');
      
      // Wait a bit for the response
      await page.waitForTimeout(3000);
      
      // Check the result
      const currentUrl = page.url();
      console.log('🔍 URL after login attempt:', currentUrl);
      
      // Take screenshot after submitting
      await page.screenshot({ path: 'login-after-submit.png' });
      console.log('📸 Screenshot taken: login-after-submit.png');
      
      // Check for success/error messages
      const pageText = await page.textContent('body');
      if (pageText.toLowerCase().includes('error')) {
        console.log('❌ Page contains error text');
      }
      if (pageText.toLowerCase().includes('dashboard') || currentUrl.includes('dashboard')) {
        console.log('🎉 Login appears successful - dashboard detected');
      }
    } else {
      console.log('❌ Login form not found - taking screenshot for debugging');
      await page.screenshot({ path: 'login-form-missing.png' });
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  } finally {
    await browser.close();
    console.log('🏁 Test completed');
  }
}

// Run the test
testAuth();