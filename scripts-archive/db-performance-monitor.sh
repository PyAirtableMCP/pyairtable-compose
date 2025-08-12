#!/bin/bash
# Database Performance Monitor for PyAirtable
# Created: 2025-08-11
# Purpose: Monitor and report on database performance metrics

set -euo pipefail

# Configuration
DB_HOST=${POSTGRES_HOST:-localhost}
DB_PORT=${POSTGRES_PORT:-5432}
DB_NAME=${POSTGRES_DB:-pyairtable}
DB_USER=${POSTGRES_USER:-postgres}
DB_PASSWORD=${POSTGRES_PASSWORD}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Function to execute SQL and format output
execute_sql() {
    local query=$1
    local title=$2
    
    echo -e "\n${CYAN}$title${NC}"
    echo "----------------------------------------"
    
    if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$query" 2>/dev/null; then
        echo ""
        return 0
    else
        log_error "Failed to execute query: $title"
        return 1
    fi
}

# Function to show connection stats
show_connection_stats() {
    log_header "DATABASE CONNECTION STATISTICS"
    
    execute_sql "
        SELECT 
            count(*) as total_connections,
            count(*) FILTER (WHERE state = 'active') as active,
            count(*) FILTER (WHERE state = 'idle') as idle,
            count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction,
            count(*) FILTER (WHERE state = 'idle in transaction (aborted)') as idle_in_transaction_aborted
        FROM pg_stat_activity 
        WHERE datname = '$DB_NAME';
    " "Current Connection Summary"
    
    execute_sql "
        SELECT 
            usename as username,
            count(*) as connections,
            max(now() - backend_start) as max_connection_age
        FROM pg_stat_activity 
        WHERE datname = '$DB_NAME' AND state IS NOT NULL
        GROUP BY usename
        ORDER BY connections DESC;
    " "Connections by User"
}

# Function to show slow queries
show_slow_queries() {
    log_header "SLOW QUERY ANALYSIS"
    
    # Check if pg_stat_statements is available
    local has_pg_stat_statements=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements');
    " 2>/dev/null | xargs)
    
    if [ "$has_pg_stat_statements" = "t" ]; then
        execute_sql "
            SELECT 
                LEFT(query, 80) as query_snippet,
                calls,
                ROUND(mean_exec_time::NUMERIC, 2) as avg_time_ms,
                ROUND(total_exec_time::NUMERIC, 2) as total_time_ms,
                ROUND((100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0))::NUMERIC, 2) as cache_hit_ratio
            FROM pg_stat_statements
            WHERE mean_exec_time > 100
            ORDER BY mean_exec_time DESC
            LIMIT 10;
        " "Top 10 Slowest Queries (>100ms average)"
        
        execute_sql "
            SELECT 
                LEFT(query, 80) as query_snippet,
                calls,
                ROUND(mean_exec_time::NUMERIC, 2) as avg_time_ms,
                ROUND(total_exec_time::NUMERIC, 2) as total_time_ms
            FROM pg_stat_statements
            WHERE calls > 1000
            ORDER BY calls DESC
            LIMIT 10;
        " "Top 10 Most Frequent Queries (>1000 calls)"
    else
        log_warning "pg_stat_statements extension not available. Cannot show slow query analysis."
        log_info "To enable, add 'pg_stat_statements' to shared_preload_libraries and restart PostgreSQL."
    fi
}

# Function to show table statistics
show_table_stats() {
    log_header "TABLE STATISTICS"
    
    execute_sql "
        SELECT 
            schemaname,
            tablename,
            n_live_tup as live_rows,
            n_dead_tup as dead_rows,
            ROUND(100.0 * n_dead_tup / GREATEST(n_live_tup + n_dead_tup, 1), 2) as dead_ratio,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
            last_vacuum,
            last_autovacuum
        FROM pg_stat_user_tables
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
        LIMIT 15;
    " "Table Size and Vacuum Status"
    
    execute_sql "
        SELECT 
            schemaname,
            tablename,
            n_tup_ins as inserts,
            n_tup_upd as updates,
            n_tup_del as deletes,
            n_tup_ins + n_tup_upd + n_tup_del as total_changes
        FROM pg_stat_user_tables
        WHERE n_tup_ins + n_tup_upd + n_tup_del > 0
        ORDER BY total_changes DESC
        LIMIT 10;
    " "Tables with Most Activity"
}

