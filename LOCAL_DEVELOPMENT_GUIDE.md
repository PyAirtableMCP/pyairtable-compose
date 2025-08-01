# PyAirtable Microservices - Local Development

**AI-Powered Airtable Automation for Internal Teams**

This repository contains everything you need to run the PyAirtable microservices stack locally for development. Perfect for internal teams of 2-3 people who want powerful AI-driven Airtable automation.

## 🎯 What This Does

- **AI Chat Interface**: Natural language interactions with your Airtable data
- **13 Advanced MCP Tools**: Comprehensive CRUD operations, batch processing, data analysis
- **Cost Tracking**: Real token counting and budget management for Gemini API
- **Session Persistence**: PostgreSQL + Redis for reliable conversation storage
- **Security**: Formula injection protection, secure API key management

## 🚀 Quick Start (30 seconds!)

```bash
# 1. Clone and setup everything automatically
git clone <your-repo> && cd pyairtable-compose
chmod +x *.sh

# 2. Run automated setup
./setup.sh

# 3. Add your API keys to .env files (see below)

# 4. Start all services  
./start.sh

# 5. Test everything works
./test.sh
```

**That's it!** Your AI-powered Airtable system is running locally.

## 📋 Prerequisites

- **Python 3.9+** (with pip and venv)
- **PostgreSQL** (running locally)
- **Redis** (running locally)
- **curl** (for testing)

### macOS Setup:
```bash
# Install with Homebrew
brew install postgresql redis
brew services start postgresql
brew services start redis
```

### Ubuntu Setup:
```bash
# Install packages
sudo apt install postgresql redis-server python3-venv
sudo systemctl start postgresql redis-server
```

## 🔑 Required API Keys

You'll need these API keys (added to `.env` files after running `./setup.sh`):

