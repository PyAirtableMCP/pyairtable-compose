# PyAirtable Full-Stack Development Setup

Transform your PyAirtable backend into a complete full-stack application in under 5 minutes.

## 🚀 Quick Start (Full-Stack)

```bash
# 1. Setup backend (if not done already)
./setup.sh

# 2. Create frontend application
npm install  # Install package.json dependencies
npm run setup:frontend

# 3. Setup frontend environment
cp frontend-env-template ../frontend/.env.local
# Edit ../frontend/.env.local with your API keys

# 4. Generate TypeScript API client
./scripts/generate-types.sh

# 5. Start full-stack development
npm run dev
```

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (React/Next.js)                 │
│                        Port: 3000                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │  Chat Interface │  │ Airtable CRUD   │  │  Analytics   ││
│  │                 │  │                 │  │              ││
│  │ • Real-time AI  │  │ • Table mgmt    │  │ • Costs      ││
│  │ • Session mgmt  │  │ • Record ops    │  │ • Usage      ││
│  │ • Budget alerts │  │ • Batch ops     │  │ • Health     ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                             │                               │
└─────────────────────────────┼───────────────────────────────┘
                              │ HTTP/REST API
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   API Gateway (Port 8000)                  │
│                                                             │
│  Routes all requests to appropriate microservices          │
│  • /api/chat → LLM Orchestrator                           │
│  • /api/airtable/* → Airtable Gateway                     │
│  • /api/tools → MCP Server                                │
│  • Authentication, CORS, Rate limiting                     │
└─────────────────────────────────────────────────────────────┘
                              │
    ┌─────────────────────────┼─────────────────────────┐
    │                         │                         │
    ▼                         ▼                         ▼
┌─────────────┐        ┌─────────────┐        ┌─────────────┐
│LLM Orchestr │        │ MCP Server  │        │Airtable GW  │
│ Port: 8003  │        │ Port: 8001  │        │ Port: 8002  │
│             │        │             │        │             │
│• Gemini API │        │• 13 Tools   │        │• Airtable   │
│• Sessions   │        │• Batch Ops  │        │• Caching    │
│• Budgets    │        │• Security   │        │• Rate Limit │
└─────────────┘        └─────────────┘        └─────────────┘
       │                        │                        │
       └────────────────────────┼────────────────────────┘
                                ▼
                    ┌─────────────────────────┐
                    │    Infrastructure       │
                    │                         │
                    │ • PostgreSQL (Sessions)│
                    │ • Redis (Cache)        │
                    │ • pyairtable-common    │
                    └─────────────────────────┘
```

## 🛠️ Development Workflow

### Daily Development
```bash
# Start everything (backend + frontend)
npm run dev

# Backend only
npm run dev:backend

# Frontend only  
npm run dev:frontend

# View logs
npm run logs

# Test everything
npm run test
```

### Key Development Scripts

| Command | Purpose |
|---------|---------|
| `npm run dev` | Start full-stack development environment |
| `npm run setup:frontend` | Create new Next.js frontend app |
| `./scripts/generate-types.sh` | Generate TypeScript API client |
| `npm run test` | Run comprehensive testing |
| `npm run logs` | View all service logs |
| `npm run clean` | Clean Docker containers and volumes |

## 🎯 Frontend Application Features

### Recommended App Structure
```
frontend/
├── src/
│   ├── app/                    # Next.js 13+ app directory
│   │   ├── chat/               # AI chat interface
│   │   ├── airtable/           # Airtable management
│   │   ├── analytics/          # Usage analytics
│   │   └── settings/           # Configuration
│   ├── components/             # Reusable components
│   │   ├── ui/                 # Basic UI components
│   │   ├── chat/               # Chat-specific components
│   │   ├── airtable/           # Airtable components
│   │   └── analytics/          # Analytics components
│   ├── hooks/                  # Custom React hooks
│   │   ├── useApi.ts           # API integration hooks
│   │   ├── useChat.ts          # Chat functionality
│   │   └── useAirtable.ts      # Airtable operations
│   ├── services/               # API clients
│   │   ├── api.ts              # Main API client
│   │   └── websocket.ts        # Real-time features
│   ├── types/                  # TypeScript definitions
│   │   ├── api.ts              # Auto-generated API types
│   │   └── app.ts              # App-specific types
│   └── utils/                  # Utility functions
├── public/                     # Static assets
└── package.json               # Dependencies
```

### Key Frontend Features to Build

1. **AI Chat Interface**
   - Real-time conversation with PyAirtable AI
   - Session management
   - Cost tracking display
   - Budget alerts

2. **Airtable Management**
   - Table browser
   - Record CRUD operations
   - Batch operations UI
   - Data export/import

3. **Analytics Dashboard**
   - API usage statistics
   - Cost breakdown
   - Performance metrics
   - Health monitoring

4. **Settings & Configuration**
   - API key management
   - Budget configuration
   - User preferences

## 🔧 API Integration Patterns

### Using the Generated API Client

```typescript
// Example: Chat with AI
import { apiClient } from '../services/api'
import { useChat } from '../hooks/useApi'

function ChatComponent() {
  const { sendMessage, loading, error } = useChat()
  
  const handleSend = async (message: string) => {
    const response = await sendMessage(message, 'user-session-123')
    console.log(response)
  }
  
  return (
    // Your chat UI here
  )
}

// Example: Airtable operations
function AirtableManager() {
  const [records, setRecords] = useState([])
  
  const loadRecords = async () => {
    const data = await apiClient.airtable.get('tables/tblXXXXXX/records')
    setRecords(data.records)
  }
  
  const createRecord = async (fields: any) => {
    await apiClient.airtable.post('tables/tblXXXXXX/records', { fields })
    loadRecords() // Refresh
  }
  
  return (
    // Your Airtable UI here
  )
}
```

### Real-time Features

```typescript
// Example: Health monitoring
import { useHealth } from '../hooks/useApi'

function HealthDashboard() {
  const { health, loading, error } = useHealth()
  
  return (
    <div>
      {health?.services?.map(service => (
        <div key={service.name}>
          {service.name}: {service.status}
        </div>
      ))}
    </div>
  )
}
```

## 🧪 Testing Strategy

### Full-Stack Testing
```bash
# Test everything
./test-fullstack.sh

# Test specific components
npm run test:health      # Backend health
npm run test:chat        # Chat functionality
cd ../frontend && npm test  # Frontend tests
```

### Testing Approach

1. **Backend API Testing**
   - Health checks for all services
   - API endpoint connectivity
   - End-to-end data flow

2. **Frontend Testing**
   - Component unit tests
   - API integration tests
   - E2E user workflows

3. **Integration Testing**
   - Full request/response cycles
   - Error handling
   - Performance benchmarks

## 🚀 Production Considerations

### Performance Optimization
- API client caching
- Frontend code splitting
- Image optimization
- Bundle size monitoring

### Security
- API key management
- CORS configuration
- Input validation
- Rate limiting

### Monitoring
- Real-time health checks
- Error tracking
- Performance metrics
- User analytics

## 🎯 Perfect For

- **2-Person Teams**: Maximum productivity with minimal overhead
- **Internal Tools**: Powerful AI-driven Airtable automation
- **Rapid Prototyping**: Get full-stack AI app running in minutes
- **Cost-Conscious Development**: Built-in budget management
- **Modern Stack**: React/Next.js + FastAPI microservices

---

## 🚀 Ready to Start?

```bash
# Get started in 30 seconds
npm run dev
```

Your AI-powered Airtable full-stack application will be running at:
- **Frontend**: http://localhost:3000
- **API Gateway**: http://localhost:8000
- **Backend Services**: Ports 8001-8003

**Happy coding!** 🎉