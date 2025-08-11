#!/bin/bash

# Emergency Stabilization Day 5: Monitoring System Demo
# Demonstrates the complete monitoring system functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🚀 PyAirtable Monitoring System Demo${NC}"
echo "=================================================="
echo ""

echo -e "${BLUE}1. Testing Health Check System${NC}"
echo "--------------------------------------------------"
python3 "$SCRIPT_DIR/health-check.py" --once
echo ""

echo -e "${BLUE}2. Current System Status${NC}"
echo "--------------------------------------------------"
python3 "$SCRIPT_DIR/test-monitoring.py" --status
echo ""

echo -e "${BLUE}3. Available Monitoring Commands${NC}"
echo "--------------------------------------------------"
echo -e "${GREEN}Start Complete Monitoring:${NC}"
echo "  ./scripts/start-monitoring.sh"
echo ""
echo -e "${GREEN}Individual Components:${NC}"
echo "  python3 scripts/health-check.py --continuous"
echo "  python3 scripts/monitor-dashboard.py"
echo "  python3 scripts/alert-manager.py --monitor"
echo ""
echo -e "${GREEN}Testing & Status:${NC}"
echo "  python3 scripts/test-monitoring.py --comprehensive"
echo "  python3 scripts/test-monitoring.py --status"
echo ""

echo -e "${BLUE}4. Monitoring URLs${NC}"
echo "--------------------------------------------------"
echo -e "${GREEN}Dashboard:${NC} http://localhost:9999"
echo -e "${GREEN}Health API:${NC} http://localhost:9999/health"
echo -e "${GREEN}WebSocket:${NC} ws://localhost:9999/ws"
echo ""

echo -e "${BLUE}5. Key Files${NC}"
echo "--------------------------------------------------"
echo -e "${GREEN}Health Data:${NC} /tmp/health-status.json"
echo -e "${GREEN}Alert Logs:${NC} /tmp/alerts.log"
echo -e "${GREEN}Process Logs:${NC} /tmp/monitoring-logs/"
echo ""

echo -e "${BLUE}6. Service Health Summary${NC}"
echo "--------------------------------------------------"
if [ -f "/tmp/health-status.json" ]; then
    python3 -c "
import json
try:
    with open('/tmp/health-status.json', 'r') as f:
        data = json.load(f)
    
    print(f\"✅ Total Services: {data.get('total_services', 0)}\")
    print(f\"✅ Healthy: {data.get('healthy_services', 0)}\")
    print(f\"⚠️  Degraded: {data.get('degraded_services', 0)}\")
    print(f\"❌ Failed: {data.get('failed_services', 0)}\")
    
    # Show healthy services
    healthy = [s for s in data.get('services', []) if s.get('status') == 'UP']
    if healthy:
        print(f\"\\n🟢 Healthy Services:\")
        for service in healthy:
            rt = service.get('response_time_ms', 0)
            print(f\"   • {service['name']} ({rt:.1f}ms)\")
    
    # Show failed services  
    failed = [s for s in data.get('services', []) if s.get('status') == 'DOWN']
    if failed:
        print(f\"\\n🔴 Failed Services:\")
        for service in failed:
            print(f\"   • {service['name']}\")
            
except Exception as e:
    print(f\"Error reading health data: {e}\")
"
else
    echo "No health data available - run health check first"
fi

echo ""
echo -e "${BLUE}7. Next Steps${NC}"
echo "--------------------------------------------------"
echo -e "${YELLOW}To start monitoring:${NC}"
echo "  1. ./scripts/start-monitoring.sh"
echo "  2. Open http://localhost:9999 in browser"
echo "  3. Monitor logs: tail -f /tmp/monitoring-logs/*.log"
echo ""

echo -e "${YELLOW}To troubleshoot failed services:${NC}"
echo "  1. Check if services are running: docker-compose ps"
echo "  2. Start services: docker-compose up -d"
echo "  3. Check service logs: docker-compose logs <service>"
echo ""

echo -e "${GREEN}✅ Monitoring System Ready!${NC}"
echo "Day 5 Emergency Stabilization: Complete visibility into system health"
echo ""