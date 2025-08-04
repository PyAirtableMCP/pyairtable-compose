package contract

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"github.com/xeipuuv/gojsonschema"

	"github.com/pyairtable-compose/tests/integration-suite/internal/framework"
	"github.com/pyairtable-compose/tests/integration-suite/internal/fixtures"
)

// ContractTestSuite tests API contracts between services
type ContractTestSuite struct {
	suite.Suite
	framework       *framework.TestFramework
	contractManager *framework.ContractManager
	schemaValidator *framework.SchemaValidator
	serviceRegistry *framework.ServiceRegistry
	versionManager  *framework.VersionManager
}

func (s *ContractTestSuite) SetupSuite() {
	s.framework = framework.NewTestFramework("contract_testing")
	require.NoError(s.T(), s.framework.Start())
	
	s.contractManager = s.framework.ContractManager()
	s.schemaValidator = s.framework.SchemaValidator()
	s.serviceRegistry = s.framework.ServiceRegistry()
	s.versionManager = s.framework.VersionManager()
}

func (s *ContractTestSuite) TearDownSuite() {
	s.framework.Stop()
}

func (s *ContractTestSuite) SetupTest() {
	require.NoError(s.T(), s.framework.ResetTestData())
}

// TestAPIGatewayContracts tests API Gateway's contract compliance
func (s *ContractTestSuite) TestAPIGatewayContracts() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Define API Gateway contract expectations
	contracts := []APIContract{
		{
			Service:     "api-gateway",
			Version:     "v1",
			Endpoint:    "/health",
			Method:      "GET",
			ExpectedStatusCodes: []int{200},
			ResponseSchema: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"status": {Type: "string", Enum: []string{"ok", "error"}},
					"version": {Type: "string"},
					"timestamp": {Type: "string"},
					"services": {
						Type: "object",
						AdditionalProperties: &JSONSchemaProperty{
							Type: "object",
							Properties: map[string]*JSONSchemaProperty{
								"status": {Type: "string"},
								"response_time": {Type: "number"},
							},
						},
					},
				},
				Required: []string{"status", "version", "timestamp"},
			},
		},
		{
			Service:     "api-gateway",
			Version:     "v1",
			Endpoint:    "/api/v1/tenants",
			Method:      "GET",
			RequiresAuth: true,
			ExpectedStatusCodes: []int{200},
			ResponseSchema: &JSONSchema{
				Type: "array",
				Items: &JSONSchemaProperty{
					Type: "object",
					Properties: map[string]*JSONSchemaProperty{
						"id":          {Type: "string", Format: "uuid"},
						"name":        {Type: "string"},
						"domain":      {Type: "string"},
						"status":      {Type: "string", Enum: []string{"active", "inactive", "suspended"}},
						"plan_type":   {Type: "string"},
						"created_at":  {Type: "string", Format: "date-time"},
						"updated_at":  {Type: "string", Format: "date-time"},
					},
					Required: []string{"id", "name", "domain", "status", "plan_type"},
				},
			},
		},
		{
			Service:     "api-gateway",
			Version:     "v1",
			Endpoint:    "/api/v1/workspaces",
			Method:      "POST",
			RequiresAuth: true,
			RequestSchema: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"name":        {Type: "string", MinLength: 1, MaxLength: 255},
					"description": {Type: "string", MaxLength: 1000},
					"settings":    {Type: "object"},
				},
				Required: []string{"name"},
			},
			ExpectedStatusCodes: []int{201},
			ResponseSchema: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"id":          {Type: "string", Format: "uuid"},
					"name":        {Type: "string"},
					"description": {Type: "string"},
					"tenant_id":   {Type: "string", Format: "uuid"},
					"created_by":  {Type: "string", Format: "uuid"},
					"status":      {Type: "string"},
					"created_at":  {Type: "string", Format: "date-time"},
					"updated_at":  {Type: "string", Format: "date-time"},
				},
				Required: []string{"id", "name", "tenant_id", "created_by", "status"},
			},
		},
	}

	// Test each contract
	for _, contract := range contracts {
		s.T().Run(fmt.Sprintf("%s_%s_%s", contract.Service, contract.Method, contract.Endpoint), func(t *testing.T) {
			s.validateAPIContract(ctx, contract)
		})
	}
}

