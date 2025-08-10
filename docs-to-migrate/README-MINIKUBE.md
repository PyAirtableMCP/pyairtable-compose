# PyAirtable Minikube Deployment System

## 🚀 Comprehensive Local Development Environment

A complete, production-ready local development environment for PyAirtable running on Minikube with enterprise-grade tooling, monitoring, and automation.

### ✨ Features

- **🎯 One-Command Deployment** - Complete environment setup with a single command
- **🔄 Service Orchestration** - Intelligent dependency management and startup sequencing
- **🔐 Security First** - Automated secret generation, rotation, and secure storage
- **📊 Health Monitoring** - Real-time service health checks with alerting
- **📋 Log Management** - Centralized log aggregation, searching, and analysis
- **🗄️ Database Management** - Automated migrations, backups, and maintenance
- **🎛️ Interactive Dashboard** - Developer-friendly management interface
- **🧹 Automated Cleanup** - Resource optimization and maintenance

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Developer     │    │  Minikube       │    │   Services      │
│   Interface     │    │  Cluster        │    │                 │
│                 │    │                 │    │                 │
│ pyairtable-dev  │────▶│  Kubernetes     │────▶│  Frontend       │
│ Interactive     │    │  Orchestration  │    │  API Gateway    │
│ Dashboard       │    │                 │    │  Microservices  │
│                 │    │                 │    │  Database       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Management    │    │   Monitoring    │    │   Storage       │
│   Tools         │    │   & Logging     │    │   & Secrets     │
│                 │    │                 │    │                 │
│ • Dependencies  │    │ • Health Checks │    │ • PostgreSQL    │
│ • Secrets       │    │ • Log Aggreg.   │    │ • Redis         │
│ • Database      │    │ • Alerting      │    │ • Persistent    │
│ • Validation    │    │ • Metrics       │    │   Volumes       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚦 Quick Start

### Prerequisites

```bash
# Required tools
brew install minikube kubectl docker jq

# Start Docker Desktop
open -a Docker

# Verify installations
minikube version
kubectl version --client
docker --version
jq --version
```

### 1. One-Command Deployment

```bash
# Clone and navigate to the project
cd pyairtable-compose

# Deploy everything (production-ready)
./pyairtable-dev.sh deploy
```

This single command will:
- ✅ Generate secure secrets
- ✅ Start optimized Minikube cluster
- ✅ Build and deploy all services
- ✅ Initialize database with migrations
- ✅ Configure health monitoring
- ✅ Validate deployment
- ✅ Show access URLs

### 2. Quick Development Setup

```bash
# For rapid development cycles
./pyairtable-dev.sh quick
```

### 3. Interactive Management

```bash
# Launch developer dashboard  
./pyairtable-dev.sh dashboard
```

## 🛠️ Management Tools

### Main Orchestrator

```bash
./pyairtable-dev.sh <command>

Commands:
  deploy      - Full production deployment
  quick       - Quick development setup  
  dashboard   - Interactive management
  status      - System status overview
  cleanup     - Remove all resources
```

### Service Dependencies

```bash
./pyairtable-dev.sh deps <command>

Commands:
  start [services...]     - Start services in dependency order
  stop [services...]      - Stop services gracefully
  restart [services...]   - Restart with dependency awareness
  health                  - Check health of all services
  status [service]        - Detailed service status
  monitor                 - Continuous health monitoring
```

### Secret Management

```bash
./pyairtable-dev.sh secrets <command>

Commands:
  generate [--force]      - Generate secure secrets
  rotate [secrets...]     - Rotate specific secrets
  status                  - Show secret status
  backup [name]           - Create encrypted backup
  restore <name>          - Restore from backup
```

### Database Operations

```bash
./pyairtable-dev.sh database <command>

Commands:
  init                    - Initialize database
  migrate [version]       - Run migrations
  backup [name]           - Create database backup
  restore <name>          - Restore from backup
  status                  - Show migration status
  reset                   - Reset database (DANGEROUS)
```

### Health Monitoring

```bash
./pyairtable-dev.sh health <command>

Commands:
  check                   - Single health check
  monitor                 - Continuous monitoring dashboard
  metrics [hours]         - Show metrics summary
  alerts [hours]          - Show recent alerts
```

