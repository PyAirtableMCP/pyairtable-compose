package e2e

import (
	"context"
	"database/sql"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/pyairtable-compose/tests/integration-suite/internal/framework"
	"github.com/pyairtable-compose/tests/integration-suite/internal/fixtures"
)

// UnitOfWorkTestSuite tests Unit of Work pattern transaction scenarios
type UnitOfWorkTestSuite struct {
	suite.Suite
	framework          *framework.TestFramework
	unitOfWork         *framework.UnitOfWork
	userRepository     *framework.UserRepository
	workspaceRepository *framework.WorkspaceRepository
	permissionRepository *framework.PermissionRepository
	auditRepository    *framework.AuditRepository
	transactionMonitor *framework.TransactionMonitor
}

func (s *UnitOfWorkTestSuite) SetupSuite() {
	s.framework = framework.NewTestFramework("unit_of_work")
	require.NoError(s.T(), s.framework.Start())
	
	s.unitOfWork = s.framework.UnitOfWork()
	s.userRepository = s.framework.UserRepository()
	s.workspaceRepository = s.framework.WorkspaceRepository()
	s.permissionRepository = s.framework.PermissionRepository()
	s.auditRepository = s.framework.AuditRepository()
	s.transactionMonitor = s.framework.TransactionMonitor()
}

func (s *UnitOfWorkTestSuite) TearDownSuite() {
	s.framework.Stop()
}

func (s *UnitOfWorkTestSuite) SetupTest() {
	require.NoError(s.T(), s.framework.ResetTestData())
	s.transactionMonitor.Reset()
}

// TestBasicUnitOfWorkCommit tests successful transaction commit with multiple repositories
func (s *UnitOfWorkTestSuite) TestBasicUnitOfWorkCommit() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	userID := "uow-test-user"
	workspaceID := "uow-test-workspace"
	
	user := &User{
		ID:        userID,
		TenantID:  tenantID,
		Email:     "uow@alpha.test.com",
		Username:  "uowuser",
		FirstName: "UoW",
		LastName:  "Test",
		Status:    "active",
		CreatedAt: time.Now(),
	}
	
	workspace := &Workspace{
		ID:          workspaceID,
		TenantID:    tenantID,
		Name:        "UoW Test Workspace",
		Description: "Testing Unit of Work pattern",
		CreatedBy:   userID,
		Status:      "active",
		CreatedAt:   time.Now(),
	}
	
	permission := &Permission{
		UserID:      userID,
		ResourceID:  workspaceID,
		ResourceType: "workspace",
		Permission:  "admin",
		GrantedBy:   fixtures.TestUserAlphaAdminID,
		GrantedAt:   time.Now(),
	}

	// Act - Execute operations within a single unit of work
	err := s.unitOfWork.Execute(ctx, func(uow *framework.UnitOfWork) error {
		// Register all aggregates with the unit of work
		uow.RegisterNew(user)
		uow.RegisterNew(workspace)
		uow.RegisterNew(permission)
		
		// Perform repository operations
		if err := s.userRepository.Save(uow, user); err != nil {
			return fmt.Errorf("failed to save user: %w", err)
		}
		
		if err := s.workspaceRepository.Save(uow, workspace); err != nil {
			return fmt.Errorf("failed to save workspace: %w", err)
		}
		
		if err := s.permissionRepository.Save(uow, permission); err != nil {
			return fmt.Errorf("failed to save permission: %w", err)
		}
		
		return nil
	})
	
	require.NoError(s.T(), err)

	// Assert - Validate all changes were committed atomically
	s.T().Run("User_Persisted", func(t *testing.T) {
		savedUser, err := s.userRepository.FindByID(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, user.ID, savedUser.ID)
		assert.Equal(t, user.Email, savedUser.Email)
		assert.Equal(t, "active", savedUser.Status)
	})

	s.T().Run("Workspace_Persisted", func(t *testing.T) {
		savedWorkspace, err := s.workspaceRepository.FindByID(ctx, workspaceID)
		require.NoError(t, err)
		assert.Equal(t, workspace.ID, savedWorkspace.ID)
		assert.Equal(t, workspace.Name, savedWorkspace.Name)
		assert.Equal(t, userID, savedWorkspace.CreatedBy)
	})

	s.T().Run("Permission_Persisted", func(t *testing.T) {
		savedPermission, err := s.permissionRepository.FindByUserAndResource(ctx, userID, workspaceID)
		require.NoError(t, err)
		assert.Equal(t, permission.Permission, savedPermission.Permission)
		assert.Equal(t, permission.GrantedBy, savedPermission.GrantedBy)
	})

	s.T().Run("Transaction_Boundaries_Respected", func(t *testing.T) {
		transactionLog := s.transactionMonitor.GetTransactionLog()
		assert.Len(t, transactionLog, 1, "Should have exactly one transaction")
		
		transaction := transactionLog[0]
		assert.Equal(t, "committed", transaction.Status)
		assert.Len(t, transaction.Operations, 3) // User, Workspace, Permission
		assert.True(t, transaction.EndTime.After(transaction.StartTime))
	})
}

