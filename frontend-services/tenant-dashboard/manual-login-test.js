const { chromium } = require('playwright');

async function manualLoginTest() {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();
  
  console.log('🔍 Starting manual login flow investigation...');
  
  try {
    // Navigate to the login page
    console.log('📍 Navigating to /auth/login...');
    await page.goto('http://localhost:3000/auth/login');
    await page.waitForTimeout(3000);
    
    // Take a screenshot
    console.log('📷 Taking screenshot of login page...');
    await page.screenshot({ path: 'login-page-screenshot.png', fullPage: true });
    
    // Check what's actually on the page
    console.log('🔍 Examining page content...');
    const title = await page.title();
    console.log('📄 Page title:', title);
    
    const url = page.url();
    console.log('🔗 Current URL:', url);
    
    // Look for headings
    const headings = await page.locator('h1, h2, h3, h4, h5, h6').allTextContents();
    console.log('📝 Found headings:', headings);
    
    // Look for any text containing login/signin
    const loginTexts = await page.locator('text=/sign|login/i').allTextContents();
    console.log('🔑 Found login-related text:', loginTexts);
    
    // Check for email/password fields
    const emailField = await page.locator('input[type="email"], input[name="email"], [placeholder*="email" i]').first();
    const passwordField = await page.locator('input[type="password"], input[name="password"], [placeholder*="password" i]').first();
    
    console.log('📧 Email field present:', await emailField.isVisible().catch(() => false));
    console.log('🔒 Password field present:', await passwordField.isVisible().catch(() => false));
    
    // Check for buttons
    const buttons = await page.locator('button').allTextContents();
    console.log('🔘 Found buttons:', buttons);
    
    // Try to find any form
    const forms = await page.locator('form').count();
    console.log('📋 Number of forms found:', forms);
    
    // Get page HTML to understand the structure
    const bodyText = await page.locator('body').textContent();
    console.log('📄 Page contains text about login?:', bodyText?.toLowerCase().includes('login') || bodyText?.toLowerCase().includes('sign'));
    
    // Check if it's an error page or loading state
    const errorMessages = await page.locator('[role="alert"], .error, .text-red').allTextContents();
    console.log('❌ Error messages:', errorMessages);
    
    console.log('✅ Manual investigation complete. Check login-page-screenshot.png for visual inspection.');
    
  } catch (error) {
    console.error('❌ Error during manual test:', error);
  } finally {
    await browser.close();
  }
}

manualLoginTest();