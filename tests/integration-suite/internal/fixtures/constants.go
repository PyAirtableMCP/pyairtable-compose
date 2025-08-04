package fixtures

// Test Tenant IDs - Predefined for consistent testing
const (
	TestTenantAlphaID = "550e8400-e29b-41d4-a716-446655440001"
	TestTenantBetaID  = "550e8400-e29b-41d4-a716-446655440002"
	TestTenantGammaID = "550e8400-e29b-41d4-a716-446655440003" // Suspended tenant for testing
)

// Test User IDs - Predefined for consistent testing
const (
	// Alpha Tenant Users
	TestUserAlphaAdminID = "660e8400-e29b-41d4-a716-446655440001"
	TestUserAlphaUser1ID = "660e8400-e29b-41d4-a716-446655440002"
	TestUserAlphaUser2ID = "660e8400-e29b-41d4-a716-446655440003"
	TestUserAlphaUser3ID = "660e8400-e29b-41d4-a716-446655440004"
	
	// Beta Tenant Users
	TestUserBetaAdminID = "660e8400-e29b-41d4-a716-446655440005"
	TestUserBetaUser1ID = "660e8400-e29b-41d4-a716-446655440006"
	TestUserBetaUser2ID = "660e8400-e29b-41d4-a716-446655440007"
	
	// Gamma Tenant Users (Suspended)
	TestUserGammaAdminID = "660e8400-e29b-41d4-a716-446655440008"
)

// Test Workspace IDs - Predefined for consistent testing
const (
	// Alpha Tenant Workspaces
	TestWorkspaceAlpha1ID = "770e8400-e29b-41d4-a716-446655440001"
	TestWorkspaceAlpha2ID = "770e8400-e29b-41d4-a716-446655440002"
	
	// Beta Tenant Workspaces
	TestWorkspaceBeta1ID = "770e8400-e29b-41d4-a716-446655440003"
)

// Test Project IDs - Predefined for consistent testing
const (
	// Alpha Workspace 1 Projects
	TestProjectAlpha1_1ID = "880e8400-e29b-41d4-a716-446655440001"
	TestProjectAlpha1_2ID = "880e8400-e29b-41d4-a716-446655440002"
	
	// Alpha Workspace 2 Projects
	TestProjectAlpha2_1ID = "880e8400-e29b-41d4-a716-446655440003"
	
	// Beta Workspace 1 Projects
	TestProjectBeta1_1ID = "880e8400-e29b-41d4-a716-446655440004"
)

// Test Base IDs - Predefined for consistent testing
const (
	// Alpha Project Bases
	TestBaseAlpha1_1_1ID = "990e8400-e29b-41d4-a716-446655440001"
	TestBaseAlpha1_1_2ID = "990e8400-e29b-41d4-a716-446655440002"
	TestBaseAlpha1_2_1ID = "990e8400-e29b-41d4-a716-446655440003"
	
	// Beta Project Bases
	TestBaseBeta1_1_1ID = "990e8400-e29b-41d4-a716-446655440004"
)

// Test API Keys
const (
	TestAPIKeyValid   = "test-api-key-12345"
	TestAPIKeyInvalid = "invalid-api-key"
	TestAPIKeyExpired = "expired-api-key-67890"
)

// Test JWT Secrets
const (
	TestJWTSecret = "test-jwt-secret-for-testing-only"
)

// Test Email Addresses
const (
	// Alpha Tenant
	TestEmailAlphaAdmin = "admin@alpha.test.com"
	TestEmailAlphaUser1 = "user1@alpha.test.com"
	TestEmailAlphaUser2 = "user2@alpha.test.com"
	TestEmailAlphaUser3 = "user3@alpha.test.com"
	
	// Beta Tenant
	TestEmailBetaAdmin = "admin@beta.test.com"
	TestEmailBetaUser1 = "user1@beta.test.com"
	TestEmailBetaUser2 = "user2@beta.test.com"
	
	// Gamma Tenant (Suspended)
	TestEmailGammaAdmin = "admin@gamma.test.com"
)

// Test Passwords (Hashed)
const (
	TestPasswordPlain  = "test123"
	TestPasswordHashed = "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO" // test123
)

