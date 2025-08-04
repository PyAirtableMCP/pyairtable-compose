package chaos

import (
	"context"
	"fmt"
	"math/rand"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/pyairtable-compose/tests/integration-suite/internal/framework"
	"github.com/pyairtable-compose/tests/integration-suite/internal/fixtures"
)

// ChaosTestSuite implements chaos engineering tests for the PyAirtable platform
type ChaosTestSuite struct {
	suite.Suite
	framework       *framework.TestFramework
	chaosInjector   *framework.ChaosInjector
	healthMonitor   *framework.HealthMonitor
	serviceManager  *framework.ServiceManager
	networkManager  *framework.NetworkManager
	resourceMonitor *framework.ResourceMonitor
}

func (s *ChaosTestSuite) SetupSuite() {
	s.framework = framework.NewTestFramework("chaos_engineering")
	require.NoError(s.T(), s.framework.Start())
	
	s.chaosInjector = s.framework.ChaosInjector()
	s.healthMonitor = s.framework.HealthMonitor()
	s.serviceManager = s.framework.ServiceManager()
	s.networkManager = s.framework.NetworkManager()
	s.resourceMonitor = s.framework.ResourceMonitor()
}

func (s *ChaosTestSuite) TearDownSuite() {
	// Ensure all chaos experiments are stopped
	s.chaosInjector.StopAllExperiments()
	s.framework.Stop()
}

func (s *ChaosTestSuite) SetupTest() {
	require.NoError(s.T(), s.framework.ResetTestData())
	s.chaosInjector.Reset()
	
	// Ensure all services are healthy before starting chaos tests
	healthy := s.healthMonitor.WaitForAllServicesHealthy(context.Background(), 30*time.Second)
	require.True(s.T(), healthy, "All services must be healthy before chaos testing")
}

func (s *ChaosTestSuite) TearDownTest() {
	// Stop any running chaos experiments
	s.chaosInjector.StopAllExperiments()
	
	// Wait for services to recover
	s.healthMonitor.WaitForAllServicesHealthy(context.Background(), 60*time.Second)
}

// TestServiceCrashResilience tests system resilience when services crash
func (s *ChaosTestSuite) TestServiceCrashResilience() {
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Second)
	defer cancel()

	// Define services to test (excluding critical infrastructure)
	services := []string{
		"user-service",
		"workspace-service", 
		"permission-service",
	}

	for _, serviceName := range services {
		s.T().Run(fmt.Sprintf("Service_%s_Crash", serviceName), func(t *testing.T) {
			// Start monitoring
			monitor := s.healthMonitor.StartServiceMonitoring(ctx, serviceName)
			defer monitor.Stop()

			// Baseline health check
			require.True(t, s.healthMonitor.IsServiceHealthy(ctx, serviceName), 
				"Service should be healthy before chaos")

			// Inject service crash
			experiment := &framework.ChaosExperiment{
				ID:          fmt.Sprintf("crash-%s-%d", serviceName, time.Now().Unix()),
				Type:        "service_crash",
				Target:      serviceName,
				Duration:    30 * time.Second,
				Intensity:   "high",
				Description: fmt.Sprintf("Crash %s service and validate recovery", serviceName),
			}

			err := s.chaosInjector.StartExperiment(ctx, experiment)
			require.NoError(t, err)

			// Wait for service to be detected as unhealthy
			s.T().Log("Waiting for service to be detected as down...")
			downDetected := s.healthMonitor.WaitForServiceDown(ctx, serviceName, 30*time.Second)
			assert.True(t, downDetected, "Service should be detected as down after crash")

			// Test that other services continue to function
			s.T().Log("Validating other services remain functional...")
			s.validateOtherServicesHealthy(ctx, serviceName)

			// Test API gateway's circuit breaker behavior
			s.validateCircuitBreakerActivation(ctx, serviceName)

			// Allow the chaos experiment to complete
			time.Sleep(experiment.Duration)
			s.chaosInjector.StopExperiment(experiment.ID)

			// Wait for service recovery
			s.T().Log("Waiting for service recovery...")
			recovered := s.healthMonitor.WaitForServiceRecovery(ctx, serviceName, 60*time.Second)
			assert.True(t, recovered, "Service should recover after crash chaos ends")

			// Validate service functionality after recovery
			s.validateServiceFunctionality(ctx, serviceName)

			// Check for any data corruption or inconsistencies
			s.validateDataConsistency(ctx, serviceName)
		})
	}
}

