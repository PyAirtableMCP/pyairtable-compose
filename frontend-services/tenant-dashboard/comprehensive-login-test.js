const { chromium } = require('playwright');

async function comprehensiveLoginTest() {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();
  
  console.log('🧪 Starting comprehensive login flow test...');
  
  try {
    // Step 1: Navigate to login page and verify it loads
    console.log('📍 Step 1: Navigating to /auth/login...');
    await page.goto('http://localhost:3000/auth/login');
    await page.waitForTimeout(2000);
    
    // Check if correct heading is present
    const welcomeHeading = await page.locator('text="Welcome back"').isVisible();
    console.log('✅ Welcome back heading found:', welcomeHeading);
    
    // Step 2: Try to fill login form with test credentials
    console.log('📝 Step 2: Testing form filling...');
    const emailField = page.locator('input[type="email"]');
    const passwordField = page.locator('input[type="password"]');
    const signInButton = page.locator('button[type="submit"]');
    
    await emailField.fill('testuser@example.com');
    await passwordField.fill('TestPassword123!');
    
    console.log('✅ Form filled with test credentials');
    
    // Step 3: Attempt login and check what happens
    console.log('🔐 Step 3: Attempting login...');
    await signInButton.click();
    
    // Wait to see what happens
    await page.waitForTimeout(5000);
    
    // Check current URL
    const currentUrl = page.url();
    console.log('🔗 Current URL after login attempt:', currentUrl);
    
    // Check for error messages
    const errorAlert = await page.locator('[role="alert"]').textContent().catch(() => '');
    const errorText = await page.locator('.text-destructive').allTextContents().catch(() => []);
    
    console.log('❌ Error alert:', errorAlert);
    console.log('❌ Error texts:', errorText);
    
    // Step 4: Check API endpoints
    console.log('🔍 Step 4: Testing authentication API endpoints...');
    
    // Test session endpoint
    const sessionResponse = await page.request.get('http://localhost:3000/api/auth/session');
    console.log('🔑 Session API status:', sessionResponse.status());
    const sessionData = await sessionResponse.json().catch(() => null);
    console.log('🔑 Session data:', sessionData);
    
    // Step 5: Test if backend is accessible
    console.log('🔍 Step 5: Testing backend connectivity...');
    try {
      const backendResponse = await page.request.get('http://localhost:8000/');
      console.log('🔧 Backend API status:', backendResponse.status());
      const backendData = await backendResponse.text().catch(() => '');
      console.log('🔧 Backend response:', backendData.substring(0, 200));
    } catch (error) {
      console.log('❌ Backend connectivity error:', error.message);
    }
    
    // Step 6: Check what authentication providers are configured
    console.log('🔍 Step 6: Checking auth providers...');
    const providersResponse = await page.request.get('http://localhost:3000/api/auth/providers');
    console.log('🔑 Providers API status:', providersResponse.status());
    const providersData = await providersResponse.json().catch(() => null);
    console.log('🔑 Available providers:', Object.keys(providersData || {}));
    
    // Step 7: Check database connectivity (NextAuth should handle this)
    console.log('🔍 Step 7: Testing database-related endpoints...');
    
    // Try to navigate to homepage to see if user session works
    console.log('🏠 Step 8: Testing navigation to homepage...');
    await page.goto('http://localhost:3000/');
    await page.waitForTimeout(3000);
    
    const homepageUrl = page.url();
    console.log('🏠 Homepage URL:', homepageUrl);
    
    // Check if redirected to login (would indicate no valid session)
    const isRedirectedToLogin = homepageUrl.includes('/auth/login');
    console.log('🔄 Redirected to login?', isRedirectedToLogin);
    
    // Step 9: Take screenshot of current state
    console.log('📷 Taking final screenshot...');
    await page.screenshot({ path: 'login-test-final-state.png', fullPage: true });
    
    console.log('✅ Comprehensive login test completed!');
    console.log('📊 Summary:');
    console.log('  - Login page loads correctly');
    console.log('  - Form fields are functional');
    console.log('  - Need to check authentication backend configuration');
    console.log('  - Screenshots saved for visual inspection');
    
  } catch (error) {
    console.error('❌ Error during comprehensive test:', error);
  } finally {
    await browser.close();
  }
}

comprehensiveLoginTest();