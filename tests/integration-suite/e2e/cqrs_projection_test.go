package e2e

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"github.com/google/uuid"

	"github.com/pyairtable-compose/tests/integration-suite/internal/framework"
	"github.com/pyairtable-compose/tests/integration-suite/internal/fixtures"
)

// CQRSProjectionTestSuite tests CQRS projection consistency and event replay validation
type CQRSProjectionTestSuite struct {
	suite.Suite
	framework        *framework.TestFramework
	eventStore       *framework.EventStore
	projectionManager *framework.ProjectionManager
	queryService     *framework.QueryService
	commandBus       *framework.CommandBus
}

func (s *CQRSProjectionTestSuite) SetupSuite() {
	s.framework = framework.NewTestFramework("cqrs_projection")
	require.NoError(s.T(), s.framework.Start())
	
	s.eventStore = s.framework.EventStore()
	s.projectionManager = s.framework.ProjectionManager()
	s.queryService = s.framework.QueryService()
	s.commandBus = s.framework.CommandBus()
}

func (s *CQRSProjectionTestSuite) TearDownSuite() {
	s.framework.Stop()
}

func (s *CQRSProjectionTestSuite) SetupTest() {
	require.NoError(s.T(), s.framework.ResetTestData())
	require.NoError(s.T(), s.projectionManager.ResetAllProjections())
}

// TestUserProjectionConsistency tests user projection synchronization with command side
func (s *CQRSProjectionTestSuite) TestUserProjectionConsistency() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	userCommands := []UserCommand{
		{
			Type: "CreateUser",
			Data: CreateUserData{
				UserID:    "new-user-1",
				TenantID:  tenantID,
				Email:     "projection.test1@alpha.test.com",
				Username:  "projtest1",
				FirstName: "Projection",
				LastName:  "Test1",
			},
		},
		{
			Type: "UpdateUser",
			Data: UpdateUserData{
				UserID:    "new-user-1",
				FirstName: "Updated",
				LastName:  "Test1",
				Email:     "updated.projection.test1@alpha.test.com",
			},
		},
		{
			Type: "AssignUserRole",
			Data: AssignUserRoleData{
				UserID:   "new-user-1",
				TenantID: tenantID,
				Role:     "workspace_admin",
			},
		},
	}

	// Act - Execute commands and wait for projection updates
	for _, cmd := range userCommands {
		err := s.commandBus.ExecuteCommand(ctx, cmd)
		require.NoError(s.T(), err)
	}

	// Wait for all projections to be updated
	success := s.projectionManager.WaitForProjectionSync(ctx, "user_projection", 10*time.Second)
	require.True(s.T(), success, "User projection should be synchronized")

	// Assert - Validate projection consistency
	s.T().Run("User_Projection_Data", func(t *testing.T) {
		userView, err := s.queryService.GetUserView(ctx, "new-user-1")
		require.NoError(t, err)
		
		assert.Equal(t, "new-user-1", userView.UserID)
		assert.Equal(t, tenantID, userView.TenantID)
		assert.Equal(t, "updated.projection.test1@alpha.test.com", userView.Email)
		assert.Equal(t, "Updated", userView.FirstName)
		assert.Equal(t, "Test1", userView.LastName)
		assert.Equal(t, "workspace_admin", userView.Role)
		assert.Equal(t, "active", userView.Status)
	})

	s.T().Run("User_Statistics_Updated", func(t *testing.T) {
		stats, err := s.queryService.GetTenantUserStatistics(ctx, tenantID)
		require.NoError(t, err)
		
		// Should include the new user in statistics
		assert.Greater(t, stats.TotalUsers, 0)
		assert.Contains(t, stats.UsersByRole, "workspace_admin")
		assert.Greater(t, stats.UsersByRole["workspace_admin"], 0)
	})

	s.T().Run("Search_Index_Updated", func(t *testing.T) {
		// Search by email
		results, err := s.queryService.SearchUsers(ctx, tenantID, "updated.projection.test1")
		require.NoError(t, err)
		assert.Len(t, results, 1)
		assert.Equal(t, "new-user-1", results[0].UserID)
		
		// Search by name
		results, err = s.queryService.SearchUsers(ctx, tenantID, "Updated Test1")
		require.NoError(t, err)
		assert.Len(t, results, 1)
		assert.Equal(t, "new-user-1", results[0].UserID)
	})

	s.T().Run("Audit_Trail_Projection", func(t *testing.T) {
		auditEntries, err := s.queryService.GetUserAuditTrail(ctx, "new-user-1")
		require.NoError(t, err)
		assert.Len(t, auditEntries, 3) // Create, Update, Role Assignment
		
		expectedActions := []string{"user_created", "user_updated", "role_assigned"}
		actualActions := make([]string, len(auditEntries))
		for i, entry := range auditEntries {
			actualActions[i] = entry.Action
		}
		
		for _, expectedAction := range expectedActions {
			assert.Contains(t, actualActions, expectedAction)
		}
	})
}

