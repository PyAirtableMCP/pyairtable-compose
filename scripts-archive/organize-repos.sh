#!/bin/bash

# PyAirtable Microservices GitHub Organization Script
# This script creates GitHub repositories for all PyAirtable microservices
# and pushes them to the Reg-Kris organization

set -e  # Exit on any error

# Configuration
ORG="Reg-Kris"
BASE_DIR="/Users/kg/IdeaProjects/pyairtable-compose/pyairtable-infrastructure"
COMPOSE_DIR="/Users/kg/IdeaProjects/pyairtable-compose"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is required but not installed"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI is not authenticated. Run 'gh auth login'"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "Git is required but not installed"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Create .gitignore for Go services
create_go_gitignore() {
    local service_dir="$1"
    cat > "$service_dir/.gitignore" << 'EOF'
# Binaries for programs and plugins
*.exe
*.exe~
*.dll
*.so
*.dylib

# Test binary, built with `go test -c`
*.test

# Output of the go coverage tool, specifically when used with LiteIDE
*.out

# Go workspace file
go.work

# Dependency directories (remove the comment below to include it)
vendor/

# Go modules (uncomment if using go modules)
# go.sum

# IDE specific files
.vscode/
.idea/
*.swp
*.swo

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Environment variables
.env
.env.local
.env.production

# Build artifacts
bin/
dist/
build/

# Logs
*.log
logs/

# Docker
.dockerignore

# Kubernetes
*.kubeconfig

# Temporary files
tmp/
temp/
*.tmp
EOF
}

# Create .gitignore for Python services
create_python_gitignore() {
    local service_dir="$1"
    cat > "$service_dir/.gitignore" << 'EOF'
# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class

# C extensions
*.so

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
pip-wheel-metadata/
share/python-wheels/
*.egg-info/
.installed.cfg
*.egg
MANIFEST

# PyInstaller
*.manifest
*.spec

# Installer logs
pip-log.txt
pip-delete-this-directory.txt

# Unit test / coverage reports
htmlcov/
.tox/
.nox/
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
*.py,cover
.hypothesis/
.pytest_cache/

# Translations
*.mo
*.pot

# Django stuff:
*.log
local_settings.py
db.sqlite3
db.sqlite3-journal

# Flask stuff:
instance/
.webassets-cache

# Scrapy stuff:
.scrapy

# Sphinx documentation
docs/_build/

# PyBuilder
target/

# Jupyter Notebook
.ipynb_checkpoints

# IPython
profile_default/
ipython_config.py

# pyenv
.python-version

# pipenv
Pipfile.lock

# PEP 582
__pypackages__/

# Celery stuff
celerybeat-schedule
celerybeat.pid

# SageMath parsed files
*.sage.py

# Environments
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# Spyder project settings
.spyderproject
.spyproject

# Rope project settings
.ropeproject

# mkdocs documentation
/site

# mypy
.mypy_cache/
.dmypy.json
dmypy.json

# Pyre type checker
.pyre/

# IDE specific files
.vscode/
.idea/
*.swp
*.swo

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
EOF
}

# Create a repository and push code
create_and_push_repo() {
    local repo_name="$1"
    local local_path="$2"
    local description="$3"
    local topics="$4"
    local service_type="$5"  # go or python
    
    log_info "Processing repository: $repo_name"
    
    # Check if local directory exists
    if [ ! -d "$local_path" ]; then
        log_warning "Directory $local_path does not exist, skipping $repo_name"
        return 1
    fi
    
    # Change to the service directory
    cd "$local_path"
    
    # Create .gitignore if it doesn't exist
    if [ ! -f ".gitignore" ]; then
        log_info "Creating .gitignore for $repo_name"
        if [ "$service_type" = "go" ]; then
            create_go_gitignore "$local_path"
        elif [ "$service_type" = "python" ]; then
            create_python_gitignore "$local_path"
        fi
    fi
    
    # Initialize git if not already initialized
    if [ ! -d ".git" ]; then
        log_info "Initializing git repository for $repo_name"
        git init
        git branch -M main
    fi
    
    # Create repository on GitHub if it doesn't exist
    if ! gh repo view "$ORG/$repo_name" &> /dev/null; then
        log_info "Creating GitHub repository: $ORG/$repo_name"
        gh repo create "$ORG/$repo_name" \
            --public \
            --description "$description" \
            --clone=false
        
        # Add topics if provided
        if [ -n "$topics" ]; then
            log_info "Adding topics to $repo_name: $topics"
            # Convert comma-separated topics to space-separated
            topic_args=""
            IFS=',' read -ra TOPIC_ARRAY <<< "$topics"
            for topic in "${TOPIC_ARRAY[@]}"; do
                topic_args="$topic_args --add-topic $(echo $topic | xargs)"
            done
            gh repo edit "$ORG/$repo_name" $topic_args
        fi
    else
        log_warning "Repository $ORG/$repo_name already exists"
    fi
    
    # Set remote origin if not set
    if ! git remote get-url origin &> /dev/null; then
        log_info "Setting remote origin for $repo_name"
        git remote add origin "https://github.com/$ORG/$repo_name.git"
    fi
    
    # Stage all files
    git add .
    
    # Check if there are changes to commit
    if git diff --staged --quiet; then
        log_warning "No changes to commit in $repo_name"
    else
        # Commit changes
        log_info "Creating initial commit for $repo_name"
        git commit -m "Initial commit: $description

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
    fi
    
    # Push to GitHub
    log_info "Pushing $repo_name to GitHub"
    git push -u origin main
    
    log_success "Successfully processed $repo_name"
    echo ""
}

