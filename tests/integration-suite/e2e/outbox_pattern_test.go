package e2e

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/pyairtable-compose/tests/integration-suite/internal/framework"
	"github.com/pyairtable-compose/tests/integration-suite/internal/fixtures"
)

// OutboxPatternTestSuite tests the transactional outbox pattern implementation
type OutboxPatternTestSuite struct {
	suite.Suite
	framework       *framework.TestFramework
	outboxService   *framework.OutboxService
	eventPublisher  *framework.EventPublisher
	messageMonitor  *framework.MessageMonitor
	failureInjector *framework.FailureInjector
}

func (s *OutboxPatternTestSuite) SetupSuite() {
	s.framework = framework.NewTestFramework("outbox_pattern")
	require.NoError(s.T(), s.framework.Start())
	
	s.outboxService = s.framework.OutboxService()
	s.eventPublisher = s.framework.EventPublisher()
	s.messageMonitor = s.framework.MessageMonitor()
	s.failureInjector = s.framework.FailureInjector()
}

func (s *OutboxPatternTestSuite) TearDownSuite() {
	s.framework.Stop()
}

func (s *OutboxPatternTestSuite) SetupTest() {
	require.NoError(s.T(), s.framework.ResetTestData())
	require.NoError(s.T(), s.outboxService.ClearOutboxTables())
	s.failureInjector.Reset()
}

// TestTransactionalEventPublishing tests that events are stored in outbox with business data
func (s *OutboxPatternTestSuite) TestTransactionalEventPublishing() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange
	tenantID := fixtures.TestTenantAlphaID
	userID := "outbox-test-user"
	
	operation := &OutboxOperation{
		BusinessOperation: func(tx framework.Transaction) error {
			// Simulate business logic that creates a user
			user := &User{
				ID:        userID,
				TenantID:  tenantID,
				Email:     "outbox@alpha.test.com",
				Username:  "outboxuser",
				FirstName: "Outbox",
				LastName:  "Test",
				Status:    "active",
				CreatedAt: time.Now(),
			}
			return s.framework.UserRepository().CreateUser(tx, user)
		},
		Events: []framework.DomainEvent{
			{
				AggregateID:   userID,
				AggregateType: "User",
				EventType:     "user.created",
				EventVersion:  1,
				Payload: map[string]interface{}{
					"user_id":    userID,
					"tenant_id":  tenantID,
					"email":      "outbox@alpha.test.com",
					"username":   "outboxuser",
					"first_name": "Outbox",
					"last_name":  "Test",
				},
				Metadata: map[string]interface{}{
					"source":     "user-service",
					"ip_address": "127.0.0.1",
					"user_agent": "test-client",
				},
				TenantID:      tenantID,
				CorrelationID: "test-correlation-123",
				CausationID:   "test-causation-456",
			},
			{
				AggregateID:   userID,
				AggregateType: "User",
				EventType:     "user.profile.initialized",
				EventVersion:  1,
				Payload: map[string]interface{}{
					"user_id":   userID,
					"tenant_id": tenantID,
					"profile": map[string]interface{}{
						"first_name": "Outbox",
						"last_name":  "Test",
						"email":      "outbox@alpha.test.com",
					},
				},
				TenantID:      tenantID,
				CorrelationID: "test-correlation-123",
				CausationID:   "test-causation-456",
			},
		},
	}

	// Act - Execute operation with outbox pattern
	err := s.outboxService.ExecuteWithOutbox(ctx, operation)
	require.NoError(s.T(), err)

	// Assert - Validate transactional consistency
	s.T().Run("Business_Data_Persisted", func(t *testing.T) {
		user, err := s.framework.UserRepository().GetUser(ctx, userID)
		require.NoError(t, err)
		assert.Equal(t, userID, user.ID)
		assert.Equal(t, "outbox@alpha.test.com", user.Email)
		assert.Equal(t, "active", user.Status)
	})

	s.T().Run("Events_In_Outbox", func(t *testing.T) {
		outboxEntries, err := s.outboxService.GetOutboxEntries(ctx, userID)
		require.NoError(t, err)
		assert.Len(t, outboxEntries, 2)
		
		eventTypes := make([]string, len(outboxEntries))
		for i, entry := range outboxEntries {
			eventTypes[i] = entry.EventType
		}
		
		assert.Contains(t, eventTypes, "user.created")
		assert.Contains(t, eventTypes, "user.profile.initialized")
		
		// Verify event details
		for _, entry := range outboxEntries {
			assert.Equal(t, userID, entry.AggregateID)
			assert.Equal(t, "User", entry.AggregateType)
			assert.Equal(t, tenantID, entry.TenantID)
			assert.Equal(t, "test-correlation-123", entry.CorrelationID)
			assert.Equal(t, "pending", entry.Status)
		}
	})

	s.T().Run("Events_Published_Successfully", func(t *testing.T) {
		// Wait for outbox processor to publish events
		success := s.messageMonitor.WaitForEventPublication(ctx, userID, 10*time.Second)
		assert.True(t, success, "Events should be published from outbox")
		
		// Verify events were published to all configured publishers
		publishedEvents := s.eventPublisher.GetPublishedEvents(ctx, userID)
		assert.Len(t, publishedEvents, 2)
		
		for _, event := range publishedEvents {
			assert.Equal(t, "published", event.Status)
			assert.NotEmpty(t, event.PublishedAt)
		}
	})

	s.T().Run("Outbox_Entries_Marked_Processed", func(t *testing.T) {
		outboxEntries, err := s.outboxService.GetOutboxEntries(ctx, userID)
		require.NoError(t, err)
		
		for _, entry := range outboxEntries {
			assert.Equal(t, "processed", entry.Status)
			assert.NotEmpty(t, entry.ProcessedAt)
			assert.Equal(t, 0, entry.RetryCount)
		}
	})
}

