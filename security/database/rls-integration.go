// Go Integration Library for Row-Level Security
// Multi-tenant database access with automatic tenant isolation
// Security implementation for 3vantage organization

package database

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	"go.uber.org/zap"
)

// TenantContext holds tenant and user information for RLS
type TenantContext struct {
	TenantID uuid.UUID
	UserID   uuid.UUID
	Role     string
	IP       string
}

// DatabaseManager handles multi-tenant database operations with RLS
type DatabaseManager struct {
	db     *sqlx.DB
	logger *zap.Logger
}

// NewDatabaseManager creates a new database manager with RLS support
func NewDatabaseManager(connectionString string, logger *zap.Logger) (*DatabaseManager, error) {
	db, err := sqlx.Connect("postgres", connectionString)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// Configure connection pool for security
	db.SetMaxOpenConns(50)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Test connection
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	if logger == nil {
		logger = zap.NewNop()
	}

	logger.Info("Database manager initialized with RLS support")

	return &DatabaseManager{
		db:     db,
		logger: logger,
	}, nil
}

// SetTenantContext sets the tenant context for RLS enforcement
func (dm *DatabaseManager) SetTenantContext(ctx context.Context, tenantCtx TenantContext) error {
	tx, err := dm.db.BeginTxx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Set session variables for RLS
	queries := []string{
		fmt.Sprintf("SET LOCAL app.current_tenant_id = '%s'", tenantCtx.TenantID),
		fmt.Sprintf("SET LOCAL app.current_user_id = '%s'", tenantCtx.UserID),
		fmt.Sprintf("SET LOCAL app.current_user_role = '%s'", tenantCtx.Role),
		fmt.Sprintf("SET LOCAL app.client_ip = '%s'", tenantCtx.IP),
	}

	for _, query := range queries {
		if _, err := tx.ExecContext(ctx, query); err != nil {
			return fmt.Errorf("failed to set session variable: %w", err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit session setup: %w", err)
	}

	dm.logger.Debug("Tenant context set successfully",
		zap.String("tenant_id", tenantCtx.TenantID.String()),
		zap.String("user_id", tenantCtx.UserID.String()),
		zap.String("role", tenantCtx.Role),
	)

	return nil
}

// WithTenantContext creates a new context with tenant information
func WithTenantContext(ctx context.Context, tenantID, userID uuid.UUID, role, ip string) context.Context {
	tenantCtx := TenantContext{
		TenantID: tenantID,
		UserID:   userID,
		Role:     role,
		IP:       ip,
	}
	return context.WithValue(ctx, "tenant_context", tenantCtx)
}

// GetTenantContext extracts tenant context from context
func GetTenantContext(ctx context.Context) (TenantContext, bool) {
	tenantCtx, ok := ctx.Value("tenant_context").(TenantContext)
	return tenantCtx, ok
}

// TenantAwareQuery executes a query with automatic tenant context setup
func (dm *DatabaseManager) TenantAwareQuery(ctx context.Context, query string, args ...interface{}) (*sqlx.Rows, error) {
	tenantCtx, ok := GetTenantContext(ctx)
	if !ok {
		return nil, fmt.Errorf("tenant context not found in request context")
	}

	// Begin transaction for session variable isolation
	tx, err := dm.db.BeginTxx(ctx, &sql.TxOptions{
		Isolation: sql.LevelReadCommitted,
		ReadOnly:  true,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}

	// Set tenant context
	if err := dm.setTenantContextInTx(ctx, tx, tenantCtx); err != nil {
		tx.Rollback()
		return nil, err
	}

	// Execute query
	rows, err := tx.QueryxContext(ctx, query, args...)
	if err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to execute query: %w", err)
	}

	// Note: Transaction will be committed when rows are closed
	// This is handled by the caller or through a wrapper

	dm.logger.Debug("Tenant-aware query executed",
		zap.String("tenant_id", tenantCtx.TenantID.String()),
		zap.String("query", query),
	)

	return rows, nil
}

// TenantAwareExec executes a command with automatic tenant context setup
func (dm *DatabaseManager) TenantAwareExec(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	tenantCtx, ok := GetTenantContext(ctx)
	if !ok {
		return nil, fmt.Errorf("tenant context not found in request context")
	}

	tx, err := dm.db.BeginTxx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Set tenant context
	if err := dm.setTenantContextInTx(ctx, tx, tenantCtx); err != nil {
		return nil, err
	}

	// Execute command
	result, err := tx.ExecContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to execute command: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	dm.logger.Info("Tenant-aware command executed",
		zap.String("tenant_id", tenantCtx.TenantID.String()),
		zap.String("command", strings.Split(query, " ")[0]),
	)

	return result, nil
}

// setTenantContextInTx sets tenant context within a transaction
func (dm *DatabaseManager) setTenantContextInTx(ctx context.Context, tx *sqlx.Tx, tenantCtx TenantContext) error {
	queries := []string{
		fmt.Sprintf("SET LOCAL app.current_tenant_id = '%s'", tenantCtx.TenantID),
		fmt.Sprintf("SET LOCAL app.current_user_id = '%s'", tenantCtx.UserID),
		fmt.Sprintf("SET LOCAL app.current_user_role = '%s'", tenantCtx.Role),
		fmt.Sprintf("SET LOCAL app.client_ip = '%s'", tenantCtx.IP),
	}

	for _, query := range queries {
		if _, err := tx.ExecContext(ctx, query); err != nil {
			return fmt.Errorf("failed to set session variable: %w", err)
		}
	}

	return nil
}

// Tenant represents a tenant in the system
type Tenant struct {
	ID              uuid.UUID              `db:"id" json:"id"`
	Name            string                 `db:"name" json:"name"`
	Slug            string                 `db:"slug" json:"slug"`
	Status          string                 `db:"status" json:"status"`
	Tier            string                 `db:"tier" json:"tier"`
	MaxUsers        int                    `db:"max_users" json:"max_users"`
	MaxWorkspaces   int                    `db:"max_workspaces" json:"max_workspaces"`
	MaxStorageGB    int                    `db:"max_storage_gb" json:"max_storage_gb"`
	EncryptionKeyID string                 `db:"encryption_key_id" json:"encryption_key_id"`
	CreatedAt       time.Time              `db:"created_at" json:"created_at"`
	UpdatedAt       time.Time              `db:"updated_at" json:"updated_at"`
	SecuritySettings map[string]interface{} `db:"security_settings" json:"security_settings"`
}

// User represents a user within a tenant
type User struct {
	ID                   uuid.UUID  `db:"id" json:"id"`
	TenantID             uuid.UUID  `db:"tenant_id" json:"tenant_id"`
	Email                string     `db:"email" json:"email"`
	Username             *string    `db:"username" json:"username,omitempty"`
	PasswordHash         string     `db:"password_hash" json:"-"`
	FirstName            *string    `db:"first_name" json:"first_name,omitempty"`
	LastName             *string    `db:"last_name" json:"last_name,omitempty"`
	Status               string     `db:"status" json:"status"`
	EmailVerified        bool       `db:"email_verified" json:"email_verified"`
	MFAEnabled           bool       `db:"mfa_enabled" json:"mfa_enabled"`
	LastLogin            *time.Time `db:"last_login" json:"last_login,omitempty"`
	FailedLoginAttempts  int        `db:"failed_login_attempts" json:"failed_login_attempts"`
	LockedUntil          *time.Time `db:"locked_until" json:"locked_until,omitempty"`
	CreatedAt            time.Time  `db:"created_at" json:"created_at"`
	UpdatedAt            time.Time  `db:"updated_at" json:"updated_at"`
}

// Workspace represents a workspace within a tenant
type Workspace struct {
	ID          uuid.UUID              `db:"id" json:"id"`
	TenantID    uuid.UUID              `db:"tenant_id" json:"tenant_id"`
	Name        string                 `db:"name" json:"name"`
	Description *string                `db:"description" json:"description,omitempty"`
	OwnerID     uuid.UUID              `db:"owner_id" json:"owner_id"`
	Settings    map[string]interface{} `db:"settings" json:"settings"`
	Status      string                 `db:"status" json:"status"`
	CreatedAt   time.Time              `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time              `db:"updated_at" json:"updated_at"`
}

// TenantService provides tenant-aware database operations
type TenantService struct {
	dm *DatabaseManager
}

// NewTenantService creates a new tenant service
func NewTenantService(dm *DatabaseManager) *TenantService {
	return &TenantService{dm: dm}
}

// GetTenantByID retrieves a tenant by ID (admin only)
func (ts *TenantService) GetTenantByID(ctx context.Context, tenantID uuid.UUID) (*Tenant, error) {
	query := `
		SELECT id, name, slug, status, tier, max_users, max_workspaces, max_storage_gb,
		       encryption_key_id, created_at, updated_at, security_settings
		FROM tenant_management.tenants
		WHERE id = $1
	`

	var tenant Tenant
	err := ts.dm.db.GetContext(ctx, &tenant, query, tenantID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("tenant not found: %s", tenantID)
		}
		return nil, fmt.Errorf("failed to get tenant: %w", err)
	}

	return &tenant, nil
}

// CreateTenant creates a new tenant with owner user
func (ts *TenantService) CreateTenant(ctx context.Context, name, slug, ownerEmail, ownerPassword, tier string) (*Tenant, error) {
	query := `
		SELECT tenant_management.create_tenant($1, $2, $3, $4, $5)
	`

	var tenantID uuid.UUID
	err := ts.dm.db.GetContext(ctx, &tenantID, query, name, slug, ownerEmail, ownerPassword, tier)
	if err != nil {
		return nil, fmt.Errorf("failed to create tenant: %w", err)
	}

	return ts.GetTenantByID(ctx, tenantID)
}

// UserService provides user-related database operations with RLS
type UserService struct {
	dm *DatabaseManager
}

// NewUserService creates a new user service
func NewUserService(dm *DatabaseManager) *UserService {
	return &UserService{dm: dm}
}

// GetUsers retrieves users for the current tenant
func (us *UserService) GetUsers(ctx context.Context, limit, offset int) ([]User, error) {
	query := `
		SELECT id, tenant_id, email, username, first_name, last_name, status,
		       email_verified, mfa_enabled, last_login, failed_login_attempts,
		       locked_until, created_at, updated_at
		FROM public.users
		ORDER BY created_at DESC
		LIMIT $1 OFFSET $2
	`

	rows, err := us.dm.TenantAwareQuery(ctx, query, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to query users: %w", err)
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var user User
		if err := rows.StructScan(&user); err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}
		users = append(users, user)
	}

	return users, nil
}

// CreateUser creates a new user in the current tenant
func (us *UserService) CreateUser(ctx context.Context, email, passwordHash string) (*User, error) {
	tenantCtx, ok := GetTenantContext(ctx)
	if !ok {
		return nil, fmt.Errorf("tenant context required")
	}

	query := `
		INSERT INTO public.users (tenant_id, email, password_hash, status, email_verified)
		VALUES ($1, $2, $3, 'active', false)
		RETURNING id, tenant_id, email, username, first_name, last_name, status,
		          email_verified, mfa_enabled, last_login, failed_login_attempts,
		          locked_until, created_at, updated_at
	`

	var user User
	err := us.dm.db.GetContext(ctx, &user, query, tenantCtx.TenantID, email, passwordHash)
	if err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	return &user, nil
}

// WorkspaceService provides workspace-related database operations with RLS
type WorkspaceService struct {
	dm *DatabaseManager
}

// NewWorkspaceService creates a new workspace service
func NewWorkspaceService(dm *DatabaseManager) *WorkspaceService {
	return &WorkspaceService{dm: dm}
}

// GetWorkspaces retrieves workspaces for the current tenant
func (ws *WorkspaceService) GetWorkspaces(ctx context.Context, limit, offset int) ([]Workspace, error) {
	query := `
		SELECT id, tenant_id, name, description, owner_id, settings, status,
		       created_at, updated_at
		FROM public.workspaces
		WHERE status = 'active'
		ORDER BY created_at DESC
		LIMIT $1 OFFSET $2
	`

	rows, err := ws.dm.TenantAwareQuery(ctx, query, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to query workspaces: %w", err)
	}
	defer rows.Close()

	var workspaces []Workspace
	for rows.Next() {
		var workspace Workspace
		if err := rows.StructScan(&workspace); err != nil {
			return nil, fmt.Errorf("failed to scan workspace: %w", err)
		}
		workspaces = append(workspaces, workspace)
	}

	return workspaces, nil
}

// CreateWorkspace creates a new workspace in the current tenant
func (ws *WorkspaceService) CreateWorkspace(ctx context.Context, name, description string) (*Workspace, error) {
	tenantCtx, ok := GetTenantContext(ctx)
	if !ok {
		return nil, fmt.Errorf("tenant context required")
	}

	query := `
		INSERT INTO public.workspaces (tenant_id, name, description, owner_id, status)
		VALUES ($1, $2, $3, $4, 'active')
		RETURNING id, tenant_id, name, description, owner_id, settings, status,
		          created_at, updated_at
	`

	var workspace Workspace
	err := ws.dm.db.GetContext(ctx, &workspace, query, tenantCtx.TenantID, name, description, tenantCtx.UserID)
	if err != nil {
		return nil, fmt.Errorf("failed to create workspace: %w", err)
	}

	return &workspace, nil
}

// SecurityService provides security-related operations
type SecurityService struct {
	dm *DatabaseManager
}

// NewSecurityService creates a new security service
func NewSecurityService(dm *DatabaseManager) *SecurityService {
	return &SecurityService{dm: dm}
}

// ValidateTenantIsolation validates that tenant isolation is working correctly
func (ss *SecurityService) ValidateTenantIsolation(ctx context.Context, testTenantID uuid.UUID) (map[string]int64, error) {
	query := `
		SELECT table_name, record_count
		FROM security.validate_tenant_isolation($1)
	`

	rows, err := ss.dm.db.QueryxContext(ctx, query, testTenantID)
	if err != nil {
		return nil, fmt.Errorf("failed to validate tenant isolation: %w", err)
	}
	defer rows.Close()

	results := make(map[string]int64)
	for rows.Next() {
		var tableName string
		var recordCount int64
		if err := rows.Scan(&tableName, &recordCount); err != nil {
			return nil, fmt.Errorf("failed to scan validation result: %w", err)
		}
		results[tableName] = recordCount
	}

	return results, nil
}

// LogSecurityEvent logs a security event to the audit log
func (ss *SecurityService) LogSecurityEvent(ctx context.Context, eventType, action, result string, details map[string]interface{}) error {
	tenantCtx, ok := GetTenantContext(ctx)
	if !ok {
		return fmt.Errorf("tenant context required for security logging")
	}

	query := `
		INSERT INTO security_audit.audit_log (
			tenant_id, user_id, event_type, action, result, ip_address, details
		) VALUES ($1, $2, $3, $4, $5, $6, $7)
	`

	detailsJSON, _ := json.Marshal(details)
	_, err := ss.dm.db.ExecContext(ctx, query,
		tenantCtx.TenantID, tenantCtx.UserID, eventType, action, result,
		tenantCtx.IP, string(detailsJSON))

	if err != nil {
		return fmt.Errorf("failed to log security event: %w", err)
	}

	return nil
}

// Close closes the database connection
func (dm *DatabaseManager) Close() error {
	if dm.db != nil {
		return dm.db.Close()
	}
	return nil
}

// Example usage function
func ExampleUsage() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	// Initialize database manager
	dm, err := NewDatabaseManager("postgres://user:pass@localhost/pyairtable?sslmode=require", logger)
	if err != nil {
		log.Fatal("Failed to initialize database manager:", err)
	}
	defer dm.Close()

	// Create services
	userService := NewUserService(dm)
	workspaceService := NewWorkspaceService(dm)

	// Create context with tenant information
	tenantID := uuid.New()
	userID := uuid.New()
	ctx := WithTenantContext(context.Background(), tenantID, userID, "admin", "192.168.1.100")

	// Get users (automatically filtered by tenant)
	users, err := userService.GetUsers(ctx, 10, 0)
	if err != nil {
		log.Printf("Failed to get users: %v", err)
		return
	}

	log.Printf("Retrieved %d users for tenant %s", len(users), tenantID)

	// Create workspace (automatically associated with tenant)
	workspace, err := workspaceService.CreateWorkspace(ctx, "My Workspace", "A test workspace")
	if err != nil {
		log.Printf("Failed to create workspace: %v", err)
		return
	}

	log.Printf("Created workspace %s for tenant %s", workspace.Name, workspace.TenantID)
}