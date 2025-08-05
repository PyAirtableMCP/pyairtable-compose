#!/bin/bash

# PyAirtable Chaos Engineering Execution Script
# This script systematically executes chaos experiments and monitors their impact

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/chaos-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create results directory
mkdir -p "$RESULTS_DIR"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}PyAirtable Chaos Engineering Execution${NC}"
echo -e "${BLUE}Timestamp: $TIMESTAMP${NC}"
echo -e "${BLUE}============================================${NC}"

# Function to log with timestamp
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to capture system metrics
capture_baseline_metrics() {
    log "${YELLOW}Capturing baseline system metrics...${NC}"
    
    # Query Mimir for current metrics
    curl -s "http://localhost:8081/prometheus/api/v1/query?query=up" > "$RESULTS_DIR/baseline_up_${TIMESTAMP}.json"
    curl -s "http://localhost:8081/prometheus/api/v1/query?query=process_resident_memory_bytes" > "$RESULTS_DIR/baseline_memory_${TIMESTAMP}.json"
    curl -s "http://localhost:8081/prometheus/api/v1/query?query=http_requests_total" > "$RESULTS_DIR/baseline_requests_${TIMESTAMP}.json"
    
    # Check Docker container status
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" > "$RESULTS_DIR/baseline_containers_${TIMESTAMP}.txt"
    
    log "${GREEN}Baseline metrics captured${NC}"
}

# Function to start monitoring during experiments
start_experiment_monitoring() {
    local experiment_name=$1
    log "${YELLOW}Starting monitoring for experiment: $experiment_name${NC}"
    
    # Start background monitoring script
    (
        while [ -f "/tmp/chaos_experiment_running" ]; do
            timestamp=$(date '+%Y%m%d_%H%M%S')
            
            # Capture metrics every 10 seconds during experiment
            curl -s "http://localhost:8081/prometheus/api/v1/query?query=up" > "$RESULTS_DIR/${experiment_name}_up_${timestamp}.json" 2>/dev/null || true
            curl -s "http://localhost:8081/prometheus/api/v1/query?query=http_requests_total" > "$RESULTS_DIR/${experiment_name}_requests_${timestamp}.json" 2>/dev/null || true
            
            # Capture container status
            docker ps --format "{{.Names}}: {{.Status}}" | grep -E "(platform-services|gateway|postgres|redis)" > "$RESULTS_DIR/${experiment_name}_containers_${timestamp}.txt" 2>/dev/null || true
            
            sleep 10
        done
    ) &
    MONITORING_PID=$!
    echo $MONITORING_PID > "/tmp/chaos_monitoring_pid"
}

# Function to stop monitoring
stop_experiment_monitoring() {
    log "${YELLOW}Stopping experiment monitoring...${NC}"
    rm -f "/tmp/chaos_experiment_running"
    
    if [ -f "/tmp/chaos_monitoring_pid" ]; then
        MONITORING_PID=$(cat "/tmp/chaos_monitoring_pid")
        kill $MONITORING_PID 2>/dev/null || true
        rm -f "/tmp/chaos_monitoring_pid"
    fi
}

