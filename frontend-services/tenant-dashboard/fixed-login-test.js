const { chromium } = require('playwright');

async function fixedLoginTest() {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();
  
  console.log('🧪 Testing login with corrected credentials...');
  
  try {
    // Navigate to login page
    await page.goto('http://localhost:3000/auth/login');
    await page.waitForTimeout(2000);
    
    // Check for correct heading
    const welcomeHeading = await page.locator('text="Welcome back"').isVisible();
    console.log('✅ Welcome back heading found:', welcomeHeading);
    
    // Fill form with corrected credentials
    await page.locator('input[type="email"]').fill('testuser@example.com');
    await page.locator('input[type="password"]').fill('TestPassword123'); // Fixed: removed !
    
    console.log('📝 Filled form with corrected password (without !)');
    
    // Submit form
    await page.locator('button[type="submit"]').click();
    console.log('🔐 Submitted login form...');
    
    // Wait for navigation or response
    await page.waitForTimeout(5000);
    
    const currentUrl = page.url();
    console.log('🔗 Current URL after login:', currentUrl);
    
    // Check for error messages
    const errorMessages = await page.locator('[role="alert"]').allTextContents().catch(() => []);
    const errorTexts = await page.locator('.text-destructive').allTextContents().catch(() => []);
    
    if (errorMessages.length > 0 || errorTexts.length > 0) {
      console.log('❌ Error messages found:', [...errorMessages, ...errorTexts]);
    } else {
      console.log('✅ No error messages detected');
    }
    
    // Check if login was successful (should redirect away from login page)
    const isStillOnLoginPage = currentUrl.includes('/auth/login');
    const loginSuccessful = !isStillOnLoginPage;
    
    console.log('🎯 Login successful:', loginSuccessful);
    console.log('📍 Final URL:', currentUrl);
    
    if (loginSuccessful) {
      console.log('🎉 SUCCESS: Login flow is working correctly!');
      
      // Test session persistence
      const sessionResponse = await page.request.get('http://localhost:3000/api/auth/session');
      const sessionData = await sessionResponse.json().catch(() => null);
      console.log('🔑 Session data:', sessionData?.user?.email || 'No session');
    } else {
      console.log('❌ FAILED: Still on login page, authentication failed');
    }
    
    await page.screenshot({ path: 'login-success-test.png', fullPage: true });
    
  } catch (error) {
    console.error('❌ Test error:', error);
  } finally {
    await browser.close();
  }
}

fixedLoginTest();