#!/bin/bash

# Create remaining Sprint 2 and Sprint 3 issues

echo "Creating remaining Sprint 2 issues..."

# P0-S2-002: MCP Tools
gh issue create \
  --title "P0-S2-002: MCP Server Tool Implementation" \
  --body "## User Story
As a developer, I need MCP tools integrated so I can leverage AI capabilities in the application.

## Acceptance Criteria
- [ ] MCP server running and accessible
- [ ] Tool registration working
- [ ] LLM provider integration functional
- [ ] Request/response handling implemented
- [ ] Error handling for failed LLM calls
- [ ] Token usage tracking
- [ ] Tool execution logging

## Branch Name
\`feature/mcp-tools\`

## Story Points
8" \
  --label "P0,sprint2,mcp" \
  --milestone "Sprint 2: Core Features"

# P0-S2-003: Chat Interface
gh issue create \
  --title "P0-S2-003: Chat Interface Integration" \
  --body "## User Story
As a user, I need a functional chat interface so I can interact with PyAirtable using natural language.

## Acceptance Criteria
- [ ] WebSocket connection to backend
- [ ] Message sending and receiving
- [ ] Conversation history persistence
- [ ] File upload capabilities
- [ ] Real-time typing indicators
- [ ] Error recovery and reconnection
- [ ] Message formatting and markdown support

## Branch Name
\`feature/chat-integration\`

## Story Points
5" \
  --label "P0,sprint2,frontend" \
  --milestone "Sprint 2: Core Features"

echo "Creating Sprint 3 issues..."

# P0-S3-001: Performance
gh issue create \
  --title "P0-S3-001: Performance Optimization" \
  --body "## User Story
As a user, I need fast response times so I can work efficiently with my data.

## Acceptance Criteria
- [ ] API response times under 200ms for simple operations
- [ ] Frontend load times under 2 seconds
- [ ] Database query optimization implemented
- [ ] Caching strategy for frequently accessed data
- [ ] Lazy loading for large datasets
- [ ] Connection pooling optimized
- [ ] Performance monitoring dashboards

## Branch Name
\`perf/application-optimization\`

## Story Points
10" \
  --label "P0,sprint3,performance" \
  --milestone "Sprint 3: Production Ready"

# P0-S3-002: Security
gh issue create \
  --title "P0-S3-002: Security Hardening" \
  --body "## User Story
As a security-conscious user, I need my data protected so I can trust the application with sensitive information.

## Acceptance Criteria
- [ ] Input sanitization and validation
- [ ] SQL injection prevention measures
- [ ] XSS protection implemented
- [ ] HTTPS enforced for all connections
- [ ] API rate limiting in place
- [ ] Secrets management secure
- [ ] Security headers configured
- [ ] Dependency vulnerability scanning

## Branch Name
\`security/hardening\`

## Story Points
8" \
  --label "P0,sprint3,security" \
  --milestone "Sprint 3: Production Ready"

# P0-S3-003: CI/CD
gh issue create \
  --title "P0-S3-003: Production Deployment Pipeline" \
  --body "## User Story
As a DevOps engineer, I need automated deployment so I can release updates safely and efficiently.

## Acceptance Criteria
- [ ] Automated testing in CI pipeline
- [ ] Docker image building and versioning
- [ ] Staging environment deployment
- [ ] Production deployment with rollback capability
- [ ] Database migration automation
- [ ] Health checks before promoting deployments
- [ ] Blue-green deployment strategy

## Branch Name
\`ci-cd/production-pipeline\`

## Story Points
10" \
  --label "P0,sprint3,deployment" \
  --milestone "Sprint 3: Production Ready"

echo "✅ All remaining issues created!"