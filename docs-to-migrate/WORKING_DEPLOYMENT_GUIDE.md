# PyAirtable Platform - Working Deployment Guide

**Last Updated:** August 6, 2025  
**Status:** Reflects actual working services only  
**Target:** Users who want to deploy what actually works

## ⚠️ Important Notice

This guide covers only the **currently working services** (5/8 operational). Three services are currently non-functional and should not be deployed until fixed:
- automation-services (Port 8006) - Returns "Service unavailable"
- saga-orchestrator (Port 8008) - Continuous restart loop  
- frontend (Port 3000) - Not deployed in current composition

## 🚀 Quick Working Deployment

### Prerequisites
- Docker and Docker Compose installed
- At least 4GB RAM available
- Ports 8000-8003, 8007, 5432, 6379 free

### Step 1: Clone Repository
```bash
git clone https://github.com/Reg-Kris/pyairtable-compose.git
cd pyairtable-compose
```

### Step 2: Configure Environment  
```bash
# Copy environment template
cp .env.example .env

# Edit with your actual credentials
nano .env
```

**Required Variables:**
```env
# Airtable Integration (REQUIRED)
AIRTABLE_TOKEN=pat_your_actual_token_here
AIRTABLE_BASE=appYourActualBaseId

# Gemini AI (REQUIRED) 
GEMINI_API_KEY=AIzaSyYourActualGeminiKey

# Service Authentication
API_KEY=your-secure-api-key-here

# Database Configuration
POSTGRES_DB=pyairtablemcp
POSTGRES_USER=admin
POSTGRES_PASSWORD=your-secure-db-password

# Redis Configuration  
REDIS_PASSWORD=your-secure-redis-password
```

### Step 3: Deploy Working Services Only
```bash
# Deploy only the working services (excludes broken automation/saga/frontend)
docker-compose -f docker-compose.minimal.yml up -d

# Check deployment status
docker-compose ps
```

### Step 4: Verify Health
```bash
# Test API Gateway (should return service status)
curl http://localhost:8000/api/health

# Test individual services
curl http://localhost:8001/health    # MCP Server
curl http://localhost:8002/health    # Airtable Gateway  
curl http://localhost:8003/health    # LLM Orchestrator
curl http://localhost:8007/health    # Platform Services
```

**Expected healthy response:**
```json
{
  "status": "healthy",
  "gateway": "healthy", 
  "services": [
    {"name": "airtable-gateway", "status": "healthy"},
    {"name": "mcp-server", "status": "healthy"},
    {"name": "llm-orchestrator", "status": "healthy"}
  ]
}
```

## 📡 Testing Working Functionality

### Test AI Chat (Primary Feature)
```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "message": "List all tables in my Airtable base",
    "session_id": "test-session-001",
    "base_id": "appYourBaseId"
  }'
```

### Test Authentication (Platform Services)
```bash
# Register new user
curl -X POST http://localhost:8007/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "SecurePassword123!",
    "name": "Test User"
  }'

# Login user
curl -X POST http://localhost:8007/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com", 
    "password": "SecurePassword123!"
  }'
```

### Test Airtable Integration
```bash
# List MCP tools available
curl -X GET http://localhost:8000/api/tools \
  -H "X-API-Key: $API_KEY"

# Execute Airtable tool
curl -X POST http://localhost:8000/api/execute-tool \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "tool_name": "list_tables",
    "arguments": {"base_id": "appYourBaseId"},
    "session_id": "test-session-001"
  }'
```

## 🏗️ Service Architecture (Working Only)

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User/Client   │    │   API Gateway   │    │ LLM Orchestrator│
│                 │────▶│   (Port 8000)   │────▶│   (Port 8003)   │
│                 │    │   ✅ HEALTHY    │    │   ✅ HEALTHY    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                        │
                                │                        ▼
                                │               ┌─────────────────┐
                                │               │   MCP Server    │
                                │               │   (Port 8001)   │
                                │               │   ✅ HEALTHY    │
                                │               └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │Airtable Gateway │    │Platform Services│
                       │   (Port 8002)   │    │   (Port 8007)   │
                       │   ✅ HEALTHY    │    │   ✅ HEALTHY    │
                       └─────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   PostgreSQL    │    │     Redis       │
                       │   (Port 5432)   │    │   (Port 6379)   │
                       │   ✅ HEALTHY    │    │   ✅ HEALTHY    │
                       └─────────────────┘    └─────────────────┘
