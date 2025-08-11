# Variables
BINARY_NAME=workspace-service
DOCKER_IMAGE=pyairtable/workspace-service
VERSION?=latest
PORT?=50053

# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GOCLEAN=$(GOCMD) clean
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOMOD=$(GOCMD) mod

# Build paths
BUILD_DIR=build
MAIN_PATH=./cmd/workspace
BINARY_PATH=$(BUILD_DIR)/$(BINARY_NAME)

# Protobuf
PROTO_PATH=proto
PROTO_FILES=$(wildcard $(PROTO_PATH)/*.proto)

# Default target
.PHONY: all
all: clean deps proto build

# Install dependencies
.PHONY: deps
deps:
	$(GOMOD) download
	$(GOMOD) tidy

# Generate protobuf files
.PHONY: proto
proto:
	@echo "Generating protobuf files..."
	protoc --go_out=. --go_opt=paths=source_relative \
		--go-grpc_out=. --go-grpc_opt=paths=source_relative \
		$(PROTO_FILES)

# Build the application
.PHONY: build
build:
	@echo "Building $(BINARY_NAME)..."
	mkdir -p $(BUILD_DIR)
	$(GOBUILD) -o $(BINARY_PATH) $(MAIN_PATH)

# Build for Linux
.PHONY: build-linux
build-linux:
	@echo "Building $(BINARY_NAME) for Linux..."
	mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GOBUILD) -o $(BINARY_PATH)-linux $(MAIN_PATH)

# Run the application
.PHONY: run
run: build
	@echo "Running $(BINARY_NAME)..."
	$(BINARY_PATH)

# Run with environment file
.PHONY: run-dev
run-dev:
	@echo "Running $(BINARY_NAME) in development mode..."
	@if [ -f .env ]; then \
		export $$(cat .env | grep -v '^#' | xargs) && $(GOBUILD) -o $(BINARY_PATH) $(MAIN_PATH) && $(BINARY_PATH); \
	else \
		echo "No .env file found. Creating example..."; \
		cp .env.example .env; \
		echo "Please edit .env file and run 'make run-dev' again"; \
	fi

# Test
.PHONY: test
test:
	@echo "Running tests..."
	$(GOTEST) -v ./...

# Test with coverage
.PHONY: test-coverage
test-coverage:
	@echo "Running tests with coverage..."
	$(GOTEST) -v -coverprofile=coverage.out ./...
	$(GOCMD) tool cover -html=coverage.out

# Run tests with race detection
.PHONY: test-race
test-race:
	@echo "Running tests with race detection..."
	$(GOTEST) -v -race ./...

# Lint
.PHONY: lint
lint:
	@echo "Running linter..."
	golangci-lint run

# Format code
.PHONY: fmt
fmt:
	@echo "Formatting code..."
	$(GOCMD) fmt ./...

# Vet code
.PHONY: vet
vet:
	@echo "Vetting code..."
	$(GOCMD) vet ./...

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning..."
	$(GOCLEAN)
	rm -rf $(BUILD_DIR)
	rm -f coverage.out

# Docker targets
.PHONY: docker-build
docker-build:
	@echo "Building Docker image..."
	docker build -t $(DOCKER_IMAGE):$(VERSION) .

.PHONY: docker-run
docker-run:
	@echo "Running Docker container..."
	docker run --rm -p $(PORT):$(PORT) \
		--name workspace-service \
		$(DOCKER_IMAGE):$(VERSION)

.PHONY: docker-stop
docker-stop:
	@echo "Stopping Docker container..."
	docker stop workspace-service || true

# Database migrations
.PHONY: migrate-up
migrate-up:
	@echo "Running database migrations..."
	migrate -path migrations -database "$$DATABASE_URL" up

.PHONY: migrate-down
migrate-down:
	@echo "Rolling back database migrations..."
	migrate -path migrations -database "$$DATABASE_URL" down

.PHONY: migrate-create
migrate-create:
	@echo "Creating new migration..."
	@read -p "Enter migration name: " name; \
	migrate create -ext sql -dir migrations $$name

# Development setup
.PHONY: setup-dev
setup-dev:
	@echo "Setting up development environment..."
	@if ! command -v protoc > /dev/null; then \
		echo "Please install protoc first"; \
		exit 1; \
	fi
	$(GOGET) google.golang.org/protobuf/cmd/protoc-gen-go@latest
	$(GOGET) google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
	$(GOGET) github.com/golang-migrate/migrate/v4/cmd/migrate@latest
	@if ! command -v golangci-lint > /dev/null; then \
		echo "Installing golangci-lint..."; \
		curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $$(go env GOPATH)/bin latest; \
	fi

# Generate example environment file
.PHONY: env-example
env-example:
	@echo "Creating .env.example..."
	@cat > .env.example << 'EOF'
# Server Configuration
SERVER_HOST=0.0.0.0
SERVER_PORT=8080
GRPC_PORT=50053

# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=workspace_service
DB_USER=postgres
DB_PASSWORD=postgres
DB_SSLMODE=disable

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# Logging
LOG_LEVEL=info
LOG_FORMAT=json

# Migration
DB_MIGRATION_PATH=file://migrations
DATABASE_URL=postgres://postgres:postgres@localhost:5432/workspace_service?sslmode=disable
EOF

# Start development services (requires Docker Compose)
.PHONY: dev-services-up
dev-services-up:
	@echo "Starting development services..."
	docker-compose -f docker-compose.dev.yml up -d

.PHONY: dev-services-down
dev-services-down:
	@echo "Stopping development services..."
	docker-compose -f docker-compose.dev.yml down

# Full development workflow
.PHONY: dev
dev: deps proto build test

# CI workflow
.PHONY: ci
ci: deps proto vet lint test-race

# Help
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  all            - Clean, install deps, generate proto, and build"
	@echo "  deps           - Download Go dependencies"
	@echo "  proto          - Generate protobuf files"
	@echo "  build          - Build the application"
	@echo "  build-linux    - Build for Linux"
	@echo "  run            - Build and run the application"
	@echo "  run-dev        - Run with .env file"
	@echo "  test           - Run tests"
	@echo "  test-coverage  - Run tests with coverage"
	@echo "  test-race      - Run tests with race detection"
	@echo "  lint           - Run linter"
	@echo "  fmt            - Format code"
	@echo "  vet            - Vet code"
	@echo "  clean          - Clean build artifacts"
	@echo "  docker-build   - Build Docker image"
	@echo "  docker-run     - Run Docker container"
	@echo "  migrate-up     - Run database migrations"
	@echo "  migrate-down   - Rollback database migrations"
	@echo "  setup-dev      - Setup development environment"
	@echo "  dev            - Full development workflow"
	@echo "  ci             - CI workflow"