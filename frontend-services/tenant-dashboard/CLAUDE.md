# PyAirtable Tenant Dashboard - Claude Context

## 🎯 Service Purpose
Modern Next.js 15 frontend application providing comprehensive tenant management interface for PyAirtable platform users. Features complete UI for workspace management, team collaboration, billing, settings, and security compliance.

## 🔧 Technology Stack
- **Framework:** Next.js 15 with App Router and TypeScript
- **Styling:** Tailwind CSS with custom design system
- **UI Components:** Radix UI primitives with custom styling  
- **Testing:** **Playwright for visual testing and E2E automation**
- **Alternative Testing:** **Puppeteer available for headless testing**
- **State Management:** Zustand with TanStack Query for server state
- **Charts & Analytics:** Recharts for data visualization
- **Performance:** Built-in Next.js optimizations with PWA support

## 🎭 Visual Testing with Playwright

### **Playwright Configuration**
```bash
# Playwright is installed and configured
npm run test:visual            # Run visual tests
npm run test:visual:update     # Update visual baselines
npm run test:e2e              # Run end-to-end tests
npm run test:headed           # Run tests in headed mode
```

### **Available Test Types**
- **Visual Regression:** Screenshot-based UI testing with automatic diff detection
- **Cross-Browser Testing:** Chromium, Firefox, and WebKit support
- **Mobile Testing:** Responsive design validation on mobile viewports  
- **Accessibility Testing:** WCAG compliance validation
- **Performance Testing:** Core Web Vitals measurement

### **Playwright Test Structure**
```
e2e/
├── auth.spec.ts                    # Authentication flow tests
├── airtable-integration-journey.spec.ts  # Full Airtable workflow tests
├── chat-interface-journey.spec.ts # AI chat functionality tests
├── complete-user-journey.spec.ts  # End-to-end user scenarios
├── visual-regression.spec.ts      # Visual testing with screenshots
├── fixtures/
│   └── test-users.ts              # Test data and user fixtures
└── helpers/
    ├── auth-helpers.ts            # Authentication test utilities
    ├── chat-helpers.ts            # Chat testing utilities
    └── common-helpers.ts          # Shared test utilities
```

### **Synthetic Agent Testing**

#### **Human-Like Test Agents**
The dashboard includes **synthetic agents that simulate real user behavior**:

```typescript
// Real user simulation examples
await page.pause(humanDelay(500, 1500));  // Natural pause times
await page.mouse.move(x, y, { steps: 10 }); // Realistic mouse movement
await page.keyboard.type(text, { delay: 120 }); // Human typing speed
```

#### **Available Synthetic Behaviors**
- **Realistic Typing:** Variable speed typing with natural pauses
- **Mouse Movement:** Curved paths and realistic click patterns
- **Reading Simulation:** Proper page scroll and content consumption
- **Error Recovery:** How real users handle and recover from errors
- **Multi-tab Workflows:** Complex workflows across multiple browser tabs

### **E2E Testing Capabilities**

#### **Complete User Journeys**
1. **New User Onboarding:** Registration → Email verification → Airtable setup → First interaction
2. **Daily Workflow:** Login → Check analytics → Manage team → Update workspace
3. **Billing Cycle:** Plan review → Usage monitoring → Upgrade flow → Payment processing
4. **Error Scenarios:** Network failures → Service outages → Invalid data handling

#### **Test Scenarios Available**
- **Authentication Flow:** Login, logout, password reset, 2FA setup
- **Airtable Integration:** Base connection, table operations, data synchronization
- **Team Management:** Invitations, role assignments, permission management
- **Workspace Operations:** Create, configure, share, archive workspaces
- **Chat Interface:** AI interactions, conversation history, file attachments

## 🤖 Puppeteer Integration

### **Headless Testing Support**
```bash
# Puppeteer is available for headless automation
npm run test:puppeteer         # Run Puppeteer tests
npm run test:performance       # Performance testing with Puppeteer
npm run test:accessibility     # Accessibility audits
```

### **Puppeteer Use Cases**
- **PDF Generation:** Automated report generation from dashboard data
- **Performance Monitoring:** Lighthouse audits and Core Web Vitals
- **Screenshot Automation:** Bulk screenshot generation for documentation
- **API Integration Testing:** Backend service integration validation

## 🚀 Local Development with Visual Testing

### **Development Setup**
```bash
# Install dependencies and browsers
npm install
npx playwright install         # Install browser engines

# Start development server
npm run dev                    # Starts on http://localhost:3000

# Environment setup
cp .env.example .env.local
# Configure API endpoints:
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXT_PUBLIC_WS_URL=ws://localhost:8000
```

### **Testing Workflow**
```bash
# 1. Start backend services (from project root)
docker-compose -f docker-compose.minimal.yml up -d

# 2. Start frontend development server
npm run dev

# 3. Run visual tests
npm run test:visual            # Full visual regression suite
npm run test:e2e              # Complete end-to-end scenarios
npm run test:visual:update    # Update visual baselines after UI changes

# 4. Debug failing tests
npm run test:debug            # Debug mode with browser dev tools
npm run test:headed           # Run with visible browser
```

### **Test Data Management**
```bash
# Test fixtures and mock data
e2e/fixtures/
├── test-users.ts             # User accounts for testing
├── airtable-data.json        # Mock Airtable responses
└── workspace-templates.json  # Workspace test data
```

