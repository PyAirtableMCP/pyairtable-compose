# PyAirtable Compose CI/CD

This repository contains only Docker Compose configurations and should not have CI/CD workflows.

All CI/CD workflows have been moved to their respective service repositories:

- **Frontend CI/CD**: `pyairtable-frontend` repository
- **Python Services CI/CD**: `pyairtable-python-services` repository  
- **Go Services CI/CD**: `pyairtable-go-services` repository

## Archived Workflows

The previous workflows (which were incorrectly placed here) have been moved to `.github/workflows-archive/` for reference.

## What This Repo Should Contain

- `docker-compose.yml` files for different environments
- Environment configuration files
- Documentation for local development setup
- Infrastructure scripts (if any)

## What This Repo Should NOT Contain

- CI/CD workflows for testing/building services
- Service-specific code or tests
- Deployment configurations (those belong in service repos)