// TestAuthServiceContracts tests Auth Service's contract compliance
func (s *ContractTestSuite) TestAuthServiceContracts() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	contracts := []APIContract{
		{
			Service:  "auth-service",
			Version:  "v1",
			Endpoint: "/auth/login",
			Method:   "POST",
			RequestSchema: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"email":    {Type: "string", Format: "email"},
					"password": {Type: "string", MinLength: 1},
				},
				Required: []string{"email", "password"},
			},
			ExpectedStatusCodes: []int{200, 401},
			ResponseSchema: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"token":         {Type: "string"},
					"refresh_token": {Type: "string"},
					"expires_at":    {Type: "string", Format: "date-time"},
					"user": {
						Type: "object",
						Properties: map[string]*JSONSchemaProperty{
							"id":         {Type: "string", Format: "uuid"},
							"email":      {Type: "string", Format: "email"},
							"first_name": {Type: "string"},
							"last_name":  {Type: "string"},
							"role":       {Type: "string"},
						},
					},
				},
				Required: []string{"token", "expires_at", "user"},
			},
		},
		{
			Service:     "auth-service",
			Version:     "v1",
			Endpoint:    "/auth/refresh",
			Method:      "POST",
			RequiresAuth: true,
			RequestSchema: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"refresh_token": {Type: "string"},
				},
				Required: []string{"refresh_token"},
			},
			ExpectedStatusCodes: []int{200, 401},
		},
		{
			Service:     "auth-service",
			Version:     "v1",
			Endpoint:    "/auth/logout",
			Method:      "POST",
			RequiresAuth: true,
			ExpectedStatusCodes: []int{200},
		},
	}

	for _, contract := range contracts {
		s.T().Run(fmt.Sprintf("%s_%s_%s", contract.Service, contract.Method, contract.Endpoint), func(t *testing.T) {
			s.validateAPIContract(ctx, contract)
		})
	}
}

// TestUserServiceContracts tests User Service's contract compliance
func (s *ContractTestSuite) TestUserServiceContracts() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	contracts := []APIContract{
		{
			Service:     "user-service",
			Version:     "v1",
			Endpoint:    "/users/profile",
			Method:      "GET",
			RequiresAuth: true,
			ExpectedStatusCodes: []int{200},
			ResponseSchema: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"id":         {Type: "string", Format: "uuid"},
					"tenant_id":  {Type: "string", Format: "uuid"},
					"email":      {Type: "string", Format: "email"},
					"username":   {Type: "string"},
					"first_name": {Type: "string"},
					"last_name":  {Type: "string"},
					"role":       {Type: "string"},
					"status":     {Type: "string", Enum: []string{"active", "inactive", "suspended"}},
					"created_at": {Type: "string", Format: "date-time"},
					"updated_at": {Type: "string", Format: "date-time"},
					"profile":    {Type: "object"},
				},
				Required: []string{"id", "tenant_id", "email", "username", "role", "status"},
			},
		},
		{
			Service:     "user-service",
			Version:     "v1",
			Endpoint:    "/users",
			Method:      "POST",
			RequiresAuth: true,
			RequestSchema: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"email":      {Type: "string", Format: "email"},
					"username":   {Type: "string", MinLength: 3, MaxLength: 50},
					"first_name": {Type: "string", MinLength: 1, MaxLength: 100},
					"last_name":  {Type: "string", MinLength: 1, MaxLength: 100},
					"role":       {Type: "string"},
					"profile":    {Type: "object"},
				},
				Required: []string{"email", "username", "first_name", "last_name"},
			},
			ExpectedStatusCodes: []int{201, 400, 409},
		},
	}

	for _, contract := range contracts {
		s.T().Run(fmt.Sprintf("%s_%s_%s", contract.Service, contract.Method, contract.Endpoint), func(t *testing.T) {
			s.validateAPIContract(ctx, contract)
		})
	}
}