// TestUnitOfWorkRollback tests transaction rollback when operations fail
func (s *UnitOfWorkTestSuite) TestUnitOfWorkRollback() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	userID := "uow-rollback-user"
	workspaceID := "uow-rollback-workspace"
	
	user := &User{
		ID:        userID,
		TenantID:  tenantID,
		Email:     "rollback@alpha.test.com",
		Username:  "rollbackuser",
		FirstName: "Rollback",
		LastName:  "Test",
		Status:    "active",
		CreatedAt: time.Now(),
	}
	
	workspace := &Workspace{
		ID:          workspaceID,
		TenantID:    tenantID,
		Name:        "Rollback Test Workspace",
		Description: "Testing rollback behavior",
		CreatedBy:   userID,
		Status:      "active",
		CreatedAt:   time.Now(),
	}

	// Act - Execute operations where one fails
	err := s.unitOfWork.Execute(ctx, func(uow *framework.UnitOfWork) error {
		uow.RegisterNew(user)
		uow.RegisterNew(workspace)
		
		// Save user successfully
		if err := s.userRepository.Save(uow, user); err != nil {
			return fmt.Errorf("failed to save user: %w", err)
		}
		
		// Save workspace successfully
		if err := s.workspaceRepository.Save(uow, workspace); err != nil {
			return fmt.Errorf("failed to save workspace: %w", err)
		}
		
		// Intentionally fail on permission creation
		invalidPermission := &Permission{
			UserID:       "", // Invalid - empty user ID
			ResourceID:   workspaceID,
			ResourceType: "workspace",
			Permission:   "admin",
		}
		
		return s.permissionRepository.Save(uow, invalidPermission)
	})
	
	require.Error(s.T(), err, "Transaction should fail due to invalid permission")

	// Assert - Validate all changes were rolled back
	s.T().Run("User_Not_Persisted", func(t *testing.T) {
		_, err := s.userRepository.FindByID(ctx, userID)
		assert.Error(t, err, "User should not exist after rollback")
	})

	s.T().Run("Workspace_Not_Persisted", func(t *testing.T) {
		_, err := s.workspaceRepository.FindByID(ctx, workspaceID)
		assert.Error(t, err, "Workspace should not exist after rollback")
	})

	s.T().Run("Transaction_Rolled_Back", func(t *testing.T) {
		transactionLog := s.transactionMonitor.GetTransactionLog()
		assert.Len(t, transactionLog, 1, "Should have exactly one transaction")
		
		transaction := transactionLog[0]
		assert.Equal(t, "rolled_back", transaction.Status)
		assert.NotEmpty(t, transaction.ErrorMessage)
	})
}

