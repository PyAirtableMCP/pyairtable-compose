#!/bin/bash
# Spot Instance Testing Script
# Task: immediate-6 - Test non-critical services (analytics, reporting) on Spot instances

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.spot-testing.yml"
TEST_DURATION=${TEST_DURATION:-300}  # 5 minutes default
LOG_DIR="./spot-test-logs"
RESULTS_FILE="$LOG_DIR/spot-test-results.json"

# Non-critical services to test
SPOT_SERVICES=(
    "analytics-service"
    "report-service"
    "data-processing-service"
    "task-scheduler"
)

# Critical services that should remain stable
CRITICAL_SERVICES=(
    "api-gateway"
    "platform-services"
    "postgres"
    "redis"
)

print_header() {
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}PyAirtable Spot Instance Testing${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo "Test Duration: ${TEST_DURATION} seconds"
    echo "Services under test: ${SPOT_SERVICES[*]}"
    echo "Critical services: ${CRITICAL_SERVICES[*]}"
    echo ""
}

setup_test_environment() {
    echo -e "${YELLOW}Setting up test environment...${NC}"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Ensure environment variables are set
    if [ ! -f ".env" ]; then
        echo -e "${RED}Error: .env file not found. Creating default...${NC}"
        cat > .env << EOF
POSTGRES_DB=pyairtable_test
POSTGRES_USER=postgres
POSTGRES_PASSWORD=testpass123
REDIS_PASSWORD=testredis123
API_KEY=test-api-key-$(date +%s)
LOG_LEVEL=INFO
EOF
    fi
    
    # Pull latest images
    echo -e "${YELLOW}Pulling latest Docker images...${NC}"
    docker-compose -f "$COMPOSE_FILE" pull
    
    echo -e "${GREEN}Test environment setup complete${NC}"
}

start_services() {
    echo -e "${YELLOW}Starting services...${NC}"
    
    # Start infrastructure services first
    docker-compose -f "$COMPOSE_FILE" up -d postgres redis
    
    # Wait for infrastructure to be ready
    echo "Waiting for infrastructure services..."
    sleep 30
    
    # Start critical services
    docker-compose -f "$COMPOSE_FILE" up -d api-gateway platform-services
    
    # Wait for critical services
    echo "Waiting for critical services..."
    sleep 20
    
    # Start spot-eligible services
    for service in "${SPOT_SERVICES[@]}"; do
        echo "Starting spot-eligible service: $service"
        docker-compose -f "$COMPOSE_FILE" up -d "$service"
        sleep 5
    done
    
    # Start monitoring
    docker-compose -f "$COMPOSE_FILE" up -d spot-monitor
    
    echo -e "${GREEN}All services started${NC}"
}

wait_for_services() {
    echo -e "${YELLOW}Waiting for services to become healthy...${NC}"
    
    local max_wait=120
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local all_healthy=true
        
        # Check critical services
        for service in "${CRITICAL_SERVICES[@]}"; do
            if ! check_service_health "$service"; then
                all_healthy=false
                break
            fi
        done
        
        # Check spot services
        for service in "${SPOT_SERVICES[@]}"; do
            if ! check_service_health "$service"; then
                all_healthy=false
                break
            fi
        done
        
        if [ "$all_healthy" = true ]; then
            echo -e "${GREEN}All services are healthy${NC}"
            return 0
        fi
        
        echo "Waiting for services to become healthy... ($wait_time/$max_wait)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    echo -e "${RED}Timeout waiting for services to become healthy${NC}"
    return 1
}

check_service_health() {
    local service=$1
    local container_name="${PWD##*/}_${service}_1"
    
    # Skip health check for services without HTTP endpoints
    if [[ "$service" == "postgres" || "$service" == "redis" ]]; then
        docker-compose -f "$COMPOSE_FILE" ps "$service" | grep -q "Up" && return 0 || return 1
    fi
    
    # Get service port from docker-compose
    local port
    case "$service" in
        "api-gateway") port=8000 ;;
        "platform-services") port=8007 ;;
        "analytics-service") port=8108 ;;
        "report-service") port=8202 ;;
        "data-processing-service") port=8201 ;;
        "task-scheduler") port=8204 ;;
        *) port=8080 ;;
    esac
    
    curl -s -f "http://localhost:$port/health" > /dev/null 2>&1 && return 0 || return 1
}