// TestOutboxReliabilityWithFailures tests outbox behavior under various failure scenarios
func (s *OutboxPatternTestSuite) TestOutboxReliabilityWithFailures() {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	// Arrange - Setup operation with multiple events
	tenantID := fixtures.TestTenantAlphaID
	userID := "failure-test-user"
	
	operation := &OutboxOperation{
		BusinessOperation: func(tx framework.Transaction) error {
			user := &User{
				ID:        userID,
				TenantID:  tenantID,
				Email:     "failure@alpha.test.com",
				Username:  "failureuser",
				FirstName: "Failure",
				LastName:  "Test",
				Status:    "active",
				CreatedAt: time.Now(),
			}
			return s.framework.UserRepository().CreateUser(tx, user)
		},
		Events: []framework.DomainEvent{
			{
				AggregateID:   userID,
				AggregateType: "User",
				EventType:     "user.created",
				EventVersion:  1,
				Payload:       map[string]interface{}{"user_id": userID},
				TenantID:      tenantID,
			},
			{
				AggregateID:   userID,
				AggregateType: "User",
				EventType:     "user.welcome.email.scheduled",
				EventVersion:  1,
				Payload:       map[string]interface{}{"user_id": userID, "email": "failure@alpha.test.com"},
				TenantID:      tenantID,
			},
		},
	}

	// Execute operation
	err := s.outboxService.ExecuteWithOutbox(ctx, operation)
	require.NoError(s.T(), err)

	// Act & Assert - Test various failure scenarios
	s.T().Run("Publisher_Temporary_Failure", func(t *testing.T) {
		// Inject temporary failure in event publisher
		s.failureInjector.InjectPublisherFailure("kafka", 3) // Fail 3 times then succeed
		
		// Wait for retry attempts
		time.Sleep(5 * time.Second)
		
		// Events should eventually be published after retries
		success := s.messageMonitor.WaitForEventPublication(ctx, userID, 30*time.Second)
		assert.True(t, success, "Events should be published after retries")
		
		// Verify retry attempts were made
		outboxEntries, err := s.outboxService.GetOutboxEntries(ctx, userID)
		require.NoError(t, err)
		
		for _, entry := range outboxEntries {
			assert.Equal(t, "processed", entry.Status)
			assert.Greater(t, entry.RetryCount, 0, "Should have retry attempts")
			assert.LessOrEqual(t, entry.RetryCount, 3, "Should not exceed failure count")
		}
	})

	s.T().Run("Publisher_Permanent_Failure", func(t *testing.T) {
		// Create new operation with permanent failure
		permanentFailUserID := "permanent-fail-user"
		permanentFailOperation := &OutboxOperation{
			BusinessOperation: func(tx framework.Transaction) error {
				user := &User{
					ID:       permanentFailUserID,
					TenantID: tenantID,
					Email:    "permanent@alpha.test.com",
					Username: "permanentuser",
					Status:   "active",
				}
				return s.framework.UserRepository().CreateUser(tx, user)
			},
			Events: []framework.DomainEvent{
				{
					AggregateID:   permanentFailUserID,
					AggregateType: "User",
					EventType:     "user.created",
					EventVersion:  1,
					Payload:       map[string]interface{}{"user_id": permanentFailUserID},
					TenantID:      tenantID,
				},
			},
		}
		
		// Inject permanent failure
		s.failureInjector.InjectPermanentPublisherFailure("kafka")
		
		err := s.outboxService.ExecuteWithOutbox(ctx, permanentFailOperation)
		require.NoError(t, err)
		
		// Wait for max retries
		time.Sleep(15 * time.Second)
		
		// Event should be moved to dead letter queue
		deadLetterEntries := s.outboxService.GetDeadLetterEntries(ctx, permanentFailUserID)
		assert.Len(t, deadLetterEntries, 1)
		
		entry := deadLetterEntries[0]
		assert.Equal(t, "failed", entry.Status)
		assert.Equal(t, s.outboxService.GetMaxRetries(), entry.RetryCount)
		assert.NotEmpty(t, entry.ErrorMessage)
	})

	s.T().Run("Database_Transaction_Failure", func(t *testing.T) {
		// Test transaction rollback when business operation fails
		failingOperation := &OutboxOperation{
			BusinessOperation: func(tx framework.Transaction) error {
				// Intentionally fail the business operation
				return assert.AnError
			},
			Events: []framework.DomainEvent{
				{
					AggregateID:   "should-not-exist",
					AggregateType: "User",
					EventType:     "user.created",
					EventVersion:  1,
					Payload:       map[string]interface{}{"user_id": "should-not-exist"},
					TenantID:      tenantID,
				},
			},
		}
		
		// Operation should fail
		err := s.outboxService.ExecuteWithOutbox(ctx, failingOperation)
		assert.Error(t, err, "Operation should fail due to business logic error")
		
		// No events should be in outbox
		outboxEntries, err := s.outboxService.GetOutboxEntries(ctx, "should-not-exist")
		require.NoError(t, err)
		assert.Empty(t, outboxEntries, "No events should be stored when transaction fails")
	})
}