// TestNetworkPartitionResilience tests network partition scenarios
func (s *ChaosTestSuite) TestNetworkPartitionResilience() {
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Second)
	defer cancel()

	partitionScenarios := []struct {
		name        string
		services    []string
		duration    time.Duration
		expectation string
	}{
		{
			name:        "Database_Partition",
			services:    []string{"postgres-primary"},
			duration:    20 * time.Second,
			expectation: "Services should handle database connectivity loss gracefully",
		},
		{
			name:        "Cache_Partition", 
			services:    []string{"redis-cache"},
			duration:    15 * time.Second,
			expectation: "Services should function without cache but with degraded performance",
		},
		{
			name:        "Service_Isolation",
			services:    []string{"user-service", "workspace-service"},
			duration:    25 * time.Second,
			expectation: "API Gateway should route around isolated services",
		},
	}

	for _, scenario := range partitionScenarios {
		s.T().Run(scenario.name, func(t *testing.T) {
			s.T().Log(scenario.expectation)

			// Create network partition experiment
			experiment := &framework.ChaosExperiment{
				ID:       fmt.Sprintf("partition-%s-%d", scenario.name, time.Now().Unix()),
				Type:     "network_partition",
				Target:   fmt.Sprintf("%v", scenario.services),
				Duration: scenario.duration,
				Parameters: map[string]interface{}{
					"partition_type": "isolate",
					"services":       scenario.services,
				},
			}

			// Start monitoring affected services
			monitors := make([]*framework.ServiceMonitor, len(scenario.services))
			for i, service := range scenario.services {
				monitors[i] = s.healthMonitor.StartServiceMonitoring(ctx, service)
				defer monitors[i].Stop()
			}

			// Inject network partition
			err := s.chaosInjector.StartExperiment(ctx, experiment)
			require.NoError(t, err)

			// Wait for partition to take effect
			time.Sleep(5 * time.Second)

			// Validate system behavior during partition
			switch scenario.name {
			case "Database_Partition":
				s.validateDatabasePartitionBehavior(ctx)
			case "Cache_Partition":
				s.validateCachePartitionBehavior(ctx)
			case "Service_Isolation":
				s.validateServiceIsolationBehavior(ctx, scenario.services)
			}

			// Allow experiment to complete
			time.Sleep(scenario.duration)
			s.chaosInjector.StopExperiment(experiment.ID)

			// Wait for network recovery
			s.T().Log("Waiting for network recovery...")
			time.Sleep(10 * time.Second)

			// Validate all services recover
			for _, service := range scenario.services {
				recovered := s.healthMonitor.WaitForServiceRecovery(ctx, service, 60*time.Second)
				assert.True(t, recovered, "Service %s should recover after partition", service)
			}

			// Test end-to-end functionality after recovery
			s.validateEndToEndFunctionality(ctx)
		})
	}
}

