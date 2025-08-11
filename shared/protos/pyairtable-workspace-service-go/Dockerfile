# Build stage
FROM golang:1.21-alpine AS builder

# Install dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o workspace-service ./cmd/workspace

# Final stage
FROM alpine:latest

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

# Create non-root user
RUN adduser -D -s /bin/sh workspace

# Set working directory
WORKDIR /home/workspace

# Copy binary from builder stage
COPY --from=builder /app/workspace-service .

# Copy migrations
COPY --from=builder /app/migrations ./migrations

# Copy config
COPY --from=builder /app/configs ./configs

# Change ownership to non-root user
RUN chown -R workspace:workspace /home/workspace

# Switch to non-root user
USER workspace

# Expose port
EXPOSE 50053

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD grpc_health_probe -addr=:50053 || exit 1

# Run the application
CMD ["./workspace-service"]