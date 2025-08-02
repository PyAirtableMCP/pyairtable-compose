package config

import (
    "os"
    "strconv"
    "time"
)

type Config struct {
    Port         string
    Environment  string
    
    // Service URLs
    AuthServiceURL        string
    UserServiceURL        string
    TenantServiceURL      string
    WorkspaceServiceURL   string
    PermissionServiceURL  string
    AirtableGatewayURL    string
    
    // Database
    DatabaseURL string
    
    // Redis
    RedisURL      string
    RedisPassword string
    
    // CORS
    CORSOrigins string
    
    // Rate Limiting
    RateLimitPerMinute int
    
    // Timeouts
    RequestTimeout  time.Duration
    ShutdownTimeout time.Duration
}

func Load() *Config {
    return &Config{
        Port:        getEnv("PORT", "8080"),
        Environment: getEnv("ENVIRONMENT", "development"),
        
        // Service URLs
        AuthServiceURL:        getEnv("AUTH_SERVICE_URL", "http://auth-service"),
        UserServiceURL:        getEnv("USER_SERVICE_URL", "http://user-service"),
        TenantServiceURL:      getEnv("TENANT_SERVICE_URL", "http://tenant-service"),
        WorkspaceServiceURL:   getEnv("WORKSPACE_SERVICE_URL", "http://workspace-service"),
        PermissionServiceURL:  getEnv("PERMISSION_SERVICE_URL", "http://permission-service"),
        AirtableGatewayURL:    getEnv("AIRTABLE_GATEWAY_URL", "http://airtable-gateway:8002"),
        
        // Database
        DatabaseURL: getEnv("DATABASE_URL", "postgres://postgres:password@localhost/pyairtable"),
        
        // Redis
        RedisURL:      getEnv("REDIS_URL", "redis://localhost:6379"),
        RedisPassword: getEnv("REDIS_PASSWORD", ""),
        
        // CORS
        CORSOrigins: getEnv("CORS_ORIGINS", "*"),
        
        // Rate Limiting
        RateLimitPerMinute: getEnvAsInt("RATE_LIMIT_PER_MINUTE", 100),
        
        // Timeouts
        RequestTimeout:  getEnvAsDuration("REQUEST_TIMEOUT", 30*time.Second),
        ShutdownTimeout: getEnvAsDuration("SHUTDOWN_TIMEOUT", 10*time.Second),
    }
}

func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}

func getEnvAsInt(key string, defaultValue int) int {
    valueStr := getEnv(key, "")
    if value, err := strconv.Atoi(valueStr); err == nil {
        return value
    }
    return defaultValue
}

func getEnvAsDuration(key string, defaultValue time.Duration) time.Duration {
    valueStr := getEnv(key, "")
    if value, err := time.ParseDuration(valueStr); err == nil {
        return value
    }
    return defaultValue
}