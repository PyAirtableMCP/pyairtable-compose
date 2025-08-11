#!/bin/bash

# Container Security Scanning Script
# Uses Trivy to scan Docker images for vulnerabilities

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCAN_OUTPUT_DIR="./security-scan-results"
TRIVY_CACHE_DIR="./trivy-cache"
REPORT_FORMAT="json"
SEVERITY_LEVELS="CRITICAL,HIGH,MEDIUM,LOW"
SCAN_TIMEOUT="10m"

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

# Check if Trivy is installed
check_trivy() {
    if ! command -v trivy &> /dev/null; then
        log_error "Trivy not found. Installing..."
        install_trivy
    else
        log_info "Trivy is already installed"
    fi
}

# Install Trivy
install_trivy() {
    log_info "Installing Trivy..."
    
    case "$(uname -s)" in
        Linux*)
            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
            ;;
        Darwin*)
            if command -v brew &> /dev/null; then
                brew install trivy
            else
                log_error "Please install Homebrew or manually install Trivy"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported operating system"
            exit 1
            ;;
    esac
    
    log_success "Trivy installed successfully"
}

# Create output directories
setup_directories() {
    mkdir -p "$SCAN_OUTPUT_DIR"
    mkdir -p "$TRIVY_CACHE_DIR"
    log_info "Created output directories"
}

# Get list of images to scan
get_images_to_scan() {
    local compose_file="${1:-docker-compose.production.yml}"
    
    if [ ! -f "$compose_file" ]; then
        log_error "Docker Compose file not found: $compose_file"
        exit 1
    fi
    
    # Extract image names from docker-compose file
    grep -E "^\s*image:" "$compose_file" | sed 's/.*image:\s*//' | sed 's/\${.*}/latest/' | sort -u
}

# Scan individual image
scan_image() {
    local image="$1"
    local output_file="$SCAN_OUTPUT_DIR/$(echo "$image" | tr '/:' '_').json"
    local summary_file="$SCAN_OUTPUT_DIR/$(echo "$image" | tr '/:' '_').summary.txt"
    
    log_info "Scanning image: $image"
    
    # Perform vulnerability scan
    if trivy image \
        --cache-dir "$TRIVY_CACHE_DIR" \
        --format "$REPORT_FORMAT" \
        --output "$output_file" \
        --severity "$SEVERITY_LEVELS" \
        --timeout "$SCAN_TIMEOUT" \
        --quiet \
        "$image"; then
        
        # Generate human-readable summary
        trivy image \
            --cache-dir "$TRIVY_CACHE_DIR" \
            --format table \
            --output "$summary_file" \
            --severity "CRITICAL,HIGH" \
            "$image" 2>/dev/null || true
        
        # Count vulnerabilities
        local critical_count high_count medium_count low_count
        critical_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL") | .VulnerabilityID' "$output_file" 2>/dev/null | wc -l || echo "0")
        high_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH") | .VulnerabilityID' "$output_file" 2>/dev/null | wc -l || echo "0")
        medium_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM") | .VulnerabilityID' "$output_file" 2>/dev/null | wc -l || echo "0")
        low_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="LOW") | .VulnerabilityID' "$output_file" 2>/dev/null | wc -l || echo "0")
        
        log_info "Scan completed for $image: Critical=$critical_count, High=$high_count, Medium=$medium_count, Low=$low_count"
        
        # Return vulnerability counts
        echo "$critical_count $high_count $medium_count $low_count"
    else
        log_error "Failed to scan image: $image"
        echo "0 0 0 0"
    fi
}