// TestOutboxOrdering tests that events maintain proper ordering
func (s *OutboxPatternTestSuite) TestOutboxOrdering() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Arrange - Create multiple operations with ordered events
	tenantID := fixtures.TestTenantAlphaID
	baseUserID := "ordering-test-user"
	
	operations := make([]*OutboxOperation, 5)
	for i := 0; i < 5; i++ {
		userID := baseUserID + "-" + string(rune('1'+i))
		operations[i] = &OutboxOperation{
			BusinessOperation: func(tx framework.Transaction) error {
				user := &User{
					ID:       userID,
					TenantID: tenantID,
					Email:    userID + "@alpha.test.com",
					Username: userID,
					Status:   "active",
				}
				return s.framework.UserRepository().CreateUser(tx, user)
			},
			Events: []framework.DomainEvent{
				{
					AggregateID:   userID,
					AggregateType: "User",
					EventType:     "user.created",
					EventVersion:  1,
					Payload:       map[string]interface{}{"user_id": userID, "sequence": i + 1},
					TenantID:      tenantID,
				},
			},
		}
	}

	// Act - Execute operations in sequence
	for i, operation := range operations {
		err := s.outboxService.ExecuteWithOutbox(ctx, operation)
		require.NoError(s.T(), err, "Operation %d should succeed", i+1)
		
		// Small delay to ensure ordering
		time.Sleep(10 * time.Millisecond)
	}

	// Wait for all events to be published
	success := s.messageMonitor.WaitForMultipleEventPublication(ctx, []string{
		baseUserID + "-1", baseUserID + "-2", baseUserID + "-3", 
		baseUserID + "-4", baseUserID + "-5",
	}, 15*time.Second)
	require.True(s.T(), success)

	// Assert - Validate event ordering
	s.T().Run("Outbox_Entries_Ordered", func(t *testing.T) {
		allEntries := s.outboxService.GetAllOutboxEntries(ctx)
		
		// Filter entries for our test
		var testEntries []framework.OutboxEntry
		for _, entry := range allEntries {
			if entry.AggregateType == "User" && entry.EventType == "user.created" {
				testEntries = append(testEntries, entry)
			}
		}
		
		assert.Len(t, testEntries, 5)
		
		// Verify chronological ordering
		for i := 1; i < len(testEntries); i++ {
			assert.True(t, testEntries[i].CreatedAt.After(testEntries[i-1].CreatedAt) ||
						  testEntries[i].CreatedAt.Equal(testEntries[i-1].CreatedAt),
				"Events should be in chronological order")
		}
	})

	s.T().Run("Published_Events_Ordered", func(t *testing.T) {
		publishedEvents := s.eventPublisher.GetAllPublishedEvents(ctx)
		
		var userCreatedEvents []framework.PublishedEvent
		for _, event := range publishedEvents {
			if event.EventType == "user.created" {
				userCreatedEvents = append(userCreatedEvents, event)
			}
		}
		
		assert.Len(t, userCreatedEvents, 5)
		
		// Verify sequence numbers in payload
		for i, event := range userCreatedEvents {
			payload := event.Payload.(map[string]interface{})
			sequence := int(payload["sequence"].(float64))
			assert.Equal(t, i+1, sequence, "Event sequence should match execution order")
		}
	})
}