// TestWorkspaceProjectionRebuild tests workspace projection rebuilding from events
func (s *CQRSProjectionTestSuite) TestWorkspaceProjectionRebuild() {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	// Arrange - Create workspace and associated resources
	tenantID := fixtures.TestTenantAlphaID
	userID := fixtures.TestUserAlphaUser1ID
	
	workspaceCommands := []WorkspaceCommand{
		{
			Type: "CreateWorkspace",
			Data: CreateWorkspaceData{
				WorkspaceID: "test-workspace-rebuild",
				TenantID:    tenantID,
				Name:        "Rebuild Test Workspace",
				Description: "Testing projection rebuild",
				CreatedBy:   userID,
			},
		},
		{
			Type: "CreateProject",
			Data: CreateProjectData{
				ProjectID:   "test-project-1",
				WorkspaceID: "test-workspace-rebuild",
				Name:        "Test Project 1",
				Description: "First test project",
			},
		},
		{
			Type: "CreateProject",
			Data: CreateProjectData{
				ProjectID:   "test-project-2",
				WorkspaceID: "test-workspace-rebuild",
				Name:        "Test Project 2",
				Description: "Second test project",
			},
		},
		{
			Type: "CreateBase",
			Data: CreateBaseData{
				BaseID:    "test-base-1",
				ProjectID: "test-project-1",
				Name:      "Test Base 1",
				Type:      "standard",
			},
		},
		{
			Type: "CreateBase",
			Data: CreateBaseData{
				BaseID:    "test-base-2",
				ProjectID: "test-project-2",
				Name:      "Test Base 2",
				Type:      "analytics",
			},
		},
	}

	// Execute all commands
	for _, cmd := range workspaceCommands {
		err := s.commandBus.ExecuteCommand(ctx, cmd)
		require.NoError(s.T(), err)
	}

	// Wait for initial projection sync
	success := s.projectionManager.WaitForProjectionSync(ctx, "workspace_projection", 15*time.Second)
	require.True(s.T(), success)

	// Get initial projection state
	initialView, err := s.queryService.GetWorkspaceView(ctx, "test-workspace-rebuild")
	require.NoError(s.T(), err)

	// Act - Clear workspace projection and rebuild from events
	s.T().Run("Clear_Projection", func(t *testing.T) {
		err := s.projectionManager.ClearProjection(ctx, "workspace_projection")
		require.NoError(t, err)
		
		// Verify projection is cleared
		_, err = s.queryService.GetWorkspaceView(ctx, "test-workspace-rebuild")
		assert.Error(t, err, "Workspace view should not exist after clearing projection")
	})

	s.T().Run("Rebuild_From_Events", func(t *testing.T) {
		// Trigger projection rebuild
		err := s.projectionManager.RebuildProjection(ctx, "workspace_projection")
		require.NoError(t, err)
		
		// Wait for rebuild completion
		success := s.projectionManager.WaitForProjectionRebuild(ctx, "workspace_projection", 30*time.Second)
		assert.True(t, success, "Workspace projection rebuild should complete")
	})

	// Assert - Validate rebuilt projection matches original
	s.T().Run("Rebuilt_Projection_Matches", func(t *testing.T) {
		rebuiltView, err := s.queryService.GetWorkspaceView(ctx, "test-workspace-rebuild")
		require.NoError(t, err)
		
		assert.Equal(t, initialView.WorkspaceID, rebuiltView.WorkspaceID)
		assert.Equal(t, initialView.Name, rebuiltView.Name)
		assert.Equal(t, initialView.Description, rebuiltView.Description)
		assert.Equal(t, initialView.TenantID, rebuiltView.TenantID)
		assert.Equal(t, initialView.CreatedBy, rebuiltView.CreatedBy)
		assert.Equal(t, len(initialView.Projects), len(rebuiltView.Projects))
		assert.Equal(t, initialView.TotalBases, rebuiltView.TotalBases)
	})

	s.T().Run("Project_Hierarchy_Rebuilt", func(t *testing.T) {
		projects, err := s.queryService.GetWorkspaceProjects(ctx, "test-workspace-rebuild")
		require.NoError(t, err)
		assert.Len(t, projects, 2)
		
		projectNames := make([]string, len(projects))
		for i, project := range projects {
			projectNames[i] = project.Name
		}
		
		assert.Contains(t, projectNames, "Test Project 1")
		assert.Contains(t, projectNames, "Test Project 2")
	})

	s.T().Run("Base_Associations_Rebuilt", func(t *testing.T) {
		bases, err := s.queryService.GetWorkspaceBases(ctx, "test-workspace-rebuild")
		require.NoError(t, err)
		assert.Len(t, bases, 2)
		
		baseNames := make([]string, len(bases))
		for i, base := range bases {
			baseNames[i] = base.Name
		}
		
		assert.Contains(t, baseNames, "Test Base 1")
		assert.Contains(t, baseNames, "Test Base 2")
	})
}

