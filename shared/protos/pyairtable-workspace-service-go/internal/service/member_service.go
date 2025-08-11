package service

import (
	"context"
	"fmt"
	"time"

	"github.com/pyairtable/workspace-service/internal/models"
	"github.com/pyairtable/workspace-service/internal/permissions"
	"github.com/pyairtable/workspace-service/internal/repository"
	"github.com/redis/go-redis/v9"
)

// MemberService handles business logic for workspace members
type MemberService struct {
	memberRepo      *repository.MemberRepository
	invitationRepo  *repository.InvitationRepository
	permissionRepo  *repository.PermissionRepository
	permissionCheck *permissions.PermissionChecker
	redisClient     *redis.Client
}

// NewMemberService creates a new member service
func NewMemberService(
	memberRepo *repository.MemberRepository,
	invitationRepo *repository.InvitationRepository,
	permissionRepo *repository.PermissionRepository,
	permissionCheck *permissions.PermissionChecker,
	redisClient *redis.Client,
) *MemberService {
	return &MemberService{
		memberRepo:      memberRepo,
		invitationRepo:  invitationRepo,
		permissionRepo:  permissionRepo,
		permissionCheck: permissionCheck,
		redisClient:     redisClient,
	}
}

// InviteMember invites a new member to the workspace
func (s *MemberService) InviteMember(ctx context.Context, workspaceID, invitedBy, email string, role models.MemberRole, message string) (*models.Invitation, error) {
	// Check permissions
	if err := s.permissionCheck.CanManageMembers(ctx, workspaceID, invitedBy); err != nil {
		return nil, err
	}
	
	// Check if user is already a member
	exists, err := s.memberRepo.ExistsByEmail(ctx, workspaceID, email)
	if err != nil {
		return nil, fmt.Errorf("failed to check existing member: %w", err)
	}
	if exists {
		return nil, fmt.Errorf("user is already a member of this workspace")
	}
	
	// Check if there's already a pending invitation
	pendingExists, err := s.invitationRepo.ExistsPendingByEmail(ctx, workspaceID, email)
	if err != nil {
		return nil, fmt.Errorf("failed to check pending invitation: %w", err)
	}
	if pendingExists {
		return nil, fmt.Errorf("there is already a pending invitation for this email")
	}
	
	// Create invitation
	invitation := models.NewInvitation(workspaceID, invitedBy, email, role)
	
	if err := s.invitationRepo.Create(ctx, invitation); err != nil {
		return nil, fmt.Errorf("failed to create invitation: %w", err)
	}
	
	// TODO: Send invitation email
	
	// Invalidate cache
	s.invalidateMembersCache(ctx, workspaceID)
	
	return invitation, nil
}

// AcceptInvitation accepts a workspace invitation
func (s *MemberService) AcceptInvitation(ctx context.Context, token, userID string) (*models.Member, error) {
	// Get invitation by token
	invitation, err := s.invitationRepo.GetByToken(ctx, token)
	if err != nil {
		return nil, fmt.Errorf("invalid invitation token")
	}
	
	// Check if invitation is still pending
	if invitation.Status != models.InvitationStatusPending {
		return nil, fmt.Errorf("invitation is no longer pending")
	}
	
	// Check if invitation is expired
	if invitation.IsExpired() {
		// Update status to expired
		invitation.Status = models.InvitationStatusExpired
		s.invitationRepo.Update(ctx, invitation)
		return nil, fmt.Errorf("invitation has expired")
	}
	
	// Check if user is already a member
	exists, err := s.memberRepo.ExistsByEmail(ctx, invitation.WorkspaceID, invitation.Email)
	if err != nil {
		return nil, fmt.Errorf("failed to check existing member: %w", err)
	}
	if exists {
		return nil, fmt.Errorf("user is already a member of this workspace")
	}
	
	// Create member
	member := models.NewMember(invitation.WorkspaceID, userID, invitation.Email, "", invitation.Role)
	
	if err := s.memberRepo.Create(ctx, member); err != nil {
		return nil, fmt.Errorf("failed to create member: %w", err)
	}
	
	// Update invitation status
	invitation.Status = models.InvitationStatusAccepted
	if err := s.invitationRepo.Update(ctx, invitation); err != nil {
		// Log error but don't fail the operation
		fmt.Printf("Failed to update invitation status: %v", err)
	}
	
	// Invalidate cache
	s.invalidateMembersCache(ctx, invitation.WorkspaceID)
	
	return member, nil
}

// DeclineInvitation declines a workspace invitation
func (s *MemberService) DeclineInvitation(ctx context.Context, token string) error {
	// Get invitation by token
	invitation, err := s.invitationRepo.GetByToken(ctx, token)
	if err != nil {
		return fmt.Errorf("invalid invitation token")
	}
	
	// Check if invitation is still pending
	if invitation.Status != models.InvitationStatusPending {
		return fmt.Errorf("invitation is no longer pending")
	}
	
	// Update invitation status
	invitation.Status = models.InvitationStatusDeclined
	if err := s.invitationRepo.Update(ctx, invitation); err != nil {
		return fmt.Errorf("failed to decline invitation: %w", err)
	}
	
	return nil
}

