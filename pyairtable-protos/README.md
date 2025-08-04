# PyAirtable Protobuf Repository

This repository contains the Protocol Buffer definitions for all PyAirtable microservices, providing a unified contract and type system for gRPC communication.

## Overview

This repository serves as the single source of truth for service contracts in the PyAirtable ecosystem. It includes:

- **Proto Definitions**: Service interfaces and message types
- **Code Generation**: Automated generation for Go and Python
- **Versioning**: Proper API versioning and backward compatibility
- **Documentation**: Comprehensive service documentation

## Repository Structure

```
pyairtable-protos/
├── proto/                          # Protocol buffer definitions
│   └── pyairtable/
│       ├── common/v1/              # Shared types and messages
│       ├── auth/v1/                # Authentication service
│       ├── user/v1/                # User management service
│       ├── permission/v1/          # Permission and RBAC service
│       ├── workspace/v1/           # Workspace management service
│       ├── notification/v1/        # Notification service
│       ├── file/v1/                # File management service
│       └── gateway/v1/             # API Gateway service
├── generated/                      # Generated code (auto-generated)
│   ├── go/                        # Go generated code
│   └── python/                    # Python generated code
├── scripts/                       # Utility scripts
│   ├── install-tools.sh          # Install required tools
│   ├── generate.sh               # Generate code
│   └── watch.sh                  # Watch for changes
├── docs/                          # Documentation
├── examples/                      # Usage examples
├── .github/workflows/             # CI/CD workflows
├── buf.yaml                       # Buf configuration
├── buf.gen.yaml                   # Code generation config
└── Makefile                       # Build automation
```

## Services

### Core Services

1. **Common** (`pyairtable.common.v1`)
   - Shared types and messages
   - Base metadata structures
   - Pagination and filtering
   - Health check definitions

2. **Auth Service** (`pyairtable.auth.v1`)
   - User authentication and authorization
   - Token management (JWT, API keys)
   - OAuth integration
   - Multi-factor authentication

3. **User Service** (`pyairtable.user.v1`)
   - User profile management
   - User preferences and settings
   - User search and discovery

4. **Permission Service** (`pyairtable.permission.v1`)
   - Role-based access control (RBAC)
   - Permission checking and validation
   - Resource-level permissions
   - Permission inheritance

5. **Workspace Service** (`pyairtable.workspace.v1`)
   - Workspace management
   - Team collaboration settings
   - Workspace permissions and access

### Support Services

6. **Notification Service** (`pyairtable.notification.v1`)
   - Multi-channel notifications
   - Email, SMS, push notifications
   - Template management

7. **File Service** (`pyairtable.file.v1`)
   - File upload and management
   - Storage abstraction
   - File metadata and processing

8. **Gateway Service** (`pyairtable.gateway.v1`)
   - API routing and proxying
   - Rate limiting
   - Circuit breaker patterns
   - Request/response metrics

## Quick Start

### Prerequisites

- Go 1.21+ (for Go code generation)
- Python 3.8+ (for Python code generation)
- buf CLI tool
- Protocol Buffer compiler (protoc)

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd pyairtable-protos
```

2. Install required tools:
```bash
make install-tools
```

3. Generate code:
```bash
make generate
```

### Using Generated Code

#### Go

```go
import (
    authv1 "github.com/pyairtable/pyairtable-protos/generated/go/pyairtable/auth/v1"
    userv1 "github.com/pyairtable/pyairtable-protos/generated/go/pyairtable/user/v1"
)

// Create gRPC client
conn, err := grpc.Dial("auth-service:50051", grpc.WithInsecure())
if err != nil {
    log.Fatal(err)
}
defer conn.Close()

client := authv1.NewAuthServiceClient(conn)

// Use the client
resp, err := client.Login(ctx, &authv1.LoginRequest{
    Credentials: &authv1.AuthCredentials{
        Email:    "user@example.com",
        Password: "password",
    },
})
```

#### Python

```python
import grpc
from pyairtable.auth.v1 import auth_pb2, auth_pb2_grpc

# Create gRPC channel
channel = grpc.insecure_channel('auth-service:50051')
client = auth_pb2_grpc.AuthServiceStub(channel)

# Use the client
response = client.Login(auth_pb2.LoginRequest(
    credentials=auth_pb2.AuthCredentials(
        email="user@example.com",
        password="password"
    )
))
```

## Development

### Available Commands

```bash
# Install required tools
make install-tools

# Generate all code
make generate

# Generate only Go code
make generate-go

# Generate only Python code
make generate-python

# Lint protobuf files
make lint

# Format protobuf files
make format

# Clean generated files
make clean

# Watch for changes and auto-regenerate
make watch

# Run tests
make test

# Check for breaking changes
make check
```

### Adding New Services

1. Create new service directory:
```bash
mkdir -p proto/pyairtable/newservice/v1
```

2. Define service proto file:
```protobuf
syntax = "proto3";

package pyairtable.newservice.v1;

import "pyairtable/common/v1/common.proto";

option go_package = "github.com/pyairtable/pyairtable-protos/generated/go/pyairtable/newservice/v1;newservicev1";

service NewService {
  rpc MethodName(MethodRequest) returns (MethodResponse);
}
```

3. Generate code:
```bash
make generate
```

### Versioning Strategy

- **Service Versioning**: Each service uses semantic versioning (v1, v2, etc.)
- **Backward Compatibility**: New versions maintain backward compatibility
- **Field Numbers**: Never reuse protobuf field numbers
- **Breaking Changes**: Require new service version

### Best Practices

1. **Field Naming**: Use snake_case for field names
2. **Service Naming**: Use PascalCase for service and method names
3. **Required Fields**: Avoid required fields, use optional instead
4. **Enums**: Always include UNSPECIFIED as first value (0)
5. **Timestamps**: Use google.protobuf.Timestamp for all time fields
6. **Metadata**: Include BaseMetadata in all entity messages

## CI/CD

The repository includes automated workflows for:

- **Linting**: Validates protobuf files on every PR
- **Code Generation**: Generates Go and Python code
- **Breaking Change Detection**: Ensures backward compatibility
- **Release Creation**: Automatic releases with generated code artifacts

## Integration

### Consuming in Go Services

Add to your `go.mod`:
```go
require (
    github.com/pyairtable/pyairtable-protos/generated/go v0.1.0
)
```

### Consuming in Python Services

Add to your `requirements.txt`:
```
pyairtable-protos==0.1.0
```

## Support

For questions and support:
- Create an issue in this repository
- Review the documentation in `/docs`
- Check examples in `/examples`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `make lint` and `make generate`
5. Submit a pull request

## License

[Your License Here]