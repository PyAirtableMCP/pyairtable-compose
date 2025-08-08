const { chromium } = require('playwright');

async function testNetworkRequests() {
  console.log('🌐 Testing network requests during login...');
  
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  // Listen to all network requests
  page.on('request', request => {
    if (request.url().includes('auth') || request.url().includes('api')) {
      console.log('📤', request.method(), request.url());
    }
  });

  page.on('response', response => {
    if (response.url().includes('auth') || response.url().includes('api')) {
      console.log('📥', response.status(), response.url());
    }
  });

  try {
    await page.goto('http://localhost:3000/auth/login', { waitUntil: 'networkidle' });
    console.log('📝 Page loaded');

    await page.locator('input[type="email"]').fill('testuser@example.com');
    await page.locator('input[type="password"]').fill('TestPassword123');
    
    console.log('🔘 Clicking submit button...');
    await page.getByRole('button', { name: /sign in/i }).click();
    
    // Wait to see network requests
    await page.waitForTimeout(5000);
    
    console.log('✅ Test completed');

  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    setTimeout(() => browser.close(), 2000);
  }
}

testNetworkRequests();