// TestCrossServiceContracts tests contracts between services
func (s *ContractTestSuite) TestCrossServiceContracts() {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	// Test API Gateway -> Auth Service integration
	s.T().Run("APIGateway_To_AuthService", func(t *testing.T) {
		s.validateCrossServiceContract(ctx, CrossServiceContract{
			Provider:    "auth-service",
			Consumer:    "api-gateway",
			Interaction: "token_validation",
			RequestContract: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"token": {Type: "string"},
				},
				Required: []string{"token"},
			},
			ResponseContract: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"valid": {Type: "boolean"},
					"user_id": {Type: "string", Format: "uuid"},
					"tenant_id": {Type: "string", Format: "uuid"},
					"permissions": {
						Type: "array",
						Items: &JSONSchemaProperty{Type: "string"},
					},
				},
				Required: []string{"valid"},
			},
		})
	})

	// Test User Service -> Permission Service integration
	s.T().Run("UserService_To_PermissionService", func(t *testing.T) {
		s.validateCrossServiceContract(ctx, CrossServiceContract{
			Provider:    "permission-service",
			Consumer:    "user-service",
			Interaction: "check_permission",
			RequestContract: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"user_id":       {Type: "string", Format: "uuid"},
					"resource_id":   {Type: "string", Format: "uuid"},
					"resource_type": {Type: "string"},
					"permission":    {Type: "string"},
				},
				Required: []string{"user_id", "resource_id", "resource_type", "permission"},
			},
			ResponseContract: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"allowed": {Type: "boolean"},
					"reason":  {Type: "string"},
				},
				Required: []string{"allowed"},
			},
		})
	})

	// Test Workspace Service -> User Service integration
	s.T().Run("WorkspaceService_To_UserService", func(t *testing.T) {
		s.validateCrossServiceContract(ctx, CrossServiceContract{
			Provider:    "user-service",
			Consumer:    "workspace-service",
			Interaction: "get_user_info",
			RequestContract: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"user_id": {Type: "string", Format: "uuid"},
				},
				Required: []string{"user_id"},
			},
			ResponseContract: &JSONSchema{
				Type: "object",
				Properties: map[string]*JSONSchemaProperty{
					"id":         {Type: "string", Format: "uuid"},
					"email":      {Type: "string", Format: "email"},
					"first_name": {Type: "string"},
					"last_name":  {Type: "string"},
					"role":       {Type: "string"},
					"status":     {Type: "string"},
				},
				Required: []string{"id", "email", "role", "status"},
			},
		})
	})
}

// TestSchemaEvolution tests backward compatibility during schema changes
func (s *ContractTestSuite) TestSchemaEvolution() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Test backward compatibility scenarios
	evolutionTests := []SchemaEvolutionTest{
		{
			Name:        "Optional_Field_Addition",
			Service:     "user-service",
			Endpoint:    "/users/profile",
			OldSchema:   s.getUserProfileSchemaV1(),
			NewSchema:   s.getUserProfileSchemaV2(),
			Compatible:  true,
			Description: "Adding optional fields should be backward compatible",
		},
		{
			Name:        "Required_Field_Addition",
			Service:     "workspace-service",
			Endpoint:    "/workspaces",
			OldSchema:   s.getWorkspaceSchemaV1(),
			NewSchema:   s.getWorkspaceSchemaV2(),
			Compatible:  false,
			Description: "Adding required fields breaks backward compatibility",
		},
		{
			Name:        "Field_Type_Change",
			Service:     "permission-service",
			Endpoint:    "/permissions",
			OldSchema:   s.getPermissionSchemaV1(),
			NewSchema:   s.getPermissionSchemaV2(),
			Compatible:  false,
			Description: "Changing field types breaks backward compatibility",
		},
		{
			Name:        "Field_Removal",
			Service:     "auth-service",
			Endpoint:    "/auth/login",
			OldSchema:   s.getAuthResponseSchemaV1(),
			NewSchema:   s.getAuthResponseSchemaV2(),
			Compatible:  false,
			Description: "Removing fields breaks backward compatibility",
		},
	}

	for _, test := range evolutionTests {
		s.T().Run(test.Name, func(t *testing.T) {
			s.validateSchemaEvolution(ctx, test)
		})
	}
}