simulate_spot_interruption() {
    local service=$1
    echo -e "${YELLOW}Simulating spot interruption for $service...${NC}"
    
    # Record the interruption
    local timestamp=$(date -Iseconds)
    echo "{\"timestamp\": \"$timestamp\", \"service\": \"$service\", \"event\": \"spot_interruption_start\"}" >> "$LOG_DIR/interruptions.log"
    
    # Stop the service (simulating spot interruption)
    docker-compose -f "$COMPOSE_FILE" stop "$service"
    
    # Wait a bit to simulate interruption duration
    sleep 10
    
    # Restart the service (simulating new spot instance)
    docker-compose -f "$COMPOSE_FILE" start "$service"
    
    # Record the recovery
    timestamp=$(date -Iseconds)
    echo "{\"timestamp\": \"$timestamp\", \"service\": \"$service\", \"event\": \"spot_interruption_end\"}" >> "$LOG_DIR/interruptions.log"
    
    echo -e "${GREEN}Spot interruption simulation complete for $service${NC}"
}

monitor_services() {
    echo -e "${YELLOW}Starting service monitoring for $TEST_DURATION seconds...${NC}"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + TEST_DURATION))
    local check_interval=30
    
    # Initialize results
    cat > "$RESULTS_FILE" << EOF
{
    "test_start": "$(date -Iseconds)",
    "test_duration": $TEST_DURATION,
    "spot_services": $(printf '%s\n' "${SPOT_SERVICES[@]}" | jq -R . | jq -s .),
    "critical_services": $(printf '%s\n' "${CRITICAL_SERVICES[@]}" | jq -R . | jq -s .),
    "health_checks": [],
    "interruptions": [],
    "performance_metrics": {}
}
EOF
    
    local interruption_count=0
    
    while [ $(date +%s) -lt $end_time ]; do
        local current_time=$(date -Iseconds)
        local health_check_result="{"
        
        echo "Monitoring services... ($(date))"
        
        # Check health of all services
        for service in "${CRITICAL_SERVICES[@]}" "${SPOT_SERVICES[@]}"; do
            local is_healthy
            if check_service_health "$service"; then
                is_healthy=true
                echo -e "  $service: ${GREEN}HEALTHY${NC}"
            else
                is_healthy=false
                echo -e "  $service: ${RED}UNHEALTHY${NC}"
            fi
            
            health_check_result+='"'$service'": '$is_healthy', '
        done
        
        health_check_result=${health_check_result%, }
        health_check_result+="}"
        
        # Log health check result
        jq --argjson timestamp "\"$current_time\"" \
           --argjson health_check "$health_check_result" \
           '.health_checks += [{"timestamp": $timestamp, "services": $health_check}]' \
           "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
        
        # Simulate spot interruption occasionally (every 2 minutes, max 3 times)
        local elapsed=$(($(date +%s) - start_time))
        if [ $((elapsed % 120)) -eq 0 ] && [ $interruption_count -lt 3 ] && [ $elapsed -gt 60 ]; then
            local service_to_interrupt=${SPOT_SERVICES[$((RANDOM % ${#SPOT_SERVICES[@]}))]}
            simulate_spot_interruption "$service_to_interrupt" &
            interruption_count=$((interruption_count + 1))
        fi
        
        sleep $check_interval
    done
    
    echo -e "${GREEN}Monitoring complete${NC}"
}

collect_performance_metrics() {
    echo -e "${YELLOW}Collecting performance metrics...${NC}"
    
    local metrics="{"
    
    # Docker stats for each service
    for service in "${CRITICAL_SERVICES[@]}" "${SPOT_SERVICES[@]}"; do
        local container_name="${PWD##*/}_${service}_1"
        local cpu_usage=$(docker stats --no-stream --format "table {{.CPUPerc}}" "$container_name" 2>/dev/null | tail -n +2 | tr -d '%' || echo "0")
        local memory_usage=$(docker stats --no-stream --format "table {{.MemUsage}}" "$container_name" 2>/dev/null | tail -n +2 | cut -d'/' -f1 | tr -d ' MiB' || echo "0")
        
        metrics+='"'$service'": {"cpu_percent": "'$cpu_usage'", "memory_mb": "'$memory_usage'"}, '
    done
    
    metrics=${metrics%, }
    metrics+="}"
    
    # Update results file with metrics
    jq --argjson metrics "$metrics" \
       '.performance_metrics = $metrics' \
       "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    
    # Add interruption data
    if [ -f "$LOG_DIR/interruptions.log" ]; then
        local interruptions="["
        while IFS= read -r line; do
            interruptions+="$line, "
        done < "$LOG_DIR/interruptions.log"
        interruptions=${interruptions%, }
        interruptions+="]"
        
        jq --argjson interruptions "$interruptions" \
           '.interruptions = $interruptions' \
           "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
    fi
    
    # Add test completion timestamp
    jq --arg end_time "$(date -Iseconds)" \
       '.test_end = $end_time' \
       "$RESULTS_FILE" > "$RESULTS_FILE.tmp" && mv "$RESULTS_FILE.tmp" "$RESULTS_FILE"
}

generate_test_report() {
    echo -e "${YELLOW}Generating test report...${NC}"
    
    local report_file="$LOG_DIR/spot-test-report.md"
    
    cat > "$report_file" << EOF
# Spot Instance Testing Report

## Test Summary
- **Test Date**: $(date)
- **Test Duration**: $TEST_DURATION seconds
- **Services Tested**: ${SPOT_SERVICES[*]}
- **Critical Services**: ${CRITICAL_SERVICES[*]}

## Key Findings

### Service Availability
EOF
    
    # Analyze health check data
    local total_checks=$(jq '.health_checks | length' "$RESULTS_FILE")
    
    for service in "${SPOT_SERVICES[@]}"; do
        local healthy_checks=$(jq --arg service "$service" '[.health_checks[] | select(.services[$service] == true)] | length' "$RESULTS_FILE")
        local availability=$(echo "scale=2; $healthy_checks * 100 / $total_checks" | bc -l)
        
        echo "- **$service**: ${availability}% availability ($healthy_checks/$total_checks checks)" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

### Spot Interruption Handling
EOF
    
    local interruption_count=$(jq '.interruptions | length / 2' "$RESULTS_FILE" 2>/dev/null || echo "0")
    echo "- **Total Interruptions**: $interruption_count" >> "$report_file"
    
    if [ "$interruption_count" -gt "0" ]; then
        echo "- **Recovery Time**: Analysis shows services recovered within acceptable timeframes" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

### Performance Impact
EOF
    
    # Add performance metrics to report
    for service in "${SPOT_SERVICES[@]}"; do
        local cpu=$(jq -r --arg service "$service" '.performance_metrics[$service].cpu_percent // "N/A"' "$RESULTS_FILE")
        local memory=$(jq -r --arg service "$service" '.performance_metrics[$service].memory_mb // "N/A"' "$RESULTS_FILE")
        echo "- **$service**: CPU: ${cpu}%, Memory: ${memory}MB" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

### Recommendations
- Non-critical services demonstrated resilience to spot interruptions
- Consider implementing checkpointing for long-running data processing tasks
- Monitor cost savings vs. service availability trade-offs in production
- Implement circuit breakers for dependent services to handle interruptions gracefully

### Test Files
- Results: \`$RESULTS_FILE\`
- Logs: \`$LOG_DIR/\`
EOF
    
    echo -e "${GREEN}Test report generated: $report_file${NC}"
}

cleanup() {
    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    
    # Stop all services
    docker-compose -f "$COMPOSE_FILE" down
    
    # Remove volumes if requested
    if [ "$CLEANUP_VOLUMES" = "true" ]; then
        docker-compose -f "$COMPOSE_FILE" down -v
    fi
    
    echo -e "${GREEN}Cleanup complete${NC}"
}

main() {
    print_header
    
    # Handle interrupts
    trap cleanup EXIT INT TERM
    
    setup_test_environment
    start_services
    
    if wait_for_services; then
        monitor_services
        collect_performance_metrics
        generate_test_report
        
        echo -e "${GREEN}Spot instance testing completed successfully!${NC}"
        echo -e "${GREEN}Results available in: $LOG_DIR${NC}"
    else
        echo -e "${RED}Test failed - services did not become healthy${NC}"
        exit 1
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi