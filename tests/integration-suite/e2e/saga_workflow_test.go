package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"github.com/google/uuid"

	"github.com/pyairtable-compose/tests/integration-suite/internal/framework"
	"github.com/pyairtable-compose/tests/integration-suite/internal/fixtures"
	"github.com/pyairtable-compose/tests/integration-suite/internal/mocks"
)

// SAGAWorkflowTestSuite tests end-to-end SAGA workflow orchestration
type SAGAWorkflowTestSuite struct {
	suite.Suite
	framework    *framework.TestFramework
	sagaOrch     *framework.SAGAOrchestrator
	eventStore   *framework.EventStore
	outboxMonitor *framework.OutboxMonitor
}

func (s *SAGAWorkflowTestSuite) SetupSuite() {
	s.framework = framework.NewTestFramework("saga_workflow")
	require.NoError(s.T(), s.framework.Start())
	
	s.sagaOrch = s.framework.SAGAOrchestrator()
	s.eventStore = s.framework.EventStore()
	s.outboxMonitor = s.framework.OutboxMonitor()
}

func (s *SAGAWorkflowTestSuite) TearDownSuite() {
	s.framework.Stop()
}

func (s *SAGAWorkflowTestSuite) SetupTest() {
	require.NoError(s.T(), s.framework.ResetTestData())
}

// TestUserRegistrationSAGA tests the complete user registration SAGA workflow
func (s *SAGAWorkflowTestSuite) TestUserRegistrationSAGA() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	userRegistrationRequest := &UserRegistrationRequest{
		Email:     "newuser@alpha.test.com",
		Username:  "newuser123",
		Password:  "SecurePassword123!",
		FirstName: "Test",
		LastName:  "User",
		TenantID:  tenantID,
	}

	// Act - Start the user registration SAGA
	sagaID, err := s.sagaOrch.StartUserRegistrationSAGA(ctx, userRegistrationRequest)
	require.NoError(s.T(), err)
	require.NotEmpty(s.T(), sagaID)

	// Assert - Wait for SAGA completion and validate results
	s.T().Run("SAGA_Completion", func(t *testing.T) {
		success := s.framework.WaitForSAGACompletion(ctx, sagaID, 25*time.Second)
		assert.True(t, success, "User registration SAGA should complete successfully")
	})

	s.T().Run("User_Created", func(t *testing.T) {
		user, err := s.framework.UserService().GetUserByEmail(ctx, userRegistrationRequest.Email)
		require.NoError(t, err)
		assert.Equal(t, userRegistrationRequest.Email, user.Email)
		assert.Equal(t, userRegistrationRequest.Username, user.Username)
		assert.Equal(t, userRegistrationRequest.TenantID, user.TenantID)
		assert.Equal(t, "active", user.Status)
	})

	s.T().Run("Workspace_Created", func(t *testing.T) {
		workspaces, err := s.framework.WorkspaceService().GetUserWorkspaces(ctx, tenantID, userRegistrationRequest.Email)
		require.NoError(t, err)
		assert.Len(t, workspaces, 1)
		assert.Equal(t, fmt.Sprintf("%s's Workspace", userRegistrationRequest.FirstName), workspaces[0].Name)
	})

	s.T().Run("Permissions_Assigned", func(t *testing.T) {
		userID := s.getUserIDByEmail(ctx, userRegistrationRequest.Email)
		permissions, err := s.framework.PermissionService().GetUserPermissions(ctx, userID, tenantID)
		require.NoError(t, err)
		
		expectedPermissions := []string{
			"workspace.read",
			"workspace.write",
			"project.create",
			"base.create",
		}
		
		for _, expectedPerm := range expectedPermissions {
			assert.Contains(t, permissions, expectedPerm)
		}
	})

	s.T().Run("Welcome_Email_Sent", func(t *testing.T) {
		emailSent := s.framework.MockEmailService().WasEmailSent(userRegistrationRequest.Email, "welcome")
		assert.True(t, emailSent, "Welcome email should be sent")
	})

	s.T().Run("Events_Published", func(t *testing.T) {
		events := s.eventStore.GetEventsBySAGA(ctx, sagaID)
		
		expectedEventTypes := []string{
			"user.registration.started",
			"user.created",
			"workspace.created",
			"permissions.assigned",
			"welcome.email.sent",
			"user.registration.completed",
		}
		
		actualEventTypes := make([]string, len(events))
		for i, event := range events {
			actualEventTypes[i] = event.EventType
		}
		
		for _, expectedType := range expectedEventTypes {
			assert.Contains(t, actualEventTypes, expectedType)
		}
	})

	s.T().Run("Outbox_Messages_Delivered", func(t *testing.T) {
		delivered := s.outboxMonitor.WaitForAllMessagesDelivered(ctx, sagaID, 10*time.Second)
		assert.True(t, delivered, "All outbox messages should be delivered")
	})
}

