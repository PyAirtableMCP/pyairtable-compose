const { chromium } = require('playwright');

async function checkAuthenticatedPage() {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();
  
  try {
    console.log('🔍 Checking authenticated page structure...');
    
    // First login
    await page.goto('http://localhost:3000/auth/login');
    await page.waitForTimeout(2000);
    
    await page.locator('input[type="email"]').fill('testuser@example.com');
    await page.locator('input[type="password"]').fill('TestPassword123');
    await page.locator('button[type="submit"]').click();
    
    // Wait for redirect
    await page.waitForTimeout(5000);
    
    const currentUrl = page.url();
    console.log('🔗 Current URL after login:', currentUrl);
    
    // Check what authentication indicators are present
    console.log('🔍 Checking for authentication indicators...');
    
    // Check for various common auth indicators
    const authIndicators = [
      'text=/welcome/i',
      'text=/dashboard/i', 
      'button[name*="logout" i]',
      'button:has-text("Logout")',
      'button:has-text("Sign out")',
      '[data-testid="user-menu"]',
      '.user-avatar',
      '[role="navigation"]',
      'header',
      'main',
      'text=/chat/i',
      'text=/pyairtable/i'
    ];
    
    for (const selector of authIndicators) {
      try {
        const count = await page.locator(selector).count();
        const visible = count > 0 ? await page.locator(selector).first().isVisible() : false;
        console.log(`${visible ? '✅' : '❌'} ${selector}: ${count} found, ${visible ? 'visible' : 'not visible'}`);
      } catch (e) {
        console.log(`❌ ${selector}: error - ${e.message}`);
      }
    }
    
    // Check page title
    const title = await page.title();
    console.log('📄 Page title:', title);
    
    // Get some text content to understand what's on the page
    const bodyText = await page.locator('body').textContent();
    const firstFewWords = bodyText?.substring(0, 200);
    console.log('📝 First 200 chars of page:', firstFewWords);
    
    // Check if the page has navigation or user menu
    const nav = await page.locator('nav').count();
    const header = await page.locator('header').count();
    const main = await page.locator('main').count();
    
    console.log('🧭 Navigation elements:');
    console.log(`  nav: ${nav}, header: ${header}, main: ${main}`);
    
    console.log('✅ Authenticated page analysis complete');
    
  } catch (error) {
    console.error('❌ Analysis error:', error);
  } finally {
    await browser.close();
  }
}

checkAuthenticatedPage();