// TestAnalyticsProjectionUpdates tests real-time analytics projection updates
func (s *CQRSProjectionTestSuite) TestAnalyticsProjectionUpdates() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange - Setup workspace with activity
	tenantID := fixtures.TestTenantAlphaID
	workspaceID := "analytics-test-workspace"
	
	// Create workspace first
	createCmd := WorkspaceCommand{
		Type: "CreateWorkspace",
		Data: CreateWorkspaceData{
			WorkspaceID: workspaceID,
			TenantID:    tenantID,
			Name:        "Analytics Test Workspace",
			Description: "Testing analytics projections",
			CreatedBy:   fixtures.TestUserAlphaUser1ID,
		},
	}
	
	err := s.commandBus.ExecuteCommand(ctx, createCmd)
	require.NoError(s.T(), err)

	// Generate activity events
	activityCommands := []AnalyticsCommand{
		{
			Type: "RecordWorkspaceAccess",
			Data: WorkspaceAccessData{
				WorkspaceID: workspaceID,
				UserID:      fixtures.TestUserAlphaUser1ID,
				AccessType:  "view",
				Timestamp:   time.Now().Unix(),
			},
		},
		{
			Type: "RecordWorkspaceAccess",
			Data: WorkspaceAccessData{
				WorkspaceID: workspaceID,
				UserID:      fixtures.TestUserAlphaUser2ID,
				AccessType:  "edit",
				Timestamp:   time.Now().Unix(),
			},
		},
		{
			Type: "RecordDataOperation",
			Data: DataOperationData{
				WorkspaceID:   workspaceID,
				UserID:        fixtures.TestUserAlphaUser1ID,
				OperationType: "create_record",
				RecordCount:   5,
				Timestamp:     time.Now().Unix(),
			},
		},
		{
			Type: "RecordDataOperation",
			Data: DataOperationData{
				WorkspaceID:   workspaceID,
				UserID:        fixtures.TestUserAlphaUser2ID,
				OperationType: "update_record",
				RecordCount:   3,
				Timestamp:     time.Now().Unix(),
			},
		},
	}

	// Act - Execute analytics commands
	for _, cmd := range activityCommands {
		err := s.commandBus.ExecuteCommand(ctx, cmd)
		require.NoError(s.T(), err)
	}

	// Wait for analytics projection updates
	success := s.projectionManager.WaitForProjectionSync(ctx, "analytics_projection", 10*time.Second)
	require.True(s.T(), success)

	// Assert - Validate analytics aggregations
	s.T().Run("Workspace_Usage_Analytics", func(t *testing.T) {
		analytics, err := s.queryService.GetWorkspaceAnalytics(ctx, workspaceID)
		require.NoError(t, err)
		
		assert.Equal(t, 2, analytics.UniqueUsers)
		assert.Equal(t, 2, analytics.TotalAccesses)
		assert.Equal(t, 8, analytics.TotalDataOperations) // 5 + 3
		assert.Greater(t, analytics.LastAccessTime, int64(0))
	})

	s.T().Run("User_Activity_Analytics", func(t *testing.T) {
		userAnalytics, err := s.queryService.GetUserActivityAnalytics(ctx, fixtures.TestUserAlphaUser1ID, workspaceID)
		require.NoError(t, err)
		
		assert.Equal(t, 1, userAnalytics.AccessCount)
		assert.Equal(t, "view", userAnalytics.LastAccessType)
		assert.Equal(t, 5, userAnalytics.DataOperationsCount)
	})

	s.T().Run("Real_Time_Metrics", func(t *testing.T) {
		metrics, err := s.queryService.GetRealTimeMetrics(ctx, workspaceID)
		require.NoError(t, err)
		
		assert.Greater(t, metrics.ActiveUsers, 0)
		assert.Greater(t, metrics.RecentOperations, 0)
		assert.NotEmpty(t, metrics.TopOperations)
	})

	s.T().Run("Time_Series_Data", func(t *testing.T) {
		timeSeries, err := s.queryService.GetWorkspaceTimeSeriesData(ctx, workspaceID, time.Now().Add(-1*time.Hour), time.Now())
		require.NoError(t, err)
		
		assert.NotEmpty(t, timeSeries.AccessPoints)
		assert.NotEmpty(t, timeSeries.OperationPoints)
	})
}

