# PyAirtable Kubernetes Deployment Makefile
# Provides convenient commands for deployment and management

.PHONY: help deploy-all deploy-core deploy-monitoring deploy-istio \
        health-check e2e-test cleanup setup-minikube setup-kind \
        build-images port-forward logs status scale

# Default target
help: ## Show this help message
	@echo "PyAirtable Kubernetes Deployment Commands"
	@echo "=========================================="
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Deployment Commands

deploy-all: ## Deploy complete PyAirtable stack (core + monitoring + istio)
	@echo "🚀 Deploying complete PyAirtable stack..."
	./scripts/deploy-core-services.sh
	./scripts/deploy-monitoring.sh
	@echo "✅ Complete deployment finished!"

deploy-core: ## Deploy core PyAirtable services only
	@echo "🚀 Deploying core PyAirtable services..."
	./scripts/deploy-core-services.sh
	@echo "✅ Core deployment finished!"

deploy-monitoring: ## Deploy monitoring stack (Prometheus, Grafana, Jaeger)
	@echo "📊 Deploying monitoring stack..."
	./scripts/deploy-monitoring.sh
	@echo "✅ Monitoring deployment finished!"

deploy-istio: ## Deploy Istio service mesh configuration
	@echo "🕸️  Deploying Istio service mesh..."
	kubectl apply -f manifests/istio-service-mesh.yaml
	@echo "✅ Istio deployment finished!"

deploy-security: ## Apply security policies and network policies
	@echo "🔒 Applying security policies..."
	kubectl apply -f manifests/security-policies.yaml
	@echo "✅ Security policies applied!"

deploy-manifests: ## Deploy using enhanced Kubernetes manifests
	@echo "📋 Deploying with enhanced manifests..."
	kubectl apply -f manifests/security-policies.yaml
	kubectl apply -f manifests/enhanced-deployments.yaml
	@echo "✅ Manifests deployment finished!"

##@ Testing and Validation

health-check: ## Run comprehensive health checks
	@echo "🏥 Running health checks..."
	./scripts/health-check.sh pyairtable

e2e-test: ## Run end-to-end tests
	@echo "🧪 Running end-to-end tests..."
	./scripts/e2e-test.sh pyairtable

test-all: health-check e2e-test ## Run all tests (health check + e2e)

##@ Cluster Management  

setup-minikube: ## Setup Minikube cluster with proper configuration
	@echo "🏗️  Setting up Minikube cluster..."
	minikube start --memory=4000 --cpus=3 --disk-size=20g \
		--addons=ingress,registry,metrics-server,dashboard
	kubectl config use-context minikube
	@echo "✅ Minikube setup complete!"

setup-kind: ## Setup Kind cluster with proper configuration
	@echo "🏗️  Setting up Kind cluster..."
	@if [ ! -f kind-config.yaml ]; then \
		echo "Creating Kind configuration..."; \
		cat > kind-config.yaml << EOF; \
kind: Cluster; \
apiVersion: kind.x-k8s.io/v1alpha4; \
nodes:; \
- role: control-plane; \
  extraPortMappings:; \
  - containerPort: 80; \
    hostPort: 80; \
    protocol: TCP; \
  - containerPort: 443; \
    hostPort: 443; \
    protocol: TCP; \
EOF; \
	fi
	kind create cluster --name pyairtable --config kind-config.yaml
	kubectl config use-context kind-pyairtable
	@echo "✅ Kind setup complete!"

##@ Image Management

build-images: ## Build all Docker images for Go services
	@echo "🔨 Building Docker images..."
	cd ../go-services && \
	for service in api-gateway platform-services automation-services; do \
		echo "Building $$service..."; \
		docker build -t localhost:5000/pyairtable-$$service:latest \
			-f cmd/$$service/Dockerfile .; \
	done
	@echo "✅ All images built successfully!"

push-images: ## Push images to registry (for remote deployments)
	@echo "📤 Pushing images to registry..."
	for service in api-gateway platform-services automation-services; do \
		docker push localhost:5000/pyairtable-$$service:latest; \
	done
	@echo "✅ All images pushed successfully!"

##@ Service Management

port-forward: ## Setup port forwarding for all services
	@echo "🌐 Setting up port forwarding..."
	@echo "Starting port forwards in background..."
	@echo "Frontend: http://localhost:3000"
	@echo "API Gateway: http://localhost:8000"
	@echo "Grafana: http://localhost:3001"
	@echo "Prometheus: http://localhost:9090"
	@echo ""
	@echo "Press Ctrl+C to stop all port forwards"
	@(kubectl port-forward -n pyairtable service/frontend 3000:3000 & \
	 kubectl port-forward -n pyairtable service/api-gateway 8000:8000 & \
	 kubectl port-forward -n pyairtable-monitoring service/prometheus-grafana 3001:80 & \
	 kubectl port-forward -n pyairtable-monitoring service/prometheus-kube-prometheus-prometheus 9090:9090 & \
	 wait)

