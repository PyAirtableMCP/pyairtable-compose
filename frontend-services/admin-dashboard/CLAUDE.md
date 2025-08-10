# PyAirtable Admin Dashboard - Claude Context

## 🎯 Service Purpose
Administrative interface for PyAirtable platform operators providing system oversight, tenant management, user administration, configuration management, and operational monitoring capabilities.

## 🔧 Technology Stack
- **Framework:** Next.js 15 with App Router and TypeScript
- **Styling:** Tailwind CSS with administrative design system
- **UI Components:** Radix UI with enhanced data tables and admin controls
- **Testing:** **Playwright configured for admin workflow testing**
- **Alternative Testing:** **Puppeteer available for automated admin tasks**
- **State Management:** Zustand with TanStack Query for admin data
- **Charts:** Recharts for system metrics and analytics
- **Data Tables:** Advanced filtering, sorting, and bulk operations

## 🎭 Admin-Focused Visual Testing

### **Playwright Admin Testing**
```bash
# Admin-specific test commands
npm run test:admin             # Admin workflow tests
npm run test:tenant-management # Tenant admin scenarios
npm run test:user-admin        # User management tests
npm run test:system-config     # Configuration testing
npm run test:visual:admin      # Admin UI visual regression
```

### **Administrative Test Scenarios**
- **Tenant Management:** Create, suspend, activate, delete tenant accounts
- **User Administration:** Bulk user operations, role assignments, permissions
- **System Configuration:** Feature flags, system settings, service config
- **Operational Logs:** Log viewing, filtering, export functionality
- **Analytics Dashboard:** System metrics, usage patterns, performance data

### **Synthetic Admin Agents**

#### **Admin Workflow Automation**
```typescript
// Realistic admin behavior simulation
await adminAgent.performBulkUserOperation(users, 'suspend');
await adminAgent.auditSystemLogs('error', lastHour);
await adminAgent.reviewTenantUsage(tenantId);
await adminAgent.configureFeatureFlag('new-feature', 'enabled');
```

#### **Admin-Specific Behaviors**
- **Bulk Operations:** Efficient handling of multiple items
- **Data Validation:** Admin-level data integrity checks  
- **System Monitoring:** Proactive issue detection and response
- **Security Audits:** Access pattern analysis and anomaly detection

## 📊 Admin Dashboard Features

### **System Overview**
- **Service Health Monitoring:** Real-time status of all PyAirtable services
- **Resource Utilization:** CPU, memory, storage metrics across services
- **Error Rate Tracking:** System-wide error monitoring and alerting
- **Performance Metrics:** Response times, throughput, availability

### **Tenant Management**
- **Tenant Registry:** Complete list with status, plan, usage
- **Account Operations:** Create, suspend, reactivate, terminate accounts
- **Usage Analytics:** Per-tenant resource consumption and billing
- **Support Tools:** Account troubleshooting and user assistance

### **User Administration**  
- **User Directory:** System-wide user management with search and filters
- **Role Management:** Platform-wide role assignments and permissions
- **Security Operations:** Password resets, 2FA management, session control
- **Audit Trail:** Complete user activity logging and investigation tools

### **Configuration Management**
- **Feature Flags:** Global feature toggle management
- **System Settings:** Platform-wide configuration parameters
- **Service Configuration:** Individual service settings and parameters
- **Integration Management:** Third-party service connections

### **Operational Logs**
- **Centralized Logging:** Aggregated logs from all PyAirtable services
- **Advanced Filtering:** Search by service, level, user, tenant, time range
- **Export Capabilities:** Log data export for analysis and compliance
- **Alert Configuration:** Custom alerts based on log patterns

## 🤖 Automated Admin Tasks with Puppeteer

### **Administrative Automation**
```bash
# Automated admin operations
npm run automate:tenant-cleanup    # Automated tenant maintenance
npm run automate:user-audit        # Bulk user compliance checks
npm run automate:report-generation # Automated reporting
npm run automate:backup-validation # Verify backup operations
```

### **Puppeteer Admin Use Cases**
- **Report Generation:** Automated PDF reports for stakeholders
- **Data Export:** Bulk data extraction for analysis
- **System Health Checks:** Automated verification of system components
- **Compliance Audits:** Automated compliance validation and reporting

## 🔒 Security and Compliance Testing

### **Security Test Scenarios**
```bash
# Security-focused testing
npm run test:security           # Security compliance testing
npm run test:rbac              # Role-based access control validation
npm run test:audit-trail       # Audit logging verification
npm run test:data-privacy      # Privacy and data protection tests
```

### **Compliance Features**
- **GDPR Compliance:** Data subject rights, data portability, deletion
- **CCPA Compliance:** California privacy rights and data transparency
- **SOC 2 Auditing:** Security controls and audit trail maintenance
- **HIPAA Support:** Healthcare data protection where applicable

## 🎨 Admin UI Visual Testing

### **Admin-Specific Visual Tests**
```bash
# Admin interface visual validation
npm run test:visual:dashboard   # System overview dashboard
npm run test:visual:tables      # Data table layouts and pagination
npm run test:visual:forms       # Admin forms and configuration UI
npm run test:visual:charts      # Analytics and metrics visualizations
```

### **Visual Test Categories**
- **Dashboard Layouts:** Multi-panel admin interfaces
- **Data Tables:** Complex tables with sorting, filtering, bulk actions
- **Form Interfaces:** Configuration forms and admin inputs
- **Chart Visualizations:** System metrics and analytics displays
- **Modal Dialogs:** Admin confirmation and detail dialogs

