#!/bin/bash

# PyAirtable Microservices Management Script
# Provides additional management capabilities for the repositories

set -e

# Configuration
ORG="Reg-Kris"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Repository list
REPOS=(
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
    "pyairtable-microservices"
)

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

# Function to list all repositories
list_repos() {
    log_info "PyAirtable microservices repositories:"
    echo ""
    for repo in "${REPOS[@]}"; do
        echo "📦 https://github.com/$ORG/$repo"
    done
    echo ""
}

# Function to check repository status
check_status() {
    log_info "Checking repository status..."
    echo ""
    
    for repo in "${REPOS[@]}"; do
        echo -n "🔍 $repo: "
        if gh repo view "$ORG/$repo" &> /dev/null; then
            echo -e "${GREEN}✅ exists${NC}"
        else
            echo -e "${RED}❌ not found${NC}"
        fi
    done
    echo ""
}

# Function to clone all repositories
clone_all() {
    local target_dir="${1:-./pyairtable-services}"
    
    log_info "Cloning all repositories to $target_dir..."
    mkdir -p "$target_dir"
    cd "$target_dir"
    
    for repo in "${REPOS[@]}"; do
        if [ -d "$repo" ]; then
            log_warning "$repo already exists, skipping..."
            continue
        fi
        
        log_info "Cloning $repo..."
        git clone "https://github.com/$ORG/$repo.git"
    done
    
    log_success "All repositories cloned to $target_dir"
}

# Function to update repository settings
update_settings() {
    log_info "Updating repository settings..."
    
    for repo in "${REPOS[@]}"; do
        log_info "Updating settings for $repo..."
        
        # Enable issues, wiki, and projects
        gh repo edit "$ORG/$repo" \
            --enable-issues \
            --enable-wiki \
            --enable-projects \
            --enable-merge-commit \
            --enable-squash-merge \
            --enable-rebase-merge \
            --delete-branch-on-merge \
            --enable-auto-merge
        
        # Add branch protection rules
        if gh api repos/$ORG/$repo/branches/main &> /dev/null; then
            log_info "Adding branch protection for $repo..."
            gh api repos/$ORG/$repo/branches/main/protection \
                --method PUT \
                --field required_status_checks='{}' \
                --field enforce_admins=true \
                --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
                --field restrictions=null \
                --silent || log_warning "Failed to add branch protection for $repo"
        fi
    done
    
    log_success "Repository settings updated"
}

# Function to add GitHub Actions workflows
add_workflows() {
    local service_dir="$1"
    
    if [ ! -d "$service_dir" ]; then
        log_error "Service directory $service_dir not found"
        return 1
    fi
    
    cd "$service_dir"
    
    # Create .github/workflows directory
    mkdir -p .github/workflows
    
    # Determine if it's a Go or Python service
    if [ -f "go.mod" ]; then
        create_go_workflow
    elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
        create_python_workflow
    else
        log_warning "Unknown service type for $service_dir"
        return 1
    fi
    
    log_success "Workflow added to $service_dir"
}

create_go_workflow() {
    cat > .github/workflows/ci.yml << 'EOF'
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
          
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
    - uses: actions/checkout@v4

    - name: Set up Go
      uses: actions/setup-go@v4
      with:
        go-version: '1.21'

    - name: Cache Go modules
      uses: actions/cache@v3
      with:
        path: ~/go/pkg/mod
        key: ${{ runner.os }}-go-${{ hashFiles('**/go.sum') }}
        restore-keys: |
          ${{ runner.os }}-go-

    - name: Install dependencies
      run: go mod download

    - name: Run tests
      run: go test -v -race -coverprofile=coverage.out ./...
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/test?sslmode=disable
        REDIS_URL: redis://localhost:6379

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage.out

    - name: Run linter
      uses: golangci/golangci-lint-action@v3
      with:
        version: latest

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
    - uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Login to GitHub Container Registry
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.repository_owner }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Build and push Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: |
          ghcr.io/${{ github.repository }}:latest
          ghcr.io/${{ github.repository }}:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  security:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        ignore-unfixed: true
        format: 'sarif'
        output: 'trivy-results.sarif'

    - name: Upload Trivy scan results to GitHub Security tab
      uses: github/codeql-action/upload-sarif@v2
      if: always()
      with:
        sarif_file: 'trivy-results.sarif'
EOF
}

create_python_workflow() {
    cat > .github/workflows/ci.yml << 'EOF'
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.11', '3.12']

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
    - uses: actions/checkout@v4

    - name: Set up Python ${{ matrix.python-version }}
      uses: actions/setup-python@v4
      with:
        python-version: ${{ matrix.python-version }}

    - name: Cache pip packages
      uses: actions/cache@v3
      with:
        path: ~/.cache/pip
        key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements*.txt', '**/pyproject.toml') }}
        restore-keys: |
          ${{ runner.os }}-pip-

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -e .[dev]

    - name: Run linters
      run: |
        black --check .
        isort --check-only .
        flake8 .
        mypy .

    - name: Run tests
      run: |
        pytest --cov=src --cov-report=xml
      env:
        DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test
        REDIS_URL: redis://localhost:6379

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage.xml

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
    - uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Login to GitHub Container Registry
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.repository_owner }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Build and push Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        platforms: linux/amd64,linux/arm64
        push: true
        tags: |
          ghcr.io/${{ github.repository }}:latest
          ghcr.io/${{ github.repository }}:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  security:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        ignore-unfixed: true
        format: 'sarif'
        output: 'trivy-results.sarif'

    - name: Upload Trivy scan results to GitHub Security tab
      uses: github/codeql-action/upload-sarif@v2
      if: always()
      with:
        sarif_file: 'trivy-results.sarif'
EOF
}

# Function to show help
show_help() {
    echo "PyAirtable Microservices Management Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list              List all repositories"
    echo "  status            Check repository status"
    echo "  clone [DIR]       Clone all repositories to directory (default: ./pyairtable-services)"
    echo "  settings          Update repository settings (enable features, branch protection)"
    echo "  workflows [DIR]   Add GitHub Actions workflows to service in directory"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 clone ./my-services"
    echo "  $0 workflows ./pyairtable-auth-service-go"
    echo ""
}

# Main execution
case "${1:-help}" in
    "list")
        list_repos
        ;;
    "status")
        check_status
        ;;
    "clone")
        clone_all "$2"
        ;;
    "settings")
        update_settings
        ;;
    "workflows")
        if [ -z "$2" ]; then
            log_error "Please specify a service directory"
            echo "Usage: $0 workflows <service_directory>"
            exit 1
        fi
        add_workflows "$2"
        ;;
    "help"|*)
        show_help
        ;;
esac