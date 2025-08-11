# PyAirtable AI Domain Service Makefile

.PHONY: help install dev build test lint format type-check clean docker-build docker-run logs

# Default target
help:
	@echo "PyAirtable AI Domain Service"
	@echo ""
	@echo "Available commands:"
	@echo "  install     Install dependencies"
	@echo "  dev         Run in development mode"
	@echo "  build       Build the application"
	@echo "  test        Run tests"
	@echo "  lint        Run linting"
	@echo "  format      Format code"
	@echo "  type-check  Run type checking"
	@echo "  clean       Clean up temporary files"
	@echo "  docker-build Build Docker image"
	@echo "  docker-run  Run with Docker Compose"
	@echo "  logs        Show Docker logs"

# Installation
install:
	poetry install

install-dev:
	poetry install --with dev

# Development
dev:
	poetry run python -m src.main

dev-debug:
	poetry run python -m debugpy --listen 0.0.0.0:5678 --wait-for-client -m src.main

# Building
build:
	poetry build

# Testing
test:
	poetry run pytest

test-coverage:
	poetry run pytest --cov=src --cov-report=html --cov-report=term

test-unit:
	poetry run pytest tests/unit -v

test-integration:
	poetry run pytest tests/integration -v

test-ai:
	poetry run pytest -m ai -v

# Code quality
lint:
	poetry run flake8 src/ tests/
	poetry run isort --check-only src/ tests/
	poetry run black --check src/ tests/

format:
	poetry run isort src/ tests/
	poetry run black src/ tests/

type-check:
	poetry run mypy src/

# Pre-commit hooks
pre-commit-install:
	poetry run pre-commit install

pre-commit-run:
	poetry run pre-commit run --all-files

# Cleaning
clean:
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	find . -type d -name ".coverage" -delete
	find . -type d -name "htmlcov" -exec rm -rf {} +

# Docker operations
docker-build:
	docker build -t pyairtable-ai-domain:latest .

docker-build-dev:
	docker build --target development -t pyairtable-ai-domain:dev .

docker-run:
	docker-compose up -d

docker-run-dev:
	docker-compose up

docker-stop:
	docker-compose down

docker-restart:
	docker-compose restart ai-domain

docker-logs:
	docker-compose logs -f ai-domain

docker-shell:
	docker-compose exec ai-domain bash

# Database operations
db-migrate:
	poetry run alembic upgrade head

db-revision:
	poetry run alembic revision --autogenerate -m "$(msg)"

db-reset:
	docker-compose down -v
	docker-compose up -d postgres redis qdrant
	sleep 5
	$(MAKE) db-migrate

# Health checks
health:
	curl -f http://localhost:8080/health || exit 1

health-ready:
	curl -f http://localhost:8080/health/ready || exit 1

# Monitoring
metrics:
	curl http://localhost:8080/metrics

# Load testing (requires hey or ab)
load-test:
	hey -n 100 -c 10 http://localhost:8080/health

# Security scanning
security-scan:
	poetry run safety check
	poetry run bandit -r src/

# Documentation
docs-serve:
	echo "Visit http://localhost:8080/docs for API documentation"

# Environment setup
setup-env:
	cp .env.example .env
	@echo "Please edit .env file with your configuration"

# Complete setup for new developers
setup: setup-env install-dev pre-commit-install
	@echo "Setup complete! Run 'make dev' to start development server"

# CI/CD pipeline simulation
ci: lint type-check test security-scan
	@echo "CI pipeline completed successfully"

# Production deployment preparation
deploy-prep: clean format lint type-check test build
	@echo "Deployment preparation completed"

# Quick development restart
restart: docker-stop docker-run
	@echo "Service restarted"

# Monitor logs
monitor:
	docker-compose logs -f

# Backup data
backup:
	docker-compose exec postgres pg_dump -U postgres pyairtable_ai > backup_$(shell date +%Y%m%d_%H%M%S).sql

# Restore data
restore:
	@echo "Usage: make restore file=backup_file.sql"
	docker-compose exec -T postgres psql -U postgres pyairtable_ai < $(file)