// TestVersionCompatibility tests API version compatibility
func (s *ContractTestSuite) TestVersionCompatibility() {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	// Test different API versions
	versionTests := []VersionCompatibilityTest{
		{
			Service:     "api-gateway",
			OldVersion:  "v1",
			NewVersion:  "v2",
			Endpoints: []string{
				"/api/v1/workspaces",
				"/api/v1/users",
				"/api/v1/permissions",
			},
			ShouldBeCompatible: true,
		},
		{
			Service:     "auth-service",
			OldVersion:  "v1",
			NewVersion:  "v2",
			Endpoints: []string{
				"/auth/login",
				"/auth/refresh",
				"/auth/logout",
			},
			ShouldBeCompatible: true,
		},
	}

	for _, test := range versionTests {
		s.T().Run(fmt.Sprintf("%s_%s_to_%s", test.Service, test.OldVersion, test.NewVersion), func(t *testing.T) {
			s.validateVersionCompatibility(ctx, test)
		})
	}
}

// TestConsumerDrivenContracts tests consumer-driven contract compliance
func (s *ContractTestSuite) TestConsumerDrivenContracts() {
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	// Load consumer-driven contracts
	contracts := s.loadConsumerDrivenContracts()

	for _, contract := range contracts {
		s.T().Run(fmt.Sprintf("%s_consumes_%s", contract.Consumer, contract.Provider), func(t *testing.T) {
			s.validateConsumerDrivenContract(ctx, contract)
		})
	}
}

// Helper methods for contract validation

func (s *ContractTestSuite) validateAPIContract(ctx context.Context, contract APIContract) {
	// Get authentication token if required
	var authToken string
	if contract.RequiresAuth {
		token, err := s.framework.AuthService().GetTestToken(ctx, fixtures.TestEmailAlphaAdmin, fixtures.TestPasswordPlain)
		require.NoError(s.T(), err)
		authToken = token
	}

	// Build request
	request := &framework.HTTPRequest{
		Method:   contract.Method,
		URL:      s.buildServiceURL(contract.Service, contract.Endpoint),
		Headers:  make(map[string]string),
	}

	if authToken != "" {
		request.Headers["Authorization"] = "Bearer " + authToken
	}

	// Add request body if schema is provided
	if contract.RequestSchema != nil {
		testData := s.generateTestDataFromSchema(contract.RequestSchema)
		request.Body = testData
		request.Headers["Content-Type"] = "application/json"
	}

	// Execute request
	response, err := s.framework.HTTPClient().Execute(ctx, request)
	require.NoError(s.T(), err)

	// Validate status code
	assert.Contains(s.T(), contract.ExpectedStatusCodes, response.StatusCode,
		"Response status code should match contract expectation")

	// Validate response schema if provided and status is success
	if contract.ResponseSchema != nil && response.StatusCode < 400 {
		s.validateResponseSchema(response.Body, contract.ResponseSchema)
	}

	// Validate response headers
	s.validateResponseHeaders(response.Headers, contract.Service)

	// Store contract validation result
	s.contractManager.RecordValidation(contract.Service, contract.Endpoint, contract.Method, true, "")
}

func (s *ContractTestSuite) validateCrossServiceContract(ctx context.Context, contract CrossServiceContract) {
	// Simulate the consumer calling the provider
	providerURL := s.buildServiceURL(contract.Provider, "/internal/"+contract.Interaction)
	
	// Generate test data from request contract
	testData := s.generateTestDataFromSchema(contract.RequestContract)
	
	request := &framework.HTTPRequest{
		Method:  "POST",
		URL:     providerURL,
		Body:    testData,
		Headers: map[string]string{
			"Content-Type": "application/json",
			"X-Consumer":   contract.Consumer,
		},
	}

	response, err := s.framework.HTTPClient().Execute(ctx, request)
	require.NoError(s.T(), err)

	// Validate response matches contract
	if response.StatusCode == 200 {
		s.validateResponseSchema(response.Body, contract.ResponseContract)
	}

	// Record contract interaction
	s.contractManager.RecordCrossServiceInteraction(
		contract.Provider, 
		contract.Consumer, 
		contract.Interaction, 
		response.StatusCode == 200,
		"",
	)
}