### 1. Gemini API Key
- Go to [Google AI Studio](https://makersuite.google.com/)
- Create a new API key
- Add to `.env` files: `GEMINI_API_KEY=your_key_here`

### 2. Airtable Token  
- Go to [Airtable Developer Hub](https://airtable.com/developers/web/api/introduction)
- Create a Personal Access Token
- Add to `.env` files: `AIRTABLE_TOKEN=your_token_here`

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ LLM Orchestrator│◄──►│   MCP Server    │◄──►│Airtable Gateway │
│   Port: 8003    │    │   Port: 8001    │    │   Port: 8002    │
│                 │    │                 │    │                 │
│ • Chat API      │    │ • 13 MCP Tools  │    │ • Airtable API  │
│ • Cost Tracking │    │ • Batch Ops     │    │ • Rate Limiting │
│ • Budgets       │    │ • Data Analysis │    │ • Caching       │
│ • Sessions      │    │ • Export/Sync   │    │ • Security      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                    ┌─────────────────────────┐
                    │    Infrastructure       │
                    │                         │
                    │ • PostgreSQL (Sessions)│
                    │ • Redis (Cache)        │
                    │ • pyairtable-common    │
                    └─────────────────────────┘
```

## 🛠️ Available Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `setup.sh` | **One-time setup** - Creates everything you need | `./setup.sh` |
| `start.sh` | **Start services** - Runs all microservices | `./start.sh` |
| `stop.sh` | **Stop services** - Graceful shutdown | `./stop.sh` |
| `test.sh` | **Test everything** - Comprehensive testing | `./test.sh` |

### Advanced Usage:
```bash
# View service status
./start.sh status

# View logs  
./start.sh logs
./start.sh logs llm-orchestrator

# Run specific tests
./test.sh health
./test.sh integration

# Force stop everything
./stop.sh force
```

## 🧪 Testing Your Setup

Once everything is running, test with these commands:

```bash
# 1. Health checks
curl http://localhost:8003/health
curl http://localhost:8001/health  
curl http://localhost:8002/health

# 2. List available MCP tools
curl http://localhost:8001/tools

# 3. Test AI chat (requires API keys)
curl -X POST http://localhost:8003/chat \
  -H 'Content-Type: application/json' \
  -d '{"message": "List my Airtable tables", "session_id": "test"}'

# 4. Test budget management  
curl -X POST http://localhost:8003/budgets/session/test \
  -H 'Content-Type: application/json' \
  -d '{"budget_limit": 5.00}'
```

## 🔧 What Each Service Does

### 🤖 LLM Orchestrator (Port 8003)
**The brain of the system**
- Natural language chat interface
- Gemini 2.5 Flash integration with native function calling
- Real-time cost tracking and budget enforcement
- Session management with PostgreSQL persistence
- Circuit breaker protection

**Key Endpoints:**
- `POST /chat` - Main chat interface
- `GET /budgets/session/{id}` - Budget management
- `GET /cost-tracking/analytics` - Usage analytics

### 🛠️ MCP Server (Port 8001)
**The tool execution engine**
- 13 advanced Airtable tools (see below)
- HTTP mode for <10ms latency (vs 200ms subprocess)
- Formula injection protection
- Batch operations support

**Available Tools:**
1. `list_tables` - List all tables in base
2. `get_records` - Retrieve records with filtering
3. `create_record` - Create single record
4. `update_record` - Update record
5. `delete_record` - Delete record  
6. `search_records` - Advanced search
7. `create_metadata_table` - Base analysis
8. `batch_create_records` - **NEW!** Bulk record creation
9. `batch_update_records` - **NEW!** Bulk updates
10. `get_field_info` - **NEW!** Field analysis
11. `analyze_table_data` - **NEW!** Data quality insights
12. `find_duplicates` - **NEW!** Duplicate detection
13. `export_table_csv` - **NEW!** Export to CSV
14. `sync_tables` - **NEW!** Table synchronization

### 🗃️ Airtable Gateway (Port 8002)
**The data layer**
- Clean REST API wrapper around Airtable
- Redis caching with smart invalidation
- Rate limiting (respects Airtable's 5 QPS limit)
- Batch operations support

## 💰 Cost Management Features

Perfect for internal teams worried about AI costs:

- **Real Token Counting**: Uses Gemini SDK for accurate costs (not estimates)
- **Pre-Request Validation**: Blocks expensive calls before they happen
- **Budget Limits**: Set per-session and per-user budgets
- **Real-Time Monitoring**: Track spending as you go
- **Detailed Analytics**: Cost breakdowns and usage reports

## 🗂️ File Structure

```
pyairtable-compose/
├── setup.sh           # 🔧 Automated setup
├── start.sh            # 🚀 Start all services  
├── stop.sh             # 🛑 Stop all services
├── test.sh             # 🧪 Test everything
├── README.md           # 📖 This file
├── .env                # 🔑 Master config (created by setup)
├── docker-compose.yml  # 🐳 Docker option
└── migrations/         # 📊 Database migrations
    └── 001_create_session_tables.sql
```

## 🐳 Docker Alternative

If you prefer Docker:

```bash
# Start with Docker Compose
docker-compose up -d

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

## 🔍 Troubleshooting

### Services won't start?
```bash
# Check if ports are already in use
lsof -i :8001 -i :8002 -i :8003

# Kill conflicting processes
./stop.sh force
```

### Database connection issues?
```bash
# Check PostgreSQL
pg_isready -h localhost -p 5432

# Check Redis  
redis-cli ping

# Restart services (macOS)
brew services restart postgresql redis
```

### API key issues?
```bash
# Check your .env files
cat /Users/kg/IdeaProjects/*/.*env | grep -E "(GEMINI|AIRTABLE)"

# Test API keys manually
curl -H "Authorization: Bearer $GEMINI_API_KEY" \
  https://generativelanguage.googleapis.com/v1/models
```

### Logs not showing what you expect?
```bash
# View all logs in real-time
tail -f /tmp/pyairtable-logs/*.log

# View specific service
tail -f /tmp/pyairtable-logs/llm-orchestrator.log
```

## 🎯 Perfect For

- **Internal Teams**: 2-3 people who need powerful Airtable automation
- **Local Development**: Everything runs on your machine
- **Cost-Conscious**: Built-in budget management and cost tracking
- **Security-Focused**: No external dependencies, secure by default
- **Rapid Prototyping**: Get AI + Airtable working in minutes

## 🤝 Usage Examples

Once running, you can ask the AI natural questions:

- "Show me all records in my Projects table"
- "Create 5 new task records from this list"
- "Find duplicate contacts in my database"
- "Export my sales data to CSV"
- "Update all pending tasks to in-progress"
- "Analyze the data quality of my customer table"
- "Sync data from staging to production table"

## 📈 Monitoring

- **Service Status**: `./start.sh status`
- **Health Checks**: Built into each service at `/health`
- **Cost Analytics**: Real-time cost tracking and reporting
- **Circuit Breakers**: Automatic failure protection
- **Logs**: Centralized logging in `/tmp/pyairtable-logs/`

---

**Ready to supercharge your Airtable workflows with AI?** 🚀

Run `./setup.sh` and get started in 30 seconds!