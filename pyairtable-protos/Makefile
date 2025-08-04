.PHONY: help install-tools generate generate-go generate-python clean lint format build test check deps

# Variables
PROTOC_VERSION := 3.21.12
BUF_VERSION := v1.28.1
PROTOC_GEN_GO_VERSION := v1.31.0
PROTOC_GEN_GO_GRPC_VERSION := v1.3.0

# Directories
PROTO_DIR := proto
GENERATED_DIR := generated
GO_OUT_DIR := $(GENERATED_DIR)/go
PYTHON_OUT_DIR := $(GENERATED_DIR)/python
SCRIPTS_DIR := scripts

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install-tools: ## Install required tools (buf, protoc, etc.)
	@echo "$(YELLOW)Installing required tools...$(NC)"
	@$(SCRIPTS_DIR)/install-tools.sh

deps: install-tools ## Install dependencies
	@echo "$(YELLOW)Installing dependencies...$(NC)"
	@buf dep update

generate: clean generate-go generate-python ## Generate all code (Go and Python)
	@echo "$(GREEN)Code generation completed successfully!$(NC)"

generate-go: ## Generate Go code from protobuf definitions
	@echo "$(YELLOW)Generating Go code...$(NC)"
	@mkdir -p $(GO_OUT_DIR)
	@buf generate --template buf.gen.yaml --path $(PROTO_DIR)
	@echo "$(GREEN)Go code generated successfully!$(NC)"

generate-python: ## Generate Python code from protobuf definitions
	@echo "$(YELLOW)Generating Python code...$(NC)"
	@mkdir -p $(PYTHON_OUT_DIR)
	@buf generate --template buf.gen.yaml --path $(PROTO_DIR)
	@echo "$(GREEN)Python code generated successfully!$(NC)"

clean: ## Clean generated files
	@echo "$(YELLOW)Cleaning generated files...$(NC)"
	@rm -rf $(GENERATED_DIR)
	@echo "$(GREEN)Generated files cleaned!$(NC)"

lint: ## Lint protobuf files
	@echo "$(YELLOW)Linting protobuf files...$(NC)"
	@buf lint

format: ## Format protobuf files
	@echo "$(YELLOW)Formatting protobuf files...$(NC)"
	@buf format -w

build: lint generate ## Build all (lint + generate)
	@echo "$(GREEN)Build completed successfully!$(NC)"

test: ## Run tests for generated code
	@echo "$(YELLOW)Running tests...$(NC)"
	@$(SCRIPTS_DIR)/run-tests.sh

check: lint ## Check protobuf files for breaking changes
	@echo "$(YELLOW)Checking for breaking changes...$(NC)"
	@buf breaking --against '.git#branch=main'

# Development helpers
watch: ## Watch for changes and regenerate code
	@echo "$(YELLOW)Watching for changes...$(NC)"
	@$(SCRIPTS_DIR)/watch.sh

docker-generate: ## Generate code using Docker (no local tools required)
	@echo "$(YELLOW)Generating code using Docker...$(NC)"
	@docker run --rm -v $(PWD):/workspace -w /workspace bufbuild/buf:$(BUF_VERSION) generate

docker-lint: ## Lint using Docker
	@echo "$(YELLOW)Linting using Docker...$(NC)"
	@docker run --rm -v $(PWD):/workspace -w /workspace bufbuild/buf:$(BUF_VERSION) lint

# Release helpers
tag: ## Create a new git tag
	@$(SCRIPTS_DIR)/create-tag.sh

release: check build tag ## Create a release (check + build + tag)
	@echo "$(GREEN)Release process completed!$(NC)"

# Go specific helpers
go-mod-init: ## Initialize Go module for generated code
	@echo "$(YELLOW)Initializing Go module...$(NC)"
	@cd $(GO_OUT_DIR) && go mod init github.com/pyairtable/pyairtable-protos/generated/go
	@cd $(GO_OUT_DIR) && go mod tidy

go-test: ## Run Go tests
	@echo "$(YELLOW)Running Go tests...$(NC)"
	@cd $(GO_OUT_DIR) && go test ./...

# Python specific helpers
python-setup: ## Set up Python environment
	@echo "$(YELLOW)Setting up Python environment...$(NC)"
	@cd $(PYTHON_OUT_DIR) && python -m pip install -e .

python-test: ## Run Python tests
	@echo "$(YELLOW)Running Python tests...$(NC)"
	@cd $(PYTHON_OUT_DIR) && python -m pytest

# Documentation
docs: ## Generate documentation
	@echo "$(YELLOW)Generating documentation...$(NC)"
	@$(SCRIPTS_DIR)/generate-docs.sh

docs-serve: ## Serve documentation locally
	@echo "$(YELLOW)Serving documentation...$(NC)"
	@$(SCRIPTS_DIR)/serve-docs.sh