func (s *ContractTestSuite) validateSchemaEvolution(ctx context.Context, test SchemaEvolutionTest) {
	// Test if new schema is compatible with old schema
	compatible := s.schemaValidator.IsBackwardCompatible(test.OldSchema, test.NewSchema)
	
	if test.Compatible {
		assert.True(s.T(), compatible, "Schema evolution should be backward compatible: %s", test.Description)
	} else {
		assert.False(s.T(), compatible, "Schema evolution should break backward compatibility: %s", test.Description)
	}

	// Test with real API call if available
	if test.Service != "" && test.Endpoint != "" {
		serviceURL := s.buildServiceURL(test.Service, test.Endpoint)
		
		// Test with old schema expectations
		response, err := s.framework.HTTPClient().Get(ctx, serviceURL)
		if err == nil && response.StatusCode == 200 {
			// Validate against old schema
			oldValid := s.schemaValidator.ValidateJSON(response.Body, test.OldSchema)
			
			// Validate against new schema
			newValid := s.schemaValidator.ValidateJSON(response.Body, test.NewSchema)
			
			if test.Compatible {
				assert.True(s.T(), oldValid || newValid, "Response should validate against at least one schema")
			}
		}
	}
}

func (s *ContractTestSuite) validateVersionCompatibility(ctx context.Context, test VersionCompatibilityTest) {
	for _, endpoint := range test.Endpoints {
		// Test old version
		oldURL := s.buildVersionedServiceURL(test.Service, test.OldVersion, endpoint)
		oldResponse, err := s.framework.HTTPClient().Get(ctx, oldURL)
		
		// Test new version
		newURL := s.buildVersionedServiceURL(test.Service, test.NewVersion, endpoint)
		newResponse, err2 := s.framework.HTTPClient().Get(ctx, newURL)

		if test.ShouldBeCompatible {
			// Both versions should work
			assert.NoError(s.T(), err, "Old version should work")
			assert.NoError(s.T(), err2, "New version should work")
			
			if err == nil && err2 == nil {
				// Response structures should be compatible
				compatible := s.areResponsesCompatible(oldResponse.Body, newResponse.Body)
				assert.True(s.T(), compatible, "Response structures should be compatible between versions")
			}
		}
	}
}

func (s *ContractTestSuite) validateConsumerDrivenContract(ctx context.Context, contract ConsumerDrivenContract) {
	// Test each interaction in the contract
	for _, interaction := range contract.Interactions {
		// Prepare request based on consumer expectations
		request := &framework.HTTPRequest{
			Method:  interaction.Method,
			URL:     s.buildServiceURL(contract.Provider, interaction.Endpoint),
			Headers: interaction.Headers,
			Body:    interaction.RequestBody,
		}

		response, err := s.framework.HTTPClient().Execute(ctx, request)
		require.NoError(s.T(), err)

		// Validate response matches consumer expectations
		assert.Equal(s.T(), interaction.ExpectedStatusCode, response.StatusCode,
			"Status code should match consumer expectation")

		if interaction.ResponseSchema != nil {
			s.validateResponseSchema(response.Body, interaction.ResponseSchema)
		}

		// Validate response headers if specified
		for expectedHeader, expectedValue := range interaction.ExpectedHeaders {
			assert.Equal(s.T(), expectedValue, response.Headers[expectedHeader],
				"Header %s should match consumer expectation", expectedHeader)
		}
	}
}

func (s *ContractTestSuite) validateResponseSchema(responseBody []byte, schema *JSONSchema) {
	// Convert to JSON schema format
	jsonSchema := s.convertToJSONSchema(schema)
	
	// Validate response
	schemaLoader := gojsonschema.NewStringLoader(jsonSchema)
	documentLoader := gojsonschema.NewBytesLoader(responseBody)
	
	result, err := gojsonschema.Validate(schemaLoader, documentLoader)
	require.NoError(s.T(), err)
	
	if !result.Valid() {
		s.T().Errorf("Response validation failed:")
		for _, error := range result.Errors() {
			s.T().Errorf("- %s", error)
		}
	}
	
	assert.True(s.T(), result.Valid(), "Response should match schema")
}

func (s *ContractTestSuite) validateResponseHeaders(headers map[string]string, service string) {
	// Common header validations
	assert.NotEmpty(s.T(), headers["Content-Type"], "Content-Type header should be present")
	
	// Service-specific header validations
	switch service {
	case "api-gateway":
		assert.NotEmpty(s.T(), headers["X-Request-ID"], "X-Request-ID should be present")
		assert.NotEmpty(s.T(), headers["X-RateLimit-Remaining"], "X-RateLimit-Remaining should be present")
	case "auth-service":
		if headers["Content-Type"] == "application/json" {
			// Auth responses should have security headers
			assert.NotEmpty(s.T(), headers["X-Content-Type-Options"], "X-Content-Type-Options should be present")
		}
	}
}

