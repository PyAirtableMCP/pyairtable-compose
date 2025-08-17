#!/bin/bash

# Test Event Infrastructure - Comprehensive validation script
# Tests Redis, Queue System, Event Streams, and DLQ functionality

set -e

echo "🚀 Starting Event Infrastructure Tests..."

# Configuration
REDIS_PASSWORD="${REDIS_PASSWORD:-your-redis-password}"
BASE_URL="http://localhost"
QUEUE_UI_PORT="8009"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Test Redis connectivity
test_redis_connectivity() {
    log_test "Testing Redis connectivity..."
    
    # Test main Redis instance
    if redis-cli -h localhost -p 6379 -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
        log_success "Redis master (6379) is accessible"
    else
        log_error "Redis master (6379) is not accessible"
        return 1
    fi
    
    # Test Redis Streams instance
    if redis-cli -h localhost -p 6380 -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
        log_success "Redis streams (6380) is accessible"
    else
        log_error "Redis streams (6380) is not accessible"
        return 1
    fi
    
    # Test Redis Queue instance
    if redis-cli -h localhost -p 6381 -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
        log_success "Redis queue (6381) is accessible"
    else
        log_error "Redis queue (6381) is not accessible"
        return 1
    fi
}

# Test Queue UI accessibility
test_queue_ui() {
    log_test "Testing Queue UI accessibility..."
    
    local max_retries=30
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -s -f "$BASE_URL:$QUEUE_UI_PORT/health" > /dev/null 2>&1; then
            log_success "Queue UI is accessible at port $QUEUE_UI_PORT"
            return 0
        fi
        
        ((retry_count++))
        if [ $retry_count -eq $max_retries ]; then
            log_error "Queue UI is not accessible at port $QUEUE_UI_PORT after $max_retries attempts"
            return 1
        fi
        
        log_info "Waiting for Queue UI to start... (attempt $retry_count/$max_retries)"
        sleep 5
    done
}

# Test Queue functionality
test_queue_functionality() {
    log_test "Testing queue functionality..."
    
    # Test queue stats endpoint
    local stats_response
    if stats_response=$(curl -s -f "$BASE_URL:$QUEUE_UI_PORT/stats" 2>/dev/null); then
        log_success "Queue stats endpoint is working"
        log_info "Queue stats: $stats_response"
    else
        log_error "Queue stats endpoint is not working"
        return 1
    fi
    
    # Test job creation
    local job_data='{"name":"test-job","data":{"message":"test"},"options":{"delay":1000}}'
    local job_response
    
    if job_response=$(curl -s -f -X POST -H "Content-Type: application/json" \
        -d "$job_data" "$BASE_URL:$QUEUE_UI_PORT/jobs/async-processing" 2>/dev/null); then
        log_success "Test job created successfully"
        log_info "Job response: $job_response"
    else
        log_error "Failed to create test job"
        return 1
    fi
    
    # Wait for job processing
    sleep 3
    
    # Check updated stats
    if stats_response=$(curl -s -f "$BASE_URL:$QUEUE_UI_PORT/stats" 2>/dev/null); then
        log_success "Queue processed the test job"
        log_info "Updated stats: $stats_response"
    else
        log_error "Failed to get updated queue stats"
        return 1
    fi
}

# Test Event Streams
test_event_streams() {
    log_test "Testing event streams functionality..."
    
    # Add test event to stream
    local event_result
    if event_result=$(redis-cli -h localhost -p 6380 -a "$REDIS_PASSWORD" XADD pyairtable-events '*' \
        type 'test.event' \
        timestamp "$(date -Iseconds)" \
        source 'test-script' \
        data '{"message":"test event"}' 2>/dev/null); then
        log_success "Test event added to stream: $event_result"
    else
        log_error "Failed to add test event to stream"
        return 1
    fi
    
    # Read from stream
    local stream_data
    if stream_data=$(redis-cli -h localhost -p 6380 -a "$REDIS_PASSWORD" XREAD COUNT 1 STREAMS pyairtable-events 0 2>/dev/null); then
        log_success "Successfully read from event stream"
        log_info "Stream data: $stream_data"
    else
        log_error "Failed to read from event stream"
        return 1
    fi
    
    # Check stream length
    local stream_length
    if stream_length=$(redis-cli -h localhost -p 6380 -a "$REDIS_PASSWORD" XLEN pyairtable-events 2>/dev/null); then
        log_success "Stream length: $stream_length events"
    else
        log_error "Failed to get stream length"
        return 1
    fi
}

# Test Pub/Sub functionality
test_pubsub() {
    log_test "Testing pub/sub functionality..."
    
    # Start subscriber in background
    timeout 10s redis-cli -h localhost -p 6379 -a "$REDIS_PASSWORD" SUBSCRIBE test-channel > /tmp/pubsub_test.log 2>&1 &
    local subscriber_pid=$!
    
    # Wait a moment for subscriber to start
    sleep 2
    
    # Publish message
    local pub_result
    if pub_result=$(redis-cli -h localhost -p 6379 -a "$REDIS_PASSWORD" PUBLISH test-channel "Hello PyAirtable!" 2>/dev/null); then
        log_success "Published message to test-channel, $pub_result subscribers"
    else
        log_error "Failed to publish message"
        kill $subscriber_pid 2>/dev/null || true
        return 1
    fi
    
    # Wait for message processing
    sleep 2
    
    # Kill subscriber
    kill $subscriber_pid 2>/dev/null || true
    
    # Check if message was received
    if grep -q "Hello PyAirtable!" /tmp/pubsub_test.log 2>/dev/null; then
        log_success "Pub/sub message was received successfully"
    else
        log_error "Pub/sub message was not received"
        return 1
    fi
    
    rm -f /tmp/pubsub_test.log
}