// TestNestedUnitOfWork tests nested unit of work scenarios
func (s *UnitOfWorkTestSuite) TestNestedUnitOfWork() {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	parentUserID := "nested-parent-user"
	childUserID := "nested-child-user"
	workspaceID := "nested-workspace"

	// Act - Execute nested unit of work
	err := s.unitOfWork.Execute(ctx, func(outerUow *framework.UnitOfWork) error {
		// Outer transaction - create parent user
		parentUser := &User{
			ID:        parentUserID,
			TenantID:  tenantID,
			Email:     "parent@alpha.test.com",
			Username:  "parentuser",
			FirstName: "Parent",
			LastName:  "User",
			Status:    "active",
			CreatedAt: time.Now(),
		}
		
		outerUow.RegisterNew(parentUser)
		if err := s.userRepository.Save(outerUow, parentUser); err != nil {
			return err
		}
		
		// Nested transaction - create child user and workspace
		return s.unitOfWork.Execute(ctx, func(innerUow *framework.UnitOfWork) error {
			childUser := &User{
				ID:        childUserID,
				TenantID:  tenantID,
				Email:     "child@alpha.test.com",
				Username:  "childuser",
				FirstName: "Child",
				LastName:  "User",
				Status:    "active",
				CreatedAt: time.Now(),
			}
			
			workspace := &Workspace{
				ID:          workspaceID,
				TenantID:    tenantID,
				Name:        "Nested Workspace",
				Description: "Testing nested transactions",
				CreatedBy:   parentUserID,
				Status:      "active",
				CreatedAt:   time.Now(),
			}
			
			innerUow.RegisterNew(childUser)
			innerUow.RegisterNew(workspace)
			
			if err := s.userRepository.Save(innerUow, childUser); err != nil {
				return err
			}
			
			return s.workspaceRepository.Save(innerUow, workspace)
		})
	})
	
	require.NoError(s.T(), err)

	// Assert - Validate nested transaction behavior
	s.T().Run("All_Entities_Persisted", func(t *testing.T) {
		// Parent user should exist
		parentUser, err := s.userRepository.FindByID(ctx, parentUserID)
		require.NoError(t, err)
		assert.Equal(t, "Parent", parentUser.FirstName)
		
		// Child user should exist
		childUser, err := s.userRepository.FindByID(ctx, childUserID)
		require.NoError(t, err)
		assert.Equal(t, "Child", childUser.FirstName)
		
		// Workspace should exist
		workspace, err := s.workspaceRepository.FindByID(ctx, workspaceID)
		require.NoError(t, err)
		assert.Equal(t, parentUserID, workspace.CreatedBy)
	})

	s.T().Run("Nested_Transaction_Isolation", func(t *testing.T) {
		transactionLog := s.transactionMonitor.GetTransactionLog()
		assert.Len(t, transactionLog, 2, "Should have outer and inner transactions")
		
		// Verify transaction hierarchy
		outerTx := transactionLog[0]
		innerTx := transactionLog[1]
		
		assert.Empty(t, outerTx.ParentTransactionID, "Outer transaction should have no parent")
		assert.Equal(t, outerTx.TransactionID, innerTx.ParentTransactionID, "Inner transaction should have outer as parent")
	})
}

// TestConcurrentUnitOfWork tests concurrent unit of work operations
func (s *UnitOfWorkTestSuite) TestConcurrentUnitOfWork() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	concurrencyLevel := 5
	
	results := make(chan error, concurrencyLevel)
	
	// Act - Execute multiple concurrent unit of work operations
	for i := 0; i < concurrencyLevel; i++ {
		go func(index int) {
			userID := fmt.Sprintf("concurrent-user-%d", index)
			workspaceID := fmt.Sprintf("concurrent-workspace-%d", index)
			
			err := s.unitOfWork.Execute(ctx, func(uow *framework.UnitOfWork) error {
				user := &User{
					ID:        userID,
					TenantID:  tenantID,
					Email:     fmt.Sprintf("concurrent%d@alpha.test.com", index),
					Username:  fmt.Sprintf("user%d", index),
					FirstName: "Concurrent",
					LastName:  fmt.Sprintf("User%d", index),
					Status:    "active",
					CreatedAt: time.Now(),
				}
				
				workspace := &Workspace{
					ID:          workspaceID,
					TenantID:    tenantID,
					Name:        fmt.Sprintf("Concurrent Workspace %d", index),
					Description: "Testing concurrent operations",
					CreatedBy:   userID,
					Status:      "active",
					CreatedAt:   time.Now(),
				}
				
				uow.RegisterNew(user)
				uow.RegisterNew(workspace)
				
				if err := s.userRepository.Save(uow, user); err != nil {
					return err
				}
				
				// Add a small delay to increase chance of contention
				time.Sleep(10 * time.Millisecond)
				
				return s.workspaceRepository.Save(uow, workspace)
			})
			
			results <- err
		}(i)
	}
	
	// Wait for all operations to complete
	var errors []error
	for i := 0; i < concurrencyLevel; i++ {
		if err := <-results; err != nil {
			errors = append(errors, err)
		}
	}

	// Assert - Validate concurrent execution
	s.T().Run("All_Operations_Succeed", func(t *testing.T) {
		assert.Empty(t, errors, "All concurrent operations should succeed")
	})

	s.T().Run("All_Users_Created", func(t *testing.T) {
		for i := 0; i < concurrencyLevel; i++ {
			userID := fmt.Sprintf("concurrent-user-%d", i)
			user, err := s.userRepository.FindByID(ctx, userID)
			require.NoError(t, err, "User %d should exist", i)
			assert.Equal(t, fmt.Sprintf("User%d", i), user.LastName)
		}
	})

	s.T().Run("All_Workspaces_Created", func(t *testing.T) {
		for i := 0; i < concurrencyLevel; i++ {
			workspaceID := fmt.Sprintf("concurrent-workspace-%d", i)
			workspace, err := s.workspaceRepository.FindByID(ctx, workspaceID)
			require.NoError(t, err, "Workspace %d should exist", i)
			assert.Equal(t, fmt.Sprintf("Concurrent Workspace %d", i), workspace.Name)
		}
	})

	s.T().Run("Transaction_Isolation_Maintained", func(t *testing.T) {
		transactionLog := s.transactionMonitor.GetTransactionLog()
		assert.Len(t, transactionLog, concurrencyLevel, "Should have one transaction per operation")
		
		// Verify all transactions completed successfully
		for _, transaction := range transactionLog {
			assert.Equal(t, "committed", transaction.Status)
		}
	})
}

