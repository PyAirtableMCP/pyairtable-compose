# PyAirtable Admin Dashboard

A comprehensive admin dashboard for PyAirtable platform management, built with Next.js 14, React 18, and modern UI components.

## Features

### 🔍 System Overview Dashboard
- Real-time system health monitoring
- Service status visualization  
- Resource utilization graphs (CPU, Memory, Disk, Network)
- Key performance indicators
- Alert and incident tracking

### 🏢 Tenant Management
- Complete tenant list with advanced search and filters
- Tenant details and configuration management
- Usage statistics and analytics per tenant
- Plan management and billing overview
- Tenant provisioning and deprovisioning workflows

### 👥 User Administration
- Comprehensive user management interface
- Role and permission assignment system
- User activity monitoring and audit logs
- Account status management (active/suspended/inactive)
- Bulk user operations and data export

### ⚙️ System Configuration
- Feature flags management with rollout controls
- System settings configuration interface
- API rate limiting configuration
- Security policy management
- Integration settings and webhooks

### 📊 Analytics & Reporting
- Interactive usage analytics dashboards
- Financial reporting and revenue tracking
- Performance metrics and trends
- Custom report builder
- Data export capabilities (CSV, JSON, PDF)

### 🛠️ Operational Tools
- Advanced log viewer with real-time search
- Database query interface with syntax highlighting
- Cache management and monitoring
- Job queue monitoring and management
- Deployment status and health checks

## Technology Stack

- **Framework**: Next.js 14 with App Router
- **UI Library**: React 18 with TypeScript
- **Styling**: Tailwind CSS with custom design system
- **Components**: Radix UI primitives with custom components
- **Data Fetching**: TanStack Query (React Query)
- **Charts**: Recharts for data visualization
- **Forms**: React Hook Form with Zod validation
- **Real-time**: Socket.IO client for live updates
- **Icons**: Lucide React
- **Notifications**: React Hot Toast

## Getting Started

### Prerequisites

- Node.js 18+ 
- npm or yarn
- Docker (optional)

### Installation

1. **Clone the repository**
   ```bash
   cd frontend-services/admin-dashboard
   ```

2. **Install dependencies**
   ```bash
   npm install
   # or
   yarn install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env.local
   ```
   
   Configure the following variables:
   ```env
   NEXT_PUBLIC_API_BASE_URL=http://localhost:8080/api/v1
   NEXT_PUBLIC_WS_URL=ws://localhost:8080
   NEXT_PUBLIC_APP_NAME=PyAirtable Admin Dashboard
   NODE_ENV=development
   ```

4. **Start the development server**
   ```bash
   npm run dev
   # or
   yarn dev
   ```