// TestResourceExhaustionResilience tests system behavior under resource constraints
func (s *ChaosTestSuite) TestResourceExhaustionResilience() {
	ctx, cancel := context.WithTimeout(context.Background(), 240*time.Second)
	defer cancel()

	resourceTests := []struct {
		name         string
		resourceType string
		target       string
		intensity    string
		duration     time.Duration
	}{
		{
			name:         "Memory_Pressure",
			resourceType: "memory",
			target:       "user-service",
			intensity:    "medium",
			duration:     30 * time.Second,
		},
		{
			name:         "CPU_Exhaustion",
			resourceType: "cpu",
			target:       "workspace-service",
			intensity:    "high",
			duration:     20 * time.Second,
		},
		{
			name:         "Disk_Pressure",
			resourceType: "disk",
			target:       "postgres-primary",
			intensity:    "medium",
			duration:     25 * time.Second,
		},
		{
			name:         "Connection_Pool_Exhaustion",
			resourceType: "connections",
			target:       "api-gateway",
			intensity:    "high",
			duration:     15 * time.Second,
		},
	}

	for _, test := range resourceTests {
		s.T().Run(test.name, func(t *testing.T) {
			// Start resource monitoring
			resourceMonitor := s.resourceMonitor.StartMonitoring(ctx, test.target)
			defer resourceMonitor.Stop()

			// Get baseline resource usage
			baseline := s.resourceMonitor.GetResourceUsage(test.target)
			t.Logf("Baseline %s usage: %v", test.resourceType, baseline)

			// Create resource exhaustion experiment
			experiment := &framework.ChaosExperiment{
				ID:       fmt.Sprintf("resource-%s-%d", test.name, time.Now().Unix()),
				Type:     "resource_exhaustion",
				Target:   test.target,
				Duration: test.duration,
				Intensity: test.intensity,
				Parameters: map[string]interface{}{
					"resource_type": test.resourceType,
					"target_usage":  getTargetUsage(test.intensity),
				},
			}

			// Start experiment
			err := s.chaosInjector.StartExperiment(ctx, experiment)
			require.NoError(t, err)

			// Monitor resource usage during experiment
			s.T().Log("Monitoring resource usage during chaos...")
			time.Sleep(5 * time.Second) // Allow time for resource pressure to build

			currentUsage := s.resourceMonitor.GetResourceUsage(test.target)
			t.Logf("Peak %s usage during chaos: %v", test.resourceType, currentUsage)

			// Validate service behavior under resource pressure
			s.validateServiceBehaviorUnderResourcePressure(ctx, test.target, test.resourceType)

			// Check for graceful degradation
			s.validateGracefulDegradation(ctx, test.target)

			// Allow experiment to complete
			time.Sleep(test.duration)
			s.chaosInjector.StopExperiment(experiment.ID)

			// Wait for resource usage to normalize
			s.T().Log("Waiting for resource usage to normalize...")
			normalized := s.resourceMonitor.WaitForResourceNormalization(ctx, test.target, 60*time.Second)
			assert.True(t, normalized, "Resource usage should normalize after chaos")

			// Validate service recovery
			recovered := s.healthMonitor.WaitForServiceRecovery(ctx, test.target, 30*time.Second)
			assert.True(t, recovered, "Service should recover after resource pressure")
		})
	}
}

// TestCascadingFailureResilience tests the system's ability to handle cascading failures
func (s *ChaosTestSuite) TestCascadingFailureResilience() {
	ctx, cancel := context.WithTimeout(context.Background(), 400*time.Second)
	defer cancel()

	// Scenario 1: Database failure triggering service failures
	s.T().Run("Database_Cascade", func(t *testing.T) {
		// Start comprehensive monitoring
		allMonitors := s.startComprehensiveMonitoring(ctx)
		defer s.stopAllMonitors(allMonitors)

		// Phase 1: Database failure
		dbExperiment := &framework.ChaosExperiment{
			ID:       fmt.Sprintf("cascade-db-%d", time.Now().Unix()),
			Type:     "service_crash",
			Target:   "postgres-primary",
			Duration: 45 * time.Second,
		}

		err := s.chaosInjector.StartExperiment(ctx, dbExperiment)
		require.NoError(t, err)

		// Wait for cascade to propagate
		time.Sleep(10 * time.Second)

		// Validate that dependent services start failing gracefully
		dependentServices := []string{"user-service", "workspace-service", "permission-service"}
		for _, service := range dependentServices {
			s.validateGracefulFailure(ctx, service, "database_unavailable")
		}

		// Validate API Gateway implements circuit breakers
		s.validateCircuitBreakerCascade(ctx)

		// Phase 2: Allow database to recover
		s.chaosInjector.StopExperiment(dbExperiment.ID)
		
		// Validate cascading recovery
		s.T().Log("Validating cascading recovery...")
		recovered := s.healthMonitor.WaitForServiceRecovery(ctx, "postgres-primary", 60*time.Second)
		require.True(t, recovered, "Database should recover")

		// Validate dependent services recover in order
		for _, service := range dependentServices {
			recovered := s.healthMonitor.WaitForServiceRecovery(ctx, service, 45*time.Second)
			assert.True(t, recovered, "Service %s should recover after database", service)
		}

		// Validate end-to-end functionality
		s.validateEndToEndFunctionality(ctx)
	})

	// Scenario 2: Auth service failure cascade
	s.T().Run("Auth_Service_Cascade", func(t *testing.T) {
		// Auth service failure should not cascade to other services
		// but should trigger proper authentication fallbacks

		authExperiment := &framework.ChaosExperiment{
			ID:       fmt.Sprintf("cascade-auth-%d", time.Now().Unix()),
			Type:     "service_crash",
			Target:   "auth-service",
			Duration: 30 * time.Second,
		}

		err := s.chaosInjector.StartExperiment(ctx, authExperiment)
		require.NoError(t, err)

		// Validate that other services continue to work for authenticated users
		s.validateAuthenticationFallback(ctx)

		// Validate new authentication requests are properly handled
		s.validateNewAuthenticationHandling(ctx)

		// Allow experiment to complete and validate recovery
		time.Sleep(authExperiment.Duration)
		s.chaosInjector.StopExperiment(authExperiment.ID)

		recovered := s.healthMonitor.WaitForServiceRecovery(ctx, "auth-service", 60*time.Second)
		assert.True(t, recovered, "Auth service should recover")
	})
}