# Main execution
main() {
    log_info "Starting PyAirtable microservices organization script"
    echo "=================================="
    
    check_prerequisites
    
    # Define repository mappings
    # Format: repo_name:local_path:description:topics:type
    declare -a repos=(
        "pyairtable-api-gateway-go:$BASE_DIR/pyairtable-api-gateway-go:API Gateway service for PyAirtable microservices architecture:golang,microservices,api-gateway,pyairtable,kubernetes:go"
        "pyairtable-auth-service-go:$BASE_DIR/pyairtable-auth-service-go:Authentication and authorization service for PyAirtable:golang,microservices,auth,jwt,oauth,pyairtable:go"
        "pyairtable-user-service-go:$BASE_DIR/go-microservice-template/service_name=userservice:User management service for PyAirtable:golang,microservices,user-management,pyairtable:go"
        "pyairtable-tenant-service-go:$BASE_DIR/go-microservice-template/tenantservice:Multi-tenant management service for PyAirtable:golang,microservices,multi-tenancy,pyairtable:go"
        "pyairtable-workspace-service-go:$BASE_DIR/go-microservice-template/workspaceservice:Workspace management service for PyAirtable:golang,microservices,workspace,pyairtable:go"
        "pyairtable-permission-service-go:$BASE_DIR/go-microservice-template/permissionservice:Permission and access control service for PyAirtable:golang,microservices,rbac,permissions,pyairtable:go"
        "pyairtable-webhook-service-go:$BASE_DIR/go-microservice-template/webhookservice:Webhook management service for PyAirtable:golang,microservices,webhooks,pyairtable:go"
        "pyairtable-notification-service-go:$BASE_DIR/go-microservice-template/notificationservice:Notification service for PyAirtable:golang,microservices,notifications,pyairtable:go"
        "pyairtable-file-service-go:$BASE_DIR/go-microservice-template/fileservice:File storage and management service for PyAirtable:golang,microservices,file-storage,pyairtable:go"
        "pyairtable-go-shared:$BASE_DIR/pyairtable-go-shared:Shared Go libraries and utilities for PyAirtable microservices:golang,microservices,shared-library,pyairtable:go"
        "pyairtable-python-shared:$BASE_DIR/pyairtable-python-shared:Shared Python libraries and utilities for PyAirtable services:python,microservices,shared-library,pyairtable:python"
    )
    
    # Process each repository
    for repo_config in "${repos[@]}"; do
        IFS=':' read -r repo_name local_path description topics service_type <<< "$repo_config"
        create_and_push_repo "$repo_name" "$local_path" "$description" "$topics" "$service_type"
    done
    
    # Create meta repository
    log_info "Creating meta repository: pyairtable-microservices"
    create_meta_repository
    
    log_success "All repositories have been processed successfully!"
    echo ""
    echo "🎉 PyAirtable microservices organization complete!"
    echo ""
    echo "Created repositories:"
    for repo_config in "${repos[@]}"; do
        IFS=':' read -r repo_name _ _ _ _ <<< "$repo_config"
        echo "  - https://github.com/$ORG/$repo_name"
    done
    echo "  - https://github.com/$ORG/pyairtable-microservices (meta repository)"
}

