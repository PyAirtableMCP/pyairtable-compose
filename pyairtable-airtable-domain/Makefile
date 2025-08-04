# Makefile for PyAirtable Airtable Domain Service

.PHONY: help install dev test lint format clean build run stop logs shell migrate

# Default target
help:
	@echo "Available commands:"
	@echo "  install     Install dependencies with Poetry"
	@echo "  dev         Start development environment"
	@echo "  test        Run tests"
	@echo "  lint        Run linting checks"
	@echo "  format      Format code"
	@echo "  clean       Clean up containers and volumes"
	@echo "  build       Build Docker images"
	@echo "  run         Start services"
	@echo "  stop        Stop services"
	@echo "  logs        Show service logs"
	@echo "  shell       Open shell in app container"
	@echo "  migrate     Run database migrations"

# Install dependencies
install:
	poetry install

# Install development dependencies
install-dev:
	poetry install --with=dev

# Start development environment
dev:
	docker-compose up -d postgres redis
	poetry run python -m src.main

# Run tests
test:
	poetry run pytest

# Run tests with coverage
test-cov:
	poetry run pytest --cov=src --cov-report=html --cov-report=term-missing

# Run specific test
test-unit:
	poetry run pytest tests/unit/ -v

test-integration:
	poetry run pytest tests/integration/ -v

# Linting
lint:
	poetry run flake8 src tests
	poetry run mypy src

# Format code
format:
	poetry run black src tests
	poetry run isort src tests

# Check code formatting
format-check:
	poetry run black --check src tests
	poetry run isort --check-only src tests

# Clean up Docker resources
clean:
	docker-compose down -v
	docker system prune -f

# Build Docker images
build:
	docker-compose build

# Start all services
run:
	docker-compose up -d

# Start with monitoring stack
run-monitoring:
	docker-compose --profile monitoring up -d

# Start with worker services
run-workers:
	docker-compose --profile workers up -d

# Start everything
run-all:
	docker-compose --profile monitoring --profile workers up -d

# Stop services
stop:
	docker-compose down

# Show logs
logs:
	docker-compose logs -f

# Show specific service logs
logs-app:
	docker-compose logs -f airtable-domain

logs-db:
	docker-compose logs -f postgres

logs-redis:
	docker-compose logs -f redis

# Open shell in app container
shell:
	docker-compose exec airtable-domain bash

# Database operations
migrate:
	poetry run alembic upgrade head

migrate-create:
	poetry run alembic revision --autogenerate -m "$(name)"

migrate-downgrade:
	poetry run alembic downgrade -1

# Development database setup
db-reset:
	docker-compose down postgres
	docker volume rm pyairtable-airtable-domain_postgres_data || true
	docker-compose up -d postgres
	sleep 5
	$(MAKE) migrate

# Security scan
security:
	poetry run bandit -r src/

# Generate requirements.txt for compatibility
requirements:
	poetry export -f requirements.txt --output requirements.txt --without-hashes

# Pre-commit hooks
install-hooks:
	poetry run pre-commit install

run-hooks:
	poetry run pre-commit run --all-files

# API documentation
docs-serve:
	poetry run python -c "import webbrowser; webbrowser.open('http://localhost:8000/docs')"

# Health check
health:
	curl -f http://localhost:8000/health || echo "Service not healthy"

# Performance testing
perf-test:
	poetry run pytest tests/performance/ -v

# Load testing (requires locust)
load-test:
	poetry run locust -f tests/load/locustfile.py --host=http://localhost:8000

# Docker build for different targets
build-prod:
	docker build --target production -t pyairtable-airtable-domain:latest .

build-dev:
	docker build --target development -t pyairtable-airtable-domain:dev .

# Kubernetes deployment (if applicable)
k8s-deploy:
	kubectl apply -f k8s/

k8s-delete:
	kubectl delete -f k8s/

# Backup database
backup-db:
	docker-compose exec postgres pg_dump -U postgres pyairtable_dev > backup_$(shell date +%Y%m%d_%H%M%S).sql

# Restore database
restore-db:
	docker-compose exec -T postgres psql -U postgres pyairtable_dev < $(file)

# Monitor resource usage
monitor:
	docker stats

# Check service status
status:
	docker-compose ps
	@echo "\nHealth checks:"
	@curl -s http://localhost:8000/health | jq '.' || echo "API not responding"
	@echo "\nDatabase connection:"
	@docker-compose exec postgres pg_isready -U postgres || echo "Database not ready"
	@echo "\nRedis connection:"
	@docker-compose exec redis redis-cli ping || echo "Redis not ready"