# Function to show index usage
show_index_usage() {
    log_header "INDEX USAGE ANALYSIS"
    
    execute_sql "
        SELECT 
            schemaname,
            tablename,
            indexname,
            idx_scan as scans,
            idx_tup_read as tuples_read,
            idx_tup_fetch as tuples_fetched,
            pg_size_pretty(pg_relation_size(indexrelid)) as index_size
        FROM pg_stat_user_indexes
        WHERE idx_scan > 100
        ORDER BY idx_scan DESC
        LIMIT 10;
    " "Most Used Indexes (>100 scans)"
    
    execute_sql "
        SELECT 
            schemaname,
            tablename,
            indexname,
            idx_scan as scans,
            pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
            CASE 
                WHEN idx_scan = 0 THEN 'NEVER USED - Consider dropping'
                WHEN idx_scan < 10 THEN 'RARELY USED - Review necessity'
                ELSE 'ACTIVELY USED'
            END as recommendation
        FROM pg_stat_user_indexes
        WHERE idx_scan < 100
        ORDER BY pg_relation_size(indexrelid) DESC
        LIMIT 10;
    " "Potentially Unused Indexes"
}

# Function to show cache performance
show_cache_performance() {
    log_header "CACHE PERFORMANCE"
    
    execute_sql "
        SELECT 
            ROUND(100.0 * sum(heap_blks_hit) / GREATEST(sum(heap_blks_hit) + sum(heap_blks_read), 1), 2) as table_cache_hit_ratio,
            ROUND(100.0 * sum(idx_blks_hit) / GREATEST(sum(idx_blks_hit) + sum(idx_blks_read), 1), 2) as index_cache_hit_ratio
        FROM pg_statio_user_tables;
    " "Overall Cache Hit Ratios (Target: >95%)"
    
    execute_sql "
        SELECT 
            schemaname,
            tablename,
            ROUND(100.0 * heap_blks_hit / GREATEST(heap_blks_hit + heap_blks_read, 1), 2) as table_hit_ratio,
            ROUND(100.0 * idx_blks_hit / GREATEST(idx_blks_hit + idx_blks_read, 1), 2) as index_hit_ratio,
            heap_blks_read + idx_blks_read as total_disk_reads
        FROM pg_statio_user_tables
        WHERE heap_blks_read + idx_blks_read > 0
        ORDER BY total_disk_reads DESC
        LIMIT 10;
    " "Tables with Most Disk Reads"
}

# Function to show lock information
show_lock_info() {
    log_header "LOCK ANALYSIS"
    
    execute_sql "
        SELECT 
            mode,
            count(*) as lock_count,
            granted
        FROM pg_locks 
        GROUP BY mode, granted
        ORDER BY lock_count DESC;
    " "Current Lock Summary"
    
    # Show any blocking locks
    local blocking_locks=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT count(*) FROM pg_locks WHERE NOT granted;
    " 2>/dev/null | xargs)
    
    if [ "$blocking_locks" -gt "0" ]; then
        log_warning "Found $blocking_locks blocking locks!"
        
        execute_sql "
            SELECT 
                l.locktype,
                l.relation::regclass,
                l.mode,
                l.granted,
                a.usename,
                LEFT(a.query, 50) as query_snippet,
                now() - a.query_start as query_duration
            FROM pg_locks l
            LEFT JOIN pg_stat_activity a ON l.pid = a.pid
            WHERE NOT l.granted
            ORDER BY query_duration DESC;
        " "Current Blocking Locks"
    else
        log_success "No blocking locks found"
    fi
}

# Function to show authentication-specific metrics
show_auth_metrics() {
    log_header "AUTHENTICATION & USER METRICS"
    
    # Check if our optimized tables exist
    local has_user_tables=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'users');
    " 2>/dev/null | xargs)
    
    if [ "$has_user_tables" = "t" ]; then
        execute_sql "
            SELECT 
                COUNT(*) as total_users,
                COUNT(*) FILTER (WHERE is_active = true) as active_users,
                COUNT(*) FILTER (WHERE last_login > CURRENT_TIMESTAMP - INTERVAL '24 hours') as recent_logins,
                COUNT(*) FILTER (WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '7 days') as new_users_week
            FROM users;
        " "User Statistics"
        
        execute_sql "
            SELECT 
                COUNT(*) as total_sessions,
                COUNT(*) FILTER (WHERE status = 'active') as active_sessions,
                COUNT(*) FILTER (WHERE last_activity > CURRENT_TIMESTAMP - INTERVAL '1 hour') as recent_activity
            FROM conversation_sessions;
        " "Session Statistics"
        
        execute_sql "
            SELECT 
                COUNT(*) as total_api_keys,
                COUNT(*) FILTER (WHERE is_active = true) as active_api_keys,
                COUNT(*) FILTER (WHERE last_used > CURRENT_TIMESTAMP - INTERVAL '24 hours') as recently_used
            FROM api_keys;
        " "API Key Statistics"
    else
        log_info "Optimized authentication tables not found. Run migrations first."
    fi
}