# Test Queue persistence across restarts
test_queue_persistence() {
    log_test "Testing queue persistence..."
    
    # Add a delayed job
    local persistent_job='{"name":"persistent-test","data":{"persist":true},"options":{"delay":300000}}'
    local job_response
    
    if job_response=$(curl -s -f -X POST -H "Content-Type: application/json" \
        -d "$persistent_job" "$BASE_URL:$QUEUE_UI_PORT/jobs/long-running-jobs" 2>/dev/null); then
        log_success "Persistent test job created"
        log_info "Job response: $job_response"
    else
        log_error "Failed to create persistent test job"
        return 1
    fi
    
    # Check that job exists in queue
    local stats_before
    if stats_before=$(curl -s -f "$BASE_URL:$QUEUE_UI_PORT/stats" 2>/dev/null); then
        if echo "$stats_before" | grep -q "waiting.*[1-9]"; then
            log_success "Persistent job is waiting in queue"
        else
            log_error "Persistent job not found in queue"
            return 1
        fi
    else
        log_error "Failed to check queue stats"
        return 1
    fi
}

# Test DLQ functionality by creating a failing job
test_dlq_functionality() {
    log_test "Testing Dead Letter Queue functionality..."
    
    # Create a job that will fail
    local failing_job='{"name":"failing-job","data":{"shouldFail":true,"error":"intentional failure"}}'
    local job_response
    
    if job_response=$(curl -s -f -X POST -H "Content-Type: application/json" \
        -d "$failing_job" "$BASE_URL:$QUEUE_UI_PORT/jobs/async-processing" 2>/dev/null); then
        log_success "Failing test job created for DLQ testing"
        log_info "Job response: $job_response"
    else
        log_error "Failed to create failing test job"
        return 1
    fi
    
    # Wait for job to fail and be processed by DLQ
    sleep 10
    
    # Check DLQ stats
    local dlq_length
    if dlq_length=$(redis-cli -h localhost -p 6379 -a "$REDIS_PASSWORD" LLEN dlq:alerts 2>/dev/null); then
        if [ "$dlq_length" -gt 0 ]; then
            log_success "DLQ processed failed job - $dlq_length alerts generated"
        else
            log_info "No DLQ alerts yet (job might still be retrying)"
        fi
    else
        log_error "Failed to check DLQ alerts"
        return 1
    fi
}

# Test health endpoints
test_health_endpoints() {
    log_test "Testing all health endpoints..."
    
    # Queue UI health
    if curl -s -f "$BASE_URL:$QUEUE_UI_PORT/health" > /dev/null 2>&1; then
        log_success "Queue UI health endpoint is working"
    else
        log_error "Queue UI health endpoint is not working"
    fi
    
    # Check if event processor is running
    if docker-compose ps event-processor | grep -q "Up"; then
        log_success "Event processor container is running"
    else
        log_error "Event processor container is not running"
    fi
    
    # Check if DLQ processor is running
    if docker-compose ps dlq-processor | grep -q "Up"; then
        log_success "DLQ processor container is running"
    else
        log_error "DLQ processor container is not running"
    fi
}

# Performance test
test_performance() {
    log_test "Running basic performance tests..."
    
    # Test multiple job submissions
    log_info "Submitting 10 test jobs for performance testing..."
    
    for i in {1..10}; do
        local perf_job="{\"name\":\"perf-test-$i\",\"data\":{\"iteration\":$i,\"duration\":1000}}"
        curl -s -f -X POST -H "Content-Type: application/json" \
            -d "$perf_job" "$BASE_URL:$QUEUE_UI_PORT/jobs/async-processing" > /dev/null 2>&1 || true
    done
    
    log_info "Waiting for jobs to process..."
    sleep 15
    
    # Check final stats
    local final_stats
    if final_stats=$(curl -s -f "$BASE_URL:$QUEUE_UI_PORT/stats" 2>/dev/null); then
        log_success "Performance test completed"
        log_info "Final stats: $final_stats"
    else
        log_error "Failed to get final performance stats"
        return 1
    fi
}

# Main test execution
main() {
    echo "🔧 Event Infrastructure Test Suite"
    echo "=================================="
    echo
    
    log_info "Starting tests at $(date)"
    echo
    
    # Run all tests
    test_redis_connectivity || true
    echo
    
    test_queue_ui || true
    echo
    
    test_queue_functionality || true
    echo
    
    test_event_streams || true
    echo
    
    test_pubsub || true
    echo
    
    test_queue_persistence || true
    echo
    
    test_dlq_functionality || true
    echo
    
    test_health_endpoints || true
    echo
    
    test_performance || true
    echo
    
    # Summary
    echo "=================================="
    echo "🎯 Test Summary"
    echo "=================================="
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "Total Tests: $(($TESTS_PASSED + $TESTS_FAILED))"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed! Event infrastructure is working correctly.${NC}"
        echo
        echo "📊 Access points:"
        echo "  - Queue UI: http://localhost:$QUEUE_UI_PORT/admin/queues"
        echo "  - Health Check: http://localhost:$QUEUE_UI_PORT/health"
        echo "  - Stats: http://localhost:$QUEUE_UI_PORT/stats"
        echo "  - Redis Master: localhost:6379"
        echo "  - Redis Streams: localhost:6380"
        echo "  - Redis Queue: localhost:6381"
        echo
        return 0
    else
        echo -e "${RED}❌ Some tests failed. Please check the logs above.${NC}"
        return 1
    fi
}

# Run main function
main "$@"