// Test Domains
const (
	TestDomainAlpha = "alpha.test.pyairtable.com"
	TestDomainBeta  = "beta.test.pyairtable.com"
	TestDomainGamma = "gamma.test.pyairtable.com"
)

// Test Plan Types
const (
	TestPlanFree       = "free"
	TestPlanPro        = "pro"
	TestPlanEnterprise = "enterprise"
	TestPlanCustom     = "custom"
)

// Test Status Values
const (
	StatusActive    = "active"
	StatusInactive  = "inactive"
	StatusSuspended = "suspended"
	StatusPending   = "pending"
	StatusDeleted   = "deleted"
)

// Test Role Values
const (
	RoleTenantAdmin    = "tenant_admin"
	RoleWorkspaceAdmin = "workspace_admin"
	RoleProjectAdmin   = "project_admin"
	RoleEditor         = "editor"
	RoleViewer         = "viewer"
	RoleCollaborator   = "collaborator"
	RoleGuest          = "guest"
)

// Test Permission Values
const (
	PermissionAdmin       = "admin"
	PermissionEditor      = "editor"
	PermissionContributor = "contributor"
	PermissionViewer      = "viewer"
	PermissionCommenter   = "commenter"
	PermissionReader      = "reader"
)

// Test Resource Types
const (
	ResourceTypeTenant    = "tenant"
	ResourceTypeWorkspace = "workspace"
	ResourceTypeProject   = "project"
	ResourceTypeBase      = "base"
	ResourceTypeTable     = "table"
	ResourceTypeRecord    = "record"
)

// Test Base Types
const (
	BaseTypeStandard           = "standard"
	BaseTypeAnalytics          = "analytics"
	BaseTypeCRM                = "crm"
	BaseTypeMarketing          = "marketing"
	BaseTypeProjectManagement  = "project_management"
	BaseTypeInventory          = "inventory"
	BaseTypeHR                 = "hr"
	BaseTypeFinance            = "finance"
)

// Test Event Types
const (
	// User Events
	EventUserCreated           = "user.created"
	EventUserUpdated           = "user.updated"
	EventUserDeleted           = "user.deleted"
	EventUserLoggedIn          = "user.logged_in"
	EventUserLoggedOut         = "user.logged_out"
	EventUserPasswordChanged   = "user.password_changed"
	EventUserRoleChanged       = "user.role_changed"
	
	// Workspace Events
	EventWorkspaceCreated      = "workspace.created"
	EventWorkspaceUpdated      = "workspace.updated"
	EventWorkspaceDeleted      = "workspace.deleted"
	EventWorkspaceShared       = "workspace.shared"
	
	// Project Events
	EventProjectCreated        = "project.created"
	EventProjectUpdated        = "project.updated"
	EventProjectDeleted        = "project.deleted"
	
	// Base Events
	EventBaseCreated           = "base.created"
	EventBaseUpdated           = "base.updated"
	EventBaseDeleted           = "base.deleted"
	EventBaseSchemaChanged     = "base.schema_changed"
	
	// Permission Events
	EventPermissionGranted     = "permission.granted"
	EventPermissionRevoked     = "permission.revoked"
	EventPermissionUpdated     = "permission.updated"
	
	// SAGA Events
	EventSAGAStarted           = "saga.started"
	EventSAGACompleted         = "saga.completed"
	EventSAGAFailed            = "saga.failed"
	EventSAGACompensated       = "saga.compensated"
	
	// Outbox Events
	EventOutboxMessageCreated  = "outbox.message.created"
	EventOutboxMessagePublished = "outbox.message.published"
	EventOutboxMessageFailed   = "outbox.message.failed"
)

// Test SAGA Types
const (
	SAGATypeUserRegistration    = "user_registration"
	SAGATypeWorkspaceCreation   = "workspace_creation"
	SAGATypePaymentProcessing   = "payment_processing"
	SAGATypeDataMigration       = "data_migration"
	SAGATypeTenantProvisioning  = "tenant_provisioning"
)