// TestUserRegistrationSAGAWithFailure tests SAGA compensation when a step fails
func (s *SAGAWorkflowTestSuite) TestUserRegistrationSAGAWithFailure() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange - Setup email service to fail
	s.framework.MockEmailService().SetFailureMode(true)
	
	tenantID := fixtures.TestTenantAlphaID
	userRegistrationRequest := &UserRegistrationRequest{
		Email:     "failuser@alpha.test.com",
		Username:  "failuser123",
		Password:  "SecurePassword123!",
		FirstName: "Fail",
		LastName:  "User",
		TenantID:  tenantID,
	}

	// Act - Start the user registration SAGA
	sagaID, err := s.sagaOrch.StartUserRegistrationSAGA(ctx, userRegistrationRequest)
	require.NoError(s.T(), err)

	// Assert - Wait for SAGA failure and validate compensation
	s.T().Run("SAGA_Compensation", func(t *testing.T) {
		failed := s.framework.WaitForSAGAFailure(ctx, sagaID, 25*time.Second)
		assert.True(t, failed, "SAGA should fail due to email service failure")
	})

	s.T().Run("User_Removed", func(t *testing.T) {
		// User should be removed as part of compensation
		_, err := s.framework.UserService().GetUserByEmail(ctx, userRegistrationRequest.Email)
		assert.Error(t, err, "User should be removed during compensation")
	})

	s.T().Run("Workspace_Removed", func(t *testing.T) {
		// Workspace should be removed as part of compensation
		workspaces, err := s.framework.WorkspaceService().GetUserWorkspaces(ctx, tenantID, userRegistrationRequest.Email)
		require.NoError(t, err)
		assert.Empty(t, workspaces, "Workspace should be removed during compensation")
	})

	s.T().Run("Compensation_Events_Published", func(t *testing.T) {
		events := s.eventStore.GetEventsBySAGA(ctx, sagaID)
		
		compensationEventTypes := []string{
			"user.registration.failed",
			"workspace.removed",
			"user.removed",
			"permissions.revoked",
			"user.registration.compensated",
		}
		
		actualEventTypes := make([]string, len(events))
		for i, event := range events {
			actualEventTypes[i] = event.EventType
		}
		
		for _, compensationType := range compensationEventTypes {
			assert.Contains(t, actualEventTypes, compensationType)
		}
	})
}

