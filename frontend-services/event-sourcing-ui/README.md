# PyAirtable Event Sourcing UI

A comprehensive React-based dashboard for monitoring and managing event-driven architecture components in the PyAirtable system.

## Features

### 🎯 Event Explorer
- Real-time event stream visualization
- Advanced filtering by type, aggregate, time range, and correlation ID
- Event details viewer with JSON formatting
- Event replay interface
- Event correlation tracking

### 🔄 SAGA Monitoring Dashboard
- Active SAGA instances visualization
- Interactive state machine diagram
- Step execution timeline with retry tracking
- Compensation tracking and management
- Failed SAGA investigation tools

### 📊 CQRS Projection Manager
- Projection status overview with health indicators
- Rebuild projection interface with progress tracking
- Projection lag monitoring and alerts
- Cache management UI
- Performance metrics visualization

### 🏥 System Health Dashboard
- Service topology visualization
- Real-time performance metrics
- Message queue depth monitoring
- Error rate tracking with alerts
- Latency heatmaps and trends

### 🛠️ Developer Tools
- Event schema browser with TypeScript generation
- Interactive event testing interface
- Event simulation with configurable load patterns
- Performance profiling with bottleneck analysis
- Debug mode with detailed event tracing

## Technology Stack

- **Frontend**: Next.js 14 with React 18
- **Styling**: Tailwind CSS with custom design system
- **Charts**: Recharts for data visualization
- **Icons**: Heroicons
- **Type Safety**: TypeScript with strict mode
- **State Management**: React hooks with local state
- **Real-time**: WebSocket connections (Socket.io)
- **HTTP Client**: Built-in fetch with custom hooks

## Getting Started

### Prerequisites
- Node.js 18+
- npm or yarn
- Access to PyAirtable backend services

### Installation

1. Install dependencies:
```bash
npm install
```

2. Configure environment variables:
```bash
cp .env.example .env.local
```

3. Start the development server:
```bash
npm run dev
```

4. Open [http://localhost:3002](http://localhost:3002) in your browser.

### Environment Variables

```env
# API Configuration
NEXT_PUBLIC_API_BASE_URL=http://localhost:8080
NEXT_PUBLIC_WS_URL=ws://localhost:8080/ws

# Features
NEXT_PUBLIC_ENABLE_REAL_TIME=true
NEXT_PUBLIC_ENABLE_DEV_TOOLS=true

# Performance
NEXT_PUBLIC_MAX_EVENTS_PER_PAGE=100
NEXT_PUBLIC_METRICS_RETENTION_DAYS=30
```

## Architecture

### Component Structure
```
src/
├── app/                    # Next.js app router pages
│   ├── page.tsx           # Dashboard home
│   ├── events/            # Event Explorer
│   ├── sagas/             # SAGA Monitor
│   ├── projections/       # Projection Manager
│   ├── health/            # System Health
│   ├── dev-tools/         # Developer Tools
│   └── settings/          # Configuration
├── components/            # Reusable components
│   ├── Layout/           # Navigation and layout
│   ├── Events/           # Event-related components
│   ├── Sagas/            # SAGA components
│   ├── Projections/      # Projection components
│   ├── Health/           # Health monitoring
│   └── DevTools/         # Development utilities
├── types/                # TypeScript type definitions
├── hooks/                # Custom React hooks
└── lib/                  # Utility functions
```

### Key Design Patterns

1. **Component Composition**: Modular components with clear responsibilities
2. **Custom Hooks**: Reusable state logic for data fetching and WebSocket connections
3. **Type Safety**: Comprehensive TypeScript types for all data structures
4. **Responsive Design**: Mobile-first approach with Tailwind CSS
5. **Accessibility**: WCAG 2.1 AA compliance with ARIA labels and keyboard navigation

## API Integration

The UI integrates with PyAirtable backend services through:

- **REST APIs**: Standard CRUD operations and queries
- **WebSocket**: Real-time updates for events, SAGAs, and metrics
- **Server-Sent Events**: Live system health monitoring

### API Endpoints

```typescript
// Event Store API
GET  /api/events           # List events with filtering
GET  /api/events/:id       # Get event details
POST /api/events/replay    # Replay events

// SAGA API
GET  /api/sagas            # List SAGA instances
GET  /api/sagas/:id        # Get SAGA details
POST /api/sagas/:id/retry  # Retry failed SAGA
POST /api/sagas/:id/compensate # Compensate SAGA

// Projections API
GET  /api/projections      # List projections
POST /api/projections/:name/rebuild # Rebuild projection
POST /api/projections/:name/reset   # Reset projection

// Health API
GET  /api/health/services  # Service health status
GET  /api/health/metrics   # System metrics
GET  /api/health/queues    # Queue statistics
```

## Performance Optimizations

1. **Code Splitting**: Automatic route-based code splitting
2. **Lazy Loading**: On-demand component loading
3. **Memoization**: React.memo and useMemo for expensive operations
4. **Virtual Scrolling**: Efficient rendering of large data sets
5. **Debounced Search**: Optimized search and filtering
6. **Connection Pooling**: Efficient WebSocket connection management

## Development

### Available Scripts

```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run start        # Start production server
npm run lint         # Run ESLint
npm run type-check   # Run TypeScript check
```

### Testing

```bash
npm run test         # Run unit tests
npm run test:e2e     # Run end-to-end tests
npm run test:coverage # Generate coverage report
```

### Code Quality

- **ESLint**: Configured with Next.js and TypeScript rules
- **Prettier**: Code formatting
- **Husky**: Pre-commit hooks
- **TypeScript**: Strict mode enabled

## Deployment

### Docker

```bash
docker build -t pyairtable-event-sourcing-ui .
docker run -p 3002:3002 pyairtable-event-sourcing-ui
```

### Docker Compose

```yaml
version: '3.8'
services:
  event-sourcing-ui:
    build: .
    ports:
      - "3002:3002"
    environment:
      - NEXT_PUBLIC_API_BASE_URL=http://api-gateway:8080
    depends_on:
      - api-gateway
```

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-sourcing-ui
spec:
  replicas: 2
  selector:
    matchLabels:
      app: event-sourcing-ui
  template:
    metadata:
      labels:
        app: event-sourcing-ui
    spec:
      containers:
      - name: ui
        image: pyairtable-event-sourcing-ui:latest
        ports:
        - containerPort: 3002
        env:
        - name: NEXT_PUBLIC_API_BASE_URL
          value: "http://api-gateway:8080"
```

## Monitoring and Observability

- **Health Checks**: Built-in health endpoint
- **Metrics**: Performance and usage metrics
- **Logging**: Structured logging with correlation IDs
- **Error Tracking**: Integration with error monitoring services

## Security

- **Authentication**: Integration with PyAirtable auth system
- **Authorization**: Role-based access control
- **HTTPS**: TLS encryption in production
- **CSP**: Content Security Policy headers
- **XSS Protection**: Input sanitization and validation

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Commit changes: `git commit -am 'Add new feature'`
4. Push to branch: `git push origin feature/new-feature`
5. Submit a pull request

## License

This project is part of the PyAirtable system and follows the same licensing terms.

## Support

For support and questions:
- Create an issue in the repository
- Check the documentation
- Contact the development team