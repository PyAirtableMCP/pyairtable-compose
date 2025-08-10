/**
 * Investigate Authentication Flow
 * 
 * This test specifically checks:
 * 1. What's on the homepage 
 * 2. Direct navigation to auth pages
 * 3. Content of auth pages
 */

const { chromium } = require('playwright');
const fs = require('fs');

async function investigateAuthFlow() {
  console.log('🔍 Investigating Authentication Flow...');
  
  const browser = await chromium.launch({ 
    headless: false, 
    slowMo: 1000 
  });
  const page = await browser.newPage();
  
  try {
    // 1. Homepage analysis
    console.log('\n📍 Step 1: Homepage Analysis');
    await page.goto('http://localhost:3000');
    await page.waitForTimeout(3000);
    
    const title = await page.title();
    console.log('Page title:', title);
    
    // Take homepage screenshot
    await page.screenshot({ 
      path: './homepage-detailed.png', 
      fullPage: true 
    });
    
    // Look for all links and buttons
    const links = await page.locator('a').all();
    console.log(`Found ${links.length} links on homepage:`);
    
    for (let i = 0; i < links.length; i++) {
      try {
        const href = await links[i].getAttribute('href');
        const text = await links[i].textContent();
        if (href && text && text.trim()) {
          console.log(`  - "${text.trim()}" -> ${href}`);
        }
      } catch (e) {}
    }
    
    const buttons = await page.locator('button').all();
    console.log(`\nFound ${buttons.length} buttons on homepage:`);
    
    for (let i = 0; i < buttons.length; i++) {
      try {
        const text = await buttons[i].textContent();
        const type = await buttons[i].getAttribute('type');
        const className = await buttons[i].getAttribute('class');
        if (text && text.trim()) {
          console.log(`  - "${text.trim()}" (type: ${type}, class: ${className})`);
        }
      } catch (e) {}
    }
    
    // 2. Direct login page test
    console.log('\n📍 Step 2: Direct Login Page Test');
    const loginResponse = await page.goto('http://localhost:3000/auth/login');
    console.log('Login page status:', loginResponse.status());
    
    await page.waitForTimeout(2000);
    await page.screenshot({ 
      path: './login-page-detailed.png', 
      fullPage: true 
    });
    
    const loginTitle = await page.title();
    console.log('Login page title:', loginTitle);
    
    // Check for form elements on login page
    const loginEmailInputs = await page.locator('input[type="email"], input[name="email"]').count();
    const loginPasswordInputs = await page.locator('input[type="password"]').count();
    const loginSubmitButtons = await page.locator('button[type="submit"], button:has-text("login"), button:has-text("sign in")').count();
    
    console.log('Login page form elements:');
    console.log(`  - Email inputs: ${loginEmailInputs}`);
    console.log(`  - Password inputs: ${loginPasswordInputs}`);
    console.log(`  - Submit buttons: ${loginSubmitButtons}`);
    
    // 3. Direct register page test
    console.log('\n📍 Step 3: Direct Register Page Test');
    const registerResponse = await page.goto('http://localhost:3000/auth/register');
    console.log('Register page status:', registerResponse.status());
    
    await page.waitForTimeout(2000);
    await page.screenshot({ 
      path: './register-page-detailed.png', 
      fullPage: true 
    });
    
    const registerTitle = await page.title();
    console.log('Register page title:', registerTitle);
    
    // Check for form elements on register page
    const regEmailInputs = await page.locator('input[type="email"], input[name="email"]').count();
    const regPasswordInputs = await page.locator('input[type="password"]').count();
    const regSubmitButtons = await page.locator('button[type="submit"], button:has-text("register"), button:has-text("sign up")').count();
    
    console.log('Register page form elements:');
    console.log(`  - Email inputs: ${regEmailInputs}`);
    console.log(`  - Password inputs: ${regPasswordInputs}`);
    console.log(`  - Submit buttons: ${regSubmitButtons}`);
    
    // 4. Test actual form filling on login page
    if (loginEmailInputs > 0 && loginPasswordInputs > 0) {
      console.log('\n📍 Step 4: Testing Login Form Filling');
      await page.goto('http://localhost:3000/auth/login');
      await page.waitForTimeout(1000);
      
      const emailField = page.locator('input[type="email"], input[name="email"]').first();
      const passwordField = page.locator('input[type="password"]').first();
      
      await emailField.fill('test@example.com');
      await passwordField.fill('testpassword123');
      
      await page.screenshot({ 
        path: './login-form-filled-detailed.png', 
        fullPage: true 
      });
      
      console.log('✅ Successfully filled login form');
      
      // Try to submit
      const submitButton = page.locator('button[type="submit"]').first();
      if (await submitButton.count() > 0) {
        console.log('Clicking submit button...');
        await submitButton.click();
        await page.waitForTimeout(3000);
        
        await page.screenshot({ 
          path: './login-after-submit-detailed.png', 
          fullPage: true 
        });
        
        console.log('Final URL after login:', page.url());
      }
    }
    
    // 5. Check dashboard access
    console.log('\n📍 Step 5: Testing Dashboard Access');
    try {
      const dashboardResponse = await page.goto('http://localhost:3000/dashboard');
      console.log('Dashboard page status:', dashboardResponse.status());
      
      await page.waitForTimeout(2000);
      await page.screenshot({ 
        path: './dashboard-page-detailed.png', 
        fullPage: true 
      });
      
      const dashboardTitle = await page.title();
      console.log('Dashboard page title:', dashboardTitle);
    } catch (e) {
      console.log('Dashboard access error:', e.message);
    }
    
  } catch (error) {
    console.error('Investigation error:', error.message);
  } finally {
    await browser.close();
  }
}

investigateAuthFlow();