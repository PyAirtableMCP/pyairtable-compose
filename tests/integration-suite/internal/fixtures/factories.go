package fixtures

import (
	"context"
	"database/sql"
	"fmt"
	"math/rand"
	"time"

	"github.com/google/uuid"
	"github.com/bxcodec/faker/v3"
)

// TestDataFactory provides methods for generating test data
type TestDataFactory struct {
	db     *sql.DB
	random *rand.Rand
}

// NewTestDataFactory creates a new test data factory
func NewTestDataFactory(db *sql.DB) *TestDataFactory {
	return &TestDataFactory{
		db:     db,
		random: rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

// Tenant represents a tenant entity for testing
type Tenant struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Domain      string    `json:"domain"`
	Status      string    `json:"status"`
	PlanType    string    `json:"plan_type"`
	BillingCycle string   `json:"billing_cycle"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	Settings    map[string]interface{} `json:"settings"`
}

// User represents a user entity for testing
type User struct {
	ID        string    `json:"id"`
	TenantID  string    `json:"tenant_id"`
	Email     string    `json:"email"`
	Username  string    `json:"username"`
	FirstName string    `json:"first_name"`
	LastName  string    `json:"last_name"`
	Role      string    `json:"role"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	LastLogin *time.Time `json:"last_login,omitempty"`
	Profile   map[string]interface{} `json:"profile"`
}

// Workspace represents a workspace entity for testing
type Workspace struct {
	ID          string    `json:"id"`
	TenantID    string    `json:"tenant_id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatedBy   string    `json:"created_by"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	Settings    map[string]interface{} `json:"settings"`
}

// Project represents a project entity for testing
type Project struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatedBy   string    `json:"created_by"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// Base represents an Airtable base entity for testing
type Base struct {
	ID        string    `json:"id"`
	ProjectID string    `json:"project_id"`
	Name      string    `json:"name"`
	Type      string    `json:"type"`
	Schema    map[string]interface{} `json:"schema"`
	CreatedBy string    `json:"created_by"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Permission represents a permission entity for testing
type Permission struct {
	ID           string    `json:"id"`
	UserID       string    `json:"user_id"`
	ResourceID   string    `json:"resource_id"`
	ResourceType string    `json:"resource_type"`
	Permission   string    `json:"permission"`
	GrantedBy    string    `json:"granted_by"`
	GrantedAt    time.Time `json:"granted_at"`
	ExpiresAt    *time.Time `json:"expires_at,omitempty"`
}

// FactoryOptions configure data generation
type FactoryOptions struct {
	Count           int
	TenantID        string
	CreatedBy       string
	WithRelations   bool
	CustomData      map[string]interface{}
	TimeRange       *TimeRange
	Status          string
	Locale          string
}

// TimeRange represents a time range for generating timestamps
type TimeRange struct {
	Start time.Time
	End   time.Time
}

// DefaultFactoryOptions returns default factory options
func DefaultFactoryOptions() *FactoryOptions {
	return &FactoryOptions{
		Count:         1,
		WithRelations: false,
		CustomData:    make(map[string]interface{}),
		TimeRange: &TimeRange{
			Start: time.Now().Add(-30 * 24 * time.Hour), // 30 days ago
			End:   time.Now(),
		},
		Status: "active",
		Locale: "en",
	}
}

// CreateTenant generates a test tenant
func (f *TestDataFactory) CreateTenant(opts *FactoryOptions) *Tenant {
	if opts == nil {
		opts = DefaultFactoryOptions()
	}

	tenant := &Tenant{
		ID:       uuid.New().String(),
		Name:     faker.CompanyName(),
		Domain:   fmt.Sprintf("%s.test.pyairtable.com", faker.Username()),
		Status:   opts.Status,
		PlanType: f.randomPlanType(),
		BillingCycle: f.randomBillingCycle(),
		CreatedAt: f.randomTimeInRange(opts.TimeRange),
		UpdatedAt: time.Now(),
		Settings: map[string]interface{}{
			"timezone":        "UTC",
			"date_format":     "MM/DD/YYYY",
			"currency":        "USD",
			"notifications":   true,
			"api_access":      true,
			"max_workspaces":  f.randomBetween(5, 50),
			"max_users":       f.randomBetween(10, 1000),
		},
	}

	// Apply custom data
	f.applyCustomData(tenant, opts.CustomData)

	return tenant
}

// CreateUser generates a test user
func (f *TestDataFactory) CreateUser(opts *FactoryOptions) *User {
	if opts == nil {
		opts = DefaultFactoryOptions()
	}

	firstName := faker.FirstName()
	lastName := faker.LastName()
	username := fmt.Sprintf("%s%s%d", 
		firstName[:1], 
		lastName, 
		f.randomBetween(1, 9999))

	user := &User{
		ID:        uuid.New().String(),
		TenantID:  opts.TenantID,
		Email:     faker.Email(),
		Username:  username,
		FirstName: firstName,
		LastName:  lastName,
		Role:      f.randomUserRole(),
		Status:    opts.Status,
		CreatedAt: f.randomTimeInRange(opts.TimeRange),
		UpdatedAt: time.Now(),
		Profile: map[string]interface{}{
			"avatar_url":     fmt.Sprintf("https://example.com/avatars/%s.jpg", username),
			"bio":           faker.Sentence(),
			"phone":         faker.Phonenumber(),
			"company":       faker.CompanyName(),
			"job_title":     faker.JobDescriptor(),
			"location":      faker.GetRealAddress().City,
			"preferences": map[string]interface{}{
				"theme":           f.randomChoice([]string{"light", "dark", "auto"}),
				"language":        opts.Locale,
				"notifications":   true,
				"weekly_digest":   f.randomBool(),
			},
		},
	}

	// Set last login for active users
	if user.Status == "active" && f.randomBool() {
		lastLogin := f.randomTimeInRange(&TimeRange{
			Start: time.Now().Add(-7 * 24 * time.Hour),
			End:   time.Now(),
		})
		user.LastLogin = &lastLogin
	}

	// Apply custom data
	f.applyCustomData(user, opts.CustomData)

	return user
}

// CreateWorkspace generates a test workspace
func (f *TestDataFactory) CreateWorkspace(opts *FactoryOptions) *Workspace {
	if opts == nil {
		opts = DefaultFactoryOptions()
	}

	workspace := &Workspace{
		ID:          uuid.New().String(),
		TenantID:    opts.TenantID,
		Name:        fmt.Sprintf("%s %s", faker.CompanyName(), f.randomWorkspaceType()),
		Description: faker.Paragraph(),
		CreatedBy:   opts.CreatedBy,
		Status:      opts.Status,
		CreatedAt:   f.randomTimeInRange(opts.TimeRange),
		UpdatedAt:   time.Now(),
		Settings: map[string]interface{}{
			"visibility":      f.randomChoice([]string{"private", "team", "public"}),
			"collaboration":   true,
			"version_control": f.randomBool(),
			"backup_enabled":  true,
			"max_projects":    f.randomBetween(10, 100),
			"templates": map[string]interface{}{
				"enabled":        true,
				"custom_allowed": f.randomBool(),
			},
			"integrations": []string{
				f.randomChoice([]string{"slack", "teams", "discord"}),
				f.randomChoice([]string{"zapier", "integromat", "automate"}),
			},
		},
	}

	// Apply custom data
	f.applyCustomData(workspace, opts.CustomData)

	return workspace
}

// CreateProject generates a test project
func (f *TestDataFactory) CreateProject(opts *FactoryOptions) *Project {
	if opts == nil {
		opts = DefaultFactoryOptions()
	}

	project := &Project{
		ID:          uuid.New().String(),
		WorkspaceID: opts.CustomData["workspace_id"].(string),
		Name:        fmt.Sprintf("%s %s", f.randomProjectType(), faker.JobDescriptor()),
		Description: faker.Paragraph(),
		CreatedBy:   opts.CreatedBy,
		Status:      opts.Status,
		CreatedAt:   f.randomTimeInRange(opts.TimeRange),
		UpdatedAt:   time.Now(),
	}

	// Apply custom data
	f.applyCustomData(project, opts.CustomData)

	return project
}

// CreateBase generates a test Airtable base
func (f *TestDataFactory) CreateBase(opts *FactoryOptions) *Base {
	if opts == nil {
		opts = DefaultFactoryOptions()
	}

	baseType := f.randomBaseType()
	
	base := &Base{
		ID:        uuid.New().String(),
		ProjectID: opts.CustomData["project_id"].(string),
		Name:      fmt.Sprintf("%s %s", baseType, faker.JobDescriptor()),
		Type:      baseType,
		Schema:    f.generateBaseSchema(baseType),
		CreatedBy: opts.CreatedBy,
		Status:    opts.Status,
		CreatedAt: f.randomTimeInRange(opts.TimeRange),
		UpdatedAt: time.Now(),
	}

	// Apply custom data
	f.applyCustomData(base, opts.CustomData)

	return base
}

// CreatePermission generates a test permission
func (f *TestDataFactory) CreatePermission(opts *FactoryOptions) *Permission {
	if opts == nil {
		opts = DefaultFactoryOptions()
	}

	permission := &Permission{
		ID:           uuid.New().String(),
		UserID:       opts.CustomData["user_id"].(string),
		ResourceID:   opts.CustomData["resource_id"].(string),
		ResourceType: opts.CustomData["resource_type"].(string),
		Permission:   f.randomPermissionLevel(opts.CustomData["resource_type"].(string)),
		GrantedBy:    opts.GrantedBy,
		GrantedAt:    f.randomTimeInRange(opts.TimeRange),
	}

	// Set expiration for temporary permissions
	if f.randomBool() && f.randomFloat() < 0.1 { // 10% chance of expiring permission
		expiration := time.Now().Add(time.Duration(f.randomBetween(1, 365)) * 24 * time.Hour)
		permission.ExpiresAt = &expiration
	}

	// Apply custom data
	f.applyCustomData(permission, opts.CustomData)

	return permission
}

// CreateTestDataSet creates a complete set of related test data
func (f *TestDataFactory) CreateTestDataSet(ctx context.Context, opts *DataSetOptions) (*TestDataSet, error) {
	if opts == nil {
		opts = DefaultDataSetOptions()
	}

	dataSet := &TestDataSet{
		Tenants:     make([]*Tenant, 0),
		Users:       make([]*User, 0),
		Workspaces:  make([]*Workspace, 0),
		Projects:    make([]*Project, 0),
		Bases:       make([]*Base, 0),
		Permissions: make([]*Permission, 0),
	}

	// Create tenants
	for i := 0; i < opts.TenantCount; i++ {
		tenant := f.CreateTenant(&FactoryOptions{
			Status: "active",
			TimeRange: &TimeRange{
				Start: time.Now().Add(-365 * 24 * time.Hour),
				End:   time.Now().Add(-30 * 24 * time.Hour),
			},
		})
		dataSet.Tenants = append(dataSet.Tenants, tenant)

		// Create users for this tenant
		for j := 0; j < opts.UsersPerTenant; j++ {
			user := f.CreateUser(&FactoryOptions{
				TenantID: tenant.ID,
				Status:   "active",
				TimeRange: &TimeRange{
					Start: tenant.CreatedAt.Add(time.Hour),
					End:   time.Now(),
				},
			})
			dataSet.Users = append(dataSet.Users, user)
		}

		// Create workspaces for this tenant
		tenantUsers := f.getUsersForTenant(dataSet.Users, tenant.ID)
		for j := 0; j < opts.WorkspacesPerTenant; j++ {
			createdBy := tenantUsers[f.randomBetween(0, len(tenantUsers)-1)].ID
			
			workspace := f.CreateWorkspace(&FactoryOptions{
				TenantID:  tenant.ID,
				CreatedBy: createdBy,
				Status:    "active",
				TimeRange: &TimeRange{
					Start: tenant.CreatedAt.Add(24 * time.Hour),
					End:   time.Now(),
				},
			})
			dataSet.Workspaces = append(dataSet.Workspaces, workspace)

			// Create projects for this workspace
			for k := 0; k < opts.ProjectsPerWorkspace; k++ {
				project := f.CreateProject(&FactoryOptions{
					CreatedBy: createdBy,
					Status:    "active",
					CustomData: map[string]interface{}{
						"workspace_id": workspace.ID,
					},
					TimeRange: &TimeRange{
						Start: workspace.CreatedAt.Add(time.Hour),
						End:   time.Now(),
					},
				})
				dataSet.Projects = append(dataSet.Projects, project)

				// Create bases for this project
				for l := 0; l < opts.BasesPerProject; l++ {
					base := f.CreateBase(&FactoryOptions{
						CreatedBy: createdBy,
						Status:    "active",
						CustomData: map[string]interface{}{
							"project_id": project.ID,
						},
						TimeRange: &TimeRange{
							Start: project.CreatedAt.Add(time.Hour),
							End:   time.Now(),
						},
					})
					dataSet.Bases = append(dataSet.Bases, base)
				}
			}

			// Create permissions for workspace users
			for _, user := range tenantUsers {
				if user.ID == createdBy {
					// Creator gets admin permission
					permission := f.CreatePermission(&FactoryOptions{
						CustomData: map[string]interface{}{
							"user_id":       user.ID,
							"resource_id":   workspace.ID,
							"resource_type": "workspace",
						},
						GrantedBy: createdBy,
						TimeRange: &TimeRange{
							Start: workspace.CreatedAt,
							End:   workspace.CreatedAt.Add(time.Hour),
						},
					})
					permission.Permission = "admin"
					dataSet.Permissions = append(dataSet.Permissions, permission)
				} else if f.randomFloat() < 0.7 { // 70% chance other users get some permission
					permission := f.CreatePermission(&FactoryOptions{
						CustomData: map[string]interface{}{
							"user_id":       user.ID,
							"resource_id":   workspace.ID,
							"resource_type": "workspace",
						},
						GrantedBy: createdBy,
						TimeRange: &TimeRange{
							Start: workspace.CreatedAt.Add(time.Hour),
							End:   time.Now(),
						},
					})
					dataSet.Permissions = append(dataSet.Permissions, permission)
				}
			}
		}
	}

	return dataSet, nil
}

// Helper methods for random data generation
func (f *TestDataFactory) randomPlanType() string {
	plans := []string{"free", "pro", "enterprise", "custom"}
	return plans[f.random.Intn(len(plans))]
}

func (f *TestDataFactory) randomBillingCycle() string {
	cycles := []string{"monthly", "annual"}
	return cycles[f.random.Intn(len(cycles))]
}

func (f *TestDataFactory) randomUserRole() string {
	roles := []string{
		"tenant_admin", "workspace_admin", "project_admin", 
		"editor", "viewer", "collaborator", "guest",
	}
	return roles[f.random.Intn(len(roles))]
}

func (f *TestDataFactory) randomWorkspaceType() string {
	types := []string{
		"Project Management", "CRM", "Marketing", "Sales",
		"Operations", "HR", "Finance", "Development",
		"Analytics", "Research", "Design", "Support",
	}
	return types[f.random.Intn(len(types))]
}

func (f *TestDataFactory) randomProjectType() string {
	types := []string{
		"Campaign", "Product", "Initiative", "Program",
		"Research", "Development", "Marketing", "Operations",
	}
	return types[f.random.Intn(len(types))]
}

func (f *TestDataFactory) randomBaseType() string {
	types := []string{
		"standard", "analytics", "crm", "marketing", 
		"project_management", "inventory", "hr", "finance",
	}
	return types[f.random.Intn(len(types))]
}

func (f *TestDataFactory) randomPermissionLevel(resourceType string) string {
	switch resourceType {
	case "workspace":
		levels := []string{"admin", "editor", "viewer"}
		return levels[f.random.Intn(len(levels))]
	case "project":
		levels := []string{"admin", "editor", "contributor", "viewer"}
		return levels[f.random.Intn(len(levels))]
	case "base":
		levels := []string{"admin", "editor", "commenter", "reader"}
		return levels[f.random.Intn(len(levels))]
	default:
		return "viewer"
	}
}

func (f *TestDataFactory) randomChoice(choices []string) string {
	return choices[f.random.Intn(len(choices))]
}

func (f *TestDataFactory) randomBool() bool {
	return f.random.Float32() < 0.5
}

func (f *TestDataFactory) randomFloat() float64 {
	return f.random.Float64()
}

func (f *TestDataFactory) randomBetween(min, max int) int {
	return min + f.random.Intn(max-min+1)
}

func (f *TestDataFactory) randomTimeInRange(timeRange *TimeRange) time.Time {
	if timeRange == nil {
		return time.Now().Add(-time.Duration(f.randomBetween(1, 365)) * 24 * time.Hour)
	}
	
	diff := timeRange.End.Unix() - timeRange.Start.Unix()
	randomSeconds := f.random.Int63n(diff)
	return timeRange.Start.Add(time.Duration(randomSeconds) * time.Second)
}

func (f *TestDataFactory) generateBaseSchema(baseType string) map[string]interface{} {
	switch baseType {
	case "crm":
		return map[string]interface{}{
			"tables": []map[string]interface{}{
				{
					"name": "Contacts",
					"fields": []map[string]interface{}{
						{"name": "Name", "type": "singleLineText"},
						{"name": "Email", "type": "email"},
						{"name": "Phone", "type": "phoneNumber"},
						{"name": "Company", "type": "singleLineText"},
						{"name": "Status", "type": "singleSelect"},
					},
				},
				{
					"name": "Companies",
					"fields": []map[string]interface{}{
						{"name": "Name", "type": "singleLineText"},
						{"name": "Industry", "type": "singleSelect"},
						{"name": "Size", "type": "number"},
					},
				},
			},
		}
	case "marketing":
		return map[string]interface{}{
			"tables": []map[string]interface{}{
				{
					"name": "Campaigns",
					"fields": []map[string]interface{}{
						{"name": "Name", "type": "singleLineText"},
						{"name": "Status", "type": "singleSelect"},
						{"name": "Budget", "type": "currency"},
						{"name": "Start Date", "type": "date"},
						{"name": "End Date", "type": "date"},
					},
				},
			},
		}
	default:
		return map[string]interface{}{
			"tables": []map[string]interface{}{
				{
					"name": "Main",
					"fields": []map[string]interface{}{
						{"name": "Name", "type": "singleLineText"},
						{"name": "Status", "type": "singleSelect"},
						{"name": "Created", "type": "dateTime"},
					},
				},
			},
		}
	}
}

func (f *TestDataFactory) applyCustomData(entity interface{}, customData map[string]interface{}) {
	// This would apply custom data to the entity
	// Implementation depends on reflection or type assertions
}

func (f *TestDataFactory) getUsersForTenant(users []*User, tenantID string) []*User {
	var tenantUsers []*User
	for _, user := range users {
		if user.TenantID == tenantID {
			tenantUsers = append(tenantUsers, user)
		}
	}
	return tenantUsers
}

// DataSetOptions configure test data set generation
type DataSetOptions struct {
	TenantCount           int
	UsersPerTenant        int
	WorkspacesPerTenant   int
	ProjectsPerWorkspace  int
	BasesPerProject       int
	GeneratePermissions   bool
	GenerateAuditTrail    bool
	GenerateAnalytics     bool
}

// DefaultDataSetOptions returns default data set options
func DefaultDataSetOptions() *DataSetOptions {
	return &DataSetOptions{
		TenantCount:          2,
		UsersPerTenant:       5,
		WorkspacesPerTenant:  3,
		ProjectsPerWorkspace: 2,
		BasesPerProject:      2,
		GeneratePermissions:  true,
		GenerateAuditTrail:   false,
		GenerateAnalytics:    false,
	}
}

// TestDataSet represents a complete set of test data
type TestDataSet struct {
	Tenants     []*Tenant     `json:"tenants"`
	Users       []*User       `json:"users"`
	Workspaces  []*Workspace  `json:"workspaces"`
	Projects    []*Project    `json:"projects"`
	Bases       []*Base       `json:"bases"`
	Permissions []*Permission `json:"permissions"`
}

// Persist saves the test data set to the database
func (ds *TestDataSet) Persist(ctx context.Context, db *sql.DB) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Insert tenants
	for _, tenant := range ds.Tenants {
		if err := ds.insertTenant(tx, tenant); err != nil {
			return fmt.Errorf("failed to insert tenant %s: %w", tenant.ID, err)
		}
	}

	// Insert users
	for _, user := range ds.Users {
		if err := ds.insertUser(tx, user); err != nil {
			return fmt.Errorf("failed to insert user %s: %w", user.ID, err)
		}
	}

	// Insert workspaces
	for _, workspace := range ds.Workspaces {
		if err := ds.insertWorkspace(tx, workspace); err != nil {
			return fmt.Errorf("failed to insert workspace %s: %w", workspace.ID, err)
		}
	}

	// Insert projects
	for _, project := range ds.Projects {
		if err := ds.insertProject(tx, project); err != nil {
			return fmt.Errorf("failed to insert project %s: %w", project.ID, err)
		}
	}

	// Insert bases
	for _, base := range ds.Bases {
		if err := ds.insertBase(tx, base); err != nil {
			return fmt.Errorf("failed to insert base %s: %w", base.ID, err)
		}
	}

	// Insert permissions
	for _, permission := range ds.Permissions {
		if err := ds.insertPermission(tx, permission); err != nil {
			return fmt.Errorf("failed to insert permission %s: %w", permission.ID, err)
		}
	}

	return tx.Commit()
}

