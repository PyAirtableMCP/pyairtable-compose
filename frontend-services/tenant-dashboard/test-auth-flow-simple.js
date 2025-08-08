const { chromium } = require('playwright');

async function testLoginFlow() {
  console.log('🚀 Starting authentication flow test...');
  
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();
  
  // Listen to console logs
  page.on('console', msg => console.log('🖥️  Browser:', msg.text()));
  page.on('pageerror', error => console.log('❌ Page error:', error.message));

  try {
    // Step 1: Go to login page
    console.log('📝 Navigating to login page...');
    await page.goto('http://localhost:3000/auth/login');
    await page.waitForLoadState('networkidle');

    // Step 2: Fill in credentials
    console.log('🔑 Filling in test credentials...');
    await page.locator('input[type="email"]').fill('testuser@example.com');
    await page.locator('input[type="password"]').fill('TestPassword123');

    // Step 3: Submit form
    console.log('✅ Submitting login form...');
    await page.getByRole('button', { name: /sign in/i }).click();

    // Step 4: Wait a moment for any processing
    console.log('⏳ Waiting for processing...');
    await page.waitForTimeout(3000);
    
    let currentUrl = page.url();
    console.log('📍 URL after 3 seconds:', currentUrl);
    
    // Check for any form errors
    const errorElements = await page.locator('.error, .alert, [role="alert"]').all();
    if (errorElements.length > 0) {
      for (let error of errorElements) {
        const errorText = await error.textContent();
        if (errorText.trim()) {
          console.log('⚠️  Form error:', errorText.trim());
        }
      }
    }

    // Step 5: Wait for redirect and check URL
    console.log('⏳ Waiting for redirect...');
    try {
      await page.waitForURL(/\/(dashboard|chat|$)/, { timeout: 20000 });
    } catch (e) {
      console.log('❌ Redirect timeout, checking current state...');
      currentUrl = page.url();
      console.log('📍 Final URL:', currentUrl);
      throw e;
    }
    
    currentUrl = page.url();
    console.log('🎯 Current URL:', currentUrl);
    
    if (currentUrl.includes('dashboard') || currentUrl.includes('chat') || currentUrl === 'http://localhost:3000/') {
      console.log('✅ SUCCESS: Authentication flow worked!');
      console.log('🎉 User successfully redirected to authenticated area');
      return true;
    } else {
      console.log('❌ FAILED: Unexpected redirect location');
      return false;
    }

  } catch (error) {
    console.error('❌ Test failed with error:', error.message);
    
    const currentUrl = page.url();
    console.log('📍 Current URL when failed:', currentUrl);
    
    // Take screenshot for debugging
    await page.screenshot({ path: 'login-debug-screenshot.png' });
    console.log('📸 Debug screenshot saved as login-debug-screenshot.png');
    
    return false;
  } finally {
    await browser.close();
  }
}

// Run the test
testLoginFlow().then(success => {
  process.exit(success ? 0 : 1);
});