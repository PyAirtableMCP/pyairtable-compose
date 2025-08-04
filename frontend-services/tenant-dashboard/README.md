# PyAirtable Tenant Dashboard

A comprehensive tenant management UI for PyAirtable that allows end-users to manage their own tenants/organizations. This modern React application provides a complete interface for tenant administration, team management, workspace organization, billing, settings, and security compliance.

## Features

### 🏠 Tenant Dashboard
- **Overview Dashboard**: Key metrics, usage statistics, billing summary, and activity feed
- **Usage Analytics**: Real-time charts showing API usage, storage growth, and team activity
- **Quick Actions**: Streamlined access to common tasks like inviting members and creating workspaces
- **Plan Status**: Current subscription information and upgrade prompts

### 👥 Team Management
- **Member Management**: View, invite, and manage team members
- **Role-Based Access Control**: Assign roles (Owner, Admin, Member, Viewer) with granular permissions
- **Bulk Operations**: Invite multiple members and manage permissions in bulk
- **Activity Monitoring**: Track team member activity and login history

### 📁 Workspace Organization
- **Workspace Management**: Create, organize, and manage workspaces
- **Template System**: Pre-built workspace templates for quick setup
- **Access Control**: Fine-grained permission settings per workspace
- **Sharing Controls**: Manage workspace visibility and sharing settings
- **Archive & Restore**: Archive unused workspaces and restore when needed

### 💳 Billing & Subscription
- **Plan Management**: View current plan details and usage limits
- **Usage Tracking**: Real-time usage monitoring with visual progress indicators
- **Upgrade/Downgrade**: Seamless plan changes with immediate effect
- **Payment Methods**: Manage payment methods and billing addresses
- **Invoice History**: Download and view past invoices

### ⚙️ Settings & Configuration
- **Tenant Profile**: Organization details, logos, and branding
- **Custom Domain**: Configure and verify custom domains
- **Single Sign-On (SSO)**: SAML and OAuth provider setup
- **API Key Management**: Generate and manage API keys with granular permissions
- **Webhook Configuration**: Set up webhooks for event notifications
- **Third-party Integrations**: Connect with external services

### 🔒 Security & Compliance
- **Two-Factor Authentication**: Setup and manage 2FA for enhanced security
- **Session Management**: View and revoke active sessions
- **Audit Logs**: Comprehensive activity logging and monitoring
- **Data Export**: GDPR-compliant data export tools
- **Compliance Tools**: Built-in GDPR, CCPA, and HIPAA compliance features

## Technology Stack

- **Framework**: Next.js 14 with App Router
- **Language**: TypeScript for type safety
- **Styling**: Tailwind CSS with custom design system
- **UI Components**: Radix UI primitives with custom styling
- **Data Fetching**: TanStack Query (React Query) for server state management
- **Charts**: Recharts for data visualization
- **Forms**: React Hook Form with Zod validation
- **Icons**: Lucide React icon library
- **Notifications**: React Hot Toast for user feedback

## Getting Started

### Prerequisites

- Node.js 18+ 
- npm or yarn package manager
- Access to PyAirtable backend services

### Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Set up environment variables**:
   ```bash
   cp .env.example .env.local
   ```
   
   Configure the following variables:
   ```env
   NEXT_PUBLIC_API_URL=http://localhost:8080
   NEXT_PUBLIC_WS_URL=ws://localhost:8080
   NEXT_PUBLIC_ENVIRONMENT=development
   ```

3. **Run the development server**:
   ```bash
   npm run dev
   ```
   
   The application will be available at `http://localhost:3002`

### Build for Production

```bash
npm run build
npm start
```

## Project Structure

```
src/
├── app/                    # Next.js App Router pages
│   ├── globals.css        # Global styles and CSS variables
│   ├── layout.tsx         # Root layout component
│   ├── page.tsx           # Dashboard homepage
│   └── providers.tsx      # React Query and other providers
├── components/
│   ├── ui/                # Reusable UI components
│   ├── layout/            # Layout components (Header, Sidebar)
│   ├── dashboard/         # Dashboard-specific components
│   ├── team/              # Team management components
│   ├── workspace/         # Workspace management components
│   ├── billing/           # Billing and subscription components
│   ├── settings/          # Settings and configuration components
│   └── security/          # Security and compliance components
├── hooks/                 # Custom React hooks
│   └── useTenant.ts       # Tenant-related data fetching hooks
├── lib/
│   ├── api.ts             # API client and utilities
│   └── utils.ts           # Utility functions
└── types/
    └── index.ts           # TypeScript type definitions
```