// TestUnitOfWorkWithEvents tests unit of work integration with domain events
func (s *UnitOfWorkTestSuite) TestUnitOfWorkWithEvents() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	userID := "event-user"
	workspaceID := "event-workspace"

	// Act - Execute operation that produces domain events
	err := s.unitOfWork.Execute(ctx, func(uow *framework.UnitOfWork) error {
		user := &User{
			ID:        userID,
			TenantID:  tenantID,
			Email:     "events@alpha.test.com",
			Username:  "eventuser",
			FirstName: "Event",
			LastName:  "User",
			Status:    "active",
			CreatedAt: time.Now(),
		}
		
		workspace := &Workspace{
			ID:          workspaceID,
			TenantID:    tenantID,
			Name:        "Event Workspace",
			Description: "Testing event generation",
			CreatedBy:   userID,
			Status:      "active",
			CreatedAt:   time.Now(),
		}
		
		// Register aggregates (these will produce domain events)
		uow.RegisterNew(user)
		uow.RegisterNew(workspace)
		
		// Add custom domain events
		uow.AddEvent(&framework.DomainEvent{
			AggregateID:   userID,
			AggregateType: "User",
			EventType:     "user.created.via.uow",
			EventVersion:  1,
			Payload: map[string]interface{}{
				"user_id":   userID,
				"tenant_id": tenantID,
				"source":    "unit_of_work_test",
			},
			TenantID: tenantID,
		})
		
		uow.AddEvent(&framework.DomainEvent{
			AggregateID:   workspaceID,
			AggregateType: "Workspace",
			EventType:     "workspace.created.via.uow",
			EventVersion:  1,
			Payload: map[string]interface{}{
				"workspace_id": workspaceID,
				"created_by":   userID,
				"tenant_id":    tenantID,
			},
			TenantID: tenantID,
		})
		
		if err := s.userRepository.Save(uow, user); err != nil {
			return err
		}
		
		return s.workspaceRepository.Save(uow, workspace)
	})
	
	require.NoError(s.T(), err)

	// Assert - Validate events were published atomically with data changes
	s.T().Run("Domain_Events_Published", func(t *testing.T) {
		events := s.framework.EventStore().GetEventsByAggregate(ctx, userID)
		var foundUserEvent bool
		for _, event := range events {
			if event.EventType == "user.created.via.uow" {
				foundUserEvent = true
				break
			}
		}
		assert.True(t, foundUserEvent, "Custom user event should be published")
		
		workspaceEvents := s.framework.EventStore().GetEventsByAggregate(ctx, workspaceID)
		var foundWorkspaceEvent bool
		for _, event := range workspaceEvents {
			if event.EventType == "workspace.created.via.uow" {
				foundWorkspaceEvent = true
				break
			}
		}
		assert.True(t, foundWorkspaceEvent, "Custom workspace event should be published")
	})

	s.T().Run("Events_And_Data_Atomic", func(t *testing.T) {
		// Both entities should exist
		user, err := s.userRepository.FindByID(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, "Event", user.FirstName)
		
		workspace, err := s.workspaceRepository.FindByID(ctx, workspaceID)
		require.NoError(t, err)
		assert.Equal(t, userID, workspace.CreatedBy)
		
		// Events should be committed in same transaction
		transactionLog := s.transactionMonitor.GetTransactionLog()
		assert.Len(t, transactionLog, 1)
		transaction := transactionLog[0]
		assert.Equal(t, "committed", transaction.Status)
		assert.Greater(t, len(transaction.Events), 0, "Transaction should include events")
	})
}