// Database insertion methods
func (ds *TestDataSet) insertTenant(tx *sql.Tx, tenant *Tenant) error {
	query := `
		INSERT INTO tenants (id, name, domain, status, plan_type, billing_cycle, created_at, updated_at, settings)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`
	_, err := tx.Exec(query, tenant.ID, tenant.Name, tenant.Domain, tenant.Status, 
		tenant.PlanType, tenant.BillingCycle, tenant.CreatedAt, tenant.UpdatedAt, 
		fmt.Sprintf("%v", tenant.Settings))
	return err
}

func (ds *TestDataSet) insertUser(tx *sql.Tx, user *User) error {
	query := `
		INSERT INTO users (id, tenant_id, email, username, first_name, last_name, role, status, created_at, updated_at, last_login, profile)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
	`
	_, err := tx.Exec(query, user.ID, user.TenantID, user.Email, user.Username,
		user.FirstName, user.LastName, user.Role, user.Status, user.CreatedAt,
		user.UpdatedAt, user.LastLogin, fmt.Sprintf("%v", user.Profile))
	return err
}

func (ds *TestDataSet) insertWorkspace(tx *sql.Tx, workspace *Workspace) error {
	query := `
		INSERT INTO workspaces (id, tenant_id, name, description, created_by, status, created_at, updated_at, settings)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`
	_, err := tx.Exec(query, workspace.ID, workspace.TenantID, workspace.Name,
		workspace.Description, workspace.CreatedBy, workspace.Status,
		workspace.CreatedAt, workspace.UpdatedAt, fmt.Sprintf("%v", workspace.Settings))
	return err
}

func (ds *TestDataSet) insertProject(tx *sql.Tx, project *Project) error {
	query := `
		INSERT INTO projects (id, workspace_id, name, description, created_by, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`
	_, err := tx.Exec(query, project.ID, project.WorkspaceID, project.Name,
		project.Description, project.CreatedBy, project.Status,
		project.CreatedAt, project.UpdatedAt)
	return err
}

func (ds *TestDataSet) insertBase(tx *sql.Tx, base *Base) error {
	query := `
		INSERT INTO bases (id, project_id, name, type, schema, created_by, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`
	_, err := tx.Exec(query, base.ID, base.ProjectID, base.Name, base.Type,
		fmt.Sprintf("%v", base.Schema), base.CreatedBy, base.Status,
		base.CreatedAt, base.UpdatedAt)
	return err
}

func (ds *TestDataSet) insertPermission(tx *sql.Tx, permission *Permission) error {
	query := `
		INSERT INTO permissions (id, user_id, resource_id, resource_type, permission, granted_by, granted_at, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`
	_, err := tx.Exec(query, permission.ID, permission.UserID, permission.ResourceID,
		permission.ResourceType, permission.Permission, permission.GrantedBy,
		permission.GrantedAt, permission.ExpiresAt)
	return err
}