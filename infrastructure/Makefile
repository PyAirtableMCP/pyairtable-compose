# PyAirtable Infrastructure Makefile
# Terraform automation and operational tasks

# Configuration
PROJECT_NAME := pyairtable
TERRAFORM_VERSION := 1.5.0
AWS_DEFAULT_REGION := us-east-1

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Default environment
ENV ?= dev

# Terraform directories
TERRAFORM_DIR := terraform
BOOTSTRAP_DIR := $(TERRAFORM_DIR)/bootstrap
MODULES_DIR := $(TERRAFORM_DIR)/modules
ENVS_DIR := $(TERRAFORM_DIR)/environments

# Validate environment
VALID_ENVS := dev staging prod
ifeq ($(filter $(ENV),$(VALID_ENVS)),)
$(error Invalid environment: $(ENV). Valid environments are: $(VALID_ENVS))
endif

# Default target
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help message
	@echo "$(BLUE)PyAirtable Infrastructure Management$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Prerequisites
.PHONY: check-aws check-terraform check-env
check-aws: ## Check AWS CLI configuration
	@echo "$(BLUE)Checking AWS CLI configuration...$(NC)"
	@aws sts get-caller-identity > /dev/null || (echo "$(RED)AWS CLI not configured$(NC)" && exit 1)
	@echo "$(GREEN)AWS CLI configured$(NC)"

check-terraform: ## Check Terraform installation
	@echo "$(BLUE)Checking Terraform installation...$(NC)"
	@terraform version | head -n1 | grep -q "$(TERRAFORM_VERSION)" || (echo "$(RED)Terraform $(TERRAFORM_VERSION) required$(NC)" && exit 1)
	@echo "$(GREEN)Terraform $(TERRAFORM_VERSION) installed$(NC)"

check-env: ## Validate environment variables
	@echo "$(BLUE)Validating environment: $(ENV)$(NC)"
	@test -f $(ENVS_DIR)/$(ENV)/terraform.tfvars || (echo "$(RED)Environment file not found: $(ENVS_DIR)/$(ENV)/terraform.tfvars$(NC)" && exit 1)
	@echo "$(GREEN)Environment validated: $(ENV)$(NC)"

# Bootstrap (run once)
.PHONY: bootstrap bootstrap-init bootstrap-plan bootstrap-apply bootstrap-destroy
bootstrap: check-aws check-terraform ## Bootstrap Terraform state management
	@echo "$(YELLOW)This will create S3 bucket and DynamoDB table for Terraform state$(NC)"
	@echo "$(YELLOW)This should only be run ONCE per AWS account$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r; echo; if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then exit 1; fi
	@$(MAKE) bootstrap-init
	@$(MAKE) bootstrap-plan
	@$(MAKE) bootstrap-apply

bootstrap-init: ## Initialize bootstrap Terraform
	@echo "$(BLUE)Initializing bootstrap Terraform...$(NC)"
	@cd $(BOOTSTRAP_DIR) && terraform init

bootstrap-plan: ## Plan bootstrap resources
	@echo "$(BLUE)Planning bootstrap resources...$(NC)"
	@cd $(BOOTSTRAP_DIR) && terraform plan -var="project_name=$(PROJECT_NAME)"

bootstrap-apply: ## Apply bootstrap resources
	@echo "$(BLUE)Applying bootstrap resources...$(NC)"
	@cd $(BOOTSTRAP_DIR) && terraform apply -var="project_name=$(PROJECT_NAME)" -auto-approve
	@echo "$(GREEN)Bootstrap completed!$(NC)"
	@echo "$(YELLOW)Backend configuration files generated in terraform/$(NC)"

bootstrap-destroy: ## Destroy bootstrap resources (DANGEROUS)
	@echo "$(RED)WARNING: This will destroy the Terraform state backend!$(NC)"
	@echo "$(RED)This will make all infrastructure unmanageable!$(NC)"
	@read -p "Are you ABSOLUTELY sure? Type 'destroy-bootstrap' to continue: " -r; if [[ ! "$$REPLY" == "destroy-bootstrap" ]]; then exit 1; fi
	@cd $(BOOTSTRAP_DIR) && terraform destroy -var="project_name=$(PROJECT_NAME)" -auto-approve

