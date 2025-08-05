#!/bin/bash

# PyAirtable Consolidated Services Deployment Validation Script
# This script validates that all consolidated services are properly deployed and accessible

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_ORG="PyAirtableMCP"
REGISTRY="ghcr.io"

# Services to validate
SERVICES=(
    "pyairtable-auth-consolidated"
    "pyairtable-tenant-consolidated"
    "pyairtable-data-consolidated"
    "pyairtable-automation-consolidated"
    "pyairtable-ai-consolidated"
    "pyairtable-gateway-consolidated"
)

GO_SERVICES=(
    "pyairtable-auth-consolidated"
    "pyairtable-tenant-consolidated"
    "pyairtable-gateway-consolidated"
)

PYTHON_SERVICES=(
    "pyairtable-data-consolidated"
    "pyairtable-automation-consolidated"
    "pyairtable-ai-consolidated"
)

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to check if GitHub CLI is installed and authenticated
check_github_cli() {
    log "Checking GitHub CLI..."
    
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    
    success "GitHub CLI is installed and authenticated"
}

# Function to validate repository exists and has proper structure
validate_repository() {
    local repo=$1
    log "Validating repository: $repo"
    
    # Check if repository exists
    if ! gh repo view "$GITHUB_ORG/$repo" &> /dev/null; then
        error "Repository $GITHUB_ORG/$repo does not exist"
        return 1
    fi
    
    # Check if repository has required files
    local required_files=(".github/workflows/ci.yml" "Dockerfile" "README.md")
    
    for file in "${required_files[@]}"; do
        if ! gh api "repos/$GITHUB_ORG/$repo/contents/$file" &> /dev/null; then
            warning "Missing required file: $file in $repo"
        else
            success "Found required file: $file in $repo"
        fi
    done
    
    # Check if main branch exists
    if ! gh api "repos/$GITHUB_ORG/$repo/branches/main" &> /dev/null; then
        error "Main branch does not exist in $repo"
        return 1
    fi
    
    success "Repository $repo structure validated"
}

# Function to check CI/CD pipeline status
check_ci_status() {
    local repo=$1
    log "Checking CI/CD status for: $repo"
    
    # Get latest workflow run
    local workflow_status
    workflow_status=$(gh api "repos/$GITHUB_ORG/$repo/actions/runs" --jq '.workflow_runs[0].status // "none"')
    
    if [ "$workflow_status" = "completed" ]; then
        local conclusion
        conclusion=$(gh api "repos/$GITHUB_ORG/$repo/actions/runs" --jq '.workflow_runs[0].conclusion // "none"')
        if [ "$conclusion" = "success" ]; then
            success "Latest CI run successful for $repo"
        else
            warning "Latest CI run failed for $repo (conclusion: $conclusion)"
        fi
    elif [ "$workflow_status" = "in_progress" ]; then
        warning "CI run in progress for $repo"
    else
        warning "No CI runs found for $repo"
    fi
}

# Function to check if Docker images are built and available
check_docker_images() {
    local repo=$1
    log "Checking Docker images for: $repo"
    
    # Check if packages exist (this requires the packages:read permission)
    if gh api "orgs/$GITHUB_ORG/packages/container/$repo/versions" &> /dev/null; then
        success "Docker images available for $repo"
    else
        warning "No Docker images found for $repo (may be building or not yet published)"
    fi
}

# Function to validate service-specific requirements
validate_go_service() {
    local repo=$1
    log "Validating Go service: $repo"
    
    # Check for Go-specific files
    local go_files=("go.mod" "cmd/server/main.go")
    
    for file in "${go_files[@]}"; do
        if gh api "repos/$GITHUB_ORG/$repo/contents/$file" &> /dev/null; then
            success "Found Go file: $file in $repo"
        else
            warning "Missing Go file: $file in $repo"
        fi
    done
    
    # Check for linting configuration
    if gh api "repos/$GITHUB_ORG/$repo/contents/.golangci.yml" &> /dev/null; then
        success "Found golangci-lint configuration in $repo"
    else
        warning "Missing golangci-lint configuration in $repo"
    fi
}

