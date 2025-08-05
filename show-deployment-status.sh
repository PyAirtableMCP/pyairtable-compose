#!/bin/bash

# PyAirtable Deployment Status Dashboard
# Quick overview of current deployment state

set -e

# Color codes
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

echo -e "${CYAN}"
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║  🚀 PyAirtable Multi-Repository Deployment Status                           ║
║                                                                              ║
║  📊 Real-time status of your local development environment                  ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# Check if minikube is running
echo -e "${WHITE}☸️  Minikube Cluster Status${NC}"
echo "================================"

if minikube status -p pyairtable-dev &> /dev/null; then
    echo -e "  ✅ Cluster: ${GREEN}Running${NC} (pyairtable-dev)"
    
    # Get cluster info
    MINIKUBE_IP=$(minikube ip -p pyairtable-dev 2>/dev/null || echo "unknown")
    echo -e "  🌐 IP Address: ${MINIKUBE_IP}"
    
    # Check kubectl context
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
    if [[ "$CURRENT_CONTEXT" == "pyairtable-dev" ]]; then
        echo -e "  ✅ Context: ${GREEN}pyairtable-dev${NC}"
    else
        echo -e "  ⚠️  Context: ${YELLOW}${CURRENT_CONTEXT}${NC} (should be pyairtable-dev)"
    fi
else
    echo -e "  ❌ Cluster: ${RED}Not Running${NC}"
    echo -e "  💡 Start with: ${CYAN}./minikube-dev-setup.sh${NC}"
    exit 1
fi

echo ""

# Check namespace and pods
echo -e "${WHITE}🔍 Pod Status${NC}"
echo "================"