# Main infrastructure
.PHONY: init plan apply destroy validate fmt-check fmt lint
init: check-aws check-terraform check-env ## Initialize Terraform for environment
	@echo "$(BLUE)Initializing Terraform for $(ENV)...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform init -backend-config=environments/$(ENV)/backend.hcl
	@cd $(TERRAFORM_DIR) && terraform workspace select $(ENV) || terraform workspace new $(ENV)

validate: ## Validate Terraform configuration
	@echo "$(BLUE)Validating Terraform configuration...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform validate
	@echo "$(GREEN)Terraform configuration is valid$(NC)"

fmt-check: ## Check Terraform formatting
	@echo "$(BLUE)Checking Terraform formatting...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform fmt -check -recursive
	@echo "$(GREEN)Terraform formatting is correct$(NC)"

fmt: ## Format Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform fmt -recursive
	@echo "$(GREEN)Terraform files formatted$(NC)"

lint: ## Lint Terraform configuration
	@echo "$(BLUE)Linting Terraform configuration...$(NC)"
	@cd $(TERRAFORM_DIR) && tflint --recursive
	@echo "$(GREEN)Terraform linting completed$(NC)"

plan: init ## Plan infrastructure changes
	@echo "$(BLUE)Planning infrastructure for $(ENV)...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform plan -var-file=environments/$(ENV)/terraform.tfvars -out=tfplan-$(ENV)
	@echo "$(GREEN)Plan saved as tfplan-$(ENV)$(NC)"

apply: ## Apply infrastructure changes
	@echo "$(BLUE)Applying infrastructure for $(ENV)...$(NC)"
	@test -f $(TERRAFORM_DIR)/tfplan-$(ENV) || (echo "$(RED)No plan file found. Run 'make plan ENV=$(ENV)' first$(NC)" && exit 1)
	@cd $(TERRAFORM_DIR) && terraform apply tfplan-$(ENV)
	@rm -f $(TERRAFORM_DIR)/tfplan-$(ENV)
	@echo "$(GREEN)Infrastructure applied for $(ENV)$(NC)"

destroy: init ## Destroy infrastructure (DANGEROUS)
	@echo "$(RED)WARNING: This will destroy all infrastructure for $(ENV)!$(NC)"
	@read -p "Are you sure? Type '$(ENV)-destroy' to continue: " -r; if [[ ! "$$REPLY" == "$(ENV)-destroy" ]]; then exit 1; fi
	@cd $(TERRAFORM_DIR) && terraform destroy -var-file=environments/$(ENV)/terraform.tfvars -auto-approve

# Operational tasks
.PHONY: outputs refresh import state-list state-show
outputs: init ## Show Terraform outputs
	@echo "$(BLUE)Terraform outputs for $(ENV):$(NC)"
	@cd $(TERRAFORM_DIR) && terraform output -json | jq .

refresh: init ## Refresh Terraform state
	@echo "$(BLUE)Refreshing Terraform state for $(ENV)...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform refresh -var-file=environments/$(ENV)/terraform.tfvars

state-list: init ## List resources in Terraform state
	@echo "$(BLUE)Resources in Terraform state for $(ENV):$(NC)"
	@cd $(TERRAFORM_DIR) && terraform state list

state-show: init ## Show specific resource in state
	@test -n "$(RESOURCE)" || (echo "$(RED)RESOURCE parameter required. Usage: make state-show ENV=$(ENV) RESOURCE=resource_name$(NC)" && exit 1)
	@cd $(TERRAFORM_DIR) && terraform state show $(RESOURCE)

import: init ## Import existing resource into state
	@test -n "$(RESOURCE)" || (echo "$(RED)RESOURCE parameter required$(NC)" && exit 1)
	@test -n "$(ID)" || (echo "$(RED)ID parameter required$(NC)" && exit 1)
	@cd $(TERRAFORM_DIR) && terraform import -var-file=environments/$(ENV)/terraform.tfvars $(RESOURCE) $(ID)

# Security and compliance
.PHONY: security-scan cost-estimate compliance-check
security-scan: ## Run security scan on Terraform code
	@echo "$(BLUE)Running security scan...$(NC)"
	@checkov -d $(TERRAFORM_DIR) --framework terraform
	@echo "$(GREEN)Security scan completed$(NC)"