// TestCrossServiceProjectionSync tests projection synchronization across services
func (s *CQRSProjectionTestSuite) TestCrossServiceProjectionSync() {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	// Arrange - Create user and workspace in different services
	tenantID := fixtures.TestTenantAlphaID
	userID := "cross-service-user"
	workspaceID := "cross-service-workspace"
	
	// User creation in Auth Service
	userCmd := UserCommand{
		Type: "CreateUser",
		Data: CreateUserData{
			UserID:    userID,
			TenantID:  tenantID,
			Email:     "crossservice@alpha.test.com",
			Username:  "crossserviceuser",
			FirstName: "Cross",
			LastName:  "Service",
		},
	}
	
	// Workspace creation in Workspace Service
	workspaceCmd := WorkspaceCommand{
		Type: "CreateWorkspace",
		Data: CreateWorkspaceData{
			WorkspaceID: workspaceID,
			TenantID:    tenantID,
			Name:        "Cross Service Workspace",
			Description: "Testing cross-service projections",
			CreatedBy:   userID,
		},
	}
	
	// Permission assignment in Permission Service
	permissionCmd := PermissionCommand{
		Type: "AssignWorkspacePermission",
		Data: AssignWorkspacePermissionData{
			UserID:      userID,
			WorkspaceID: workspaceID,
			Permission:  "workspace.admin",
			GrantedBy:   fixtures.TestUserAlphaAdminID,
		},
	}

	// Act - Execute commands across different services
	err := s.commandBus.ExecuteCommand(ctx, userCmd)
	require.NoError(s.T(), err)
	
	err = s.commandBus.ExecuteCommand(ctx, workspaceCmd)
	require.NoError(s.T(), err)
	
	err = s.commandBus.ExecuteCommand(ctx, permissionCmd)
	require.NoError(s.T(), err)

	// Wait for all cross-service projections to sync
	projections := []string{"user_projection", "workspace_projection", "permission_projection"}
	for _, projection := range projections {
		success := s.projectionManager.WaitForProjectionSync(ctx, projection, 15*time.Second)
		require.True(s.T(), success, "Projection %s should sync", projection)
	}

	// Assert - Validate cross-service consistency
	s.T().Run("User_Workspace_Relationship", func(t *testing.T) {
		userView, err := s.queryService.GetUserView(ctx, userID)
		require.NoError(t, err)
		
		workspaceView, err := s.queryService.GetWorkspaceView(ctx, workspaceID)
		require.NoError(t, err)
		
		assert.Equal(t, userView.UserID, workspaceView.CreatedBy)
		assert.Equal(t, userView.TenantID, workspaceView.TenantID)
	})

	s.T().Run("Permission_Consistency", func(t *testing.T) {
		permissions, err := s.queryService.GetUserWorkspacePermissions(ctx, userID, workspaceID)
		require.NoError(t, err)
		
		assert.Contains(t, permissions, "workspace.admin")
	})

	s.T().Run("Aggregated_Views", func(t *testing.T) {
		userSummary, err := s.queryService.GetUserSummaryView(ctx, userID)
		require.NoError(t, err)
		
		assert.Equal(t, 1, userSummary.WorkspaceCount)
		assert.Equal(t, 1, userSummary.AdminWorkspaceCount)
		assert.Contains(t, userSummary.WorkspaceNames, "Cross Service Workspace")
	})

	s.T().Run("Search_Across_Services", func(t *testing.T) {
		// Search for user should return workspace information
		searchResults, err := s.queryService.SearchAll(ctx, tenantID, "crossservice")
		require.NoError(t, err)
		
		var foundUser, foundWorkspace bool
		for _, result := range searchResults {
			if result.Type == "user" && result.ID == userID {
				foundUser = true
			}
			if result.Type == "workspace" && result.ID == workspaceID {
				foundWorkspace = true
			}
		}
		
		assert.True(t, foundUser, "User should be found in search")
		assert.True(t, foundWorkspace, "Workspace should be found in search")
	})
}