// TestConcurrentChaosEvents tests system behavior under multiple simultaneous chaos events
func (s *ChaosTestSuite) TestConcurrentChaosEvents() {
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Second)
	defer cancel()

	s.T().Run("Multiple_Service_Failures", func(t *testing.T) {
		// Start monitoring all services
		allMonitors := s.startComprehensiveMonitoring(ctx)
		defer s.stopAllMonitors(allMonitors)

		// Create multiple concurrent chaos experiments
		experiments := []*framework.ChaosExperiment{
			{
				ID:       fmt.Sprintf("concurrent-1-%d", time.Now().Unix()),
				Type:     "service_crash",
				Target:   "user-service",
				Duration: 20 * time.Second,
			},
			{
				ID:       fmt.Sprintf("concurrent-2-%d", time.Now().Unix()),
				Type:     "network_latency",
				Target:   "workspace-service",
				Duration: 25 * time.Second,
				Parameters: map[string]interface{}{
					"latency_ms": 2000,
					"jitter_ms":  500,
				},
			},
			{
				ID:       fmt.Sprintf("concurrent-3-%d", time.Now().Unix()),
				Type:     "resource_exhaustion",
				Target:   "permission-service",
				Duration: 15 * time.Second,
				Parameters: map[string]interface{}{
					"resource_type": "memory",
					"target_usage":  85,
				},
			},
		}

		// Start all experiments concurrently
		var wg sync.WaitGroup
		for _, exp := range experiments {
			wg.Add(1)
			go func(experiment *framework.ChaosExperiment) {
				defer wg.Done()
				err := s.chaosInjector.StartExperiment(ctx, experiment)
				assert.NoError(t, err)
			}(exp)
		}
		wg.Wait()

		// Wait for chaos to take effect
		time.Sleep(10 * time.Second)

		// Validate that API Gateway handles multiple service failures
		s.validateAPIGatewayResilience(ctx)

		// Validate that at least one critical path remains functional
		s.validateCriticalPathAvailability(ctx)

		// Wait for all experiments to complete
		maxDuration := time.Duration(0)
		for _, exp := range experiments {
			if exp.Duration > maxDuration {
				maxDuration = exp.Duration
			}
		}
		time.Sleep(maxDuration)

		// Stop all experiments
		for _, exp := range experiments {
			s.chaosInjector.StopExperiment(exp.ID)
		}

		// Validate system recovery
		s.T().Log("Validating system recovery from concurrent chaos...")
		allHealthy := s.healthMonitor.WaitForAllServicesHealthy(ctx, 120*time.Second)
		assert.True(t, allHealthy, "All services should recover from concurrent chaos")

		// Validate end-to-end functionality
		s.validateEndToEndFunctionality(ctx)
	})
}