### Log Management

```bash
./pyairtable-dev.sh logs <command>

Commands:
  view [service] [lines]  - View service logs
  follow [service]        - Follow logs in real-time
  search <pattern>        - Search across all logs
  export [format]         - Export logs (text/json/csv)
  analyze [service]       - Analyze for issues
```

## 🎯 Service Architecture

### Core Services

| Service | Port | Type | Description |
|---------|------|------|-------------|
| **Frontend** | 30081 | Next.js | Web interface |
| **API Gateway** | 30080 | Go/Fiber | Request routing |
| **Auth Service** | 8081 | Go | Authentication |
| **Platform Services** | 8007 | Python | Core business logic |

### Microservices

| Service | Port | Language | Function |
|---------|------|----------|----------|
| **Airtable Gateway** | 8002 | Python | Airtable API integration |
| **LLM Orchestrator** | 8003 | Python | Gemini AI integration |
| **MCP Server** | 8001 | Python | Model Context Protocol |
| **Automation Services** | 8006 | Python | Workflow automation |

### Infrastructure

| Service | Port | Type | Purpose |
|---------|------|------|---------|
| **PostgreSQL** | 5432 | Database | Primary data store |
| **Redis** | 6379 | Cache | Session & cache store |

## 🔐 Security Features

### Secret Management
- **Cryptographically secure** random generation
- **Automatic rotation** with zero-downtime
- **Encrypted backups** with GPG
- **Environment isolation**
- **Kubernetes secret integration**

### Network Security
- **Internal service mesh** - Services only accessible within cluster
- **External access** only through controlled NodePorts
- **Secret injection** via Kubernetes secrets
- **TLS-ready** configuration

## 📊 Monitoring & Observability

### Health Monitoring
- **Real-time health checks** for all services
- **Response time tracking**
- **Automatic alerting** on failures
- **Service dependency** health propagation
- **Historical metrics** collection

### Log Management
- **Centralized aggregation** from all services
- **Real-time log streaming**
- **Advanced search** with pattern matching
- **Log level filtering**
- **Export capabilities** (JSON, CSV, text)
- **Automated analysis** for error patterns

### Metrics & Alerting
- **Service availability** tracking
- **Performance metrics**
- **Error rate monitoring**
- **Custom alert thresholds**
- **Dashboard visualization**

## 🗄️ Database Management

### Migration System
- **Version-controlled** schema changes
- **Rollback capabilities**
- **Migration locking** prevents conflicts
- **Automated validation**
- **Backup before migrations**

### Backup & Recovery
- **Automated backups** with compression
- **Point-in-time recovery**
- **Backup encryption**
- **Retention policies**
- **One-click restoration**

## 🎛️ Developer Experience

### Interactive Dashboard
The built-in dashboard provides:
- 📊 Real-time service status
- 📋 Log viewing and searching  
- 🔄 Service restart capabilities
- 🗃️ Database operations
- 🔐 Secret management
- 🧹 Cleanup operations

### Development Workflow

```bash
# Daily development workflow
./pyairtable-dev.sh dashboard

# Quick service restart
./pyairtable-dev.sh deps restart api-gateway

# Check logs for errors
./pyairtable-dev.sh logs search "error"

# Monitor system health
./pyairtable-dev.sh health monitor

# Database operations
./pyairtable-dev.sh database migrate
```

## ⚡ Performance Optimization

### Resource Configuration
- **Optimized for local development** (8GB RAM, 4 CPU)
- **Efficient container sizing**
- **Shared volume optimization**
- **Startup time minimization**

### Service Startup
- **Dependency-aware ordering** prevents startup failures
- **Health check validation** ensures readiness
- **Parallel deployment** where possible
- **Graceful degradation** on failures

## 🧹 Maintenance & Cleanup

### Automated Cleanup
```bash
# Clean old logs (configurable retention)
./pyairtable-dev.sh logs cleanup

# Archive old database backups  
./pyairtable-dev.sh database cleanup

# Clean monitoring data
./pyairtable-dev.sh health cleanup

# Complete environment cleanup
./pyairtable-dev.sh cleanup
```

