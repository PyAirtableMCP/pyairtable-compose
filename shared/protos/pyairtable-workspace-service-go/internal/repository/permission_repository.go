package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/jmoiron/sqlx"
	"github.com/pyairtable/workspace-service/internal/models"
)

// PermissionRepository handles database operations for permissions
type PermissionRepository struct {
	db *sqlx.DB
}

// NewPermissionRepository creates a new permission repository
func NewPermissionRepository(db *sqlx.DB) *PermissionRepository {
	return &PermissionRepository{db: db}
}

// Grant creates a new permission grant
func (r *PermissionRepository) Grant(ctx context.Context, grant *models.PermissionGrant) error {
	query := `
		INSERT INTO permission_grants (id, workspace_id, user_id, resource_type, resource_id, permission, granted_at, granted_by)
		VALUES (:id, :workspace_id, :user_id, :resource_type, :resource_id, :permission, :granted_at, :granted_by)
		ON CONFLICT (workspace_id, user_id, resource_type, resource_id, permission) 
		DO UPDATE SET granted_at = :granted_at, granted_by = :granted_by`
	
	_, err := r.db.NamedExecContext(ctx, query, grant)
	return err
}

// Revoke removes a permission grant
func (r *PermissionRepository) Revoke(ctx context.Context, workspaceID, userID, resourceType, resourceID string, permission models.Permission) error {
	query := `
		DELETE FROM permission_grants 
		WHERE workspace_id = $1 AND user_id = $2 AND resource_type = $3 AND resource_id = $4 AND permission = $5`
	
	result, err := r.db.ExecContext(ctx, query, workspaceID, userID, resourceType, resourceID, permission)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("permission grant not found")
	}
	
	return nil
}

// CheckPermission checks if a user has a specific permission
func (r *PermissionRepository) CheckPermission(ctx context.Context, workspaceID, userID, resourceType, resourceID string, permission models.Permission) (bool, error) {
	var count int
	query := `
		SELECT COUNT(*) 
		FROM permission_grants 
		WHERE workspace_id = $1 AND user_id = $2 AND resource_type = $3 AND resource_id = $4 AND permission = $5`
	
	err := r.db.GetContext(ctx, &count, query, workspaceID, userID, resourceType, resourceID, permission)
	if err != nil {
		return false, err
	}
	
	return count > 0, nil
}

// ListByUser lists all permissions for a user in a workspace
func (r *PermissionRepository) ListByUser(ctx context.Context, workspaceID, userID string) ([]*models.PermissionGrant, error) {
	var grants []*models.PermissionGrant
	query := `
		SELECT * FROM permission_grants 
		WHERE workspace_id = $1 AND user_id = $2
		ORDER BY granted_at DESC`
	
	err := r.db.SelectContext(ctx, &grants, query, workspaceID, userID)
	if err != nil {
		return nil, err
	}
	
	return grants, nil
}

// ListByResource lists all permissions for a specific resource
func (r *PermissionRepository) ListByResource(ctx context.Context, workspaceID, resourceType, resourceID string, targetUserID string) ([]*models.PermissionGrant, error) {
	var grants []*models.PermissionGrant
	var query string
	var args []interface{}
	
	if targetUserID != "" {
		query = `
			SELECT * FROM permission_grants 
			WHERE workspace_id = $1 AND resource_type = $2 AND resource_id = $3 AND user_id = $4
			ORDER BY granted_at DESC`
		args = []interface{}{workspaceID, resourceType, resourceID, targetUserID}
	} else {
		query = `
			SELECT * FROM permission_grants 
			WHERE workspace_id = $1 AND resource_type = $2 AND resource_id = $3
			ORDER BY granted_at DESC`
		args = []interface{}{workspaceID, resourceType, resourceID}
	}
	
	err := r.db.SelectContext(ctx, &grants, query, args...)
	if err != nil {
		return nil, err
	}
	
	return grants, nil
}

// ListByWorkspace lists all permissions in a workspace
func (r *PermissionRepository) ListByWorkspace(ctx context.Context, workspaceID string, filters map[string]interface{}) ([]*models.PermissionGrant, error) {
	conditions := []string{"workspace_id = $1"}
	args := []interface{}{workspaceID}
	argCount := 1
	
	if userID, ok := filters["user_id"]; ok && userID != "" {
		argCount++
		conditions = append(conditions, fmt.Sprintf("user_id = $%d", argCount))
		args = append(args, userID)
	}
	
	if resourceType, ok := filters["resource_type"]; ok && resourceType != "" {
		argCount++
		conditions = append(conditions, fmt.Sprintf("resource_type = $%d", argCount))
		args = append(args, resourceType)
	}
	
	if resourceID, ok := filters["resource_id"]; ok && resourceID != "" {
		argCount++
		conditions = append(conditions, fmt.Sprintf("resource_id = $%d", argCount))
		args = append(args, resourceID)
	}
	
	whereClause := strings.Join(conditions, " AND ")
	
	query := fmt.Sprintf(`
		SELECT * FROM permission_grants 
		WHERE %s
		ORDER BY granted_at DESC`, whereClause)
	
	var grants []*models.PermissionGrant
	err := r.db.SelectContext(ctx, &grants, query, args...)
	if err != nil {
		return nil, err
	}
	
	return grants, nil
}

// GetByID retrieves a permission grant by ID
func (r *PermissionRepository) GetByID(ctx context.Context, id string) (*models.PermissionGrant, error) {
	grant := &models.PermissionGrant{}
	query := `SELECT * FROM permission_grants WHERE id = $1`
	
	err := r.db.GetContext(ctx, grant, query, id)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("permission grant not found: %s", id)
		}
		return nil, err
	}
	
	return grant, nil
}

// RevokeAllForUser removes all permissions for a user in a workspace
func (r *PermissionRepository) RevokeAllForUser(ctx context.Context, workspaceID, userID string) error {
	query := `DELETE FROM permission_grants WHERE workspace_id = $1 AND user_id = $2`
	
	_, err := r.db.ExecContext(ctx, query, workspaceID, userID)
	return err
}

// RevokeAllForResource removes all permissions for a specific resource
func (r *PermissionRepository) RevokeAllForResource(ctx context.Context, workspaceID, resourceType, resourceID string) error {
	query := `DELETE FROM permission_grants WHERE workspace_id = $1 AND resource_type = $2 AND resource_id = $3`
	
	_, err := r.db.ExecContext(ctx, query, workspaceID, resourceType, resourceID)
	return err
}

// HasAnyPermission checks if a user has any permission on a resource
func (r *PermissionRepository) HasAnyPermission(ctx context.Context, workspaceID, userID, resourceType, resourceID string) (bool, error) {
	var count int
	query := `
		SELECT COUNT(*) 
		FROM permission_grants 
		WHERE workspace_id = $1 AND user_id = $2 AND resource_type = $3 AND resource_id = $4`
	
	err := r.db.GetContext(ctx, &count, query, workspaceID, userID, resourceType, resourceID)
	if err != nil {
		return false, err
	}
	
	return count > 0, nil
}

// GetUserPermissions gets all permissions for a user on a specific resource
func (r *PermissionRepository) GetUserPermissions(ctx context.Context, workspaceID, userID, resourceType, resourceID string) ([]models.Permission, error) {
	var permissions []models.Permission
	query := `
		SELECT permission 
		FROM permission_grants 
		WHERE workspace_id = $1 AND user_id = $2 AND resource_type = $3 AND resource_id = $4`
	
	err := r.db.SelectContext(ctx, &permissions, query, workspaceID, userID, resourceType, resourceID)
	if err != nil {
		return nil, err
	}
	
	return permissions, nil
}