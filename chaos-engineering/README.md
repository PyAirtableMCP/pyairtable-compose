# PyAirtable Chaos Engineering Framework

## Overview

This chaos engineering framework is designed to test the resilience and fault tolerance of the PyAirtable platform through controlled failure injection and monitoring.

## Directory Structure

```
chaos-engineering/
├── chaos-mesh/          # Chaos Mesh installation and configuration
├── experiments/         # Reusable chaos experiments
├── scenarios/          # Common failure scenarios
├── observability/      # Monitoring during chaos experiments
├── documentation/      # Runbooks and procedures
├── safety/            # Guardrails and rollback procedures
└── tools/             # Utility scripts and automation
```

## Quick Start

1. **Setup Chaos Mesh**: `cd chaos-mesh && ./install.sh`
2. **Run Basic Experiment**: `cd experiments && ./run-experiment.sh basic-pod-failure`
3. **Monitor Results**: Check observability dashboards
4. **Review Runbooks**: Consult documentation for specific scenarios

## Safety First

All chaos experiments include:
- Automatic rollback mechanisms
- Resource monitoring and limits
- Emergency stop procedures
- Detailed logging and alerting

## Architecture Components Tested

- **Go Services**: API Gateway, Auth Service, Platform Services
- **Python Services**: Automation Services, AI Services, Analytics
- **Infrastructure**: Kubernetes, PostgreSQL, Redis, Kafka
- **Monitoring**: Prometheus, Grafana, OpenTelemetry
- **Network**: Service mesh, load balancers, ingress

## Experiment Categories

1. **Application Failures**: Service crashes, memory leaks, CPU spikes
2. **Infrastructure Failures**: Node failures, disk issues, network partitions
3. **Data Layer Failures**: Database connections, cache unavailability
4. **Network Failures**: Latency injection, packet loss, DNS issues
5. **Resource Exhaustion**: Memory pressure, CPU limits, disk space

## Getting Started

See individual README files in each directory for detailed instructions.