// TestOutboxBatchProcessing tests batch processing of outbox entries
func (s *OutboxPatternTestSuite) TestOutboxBatchProcessing() {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	// Arrange - Create many operations to trigger batch processing
	tenantID := fixtures.TestTenantAlphaID
	batchSize := 20
	
	operations := make([]*OutboxOperation, batchSize)
	userIDs := make([]string, batchSize)
	
	for i := 0; i < batchSize; i++ {
		userID := "batch-user-" + string(rune('1'+i%10)) + "-" + string(rune('a'+i/10))
		userIDs[i] = userID
		
		operations[i] = &OutboxOperation{
			BusinessOperation: func(tx framework.Transaction) error {
				user := &User{
					ID:       userID,
					TenantID: tenantID,
					Email:    userID + "@alpha.test.com",
					Username: userID,
					Status:   "active",
				}
				return s.framework.UserRepository().CreateUser(tx, user)
			},
			Events: []framework.DomainEvent{
				{
					AggregateID:   userID,
					AggregateType: "User",
					EventType:     "user.created",
					EventVersion:  1,
					Payload:       map[string]interface{}{"user_id": userID, "batch_id": i / 5},
					TenantID:      tenantID,
				},
			},
		}
	}

	// Act - Execute all operations rapidly
	for i, operation := range operations {
		err := s.outboxService.ExecuteWithOutbox(ctx, operation)
		require.NoError(s.T(), err, "Batch operation %d should succeed", i+1)
	}

	// Wait for batch processing
	success := s.messageMonitor.WaitForMultipleEventPublication(ctx, userIDs, 30*time.Second)
	require.True(s.T(), success, "All batch events should be published")

	// Assert - Validate batch processing behavior
	s.T().Run("All_Events_Processed", func(t *testing.T) {
		processedCount := 0
		for _, userID := range userIDs {
			entries, err := s.outboxService.GetOutboxEntries(ctx, userID)
			require.NoError(t, err)
			
			for _, entry := range entries {
				if entry.Status == "processed" {
					processedCount++
				}
			}
		}
		
		assert.Equal(t, batchSize, processedCount, "All events should be processed")
	})

	s.T().Run("Batch_Processing_Efficiency", func(t *testing.T) {
		// Verify that events were processed in batches, not individually
		processingStats := s.outboxService.GetProcessingStatistics(ctx)
		
		assert.Greater(t, processingStats.BatchCount, 0, "Should have batch processing")
		assert.Greater(t, processingStats.AverageBatchSize, 1.0, "Should process multiple events per batch")
		assert.LessOrEqual(t, processingStats.TotalBatches*processingStats.AverageBatchSize, 
						   float64(batchSize*1.5), "Should be efficient in batching")
	})

	s.T().Run("No_Event_Loss", func(t *testing.T) {
		publishedEvents := s.eventPublisher.GetAllPublishedEvents(ctx)
		
		var batchUserEvents []framework.PublishedEvent
		for _, event := range publishedEvents {
			if event.EventType == "user.created" {
				for _, userID := range userIDs {
					if event.AggregateID == userID {
						batchUserEvents = append(batchUserEvents, event)
						break
					}
				}
			}
		}
		
		assert.Len(t, batchUserEvents, batchSize, "No events should be lost during batch processing")
	})
}