// RemoveMember removes a member from the workspace
func (s *MemberService) RemoveMember(ctx context.Context, workspaceID, userID, memberID string) error {
	// Check permissions
	if err := s.permissionCheck.CanRemoveMember(ctx, workspaceID, userID, memberID); err != nil {
		return err
	}
	
	// Remove member
	if err := s.memberRepo.Delete(ctx, memberID); err != nil {
		return fmt.Errorf("failed to remove member: %w", err)
	}
	
	// Remove all permissions for this user
	member, err := s.memberRepo.GetByID(ctx, memberID)
	if err == nil {
		s.permissionRepo.RevokeAllForUser(ctx, workspaceID, member.UserID)
	}
	
	// Invalidate cache
	s.invalidateMembersCache(ctx, workspaceID)
	
	return nil
}

// UpdateMemberRole updates a member's role
func (s *MemberService) UpdateMemberRole(ctx context.Context, workspaceID, userID, memberID string, newRole models.MemberRole) (*models.Member, error) {
	// Check permissions
	if err := s.permissionCheck.CanUpdateMemberRole(ctx, workspaceID, userID, memberID, newRole); err != nil {
		return nil, err
	}
	
	// Update role
	if err := s.memberRepo.UpdateRole(ctx, memberID, newRole); err != nil {
		return nil, fmt.Errorf("failed to update member role: %w", err)
	}
	
	// Get updated member
	member, err := s.memberRepo.GetByID(ctx, memberID)
	if err != nil {
		return nil, fmt.Errorf("failed to get updated member: %w", err)
	}
	
	// Invalidate cache
	s.invalidateMembersCache(ctx, workspaceID)
	
	return member, nil
}

// ListMembers lists members of a workspace
func (s *MemberService) ListMembers(ctx context.Context, workspaceID, userID string, roleFilter models.MemberRole, page, pageSize int) ([]*models.Member, int, error) {
	// Check permissions
	if err := s.permissionCheck.CanViewWorkspace(ctx, workspaceID, userID); err != nil {
		return nil, 0, err
	}
	
	// Try to get from cache first
	if members, total := s.getMembersFromCache(ctx, workspaceID, roleFilter, page, pageSize); members != nil {
		return members, total, nil
	}
	
	members, total, err := s.memberRepo.ListByWorkspace(ctx, workspaceID, roleFilter, page, pageSize)
	if err != nil {
		return nil, 0, err
	}
	
	// Cache the result
	s.cacheMembers(ctx, workspaceID, roleFilter, page, pageSize, members, total)
	
	return members, total, nil
}

// GetMember gets a specific member
func (s *MemberService) GetMember(ctx context.Context, workspaceID, userID, memberID string) (*models.Member, error) {
	// Check permissions
	if err := s.permissionCheck.CanViewWorkspace(ctx, workspaceID, userID); err != nil {
		return nil, err
	}
	
	member, err := s.memberRepo.GetByID(ctx, memberID)
	if err != nil {
		return nil, err
	}
	
	// Verify member belongs to the workspace
	if member.WorkspaceID != workspaceID {
		return nil, fmt.Errorf("member not found in workspace")
	}
	
	return member, nil
}

// ListInvitations lists pending invitations for a workspace
func (s *MemberService) ListInvitations(ctx context.Context, workspaceID, userID string) ([]*models.Invitation, error) {
	// Check permissions
	if err := s.permissionCheck.CanManageMembers(ctx, workspaceID, userID); err != nil {
		return nil, err
	}
	
	invitations, err := s.invitationRepo.ListByWorkspace(ctx, workspaceID, models.InvitationStatusPending)
	if err != nil {
		return nil, err
	}
	
	return invitations, nil
}

// ExpireOldInvitations marks old invitations as expired
func (s *MemberService) ExpireOldInvitations(ctx context.Context) error {
	return s.invitationRepo.ExpireOldInvitations(ctx)
}

// Cache methods
func (s *MemberService) cacheMembers(ctx context.Context, workspaceID string, roleFilter models.MemberRole, page, pageSize int, members []*models.Member, total int) {
	if s.redisClient == nil {
		return
	}
	
	key := fmt.Sprintf("members:%s:%s:%d:%d", workspaceID, roleFilter, page, pageSize)
	// Note: In production, you'd use proper JSON serialization
	s.redisClient.Set(ctx, key, fmt.Sprintf("%d", total), 5*time.Minute)
}

func (s *MemberService) getMembersFromCache(ctx context.Context, workspaceID string, roleFilter models.MemberRole, page, pageSize int) ([]*models.Member, int) {
	if s.redisClient == nil {
		return nil, 0
	}
	
	// Note: Simplified implementation - in production you'd cache the actual data
	return nil, 0
}

func (s *MemberService) invalidateMembersCache(ctx context.Context, workspaceID string) {
	if s.redisClient == nil {
		return
	}
	
	pattern := fmt.Sprintf("members:%s:*", workspaceID)
	keys, err := s.redisClient.Keys(ctx, pattern).Result()
	if err != nil {
		return
	}
	
	if len(keys) > 0 {
		s.redisClient.Del(ctx, keys...)
	}
}