// TestUnitOfWorkPerformance tests performance characteristics of unit of work
func (s *UnitOfWorkTestSuite) TestUnitOfWorkPerformance() {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	operationCount := 100
	
	startTime := time.Now()

	// Act - Execute many operations
	for i := 0; i < operationCount; i++ {
		userID := fmt.Sprintf("perf-user-%d", i)
		workspaceID := fmt.Sprintf("perf-workspace-%d", i)
		
		err := s.unitOfWork.Execute(ctx, func(uow *framework.UnitOfWork) error {
			user := &User{
				ID:        userID,
				TenantID:  tenantID,
				Email:     fmt.Sprintf("perf%d@alpha.test.com", i),
				Username:  fmt.Sprintf("perfuser%d", i),
				FirstName: "Performance",
				LastName:  fmt.Sprintf("User%d", i),
				Status:    "active",
				CreatedAt: time.Now(),
			}
			
			workspace := &Workspace{
				ID:          workspaceID,
				TenantID:    tenantID,
				Name:        fmt.Sprintf("Performance Workspace %d", i),
				Description: "Performance testing",
				CreatedBy:   userID,
				Status:      "active",
				CreatedAt:   time.Now(),
			}
			
			uow.RegisterNew(user)
			uow.RegisterNew(workspace)
			
			if err := s.userRepository.Save(uow, user); err != nil {
				return err
			}
			
			return s.workspaceRepository.Save(uow, workspace)
		})
		
		require.NoError(s.T(), err, "Operation %d should succeed", i)
	}
	
	totalTime := time.Since(startTime)

	// Assert - Validate performance characteristics
	s.T().Run("Performance_Benchmarks", func(t *testing.T) {
		averageTime := totalTime / time.Duration(operationCount)
		assert.Less(t, averageTime, 100*time.Millisecond, "Average operation time should be under 100ms")
		
		transactionLog := s.transactionMonitor.GetTransactionLog()
		assert.Len(t, transactionLog, operationCount)
		
		// Calculate transaction statistics
		var totalTxTime time.Duration
		for _, tx := range transactionLog {
			totalTxTime += tx.EndTime.Sub(tx.StartTime)
		}
		
		averageTxTime := totalTxTime / time.Duration(len(transactionLog))
		assert.Less(t, averageTxTime, 50*time.Millisecond, "Average transaction time should be under 50ms")
	})

	s.T().Run("Resource_Usage_Optimal", func(t *testing.T) {
		stats := s.transactionMonitor.GetStatistics()
		
		// Connection pool should be efficiently used
		assert.Less(t, stats.MaxConcurrentConnections, 10, "Should not use too many connections")
		assert.Equal(t, 0, stats.ConnectionLeaks, "Should have no connection leaks")
		
		// Memory usage should be reasonable
		assert.Less(t, stats.PeakMemoryUsage, 100*1024*1024, "Peak memory usage should be under 100MB")
	})
}

// Helper types for unit of work testing
type Workspace struct {
	ID          string    `json:"id"`
	TenantID    string    `json:"tenant_id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatedBy   string    `json:"created_by"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

type Permission struct {
	UserID       string    `json:"user_id"`
	ResourceID   string    `json:"resource_id"`
	ResourceType string    `json:"resource_type"`
	Permission   string    `json:"permission"`
	GrantedBy    string    `json:"granted_by"`
	GrantedAt    time.Time `json:"granted_at"`
}

// Test runner
func TestUnitOfWorkSuite(t *testing.T) {
	suite.Run(t, new(UnitOfWorkTestSuite))
}