// TestWorkspaceCreationSAGA tests the workspace creation SAGA with complex resource provisioning
func (s *SAGAWorkflowTestSuite) TestWorkspaceCreationSAGA() {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	// Arrange
	userID := fixtures.TestUserAlphaUser1ID
	tenantID := fixtures.TestTenantAlphaID
	
	workspaceRequest := &WorkspaceCreationRequest{
		Name:        "Complex Workspace",
		Description: "Workspace with multiple projects and bases",
		TenantID:    tenantID,
		CreatedBy:   userID,
		ProjectTemplates: []ProjectTemplate{
			{
				Name:        "Marketing Project",
				Description: "Marketing campaigns and analytics",
				BaseTemplates: []BaseTemplate{
					{Name: "Campaigns", Type: "marketing"},
					{Name: "Analytics", Type: "analytics"},
				},
			},
			{
				Name:        "Sales Project",
				Description: "Sales pipeline and CRM",
				BaseTemplates: []BaseTemplate{
					{Name: "Leads", Type: "crm"},
					{Name: "Opportunities", Type: "sales"},
				},
			},
		},
	}

	// Act - Start the workspace creation SAGA
	sagaID, err := s.sagaOrch.StartWorkspaceCreationSAGA(ctx, workspaceRequest)
	require.NoError(s.T(), err)
	require.NotEmpty(s.T(), sagaID)

	// Assert - Validate complex resource provisioning
	s.T().Run("SAGA_Completion", func(t *testing.T) {
		success := s.framework.WaitForSAGACompletion(ctx, sagaID, 40*time.Second)
		assert.True(t, success, "Workspace creation SAGA should complete successfully")
	})

	s.T().Run("Workspace_Created", func(t *testing.T) {
		workspace, err := s.framework.WorkspaceService().GetWorkspaceByName(ctx, tenantID, workspaceRequest.Name)
		require.NoError(t, err)
		assert.Equal(t, workspaceRequest.Name, workspace.Name)
		assert.Equal(t, workspaceRequest.Description, workspace.Description)
		assert.Equal(t, "active", workspace.Status)
	})

	s.T().Run("Projects_Created", func(t *testing.T) {
		workspace, _ := s.framework.WorkspaceService().GetWorkspaceByName(ctx, tenantID, workspaceRequest.Name)
		projects, err := s.framework.ProjectService().GetWorkspaceProjects(ctx, workspace.ID)
		require.NoError(t, err)
		assert.Len(t, projects, 2)
		
		projectNames := make([]string, len(projects))
		for i, project := range projects {
			projectNames[i] = project.Name
		}
		
		assert.Contains(t, projectNames, "Marketing Project")
		assert.Contains(t, projectNames, "Sales Project")
	})

	s.T().Run("Bases_Created", func(t *testing.T) {
		workspace, _ := s.framework.WorkspaceService().GetWorkspaceByName(ctx, tenantID, workspaceRequest.Name)
		bases, err := s.framework.BaseService().GetWorkspaceBases(ctx, workspace.ID)
		require.NoError(t, err)
		assert.Len(t, bases, 4)
		
		baseNames := make([]string, len(bases))
		for i, base := range bases {
			baseNames[i] = base.Name
		}
		
		expectedBases := []string{"Campaigns", "Analytics", "Leads", "Opportunities"}
		for _, expectedBase := range expectedBases {
			assert.Contains(t, baseNames, expectedBase)
		}
	})

	s.T().Run("Permissions_Configured", func(t *testing.T) {
		workspace, _ := s.framework.WorkspaceService().GetWorkspaceByName(ctx, tenantID, workspaceRequest.Name)
		
		// Check creator has admin permissions
		hasAdmin := s.framework.PermissionService().CheckPermission(ctx, userID, workspace.ID, "workspace.admin")
		assert.True(t, hasAdmin, "Creator should have admin permissions")
		
		// Check project-level permissions
		projects, _ := s.framework.ProjectService().GetWorkspaceProjects(ctx, workspace.ID)
		for _, project := range projects {
			hasProjectAdmin := s.framework.PermissionService().CheckPermission(ctx, userID, project.ID, "project.admin")
			assert.True(t, hasProjectAdmin, "Creator should have project admin permissions")
		}
	})

	s.T().Run("Audit_Trail_Created", func(t *testing.T) {
		auditEvents := s.framework.AuditService().GetSAGAAuditTrail(ctx, sagaID)
		assert.NotEmpty(t, auditEvents)
		
		// Verify key audit events
		auditEventTypes := make([]string, len(auditEvents))
		for i, event := range auditEvents {
			auditEventTypes[i] = event.EventType
		}
		
		expectedAuditTypes := []string{
			"workspace.creation.started",
			"workspace.created",
			"projects.created",
			"bases.created",
			"permissions.configured",
			"workspace.creation.completed",
		}
		
		for _, expectedType := range expectedAuditTypes {
			assert.Contains(t, auditEventTypes, expectedType)
		}
	})
}

// TestPaymentProcessingSAGA tests financial transaction coordination
func (s *SAGAWorkflowTestSuite) TestPaymentProcessingSAGA() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	paymentRequest := &PaymentProcessingRequest{
		TenantID:      tenantID,
		Amount:        99.99,
		Currency:      "USD",
		PaymentMethod: "card_123",
		Description:   "Upgrade to Pro Plan",
		PlanUpgrade: &PlanUpgradeRequest{
			FromPlan: "free",
			ToPlan:   "pro",
			BillingCycle: "monthly",
		},
	}

	// Act - Start the payment processing SAGA
	sagaID, err := s.sagaOrch.StartPaymentProcessingSAGA(ctx, paymentRequest)
	require.NoError(s.T(), err)
	require.NotEmpty(s.T(), sagaID)

	// Assert - Validate financial transaction coordination
	s.T().Run("SAGA_Completion", func(t *testing.T) {
		success := s.framework.WaitForSAGACompletion(ctx, sagaID, 25*time.Second)
		assert.True(t, success, "Payment processing SAGA should complete successfully")
	})

	s.T().Run("Payment_Processed", func(t *testing.T) {
		payment, err := s.framework.PaymentService().GetPaymentBySAGA(ctx, sagaID)
		require.NoError(t, err)
		assert.Equal(t, "completed", payment.Status)
		assert.Equal(t, paymentRequest.Amount, payment.Amount)
		assert.Equal(t, paymentRequest.Currency, payment.Currency)
	})

	s.T().Run("Plan_Upgraded", func(t *testing.T) {
		tenant, err := s.framework.TenantService().GetTenant(ctx, tenantID)
		require.NoError(t, err)
		assert.Equal(t, "pro", tenant.PlanType)
		assert.Equal(t, "monthly", tenant.BillingCycle)
	})

	s.T().Run("Invoice_Generated", func(t *testing.T) {
		invoice, err := s.framework.BillingService().GetInvoiceBySAGA(ctx, sagaID)
		require.NoError(t, err)
		assert.Equal(t, "paid", invoice.Status)
		assert.Equal(t, paymentRequest.Amount, invoice.Amount)
	})

	s.T().Run("Features_Enabled", func(t *testing.T) {
		features, err := s.framework.FeatureService().GetTenantFeatures(ctx, tenantID)
		require.NoError(t, err)
		
		expectedFeatures := []string{
			"advanced_analytics",
			"collaboration_tools",
			"api_access",
			"premium_support",
		}
		
		for _, feature := range expectedFeatures {
			assert.Contains(t, features, feature)
		}
	})

	s.T().Run("Notification_Sent", func(t *testing.T) {
		// Check upgrade confirmation email
		emailSent := s.framework.MockEmailService().WasEmailSent(
			s.getTenantAdminEmail(ctx, tenantID),
			"plan_upgrade_confirmation",
		)
		assert.True(t, emailSent, "Plan upgrade confirmation email should be sent")
	})
}