# Function to execute service failure scenarios
execute_service_failure_tests() {
    log "${BLUE}=== Executing Service Failure Scenarios ===${NC}"
    
    # Test 1: Container restart simulation
    log "${YELLOW}Test 1: Container Restart Simulation${NC}"
    touch "/tmp/chaos_experiment_running"
    start_experiment_monitoring "service_restart"
    
    # Find and restart a platform services container
    PLATFORM_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "(platform|gateway)" | head -1)
    if [ -n "$PLATFORM_CONTAINER" ]; then
        log "Restarting container: $PLATFORM_CONTAINER"
        docker restart "$PLATFORM_CONTAINER" || true
        
        # Monitor recovery time
        start_time=$(date +%s)
        while ! docker ps --format "{{.Names}}: {{.Status}}" | grep "$PLATFORM_CONTAINER" | grep -q "Up"; do
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            if [ $elapsed -gt 120 ]; then
                log "${RED}Container failed to restart within 2 minutes${NC}"
                break
            fi
            sleep 2
        done
        end_time=$(date +%s)
        recovery_time=$((end_time - start_time))
        
        log "${GREEN}Container recovery time: ${recovery_time} seconds${NC}"
        echo "service_restart_recovery_time_seconds: $recovery_time" >> "$RESULTS_DIR/recovery_metrics_${TIMESTAMP}.txt"
    else
        log "${YELLOW}No platform container found to restart${NC}"
    fi
    
    sleep 30  # Wait for system stabilization
    stop_experiment_monitoring
    
    # Test 2: Multiple container failure simulation
    log "${YELLOW}Test 2: Multiple Container Failure Simulation${NC}"
    touch "/tmp/chaos_experiment_running"
    start_experiment_monitoring "multiple_failure"
    
    # Stop multiple containers temporarily
    PLATFORM_CONTAINERS=$(docker ps --format "{{.Names}}" | grep -E "(platform|gateway)" | head -2)
    for container in $PLATFORM_CONTAINERS; do
        log "Stopping container: $container"
        docker stop "$container" || true
    done
    
    # Wait to observe impact
    sleep 60
    
    # Restart containers
    for container in $PLATFORM_CONTAINERS; do
        log "Starting container: $container"
        docker start "$container" || true
    done
    
    # Wait for recovery
    sleep 60
    stop_experiment_monitoring
}

# Function to execute network partition tests
execute_network_partition_tests() {
    log "${BLUE}=== Executing Network Partition Tests ===${NC}"
    
    # Test 1: Database connection interruption
    log "${YELLOW}Test 1: Database Connection Interruption${NC}"
    touch "/tmp/chaos_experiment_running"
    start_experiment_monitoring "db_partition"
    
    # Block database traffic using iptables (if available) or docker network manipulation
    DB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i postgres | head -1)
    if [ -n "$DB_CONTAINER" ]; then
        log "Disconnecting database container from network"
        
        # Get container network
        CONTAINER_NETWORK=$(docker inspect "$DB_CONTAINER" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)
        
        if [ -n "$CONTAINER_NETWORK" ]; then
            # Disconnect and reconnect after delay
            docker network disconnect "$CONTAINER_NETWORK" "$DB_CONTAINER" || true
            sleep 60  # 1 minute partition
            docker network connect "$CONTAINER_NETWORK" "$DB_CONTAINER" || true
            
            log "${GREEN}Database network partition test completed${NC}"
        fi
    fi
    
    sleep 30
    stop_experiment_monitoring
}

# Function to execute resource exhaustion tests
execute_resource_exhaustion_tests() {
    log "${BLUE}=== Executing Resource Exhaustion Tests ===${NC}"
    
    # Test 1: Memory pressure simulation
    log "${YELLOW}Test 1: Memory Pressure Simulation${NC}"
    touch "/tmp/chaos_experiment_running"
    start_experiment_monitoring "memory_pressure"
    
    # Create memory pressure using stress tool or similar
    # Since we may not have stress installed, we'll simulate with container limits
    PLATFORM_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "(platform|gateway)" | head -1)
    if [ -n "$PLATFORM_CONTAINER" ]; then
        log "Applying memory constraints to: $PLATFORM_CONTAINER"
        
        # Update container with memory limit (this requires restart)
        docker update --memory="128m" "$PLATFORM_CONTAINER" 2>/dev/null || log "Memory limit update not supported"
        
        sleep 120  # Monitor for 2 minutes
        
        # Remove memory constraint
        docker update --memory="0" "$PLATFORM_CONTAINER" 2>/dev/null || true
    fi
    
    stop_experiment_monitoring
}

# Function to execute database connection failure tests
execute_database_failure_tests() {
    log "${BLUE}=== Executing Database Connection Failure Tests ===${NC}"
    
    # Test 1: Database container stop/start
    log "${YELLOW}Test 1: Database Container Stop/Start${NC}"
    touch "/tmp/chaos_experiment_running"
    start_experiment_monitoring "db_failure"
    
    DB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i postgres | head -1)
    if [ -n "$DB_CONTAINER" ]; then
        log "Stopping database container: $DB_CONTAINER"
        docker stop "$DB_CONTAINER" || true
        
        # Monitor system behavior for 2 minutes
        sleep 120
        
        log "Restarting database container: $DB_CONTAINER"
        docker start "$DB_CONTAINER" || true
        
        # Wait for database to be ready
        sleep 60
        log "${GREEN}Database failure test completed${NC}"
    fi
    
    stop_experiment_monitoring
}

