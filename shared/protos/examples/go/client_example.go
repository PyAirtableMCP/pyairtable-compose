package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/metadata"

	authv1 "github.com/pyairtable/pyairtable-protos/generated/go/pyairtable/auth/v1"
	commonv1 "github.com/pyairtable/pyairtable-protos/generated/go/pyairtable/common/v1"
	permissionv1 "github.com/pyairtable/pyairtable-protos/generated/go/pyairtable/permission/v1"
	userv1 "github.com/pyairtable/pyairtable-protos/generated/go/pyairtable/user/v1"
)

// PyAirtableClient wraps gRPC clients for PyAirtable services
type PyAirtableClient struct {
	authClient       authv1.AuthServiceClient
	userClient       userv1.UserServiceClient
	permissionClient permissionv1.PermissionServiceClient
	
	// Connection management
	conn *grpc.ClientConn
	
	// Authentication context
	accessToken string
}

// NewPyAirtableClient creates a new client with gRPC connections
func NewPyAirtableClient(serviceAddress string, useTLS bool) (*PyAirtableClient, error) {
	var opts []grpc.DialOption
	
	if useTLS {
		config := &tls.Config{
			ServerName: serviceAddress,
		}
		opts = append(opts, grpc.WithTransportCredentials(credentials.NewTLS(config)))
	} else {
		opts = append(opts, grpc.WithInsecure())
	}
	
	// Add interceptors for authentication and logging
	opts = append(opts, 
		grpc.WithUnaryInterceptor(loggingInterceptor),
		grpc.WithStreamInterceptor(streamLoggingInterceptor),
	)
	
	conn, err := grpc.Dial(serviceAddress, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to service: %w", err)
	}
	
	return &PyAirtableClient{
		authClient:       authv1.NewAuthServiceClient(conn),
		userClient:       userv1.NewUserServiceClient(conn),
		permissionClient: permissionv1.NewPermissionServiceClient(conn),
		conn:             conn,
	}, nil
}

// Close closes the gRPC connection
func (c *PyAirtableClient) Close() error {
	return c.conn.Close()
}

// Login authenticates a user and stores the access token
func (c *PyAirtableClient) Login(ctx context.Context, email, password string) (*authv1.LoginResponse, error) {
	req := &authv1.LoginRequest{
		RequestMetadata: &commonv1.RequestMetadata{
			RequestId: generateRequestID(),
			Timestamp: timestampNow(),
		},
		Credentials: &authv1.AuthCredentials{
			Email:    email,
			Password: password,
			Provider: authv1.AuthProvider_AUTH_PROVIDER_LOCAL,
		},
	}
	
	resp, err := c.authClient.Login(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("login failed: %w", err)
	}
	
	// Store access token for future requests
	c.accessToken = resp.AccessToken.Token
	
	return resp, nil
}

// GetUser retrieves user information
func (c *PyAirtableClient) GetUser(ctx context.Context, userID string) (*userv1.GetUserResponse, error) {
	ctx = c.addAuthContext(ctx)
	
	req := &userv1.GetUserRequest{
		RequestMetadata: &commonv1.RequestMetadata{
			RequestId: generateRequestID(),
			Timestamp: timestampNow(),
		},
		UserId: userID,
	}
	
	resp, err := c.userClient.GetUser(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("get user failed: %w", err)
	}
	
	return resp, nil
}

// CheckPermission validates if a user has permission for an action
func (c *PyAirtableClient) CheckPermission(ctx context.Context, userID string, resourceType permissionv1.ResourceType, resourceID, action string) (*permissionv1.CheckPermissionResponse, error) {
	ctx = c.addAuthContext(ctx)
	
	req := &permissionv1.CheckPermissionRequest{
		RequestMetadata: &commonv1.RequestMetadata{
			RequestId: generateRequestID(),
			Timestamp: timestampNow(),
		},
		UserId:       userID,
		ResourceType: resourceType,
		ResourceId:   resourceID,
		Action:       action,
	}
	
	resp, err := c.permissionClient.CheckPermission(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("permission check failed: %w", err)
	}
	
	return resp, nil
}