## 📱 Mobile and Responsive Testing

### **Viewport Testing**
```bash
# Mobile viewport testing
npm run test:mobile           # Test mobile-specific layouts
npm run test:responsive       # Test all breakpoints
npm run test:cross-device     # Test across device types
```

### **Device Emulation**
- **Mobile Devices:** iPhone, Android, iPad testing
- **Desktop Resolutions:** Multiple screen sizes and pixel densities
- **Touch vs. Mouse:** Different interaction patterns
- **Network Conditions:** Slow 3G, offline scenarios

## 🎨 Visual Regression Testing

### **Screenshot Management**
```bash
# Visual testing commands
npm run test:visual:chromium  # Chrome-specific visual tests
npm run test:visual:firefox   # Firefox visual validation  
npm run test:visual:webkit    # Safari/WebKit testing

# Update visual baselines
npm run test:visual:update    # Update all screenshots
npm run test:visual:approve   # Approve visual changes
```

### **Visual Test Categories**
- **Layout Tests:** Page structure and component positioning
- **Styling Tests:** Colors, fonts, spacing validation
- **Responsive Tests:** Mobile and desktop layout verification
- **Interactive States:** Hover, focus, active state testing
- **Dark Mode Tests:** Theme switching validation

## 🔍 Performance and Accessibility

### **Performance Testing**
```bash
# Performance validation
npm run test:lighthouse      # Lighthouse audits
npm run test:core-vitals     # Core Web Vitals measurement
npm run test:bundle-size     # Bundle size analysis
```

### **Accessibility Testing**
```bash
# Accessibility validation
npm run test:a11y            # WCAG compliance testing
npm run test:keyboard        # Keyboard navigation testing
npm run test:screen-reader   # Screen reader compatibility
```

## 🛠️ Development Commands

### **Container Development**
```bash
# Using Colima (Docker Desktop replacement)
colima start --cpu 4 --memory 8

# Development with hot reload
docker-compose -f docker-compose.dev.yml up frontend-tenant-dashboard

# Production build testing
docker build -t tenant-dashboard .
docker run -p 3000:3000 tenant-dashboard
```

### **Testing in Minikube**
```bash
# Deploy to local Kubernetes
minikube start
kubectl apply -f k8s/frontend-deployment.yaml

# Access via port forwarding
kubectl port-forward svc/tenant-dashboard 3000:3000
```

## 🔧 Debugging and Troubleshooting

### **Visual Test Debugging**
```bash
# Debug failed visual tests
npm run test:debug           # Interactive debugging
npm run test:trace           # Generate test traces
npm run test:report          # View HTML test report

# View test artifacts
open test-results/         # Screenshots and videos
open test-results-visual-html/index.html  # Visual test report
```

### **Performance Debugging**  
```bash
# Analyze performance issues
npm run analyze              # Bundle analyzer
npm run lighthouse          # Performance audit
npm run test:memory         # Memory leak detection
```

### **Common Issues**
- **Visual Test Failures:** Check browser differences, update baselines
- **API Integration:** Verify backend services are running
- **Authentication:** Ensure auth service is functional
- **Performance:** Check bundle size and Core Web Vitals

## 📊 Current Status

### **✅ Working Features**
- **UI Components:** All components rendered correctly
- **Responsive Design:** Mobile and desktop layouts functional
- **Visual Testing:** Playwright configured and operational
- **Development Server:** Local development working

### **❌ Integration Issues**
- **Backend API:** Authentication endpoints failing (500 errors)
- **Airtable Integration:** API connection broken ("Invalid API key")
- **Real Data:** Currently using mock data due to backend issues
- **WebSocket:** Real-time features not functional

### **🔧 Immediate Fixes Needed**
1. **Backend Integration:** Fix API Gateway routing to services
2. **Authentication:** Resolve login/registration endpoint failures  
3. **Airtable API:** Fix API key configuration
4. **WebSocket Connection:** Enable real-time updates

## 🎯 Testing Strategy

### **Test Pyramid Structure**
- **Unit Tests (Jest):** Component logic and utilities
- **Integration Tests (Playwright):** API and service integration  
- **E2E Tests (Playwright):** Complete user workflows
- **Visual Tests (Playwright):** UI regression detection
- **Performance Tests (Lighthouse):** Speed and accessibility

### **Continuous Testing**
- **Pre-commit:** Visual regression tests
- **CI/CD Pipeline:** Full test suite on pull requests  
- **Nightly:** Cross-browser testing and performance audits
- **Release:** Complete E2E validation before deployment

## 📞 Getting Help

### **Visual Testing Issues**
- Check `test-results-visual-html/index.html` for detailed test reports
- Review screenshot diffs in `test-results-visual/` directory
- Run `npm run test:headed` to see tests execute in real browsers

### **Development Issues**
- Verify backend services: `docker-compose ps`
- Check API connectivity: `curl http://localhost:8000/api/health`
- Review logs: `docker-compose logs api-gateway`

---

**Status:** Frontend operational with visual testing capabilities. Backend integration blocked by service failures.  
**Priority:** Fix backend authentication and API integration for full functionality.  
**Testing:** Comprehensive Playwright and Puppeteer setup ready for development.