# Function to show recommendations
show_recommendations() {
    log_header "PERFORMANCE RECOMMENDATIONS"
    
    # Check if our monitoring functions exist
    local has_monitoring_functions=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT EXISTS(SELECT 1 FROM information_schema.routines WHERE routine_name = 'analyze_query_performance');
    " 2>/dev/null | xargs)
    
    if [ "$has_monitoring_functions" = "t" ]; then
        execute_sql "
            SELECT 
                query_snippet,
                avg_duration_ms,
                call_count,
                recommendation
            FROM analyze_query_performance()
            WHERE recommendation != 'OK: Performance acceptable'
            ORDER BY 
                CASE 
                    WHEN recommendation LIKE 'URGENT%' THEN 1
                    WHEN recommendation LIKE 'HIGH%' THEN 2
                    WHEN recommendation LIKE 'MEDIUM%' THEN 3
                    ELSE 4
                END,
                avg_duration_ms DESC
            LIMIT 10;
        " "Query Performance Recommendations"
        
        execute_sql "
            SELECT 
                table_name,
                current_size,
                current_rows,
                estimated_daily_growth_mb
            FROM get_table_growth_stats(30)
            WHERE estimated_daily_growth_mb > 1
            ORDER BY estimated_daily_growth_mb DESC
            LIMIT 10;
        " "Tables with High Growth (>1MB/day estimated)"
    else
        log_info "Performance monitoring functions not available. Run migration 003 first."
    fi
    
    # General recommendations based on statistics
    echo ""
    log_info "General Recommendations:"
    
    # Check cache hit ratio
    local cache_hit_ratio=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT ROUND(100.0 * sum(heap_blks_hit) / GREATEST(sum(heap_blks_hit) + sum(heap_blks_read), 1), 2)
        FROM pg_statio_user_tables;
    " 2>/dev/null | xargs)
    
    if (( $(echo "$cache_hit_ratio < 95" | bc -l) )); then
        echo "  ⚠️  Cache hit ratio is ${cache_hit_ratio}% (target: >95%). Consider increasing shared_buffers."
    else
        echo "  ✅ Cache hit ratio is good: ${cache_hit_ratio}%"
    fi
    
    # Check for tables needing vacuum
    local tables_needing_vacuum=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT count(*) FROM pg_stat_user_tables 
        WHERE n_dead_tup > 1000 AND (last_autovacuum IS NULL OR last_autovacuum < CURRENT_TIMESTAMP - INTERVAL '1 day');
    " 2>/dev/null | xargs)
    
    if [ "$tables_needing_vacuum" -gt "0" ]; then
        echo "  ⚠️  $tables_needing_vacuum tables may need vacuum. Check autovacuum settings."
    else
        echo "  ✅ Table maintenance appears up to date"
    fi
    
    echo ""
}

# Function to run cleanup
run_cleanup() {
    log_header "DATABASE CLEANUP"
    
    local has_cleanup_function=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT EXISTS(SELECT 1 FROM information_schema.routines WHERE routine_name = 'cleanup_expired_data');
    " 2>/dev/null | xargs)
    
    if [ "$has_cleanup_function" = "t" ]; then
        log_info "Running automated cleanup..."
        
        execute_sql "
            SELECT 
                table_name,
                rows_deleted,
                CASE 
                    WHEN rows_deleted > 0 THEN 'Cleaned up ' || rows_deleted || ' rows'
                    ELSE 'No cleanup needed'
                END as status
            FROM cleanup_expired_data();
        " "Cleanup Results"
        
        log_success "Cleanup completed"
    else
        log_info "Cleanup function not available. Run migration 003 first."
    fi
}

# Main function
main() {
    local action=${1:-"all"}
    
    case $action in
        "connections"|"conn")
            show_connection_stats
            ;;
        "slow"|"queries")
            show_slow_queries
            ;;
        "tables"|"table")
            show_table_stats
            ;;
        "indexes"|"index")
            show_index_usage
            ;;
        "cache")
            show_cache_performance
            ;;
        "locks"|"lock")
            show_lock_info
            ;;
        "auth")
            show_auth_metrics
            ;;
        "recommendations"|"recommend")
            show_recommendations
            ;;
        "cleanup")
            run_cleanup
            ;;
        "all"|*)
            log_info "PyAirtable Database Performance Monitor"
            log_info "Target: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
            log_info "Timestamp: $(date)"
            
            show_connection_stats
            show_slow_queries
            show_table_stats
            show_index_usage
            show_cache_performance
            show_lock_info
            show_auth_metrics
            show_recommendations
            
            echo ""
            log_info "Monitor completed. Run specific sections with:"
            echo "  $0 connections  - Connection statistics"
            echo "  $0 slow         - Slow query analysis"
            echo "  $0 tables       - Table statistics"
            echo "  $0 indexes      - Index usage"
            echo "  $0 cache        - Cache performance"
            echo "  $0 locks        - Lock analysis"
            echo "  $0 auth         - Authentication metrics"
            echo "  $0 recommend    - Performance recommendations"
            echo "  $0 cleanup      - Run database cleanup"
            ;;
    esac
}

# Check if bc is available for numeric comparisons
if ! command -v bc >/dev/null 2>&1; then
    log_warning "bc command not found. Some numeric comparisons may not work."
fi

# Execute main function
main "$@"