cost-estimate: ## Estimate infrastructure costs
	@echo "$(BLUE)Estimating costs for $(ENV)...$(NC)"
	@test -f $(TERRAFORM_DIR)/tfplan-$(ENV) || (echo "$(RED)No plan file found. Run 'make plan ENV=$(ENV)' first$(NC)" && exit 1)
	@infracost breakdown --path $(TERRAFORM_DIR)/tfplan-$(ENV)

compliance-check: ## Check compliance with policies
	@echo "$(BLUE)Checking compliance for $(ENV)...$(NC)"
	@cd $(TERRAFORM_DIR) && terraform plan -var-file=environments/$(ENV)/terraform.tfvars | conftest verify --policy opa-policies -

# Development and testing
.PHONY: test test-unit test-integration clean-cache
test: test-unit test-integration ## Run all tests

test-unit: ## Run unit tests
	@echo "$(BLUE)Running unit tests...$(NC)"
	@cd $(TERRAFORM_DIR) && go test ./tests/unit/...

test-integration: ## Run integration tests
	@echo "$(BLUE)Running integration tests for $(ENV)...$(NC)"
	@cd $(TERRAFORM_DIR) && go test ./tests/integration/... -v -timeout=30m

clean-cache: ## Clean Terraform cache
	@echo "$(BLUE)Cleaning Terraform cache...$(NC)"
	@find $(TERRAFORM_DIR) -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find $(TERRAFORM_DIR) -name "*.tfplan" -delete
	@find $(TERRAFORM_DIR) -name ".terraform.lock.hcl" -delete
	@echo "$(GREEN)Cache cleaned$(NC)"

# Disaster recovery
.PHONY: backup-state restore-state backup-data
backup-state: ## Backup Terraform state
	@echo "$(BLUE)Backing up Terraform state for $(ENV)...$(NC)"
	@mkdir -p backups/$(ENV)
	@cd $(TERRAFORM_DIR) && terraform show -json > ../backups/$(ENV)/terraform-state-$(shell date +%Y%m%d-%H%M%S).json
	@echo "$(GREEN)State backed up to backups/$(ENV)/$(NC)"

restore-state: ## Restore Terraform state from backup
	@test -n "$(BACKUP_FILE)" || (echo "$(RED)BACKUP_FILE parameter required$(NC)" && exit 1)
	@echo "$(YELLOW)Restoring state from $(BACKUP_FILE)$(NC)"
	@echo "$(RED)This is a dangerous operation!$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r; echo; if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then exit 1; fi
	# Implementation depends on specific backup format

backup-data: ## Backup application data
	@echo "$(BLUE)Creating application data backup for $(ENV)...$(NC)"
	@aws backup start-backup-job \
		--backup-vault-name $(PROJECT_NAME)-$(ENV)-backup-vault \
		--resource-arn $(shell cd $(TERRAFORM_DIR) && terraform output -raw database_arn) \
		--iam-role-arn $(shell cd $(TERRAFORM_DIR) && terraform output -raw backup_role_arn)

# Monitoring and logs
.PHONY: logs tail-logs metrics dashboard
logs: ## View application logs
	@test -n "$(SERVICE)" || (echo "$(RED)SERVICE parameter required$(NC)" && exit 1)
	@echo "$(BLUE)Fetching logs for $(SERVICE) in $(ENV)...$(NC)"
	@aws logs describe-log-streams \
		--log-group-name "/ecs/$(PROJECT_NAME)-$(ENV)" \
		--order-by LastEventTime \
		--descending \
		--max-items 1 \
		--query 'logStreams[0].logStreamName' \
		--output text | xargs -I {} aws logs get-log-events \
		--log-group-name "/ecs/$(PROJECT_NAME)-$(ENV)" \
		--log-stream-name {} \
		--query 'events[*].[timestamp,message]' \
		--output table

tail-logs: ## Tail application logs
	@test -n "$(SERVICE)" || (echo "$(RED)SERVICE parameter required$(NC)" && exit 1)
	@echo "$(BLUE)Tailing logs for $(SERVICE) in $(ENV)...$(NC)"
	@aws logs tail "/ecs/$(PROJECT_NAME)-$(ENV)" --follow --filter-pattern "$(SERVICE)"