## 🚀 Local Development for Admin Dashboard

### **Admin Development Setup**
```bash
# Setup admin development environment
npm install
npx playwright install

# Admin-specific environment variables
cp .env.admin.example .env.local
# Configure admin API endpoints:
NEXT_PUBLIC_ADMIN_API_URL=http://localhost:8000/admin
NEXT_PUBLIC_ADMIN_WS_URL=ws://localhost:8000/admin
ADMIN_SECRET_KEY=your-admin-secret
```

### **Admin Testing Workflow**
```bash
# 1. Start backend with admin privileges
docker-compose -f docker-compose.admin.yml up -d

# 2. Start admin dashboard
npm run dev:admin              # Starts on http://localhost:3001

# 3. Run admin-specific tests  
npm run test:admin             # Admin workflow tests
npm run test:tenant-ops        # Tenant management tests
npm run test:user-admin        # User administration tests

# 4. Visual regression for admin UI
npm run test:visual:admin      # Admin interface visual tests
```

## 📱 Admin Mobile Interface

### **Mobile Admin Testing**
```bash
# Mobile admin interface testing
npm run test:mobile:admin      # Mobile admin functionality
npm run test:responsive:admin  # Admin responsive design
npm run test:touch:admin       # Touch interaction for admin tasks
```

### **Mobile Admin Features**
- **Emergency Response:** Critical alerts and actions on mobile
- **System Status:** Quick system health checks on mobile
- **User Management:** Essential user operations from mobile
- **Approval Workflows:** Mobile-friendly approval processes

## 📊 Performance and Monitoring

### **Admin Performance Testing**
```bash
# Performance testing for admin operations
npm run test:performance:admin # Admin interface performance
npm run test:bulk-operations   # Bulk operation performance
npm run test:data-loading      # Large dataset loading tests
npm run test:export-operations # Data export performance
```

### **Performance Considerations**
- **Large Data Sets:** Efficient handling of thousands of users/tenants
- **Bulk Operations:** Performance optimization for batch operations
- **Real-time Updates:** WebSocket performance for live admin data
- **Export Operations:** Streaming large data exports

## 🔍 Admin Analytics and Reporting

### **Analytics Features**
- **Usage Patterns:** Platform usage analytics and trends
- **Cost Analysis:** Resource consumption and cost attribution
- **Security Metrics:** Authentication patterns and security events
- **Performance Trends:** System performance over time

### **Reporting Capabilities**
- **Automated Reports:** Scheduled report generation and distribution
- **Custom Dashboards:** Configurable admin analytics dashboards
- **Data Visualization:** Interactive charts for admin insights
- **Export Options:** PDF, CSV, Excel export for all reports

## 🛠️ Development and Deployment

### **Container Development**
```bash
# Admin dashboard container development
docker build -t admin-dashboard -f Dockerfile.admin .
docker run -p 3001:3001 admin-dashboard

# Kubernetes deployment
kubectl apply -f k8s/admin-dashboard-deployment.yaml
kubectl port-forward svc/admin-dashboard 3001:3001
```

### **Environment Configuration**
```bash
# Admin-specific environment variables
ADMIN_SECRET_KEY=admin-secret
ENABLE_ADMIN_FEATURES=true
ADMIN_SESSION_TIMEOUT=3600
LOG_LEVEL=debug
AUDIT_ENABLED=true
```

## 🚨 Current Status - Admin Dashboard

### **✅ Working Features**
- **Admin UI Framework:** Next.js admin interface operational
- **Visual Testing:** Playwright configured for admin workflows
- **Component Library:** Admin-specific UI components functional
- **Development Environment:** Local development setup working

### **❌ Backend Integration Issues**
- **Admin API Gateway:** Admin endpoints not properly configured
- **Authentication:** Admin login system not integrated with backend
- **Real-time Data:** WebSocket connections for live admin data not working
- **Database Access:** Admin queries blocked by authentication failures

### **🔧 Critical Admin Fixes Needed**
1. **Admin Authentication:** Implement admin-specific auth system
2. **Admin API Gateway:** Configure admin-specific API routes
3. **Database Access:** Enable admin database queries and operations
4. **Real-time Updates:** Implement WebSocket for live admin data

## 🎯 Admin Testing Strategy

### **Test Coverage Areas**
- **Tenant Operations:** Complete tenant lifecycle testing
- **User Management:** Bulk user operations and security testing
- **System Configuration:** Feature flags and settings management
- **Operational Monitoring:** Log viewing and alert management
- **Security Compliance:** RBAC and audit trail validation

### **Testing Priorities**
1. **P0:** Core admin functionality (tenant, user management)
2. **P1:** System monitoring and configuration
3. **P2:** Advanced features (bulk operations, reporting)
4. **P3:** Mobile admin interface and accessibility

## 📞 Admin Support and Troubleshooting

### **Debug Admin Issues**
```bash
# Admin debugging commands
npm run debug:admin            # Interactive admin debugging
npm run logs:admin             # Admin-specific log viewing
npm run test:admin:trace       # Generate admin test traces
npm run health:admin           # Admin system health check
```

### **Common Admin Issues**
- **Permission Errors:** Check admin role assignments and API permissions
- **Data Loading:** Verify admin database access and query performance
- **Bulk Operations:** Monitor memory usage during large operations
- **Export Failures:** Check file system permissions and disk space

---

**Status:** Admin dashboard framework ready, backend admin API integration required.  
**Priority:** Implement admin authentication and API gateway configuration.  
**Testing:** Comprehensive admin workflow testing available with Playwright.