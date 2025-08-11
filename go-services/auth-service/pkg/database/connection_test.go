package database

import (
	"testing"
)

func TestConnect(t *testing.T) {
	// Test with default localhost connection
	databaseURL := "postgres://postgres:password@localhost:5432/pyairtable_auth?sslmode=disable"
	
	db, err := Connect(databaseURL)
	if err != nil {
		t.Skipf("Skipping database test - PostgreSQL not available: %v", err)
		return
	}
	defer db.Close()

	// Test health check
	if err := db.Health(); err != nil {
		t.Fatalf("Database health check failed: %v", err)
	}
}

func TestConnect_InvalidURL(t *testing.T) {
	// Test with invalid connection string
	databaseURL := "invalid://connection"
	
	_, err := Connect(databaseURL)
	if err == nil {
		t.Fatal("Expected error with invalid database URL")
	}
}