// TestEventReplayValidation tests event replay for projection validation
func (s *CQRSProjectionTestSuite) TestEventReplayValidation() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Arrange - Create a complex scenario with multiple events
	tenantID := fixtures.TestTenantAlphaID
	
	// Complex command sequence
	commands := []interface{}{
		UserCommand{
			Type: "CreateUser",
			Data: CreateUserData{
				UserID:    "replay-user",
				TenantID:  tenantID,
				Email:     "replay@alpha.test.com",
				Username:  "replayuser",
				FirstName: "Replay",
				LastName:  "User",
			},
		},
		WorkspaceCommand{
			Type: "CreateWorkspace",
			Data: CreateWorkspaceData{
				WorkspaceID: "replay-workspace",
				TenantID:    tenantID,
				Name:        "Replay Workspace",
				Description: "Testing event replay",
				CreatedBy:   "replay-user",
			},
		},
		UserCommand{
			Type: "UpdateUser",
			Data: UpdateUserData{
				UserID:    "replay-user",
				FirstName: "Updated",
				LastName:  "Replay",
			},
		},
		WorkspaceCommand{
			Type: "UpdateWorkspace",
			Data: UpdateWorkspaceData{
				WorkspaceID: "replay-workspace",
				Name:        "Updated Replay Workspace",
				Description: "Updated for replay testing",
			},
		},
		PermissionCommand{
			Type: "AssignWorkspacePermission",
			Data: AssignWorkspacePermissionData{
				UserID:      "replay-user",
				WorkspaceID: "replay-workspace",
				Permission:  "workspace.admin",
				GrantedBy:   fixtures.TestUserAlphaAdminID,
			},
		},
	}

	// Execute all commands and wait for projections
	for i, cmd := range commands {
		err := s.commandBus.ExecuteCommand(ctx, cmd)
		require.NoError(s.T(), err, "Command %d should execute successfully", i)
	}

	// Wait for all projections to sync
	projections := []string{"user_projection", "workspace_projection", "permission_projection"}
	for _, projection := range projections {
		success := s.projectionManager.WaitForProjectionSync(ctx, projection, 10*time.Second)
		require.True(s.T(), success, "Projection %s should sync", projection)
	}

	// Capture final state
	finalUserView, err := s.queryService.GetUserView(ctx, "replay-user")
	require.NoError(s.T(), err)
	
	finalWorkspaceView, err := s.queryService.GetWorkspaceView(ctx, "replay-workspace")
	require.NoError(s.T(), err)
	
	finalPermissions, err := s.queryService.GetUserWorkspacePermissions(ctx, "replay-user", "replay-workspace")
	require.NoError(s.T(), err)

	// Act - Clear projections and replay from events
	s.T().Run("Clear_All_Projections", func(t *testing.T) {
		for _, projection := range projections {
			err := s.projectionManager.ClearProjection(ctx, projection)
			require.NoError(t, err, "Should clear projection %s", projection)
		}
	})

	s.T().Run("Replay_Events", func(t *testing.T) {
		// Get all events for replay
		events := s.eventStore.GetAllEvents(ctx)
		assert.NotEmpty(t, events, "Should have events to replay")
		
		// Replay events in order
		err := s.projectionManager.ReplayEvents(ctx, events)
		require.NoError(t, err, "Event replay should succeed")
		
		// Wait for replay completion
		for _, projection := range projections {
			success := s.projectionManager.WaitForProjectionRebuild(ctx, projection, 20*time.Second)
			assert.True(t, success, "Projection %s should complete replay", projection)
		}
	})

	// Assert - Validate replayed state matches original
	s.T().Run("Replayed_User_Matches", func(t *testing.T) {
		replayedUserView, err := s.queryService.GetUserView(ctx, "replay-user")
		require.NoError(t, err)
		
		assert.Equal(t, finalUserView.UserID, replayedUserView.UserID)
		assert.Equal(t, finalUserView.Email, replayedUserView.Email)
		assert.Equal(t, finalUserView.FirstName, replayedUserView.FirstName)
		assert.Equal(t, finalUserView.LastName, replayedUserView.LastName)
		assert.Equal(t, finalUserView.Status, replayedUserView.Status)
	})

	s.T().Run("Replayed_Workspace_Matches", func(t *testing.T) {
		replayedWorkspaceView, err := s.queryService.GetWorkspaceView(ctx, "replay-workspace")
		require.NoError(t, err)
		
		assert.Equal(t, finalWorkspaceView.WorkspaceID, replayedWorkspaceView.WorkspaceID)
		assert.Equal(t, finalWorkspaceView.Name, replayedWorkspaceView.Name)
		assert.Equal(t, finalWorkspaceView.Description, replayedWorkspaceView.Description)
		assert.Equal(t, finalWorkspaceView.CreatedBy, replayedWorkspaceView.CreatedBy)
	})

	s.T().Run("Replayed_Permissions_Match", func(t *testing.T) {
		replayedPermissions, err := s.queryService.GetUserWorkspacePermissions(ctx, "replay-user", "replay-workspace")
		require.NoError(t, err)
		
		assert.Equal(t, len(finalPermissions), len(replayedPermissions))
		for _, permission := range finalPermissions {
			assert.Contains(t, replayedPermissions, permission)
		}
	})

	s.T().Run("Event_Ordering_Validation", func(t *testing.T) {
		// Validate that events were replayed in correct order
		events := s.eventStore.GetEventsByAggregate(ctx, "replay-user")
		
		// Events should be in chronological order
		for i := 1; i < len(events); i++ {
			assert.True(t, events[i].Timestamp.After(events[i-1].Timestamp) || 
						 events[i].Timestamp.Equal(events[i-1].Timestamp),
				"Events should be in chronological order")
		}
	})
}

