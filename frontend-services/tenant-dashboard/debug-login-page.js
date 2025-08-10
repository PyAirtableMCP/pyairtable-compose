const { chromium } = require('playwright');

async function debugLoginPage() {
  console.log('🔍 Debugging login page structure...');
  
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    await page.goto('http://localhost:3000/auth/login', { waitUntil: 'networkidle' });
    console.log('📝 Page loaded successfully');

    // Take screenshot
    await page.screenshot({ path: 'debug-login-page.png', fullPage: true });
    console.log('📸 Screenshot saved as debug-login-page.png');

    // Check for email input
    console.log('\n📧 Looking for email field...');
    const emailFields = await page.locator('input[type="email"], input[name="email"], input[placeholder*="email" i]').all();
    console.log(`Found ${emailFields.length} potential email fields`);

    // Check for password input  
    console.log('\n🔒 Looking for password field...');
    const passwordFields = await page.locator('input[type="password"], input[name="password"], input[placeholder*="password" i]').all();
    console.log(`Found ${passwordFields.length} potential password fields`);

    // Check for sign in button
    console.log('\n🔘 Looking for sign in button...');
    const signInButtons = await page.locator('button:has-text("Sign In"), button:has-text("Login"), input[type="submit"]').all();
    console.log(`Found ${signInButtons.length} potential sign in buttons`);

    // Get page title and content
    const title = await page.title();
    console.log(`\n📄 Page title: ${title}`);

    // Check if there are any error messages
    const errors = await page.locator('.error, .alert, [role="alert"]').all();
    if (errors.length > 0) {
      console.log(`\n⚠️ Found ${errors.length} error/alert elements`);
      for (let i = 0; i < errors.length; i++) {
        const errorText = await errors[i].textContent();
        console.log(`   Error ${i + 1}: ${errorText}`);
      }
    }

    // Check page content
    const bodyText = await page.locator('body').textContent();
    if (bodyText.includes('loading') || bodyText.includes('Loading')) {
      console.log('⏳ Page might still be loading...');
    }

    console.log('\n✅ Debug completed successfully');

  } catch (error) {
    console.error('❌ Debug failed:', error.message);
  } finally {
    setTimeout(async () => {
      await browser.close();
    }, 2000); // Keep browser open for 2 seconds to see the page
  }
}

debugLoginPage();