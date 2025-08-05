#!/bin/bash

# PyAirtable LGTM Stack Dashboard Validation Script
# Tests dashboard JSON validity and LGTM compatibility

set -euo pipefail

DASHBOARD_DIR="/Users/kg/IdeaProjects/pyairtable-compose/monitoring/lgtm-stack/grafana/dashboards"
GRAFANA_URL="http://localhost:3001"
ERRORS=0

echo "🚀 PyAirtable Dashboard Validation Script"
echo "========================================="

# Function to check JSON validity
check_json() {
    local file="$1"
    if ! jq empty "$file" 2>/dev/null; then
        echo "❌ Invalid JSON: $file"
        ((ERRORS++))
        return 1
    else
        echo "✅ Valid JSON: $file"
        return 0
    fi
}

# Function to validate dashboard structure
validate_dashboard() {
    local file="$1"
    local filename=$(basename "$file")
    
    echo "📊 Validating dashboard: $filename"
    
    # Check required fields
    local title=$(jq -r '.title // "null"' "$file")
    local uid=$(jq -r '.uid // "null"' "$file")
    local tags=$(jq -r '.tags // [] | length' "$file")
    
    if [[ "$title" == "null" ]]; then
        echo "❌ Missing title in $filename"
        ((ERRORS++))
    else
        echo "   📝 Title: $title"
    fi
    
    if [[ "$uid" == "null" ]]; then
        echo "❌ Missing UID in $filename"
        ((ERRORS++))
    else
        echo "   🔗 UID: $uid"
    fi
    
    if [[ "$tags" == "0" ]]; then
        echo "⚠️  No tags in $filename"
    else
        echo "   🏷️  Tags: $tags"
    fi
    
    # Check for LGTM datasource references
    local mimir_refs=$(jq '[.panels[]?.targets[]?.datasource? | select(.uid == "mimir")] | length' "$file")
    local loki_refs=$(jq '[.panels[]?.targets[]?.datasource? | select(.uid == "loki")] | length' "$file")
    local tempo_refs=$(jq '[.panels[]?.targets[]?.datasource? | select(.uid == "tempo")] | length' "$file")
    
    echo "   📈 Datasource references:"
    echo "      - Mimir: $mimir_refs"
    echo "      - Loki: $loki_refs" 
    echo "      - Tempo: $tempo_refs"
    
    if [[ "$mimir_refs" == "0" ]]; then
        echo "⚠️  No Mimir datasource references in $filename"
    fi
    
    # Check panel count
    local panel_count=$(jq '.panels | length' "$file")
    echo "   📊 Panel count: $panel_count"
    
    if [[ "$panel_count" == "0" ]]; then
        echo "❌ No panels in $filename"
        ((ERRORS++))
    fi
    
    echo ""
}

# Function to check Grafana API connectivity
check_grafana_api() {
    echo "🔍 Checking Grafana API connectivity..."
    
    if curl -s -f "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
        echo "✅ Grafana API is accessible at $GRAFANA_URL"
        
        # Check datasources
        echo "📊 Checking configured datasources..."
        local datasources=$(curl -s "$GRAFANA_URL/api/datasources" 2>/dev/null || echo "[]")
        
        local mimir_count=$(echo "$datasources" | jq '[.[] | select(.type == "prometheus" and (.name | contains("Mimir")))] | length' 2>/dev/null || echo "0")
        local loki_count=$(echo "$datasources" | jq '[.[] | select(.type == "loki")] | length' 2>/dev/null || echo "0")
        local tempo_count=$(echo "$datasources" | jq '[.[] | select(.type == "tempo")] | length' 2>/dev/null || echo "0")
        
        echo "   - Mimir/Prometheus: $mimir_count"
        echo "   - Loki: $loki_count"
        echo "   - Tempo: $tempo_count"
        
        if [[ "$mimir_count" == "0" ]]; then
            echo "⚠️  No Mimir/Prometheus datasource configured"
        fi
        
    else
        echo "⚠️  Grafana API not accessible at $GRAFANA_URL"
        echo "   Make sure LGTM stack is running: docker-compose -f docker-compose.lgtm.yml up -d"
    fi
    echo ""
}

# Function to validate metric queries
validate_queries() {
    local file="$1"
    local filename=$(basename "$file")
    
    echo "🔍 Validating queries in: $filename"
    
    # Extract all prometheus queries
    local queries=$(jq -r '.panels[]?.targets[]?.expr // empty' "$file" 2>/dev/null || echo "")
    
    if [[ -z "$queries" ]]; then
        echo "⚠️  No Prometheus queries found"
        return
    fi
    
    local query_count=0
    while IFS= read -r query; do
        if [[ -n "$query" ]]; then
            ((query_count++))
            # Basic query validation
            if [[ "$query" =~ ^[a-zA-Z_][a-zA-Z0-9_]*\{ ]]; then
                echo "   ✅ Query $query_count: $(echo "$query" | cut -c1-50)..."
            elif [[ "$query" =~ ^(rate|histogram_quantile|sum|avg|max|min) ]]; then
                echo "   ✅ Query $query_count: $(echo "$query" | cut -c1-50)..."
            else
                echo "   ⚠️  Query $query_count may be invalid: $(echo "$query" | cut -c1-50)..."
            fi
        fi
    done <<< "$queries"
    
    echo "   📊 Total queries: $query_count"
    echo ""
}

# Main validation
echo "📁 Dashboard directory: $DASHBOARD_DIR"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "❌ jq is required but not installed. Please install jq first."
    exit 1
fi

# Check Grafana connectivity
check_grafana_api

echo "🔍 Validating dashboard files..."
echo ""

# Find and validate all dashboard JSON files
if [[ -d "$DASHBOARD_DIR" ]]; then
    while IFS= read -r -d '' file; do
        if check_json "$file"; then
            validate_dashboard "$file"
            validate_queries "$file"
        fi
    done < <(find "$DASHBOARD_DIR" -name "*.json" -type f -print0)
else
    echo "❌ Dashboard directory not found: $DASHBOARD_DIR"
    ((ERRORS++))
fi

# Summary
echo "📋 Validation Summary"
echo "===================="

if [[ $ERRORS -eq 0 ]]; then
    echo "✅ All validations passed! Dashboards are ready for deployment."
    echo ""
    echo "🚀 Next steps:"
    echo "1. Start LGTM stack: docker-compose -f docker-compose.lgtm.yml up -d"
    echo "2. Access Grafana: $GRAFANA_URL (admin/admin123)"
    echo "3. Dashboards will be auto-provisioned in their respective folders"
    echo "4. Configure alerting rules if needed"
    echo ""
    exit 0
else
    echo "❌ Found $ERRORS validation errors. Please fix before deployment."
    echo ""
    exit 1
fi