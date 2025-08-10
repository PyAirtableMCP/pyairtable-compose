# PyAirtable Auth Frontend - Claude Context

## 🎯 Service Purpose
Dedicated authentication frontend for PyAirtable platform providing secure user registration, login, password management, and multi-factor authentication. Serves as the authentication gateway for all PyAirtable services.

## 🔧 Technology Stack
- **Framework:** Next.js 15 with App Router and TypeScript
- **Styling:** Tailwind CSS with authentication-focused design
- **UI Components:** Radix UI with enhanced security components
- **Testing:** **Playwright configured for authentication flow testing**
- **Alternative Testing:** **Puppeteer for automated security testing**
- **Authentication:** NextAuth.js with multiple provider support
- **Security:** Enhanced security features including 2FA and biometrics
- **State Management:** Secure session management with JWT

## 🎭 Authentication Testing with Playwright

### **Auth-Specific Testing**
```bash
# Authentication flow test commands
npm run test:auth-flows         # Complete authentication workflows
npm run test:registration       # User registration scenarios
npm run test:login              # Login flow validation
npm run test:password-reset     # Password reset workflows
npm run test:mfa                # Multi-factor authentication testing
npm run test:security           # Security vulnerability testing
npm run test:visual:auth        # Auth UI visual regression
```

### **Authentication Test Scenarios**
- **User Registration:** Email validation, password strength, terms acceptance
- **Login Flows:** Username/email login, remember me, session management
- **Password Management:** Password reset, change password, strength validation
- **Multi-Factor Auth:** TOTP, SMS, email verification, backup codes
- **Social Login:** OAuth providers (Google, GitHub, etc.)
- **Security Features:** Rate limiting, CAPTCHA, account lockout

### **Synthetic Authentication Agents**

#### **Realistic Auth Behavior Simulation**
```typescript
// Human-like authentication patterns
await authAgent.attemptLogin(credentials, { typos: true, delays: true });
await authAgent.handleMFAPrompt(totpCode, { humanDelay: true });
await authAgent.completePasswordReset(resetLink, newPassword);
await authAgent.simulateSessionTimeout();
```

#### **Security-Focused Testing Behaviors**
- **Brute Force Simulation:** Rate limiting and lockout testing
- **Social Engineering:** Phishing and security awareness testing
- **Session Management:** Session hijacking and fixation testing
- **Input Validation:** XSS and injection attempt simulation

## 🔐 Authentication Features

### **User Registration**
- **Email Verification:** Secure email validation and activation
- **Password Strength:** Real-time password strength validation
- **Terms and Privacy:** Legal compliance and consent management
- **Account Activation:** Secure account activation workflows
- **Data Validation:** Comprehensive input validation and sanitization

### **Login Management**
- **Multiple Login Methods:** Email, username, phone number support
- **Remember Me:** Secure persistent login with proper expiration
- **Device Management:** Trusted device registration and management
- **Session Security:** Secure session tokens with automatic refresh
- **Login Analytics:** Login attempt tracking and anomaly detection

### **Multi-Factor Authentication**
- **TOTP Support:** Time-based one-time password with QR codes
- **SMS Verification:** SMS-based two-factor authentication
- **Email Verification:** Email-based verification codes
- **Backup Codes:** Recovery codes for account access
- **Biometric Auth:** WebAuthn support for biometric authentication

### **Password Management**
- **Password Reset:** Secure password reset with email verification
- **Password Change:** Authenticated password change workflows
- **Password History:** Prevention of password reuse
- **Strength Requirements:** Configurable password complexity rules
- **Breach Detection:** Integration with breach detection services

### **Social Authentication**
- **OAuth Providers:** Google, GitHub, Microsoft, Apple integration
- **Provider Management:** Link/unlink social accounts
- **Profile Sync:** Automatic profile synchronization from providers
- **Privacy Controls:** Granular permission management for social data

## 🤖 Automated Security Testing with Puppeteer

### **Security Automation**
```bash
# Automated security testing
npm run automate:security-scan    # Automated vulnerability scanning
npm run automate:penetration-test # Automated penetration testing
npm run automate:compliance-check # Security compliance validation
npm run automate:session-testing  # Session security testing
```

### **Puppeteer Security Use Cases**
- **Vulnerability Assessment:** Automated security vulnerability detection
- **Compliance Testing:** OWASP and security standard compliance
- **Performance Testing:** Authentication performance under load
- **Integration Testing:** Cross-service authentication validation

## 🎨 Authentication UI Visual Testing

### **Auth-Specific Visual Tests**
```bash
# Authentication UI visual validation
npm run test:visual:login        # Login form layouts and states
npm run test:visual:register     # Registration form validation
npm run test:visual:mfa          # Multi-factor auth interfaces
npm run test:visual:password     # Password management forms
```

### **Visual Test Categories**
- **Form Layouts:** Authentication form design and responsiveness
- **Error States:** Error message display and formatting
- **Success States:** Confirmation and success message display
- **Loading States:** Authentication processing indicators
- **Security Indicators:** Trust signals and security status displays

## 🚀 Local Development for Auth Frontend

### **Auth Development Setup**
```bash
# Setup authentication development
npm install
npx playwright install

# Authentication environment variables
cp .env.auth.example .env.local
# Configure authentication settings:
NEXTAUTH_URL=http://localhost:3004
NEXTAUTH_SECRET=your-secret-key
AUTH_API_URL=http://localhost:8007
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
```