## Key Components

### Layout Components
- **MainLayout**: Primary application layout with sidebar and header
- **Header**: Top navigation with user menu, notifications, and search
- **Sidebar**: Collapsible navigation menu with hierarchical sections

### Dashboard Components
- **DashboardOverview**: Main dashboard with metrics and activity
- **MetricCard**: Reusable metric display with trend indicators
- **UsageChart**: Configurable charts for usage visualization
- **UsageProgress**: Progress bars for usage limits
- **ActivityFeed**: Real-time activity and audit log display

### UI Components
All UI components follow the Radix UI design system with Tailwind CSS styling:
- Button, Card, Badge, Input, Progress
- Dialog, Dropdown Menu, Alert, Tooltip
- Form components with validation
- Data tables with sorting and filtering

## API Integration

The application uses a centralized API client (`src/lib/api.ts`) that provides:

- **Type-safe requests** with full TypeScript support
- **Automatic error handling** with user-friendly messages
- **Request/response interceptors** for authentication and logging
- **Retry logic** for failed requests
- **File upload capabilities** with progress tracking

### Data Fetching Hooks

React Query hooks in `src/hooks/useTenant.ts` provide:

- **Optimistic updates** for better user experience
- **Background refetching** to keep data fresh
- **Caching strategies** to minimize API calls
- **Loading and error states** for all operations
- **Mutation callbacks** for side effects

## Responsive Design

The application is built with a mobile-first approach:

- **Breakpoint system**: Tailored for mobile, tablet, and desktop
- **Collapsible navigation**: Sidebar adapts to screen size
- **Flexible layouts**: Grid and flexbox layouts that reflow
- **Touch-friendly**: Appropriate tap targets and spacing
- **Progressive enhancement**: Core functionality works on all devices

## Accessibility Features

Built with WCAG 2.1 AA compliance in mind:

- **Keyboard navigation**: Full keyboard accessibility
- **Screen reader support**: Proper ARIA labels and roles
- **Focus management**: Clear focus indicators and logical flow
- **Color contrast**: High contrast ratios for all text
- **Semantic HTML**: Proper heading hierarchy and landmarks

## Security Considerations

- **XSS Protection**: All user input is properly sanitized
- **CSRF Protection**: API requests include CSRF tokens
- **Content Security Policy**: Strict CSP headers
- **Secure Authentication**: JWT tokens with proper expiration
- **Data Encryption**: Sensitive data encrypted in transit and at rest

## Deployment

### Docker Deployment

Build the Docker image:
```bash
docker build -t pyairtable-tenant-dashboard .
```

Run the container:
```bash
docker run -p 3002:3002 \
  -e NEXT_PUBLIC_API_URL=https://api.pyairtable.com \
  pyairtable-tenant-dashboard
```

### Environment Configuration

Set the following environment variables for production:

```env
NEXT_PUBLIC_API_URL=https://api.pyairtable.com
NEXT_PUBLIC_WS_URL=wss://api.pyairtable.com
NEXT_PUBLIC_ENVIRONMENT=production
NODE_ENV=production
```

## Contributing

1. Follow the existing code style and patterns
2. Write TypeScript for all new code
3. Add unit tests for new components and utilities
4. Ensure accessibility compliance
5. Test responsive design on multiple devices
6. Update documentation for new features

## Testing

Run the test suite:
```bash
npm test                 # Run all tests
npm run test:watch      # Run tests in watch mode
npm run test:coverage   # Generate coverage report
```

## Performance Optimization

The application includes several performance optimizations:

- **Code splitting**: Automatic route-based code splitting
- **Image optimization**: Next.js Image component with lazy loading
- **Bundle analysis**: Webpack bundle analyzer for size optimization
- **Caching strategies**: Aggressive caching for static assets
- **Tree shaking**: Unused code elimination

## Browser Support

- **Modern browsers**: Chrome 90+, Firefox 88+, Safari 14+, Edge 90+
- **Progressive enhancement**: Core functionality on older browsers
- **Polyfills**: Automatic polyfills for missing features

## License

This project is part of the PyAirtable ecosystem and follows the same licensing terms.