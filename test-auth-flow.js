// Using native fetch API available in Node.js 18+

async function testAuthFlow() {
  const baseUrl = 'http://localhost:3004';
  
  console.log('Testing authentication flow...\n');
  
  try {
    // Step 1: Test backend auth service directly
    console.log('1. Testing backend auth service registration...');
    const registerResponse = await fetch('http://localhost:8007/auth/register', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: 'flow-test@example.com',
        password: 'TestPassword123',
        first_name: 'Flow',
        last_name: 'Test',
        tenant_id: '550e8400-e29b-41d4-a716-446655440000'
      })
    });
    
    if (registerResponse.ok) {
      const registerData = await registerResponse.json();
      console.log('✅ Backend registration successful:', registerData.email);
    } else {
      const errorData = await registerResponse.json();
      console.log('⚠️ Backend registration result:', errorData);
    }
    
    // Step 2: Test backend login
    console.log('\n2. Testing backend auth service login...');
    const loginResponse = await fetch('http://localhost:8007/auth/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: 'flow-test@example.com',
        password: 'TestPassword123'
      })
    });
    
    if (loginResponse.ok) {
      const loginData = await loginResponse.json();
      console.log('✅ Backend login successful, token received');
      console.log('Access token length:', loginData.access_token.length);
      
      // Decode JWT payload to show user info
      const jwtPayload = JSON.parse(Buffer.from(loginData.access_token.split('.')[1], 'base64').toString());
      console.log('User info from JWT:', {
        email: jwtPayload.email,
        role: jwtPayload.role,
        user_id: jwtPayload.user_id
      });
    } else {
      console.log('❌ Backend login failed');
    }
    
    // Step 3: Test frontend registration API
    console.log('\n3. Testing frontend registration API...');
    const frontendRegisterResponse = await fetch(`${baseUrl}/api/auth/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: 'Frontend Test User',
        email: 'frontend-test@example.com',
        password: 'TestPassword123'
      })
    });
    
    if (frontendRegisterResponse.ok) {
      const frontendRegisterData = await frontendRegisterResponse.json();
      console.log('✅ Frontend registration API successful:', frontendRegisterData.user.email);
    } else {
      const error = await frontendRegisterResponse.json();
      console.log('❌ Frontend registration failed:', error);
    }
    
    console.log('\n🎉 Authentication flow test completed!');
    console.log('\nNext steps:');
    console.log('- Visit http://localhost:3004/auth/login to test the login UI');
    console.log('- Visit http://localhost:3004/auth/register to test the registration UI');
    console.log('- Backend auth service is running on http://localhost:8007');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  }
}

testAuthFlow();