func (s *ContractTestSuite) buildServiceURL(service string, endpoint string) string {
	baseURL := s.framework.GetServiceURL(service)
	return fmt.Sprintf("%s%s", baseURL, endpoint)
}

func (s *ContractTestSuite) buildVersionedServiceURL(service string, version string, endpoint string) string {
	baseURL := s.framework.GetServiceURL(service)
	return fmt.Sprintf("%s/%s%s", baseURL, version, endpoint)
}

func (s *ContractTestSuite) generateTestDataFromSchema(schema *JSONSchema) []byte {
	// Generate valid test data based on schema
	data := s.schemaValidator.GenerateTestData(schema)
	jsonData, _ := json.Marshal(data)
	return jsonData
}

func (s *ContractTestSuite) convertToJSONSchema(schema *JSONSchema) string {
	// Convert internal schema representation to JSON Schema format
	jsonSchema, _ := json.Marshal(schema)
	return string(jsonSchema)
}

func (s *ContractTestSuite) areResponsesCompatible(oldResponse, newResponse []byte) bool {
	// Compare response structures for compatibility
	var oldData, newData interface{}
	
	if err := json.Unmarshal(oldResponse, &oldData); err != nil {
		return false
	}
	
	if err := json.Unmarshal(newResponse, &newData); err != nil {
		return false
	}
	
	// Check if new response contains all fields from old response
	return s.schemaValidator.IsStructurallyCompatible(oldData, newData)
}

func (s *ContractTestSuite) loadConsumerDrivenContracts() []ConsumerDrivenContract {
	// Load contracts from configuration or contract repository
	return []ConsumerDrivenContract{
		{
			Consumer: "frontend-app",
			Provider: "api-gateway",
			Interactions: []ContractInteraction{
				{
					Description:        "Get user workspaces",
					Method:            "GET",
					Endpoint:          "/api/v1/workspaces",
					ExpectedStatusCode: 200,
					ResponseSchema:    s.getWorkspaceListSchema(),
				},
				{
					Description:        "Create new workspace",
					Method:            "POST",
					Endpoint:          "/api/v1/workspaces",
					RequestBody:       []byte(`{"name":"Test Workspace","description":"Test"}`),
					ExpectedStatusCode: 201,
					ResponseSchema:    s.getWorkspaceSchema(),
				},
			},
		},
	}
}

// Schema definition helpers
func (s *ContractTestSuite) getUserProfileSchemaV1() *JSONSchema {
	return &JSONSchema{
		Type: "object",
		Properties: map[string]*JSONSchemaProperty{
			"id":        {Type: "string", Format: "uuid"},
			"email":     {Type: "string", Format: "email"},
			"first_name": {Type: "string"},
			"last_name":  {Type: "string"},
			"role":      {Type: "string"},
		},
		Required: []string{"id", "email", "first_name", "last_name", "role"},
	}
}

func (s *ContractTestSuite) getUserProfileSchemaV2() *JSONSchema {
	schema := s.getUserProfileSchemaV1()
	// Add optional field
	schema.Properties["avatar_url"] = &JSONSchemaProperty{Type: "string", Format: "uri"}
	schema.Properties["bio"] = &JSONSchemaProperty{Type: "string"}
	return schema
}

func (s *ContractTestSuite) getWorkspaceSchemaV1() *JSONSchema {
	return &JSONSchema{
		Type: "object",
		Properties: map[string]*JSONSchemaProperty{
			"name":        {Type: "string"},
			"description": {Type: "string"},
		},
		Required: []string{"name"},
	}
}

func (s *ContractTestSuite) getWorkspaceSchemaV2() *JSONSchema {
	schema := s.getWorkspaceSchemaV1()
	// Add required field (breaking change)
	schema.Properties["category"] = &JSONSchemaProperty{Type: "string"}
	schema.Required = append(schema.Required, "category")
	return schema
}

func (s *ContractTestSuite) getPermissionSchemaV1() *JSONSchema {
	return &JSONSchema{
		Type: "object",
		Properties: map[string]*JSONSchemaProperty{
			"permission": {Type: "string"},
			"granted":    {Type: "boolean"},
		},
		Required: []string{"permission", "granted"},
	}
}