### Data Management
- **Configurable retention** policies
- **Automated archival** with compression
- **Storage optimization**
- **Selective cleanup** options

## 🛠️ Troubleshooting

### Common Issues

#### Minikube Won't Start
```bash
# Check Docker
docker info

# Restart Minikube
minikube delete
minikube start --cpus=4 --memory=8192

# Verify
./pyairtable-dev.sh status
```

#### Services Not Starting
```bash
# Check service dependencies
./pyairtable-dev.sh deps status

# View detailed logs
./pyairtable-dev.sh logs view all

# Restart in dependency order
./pyairtable-dev.sh deps restart
```

#### Database Connection Issues
```bash
# Check database status
./pyairtable-dev.sh database status

# Verify migrations
./pyairtable-dev.sh database migrate

# Check pod status
kubectl get pods -n pyairtable
```

### Debug Commands

```bash
# Get all resource status
kubectl get all -n pyairtable

# Describe problematic pod
kubectl describe pod <pod-name> -n pyairtable

# Check events
kubectl get events -n pyairtable --sort-by='.lastTimestamp'

# Port forward for direct access
kubectl port-forward -n pyairtable service/api-gateway 8080:8000
```

## 📁 File Structure

```
pyairtable-compose/
├── pyairtable-dev.sh              # Main orchestrator
├── deploy-minikube.sh             # Core deployment script
├── scripts/                       # Management tools
│   ├── dependency-manager.sh      # Service dependencies
│   ├── secret-manager.sh          # Secret management
│   ├── database-manager.sh        # Database operations
│   ├── health-monitor.sh          # Health monitoring
│   └── log-manager.sh             # Log management
├── .secrets/                      # Generated secrets (gitignored)
├── .logs/                         # Log aggregation
├── .monitoring/                   # Health metrics
└── migrations/                    # Database migrations
```

## 🔧 Configuration

### Environment Variables

```bash
# Cluster configuration
export MINIKUBE_CPUS=4
export MINIKUBE_MEMORY=8192
export MINIKUBE_DISK_SIZE=30g

# Service configuration  
export NAMESPACE=pyairtable
export LOG_LEVEL=info
export CHECK_INTERVAL=30

# External APIs (required)
export AIRTABLE_TOKEN=your_token
export GEMINI_API_KEY=your_key
```

### Customization

The system supports extensive customization through:
- Environment variables
- Configuration files
- Service-specific settings
- Resource limits
- Monitoring thresholds

## 📊 Monitoring Dashboards

### Service Health Dashboard
- Real-time service status
- Response time graphs
- Error rate tracking
- Dependency health
- Alert summary

### Resource Monitoring
- CPU and memory usage
- Pod scaling metrics
- Storage utilization
- Network performance

## 🎯 Production Readiness

This system includes production-grade features:
- ✅ **High Availability** patterns
- ✅ **Security best practices**
- ✅ **Monitoring & alerting**
- ✅ **Backup & recovery**
- ✅ **Configuration management**
- ✅ **Automated deployment**
- ✅ **Health validation**
- ✅ **Log aggregation**

## 🚀 Getting Started Checklist

- [ ] Install prerequisites (minikube, kubectl, docker, jq)
- [ ] Set required environment variables (AIRTABLE_TOKEN, GEMINI_API_KEY)
- [ ] Run `./pyairtable-dev.sh deploy`
- [ ] Access the dashboard `./pyairtable-dev.sh dashboard`
- [ ] Verify services `./pyairtable-dev.sh status`
- [ ] Test API Gateway at http://localhost:30080
- [ ] Test Frontend at http://localhost:30081

## 📞 Support

For issues, questions, or contributions:
1. Check the troubleshooting section
2. Review logs with `./pyairtable-dev.sh logs analyze`
3. Use the interactive dashboard for real-time debugging
4. Consult individual component help with `<component> help`

---

**🎉 Happy Developing with PyAirtable!**

This system provides enterprise-grade local development capabilities while maintaining simplicity and developer productivity. The comprehensive tooling ensures you can focus on building features rather than managing infrastructure.