logs: ## View logs for all services
	@echo "📋 Viewing service logs..."
	kubectl logs -f -l app.kubernetes.io/name=pyairtable -n pyairtable --max-log-requests=10

logs-api: ## View API Gateway logs
	kubectl logs -f deployment/api-gateway -n pyairtable

logs-platform: ## View Platform Services logs  
	kubectl logs -f deployment/platform-services -n pyairtable

logs-automation: ## View Automation Services logs
	kubectl logs -f deployment/automation-services -n pyairtable

##@ Status and Monitoring

status: ## Show status of all resources
	@echo "📊 PyAirtable Deployment Status"
	@echo "==============================="
	@echo ""
	@echo "Namespaces:"
	@kubectl get namespaces | grep pyairtable || echo "No PyAirtable namespaces found"
	@echo ""
	@echo "Pods (pyairtable namespace):"
	@kubectl get pods -n pyairtable -o wide || echo "Namespace not found"
	@echo ""
	@echo "Services (pyairtable namespace):"
	@kubectl get services -n pyairtable || echo "Namespace not found"
	@echo ""
	@echo "PVCs (pyairtable namespace):"
	@kubectl get pvc -n pyairtable || echo "No PVCs found"
	@echo ""
	@if kubectl get namespace pyairtable-monitoring >/dev/null 2>&1; then \
		echo "Monitoring Pods:"; \
		kubectl get pods -n pyairtable-monitoring; \
		echo ""; \
	fi

pods: ## Show pod status with resource usage
	@echo "Pod Status and Resource Usage:"
	@kubectl get pods -n pyairtable -o wide
	@echo ""
	@kubectl top pods -n pyairtable 2>/dev/null || echo "Metrics server not available"

services: ## Show service endpoints
	@echo "Service Endpoints:"
	@kubectl get services -n pyairtable
	@echo ""
	@kubectl get endpoints -n pyairtable

events: ## Show recent events
	@echo "Recent Events:"
	@kubectl get events -n pyairtable --sort-by='.lastTimestamp' | tail -20

##@ Scaling Operations

scale-up: ## Scale all services to 3 replicas
	@echo "📈 Scaling services up to 3 replicas..."
	kubectl scale deployment api-gateway --replicas=3 -n pyairtable
	kubectl scale deployment platform-services --replicas=3 -n pyairtable
	kubectl scale deployment automation-services --replicas=3 -n pyairtable
	@echo "✅ Services scaled up!"

scale-down: ## Scale all services to 1 replica
	@echo "📉 Scaling services down to 1 replica..."
	kubectl scale deployment api-gateway --replicas=1 -n pyairtable
	kubectl scale deployment platform-services --replicas=1 -n pyairtable
	kubectl scale deployment automation-services --replicas=1 -n pyairtable
	@echo "✅ Services scaled down!"

scale: ## Scale specific service (usage: make scale SERVICE=api-gateway REPLICAS=3)
	@if [ -z "$(SERVICE)" ] || [ -z "$(REPLICAS)" ]; then \
		echo "Usage: make scale SERVICE=<service-name> REPLICAS=<number>"; \
		echo "Available services: api-gateway, platform-services, automation-services"; \
		exit 1; \
	fi
	kubectl scale deployment $(SERVICE) --replicas=$(REPLICAS) -n pyairtable
	@echo "✅ $(SERVICE) scaled to $(REPLICAS) replicas!"

##@ Cleanup Operations

cleanup: ## Remove PyAirtable services (interactive)
	@echo "🧹 Cleaning up PyAirtable services..."
	./scripts/cleanup.sh pyairtable

cleanup-monitoring: ## Remove monitoring stack
	@echo "🧹 Cleaning up monitoring stack..."
	helm uninstall prometheus jaeger -n pyairtable-monitoring || true
	kubectl delete namespace pyairtable-monitoring || true
	@echo "✅ Monitoring cleanup complete!"

cleanup-all: ## Remove everything including cluster
	@echo "🧹 Complete cleanup (WARNING: This removes everything!)"
	@read -p "Are you sure? This will delete the entire cluster (y/N): " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		./scripts/cleanup.sh pyairtable --force; \
		minikube delete 2>/dev/null || kind delete cluster --name pyairtable 2>/dev/null || true; \
		echo "✅ Complete cleanup finished!"; \
	else \
		echo "Cleanup cancelled"; \
	fi

