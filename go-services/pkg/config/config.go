package config

import (
	"github.com/caarlos0/env/v10"
)

// Config holds all configuration for the application
type Config struct {
	Server struct {
		Port string `env:"PORT" envDefault:"8080"`
		Host string `env:"HOST" envDefault:"0.0.0.0"`
		Env  string `env:"ENVIRONMENT" envDefault:"development"`
	}

	Database struct {
		URL             string `env:"DATABASE_URL" envDefault:"postgres://user:password@localhost/pyairtable?sslmode=disable"`
		MaxOpenConns    int    `env:"DB_MAX_OPEN_CONNS" envDefault:"25"`
		MaxIdleConns    int    `env:"DB_MAX_IDLE_CONNS" envDefault:"5"`
		ConnMaxLifetime int    `env:"DB_CONN_MAX_LIFETIME" envDefault:"300"` // seconds
	}

	Redis struct {
		URL      string `env:"REDIS_URL" envDefault:"redis://localhost:6379"`
		Password string `env:"REDIS_PASSWORD"`
		DB       int    `env:"REDIS_DB" envDefault:"0"`
	}

	JWT struct {
		Secret    string `env:"JWT_SECRET" envDefault:"default-secret-change-in-production"`
		Issuer    string `env:"JWT_ISSUER" envDefault:"pyairtable"`
		ExpiresIn int    `env:"JWT_EXPIRES_IN" envDefault:"86400"` // seconds (24 hours)
	}

	Auth struct {
		RequireAPIKey    bool   `env:"REQUIRE_API_KEY" envDefault:"true"`
		APIKey           string `env:"API_KEY"`
		PasswordMinLen   int    `env:"PASSWORD_MIN_LENGTH" envDefault:"8"`
		PasswordHashCost int    `env:"PASSWORD_HASH_ROUNDS" envDefault:"12"`
	}

	CORS struct {
		Origins []string `env:"CORS_ORIGINS" envSeparator:"," envDefault:"*"`
	}

	Services struct {
		LLMOrchestratorURL    string `env:"LLM_ORCHESTRATOR_URL" envDefault:"http://llm-orchestrator:8003"`
		MCPServerURL          string `env:"MCP_SERVER_URL" envDefault:"http://mcp-server:8001"`
		AirtableGatewayURL    string `env:"AIRTABLE_GATEWAY_URL" envDefault:"http://airtable-gateway:8002"`
		PlatformServicesURL   string `env:"PLATFORM_SERVICES_URL" envDefault:"http://platform-services:8007"`
		AutomationServicesURL string `env:"AUTOMATION_SERVICES_URL" envDefault:"http://automation-services:8006"`
	}

	FileProcessing struct {
		MaxFileSize       int64    `env:"MAX_FILE_SIZE" envDefault:"10485760"` // 10MB in bytes
		AllowedExtensions []string `env:"ALLOWED_EXTENSIONS" envSeparator:"," envDefault:"pdf,doc,docx,txt,csv,xlsx"`
		UploadDir         string   `env:"UPLOAD_DIR" envDefault:"/tmp/uploads"`
	}

	Workflow struct {
		DefaultTimeout    int `env:"DEFAULT_WORKFLOW_TIMEOUT" envDefault:"300"` // seconds
		MaxRetries        int `env:"MAX_WORKFLOW_RETRIES" envDefault:"3"`
		CheckInterval     int `env:"SCHEDULER_CHECK_INTERVAL" envDefault:"30"` // seconds
		WorkerPoolSize    int `env:"WORKER_POOL_SIZE" envDefault:"100"`
	}

	Analytics struct {
		RetentionDays  int `env:"ANALYTICS_RETENTION_DAYS" envDefault:"90"`
		BatchSize      int `env:"METRICS_BATCH_SIZE" envDefault:"100"`
		FlushInterval  int `env:"METRICS_FLUSH_INTERVAL" envDefault:"10"` // seconds
	}

	Logging struct {
		Level  string `env:"LOG_LEVEL" envDefault:"info"`
		Format string `env:"LOG_FORMAT" envDefault:"json"` // json or text
	}

	Metrics struct {
		Enabled   bool   `env:"METRICS_ENABLED" envDefault:"true"`
		Namespace string `env:"METRICS_NAMESPACE" envDefault:"pyairtable"`
		Path      string `env:"METRICS_PATH" envDefault:"/metrics"`
	}

	RateLimit struct {
		RequestsPerMinute int `env:"RATE_LIMIT_RPM" envDefault:"100"`
		BurstSize         int `env:"RATE_LIMIT_BURST" envDefault:"10"`
	}
}

// Load loads configuration from environment variables
func Load() (*Config, error) {
	cfg := &Config{}
	if err := env.Parse(cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

// IsDevelopment returns true if running in development mode
func (c *Config) IsDevelopment() bool {
	return c.Server.Env == "development"
}

// IsProduction returns true if running in production mode
func (c *Config) IsProduction() bool {
	return c.Server.Env == "production"
}

// GetServerAddress returns the full server address
func (c *Config) GetServerAddress() string {
	return c.Server.Host + ":" + c.Server.Port
}