// Test Error Codes
const (
	ErrorCodeUnauthorized      = "UNAUTHORIZED"
	ErrorCodeForbidden         = "FORBIDDEN"
	ErrorCodeNotFound          = "NOT_FOUND"
	ErrorCodeValidationFailed  = "VALIDATION_FAILED"
	ErrorCodeTenantSuspended   = "TENANT_SUSPENDED"
	ErrorCodePlanLimitExceeded = "PLAN_LIMIT_EXCEEDED"
	ErrorCodeRateLimitExceeded = "RATE_LIMIT_EXCEEDED"
)

// Test Database Connection Strings
var (
	TestDatabaseURL = "postgres://test_user:test_password@localhost:5432/pyairtable_test?sslmode=disable"
	TestEventsDatabaseURL = "postgres://test_user:test_password@localhost:5433/pyairtable_events_test?sslmode=disable"
	TestRedisURL = "redis://:testpassword@localhost:6379/0"
	TestRedisSessionsURL = "redis://:testpassword@localhost:6380/1"
)

// Test Service URLs
var (
	TestServiceURLs = map[string]string{
		"api-gateway":        "http://localhost:8080",
		"auth-service":       "http://localhost:8083",
		"user-service":       "http://localhost:8084",
		"workspace-service":  "http://localhost:8086",
		"permission-service": "http://localhost:8085",
		"saga-orchestrator":  "http://localhost:8087",
		"prometheus":         "http://localhost:9090",
		"grafana":           "http://localhost:3000",
		"mailhog":           "http://localhost:8025",
	}
)

// Test Kafka Configuration
var (
	TestKafkaConfig = map[string]interface{}{
		"brokers": []string{"localhost:9092"},
		"topics": map[string]interface{}{
			"events":      "pyairtable-events",
			"commands":    "pyairtable-commands",
			"saga-events": "pyairtable-saga-events",
		},
	}
)

// Test Performance Thresholds
var (
	TestPerformanceThresholds = map[string]map[string]interface{}{
		"response_times": {
			"api_gateway": map[string]string{
				"p50": "100ms",
				"p90": "200ms",
				"p95": "300ms",
				"p99": "500ms",
			},
			"auth_service": map[string]string{
				"p50": "50ms",
				"p90": "100ms",
				"p95": "150ms",
				"p99": "250ms",
			},
		},
		"throughput": {
			"api_gateway":  "1000rps",
			"auth_service": "500rps",
			"user_service": "300rps",
		},
		"resource_usage": {
			"memory_max": "80%",
			"cpu_max":    "70%",
			"disk_max":   "85%",
		},
	}
)

// Test Load Testing Configuration
var (
	TestLoadConfig = map[string]interface{}{
		"scenarios": map[string]interface{}{
			"smoke": map[string]interface{}{
				"users":    1,
				"duration": "30s",
				"ramp_up":  "5s",
			},
			"load": map[string]interface{}{
				"users":    10,
				"duration": "2m",
				"ramp_up":  "30s",
			},
			"stress": map[string]interface{}{
				"users":    50,
				"duration": "5m",
				"ramp_up":  "1m",
			},
			"spike": map[string]interface{}{
				"users":    100,
				"duration": "1m",
				"ramp_up":  "10s",
			},
		},
	}
)

// Test Chaos Engineering Configuration
var (
	TestChaosConfig = map[string]interface{}{
		"failure_modes": []string{
			"service_crash",
			"network_partition",
			"high_latency",
			"memory_exhaustion",
			"disk_full",
			"database_timeout",
		},
		"failure_rates": map[string]float64{
			"low":    0.01, // 1%
			"medium": 0.05, // 5%
			"high":   0.10, // 10%
		},
		"recovery_times": map[string]string{
			"fast":   "5s",
			"medium": "30s",
			"slow":   "2m",
		},
	}
)

// Test Security Configuration
var (
	TestSecurityConfig = map[string]interface{}{
		"rate_limiting": map[string]interface{}{
			"requests_per_minute": 100,
			"burst_size":         10,
		},
		"authentication": map[string]interface{}{
			"jwt_expiry":         "1h",
			"refresh_expiry":     "24h",
			"max_login_attempts": 5,
			"lockout_duration":   "15m",
		},
		"encryption": map[string]interface{}{
			"algorithm": "AES-256-GCM",
			"key_size":  256,
		},
	}
)