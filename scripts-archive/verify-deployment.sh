#!/bin/bash

# PyAirtable Microservices Deployment Verification Script
# Verifies that all repositories are properly configured and accessible

set -e

# Configuration
ORG="Reg-Kris"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Function to verify repository exists and is accessible
verify_repo_exists() {
    local repo="$1"
    
    if gh repo view "$ORG/$repo" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to verify repository has proper configuration
verify_repo_config() {
    local repo="$1"
    local issues=0
    
    log_info "Verifying configuration for $repo..."
    
    # Get repository information
    local repo_info=$(gh repo view "$ORG/$repo" --json name,description,visibility,hasIssuesEnabled,hasWikiEnabled,hasProjectsEnabled)
    
    # Check visibility
    local visibility=$(echo "$repo_info" | jq -r '.visibility')
    if [ "$visibility" != "PUBLIC" ]; then
        log_warning "$repo: Repository is not public (visibility: $visibility)"
        ((issues++))
    fi
    
    # Check if issues are enabled
    local has_issues=$(echo "$repo_info" | jq -r '.hasIssuesEnabled')
    if [ "$has_issues" != "true" ]; then
        log_warning "$repo: Issues are not enabled"
        ((issues++))
    fi
    
    # Check if description exists
    local description=$(echo "$repo_info" | jq -r '.description')
    if [ "$description" = "null" ] || [ -z "$description" ]; then
        log_warning "$repo: No description set"
        ((issues++))
    fi
    
    return $issues
}

# Function to verify repository topics
verify_repo_topics() {
    local repo="$1"
    
    # Get current topics
    local current_topics=$(gh repo view "$ORG/$repo" --json repositoryTopics --jq '.repositoryTopics[].name' | tr '\n' ',' | sed 's/,$//')
    
    if [ -n "$current_topics" ]; then
        log_success "$repo: Topics: $current_topics"
        return 0
    else
        log_warning "$repo: No topics found"
        return 1
    fi
}

# Function to verify repository has recent commits
verify_repo_activity() {
    local repo="$1"
    
    # Get latest commit information
    local latest_commit=$(gh api repos/$ORG/$repo/commits/main --jq '.commit.committer.date')
    
    if [ -n "$latest_commit" ]; then
        log_success "$repo: Latest commit: $latest_commit"
        return 0
    else
        log_error "$repo: No commits found"
        return 1
    fi
}

# Function to verify repository file structure
verify_repo_structure() {
    local repo="$1"
    
    # Check for essential files
    local files_to_check=("README.md" ".gitignore")
    local missing_files=()
    
    for file in "${files_to_check[@]}"; do
        if ! gh api repos/$ORG/$repo/contents/$file &> /dev/null; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        log_success "$repo: All essential files present"
        return 0
    else
        log_warning "$repo: Missing files: ${missing_files[*]}"
        return 1
    fi
}

# Function to generate deployment report
generate_report() {
    local total_repos=${#REPOS[@]}
    local successful_repos=0
    local failed_repos=0
    
    echo ""
    echo "===========================================" 
    log_info "PyAirtable Microservices Deployment Report"
    echo "==========================================="
    echo ""
    
    for repo in "${REPOS[@]}"; do
        echo "🔍 Verifying: $repo"
        echo "   URL: https://github.com/$ORG/$repo"
        
        local repo_issues=0
        
        # Check if repository exists
        if verify_repo_exists "$repo"; then
            echo "   ✅ Repository exists"
            
            # Verify configuration
            verify_repo_config "$repo"
            repo_issues=$((repo_issues + $?))
            
            # Verify topics
            verify_repo_topics "$repo"
            repo_issues=$((repo_issues + $?))
            
            # Verify activity
            verify_repo_activity "$repo"
            repo_issues=$((repo_issues + $?))
            
            # Verify structure
            verify_repo_structure "$repo"
            repo_issues=$((repo_issues + $?))
            
            if [ $repo_issues -eq 0 ]; then
                echo "   ✅ All verifications passed"
                ((successful_repos++))
            else
                echo "   ⚠️  $repo_issues issues found"
                ((failed_repos++))
            fi
        else
            echo "   ❌ Repository not found"
            ((failed_repos++))
        fi
        
        echo ""
    done
    
    echo "==========================================="
    echo "📊 SUMMARY:"
    echo "   Total repositories: $total_repos"
    echo "   ✅ Successful: $successful_repos"
    echo "   ⚠️  With issues: $failed_repos"
    echo ""
    
    if [ $failed_repos -eq 0 ]; then
        log_success "🎉 All repositories are properly configured!"
        echo ""
        echo "🚀 Ready for development and deployment!"
        echo ""
        echo "Next steps:"
        echo "   1. Clone repositories: ./manage-repos.sh clone"
        echo "   2. Set up CI/CD: ./manage-repos.sh settings"
        echo "   3. Start development: cd pyairtable-services"
        echo ""
    else
        log_warning "⚠️  Some repositories need attention"
        echo ""
        echo "Consider running:"
        echo "   ./manage-repos.sh settings  # To fix repository settings"
        echo ""
    fi
}

# Function to show help
show_help() {
    echo "PyAirtable Microservices Deployment Verification"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  verify            Run full verification (default)"
    echo "  report            Generate detailed report"
    echo "  quick             Quick status check"
    echo "  help              Show this help"
    echo ""
}

# Quick status check
quick_check() {
    log_info "Quick status check..."
    echo ""
    
    local total=0
    local exists=0
    
    for repo in "${REPOS[@]}"; do
        ((total++))
        if verify_repo_exists "$repo"; then
            echo "✅ $repo"
            ((exists++))
        else
            echo "❌ $repo"
        fi
    done
    
    echo ""
    log_info "Status: $exists/$total repositories exist"
}

# Main execution
case "${1:-verify}" in
    "verify"|"report")
        generate_report
        ;;
    "quick")
        quick_check
        ;;
    "help"|*)
        show_help
        ;;
esac