// TestPaymentProcessingSAGAWithFailure tests payment SAGA compensation
func (s *SAGAWorkflowTestSuite) TestPaymentProcessingSAGAWithFailure() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange - Setup payment service to fail
	s.framework.MockPaymentService().SetFailureMode(true)
	
	tenantID := fixtures.TestTenantAlphaID
	paymentRequest := &PaymentProcessingRequest{
		TenantID:      tenantID,
		Amount:        199.99,
		Currency:      "USD",
		PaymentMethod: "card_invalid",
		Description:   "Upgrade to Enterprise Plan",
		PlanUpgrade: &PlanUpgradeRequest{
			FromPlan: "pro",
			ToPlan:   "enterprise",
			BillingCycle: "annual",
		},
	}

	// Get original plan before attempting upgrade
	originalTenant, err := s.framework.TenantService().GetTenant(ctx, tenantID)
	require.NoError(s.T(), err)
	originalPlan := originalTenant.PlanType

	// Act - Start the payment processing SAGA
	sagaID, err := s.sagaOrch.StartPaymentProcessingSAGA(ctx, paymentRequest)
	require.NoError(s.T(), err)

	// Assert - Validate payment failure compensation
	s.T().Run("SAGA_Failure", func(t *testing.T) {
		failed := s.framework.WaitForSAGAFailure(ctx, sagaID, 25*time.Second)
		assert.True(t, failed, "Payment processing SAGA should fail due to payment failure")
	})

	s.T().Run("Payment_Failed", func(t *testing.T) {
		payment, err := s.framework.PaymentService().GetPaymentBySAGA(ctx, sagaID)
		require.NoError(t, err)
		assert.Equal(t, "failed", payment.Status)
	})

	s.T().Run("Plan_Unchanged", func(t *testing.T) {
		tenant, err := s.framework.TenantService().GetTenant(ctx, tenantID)
		require.NoError(t, err)
		assert.Equal(t, originalPlan, tenant.PlanType, "Plan should remain unchanged after payment failure")
	})

	s.T().Run("Failure_Notification_Sent", func(t *testing.T) {
		emailSent := s.framework.MockEmailService().WasEmailSent(
			s.getTenantAdminEmail(ctx, tenantID),
			"payment_failed",
		)
		assert.True(t, emailSent, "Payment failure notification should be sent")
	})
}