if kubectl get namespace pyairtable-dev &> /dev/null; then
    echo -e "  ✅ Namespace: ${GREEN}pyairtable-dev exists${NC}"
    
    # Get pod status
    echo ""
    echo -e "${BLUE}Service Pods:${NC}"
    
    PODS=$(kubectl get pods -n pyairtable-dev --no-headers 2>/dev/null || echo "")
    
    if [[ -n "$PODS" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                POD_NAME=$(echo "$line" | awk '{print $1}')
                READY=$(echo "$line" | awk '{print $2}')
                STATUS=$(echo "$line" | awk '{print $3}')
                
                # Determine status emoji
                if [[ "$STATUS" == "Running" ]] && [[ "$READY" == "1/1" ]]; then
                    STATUS_EMOJI="✅"
                    COLOR="$GREEN"
                elif [[ "$STATUS" == "Running" ]]; then
                    STATUS_EMOJI="⚠️"
                    COLOR="$YELLOW"
                else
                    STATUS_EMOJI="❌"
                    COLOR="$RED"
                fi
                
                echo -e "  ${STATUS_EMOJI} ${POD_NAME}: ${COLOR}${STATUS}${NC} (${READY})"
            fi
        done <<< "$PODS"
    else
        echo -e "  ❌ No pods found in namespace"
    fi
else
    echo -e "  ❌ Namespace: ${RED}pyairtable-dev not found${NC}"
fi

echo ""

# Check services
echo -e "${WHITE}🌐 Service Status${NC}"
echo "=================="

SERVICES=$(kubectl get services -n pyairtable-dev --no-headers 2>/dev/null || echo "")

if [[ -n "$SERVICES" ]]; then
    while IFS= read -r line; do
        if [[ -n "$line" ]] && [[ ! "$line" =~ "external" ]]; then
            SERVICE_NAME=$(echo "$line" | awk '{print $1}')
            SERVICE_TYPE=$(echo "$line" | awk '{print $2}')
            CLUSTER_IP=$(echo "$line" | awk '{print $3}')
            PORT=$(echo "$line" | awk '{print $5}' | cut -d'/' -f1)
            
            echo -e "  🔗 ${SERVICE_NAME}: ${BLUE}${CLUSTER_IP}:${PORT}${NC} (${SERVICE_TYPE})"
        fi
    done <<< "$SERVICES"
else
    echo -e "  ❌ No services found"
fi

echo ""

# Check external API connectivity
echo -e "${WHITE}🔑 API Connectivity${NC}"
echo "==================="

# Check .env file
if [[ -f ".env" ]]; then
    source .env
    
    # Check Airtable token
    if [[ -n "$AIRTABLE_TOKEN" ]] && [[ ${#AIRTABLE_TOKEN} -gt 10 ]]; then
        echo -e "  ✅ Airtable Token: ${GREEN}Configured${NC} (${#AIRTABLE_TOKEN} chars)"
    else
        echo -e "  ❌ Airtable Token: ${RED}Missing or invalid${NC}"
    fi
    
    # Check Gemini API key
    if [[ -n "$GEMINI_API_KEY" ]] && [[ ${#GEMINI_API_KEY} -gt 10 ]]; then
        echo -e "  ✅ Gemini API Key: ${GREEN}Configured${NC} (${#GEMINI_API_KEY} chars)"
    else
        echo -e "  ❌ Gemini API Key: ${RED}Missing or invalid${NC}"
    fi
    
    # Check Airtable Base
    if [[ -n "$AIRTABLE_BASE" ]] && [[ "$AIRTABLE_BASE" =~ ^app[a-zA-Z0-9]+$ ]]; then
        echo -e "  ✅ Airtable Base: ${GREEN}${AIRTABLE_BASE}${NC}"
    else
        echo -e "  ❌ Airtable Base: ${RED}Missing or invalid${NC}"
    fi
else
    echo -e "  ❌ .env file: ${RED}Not found${NC}"
fi

echo ""

# Quick actions
echo -e "${WHITE}🛠️  Quick Actions${NC}"
echo "================="
echo -e "  📊 Health Check:      ${CYAN}python deployment_validation_test.py${NC}"
echo -e "  🔗 API Test:          ${CYAN}python api_connectivity_test.py${NC}"
echo -e "  🔧 Port Forward:      ${CYAN}source dev-access.sh && forward_all${NC}"
echo -e "  📋 View Logs:         ${CYAN}kubectl logs -n pyairtable-dev deployment/<service>${NC}"
echo -e "  🔄 Restart Service:   ${CYAN}kubectl rollout restart deployment/<service> -n pyairtable-dev${NC}"
echo -e "  🧹 Clean & Restart:   ${CYAN}./minikube-dev-setup.sh clean${NC}"

echo ""

# Resource usage
echo -e "${WHITE}📈 Resource Usage${NC}"
echo "=================="

# Try to get resource usage
if kubectl top nodes &> /dev/null; then
    NODE_USAGE=$(kubectl top nodes --no-headers 2>/dev/null | head -1)
    if [[ -n "$NODE_USAGE" ]]; then
        CPU_USAGE=$(echo "$NODE_USAGE" | awk '{print $2}')
        MEM_USAGE=$(echo "$NODE_USAGE" | awk '{print $3}')
        echo -e "  💻 CPU Usage: ${BLUE}${CPU_USAGE}${NC}"
        echo -e "  🧠 Memory Usage: ${BLUE}${MEM_USAGE}${NC}"
    fi
    
    # Pod resource usage
    POD_USAGE=$(kubectl top pods -n pyairtable-dev --no-headers 2>/dev/null | head -5)
    if [[ -n "$POD_USAGE" ]]; then
        echo -e "\n  ${BLUE}Top Pod Usage:${NC}"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                POD_NAME=$(echo "$line" | awk '{print $1}' | cut -c1-20)
                CPU=$(echo "$line" | awk '{print $2}')
                MEM=$(echo "$line" | awk '{print $3}')
                echo -e "    ${POD_NAME}: CPU ${CPU}, Memory ${MEM}"
            fi
        done <<< "$POD_USAGE"
    fi
else
    echo -e "  ⚠️  Metrics server not ready yet"
fi

echo ""

# Final status
echo -e "${WHITE}🎯 Overall Status${NC}"
echo "=================="

# Count healthy pods
HEALTHY_PODS=0
TOTAL_PODS=0

if [[ -n "$PODS" ]]; then
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            TOTAL_PODS=$((TOTAL_PODS + 1))
            READY=$(echo "$line" | awk '{print $2}')
            STATUS=$(echo "$line" | awk '{print $3}')
            
            if [[ "$STATUS" == "Running" ]] && [[ "$READY" == "1/1" ]]; then
                HEALTHY_PODS=$((HEALTHY_PODS + 1))
            fi
        fi
    done <<< "$PODS"
fi

if [[ $TOTAL_PODS -gt 0 ]]; then
    SUCCESS_RATE=$(( (HEALTHY_PODS * 100) / TOTAL_PODS ))
    
    if [[ $SUCCESS_RATE -eq 100 ]]; then
        echo -e "  🎉 Status: ${GREEN}ALL SYSTEMS OPERATIONAL${NC}"
        echo -e "  📊 Success Rate: ${GREEN}${SUCCESS_RATE}%${NC} (${HEALTHY_PODS}/${TOTAL_PODS} pods healthy)"
        echo -e "  ✨ Ready for development!"
    elif [[ $SUCCESS_RATE -ge 80 ]]; then
        echo -e "  ⚠️  Status: ${YELLOW}MOSTLY OPERATIONAL${NC}"
        echo -e "  📊 Success Rate: ${YELLOW}${SUCCESS_RATE}%${NC} (${HEALTHY_PODS}/${TOTAL_PODS} pods healthy)"
        echo -e "  🔧 Some services may need attention"
    else
        echo -e "  ❌ Status: ${RED}NEEDS ATTENTION${NC}"
        echo -e "  📊 Success Rate: ${RED}${SUCCESS_RATE}%${NC} (${HEALTHY_PODS}/${TOTAL_PODS} pods healthy)"
        echo -e "  🚨 Multiple services require fixing"
    fi
else
    echo -e "  ❌ Status: ${RED}NO SERVICES RUNNING${NC}"
    echo -e "  💡 Run: ${CYAN}./minikube-dev-setup.sh${NC}"
fi

echo ""
echo -e "${CYAN}📄 Full report available in: COMPREHENSIVE_DEPLOYMENT_VALIDATION_REPORT.md${NC}"
echo ""