// Command and Data types for CQRS testing
type UserCommand struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}

type WorkspaceCommand struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}

type PermissionCommand struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}

type AnalyticsCommand struct {
	Type string      `json:"type"`
	Data interface{} `json:"data"`
}

type CreateUserData struct {
	UserID    string `json:"user_id"`
	TenantID  string `json:"tenant_id"`
	Email     string `json:"email"`
	Username  string `json:"username"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
}

type UpdateUserData struct {
	UserID    string `json:"user_id"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Email     string `json:"email,omitempty"`
}

type AssignUserRoleData struct {
	UserID   string `json:"user_id"`
	TenantID string `json:"tenant_id"`
	Role     string `json:"role"`
}

type CreateWorkspaceData struct {
	WorkspaceID string `json:"workspace_id"`
	TenantID    string `json:"tenant_id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	CreatedBy   string `json:"created_by"`
}

type UpdateWorkspaceData struct {
	WorkspaceID string `json:"workspace_id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

type CreateProjectData struct {
	ProjectID   string `json:"project_id"`
	WorkspaceID string `json:"workspace_id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

type CreateBaseData struct {
	BaseID    string `json:"base_id"`
	ProjectID string `json:"project_id"`
	Name      string `json:"name"`
	Type      string `json:"type"`
}

type AssignWorkspacePermissionData struct {
	UserID      string `json:"user_id"`
	WorkspaceID string `json:"workspace_id"`
	Permission  string `json:"permission"`
	GrantedBy   string `json:"granted_by"`
}

type WorkspaceAccessData struct {
	WorkspaceID string `json:"workspace_id"`
	UserID      string `json:"user_id"`
	AccessType  string `json:"access_type"`
	Timestamp   int64  `json:"timestamp"`
}

type DataOperationData struct {
	WorkspaceID   string `json:"workspace_id"`
	UserID        string `json:"user_id"`
	OperationType string `json:"operation_type"`
	RecordCount   int    `json:"record_count"`
	Timestamp     int64  `json:"timestamp"`
}

// Test runner
func TestCQRSProjectionSuite(t *testing.T) {
	suite.Run(t, new(CQRSProjectionTestSuite))
}