5. **Open your browser**
   Navigate to [http://localhost:3001](http://localhost:3001)

### Docker Setup

1. **Build the Docker image**
   ```bash
   docker build -t pyairtable-admin-dashboard .
   ```

2. **Run the container**
   ```bash
   docker run -p 3001:3001 -e NEXT_PUBLIC_API_BASE_URL=http://localhost:8080/api/v1 pyairtable-admin-dashboard
   ```

## Project Structure

```
src/
├── app/                    # Next.js App Router pages
│   ├── analytics/         # Analytics and reporting pages
│   ├── config/           # System configuration pages
│   ├── operations/       # Operational tools pages
│   ├── tenants/          # Tenant management pages
│   ├── users/            # User administration pages
│   └── system/           # System monitoring pages
├── components/            # React components
│   ├── analytics/        # Analytics dashboard components
│   ├── charts/           # Chart components
│   ├── config/           # Configuration components
│   ├── dashboard/        # Main dashboard components
│   ├── layout/           # Layout components
│   ├── operational/      # Operational tool components
│   ├── tenant/           # Tenant management components
│   ├── ui/              # Base UI components
│   └── user/            # User management components
├── hooks/                # Custom React hooks
├── lib/                  # Utility functions and configurations
├── types/                # TypeScript type definitions
└── utils/                # Helper functions
```

## Key Components

### System Overview (`/dashboard`)
- Real-time system health status
- Resource usage metrics with live updates
- Service topology and status monitoring
- Alert management and acknowledgment

### Tenant Management (`/tenants`)
- Searchable tenant list with filters
- Tenant usage analytics and billing
- Plan management and limits
- Tenant lifecycle operations

### User Administration (`/users`)
- User search and management
- Role-based access control
- Activity monitoring and audit trails
- Bulk operations and user import/export

### System Configuration (`/config`)
- Feature flag management with rollout controls
- System settings with validation
- Rate limiting configuration
- Security policy management

### Analytics Dashboard (`/analytics`)
- Interactive charts and metrics
- Usage trends and patterns
- Financial reporting
- Custom report generation

### Operational Tools (`/operations`)
- Real-time log streaming and search
- Database query interface
- Cache monitoring and management
- Job queue monitoring

## API Integration

The dashboard integrates with the PyAirtable backend services through:

- **REST API**: Standard CRUD operations
- **WebSocket**: Real-time updates and notifications
- **Server-Sent Events**: Live data streaming

### API Endpoints

All API calls are handled through the centralized API client (`/lib/api.ts`):

```typescript
// System monitoring
GET /admin/system/health
GET /admin/system/metrics
GET /admin/system/services

// Tenant management
GET /admin/tenants
POST /admin/tenants
PUT /admin/tenants/:id
DELETE /admin/tenants/:id

// User administration
GET /admin/users
PUT /admin/users/:id
POST /admin/users/:id/suspend

// Configuration
GET /admin/config/feature-flags
PUT /admin/config/feature-flags/:id
GET /admin/config/settings

// Analytics
GET /admin/analytics/:metric
GET /admin/reports/usage
POST /admin/reports/export

// Operations
POST /admin/logs/search
POST /admin/database/query
GET /admin/jobs/queues
```

## Real-time Features

The dashboard supports real-time updates through WebSocket connections:

- **System Health**: Live status updates
- **User Activity**: Real-time user actions
- **Log Streaming**: Live log entries
- **Metrics**: Real-time performance data
- **Alerts**: Instant alert notifications

## Development

### Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run start` - Start production server
- `npm run lint` - Run ESLint
- `npm run lint:fix` - Fix linting issues
- `npm run type-check` - Run TypeScript checks
- `npm run test` - Run tests
- `npm run test:watch` - Run tests in watch mode

### Code Style

- **TypeScript**: Strict mode enabled
- **ESLint**: Next.js recommended configuration
- **Prettier**: Code formatting
- **Tailwind CSS**: Utility-first styling

### Testing

```bash
# Run all tests
npm run test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage
```

## Security Features

- **Authentication**: JWT-based auth with refresh tokens
- **Authorization**: Role-based access control
- **CSRF Protection**: Built-in CSRF tokens
- **Content Security Policy**: Strict CSP headers
- **Rate Limiting**: Request throttling
- **Input Validation**: Comprehensive form validation

## Performance Optimizations

- **Code Splitting**: Automatic route-based splitting
- **Image Optimization**: Next.js Image component
- **Caching**: React Query for efficient data caching
- **Bundle Analysis**: Built-in bundle analyzer
- **Lazy Loading**: Component and route lazy loading

## Deployment

### Production Build

```bash
npm run build
npm run start
```

### Docker Deployment

```bash
docker build -t pyairtable-admin-dashboard .
docker run -p 3001:3001 pyairtable-admin-dashboard
```

### Environment Variables

Required environment variables for production:

```env
NEXT_PUBLIC_API_BASE_URL=https://api.pyairtable.com/api/v1
NEXT_PUBLIC_WS_URL=wss://api.pyairtable.com
NODE_ENV=production
```

## Monitoring and Observability

The dashboard includes built-in monitoring:

- **Error Tracking**: Automatic error reporting
- **Performance Monitoring**: Core Web Vitals tracking
- **User Analytics**: Usage pattern analysis
- **API Monitoring**: Request/response tracking

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new features
5. Run the test suite
6. Submit a pull request

## License

This project is proprietary software. All rights reserved.

## Support

For technical support or questions:
- Create an issue in the repository
- Contact the development team
- Check the documentation wiki

---

Built with ❤️ by the PyAirtable team