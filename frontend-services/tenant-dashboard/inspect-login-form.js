const { chromium } = require('playwright');

async function inspectLoginForm() {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();
  
  try {
    console.log('🔍 Inspecting login form structure...');
    
    await page.goto('http://localhost:3000/auth/login');
    await page.waitForTimeout(3000);
    
    // Check form structure
    console.log('📋 Form inspection:');
    
    // Check for email inputs
    const emailInputs = await page.locator('input[type="email"]').count();
    console.log('📧 Email inputs found:', emailInputs);
    
    if (emailInputs > 0) {
      const emailPlaceholder = await page.locator('input[type="email"]').getAttribute('placeholder');
      const emailName = await page.locator('input[type="email"]').getAttribute('name');
      console.log('📧 Email placeholder:', emailPlaceholder);
      console.log('📧 Email name attribute:', emailName);
    }
    
    // Check for password inputs
    const passwordInputs = await page.locator('input[type="password"]').count();
    console.log('🔒 Password inputs found:', passwordInputs);
    
    if (passwordInputs > 0) {
      const passwordPlaceholder = await page.locator('input[type="password"]').getAttribute('placeholder');
      const passwordName = await page.locator('input[type="password"]').getAttribute('name');
      console.log('🔒 Password placeholder:', passwordPlaceholder);
      console.log('🔒 Password name attribute:', passwordName);
    }
    
    // Check for labels
    const labels = await page.locator('label').allTextContents();
    console.log('🏷️ Labels found:', labels);
    
    // Check for buttons
    const buttons = await page.locator('button').allTextContents();
    console.log('🔘 Buttons found:', buttons);
    
    // Check if we can target by placeholder
    const emailByPlaceholder = await page.locator('input[placeholder*="email" i]').count();
    const passwordByPlaceholder = await page.locator('input[placeholder*="password" i]').count();
    console.log('📧 Email by placeholder:', emailByPlaceholder);
    console.log('🔒 Password by placeholder:', passwordByPlaceholder);
    
    // Try filling the form with different selectors
    console.log('✏️ Testing form filling...');
    
    try {
      await page.locator('input[type="email"]').fill('test@example.com');
      console.log('✅ Email filled successfully with input[type="email"]');
    } catch (e) {
      console.log('❌ Email filling failed:', e.message);
    }
    
    try {
      await page.locator('input[type="password"]').fill('testpassword');
      console.log('✅ Password filled successfully with input[type="password"]');
    } catch (e) {
      console.log('❌ Password filling failed:', e.message);
    }
    
    // Test submit button
    try {
      const submitButton = page.locator('button[type="submit"]');
      const isVisible = await submitButton.isVisible();
      console.log('🔘 Submit button visible:', isVisible);
    } catch (e) {
      console.log('❌ Submit button check failed:', e.message);
    }
    
    console.log('✅ Form inspection complete');
    
  } catch (error) {
    console.error('❌ Inspection error:', error);
  } finally {
    await browser.close();
  }
}

inspectLoginForm();