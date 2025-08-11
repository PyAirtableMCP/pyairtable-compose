package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/jmoiron/sqlx"
	"github.com/pyairtable/workspace-service/internal/models"
)

// InvitationRepository handles database operations for invitations
type InvitationRepository struct {
	db *sqlx.DB
}

// NewInvitationRepository creates a new invitation repository
func NewInvitationRepository(db *sqlx.DB) *InvitationRepository {
	return &InvitationRepository{db: db}
}

// Create creates a new invitation
func (r *InvitationRepository) Create(ctx context.Context, invitation *models.Invitation) error {
	query := `
		INSERT INTO invitations (id, workspace_id, invited_by, email, role, status, token, expires_at, created_at)
		VALUES (:id, :workspace_id, :invited_by, :email, :role, :status, :token, :expires_at, :created_at)`
	
	_, err := r.db.NamedExecContext(ctx, query, invitation)
	return err
}

// GetByID retrieves an invitation by ID
func (r *InvitationRepository) GetByID(ctx context.Context, id string) (*models.Invitation, error) {
	invitation := &models.Invitation{}
	query := `SELECT * FROM invitations WHERE id = $1`
	
	err := r.db.GetContext(ctx, invitation, query, id)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("invitation not found: %s", id)
		}
		return nil, err
	}
	
	return invitation, nil
}

// GetByToken retrieves an invitation by token
func (r *InvitationRepository) GetByToken(ctx context.Context, token string) (*models.Invitation, error) {
	invitation := &models.Invitation{}
	query := `SELECT * FROM invitations WHERE token = $1`
	
	err := r.db.GetContext(ctx, invitation, query, token)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("invitation not found for token: %s", token)
		}
		return nil, err
	}
	
	return invitation, nil
}

// GetByWorkspaceAndEmail retrieves an invitation by workspace and email
func (r *InvitationRepository) GetByWorkspaceAndEmail(ctx context.Context, workspaceID, email string) (*models.Invitation, error) {
	invitation := &models.Invitation{}
	query := `SELECT * FROM invitations WHERE workspace_id = $1 AND email = $2 AND status = 'pending'`
	
	err := r.db.GetContext(ctx, invitation, query, workspaceID, email)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("pending invitation not found for workspace %s and email %s", workspaceID, email)
		}
		return nil, err
	}
	
	return invitation, nil
}

// Update updates an invitation
func (r *InvitationRepository) Update(ctx context.Context, invitation *models.Invitation) error {
	query := `
		UPDATE invitations 
		SET status = :status
		WHERE id = :id`
	
	result, err := r.db.NamedExecContext(ctx, query, invitation)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("invitation not found: %s", invitation.ID)
	}
	
	return nil
}

// UpdateStatus updates invitation status
func (r *InvitationRepository) UpdateStatus(ctx context.Context, id string, status models.InvitationStatus) error {
	query := `UPDATE invitations SET status = $2 WHERE id = $1`
	
	result, err := r.db.ExecContext(ctx, query, id, status)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("invitation not found: %s", id)
	}
	
	return nil
}

// Delete deletes an invitation
func (r *InvitationRepository) Delete(ctx context.Context, id string) error {
	query := `DELETE FROM invitations WHERE id = $1`
	
	result, err := r.db.ExecContext(ctx, query, id)
	if err != nil {
		return err
	}
	
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	
	if rows == 0 {
		return fmt.Errorf("invitation not found: %s", id)
	}
	
	return nil
}

// ListByWorkspace lists invitations for a workspace
func (r *InvitationRepository) ListByWorkspace(ctx context.Context, workspaceID string, status models.InvitationStatus) ([]*models.Invitation, error) {
	var invitations []*models.Invitation
	var query string
	var args []interface{}
	
	if status != "" {
		query = `SELECT * FROM invitations WHERE workspace_id = $1 AND status = $2 ORDER BY created_at DESC`
		args = []interface{}{workspaceID, status}
	} else {
		query = `SELECT * FROM invitations WHERE workspace_id = $1 ORDER BY created_at DESC`
		args = []interface{}{workspaceID}
	}
	
	err := r.db.SelectContext(ctx, &invitations, query, args...)
	if err != nil {
		return nil, err
	}
	
	return invitations, nil
}

// ListByEmail lists invitations for an email address
func (r *InvitationRepository) ListByEmail(ctx context.Context, email string, status models.InvitationStatus) ([]*models.Invitation, error) {
	var invitations []*models.Invitation
	var query string
	var args []interface{}
	
	if status != "" {
		query = `SELECT * FROM invitations WHERE email = $1 AND status = $2 ORDER BY created_at DESC`
		args = []interface{}{email, status}
	} else {
		query = `SELECT * FROM invitations WHERE email = $1 ORDER BY created_at DESC`
		args = []interface{}{email}
	}
	
	err := r.db.SelectContext(ctx, &invitations, query, args...)
	if err != nil {
		return nil, err
	}
	
	return invitations, nil
}

// ExistsPendingByEmail checks if there's a pending invitation for the email in the workspace
func (r *InvitationRepository) ExistsPendingByEmail(ctx context.Context, workspaceID, email string) (bool, error) {
	var count int
	query := `SELECT COUNT(*) FROM invitations WHERE workspace_id = $1 AND email = $2 AND status = 'pending'`
	
	err := r.db.GetContext(ctx, &count, query, workspaceID, email)
	if err != nil {
		return false, err
	}
	
	return count > 0, nil
}

// ExpireOldInvitations marks expired invitations as expired
func (r *InvitationRepository) ExpireOldInvitations(ctx context.Context) error {
	query := `
		UPDATE invitations 
		SET status = 'expired' 
		WHERE status = 'pending' AND expires_at < NOW()`
	
	_, err := r.db.ExecContext(ctx, query)
	return err
}

// CleanupExpiredInvitations deletes old expired invitations
func (r *InvitationRepository) CleanupExpiredInvitations(ctx context.Context, olderThanDays int) error {
	query := `
		DELETE FROM invitations 
		WHERE status IN ('expired', 'declined') 
		AND created_at < NOW() - INTERVAL '%d days'`
	
	_, err := r.db.ExecContext(ctx, fmt.Sprintf(query, olderThanDays))
	return err
}