// TestConcurrentSAGAExecution tests multiple SAGAs running concurrently
func (s *SAGAWorkflowTestSuite) TestConcurrentSAGAExecution() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Arrange - Multiple user registration requests
	registrationRequests := []*UserRegistrationRequest{
		{
			Email: "concurrent1@alpha.test.com",
			Username: "concurrent1",
			Password: "SecurePassword123!",
			FirstName: "User",
			LastName: "One",
			TenantID: fixtures.TestTenantAlphaID,
		},
		{
			Email: "concurrent2@alpha.test.com",
			Username: "concurrent2",
			Password: "SecurePassword123!",
			FirstName: "User",
			LastName: "Two",
			TenantID: fixtures.TestTenantAlphaID,
		},
		{
			Email: "concurrent3@beta.test.com",
			Username: "concurrent3",
			Password: "SecurePassword123!",
			FirstName: "User",
			LastName: "Three",
			TenantID: fixtures.TestTenantBetaID,
		},
	}

	// Act - Start multiple SAGAs concurrently
	sagaIDs := make([]string, len(registrationRequests))
	for i, request := range registrationRequests {
		sagaID, err := s.sagaOrch.StartUserRegistrationSAGA(ctx, request)
		require.NoError(s.T(), err)
		sagaIDs[i] = sagaID
	}

	// Assert - All SAGAs should complete successfully
	s.T().Run("All_SAGAs_Complete", func(t *testing.T) {
		for i, sagaID := range sagaIDs {
			success := s.framework.WaitForSAGACompletion(ctx, sagaID, 45*time.Second)
			assert.True(t, success, "SAGA %d should complete successfully", i+1)
		}
	})

	s.T().Run("All_Users_Created", func(t *testing.T) {
		for i, request := range registrationRequests {
			user, err := s.framework.UserService().GetUserByEmail(ctx, request.Email)
			require.NoError(t, err, "User %d should be created", i+1)
			assert.Equal(t, request.Email, user.Email)
			assert.Equal(t, "active", user.Status)
		}
	})

	s.T().Run("No_Resource_Conflicts", func(t *testing.T) {
		// Verify no username conflicts
		usernames := make(map[string]bool)
		for _, request := range registrationRequests {
			user, _ := s.framework.UserService().GetUserByEmail(ctx, request.Email)
			assert.False(t, usernames[user.Username], "Username should be unique: %s", user.Username)
			usernames[user.Username] = true
		}
	})

	s.T().Run("Tenant_Isolation_Maintained", func(t *testing.T) {
		// Alpha tenant users
		alphaUsers, err := s.framework.UserService().GetTenantUsers(ctx, fixtures.TestTenantAlphaID)
		require.NoError(t, err)
		alphaUserEmails := make([]string, len(alphaUsers))
		for i, user := range alphaUsers {
			alphaUserEmails[i] = user.Email
		}
		assert.Contains(t, alphaUserEmails, "concurrent1@alpha.test.com")
		assert.Contains(t, alphaUserEmails, "concurrent2@alpha.test.com")
		assert.NotContains(t, alphaUserEmails, "concurrent3@beta.test.com")

		// Beta tenant users
		betaUsers, err := s.framework.UserService().GetTenantUsers(ctx, fixtures.TestTenantBetaID)
		require.NoError(t, err)
		betaUserEmails := make([]string, len(betaUsers))
		for i, user := range betaUsers {
			betaUserEmails[i] = user.Email
		}
		assert.Contains(t, betaUserEmails, "concurrent3@beta.test.com")
		assert.NotContains(t, betaUserEmails, "concurrent1@alpha.test.com")
		assert.NotContains(t, betaUserEmails, "concurrent2@alpha.test.com")
	})
}

// Helper methods
func (s *SAGAWorkflowTestSuite) getUserIDByEmail(ctx context.Context, email string) string {
	user, err := s.framework.UserService().GetUserByEmail(ctx, email)
	require.NoError(s.T(), err)
	return user.ID
}

func (s *SAGAWorkflowTestSuite) getTenantAdminEmail(ctx context.Context, tenantID string) string {
	admin, err := s.framework.UserService().GetTenantAdmin(ctx, tenantID)
	require.NoError(s.T(), err)
	return admin.Email
}

// Request types for SAGA workflows
type UserRegistrationRequest struct {
	Email     string `json:"email"`
	Username  string `json:"username"`
	Password  string `json:"password"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	TenantID  string `json:"tenant_id"`
}

type WorkspaceCreationRequest struct {
	Name             string            `json:"name"`
	Description      string            `json:"description"`
	TenantID         string            `json:"tenant_id"`
	CreatedBy        string            `json:"created_by"`
	ProjectTemplates []ProjectTemplate `json:"project_templates"`
}

type ProjectTemplate struct {
	Name          string         `json:"name"`
	Description   string         `json:"description"`
	BaseTemplates []BaseTemplate `json:"base_templates"`
}

type BaseTemplate struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

type PaymentProcessingRequest struct {
	TenantID      string              `json:"tenant_id"`
	Amount        float64             `json:"amount"`
	Currency      string              `json:"currency"`
	PaymentMethod string              `json:"payment_method"`
	Description   string              `json:"description"`
	PlanUpgrade   *PlanUpgradeRequest `json:"plan_upgrade,omitempty"`
}

type PlanUpgradeRequest struct {
	FromPlan     string `json:"from_plan"`
	ToPlan       string `json:"to_plan"`
	BillingCycle string `json:"billing_cycle"`
}

// Test runner
func TestSAGAWorkflowSuite(t *testing.T) {
	suite.Run(t, new(SAGAWorkflowTestSuite))
}