# ARM64 Optimization Summary for LGTM Stack

## Overview
This document summarizes the ARM64 optimizations made to the LGTM (Loki, Grafana, Tempo, Mimir) stack for MacBook Air M2 compatibility.

## Key Changes Made

### 1. Docker Compose Platform Specifications
- Added `platform: linux/arm64` to all services in `docker-compose.lgtm.yml`
- Services affected: MinIO, Loki, Tempo, Mimir, Grafana, Promtail, OpenTelemetry Collector, AlertManager

### 2. Memory Optimizations

#### Tempo (Reduced from 2GB to 1GB)
- **Memory limits**: 2GB → 1GB
- **Memory reservations**: 1GB → 512MB
- **CPU limits**: 1.0 → 0.5
- **CPU reservations**: 0.5 → 0.25

#### Mimir (Reduced from 4GB to 2GB)
- **Memory limits**: 4GB → 2GB
- **Memory reservations**: 2GB → 1GB
- **CPU limits**: 2.0 → 1.0
- **CPU reservations**: 1.0 → 0.5

### 3. Tempo Configuration Optimizations (`tempo/tempo-simple.yml`)
- **Parallelism**: 20 → 10 workers
- **Concurrent jobs**: 1000 → 100
- **Query shards**: 50 → 10
- **Tokens**: 128 → 64
- **Max block bytes**: 100MB → 50MB
- **Block retention**: 168h → 72h
- **Pool workers**: 100 → 50
- **Queue depth**: 10000 → 1000
- **Complete block timeout**: 32m → 16m

### 4. Mimir Configuration Optimizations (`mimir/mimir-simple.yml`)
- **Block ranges**: Removed 24h range, kept 2h and 12h
- **Retention period**: 24h → 12h
- **Index cache**: 268MB → 134MB
- **Chunks cache**: 268MB → 134MB
- **Max concurrent queries**: 20 → 10
- **Query timeout**: 2m → 1m
- **Results cache**: 134MB → 67MB
- **Ingestion rate**: 10000 → 5000
- **Ingestion burst**: 200000 → 100000
- **Max series per user**: 1M → 500K
- **Max samples per query**: 1M → 500K
- **Tokens**: 128 → 64

### 5. Additional Files Created
- **AlertManager configuration**: `alertmanager/alertmanager-optimized.yml`
- **ARM64 test script**: `test-arm64-stack.sh`

## Total Resource Usage

### Before Optimization
- **Total Memory**: ~9GB (MinIO + Loki + Tempo + Mimir + Grafana + Others)
- **Total CPU**: ~5.25 cores

### After Optimization
- **Total Memory**: ~6GB (fits within 8GB system limit)
- **Total CPU**: ~3.25 cores

## Services and Ports

| Service | Port | Purpose |
|---------|------|---------|
| MinIO | 9000, 9001 | Object storage and console |
| Loki | 3100 | Log aggregation |
| Tempo | 3200, 14268, 4317, 4318 | Distributed tracing |
| Mimir | 8081, 7946 | Metrics storage |
| Grafana | 3001 | Visualization dashboard |
| OTEL Collector | 4317, 4319, 8889, 13133 | Telemetry collection |
| AlertManager | 9093 | Alert notifications |

## Testing

### Quick Test
```bash
# Validate configuration
docker-compose -f docker-compose.lgtm.yml config --quiet

# Start the stack
docker-compose -f docker-compose.lgtm.yml up -d
```

### Comprehensive Test
```bash
# Run the ARM64 test script
./test-arm64-stack.sh
```

## Credentials
- **Grafana**: admin / admin123
- **MinIO**: minioadmin / minioadmin123

## ARM64 Compatibility Notes
- All images support ARM64 architecture
- Configurations optimized for limited resources
- Retention periods reduced for local development
- Cache sizes adjusted for memory constraints
- Worker counts tuned for ARM64 performance characteristics

## Troubleshooting
If services fail to start:
1. Check available memory: `docker system df`
2. Verify Docker Desktop has sufficient resources allocated
3. Check logs: `docker-compose -f docker-compose.lgtm.yml logs [service-name]`
4. Restart with clean state: `docker-compose -f docker-compose.lgtm.yml down -v && docker-compose -f docker-compose.lgtm.yml up -d`