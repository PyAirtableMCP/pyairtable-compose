package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	"google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/reflection"

	"github.com/pyairtable/workspace-service/internal/config"
	"github.com/pyairtable/workspace-service/internal/handlers"
	"github.com/pyairtable/workspace-service/internal/permissions"
	"github.com/pyairtable/workspace-service/internal/repository"
	"github.com/pyairtable/workspace-service/internal/service"
	pb "github.com/pyairtable/workspace-service/proto"
)

func main() {
	// Load configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatal("Failed to load config:", err)
	}
	
	if err := cfg.Validate(); err != nil {
		log.Fatal("Invalid config:", err)
	}
	
	// Setup database
	db, err := setupDatabase(cfg.Database)
	if err != nil {
		log.Fatal("Failed to setup database:", err)
	}
	defer db.Close()
	
	// Run migrations
	if err := runMigrations(cfg.Database); err != nil {
		log.Fatal("Failed to run migrations:", err)
	}
	
	// Setup Redis
	redisClient := setupRedis(cfg.Redis)
	defer redisClient.Close()
	
	// Initialize repositories
	workspaceRepo := repository.NewWorkspaceRepository(db)
	memberRepo := repository.NewMemberRepository(db)
	invitationRepo := repository.NewInvitationRepository(db)
	permissionRepo := repository.NewPermissionRepository(db)
	
	// Initialize permission checker
	permissionChecker := permissions.NewPermissionChecker(memberRepo, permissionRepo)
	
	// Initialize services
	workspaceService := service.NewWorkspaceService(
		workspaceRepo,
		memberRepo,
		invitationRepo,
		permissionRepo,
		permissionChecker,
		redisClient,
	)
	
	memberService := service.NewMemberService(
		memberRepo,
		invitationRepo,
		permissionRepo,
		permissionChecker,
		redisClient,
	)
	
	permissionService := service.NewPermissionService(
		permissionRepo,
		permissionChecker,
		redisClient,
	)
	
	// Initialize handlers
	workspaceHandler := handlers.NewWorkspaceHandler(
		workspaceService,
		memberService,
		permissionService,
	)
	
	// Setup gRPC server
	grpcServer := grpc.NewServer(
		grpc.UnaryInterceptor(loggingInterceptor),
	)
	
	// Register services
	pb.RegisterWorkspaceServiceServer(grpcServer, workspaceHandler)
	
	// Register health service
	healthServer := health.NewServer()
	healthServer.SetServingStatus("workspace", grpc_health_v1.HealthCheckResponse_SERVING)
	grpc_health_v1.RegisterHealthServer(grpcServer, healthServer)
	
	// Enable reflection for development
	reflection.Register(grpcServer)
	
	// Setup listener
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", cfg.Server.GRPCPort))
	if err != nil {
		log.Fatal("Failed to listen:", err)
	}
	
	// Start server in goroutine
	go func() {
		log.Printf("Starting gRPC server on port %d", cfg.Server.GRPCPort)
		if err := grpcServer.Serve(lis); err != nil {
			log.Fatal("Failed to serve:", err)
		}
	}()
	
	// Setup background tasks
	go runBackgroundTasks(context.Background(), memberService)
	
	// Wait for interrupt signal to gracefully shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	
	log.Println("Shutting down server...")
	
	// Graceful shutdown
	grpcServer.GracefulStop()
	
	log.Println("Server stopped")
}

func setupDatabase(cfg config.DatabaseConfig) (*sqlx.DB, error) {
	db, err := sqlx.Connect("postgres", cfg.GetDSN())
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}
	
	// Configure connection pool
	db.SetMaxOpenConns(cfg.MaxOpenConns)
	db.SetMaxIdleConns(cfg.MaxIdleConns)
	db.SetConnMaxLifetime(cfg.ConnMaxLifetime)
	
	// Test the connection
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}
	
	return db, nil
}

func setupRedis(cfg config.RedisConfig) *redis.Client {
	client := redis.NewClient(&redis.Options{
		Addr:         cfg.GetRedisAddr(),
		Password:     cfg.Password,
		DB:           cfg.DB,
		MaxRetries:   cfg.MaxRetries,
		PoolSize:     cfg.PoolSize,
		IdleTimeout:  cfg.IdleTimeout,
		DialTimeout:  10 * time.Second,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	})
	
	// Test the connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	
	if err := client.Ping(ctx).Err(); err != nil {
		log.Printf("Warning: Failed to connect to Redis: %v", err)
		// Return nil client if Redis is not available
		client.Close()
		return nil
	}
	
	log.Println("Successfully connected to Redis")
	return client
}

func runMigrations(cfg config.DatabaseConfig) error {
	m, err := migrate.New(cfg.MigrationPath, cfg.GetDSN())
	if err != nil {
		return fmt.Errorf("failed to create migrate instance: %w", err)
	}
	defer m.Close()
	
	err = m.Up()
	if err != nil && err != migrate.ErrNoChange {
		return fmt.Errorf("failed to run migrations: %w", err)
	}
	
	log.Println("Database migrations completed successfully")
	return nil
}

func runBackgroundTasks(ctx context.Context, memberService *service.MemberService) {
	ticker := time.NewTicker(1 * time.Hour) // Run every hour
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Expire old invitations
			if err := memberService.ExpireOldInvitations(ctx); err != nil {
				log.Printf("Error expiring old invitations: %v", err)
			}
		}
	}
}

func loggingInterceptor(
	ctx context.Context,
	req interface{},
	info *grpc.UnaryServerInfo,
	handler grpc.UnaryHandler,
) (interface{}, error) {
	start := time.Now()
	
	resp, err := handler(ctx, req)
	
	duration := time.Since(start)
	
	if err != nil {
		log.Printf("gRPC call failed: method=%s duration=%v error=%v", info.FullMethod, duration, err)
	} else {
		log.Printf("gRPC call: method=%s duration=%v", info.FullMethod, duration)
	}
	
	return resp, err
}