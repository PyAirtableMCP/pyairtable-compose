#!/bin/bash

# PyAirtable Development Monitoring Script for Kubernetes/Minikube

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📊 PyAirtable Development Monitoring Dashboard${NC}"

# Check if kubectl is configured for minikube
if ! kubectl config current-context | grep -q "minikube"; then
    echo -e "${YELLOW}⚠️  Setting kubectl context to minikube${NC}"
    kubectl config use-context minikube
fi

# Check if namespace exists
if ! kubectl get namespace pyairtable >/dev/null 2>&1; then
    echo -e "${RED}❌ Namespace 'pyairtable' not found. Is the application deployed?${NC}"
    exit 1
fi

# Function to show status
show_status() {
    echo -e "\n${BLUE}=== PODS STATUS ===${NC}"
    kubectl get pods -n pyairtable -o wide
    
    echo -e "\n${BLUE}=== SERVICES STATUS ===${NC}"
    kubectl get services -n pyairtable
    
    echo -e "\n${BLUE}=== PERSISTENT VOLUMES ===${NC}"
    kubectl get pvc -n pyairtable
    
    echo -e "\n${BLUE}=== INGRESS STATUS ===${NC}"
    kubectl get ingress -n pyairtable || echo "No ingress resources found"
    
    echo -e "\n${BLUE}=== DEPLOYMENT STATUS ===${NC}"
    kubectl get deployments -n pyairtable
    
    echo -e "\n${BLUE}=== RESOURCE USAGE ===${NC}"
    kubectl top pods -n pyairtable 2>/dev/null || echo "Metrics server not available"
}

# Function to show logs
show_logs() {
    echo -e "\n${BLUE}=== RECENT LOGS ===${NC}"
    echo -e "${YELLOW}Choose a service to view logs:${NC}"
    
    services=$(kubectl get deployments -n pyairtable -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | sed 's/pyairtable-dev-//')
    
    select service in $services "All services" "Back to main menu"; do
        case $service in
            "All services")
                for svc in $services; do
                    echo -e "\n${BLUE}--- Logs for $svc ---${NC}"
                    kubectl logs --tail=20 -n pyairtable deployment/pyairtable-dev-$svc
                done
                break
                ;;
            "Back to main menu")
                break
                ;;
            *)
                if [[ -n $service ]]; then
                    echo -e "\n${BLUE}--- Recent logs for $service ---${NC}"
                    kubectl logs --tail=50 -n pyairtable deployment/pyairtable-dev-$service
                    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
                    read
                fi
                break
                ;;
        esac
    done
}

# Function to port forward
setup_port_forward() {
    echo -e "\n${BLUE}=== PORT FORWARDING SETUP ===${NC}"
    echo -e "${YELLOW}Available services:${NC}"
    echo "1. Frontend (3000)"
    echo "2. API Gateway (8000)" 
    echo "3. LLM Orchestrator (8003)"
    echo "4. MCP Server (8001)"
    echo "5. Airtable Gateway (8002)"
    echo "6. Platform Services (8007)"
    echo "7. Automation Services (8006)"
    echo "8. All main services (Frontend + API Gateway)"
    echo "9. Back to main menu"
    
    read -p "Choose service to port forward (1-9): " choice
    
    case $choice in
        1)
            echo -e "${BLUE}🚀 Port forwarding Frontend to localhost:3000${NC}"
            kubectl port-forward -n pyairtable service/frontend 3000:3000
            ;;
        2)
            echo -e "${BLUE}🚀 Port forwarding API Gateway to localhost:8000${NC}"
            kubectl port-forward -n pyairtable service/api-gateway 8000:8000
            ;;
        3)
            echo -e "${BLUE}🚀 Port forwarding LLM Orchestrator to localhost:8003${NC}"
            kubectl port-forward -n pyairtable service/llm-orchestrator 8003:8003
            ;;
        4)
            echo -e "${BLUE}🚀 Port forwarding MCP Server to localhost:8001${NC}"
            kubectl port-forward -n pyairtable service/mcp-server 8001:8001
            ;;
        5)
            echo -e "${BLUE}🚀 Port forwarding Airtable Gateway to localhost:8002${NC}"
            kubectl port-forward -n pyairtable service/airtable-gateway 8002:8002
            ;;
        6)
            echo -e "${BLUE}🚀 Port forwarding Platform Services to localhost:8007${NC}"
            kubectl port-forward -n pyairtable service/platform-services 8007:8007
            ;;
        7)
            echo -e "${BLUE}🚀 Port forwarding Automation Services to localhost:8006${NC}"
            kubectl port-forward -n pyairtable service/automation-services 8006:8006
            ;;
        8)
            echo -e "${BLUE}🚀 Port forwarding Frontend and API Gateway${NC}"
            kubectl port-forward -n pyairtable service/frontend 3000:3000 &
            kubectl port-forward -n pyairtable service/api-gateway 8000:8000 &
            echo -e "${GREEN}✅ Port forwarding started in background${NC}"
            echo -e "${YELLOW}Press Ctrl+C to stop port forwarding${NC}"
            wait
            ;;
        9)
            return
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            ;;
    esac
}

# Function to describe problematic pods
debug_issues() {
    echo -e "\n${BLUE}=== DEBUGGING ISSUES ===${NC}"
    
    # Find problematic pods
    problematic_pods=$(kubectl get pods -n pyairtable --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z $problematic_pods ]]; then
        echo -e "${GREEN}✅ All pods are running normally${NC}"
        return
    fi
    
    echo -e "${YELLOW}⚠️  Found problematic pods: $problematic_pods${NC}"
    
    for pod in $problematic_pods; do
        echo -e "\n${BLUE}--- Details for $pod ---${NC}"
        kubectl describe pod $pod -n pyairtable
        echo -e "\n${BLUE}--- Recent logs for $pod ---${NC}"
        kubectl logs --tail=30 $pod -n pyairtable || echo "No logs available"
    done
}

# Main menu
while true; do
    echo -e "\n${BLUE}=== PYAIRTABLE MONITORING MENU ===${NC}"
    echo "1. Show Status Overview"
    echo "2. View Logs"
    echo "3. Setup Port Forwarding"
    echo "4. Debug Issues"
    echo "5. Watch Pods (real-time)"
    echo "6. Open Kubernetes Dashboard"
    echo "7. Exit"
    
    read -p "Choose an option (1-7): " choice
    
    case $choice in
        1)
            show_status
            ;;
        2)
            show_logs
            ;;
        3)
            setup_port_forward
            ;;
        4)
            debug_issues
            ;;
        5)
            echo -e "${BLUE}📺 Watching pods in real-time (Press Ctrl+C to stop)${NC}"
            kubectl get pods -n pyairtable -w
            ;;
        6)
            echo -e "${BLUE}🌐 Opening Kubernetes Dashboard${NC}"
            minikube dashboard &
            ;;
        7)
            echo -e "${GREEN}👋 Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Invalid choice. Please select 1-7${NC}"
            ;;
    esac
    
    if [[ $choice != 5 && $choice != 6 ]]; then
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
    fi
done