cleanup-images: ## Remove all PyAirtable Docker images
	@echo "🧹 Cleaning up Docker images..."
	@docker images | grep pyairtable | awk '{print $$3}' | xargs -r docker rmi -f
	@docker image prune -f
	@echo "✅ Docker images cleaned up!"

##@ Development Operations

dev-setup: setup-minikube build-images deploy-core ## Complete development setup
	@echo "🎉 Development environment ready!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Run 'make port-forward' to access services"
	@echo "2. Run 'make health-check' to verify deployment"
	@echo "3. Visit http://localhost:3000 for the frontend"

dev-rebuild: build-images ## Rebuild images and restart deployments
	@echo "🔄 Rebuilding and restarting services..."
	kubectl rollout restart deployment -n pyairtable
	kubectl rollout status deployment -n pyairtable --timeout=300s
	@echo "✅ Services rebuilt and restarted!"

dev-logs: ## Follow logs from all development services
	kubectl logs -f -l app.kubernetes.io/name=pyairtable -n pyairtable --tail=100

##@ Troubleshooting

debug: ## Show debugging information
	@echo "🐛 PyAirtable Debugging Information"
	@echo "===================================="
	@echo ""
	@echo "Cluster Info:"
	@kubectl cluster-info
	@echo ""
	@echo "Node Status:"
	@kubectl get nodes -o wide
	@echo ""
	@echo "Pod Status:"
	@kubectl get pods -n pyairtable -o wide
	@echo ""
	@echo "Recent Events:"
	@kubectl get events -n pyairtable --sort-by='.lastTimestamp' | tail -10
	@echo ""
	@echo "Resource Usage:"
	@kubectl top nodes 2>/dev/null || echo "Metrics server not available"
	@kubectl top pods -n pyairtable 2>/dev/null || echo "Metrics server not available"

describe-failing-pods: ## Describe all non-running pods
	@echo "🔍 Describing failing pods..."
	@kubectl get pods -n pyairtable --field-selector=status.phase!=Running -o name | \
	 xargs -I {} kubectl describe {} -n pyairtable

restart-failing-pods: ## Restart all failing pods
	@echo "🔄 Restarting failing pods..."
	@kubectl get pods -n pyairtable --field-selector=status.phase!=Running -o name | \
	 xargs -I {} kubectl delete {} -n pyairtable
	@echo "✅ Failing pods restarted!"

##@ Configuration

config-show: ## Show current configuration
	@echo "📋 Current Configuration"
	@echo "======================="
	@echo ""
	@echo "Kubectl Context:"
	@kubectl config current-context
	@echo ""
	@echo "Secrets:"
	@kubectl get secrets -n pyairtable || echo "Namespace not found"
	@echo ""
	@echo "ConfigMaps:"
	@kubectl get configmaps -n pyairtable || echo "Namespace not found"
	@echo ""
	@echo "Helm Releases:"
	@helm list -n pyairtable || echo "No releases found"

config-update: ## Update configuration from values files
	@echo "🔧 Updating configuration..."
	@if helm list -n pyairtable | grep -q pyairtable-dev; then \
		helm upgrade pyairtable-dev ./helm/pyairtable-stack \
			--namespace pyairtable \
			--values ./helm/pyairtable-stack/values-dev.yaml; \
		echo "✅ Configuration updated!"; \
	else \
		echo "❌ No Helm release found. Deploy first with 'make deploy-core'"; \
	fi

##@ Utilities

dashboard: ## Open Kubernetes dashboard (Minikube)
	@if command -v minikube >/dev/null 2>&1 && minikube status | grep -q "Running"; then \
		minikube dashboard; \
	else \
		echo "Minikube not running or not available"; \
	fi

shell: ## Get shell access to API Gateway pod
	@kubectl exec -it deployment/api-gateway -n pyairtable -- /bin/sh

db-shell: ## Get shell access to PostgreSQL
	@kubectl exec -it deployment/postgresql-dev -n pyairtable -- psql -U postgres -d pyairtable

redis-shell: ## Get shell access to Redis
	@kubectl exec -it deployment/redis-dev -n pyairtable -- redis-cli

backup-db: ## Backup PostgreSQL database
	@echo "💾 Creating database backup..."
	@kubectl exec deployment/postgresql-dev -n pyairtable -- \
		pg_dump -U postgres pyairtable > backup-$(shell date +%Y%m%d-%H%M%S).sql
	@echo "✅ Database backup created!"

# Variables
NAMESPACE ?= pyairtable
MONITORING_NAMESPACE ?= pyairtable-monitoring
SERVICE ?= api-gateway
REPLICAS ?= 2