metrics: ## Show key metrics
	@echo "$(BLUE)Key metrics for $(ENV):$(NC)"
	@aws cloudwatch get-metric-statistics \
		--namespace AWS/ECS \
		--metric-name CPUUtilization \
		--dimensions Name=ClusterName,Value=$(PROJECT_NAME)-$(ENV) \
		--start-time $(shell date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S') \
		--end-time $(shell date -u '+%Y-%m-%dT%H:%M:%S') \
		--period 300 \
		--statistics Average \
		--query 'Datapoints[*].[Timestamp,Average]' \
		--output table

dashboard: ## Open CloudWatch dashboard
	@echo "$(BLUE)Opening CloudWatch dashboard for $(ENV)...$(NC)"
	@aws cloudwatch get-dashboard \
		--dashboard-name $(PROJECT_NAME)-$(ENV)-dashboard \
		--query 'DashboardBody' \
		--output text | jq . > /tmp/dashboard.json
	@echo "Dashboard JSON saved to /tmp/dashboard.json"

# Environment management
.PHONY: switch-env list-workspaces create-env
switch-env: ## Switch to different environment
	@echo "$(BLUE)Switching to environment: $(ENV)$(NC)"
	@cd $(TERRAFORM_DIR) && terraform workspace select $(ENV)

list-workspaces: ## List all Terraform workspaces
	@echo "$(BLUE)Available workspaces:$(NC)"
	@cd $(TERRAFORM_DIR) && terraform workspace list

create-env: ## Create new environment
	@test -n "$(NEW_ENV)" || (echo "$(RED)NEW_ENV parameter required$(NC)" && exit 1)
	@echo "$(BLUE)Creating new environment: $(NEW_ENV)$(NC)"
	@mkdir -p $(ENVS_DIR)/$(NEW_ENV)
	@cp $(ENVS_DIR)/dev/terraform.tfvars $(ENVS_DIR)/$(NEW_ENV)/terraform.tfvars
	@cp $(ENVS_DIR)/dev/backend.hcl $(ENVS_DIR)/$(NEW_ENV)/backend.hcl
	@sed -i 's/environment = "dev"/environment = "$(NEW_ENV)"/g' $(ENVS_DIR)/$(NEW_ENV)/terraform.tfvars
	@sed -i 's/environments\/dev\//environments\/$(NEW_ENV)\//g' $(ENVS_DIR)/$(NEW_ENV)/backend.hcl
	@echo "$(GREEN)Environment $(NEW_ENV) created$(NC)"
	@echo "$(YELLOW)Please review and update $(ENVS_DIR)/$(NEW_ENV)/terraform.tfvars$(NC)"

# CI/CD integration
.PHONY: ci-plan ci-apply ci-test ci-security
ci-plan: ## CI-friendly plan (no interactive prompts)
	@cd $(TERRAFORM_DIR) && terraform init -backend-config=environments/$(ENV)/backend.hcl -input=false
	@cd $(TERRAFORM_DIR) && terraform workspace select $(ENV) || terraform workspace new $(ENV)
	@cd $(TERRAFORM_DIR) && terraform plan -var-file=environments/$(ENV)/terraform.tfvars -input=false -out=tfplan-$(ENV)

ci-apply: ## CI-friendly apply (no interactive prompts)
	@cd $(TERRAFORM_DIR) && terraform apply -input=false tfplan-$(ENV)

ci-test: ## Run tests in CI environment
	@$(MAKE) validate
	@$(MAKE) fmt-check
	@$(MAKE) security-scan

ci-security: ## Run security checks in CI
	@$(MAKE) security-scan
	@$(MAKE) compliance-check

# Quick deployment targets
.PHONY: deploy-dev deploy-staging deploy-prod
deploy-dev: ENV=dev
deploy-dev: ## Quick deploy to development
	@$(MAKE) plan ENV=dev
	@$(MAKE) apply ENV=dev

deploy-staging: ENV=staging
deploy-staging: ## Quick deploy to staging
	@$(MAKE) plan ENV=staging
	@$(MAKE) apply ENV=staging

deploy-prod: ENV=prod
deploy-prod: ## Quick deploy to production (with confirmation)
	@echo "$(RED)Deploying to PRODUCTION$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; echo; if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then exit 1; fi
	@$(MAKE) plan ENV=prod
	@$(MAKE) apply ENV=prod