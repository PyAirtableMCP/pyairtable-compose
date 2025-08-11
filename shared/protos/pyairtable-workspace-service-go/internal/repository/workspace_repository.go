package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"
	"github.com/pyairtable/workspace-service/internal/models"
)

// WorkspaceRepository handles database operations for workspaces
type WorkspaceRepository struct {
	db *sqlx.DB
}

// NewWorkspaceRepository creates a new workspace repository
func NewWorkspaceRepository(db *sqlx.DB) *WorkspaceRepository {
	return &WorkspaceRepository{db: db}
}

// Create creates a new workspace
func (r *WorkspaceRepository) Create(ctx context.Context, workspace *models.Workspace) error {
	query := `
		INSERT INTO workspaces (id, name, description, owner_id, status, settings, created_at, updated_at)
		VALUES (:id, :name, :description, :owner_id, :status, :settings, :created_at, :updated_at)`
	
	_, err := r.db.NamedExecContext(ctx, query, workspace)
	return err
}

// GetByID retrieves a workspace by ID
func (r *WorkspaceRepository) GetByID(ctx context.Context, id string) (*models.Workspace, error) {
	workspace := &models.Workspace{}
	query := `
		SELECT w.*, COALESCE(m.member_count, 0) as member_count
		FROM workspaces w
		LEFT JOIN (
			SELECT workspace_id, COUNT(*) as member_count 
			FROM members 
			WHERE is_active = true 
			GROUP BY workspace_id
		) m ON w.id = m.workspace_id
		WHERE w.id = $1`
	
	err := r.db.GetContext(ctx, workspace, query, id)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("workspace not found: %s", id)
		}
		return nil, err
	}
	
	return workspace, nil
}

// Update updates a workspace
func (r *WorkspaceRepository) Update(ctx context.Context, workspace *models.Workspace) error {
	workspace.UpdatedAt = time.Now()
	
	query := `
		UPDATE workspaces 
		SET name = :name, description = :description, status = :status, 
			settings = :settings, updated_at = :updated_at
		WHERE id = :id`
	
	result, err := r.db.NamedExecContext(ctx, query, workspace)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("workspace not found: %s", workspace.ID)
	}
	
	return nil
}

// Delete deletes a workspace
func (r *WorkspaceRepository) Delete(ctx context.Context, id string) error {
	query := `DELETE FROM workspaces WHERE id = $1`
	
	result, err := r.db.ExecContext(ctx, query, id)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("workspace not found: %s", id)
	}
	
	return nil
}

// ListByUserID lists workspaces where user is a member
func (r *WorkspaceRepository) ListByUserID(ctx context.Context, userID string, status models.WorkspaceStatus, page, pageSize int) ([]*models.Workspace, int, error) {
	offset := (page - 1) * pageSize
	
	conditions := []string{"m.user_id = $1", "m.is_active = true"}
	args := []interface{}{userID}
	argCount := 1
	
	if status != "" {
		argCount++
		conditions = append(conditions, fmt.Sprintf("w.status = $%d", argCount))
		args = append(args, status)
	}
	
	whereClause := strings.Join(conditions, " AND ")
	
	// Get total count
	countQuery := fmt.Sprintf(`
		SELECT COUNT(DISTINCT w.id)
		FROM workspaces w
		INNER JOIN members m ON w.id = m.workspace_id
		WHERE %s`, whereClause)
	
	var totalCount int
	err := r.db.GetContext(ctx, &totalCount, countQuery, args...)
	if err != nil {
		return nil, 0, err
	}
	
	// Get workspaces with pagination
	query := fmt.Sprintf(`
		SELECT DISTINCT w.*, COALESCE(mc.member_count, 0) as member_count
		FROM workspaces w
		INNER JOIN members m ON w.id = m.workspace_id
		LEFT JOIN (
			SELECT workspace_id, COUNT(*) as member_count 
			FROM members 
			WHERE is_active = true 
			GROUP BY workspace_id
		) mc ON w.id = mc.workspace_id
		WHERE %s
		ORDER BY w.updated_at DESC
		LIMIT $%d OFFSET $%d`, whereClause, argCount+1, argCount+2)
	
	args = append(args, pageSize, offset)
	
	var workspaces []*models.Workspace
	err = r.db.SelectContext(ctx, &workspaces, query, args...)
	if err != nil {
		return nil, 0, err
	}
	
	return workspaces, totalCount, nil
}

// UpdateSettings updates workspace settings
func (r *WorkspaceRepository) UpdateSettings(ctx context.Context, id string, settings models.WorkspaceSettings) error {
	query := `
		UPDATE workspaces 
		SET settings = $2, updated_at = NOW()
		WHERE id = $1`
	
	result, err := r.db.ExecContext(ctx, query, id, settings)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("workspace not found: %s", id)
	}
	
	return nil
}