// CreateUser creates a new user
func (c *PyAirtableClient) CreateUser(ctx context.Context, email, firstName, lastName string) (*userv1.CreateUserResponse, error) {
	ctx = c.addAuthContext(ctx)
	
	req := &userv1.CreateUserRequest{
		RequestMetadata: &commonv1.RequestMetadata{
			RequestId: generateRequestID(),
			Timestamp: timestampNow(),
		},
		Email: email,
		Profile: &userv1.UserProfile{
			FirstName: firstName,
			LastName:  lastName,
		},
	}
	
	resp, err := c.userClient.CreateUser(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("create user failed: %w", err)
	}
	
	return resp, nil
}

// ListUsers retrieves a paginated list of users
func (c *PyAirtableClient) ListUsers(ctx context.Context, page, pageSize int32) (*userv1.ListUsersResponse, error) {
	ctx = c.addAuthContext(ctx)
	
	req := &userv1.ListUsersRequest{
		RequestMetadata: &commonv1.RequestMetadata{
			RequestId: generateRequestID(),
			Timestamp: timestampNow(),
		},
		Pagination: &commonv1.PaginationRequest{
			Page:     page,
			PageSize: pageSize,
		},
	}
	
	resp, err := c.userClient.ListUsers(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("list users failed: %w", err)
	}
	
	return resp, nil
}

// addAuthContext adds authentication metadata to the context
func (c *PyAirtableClient) addAuthContext(ctx context.Context) context.Context {
	if c.accessToken != "" {
		md := metadata.New(map[string]string{
			"authorization": "Bearer " + c.accessToken,
		})
		ctx = metadata.NewOutgoingContext(ctx, md)
	}
	return ctx
}

// Helper functions

func generateRequestID() string {
	return fmt.Sprintf("req_%d", time.Now().UnixNano())
}

func timestampNow() *commonv1.BaseMetadata {
	// In real implementation, you'd use timestamppb.Now()
	return nil
}

// Interceptors for logging and monitoring

func loggingInterceptor(ctx context.Context, method string, req, reply interface{}, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
	start := time.Now()
	err := invoker(ctx, method, req, reply, cc, opts...)
	duration := time.Since(start)
	
	log.Printf("gRPC call: method=%s duration=%v error=%v", method, duration, err)
	return err
}

func streamLoggingInterceptor(ctx context.Context, desc *grpc.StreamDesc, cc *grpc.ClientConn, method string, streamer grpc.Streamer, opts ...grpc.CallOption) (grpc.ClientStream, error) {
	log.Printf("gRPC stream: method=%s", method)
	return streamer(ctx, desc, cc, method, opts...)
}

// Example usage
func main() {
	// Create client
	client, err := NewPyAirtableClient("localhost:50051", false)
	if err != nil {
		log.Fatal("Failed to create client:", err)
	}
	defer client.Close()
	
	ctx := context.Background()
	
	// Login
	loginResp, err := client.Login(ctx, "admin@example.com", "password")
	if err != nil {
		log.Fatal("Login failed:", err)
	}
	fmt.Printf("Login successful: %s\n", loginResp.UserContext.Email)
	
	// Create a user
	createResp, err := client.CreateUser(ctx, "newuser@example.com", "John", "Doe")
	if err != nil {
		log.Fatal("Create user failed:", err)
	}
	fmt.Printf("User created: %s\n", createResp.User.Metadata.Id)
	
	// Check permission
	permResp, err := client.CheckPermission(ctx, 
		createResp.User.Metadata.Id, 
		permissionv1.ResourceType_RESOURCE_TYPE_WORKSPACE, 
		"workspace-123", 
		"read")
	if err != nil {
		log.Fatal("Permission check failed:", err)
	}
	fmt.Printf("Permission allowed: %t\n", permResp.Allowed)
	
	// List users
	listResp, err := client.ListUsers(ctx, 1, 10)
	if err != nil {
		log.Fatal("List users failed:", err)
	}
	fmt.Printf("Found %d users\n", len(listResp.Users))
}