# PyAirtable Protocol Buffers

Shared protocol buffer definitions for all PyAirtable microservices.

## Overview

This repository contains the common protocol buffer definitions, shared message types, and service contracts used across all PyAirtable microservices.

## Structure

```
pyairtable-protos/
├── common/           # Shared message types
│   ├── pagination.proto
│   ├── errors.proto
│   ├── timestamps.proto
│   └── metadata.proto
├── services/         # Service definitions
│   ├── auth.proto
│   ├── user.proto
│   ├── workspace.proto
│   ├── table.proto
│   ├── data.proto
│   ├── file.proto
│   ├── notification.proto
│   ├── ai.proto
│   ├── llm.proto
│   ├── mcp.proto
│   ├── search.proto
│   ├── automation.proto
│   ├── analytics.proto
│   └── events.proto
├── generated/        # Generated code (gitignored)
│   ├── go/
│   └── python/
├── scripts/          # Code generation scripts
│   ├── generate-go.sh
│   └── generate-python.sh
├── Makefile
└── README.md
```

## Usage

### For Go Services

```go
import (
    pb "github.com/PyAirtableMCP/pyairtable-protos/generated/go/services"
    common "github.com/PyAirtableMCP/pyairtable-protos/generated/go/common"
)
```

### For Python Services

```python
from pyairtable_protos.services import auth_pb2, auth_pb2_grpc
from pyairtable_protos.common import pagination_pb2
```

## Code Generation

### Generate All Languages
```bash
make generate
```

### Generate Go Code Only
```bash
make generate-go
```

### Generate Python Code Only
```bash
make generate-python
```

## Adding New Definitions

1. Add your `.proto` file to the appropriate directory
2. Run `make generate` to generate code for all languages
3. Commit the `.proto` files (NOT the generated code)
4. Tag a new version for downstream services

## Versioning

We use semantic versioning for proto definitions:
- **Major**: Breaking changes to existing messages/services
- **Minor**: New messages/services added
- **Patch**: Documentation or non-breaking fixes

## Service Contracts

Each service has its own proto file defining:
- Service methods (RPC definitions)
- Request/response messages
- Service-specific enums and types

## Common Types

Shared across all services:
- **Pagination**: StandardPageRequest, PageResponse
- **Errors**: Error, ErrorDetail, ErrorCode enum
- **Timestamps**: Using google.protobuf.Timestamp
- **Metadata**: CommonMetadata for audit fields

## Development

### Prerequisites
- protoc (Protocol Buffer Compiler)
- protoc-gen-go
- protoc-gen-go-grpc
- grpcio-tools (Python)

### Install Dependencies
```bash
make deps
```

## Contributing

1. Create feature branch
2. Add/modify proto definitions
3. Generate code and test locally
4. Submit PR with only proto changes
5. Tag release after merge

## License

MIT