// Helper methods for chaos testing

func (s *ChaosTestSuite) validateOtherServicesHealthy(ctx context.Context, excludeService string) {
	services := []string{"api-gateway", "auth-service", "user-service", "workspace-service", "permission-service"}
	
	for _, service := range services {
		if service != excludeService {
			healthy := s.healthMonitor.IsServiceHealthy(ctx, service)
			assert.True(s.T(), healthy, "Service %s should remain healthy", service)
		}
	}
}

func (s *ChaosTestSuite) validateCircuitBreakerActivation(ctx context.Context, service string) {
	// Check if API Gateway activates circuit breaker for the failed service
	circuitBreakerActive := s.framework.APIGateway().IsCircuitBreakerOpen(service)
	assert.True(s.T(), circuitBreakerActive, "Circuit breaker should be active for %s", service)
}

func (s *ChaosTestSuite) validateServiceFunctionality(ctx context.Context, service string) {
	switch service {
	case "user-service":
		// Test user operations
		success := s.framework.TestUserOperations(ctx)
		assert.True(s.T(), success, "User operations should work after recovery")
	case "workspace-service":
		// Test workspace operations
		success := s.framework.TestWorkspaceOperations(ctx)
		assert.True(s.T(), success, "Workspace operations should work after recovery")
	case "permission-service":
		// Test permission operations
		success := s.framework.TestPermissionOperations(ctx)
		assert.True(s.T(), success, "Permission operations should work after recovery")
	}
}

func (s *ChaosTestSuite) validateDataConsistency(ctx context.Context, service string) {
	// Check for data corruption or inconsistencies
	consistent := s.framework.ValidateDataConsistency(ctx, service)
	assert.True(s.T(), consistent, "Data should remain consistent after chaos for %s", service)
}

func (s *ChaosTestSuite) validateDatabasePartitionBehavior(ctx context.Context) {
	// Services should handle database connectivity loss gracefully
	// They should either queue operations or return appropriate errors
	
	// Test that services return proper error codes
	response := s.framework.APIGateway().TestEndpoint(ctx, "/api/v1/users")
	assert.Contains(s.T(), []int{503, 500}, response.StatusCode, "Should return service unavailable during DB partition")
}

func (s *ChaosTestSuite) validateCachePartitionBehavior(ctx context.Context) {
	// Services should function without cache but with degraded performance
	
	// Measure response time without cache
	startTime := time.Now()
	response := s.framework.APIGateway().TestEndpoint(ctx, "/api/v1/workspaces")
	duration := time.Since(startTime)
	
	// Should still work but be slower
	assert.Equal(s.T(), 200, response.StatusCode, "Should work without cache")
	assert.Greater(s.T(), duration.Milliseconds(), int64(100), "Should be slower without cache")
}

func (s *ChaosTestSuite) validateServiceIsolationBehavior(ctx context.Context, isolatedServices []string) {
	// API Gateway should route around isolated services
	
	for _, service := range isolatedServices {
		circuitOpen := s.framework.APIGateway().IsCircuitBreakerOpen(service)
		assert.True(s.T(), circuitOpen, "Circuit breaker should be open for isolated service %s", service)
	}
}

func (s *ChaosTestSuite) validateEndToEndFunctionality(ctx context.Context) {
	// Test a complete user workflow
	success := s.framework.TestCompleteUserWorkflow(ctx)
	assert.True(s.T(), success, "End-to-end functionality should work")
}

func (s *ChaosTestSuite) validateServiceBehaviorUnderResourcePressure(ctx context.Context, service string, resourceType string) {
	// Service should implement backpressure and rate limiting
	
	switch resourceType {
	case "memory":
		// Should limit memory-intensive operations
		limited := s.framework.TestMemoryLimiting(ctx, service)
		assert.True(s.T(), limited, "Service should limit memory usage")
	case "cpu":
		// Should throttle CPU-intensive operations
		throttled := s.framework.TestCPUThrottling(ctx, service)
		assert.True(s.T(), throttled, "Service should throttle CPU usage")
	case "connections":
		// Should limit concurrent connections
		limited := s.framework.TestConnectionLimiting(ctx, service)
		assert.True(s.T(), limited, "Service should limit connections")
	}
}