```

## 💡 What You Can Do With Working Services

### ✅ Available Features
1. **AI-Powered Airtable Chat**
   - Ask questions about your Airtable data
   - Get AI-generated insights and recommendations
   - Natural language queries converted to Airtable operations

2. **Direct Airtable Integration**
   - CRUD operations on all your bases and tables
   - Real-time data synchronization
   - Rate limiting and caching for performance

3. **User Authentication & Analytics**
   - User registration and login
   - JWT token management
   - Usage analytics and metrics collection

4. **Session Management**
   - Persistent chat sessions
   - Context awareness across conversations
   - Multi-user session handling

### ❌ Currently Unavailable Features
- **File Processing** (automation-services down)
- **Workflow Automation** (automation-services down)
- **Distributed Transactions** (saga-orchestrator down)
- **Web Interface** (frontend not deployed)

## 🔧 Monitoring Working Services

### Service Logs
```bash
# View all service logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f api-gateway
docker-compose logs -f llm-orchestrator
docker-compose logs -f airtable-gateway
docker-compose logs -f platform-services
```

### Resource Monitoring
```bash
# Check container resource usage
docker stats

# Check service status
docker-compose ps
```

### Health Monitoring
```bash
# Automated health check script
cat > health-check.sh << 'EOF'
#!/bin/bash
echo "=== PyAirtable Health Check ==="
echo "API Gateway: $(curl -s http://localhost:8000/api/health | jq -r .status)"
echo "Airtable Gateway: $(curl -s http://localhost:8002/health | jq -r .status)"
echo "LLM Orchestrator: $(curl -s http://localhost:8003/health | jq -r .status)"
echo "MCP Server: $(curl -s http://localhost:8001/health | jq -r .status)"
echo "Platform Services: $(curl -s http://localhost:8007/health | jq -r .status)"
EOF

chmod +x health-check.sh
./health-check.sh
```

## 🚨 Known Issues & Workarounds

### Issue 1: Automation Services Unavailable
**Problem:** File processing endpoints return 503 Service Unavailable  
**Workaround:** Use direct Airtable API calls for file attachments  
**ETA for Fix:** Being investigated

### Issue 2: No Web Interface
**Problem:** Frontend service not deployed in current composition  
**Workaround:** Use API endpoints directly or tools like Postman  
**ETA for Fix:** Frontend deployment in progress

### Issue 3: SAGA Orchestrator Failing
**Problem:** Distributed transaction service unstable  
**Workaround:** Avoid complex multi-service operations  
**ETA for Fix:** Service stabilization in progress

## 🛠️ Production Readiness Checklist

### ❌ NOT READY FOR PRODUCTION (Current Status)
- [ ] All services healthy (currently 62.5% operational)
- [ ] Web interface deployed
- [ ] End-to-end testing completed
- [ ] Load testing performed
- [ ] Security hardening completed

### ✅ Ready for Development/Testing
- [x] Core AI functionality working
- [x] Airtable integration operational
- [x] Authentication system functional
- [x] Database and caching working
- [x] Basic monitoring in place

## 🎯 Next Steps

### For Developers
1. **Fix automation services** - investigate service unavailable error
2. **Stabilize SAGA orchestrator** - resolve restart loop
3. **Deploy frontend service** - add to Docker Compose
4. **Complete integration testing** with real user scenarios

### For Users
1. **Start with API-based testing** using the working endpoints
2. **Test core AI chat functionality** with your Airtable data
3. **Provide feedback** on functionality and performance
4. **Wait for web interface** before broader user rollout

## 📞 Support & Troubleshooting

### Getting Help
- **Service logs:** `docker-compose logs [service-name]`
- **Health checks:** Use the provided health-check.sh script
- **Reset services:** `docker-compose restart [service-name]`

### Emergency Procedures
```bash
# Stop all services
docker-compose down

# Clean restart (loses session data)
docker-compose down -v
docker-compose up -d

# Backup database before major changes
docker exec pyairtable-compose-postgres-1 pg_dump -U admin pyairtablemcp > backup.sql
```

---

**This guide reflects the actual working state as of August 6, 2025. It will be updated as service issues are resolved.**