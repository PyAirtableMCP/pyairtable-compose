# PyAirtable Automation Domain Service Makefile

.PHONY: help install test lint format clean dev build run stop logs shell worker beat flower

# Variables
PYTHON := python
POETRY := poetry
DOCKER_COMPOSE := docker-compose
SERVICE_NAME := automation-domain

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies
	$(POETRY) install

install-dev: ## Install development dependencies
	$(POETRY) install --with dev

test: ## Run tests
	$(POETRY) run pytest

test-cov: ## Run tests with coverage
	$(POETRY) run pytest --cov=src --cov-report=html --cov-report=term

lint: ## Run linting
	$(POETRY) run flake8 src tests
	$(POETRY) run mypy src

format: ## Format code
	$(POETRY) run black src tests
	$(POETRY) run isort src tests

format-check: ## Check code formatting
	$(POETRY) run black --check src tests
	$(POETRY) run isort --check-only src tests

clean: ## Clean cache and temporary files
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
	rm -rf .pytest_cache
	rm -rf htmlcov
	rm -rf .coverage
	rm -rf dist
	rm -rf build

# Development commands
dev: ## Start development environment
	$(DOCKER_COMPOSE) up --build

dev-detached: ## Start development environment in background
	$(DOCKER_COMPOSE) up -d --build

build: ## Build Docker images
	$(DOCKER_COMPOSE) build

run: ## Run the application
	$(POETRY) run python -m src.main

worker: ## Run Celery worker
	$(POETRY) run celery -A src.workers.celery_app worker --loglevel=info --queues=critical,workflow,notification,webhook,automation,default --concurrency=4

beat: ## Run Celery beat scheduler
	$(POETRY) run celery -A src.workers.celery_app beat --loglevel=info

flower: ## Run Flower monitoring
	$(POETRY) run celery -A src.workers.celery_app flower --port=5555

# Docker commands
stop: ## Stop all services
	$(DOCKER_COMPOSE) down

stop-volumes: ## Stop all services and remove volumes
	$(DOCKER_COMPOSE) down -v

logs: ## Show logs
	$(DOCKER_COMPOSE) logs -f

logs-app: ## Show application logs
	$(DOCKER_COMPOSE) logs -f $(SERVICE_NAME)

logs-worker: ## Show worker logs
	$(DOCKER_COMPOSE) logs -f automation-worker

shell: ## Get shell in running container
	$(DOCKER_COMPOSE) exec $(SERVICE_NAME) /bin/bash

shell-worker: ## Get shell in worker container
	$(DOCKER_COMPOSE) exec automation-worker /bin/bash

# Database commands
db-upgrade: ## Run database migrations
	$(POETRY) run alembic upgrade head

db-downgrade: ## Rollback database migrations
	$(POETRY) run alembic downgrade -1

db-revision: ## Create new migration
	$(POETRY) run alembic revision --autogenerate -m "$(message)"

db-reset: ## Reset database
	$(DOCKER_COMPOSE) down postgres
	$(DOCKER_COMPOSE) up -d postgres
	sleep 5
	$(MAKE) db-upgrade

# Testing and CI
ci-test: install-dev lint test ## Run CI tests

security: ## Run security checks
	$(POETRY) run safety check
	$(POETRY) run bandit -r src

# Monitoring
monitor: ## Show system monitoring
	$(DOCKER_COMPOSE) ps
	@echo "\n=== Service Health ==="
	curl -s http://localhost:8090/health | python -m json.tool || echo "Service not responding"
	@echo "\n=== Celery Monitoring ==="
	@echo "Flower: http://localhost:5555"
	@echo "MailHog: http://localhost:8025"

# Production commands
prod-build: ## Build production image
	docker build -t pyairtable-automation-domain:latest .

prod-run: ## Run production container
	docker run -d \
		--name automation-domain \
		-p 8090:8090 \
		-e ENV=production \
		pyairtable-automation-domain:latest

# Utility commands
check-deps: ## Check for dependency updates
	$(POETRY) show --outdated

update-deps: ## Update dependencies
	$(POETRY) update

generate-requirements: ## Generate requirements.txt
	$(POETRY) export -f requirements.txt --output requirements.txt

backup-data: ## Backup database
	$(DOCKER_COMPOSE) exec postgres pg_dump -U postgres pyairtable_automation > backup_$(shell date +%Y%m%d_%H%M%S).sql

restore-data: ## Restore database (specify file with FILE=backup.sql)
	$(DOCKER_COMPOSE) exec -T postgres psql -U postgres pyairtable_automation < $(FILE)