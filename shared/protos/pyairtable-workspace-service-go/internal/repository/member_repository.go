package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/jmoiron/sqlx"
	"github.com/pyairtable/workspace-service/internal/models"
)

// MemberRepository handles database operations for workspace members
type MemberRepository struct {
	db *sqlx.DB
}

// NewMemberRepository creates a new member repository
func NewMemberRepository(db *sqlx.DB) *MemberRepository {
	return &MemberRepository{db: db}
}

// Create creates a new member
func (r *MemberRepository) Create(ctx context.Context, member *models.Member) error {
	query := `
		INSERT INTO members (id, workspace_id, user_id, email, name, role, joined_at, last_active, is_active)
		VALUES (:id, :workspace_id, :user_id, :email, :name, :role, :joined_at, :last_active, :is_active)`
	
	_, err := r.db.NamedExecContext(ctx, query, member)
	return err
}

// GetByID retrieves a member by ID
func (r *MemberRepository) GetByID(ctx context.Context, id string) (*models.Member, error) {
	member := &models.Member{}
	query := `SELECT * FROM members WHERE id = $1`
	
	err := r.db.GetContext(ctx, member, query, id)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("member not found: %s", id)
		}
		return nil, err
	}
	
	return member, nil
}

// GetByWorkspaceAndUser retrieves a member by workspace and user ID
func (r *MemberRepository) GetByWorkspaceAndUser(ctx context.Context, workspaceID, userID string) (*models.Member, error) {
	member := &models.Member{}
	query := `SELECT * FROM members WHERE workspace_id = $1 AND user_id = $2 AND is_active = true`
	
	err := r.db.GetContext(ctx, member, query, workspaceID, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("member not found for workspace %s and user %s", workspaceID, userID)
		}
		return nil, err
	}
	
	return member, nil
}

// Update updates a member
func (r *MemberRepository) Update(ctx context.Context, member *models.Member) error {
	query := `
		UPDATE members 
		SET email = :email, name = :name, role = :role, last_active = :last_active, is_active = :is_active
		WHERE id = :id`
	
	result, err := r.db.NamedExecContext(ctx, query, member)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("member not found: %s", member.ID)
	}
	
	return nil
}

// UpdateRole updates a member's role
func (r *MemberRepository) UpdateRole(ctx context.Context, id string, role models.MemberRole) error {
	query := `UPDATE members SET role = $2, last_active = NOW() WHERE id = $1`
	
	result, err := r.db.ExecContext(ctx, query, id, role)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("member not found: %s", id)
	}
	
	return nil
}

// Delete soft deletes a member (sets is_active = false)
func (r *MemberRepository) Delete(ctx context.Context, id string) error {
	query := `UPDATE members SET is_active = false WHERE id = $1`
	
	result, err := r.db.ExecContext(ctx, query, id)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("member not found: %s", id)
	}
	
	return nil
}

// ListByWorkspace lists members of a workspace
func (r *MemberRepository) ListByWorkspace(ctx context.Context, workspaceID string, roleFilter models.MemberRole, page, pageSize int) ([]*models.Member, int, error) {
	offset := (page - 1) * pageSize
	
	conditions := []string{"workspace_id = $1", "is_active = true"}
	args := []interface{}{workspaceID}
	argCount := 1
	
	if roleFilter != "" {
		argCount++
		conditions = append(conditions, fmt.Sprintf("role = $%d", argCount))
		args = append(args, roleFilter)
	}
	
	whereClause := strings.Join(conditions, " AND ")
	
	// Get total count
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM members WHERE %s", whereClause)
	
	var totalCount int
	err := r.db.GetContext(ctx, &totalCount, countQuery, args...)
	if err != nil {
		return nil, 0, err
	}
	
	// Get members with pagination
	query := fmt.Sprintf(`
		SELECT * FROM members 
		WHERE %s
		ORDER BY joined_at DESC
		LIMIT $%d OFFSET $%d`, whereClause, argCount+1, argCount+2)
	
	args = append(args, pageSize, offset)
	
	var members []*models.Member
	err = r.db.SelectContext(ctx, &members, query, args...)
	if err != nil {
		return nil, 0, err
	}
	
	return members, totalCount, nil
}

// CountByWorkspace counts active members in a workspace
func (r *MemberRepository) CountByWorkspace(ctx context.Context, workspaceID string) (int, error) {
	var count int
	query := `SELECT COUNT(*) FROM members WHERE workspace_id = $1 AND is_active = true`
	
	err := r.db.GetContext(ctx, &count, query, workspaceID)
	return count, err
}

// ExistsByEmail checks if a member with the given email exists in the workspace
func (r *MemberRepository) ExistsByEmail(ctx context.Context, workspaceID, email string) (bool, error) {
	var count int
	query := `SELECT COUNT(*) FROM members WHERE workspace_id = $1 AND email = $2 AND is_active = true`
	
	err := r.db.GetContext(ctx, &count, query, workspaceID, email)
	if err != nil {
		return false, err
	}
	
	return count > 0, nil
}

// GetOwner retrieves the owner of a workspace
func (r *MemberRepository) GetOwner(ctx context.Context, workspaceID string) (*models.Member, error) {
	member := &models.Member{}
	query := `SELECT * FROM members WHERE workspace_id = $1 AND role = 'owner' AND is_active = true`
	
	err := r.db.GetContext(ctx, member, query, workspaceID)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("workspace owner not found for workspace: %s", workspaceID)
		}
		return nil, err
	}
	
	return member, nil
}