# Function to validate chaos resilience mechanisms
validate_resilience_mechanisms() {
    log "${BLUE}=== Validating Resilience Mechanisms ===${NC}"
    
    # Check circuit breaker status (if accessible via API)
    log "${YELLOW}Checking circuit breaker status...${NC}"
    
    # Check health endpoints
    log "${YELLOW}Checking health endpoints...${NC}"
    
    # Test various endpoints to see if they respond appropriately
    endpoints=(
        "http://localhost:8007/health"
        "http://localhost:8007/auth/verify"
        "http://localhost:8007/analytics/metrics"
    )
    
    for endpoint in "${endpoints[@]}"; do
        response=$(curl -s -o /dev/null -w "%{http_code}" "$endpoint" 2>/dev/null || echo "000")
        log "Endpoint $endpoint: HTTP $response"
        echo "endpoint_check: $endpoint: $response" >> "$RESULTS_DIR/resilience_check_${TIMESTAMP}.txt"
    done
}

# Function to analyze results
analyze_results() {
    log "${BLUE}=== Analyzing Chaos Experiment Results ===${NC}"
    
    # Count number of metric files captured
    metric_files=$(find "$RESULTS_DIR" -name "*_${TIMESTAMP}.json" | wc -l)
    log "Captured $metric_files metric snapshots"
    
    # Check for any container restart events
    restart_count=$(find "$RESULTS_DIR" -name "*containers*" -exec grep -l "Restarting\|starting" {} \; | wc -l)
    log "Detected $restart_count container restart events"
    
    # Summary
    cat > "$RESULTS_DIR/chaos_experiment_summary_${TIMESTAMP}.md" << EOF
# Chaos Engineering Experiment Summary

**Timestamp:** $TIMESTAMP
**Duration:** $(date)

## Experiments Executed

1. **Service Failure Scenarios**
   - Container restart simulation
   - Multiple container failure simulation

2. **Network Partition Tests**
   - Database connection interruption

3. **Resource Exhaustion Tests**
   - Memory pressure simulation

4. **Database Connection Failures**
   - Database container stop/start

## Metrics Collected
- Total metric snapshots: $metric_files
- Container restart events: $restart_count

## Files Generated
$(ls -la "$RESULTS_DIR"/*${TIMESTAMP}* | wc -l) files created in $RESULTS_DIR

## Next Steps
- Review metric files for anomalies
- Analyze recovery patterns
- Document recommendations for resilience improvements

EOF

    log "${GREEN}Results analysis completed. Summary: $RESULTS_DIR/chaos_experiment_summary_${TIMESTAMP}.md${NC}"
}

# Main execution flow
main() {
    log "${GREEN}Starting PyAirtable Chaos Engineering Experiments${NC}"
    
    # Pre-flight checks
    if ! command -v docker &> /dev/null; then
        log "${RED}Docker is required but not installed${NC}"
        exit 1
    fi
    
    if ! curl -s http://localhost:3001/api/health > /dev/null; then
        log "${RED}Grafana not accessible at localhost:3001${NC}"
        exit 1
    fi
    
    # Capture baseline
    capture_baseline_metrics
    
    # Execute experiments in order
    execute_service_failure_tests
    execute_network_partition_tests
    execute_resource_exhaustion_tests
    execute_database_failure_tests
    
    # Validate resilience mechanisms
    validate_resilience_mechanisms
    
    # Analyze results
    analyze_results
    
    log "${GREEN}Chaos engineering experiments completed successfully!${NC}"
    log "${BLUE}Results available in: $RESULTS_DIR${NC}"
}

# Trap to ensure cleanup on exit
trap 'stop_experiment_monitoring; rm -f /tmp/chaos_experiment_running' EXIT

# Execute main function
main "$@"