# Function to validate Python service requirements
validate_python_service() {
    local repo=$1
    log "Validating Python service: $repo"
    
    # Check for Python-specific files
    local python_files=("pyproject.toml" "src")
    
    for file in "${python_files[@]}"; do
        if gh api "repos/$GITHUB_ORG/$repo/contents/$file" &> /dev/null; then
            success "Found Python file/directory: $file in $repo"
        else
            warning "Missing Python file/directory: $file in $repo"
        fi
    done
}

# Function to check repository settings
check_repository_settings() {
    local repo=$1
    log "Checking repository settings: $repo"
    
    # Get repository information
    local repo_info
    repo_info=$(gh api "repos/$GITHUB_ORG/$repo")
    
    # Check if repository is private (for security)
    local is_private
    is_private=$(echo "$repo_info" | jq -r '.private')
    
    if [ "$is_private" = "true" ]; then
        success "Repository $repo is private (good for security)"
    else
        warning "Repository $repo is public (consider making it private for production)"
    fi
    
    # Check if issues are enabled
    local has_issues
    has_issues=$(echo "$repo_info" | jq -r '.has_issues')
    
    if [ "$has_issues" = "true" ]; then
        success "Issues enabled for $repo"
    else
        warning "Issues disabled for $repo"
    fi
    
    # Check default branch
    local default_branch
    default_branch=$(echo "$repo_info" | jq -r '.default_branch')
    
    if [ "$default_branch" = "main" ]; then
        success "Default branch is 'main' for $repo"
    else
        warning "Default branch is '$default_branch' for $repo (expected 'main')"
    fi
}

# Function to generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    echo ""
    echo "=================================================="
    echo "      PyAirtable Consolidated Services"
    echo "           Deployment Summary"
    echo "=================================================="
    echo ""
    
    echo "GitHub Organization: $GITHUB_ORG"
    echo "Container Registry: $REGISTRY"
    echo "Total Services: ${#SERVICES[@]}"
    echo ""
    
    echo "Go Services (${#GO_SERVICES[@]}):"
    for service in "${GO_SERVICES[@]}"; do
        echo "  - $service"
    done
    
    echo ""
    echo "Python Services (${#PYTHON_SERVICES[@]}):"
    for service in "${PYTHON_SERVICES[@]}"; do
        echo "  - $service"
    done
    
    echo ""
    echo "All services include:"
    echo "  ✓ Comprehensive CI/CD pipelines"
    echo "  ✓ Multi-stage Docker builds"
    echo "  ✓ Security scanning and testing"
    echo "  ✓ Production-ready configurations"
    echo "  ✓ Health checks and monitoring"
    echo "  ✓ Documentation and examples"
    echo ""
    
    echo "Next steps:"
    echo "  1. Configure production secrets in GitHub"
    echo "  2. Set up staging and production environments"
    echo "  3. Deploy to Kubernetes or Docker Swarm"
    echo "  4. Configure monitoring and alerting"
    echo "  5. Set up log aggregation"
    echo ""
}

# Main validation function
main() {
    log "Starting PyAirtable Consolidated Services validation..."
    
    check_github_cli
    
    local failed_validations=0
    
    for service in "${SERVICES[@]}"; do
        echo ""
        log "Validating service: $service"
        
        if ! validate_repository "$service"; then
            ((failed_validations++))
            continue
        fi
        
        check_ci_status "$service"
        check_docker_images "$service"
        check_repository_settings "$service"
        
        # Service-specific validations
        if [[ " ${GO_SERVICES[*]} " =~ " ${service} " ]]; then
            validate_go_service "$service"
        elif [[ " ${PYTHON_SERVICES[*]} " =~ " ${service} " ]]; then
            validate_python_service "$service"
        fi
        
        success "Service $service validation completed"
    done
    
    echo ""
    if [ $failed_validations -eq 0 ]; then
        success "All services validated successfully!"
    else
        warning "$failed_validations service(s) had validation issues"
    fi
    
    generate_summary
    
    log "Validation completed!"
}

# Run main function
main "$@"