// TestOutboxCircuitBreaker tests circuit breaker functionality
func (s *OutboxPatternTestSuite) TestOutboxCircuitBreaker() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Arrange - Configure circuit breaker for testing
	s.outboxService.ConfigureCircuitBreaker(5, 10*time.Second) // 5 failures, 10s timeout

	tenantID := fixtures.TestTenantAlphaID
	
	// Act - Trigger circuit breaker with multiple failures
	s.T().Run("Circuit_Breaker_Triggers", func(t *testing.T) {
		// Inject failures to trigger circuit breaker
		s.failureInjector.InjectPermanentPublisherFailure("kafka")
		
		// Create operations that will fail
		for i := 0; i < 6; i++ { // One more than circuit breaker threshold
			userID := "circuit-breaker-user-" + string(rune('1'+i))
			operation := &OutboxOperation{
				BusinessOperation: func(tx framework.Transaction) error {
					user := &User{
						ID:       userID,
						TenantID: tenantID,
						Email:    userID + "@alpha.test.com",
						Username: userID,
						Status:   "active",
					}
					return s.framework.UserRepository().CreateUser(tx, user)
				},
				Events: []framework.DomainEvent{
					{
						AggregateID:   userID,
						AggregateType: "User",
						EventType:     "user.created",
						EventVersion:  1,
						Payload:       map[string]interface{}{"user_id": userID},
						TenantID:      tenantID,
					},
				},
			}
			
			err := s.outboxService.ExecuteWithOutbox(ctx, operation)
			require.NoError(t, err, "Business operation should succeed even with publisher failures")
		}
		
		// Wait for circuit breaker to trigger
		time.Sleep(5 * time.Second)
		
		// Circuit breaker should be open
		assert.True(t, s.outboxService.IsCircuitBreakerOpen(), "Circuit breaker should be open")
	})

	s.T().Run("Circuit_Breaker_Prevents_Further_Attempts", func(t *testing.T) {
		// Create another operation while circuit breaker is open
		userID := "circuit-breaker-blocked-user"
		operation := &OutboxOperation{
			BusinessOperation: func(tx framework.Transaction) error {
				user := &User{
					ID:       userID,
					TenantID: tenantID,
					Email:    userID + "@alpha.test.com",
					Username: userID,
					Status:   "active",
				}
				return s.framework.UserRepository().CreateUser(tx, user)
			},
			Events: []framework.DomainEvent{
				{
					AggregateID:   userID,
					AggregateType: "User",
					EventType:     "user.created",
					EventVersion:  1,
					Payload:       map[string]interface{}{"user_id": userID},
					TenantID:      tenantID,
				},
			},
		}
		
		err := s.outboxService.ExecuteWithOutbox(ctx, operation)
		require.NoError(t, err, "Business operation should still succeed")
		
		// Event should be in outbox but not attempted for publishing
		entries, err := s.outboxService.GetOutboxEntries(ctx, userID)
		require.NoError(t, err)
		assert.Len(t, entries, 1)
		assert.Equal(t, "pending", entries[0].Status)
		assert.Equal(t, 0, entries[0].RetryCount, "Should not attempt publishing while circuit breaker is open")
	})

	s.T().Run("Circuit_Breaker_Recovery", func(t *testing.T) {
		// Remove failure injection
		s.failureInjector.Reset()
		
		// Wait for circuit breaker timeout
		time.Sleep(11 * time.Second)
		
		// Circuit breaker should reset to half-open, then closed
		assert.False(t, s.outboxService.IsCircuitBreakerOpen(), "Circuit breaker should recover")
		
		// Previous events should now be processed
		success := s.messageMonitor.WaitForEventPublication(ctx, "circuit-breaker-blocked-user", 15*time.Second)
		assert.True(t, success, "Events should be processed after circuit breaker recovery")
	})
}

// Helper types for outbox testing
type OutboxOperation struct {
	BusinessOperation func(tx framework.Transaction) error
	Events           []framework.DomainEvent
}

type User struct {
	ID        string    `json:"id"`
	TenantID  string    `json:"tenant_id"`
	Email     string    `json:"email"`
	Username  string    `json:"username"`
	FirstName string    `json:"first_name"`
	LastName  string    `json:"last_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

// Test runner
func TestOutboxPatternSuite(t *testing.T) {
	suite.Run(t, new(OutboxPatternTestSuite))
}