func (s *ContractTestSuite) getPermissionSchemaV2() *JSONSchema {
	return &JSONSchema{
		Type: "object",
		Properties: map[string]*JSONSchemaProperty{
			"permission": {Type: "string"},
			"granted":    {Type: "string"}, // Changed type (breaking change)
		},
		Required: []string{"permission", "granted"},
	}
}

func (s *ContractTestSuite) getAuthResponseSchemaV1() *JSONSchema {
	return &JSONSchema{
		Type: "object",
		Properties: map[string]*JSONSchemaProperty{
			"token":      {Type: "string"},
			"user_id":    {Type: "string"},
			"expires_at": {Type: "string"},
		},
		Required: []string{"token", "user_id", "expires_at"},
	}
}

func (s *ContractTestSuite) getAuthResponseSchemaV2() *JSONSchema {
	return &JSONSchema{
		Type: "object",
		Properties: map[string]*JSONSchemaProperty{
			"token":      {Type: "string"},
			"expires_at": {Type: "string"},
			// Removed user_id (breaking change)
		},
		Required: []string{"token", "expires_at"},
	}
}

func (s *ContractTestSuite) getWorkspaceListSchema() *JSONSchema {
	return &JSONSchema{
		Type: "array",
		Items: &JSONSchemaProperty{
			Type: "object",
			Properties: map[string]*JSONSchemaProperty{
				"id":   {Type: "string", Format: "uuid"},
				"name": {Type: "string"},
			},
		},
	}
}

func (s *ContractTestSuite) getWorkspaceSchema() *JSONSchema {
	return &JSONSchema{
		Type: "object",
		Properties: map[string]*JSONSchemaProperty{
			"id":          {Type: "string", Format: "uuid"},
			"name":        {Type: "string"},
			"description": {Type: "string"},
			"created_at":  {Type: "string", Format: "date-time"},
		},
		Required: []string{"id", "name"},
	}
}

// Test data structures
type APIContract struct {
	Service             string
	Version             string
	Endpoint            string
	Method              string
	RequiresAuth        bool
	RequestSchema       *JSONSchema
	ResponseSchema      *JSONSchema
	ExpectedStatusCodes []int
}

type CrossServiceContract struct {
	Provider         string
	Consumer         string
	Interaction      string
	RequestContract  *JSONSchema
	ResponseContract *JSONSchema
}

type SchemaEvolutionTest struct {
	Name        string
	Service     string
	Endpoint    string
	OldSchema   *JSONSchema
	NewSchema   *JSONSchema
	Compatible  bool
	Description string
}

type VersionCompatibilityTest struct {
	Service            string
	OldVersion         string
	NewVersion         string
	Endpoints          []string
	ShouldBeCompatible bool
}

type ConsumerDrivenContract struct {
	Consumer     string
	Provider     string
	Interactions []ContractInteraction
}

type ContractInteraction struct {
	Description        string
	Method             string
	Endpoint           string
	Headers            map[string]string
	RequestBody        []byte
	ExpectedStatusCode int
	ExpectedHeaders    map[string]string
	ResponseSchema     *JSONSchema
}

type JSONSchema struct {
	Type                 string                          `json:"type"`
	Properties           map[string]*JSONSchemaProperty `json:"properties,omitempty"`
	Required             []string                        `json:"required,omitempty"`
	Items                *JSONSchemaProperty             `json:"items,omitempty"`
	AdditionalProperties *JSONSchemaProperty             `json:"additionalProperties,omitempty"`
}

type JSONSchemaProperty struct {
	Type      string                          `json:"type"`
	Format    string                          `json:"format,omitempty"`
	MinLength int                             `json:"minLength,omitempty"`
	MaxLength int                             `json:"maxLength,omitempty"`
	Enum      []string                        `json:"enum,omitempty"`
	Properties map[string]*JSONSchemaProperty `json:"properties,omitempty"`
	Required   []string                       `json:"required,omitempty"`
	Items      *JSONSchemaProperty             `json:"items,omitempty"`
}

// Test runner
func TestContractTestSuite(t *testing.T) {
	suite.Run(t, new(ContractTestSuite))
}