# Create meta repository with documentation
create_meta_repository() {
    local meta_repo="pyairtable-microservices"
    local meta_dir="/tmp/$meta_repo"
    
    # Create temporary directory for meta repository
    rm -rf "$meta_dir"
    mkdir -p "$meta_dir"
    cd "$meta_dir"
    
    # Initialize git
    git init
    git branch -M main
    
    # Create README.md
    cat > README.md << 'EOF'
# PyAirtable Microservices

A comprehensive microservices architecture for PyAirtable, built with Go and Python, designed for scalability, maintainability, and cloud-native deployment.

## 🏗️ Architecture Overview

PyAirtable is built using a microservices architecture pattern with the following core principles:

- **Domain-Driven Design**: Each service owns its domain and data
- **API-First**: RESTful APIs with OpenAPI documentation
- **Cloud-Native**: Kubernetes-ready with Docker containers
- **Observability**: Comprehensive logging, metrics, and tracing
- **Security**: JWT-based authentication with RBAC authorization

## 📋 Services Overview

### Core Services

| Service | Repository | Language | Purpose |
|---------|------------|----------|---------|
| **API Gateway** | [pyairtable-api-gateway-go](https://github.com/Reg-Kris/pyairtable-api-gateway-go) | Go | Entry point, routing, rate limiting |
| **Auth Service** | [pyairtable-auth-service-go](https://github.com/Reg-Kris/pyairtable-auth-service-go) | Go | Authentication, authorization, JWT |
| **User Service** | [pyairtable-user-service-go](https://github.com/Reg-Kris/pyairtable-user-service-go) | Go | User management, profiles |
| **Tenant Service** | [pyairtable-tenant-service-go](https://github.com/Reg-Kris/pyairtable-tenant-service-go) | Go | Multi-tenancy, organization management |
| **Workspace Service** | [pyairtable-workspace-service-go](https://github.com/Reg-Kris/pyairtable-workspace-service-go) | Go | Workspace creation, management |
| **Permission Service** | [pyairtable-permission-service-go](https://github.com/Reg-Kris/pyairtable-permission-service-go) | Go | RBAC, access control |

### Supporting Services

| Service | Repository | Language | Purpose |
|---------|------------|----------|---------|
| **Webhook Service** | [pyairtable-webhook-service-go](https://github.com/Reg-Kris/pyairtable-webhook-service-go) | Go | Webhook management, delivery |
| **Notification Service** | [pyairtable-notification-service-go](https://github.com/Reg-Kris/pyairtable-notification-service-go) | Go | Email, SMS, push notifications |
| **File Service** | [pyairtable-file-service-go](https://github.com/Reg-Kris/pyairtable-file-service-go) | Go | File upload, storage, processing |

### Shared Libraries

| Library | Repository | Language | Purpose |
|---------|------------|----------|---------|
| **Go Shared** | [pyairtable-go-shared](https://github.com/Reg-Kris/pyairtable-go-shared) | Go | Common Go utilities, middleware |
| **Python Shared** | [pyairtable-python-shared](https://github.com/Reg-Kris/pyairtable-python-shared) | Python | Common Python utilities, helpers |

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- Kubernetes cluster (local or cloud)
- Go 1.21+ (for development)
- Python 3.11+ (for Python services)

### Local Development Setup

1. **Clone this repository**:
   ```bash
   git clone https://github.com/Reg-Kris/pyairtable-microservices.git
   cd pyairtable-microservices
   ```

2. **Clone all service repositories**:
   ```bash
   ./scripts/clone-all-repos.sh
   ```

3. **Start local development environment**:
   ```bash
   docker-compose up -d
   ```

4. **Run database migrations**:
   ```bash
   ./scripts/run-migrations.sh
   ```

### Production Deployment

For production deployment using Kubernetes:

```bash
# Deploy to Kubernetes
kubectl apply -f k8s/

# Or use Helm
helm install pyairtable ./helm/pyairtable-stack
```

## 🛠️ Development Guidelines

### Service Standards

Each microservice follows these standards:

- **Structure**: Standard Go project layout
- **Configuration**: Environment-based config with validation
- **Database**: PostgreSQL with migrations
- **Caching**: Redis for performance
- **Monitoring**: Prometheus metrics, structured logging
- **Testing**: Unit tests, integration tests, benchmark tests
- **Documentation**: OpenAPI/Swagger specifications

### API Design

- RESTful endpoints following OpenAPI 3.0
- Consistent error responses
- Request/response validation
- Rate limiting and throttling
- API versioning support

### Security

- JWT-based authentication
- Role-based access control (RBAC)
- Input validation and sanitization
- SQL injection prevention
- Rate limiting and DDoS protection

## 📊 Service Communication

```mermaid
graph TB
    Client[Client Applications] --> Gateway[API Gateway]
    Gateway --> Auth[Auth Service]
    Gateway --> User[User Service]
    Gateway --> Tenant[Tenant Service]
    Gateway --> Workspace[Workspace Service]
    Gateway --> Permission[Permission Service]
    Gateway --> Webhook[Webhook Service]
    Gateway --> Notification[Notification Service]
    Gateway --> File[File Service]
    
    Auth --> DB[(PostgreSQL)]
    User --> DB
    Tenant --> DB
    Workspace --> DB
    Permission --> DB
    
    Auth --> Cache[(Redis)]
    Permission --> Cache
    
    Webhook --> Queue[Message Queue]
    Notification --> Queue
```

## 🏗️ Technology Stack

### Backend Services
- **Language**: Go 1.21+
- **Framework**: Gin (HTTP), GORM (ORM)
- **Database**: PostgreSQL 15+
- **Cache**: Redis 7+
- **Message Queue**: Redis Streams / RabbitMQ

### Infrastructure
- **Containerization**: Docker
- **Orchestration**: Kubernetes
- **Service Mesh**: Istio (optional)
- **Load Balancer**: NGINX / Traefik
- **Monitoring**: Prometheus + Grafana
- **Logging**: ELK Stack / Loki

### Development Tools
- **CI/CD**: GitHub Actions
- **Testing**: Go testing, Testify
- **Documentation**: Swagger/OpenAPI
- **Code Quality**: golangci-lint, SonarQube

## 📈 Monitoring & Observability

### Metrics
- Application metrics via Prometheus
- Business metrics and KPIs
- Infrastructure monitoring
- Custom dashboards in Grafana

### Logging
- Structured logging with consistent format
- Centralized log aggregation
- Log correlation with trace IDs
- Error tracking and alerting

### Tracing
- Distributed tracing with OpenTelemetry
- Request flow visualization
- Performance bottleneck identification

## 🔧 Contributing

### Development Workflow

1. **Fork** the relevant service repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add some amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Code Standards

- Follow Go conventions and best practices
- Write comprehensive tests (aim for >80% coverage)
- Update documentation for API changes
- Use conventional commit messages
- Ensure all CI checks pass

### Testing

```bash
# Run unit tests
make test

# Run integration tests
make test-integration

# Run benchmarks
make benchmark

# Generate coverage report
make coverage
```

## 📚 Documentation

- [API Documentation](./docs/api/)
- [Deployment Guide](./docs/deployment/)
- [Development Setup](./docs/development/)
- [Architecture Decisions](./docs/architecture/)
- [Security Guidelines](./docs/security/)

## 🤝 Support

- **Issues**: Use GitHub Issues in relevant repositories
- **Discussions**: GitHub Discussions in this repository
- **Security**: Email security@pyairtable.com for security concerns

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

Built with modern microservices patterns and cloud-native technologies. Special thanks to the Go and Kubernetes communities for excellent tooling and documentation.

---

**🤖 Generated with [Claude Code](https://claude.ai/code)**
EOF

    # Create directory structure
    mkdir -p docs/{api,deployment,development,architecture,security}
    mkdir -p scripts
    mkdir -p k8s
    mkdir -p helm

    # Create scripts/clone-all-repos.sh
    cat > scripts/clone-all-repos.sh << 'EOF'
#!/bin/bash

# Script to clone all PyAirtable microservice repositories

set -e

ORG="Reg-Kris"
SERVICES=(
    "pyairtable-api-gateway-go"
    "pyairtable-auth-service-go"
    "pyairtable-user-service-go"
    "pyairtable-tenant-service-go"
    "pyairtable-workspace-service-go"
    "pyairtable-permission-service-go"
    "pyairtable-webhook-service-go"
    "pyairtable-notification-service-go"
    "pyairtable-file-service-go"
    "pyairtable-go-shared"
    "pyairtable-python-shared"
)

echo "Cloning all PyAirtable microservice repositories..."

for service in "${SERVICES[@]}"; do
    if [ -d "$service" ]; then
        echo "Directory $service already exists, skipping..."
        continue
    fi
    
    echo "Cloning $service..."
    git clone "https://github.com/$ORG/$service.git"
done

echo "All repositories cloned successfully!"
EOF

    chmod +x scripts/clone-all-repos.sh

    # Create basic docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: pyairtable
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Service directories (cloned separately)
pyairtable-*/

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Environment
.env
.env.local
EOF

    # Create LICENSE
    cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2025 PyAirtable

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

    # Add all files to git
    git add .

    # Create initial commit
    git commit -m "Initial commit: PyAirtable microservices meta repository

This repository serves as the central hub for the PyAirtable microservices architecture,
providing documentation, deployment scripts, and development guidelines.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

    # Create GitHub repository
    if ! gh repo view "$ORG/$meta_repo" &> /dev/null; then
        log_info "Creating GitHub repository: $ORG/$meta_repo"
        gh repo create "$ORG/$meta_repo" \
            --public \
            --description "Meta repository for PyAirtable microservices architecture - documentation, deployment, and development hub" \
            --clone=false
        
        # Add topics
        gh repo edit "$ORG/$meta_repo" \
            --add-topic microservices \
            --add-topic pyairtable \
            --add-topic golang \
            --add-topic python \
            --add-topic kubernetes \
            --add-topic docker \
            --add-topic architecture
    fi

    # Set remote and push
    git remote add origin "https://github.com/$ORG/$meta_repo.git"
    git push -u origin main

    log_success "Meta repository created successfully"
    
    # Clean up
    rm -rf "$meta_dir"
}

# Run main function
main "$@"
EOF