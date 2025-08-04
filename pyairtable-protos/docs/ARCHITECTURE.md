# PyAirtable gRPC Architecture

## Overview

This document describes the gRPC architecture for PyAirtable's microservices ecosystem. The architecture is designed for high performance, scalability, and strong type safety across service boundaries.

## Architecture Principles

### 1. Contract-First Development
- All service interfaces are defined in Protocol Buffers
- Services implement generated interfaces
- Strong typing prevents runtime errors
- Clear API contracts between teams

### 2. Service Boundaries
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   API Gateway   │────│  Auth Service   │────│  User Service   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│Permission Service│   │Workspace Service│   │ File Service    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│Notification Svc │    │  Webhook Svc    │    │  Analytics Svc  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 3. Layered Architecture
- **Gateway Layer**: API routing, authentication, rate limiting
- **Core Services**: Business logic and domain operations
- **Support Services**: Cross-cutting concerns (notifications, files)
- **Data Layer**: Persistent storage and caching

## Service Design Patterns

### 1. Request/Response Patterns

#### Unary RPC (Request-Response)
```protobuf
service UserService {
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
}
```

#### Server Streaming (Real-time Updates)
```protobuf
service NotificationService {
  rpc StreamNotifications(StreamRequest) returns (stream Notification);
}
```

#### Client Streaming (Batch Operations)
```protobuf
service FileService {
  rpc BatchUpload(stream UploadRequest) returns (BatchUploadResponse);
}
```

### 2. Error Handling

#### Standard Error Codes
```protobuf
enum ErrorCode {
  ERROR_CODE_UNSPECIFIED = 0;
  ERROR_CODE_INVALID_ARGUMENT = 3;
  ERROR_CODE_NOT_FOUND = 5;
  ERROR_CODE_PERMISSION_DENIED = 7;
  ERROR_CODE_UNAUTHENTICATED = 16;
}
```

#### Error Details
```protobuf
message ErrorDetail {
  string code = 1;
  string message = 2;
  map<string, string> metadata = 3;
}
```

### 3. Authentication & Authorization

#### Request Metadata
Every request includes authentication context:
```protobuf
message RequestMetadata {
  string request_id = 1;
  UserContext user_context = 2;
  string client_ip = 3;
  string user_agent = 4;
  google.protobuf.Timestamp timestamp = 5;
}
```

#### Permission Checking
```protobuf
service PermissionService {
  rpc CheckPermission(CheckPermissionRequest) returns (CheckPermissionResponse);
  rpc BatchCheckPermission(BatchCheckPermissionRequest) returns (BatchCheckPermissionResponse);
}
```

## Data Flow Patterns

### 1. Synchronous Operations
```
Client Request → API Gateway → Service → Database → Response
```

### 2. Asynchronous Operations
```
Client Request → API Gateway → Service → Message Queue → Background Service
```

### 3. Event-Driven Updates
```
Service A → Event Bus → Service B (React to Changes)
```

## Performance Considerations

### 1. Connection Pooling
- Reuse gRPC connections across requests
- Configure appropriate pool sizes
- Monitor connection health

### 2. Load Balancing
- Use client-side load balancing for service-to-service calls
- Implement health checks for service discovery
- Support graceful service shutdowns

### 3. Caching Strategies
```protobuf
message CacheableResponse {
  google.protobuf.Timestamp expires_at = 1;
  string etag = 2;
  // ... response data
}
```

### 4. Pagination
```protobuf
message PaginationRequest {
  int32 page = 1;
  int32 page_size = 2;
  optional string cursor = 3;
}

message PaginationResponse {
  int32 current_page = 1;
  int32 page_size = 2;
  int64 total_count = 3;
  optional string next_cursor = 5;
  bool has_next = 7;
}
```

## Security Architecture

### 1. Authentication Flow
```
1. Client → Auth Service (Login)
2. Auth Service → JWT Token
3. Client → API Gateway (Request + JWT)
4. API Gateway → Auth Service (Validate Token)
5. API Gateway → Target Service (Authenticated Request)
```

### 2. Authorization Patterns

#### Resource-Based Permissions
```protobuf
message Permission {
  string user_id = 1;
  ResourceType resource_type = 2;
  string resource_id = 3;
  PermissionLevel level = 4;
}
```

#### Role-Based Access Control
```protobuf
message Role {
  string name = 1;
  repeated string permissions = 2;
  PermissionScope scope = 3;
}
```

### 3. API Security
- TLS encryption for all gRPC communications
- Mutual TLS (mTLS) for service-to-service communication
- API key authentication for external integrations
- Rate limiting and circuit breakers

## Monitoring & Observability

### 1. Metrics Collection
```protobuf
message APIMetrics {
  string endpoint = 1;
  HttpMethod method = 2;
  int32 status_code = 3;
  int64 response_time_ms = 4;
  google.protobuf.Timestamp timestamp = 7;
}
```

### 2. Distributed Tracing
- Request ID propagation across service calls
- Trace context in all gRPC metadata
- Integration with OpenTelemetry

### 3. Health Checks
```protobuf
enum HealthStatus {
  HEALTH_STATUS_SERVING = 1;
  HEALTH_STATUS_NOT_SERVING = 2;
  HEALTH_STATUS_SERVICE_UNKNOWN = 3;
}

service HealthService {
  rpc Check(HealthCheckRequest) returns (HealthCheckResponse);
}
```

## Deployment Patterns

### 1. Service Discovery
- Kubernetes service discovery
- Consul for service registration
- DNS-based service resolution

### 2. Circuit Breaker Pattern
```protobuf
message CircuitBreakerInfo {
  string service = 1;
  CircuitBreakerState state = 2;
  int32 failure_count = 3;
  google.protobuf.Timestamp next_attempt = 6;
}
```

### 3. Blue-Green Deployments
- Version-aware routing
- Gradual traffic shifting
- Rollback capabilities

## Development Workflow

### 1. Proto-First Development
```
1. Define service contract in .proto files
2. Generate client/server code
3. Implement service logic
4. Write integration tests
5. Deploy and monitor
```

### 2. API Evolution
- Backward-compatible changes only
- New service versions for breaking changes
- Deprecation notices and migration guides

### 3. Testing Strategy
- Unit tests for generated code
- Integration tests for service contracts
- Contract testing between services
- End-to-end testing scenarios

## Best Practices

### 1. Message Design
- Use optional fields for flexibility
- Include metadata in all entities
- Design for forward compatibility
- Use enums with UNSPECIFIED values

### 2. Service Design
- Keep services focused and cohesive
- Minimize service dependencies
- Design for idempotency
- Include proper error handling

### 3. Performance Optimization
- Use streaming for large datasets
- Implement proper caching strategies
- Monitor and optimize hot paths
- Use connection pooling effectively

## Migration Strategy

### 1. REST to gRPC Migration
```
Phase 1: Parallel Implementation (REST + gRPC)
Phase 2: Internal Migration (Service-to-Service)
Phase 3: Client Migration (External APIs)
Phase 4: REST Deprecation
```

### 2. Version Management
- Maintain multiple API versions
- Clear migration timelines
- Comprehensive documentation
- Automated testing for compatibility