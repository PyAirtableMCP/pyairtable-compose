# PyAirtable Workspace Service

A high-performance gRPC microservice for workspace/tenant management, permissions, and sharing built with Go.

## Features

- **Workspace Management**: Create, update, delete, and list workspaces
- **Member Management**: Invite, remove, and manage member roles
- **Permission System**: Fine-grained permission control with role-based access
- **Invitation System**: Secure workspace invitations with expiration
- **Settings Management**: Configurable workspace settings
- **Caching**: Redis-based caching for improved performance
- **Database Migrations**: Automated database schema management
- **Health Checks**: Built-in health check endpoints
- **Docker Support**: Full containerization support

## Architecture

The service follows a clean architecture pattern:

```
cmd/workspace/          # Application entry point
internal/
├── config/            # Configuration management
├── handlers/          # gRPC handlers
├── service/           # Business logic layer
├── repository/        # Data access layer
├── models/            # Data models
├── permissions/       # Permission checking logic
proto/                 # Protocol buffer definitions
migrations/            # Database migrations
configs/               # Configuration files
```

## Quick Start

### Prerequisites

- Go 1.21+
- PostgreSQL 12+
- Redis 6+
- Protocol Buffers compiler (protoc)

### Development Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd pyairtable-workspace-service-go
   ```

2. **Install dependencies and setup development environment**
   ```bash
   make setup-dev
   make deps
   ```

3. **Generate protobuf files**
   ```bash
   make proto
   ```

4. **Start development services**
   ```bash
   make dev-services-up
   ```

5. **Create environment file**
   ```bash
   make env-example
   cp .env.example .env
   # Edit .env with your configuration
   ```

6. **Run database migrations**
   ```bash
   make migrate-up
   ```

7. **Run the service**
   ```bash
   make run-dev
   ```

### Using Docker

1. **Build and run with Docker Compose**
   ```bash
   docker-compose -f docker-compose.dev.yml up --build
   ```

2. **Build Docker image**
   ```bash
   make docker-build
   ```

3. **Run Docker container**
   ```bash
   make docker-run
   ```

## API Reference

The service exposes a gRPC API on port 50053. Key service methods include:

### Workspace Operations
- `CreateWorkspace` - Create a new workspace
- `GetWorkspace` - Retrieve workspace details
- `UpdateWorkspace` - Update workspace information
- `DeleteWorkspace` - Delete a workspace
- `ListWorkspaces` - List user's workspaces

### Member Management
- `InviteMember` - Invite a user to the workspace
- `AcceptInvitation` - Accept a workspace invitation
- `DeclineInvitation` - Decline a workspace invitation
- `RemoveMember` - Remove a member from the workspace
- `UpdateMemberRole` - Change a member's role
- `ListMembers` - List workspace members

### Permission Management
- `CheckPermission` - Check if a user has a specific permission
- `GrantPermission` - Grant a permission to a user
- `RevokePermission` - Revoke a permission from a user
- `ListPermissions` - List permissions in the workspace

### Settings Management
- `UpdateSettings` - Update workspace settings
- `GetSettings` - Retrieve workspace settings

## Configuration

Configuration can be set via environment variables or configuration file:

### Environment Variables

```bash
# Server
SERVER_HOST=0.0.0.0
GRPC_PORT=50053

# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=workspace_service
DB_USER=postgres
DB_PASSWORD=postgres

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
```

### Configuration File

See `configs/config.yaml` for the full configuration schema.

## Database Schema

The service uses PostgreSQL with the following main tables:

- `workspaces` - Workspace information and settings
- `members` - Workspace members and their roles
- `invitations` - Pending workspace invitations
- `permission_grants` - Explicit permission grants

## Permission System

The service implements a role-based permission system with four main roles:

- **Owner**: Full control over the workspace
- **Admin**: Can manage members and settings (except promoting to owner)
- **Editor**: Can read and write data
- **Viewer**: Can only read data

Additional explicit permissions can be granted for fine-grained control:
- `read`, `write`, `delete` - Data permissions
- `manage_members` - Member management
- `manage_settings` - Settings management
- `admin` - Administrative permissions

## Development

### Available Make Commands

```bash
make help              # Show all available commands
make dev               # Full development workflow
make build             # Build the application
make test              # Run tests
make test-coverage     # Run tests with coverage
make lint              # Run linter
make proto             # Generate protobuf files
make migrate-up        # Run database migrations
make docker-build      # Build Docker image
```

### Running Tests

```bash
# Run all tests
make test

# Run tests with coverage
make test-coverage

# Run tests with race detection
make test-race
```

### Code Quality

The project uses:
- `golangci-lint` for linting
- Standard Go formatting (`go fmt`)
- Go vet for static analysis
- Comprehensive test coverage

```bash
make lint              # Run linter
make fmt               # Format code
make vet               # Run static analysis
```

## Deployment

### Docker Deployment

1. **Build the image**
   ```bash
   make docker-build
   ```

2. **Run with Docker Compose**
   ```bash
   docker-compose -f docker-compose.dev.yml up -d
   ```

### Production Deployment

For production deployment:

1. Set appropriate environment variables
2. Ensure PostgreSQL and Redis are available
3. Run database migrations
4. Deploy the container with health checks enabled

## Health Checks

The service provides health check endpoints:

- gRPC health check on port 50053 (standard gRPC health checking protocol)
- Docker health check built into the container

## Monitoring

The service includes:

- Structured logging with configurable levels
- Request/response logging with timing
- Connection pool monitoring
- Background task monitoring

## Contributing

1. Follow the existing code structure and patterns
2. Write tests for new functionality
3. Run the full test suite before submitting
4. Follow Go best practices and idioms

## License

[Add your license information here]