# Generate consolidated report
generate_report() {
    local report_file="$SCAN_OUTPUT_DIR/security-scan-report.html"
    local summary_file="$SCAN_OUTPUT_DIR/security-scan-summary.txt"
    
    log_info "Generating consolidated security report..."
    
    # Create HTML report
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Security Scan Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .critical { color: #d32f2f; font-weight: bold; }
        .high { color: #f57c00; font-weight: bold; }
        .medium { color: #fbc02d; }
        .low { color: #388e3c; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f5f5f5; }
        .summary { background-color: #f9f9f9; padding: 20px; margin: 20px 0; border-radius: 5px; }
        .pass { color: #4caf50; }
        .fail { color: #f44336; }
    </style>
</head>
<body>
    <h1>Container Security Scan Report</h1>
    <div class="summary">
        <h2>Scan Summary</h2>
        <p><strong>Scan Date:</strong> $(date)</p>
        <p><strong>Scanner:</strong> Trivy</p>
        <p><strong>Severity Levels:</strong> $SEVERITY_LEVELS</p>
    </div>
    <table>
        <thead>
            <tr>
                <th>Image</th>
                <th>Critical</th>
                <th>High</th>
                <th>Medium</th>
                <th>Low</th>
                <th>Status</th>
            </tr>
        </thead>
        <tbody>
EOF

    # Create summary file
    echo "Container Security Scan Summary" > "$summary_file"
    echo "===============================" >> "$summary_file"
    echo "Scan Date: $(date)" >> "$summary_file"
    echo "Scanner: Trivy" >> "$summary_file"
    echo "" >> "$summary_file"
    
    local total_critical=0 total_high=0 total_medium=0 total_low=0
    local images_scanned=0 images_passed=0
    
    # Process each scan result
    for json_file in "$SCAN_OUTPUT_DIR"/*.json; do
        if [ -f "$json_file" ]; then
            local image_name
            image_name=$(basename "$json_file" .json | tr '_' '/')
            
            local critical_count high_count medium_count low_count
            critical_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL") | .VulnerabilityID' "$json_file" 2>/dev/null | wc -l || echo "0")
            high_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH") | .VulnerabilityID' "$json_file" 2>/dev/null | wc -l || echo "0")
            medium_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM") | .VulnerabilityID' "$json_file" 2>/dev/null | wc -l || echo "0")
            low_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity=="LOW") | .VulnerabilityID' "$json_file" 2>/dev/null | wc -l || echo "0")
            
            total_critical=$((total_critical + critical_count))
            total_high=$((total_high + high_count))
            total_medium=$((total_medium + medium_count))
            total_low=$((total_low + low_count))
            images_scanned=$((images_scanned + 1))
            
            local status="PASS"
            local status_class="pass"
            if [ "$critical_count" -gt 0 ] || [ "$high_count" -gt 10 ]; then
                status="FAIL"
                status_class="fail"
            else
                images_passed=$((images_passed + 1))
            fi
            
            # Add to HTML report
            cat >> "$report_file" << EOF
            <tr>
                <td>$image_name</td>
                <td class="critical">$critical_count</td>
                <td class="high">$high_count</td>
                <td class="medium">$medium_count</td>
                <td class="low">$low_count</td>
                <td class="$status_class">$status</td>
            </tr>
EOF
            
            # Add to summary
            echo "Image: $image_name" >> "$summary_file"
            echo "  Critical: $critical_count" >> "$summary_file"
            echo "  High: $high_count" >> "$summary_file"
            echo "  Medium: $medium_count" >> "$summary_file"
            echo "  Low: $low_count" >> "$summary_file"
            echo "  Status: $status" >> "$summary_file"
            echo "" >> "$summary_file"
        fi
    done
    
    # Close HTML report
    cat >> "$report_file" << EOF
        </tbody>
    </table>
    <div class="summary">
        <h2>Overall Results</h2>
        <p><strong>Images Scanned:</strong> $images_scanned</p>
        <p><strong>Images Passed:</strong> $images_passed</p>
        <p><strong>Images Failed:</strong> $((images_scanned - images_passed))</p>
        <p><strong>Total Critical:</strong> <span class="critical">$total_critical</span></p>
        <p><strong>Total High:</strong> <span class="high">$total_high</span></p>
        <p><strong>Total Medium:</strong> <span class="medium">$total_medium</span></p>
        <p><strong>Total Low:</strong> <span class="low">$total_low</span></p>
    </div>
</body>
</html>
EOF
    
    # Add totals to summary
    echo "OVERALL RESULTS" >> "$summary_file"
    echo "===============" >> "$summary_file"
    echo "Images Scanned: $images_scanned" >> "$summary_file"
    echo "Images Passed: $images_passed" >> "$summary_file"
    echo "Images Failed: $((images_scanned - images_passed))" >> "$summary_file"
    echo "Total Critical: $total_critical" >> "$summary_file"
    echo "Total High: $total_high" >> "$summary_file"
    echo "Total Medium: $total_medium" >> "$summary_file"
    echo "Total Low: $total_low" >> "$summary_file"
    
    log_success "Reports generated:"
    log_info "  HTML Report: $report_file"
    log_info "  Summary: $summary_file"
    
    # Return exit code based on results
    if [ "$total_critical" -gt 0 ]; then
        return 2  # Critical vulnerabilities found
    elif [ "$total_high" -gt 20 ]; then
        return 1  # Too many high vulnerabilities
    else
        return 0  # All good
    fi
}

# Main function
main() {
    local compose_file="${1:-docker-compose.production.yml}"
    local scan_mode="${2:-all}"
    
    log_info "Starting container security scan..."
    log_info "Compose file: $compose_file"
    log_info "Scan mode: $scan_mode"
    
    check_trivy
    setup_directories
    
    # Update Trivy database
    log_info "Updating Trivy vulnerability database..."
    trivy image --download-db-only --cache-dir "$TRIVY_CACHE_DIR" --quiet
    
    # Get images to scan
    local images
    images=$(get_images_to_scan "$compose_file")
    
    if [ -z "$images" ]; then
        log_warning "No images found to scan"
        exit 0
    fi
    
    log_info "Found $(echo "$images" | wc -l) images to scan"
    
    # Scan each image
    local total_critical=0 total_high=0
    while IFS= read -r image; do
        if [ -n "$image" ]; then
            local counts
            counts=$(scan_image "$image")
            local critical high medium low
            read -r critical high medium low <<< "$counts"
            total_critical=$((total_critical + critical))
            total_high=$((total_high + high))
        fi
    done <<< "$images"
    
    # Generate reports
    local exit_code=0
    if ! generate_report; then
        exit_code=$?
    fi
    
    log_success "Security scan completed!"
    log_info "Results saved in: $SCAN_OUTPUT_DIR"
    
    # Summary
    if [ $exit_code -eq 2 ]; then
        log_error "CRITICAL vulnerabilities found! Immediate action required."
    elif [ $exit_code -eq 1 ]; then
        log_warning "HIGH vulnerabilities found. Review and remediate."
    else
        log_success "Security scan passed all checks."
    fi
    
    exit $exit_code
}

# Show help
show_help() {
    echo "Container Security Scanning Tool"
    echo ""
    echo "Usage: $0 [COMPOSE_FILE] [SCAN_MODE]"
    echo ""
    echo "Options:"
    echo "  COMPOSE_FILE    Docker Compose file to scan (default: docker-compose.production.yml)"
    echo "  SCAN_MODE       Scan mode: all, critical, high (default: all)"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Scan production compose with all severity levels"
    echo "  $0 docker-compose.yml critical              # Scan with critical vulnerabilities only"
    echo "  $0 docker-compose.test.yml all              # Scan test compose with all levels"
    echo ""
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac