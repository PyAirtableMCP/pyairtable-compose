# PyAirtable Platform - Getting Started (Real Working Flows)

**Last Updated:** August 6, 2025  
**Status:** Based on actually working services only  
**Audience:** Users who want to use the platform today

## ⚠️ Before You Start

**Current Reality:** This guide covers only the **working functionality** as of August 6, 2025. The platform has 5/8 services operational (62.5% availability). Some features are currently unavailable:

❌ **Not Available:** Web interface, file processing, complex workflows  
✅ **Available:** AI chat, Airtable integration, authentication, analytics

## 🎯 What You Can Actually Do Today

### 1. Chat with AI About Your Airtable Data ✅
Get AI-powered insights about your Airtable bases using natural language.

### 2. Authenticate and Manage Sessions ✅  
Register users, login, and maintain persistent chat sessions.

### 3. Direct Airtable Operations ✅
Create, read, update, and delete records in your Airtable bases.

### 4. Monitor Usage and Analytics ✅
Track API usage, performance metrics, and user activity.

## 🚀 Tutorial 1: AI Chat with Your Airtable Data

This is the **primary working feature** - AI-powered analysis of your Airtable data.

### Prerequisites
- Airtable Personal Access Token ([Get one here](https://airtable.com/developers/web/api/introduction))
- Airtable Base ID (from your base URL: `https://airtable.com/appXXXXXXXXXXXXXX`)
- Gemini API key ([Get one here](https://makersuite.google.com/app/apikey))

### Step 1: Set Up Environment
```bash
# Clone the repository
git clone https://github.com/Reg-Kris/pyairtable-compose.git
cd pyairtable-compose

# Create environment file
cat > .env << 'EOF'
AIRTABLE_TOKEN=pat_your_actual_token_here
AIRTABLE_BASE=appYourActualBaseId  
GEMINI_API_KEY=AIzaSyYourActualGeminiKey
API_KEY=your-secure-api-key
POSTGRES_DB=pyairtablemcp
POSTGRES_USER=admin
POSTGRES_PASSWORD=changeme123
REDIS_PASSWORD=redis123
EOF
```

### Step 2: Start Working Services
```bash
# Deploy only working services (automation/saga/frontend excluded)
docker-compose -f docker-compose.minimal.yml up -d

# Wait for services to be ready (30-60 seconds)
sleep 60

# Verify health
curl http://localhost:8000/api/health
```

### Step 3: Your First AI Chat
```bash
# Basic chat about your data
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secure-api-key" \
  -d '{
    "message": "What tables do I have in my Airtable base?",
    "session_id": "tutorial-session-001",
    "base_id": "appYourActualBaseId"
  }'
```

**Expected Response:**
```json
{
  "response": "I found several tables in your Airtable base:\n1. Table1 - Description\n2. Table2 - Description\n...",
  "session_id": "tutorial-session-001",
  "metadata": {
    "tools_used": ["list_tables"],
    "response_time": 1.2,
    "tokens_used": 150
  }
}
```

### Step 4: Advanced AI Analysis
```bash
# Ask for data insights
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secure-api-key" \
  -d '{
    "message": "Analyze my Facebook posts table and suggest improvements for engagement",
    "session_id": "tutorial-session-001",
    "base_id": "appYourActualBaseId"
  }'

# Request data summaries
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secure-api-key" \
  -d '{
    "message": "Create a summary report of all projects with their status and completion dates",
    "session_id": "tutorial-session-001", 
    "base_id": "appYourActualBaseId"
  }'
```

### Step 5: View Session History
```bash
# Get conversation history
curl -X GET "http://localhost:8000/api/sessions/tutorial-session-001/history" \
  -H "X-API-Key: your-secure-api-key"
```

## 🛡️ Tutorial 2: User Authentication (Working)

The platform services provide full authentication capabilities.

### Register a New User
```bash
curl -X POST http://localhost:8007/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "SecurePassword123!",
    "name": "John Doe"
  }'
```

**Expected Response:**
```json
{
  "message": "User registered successfully",
  "user_id": "uuid-here",
  "email": "user@example.com"
}
```

### Login User
```bash
curl -X POST http://localhost:8007/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "SecurePassword123!"
  }'
```

**Expected Response:**
```json
{
  "access_token": "jwt-token-here",
  "token_type": "bearer",
  "expires_in": 3600,
  "user": {
    "id": "uuid-here",
    "email": "user@example.com",
    "name": "John Doe"
  }
}
```

### Use JWT Token for Authenticated Requests
```bash
# Use the JWT token for authenticated chat
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer jwt-token-here" \
  -d '{
    "message": "Show me my recent activity",
    "session_id": "authenticated-session",
    "base_id": "appYourActualBaseId"
  }'
```

## 🔧 Tutorial 3: Direct Airtable Operations (Working)

Access Airtable data directly through MCP tools.

### List Available Tools
```bash
curl -X GET http://localhost:8000/api/tools \
  -H "X-API-Key: your-secure-api-key"
```

**Available Tools (14 total):**
- `list_tables` - Get all tables in a base
- `get_table_schema` - Get table structure and fields
- `list_records` - Get records from a table
- `create_record` - Create a new record
- `update_record` - Update existing record
- `delete_record` - Delete a record
- `search_records` - Search for records
- And more...

### Get Table Schema
```bash
curl -X POST http://localhost:8000/api/execute-tool \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secure-api-key" \
  -d '{
    "tool_name": "get_table_schema",
    "arguments": {
      "base_id": "appYourActualBaseId",
      "table_name": "Your Table Name"
    },
    "session_id": "direct-ops-session"
  }'
```

### Create a Record
```bash
curl -X POST http://localhost:8000/api/execute-tool \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secure-api-key" \
  -d '{
    "tool_name": "create_record",
    "arguments": {
      "base_id": "appYourActualBaseId",
      "table_name": "Tasks",
      "fields": {
        "Name": "New Task from API",
        "Status": "In Progress",
        "Priority": "High"
      }
    },
    "session_id": "direct-ops-session"
  }'
```

### Search Records
```bash
curl -X POST http://localhost:8000/api/execute-tool \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secure-api-key" \
  -d '{
    "tool_name": "search_records",
    "arguments": {
      "base_id": "appYourActualBaseId",
      "table_name": "Tasks", 
      "formula": "AND({Status} = \"Completed\", {Priority} = \"High\")"
    },
    "session_id": "direct-ops-session"
  }'
```

## 📊 Tutorial 4: Analytics and Monitoring (Working)

Track usage and monitor system performance.

### Get Usage Analytics
```bash
curl -X GET http://localhost:8007/analytics/usage \
  -H "Authorization: Bearer jwt-token-here"
```

### Track Custom Events
```bash
curl -X POST http://localhost:8007/analytics/events \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer jwt-token-here" \
  -d '{
    "event_type": "custom_analysis",
    "properties": {
      "analysis_type": "facebook_posts",
      "records_processed": 25,
      "user_satisfaction": "high"
    }
  }'
```

### Get System Metrics
```bash
curl -X GET http://localhost:8007/analytics/metrics \
  -H "Authorization: Bearer jwt-token-here"
```

## ⚠️ What's NOT Available Right Now

### ❌ File Processing Tutorial (Service Down)
The automation services (port 8006) are currently returning "Service unavailable". File upload and processing features are not working until this is fixed.

**Planned Features (Not Working):**
- Upload CSV/Excel files for processing
- Bulk data operations
- File attachment management
- Document analysis

### ❌ Complex Workflow Tutorial (Service Down) 
The SAGA orchestrator (port 8008) is in a restart loop. Complex multi-step workflows are not available.

**Planned Features (Not Working):**
- Multi-table data synchronization
- Complex approval workflows  
- Distributed transaction handling
- Batch job processing

### ❌ Web Interface Tutorial (Not Deployed)
There's no frontend service running on port 3000. All interactions must be through API calls.

**Planned Features (Not Working):**
- Web-based chat interface
- Visual data exploration
- User dashboards
- Interactive workflow builder

## 🔍 Troubleshooting Working Flows

### Common Issues

**1. "Connection refused" errors**
```bash
# Check if services are running
docker-compose ps

# Restart services if needed
docker-compose restart
```

**2. "Unauthorized" responses**
```bash
# Verify your API key is correct
curl -I http://localhost:8000/api/health -H "X-API-Key: your-api-key"

# Should return 200 OK, not 401 Unauthorized
```

**3. "Service unavailable for automation features"**
This is expected - automation services are currently down. Use direct Airtable operations instead.

**4. AI responses seem generic**
```bash
# Make sure you're using a real Airtable base with actual data
# Generic responses often indicate the AI is working with stub data
```

### Getting Help

**Check Service Health:**
```bash
# Quick health check script
curl -s http://localhost:8000/api/health | jq '.'
curl -s http://localhost:8007/health | jq '.'
```

**View Service Logs:**
```bash
# Check for errors in service logs
docker-compose logs llm-orchestrator | tail -20
docker-compose logs airtable-gateway | tail -20
```

## 🎯 Next Steps

### What You Should Try Next
1. **Test with your real Airtable data** - The AI works best with actual data
2. **Experiment with different question types** - Ask for analysis, summaries, recommendations
3. **Set up authentication for your users** - Test the registration and login flows
4. **Monitor API usage** - Track how your users interact with the system

### What to Wait For
1. **Web interface deployment** - Coming soon for better user experience
2. **File processing fixes** - Will enable bulk data operations
3. **Workflow automation** - Complex multi-step processes

### Production Readiness
**Current Status:** Good for API-based testing and development  
**Not Ready For:** Production web application deployment  
**ETA for Production:** 1-2 weeks after service fixes

---

**This tutorial reflects the actual working capabilities as of August 6, 2025. It will be updated as more services come online.**