### **Auth Development Workflow**
```bash
# 1. Start authentication backend services
docker-compose -f docker-compose.auth.yml up -d

# 2. Start auth frontend
npm run dev:auth               # Starts on http://localhost:3004

# 3. Run authentication tests
npm run test:auth-flows        # Authentication workflow tests
npm run test:security          # Security testing
npm run test:mfa               # Multi-factor auth tests

# 4. Visual regression for auth UI
npm run test:visual:auth       # Auth interface visual tests
```

## 🔒 Security Features and Testing

### **Security Testing**
```bash
# Security-focused testing
npm run test:vulnerability      # Vulnerability testing
npm run test:rate-limiting     # Rate limiting validation
npm run test:session-security  # Session security testing
npm run test:input-validation  # Input validation testing
```

### **Security Features**
- **Rate Limiting:** Configurable rate limits for authentication attempts
- **Account Lockout:** Automatic account lockout after failed attempts
- **CAPTCHA Integration:** Bot protection with reCAPTCHA
- **IP Blocking:** Suspicious IP address blocking and monitoring
- **Device Fingerprinting:** Device identification for fraud prevention

## 📱 Mobile Authentication

### **Mobile Auth Testing**
```bash
# Mobile authentication testing
npm run test:mobile:auth       # Mobile auth interface testing
npm run test:biometric:mobile  # Mobile biometric testing
npm run test:responsive:auth   # Auth responsive design
```

### **Mobile Auth Features**
- **Touch ID/Face ID:** Biometric authentication on supported devices
- **Mobile-Optimized UI:** Touch-friendly authentication interfaces
- **SMS Integration:** SMS-based verification and notifications
- **Push Notifications:** Authentication alerts and notifications
- **Offline Support:** Limited offline authentication capabilities

## 🎯 Auth Performance and Analytics

### **Performance Testing**
```bash
# Authentication performance testing
npm run test:performance:auth  # Auth performance testing
npm run test:load:login        # Login performance under load
npm run test:concurrency       # Concurrent authentication testing
npm run test:database-load     # Database performance with auth load
```

### **Authentication Analytics**
- **Login Success Rates:** Authentication success and failure metrics
- **Performance Metrics:** Authentication response times and throughput
- **Security Incidents:** Failed login attempts and security events
- **User Behavior:** Authentication pattern analysis and insights

## 🔍 Auth Debugging and Troubleshooting

### **Debug Tools**
```bash
# Authentication debugging
npm run debug:auth             # Interactive auth debugging
npm run logs:auth              # Authentication log analysis
npm run trace:auth-flows       # Authentication flow tracing
npm run validate:tokens        # JWT token validation
```

### **Common Auth Issues**
- **Token Expiration:** JWT token refresh and expiration handling
- **Session Management:** Session persistence and cleanup
- **Provider Integration:** OAuth provider connection issues
- **Database Connectivity:** User authentication database issues

## 🚨 Current Status - Auth Frontend

### **✅ Working Features**
- **Auth UI Framework:** Next.js authentication interface operational
- **Component Library:** Authentication-specific UI components
- **Development Environment:** Local development setup working
- **Testing Framework:** Playwright configured for auth testing

### **❌ Backend Integration Issues**
- **Auth Service Connection:** Platform Services (port 8007) integration issues
- **Database Authentication:** User authentication database not accessible
- **OAuth Providers:** Social authentication provider configuration missing
- **Session Management:** Backend session validation not working

### **🔧 Critical Auth Fixes Needed**
1. **Backend Auth Integration:** Fix Platform Services authentication endpoints
2. **Database Connection:** Resolve user authentication database connectivity
3. **OAuth Configuration:** Configure social authentication providers
4. **Session Management:** Implement secure session validation with backend

## 🎯 Authentication Testing Strategy

### **Test Coverage Areas**
- **Registration Flows:** Complete user registration workflows
- **Login Scenarios:** Various login methods and edge cases
- **Security Testing:** Authentication security and vulnerability testing
- **Performance Testing:** Authentication performance and scalability
- **Integration Testing:** Cross-service authentication validation

### **Testing Priorities**
1. **P0:** Core authentication flows (login, registration)
2. **P1:** Security features (MFA, rate limiting, session management)
3. **P2:** Advanced features (social login, biometrics)
4. **P3:** Analytics and monitoring integration

## 📊 Compliance and Legal

### **Privacy and Compliance**
- **GDPR Compliance:** EU privacy regulation compliance for auth data
- **CCPA Compliance:** California privacy rights for authentication
- **Data Minimization:** Collect only necessary authentication data
- **Right to Erasure:** Account deletion and data removal capabilities
- **Consent Management:** Clear consent mechanisms for data processing

### **Security Standards**
- **OWASP Compliance:** Authentication security best practices
- **OAuth 2.0/OIDC:** Standard authentication protocol implementation
- **SAML Support:** Enterprise single sign-on integration
- **NIST Guidelines:** Password and authentication security guidelines

## 📞 Auth Support and Help

### **Debug Auth Issues**
```bash
# Authentication debugging commands
npm run debug:login-failures   # Debug login failure issues
npm run validate:user-data     # Validate user authentication data
npm run test:connectivity      # Test backend connectivity
npm run repair:sessions        # Repair corrupted user sessions
```

### **Common Authentication Issues**
- **Login Failures:** Invalid credentials, account lockout, rate limiting
- **Registration Issues:** Email validation, password requirements
- **Session Problems:** Token expiration, session persistence
- **Provider Issues:** OAuth provider configuration and connectivity

---

**Status:** Authentication frontend ready, backend authentication service integration required.  
**Priority:** Fix Platform Services authentication endpoints and database connectivity.  
**Testing:** Comprehensive authentication testing capabilities available with Playwright.