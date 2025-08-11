# PyAirtable Compose - Orchestration Layer

This repository contains **ONLY** the Docker Compose orchestration files for the PyAirtable platform.

## Repository Structure

The PyAirtable platform is now properly separated into individual repositories:

- **[pyairtable-frontend](https://github.com/PyAirtableMCP/pyairtable-frontend)** - All frontend services (React/Next.js)
- **[pyairtable-go-services](https://github.com/PyAirtableMCP/pyairtable-go-services)** - All Go microservices
- **[pyairtable-python-services](https://github.com/PyAirtableMCP/pyairtable-python-services)** - All Python microservices
- **[pyairtable-infrastructure](https://github.com/PyAirtableMCP/pyairtable-infrastructure)** - Infrastructure as Code (Terraform/K8s)
- **[pyairtable-docs](https://github.com/PyAirtableMCP/pyairtable-docs)** - Documentation hub

## What This Repository Contains

- `docker-compose.yml` - Main orchestration file
- `docker-compose.prod.yml` - Production configuration
- `docker-compose.test.yml` - Test configuration
- `.env.*` - Environment configurations
- Deployment and test scripts

## Quick Start

1. Clone all repositories:
```bash
git clone https://github.com/PyAirtableMCP/pyairtable-compose.git
git clone https://github.com/PyAirtableMCP/pyairtable-frontend.git
git clone https://github.com/PyAirtableMCP/pyairtable-go-services.git
git clone https://github.com/PyAirtableMCP/pyairtable-python-services.git
git clone https://github.com/PyAirtableMCP/pyairtable-infrastructure.git
```

2. Set up environment:
```bash
cd pyairtable-compose
cp .env.example .env
# Edit .env with your configuration
```

3. Start services:
```bash
docker-compose up -d
```

## Development

Each service repository has its own development setup and README. This repository is purely for orchestration.

## License

MIT