func (s *ChaosTestSuite) validateGracefulDegradation(ctx context.Context, service string) {
	// Service should degrade gracefully under pressure
	degraded := s.framework.TestGracefulDegradation(ctx, service)
	assert.True(s.T(), degraded, "Service should degrade gracefully")
}

func (s *ChaosTestSuite) startComprehensiveMonitoring(ctx context.Context) map[string]*framework.ServiceMonitor {
	services := []string{"api-gateway", "auth-service", "user-service", "workspace-service", "permission-service"}
	monitors := make(map[string]*framework.ServiceMonitor)
	
	for _, service := range services {
		monitors[service] = s.healthMonitor.StartServiceMonitoring(ctx, service)
	}
	
	return monitors
}

func (s *ChaosTestSuite) stopAllMonitors(monitors map[string]*framework.ServiceMonitor) {
	for _, monitor := range monitors {
		monitor.Stop()
	}
}

func (s *ChaosTestSuite) validateGracefulFailure(ctx context.Context, service string, reason string) {
	// Service should fail gracefully with proper error codes
	healthy := s.healthMonitor.IsServiceHealthy(ctx, service)
	
	if !healthy {
		// Should return proper error responses
		response := s.framework.APIGateway().TestServiceEndpoint(ctx, service)
		assert.Contains(s.T(), []int{503, 500}, response.StatusCode, 
			"Service %s should return proper error code for %s", service, reason)
	}
}

func (s *ChaosTestSuite) validateCircuitBreakerCascade(ctx context.Context) {
	// API Gateway should open circuit breakers for failing services
	failingServices := []string{"user-service", "workspace-service", "permission-service"}
	
	for _, service := range failingServices {
		// Circuit breaker should eventually open
		opened := s.framework.APIGateway().WaitForCircuitBreakerOpen(ctx, service, 30*time.Second)
		assert.True(s.T(), opened, "Circuit breaker should open for %s", service)
	}
}

func (s *ChaosTestSuite) validateAuthenticationFallback(ctx context.Context) {
	// Existing authenticated requests should continue to work
	success := s.framework.TestAuthenticatedOperations(ctx)
	assert.True(s.T(), success, "Authenticated operations should continue during auth service failure")
}

func (s *ChaosTestSuite) validateNewAuthenticationHandling(ctx context.Context) {
	// New authentication requests should be properly handled (queued or rejected gracefully)
	response := s.framework.AuthService().TestLogin(ctx, "test@example.com", "password")
	assert.Contains(s.T(), []int{503, 500}, response.StatusCode, "New auth requests should be handled gracefully")
}

func (s *ChaosTestSuite) validateAPIGatewayResilience(ctx context.Context) {
	// API Gateway should remain functional and route around failed services
	healthy := s.healthMonitor.IsServiceHealthy(ctx, "api-gateway")
	assert.True(s.T(), healthy, "API Gateway should remain healthy")
	
	// Should implement proper circuit breakers
	resilient := s.framework.APIGateway().TestResilience(ctx)
	assert.True(s.T(), resilient, "API Gateway should be resilient to service failures")
}

func (s *ChaosTestSuite) validateCriticalPathAvailability(ctx context.Context) {
	// At least basic health checks should remain functional
	response := s.framework.APIGateway().TestEndpoint(ctx, "/health")
	assert.Equal(s.T(), 200, response.StatusCode, "Health endpoint should remain available")
}

func getTargetUsage(intensity string) int {
	switch intensity {
	case "low":
		return 60
	case "medium":
		return 80
	case "high":
		return 95
	default:
		return 70
	}
}

// Test runner
func TestChaosTestSuite(t *testing.T) {
	suite.Run(t, new(ChaosTestSuite))
}