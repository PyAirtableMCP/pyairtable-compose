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

// WorkspaceService handles business logic for workspaces
type WorkspaceService struct {
	workspaceRepo   *repository.WorkspaceRepository
	memberRepo      *repository.MemberRepository
	invitationRepo  *repository.InvitationRepository
	permissionRepo  *repository.PermissionRepository
	permissionCheck *permissions.PermissionChecker
	redisClient     *redis.Client
}

// NewWorkspaceService creates a new workspace service
func NewWorkspaceService(
	workspaceRepo *repository.WorkspaceRepository,
	memberRepo *repository.MemberRepository,
	invitationRepo *repository.InvitationRepository,
	permissionRepo *repository.PermissionRepository,
	permissionCheck *permissions.PermissionChecker,
	redisClient *redis.Client,
) *WorkspaceService {
	return &WorkspaceService{
		workspaceRepo:   workspaceRepo,
		memberRepo:      memberRepo,
		invitationRepo:  invitationRepo,
		permissionRepo:  permissionRepo,
		permissionCheck: permissionCheck,
		redisClient:     redisClient,
	}
}

// CreateWorkspace creates a new workspace
func (s *WorkspaceService) CreateWorkspace(ctx context.Context, name, description, ownerID string, settings *models.WorkspaceSettings) (*models.Workspace, error) {
	// Create workspace
	workspace := models.NewWorkspace(name, description, ownerID)
	if settings != nil {
		workspace.Settings = *settings
	}
	
	if err := s.workspaceRepo.Create(ctx, workspace); err != nil {
		return nil, fmt.Errorf("failed to create workspace: %w", err)
	}
	
	// Add owner as a member
	owner := models.NewMember(workspace.ID, ownerID, "", "", models.MemberRoleOwner)
	if err := s.memberRepo.Create(ctx, owner); err != nil {
		return nil, fmt.Errorf("failed to add owner as member: %w", err)
	}
	
	// Invalidate cache
	s.invalidateWorkspaceCache(ctx, workspace.ID)
	s.invalidateUserWorkspacesCache(ctx, ownerID)
	
	return workspace, nil
}

// GetWorkspace retrieves a workspace by ID
func (s *WorkspaceService) GetWorkspace(ctx context.Context, workspaceID, userID string) (*models.Workspace, error) {
	// Check permissions
	if err := s.permissionCheck.CanViewWorkspace(ctx, workspaceID, userID); err != nil {
		return nil, err
	}
	
	// Try to get from cache first
	if workspace := s.getWorkspaceFromCache(ctx, workspaceID); workspace != nil {
		return workspace, nil
	}
	
	workspace, err := s.workspaceRepo.GetByID(ctx, workspaceID)
	if err != nil {
		return nil, err
	}
	
	// Cache the result
	s.cacheWorkspace(ctx, workspace)
	
	return workspace, nil
}

// UpdateWorkspace updates a workspace
func (s *WorkspaceService) UpdateWorkspace(ctx context.Context, workspaceID, userID string, updates map[string]interface{}) (*models.Workspace, error) {
	// Check permissions
	if err := s.permissionCheck.CanManageWorkspace(ctx, workspaceID, userID); err != nil {
		return nil, err
	}
	
	// Get current workspace
	workspace, err := s.workspaceRepo.GetByID(ctx, workspaceID)
	if err != nil {
		return nil, err
	}
	
	// Apply updates
	if name, ok := updates["name"]; ok {
		if nameStr, ok := name.(string); ok {
			workspace.Name = nameStr
		}
	}
	
	if description, ok := updates["description"]; ok {
		if descStr, ok := description.(string); ok {
			workspace.Description = descStr
		}
	}
	
	if status, ok := updates["status"]; ok {
		if statusVal, ok := status.(models.WorkspaceStatus); ok {
			workspace.Status = statusVal
		}
	}
	
	if err := s.workspaceRepo.Update(ctx, workspace); err != nil {
		return nil, fmt.Errorf("failed to update workspace: %w", err)
	}
	
	// Invalidate cache
	s.invalidateWorkspaceCache(ctx, workspaceID)
	
	return workspace, nil
}

// DeleteWorkspace deletes a workspace
func (s *WorkspaceService) DeleteWorkspace(ctx context.Context, workspaceID, userID string) error {
	// Check permissions (only owner can delete)
	member, err := s.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return fmt.Errorf("user is not a member of this workspace")
	}
	
	if member.Role != models.MemberRoleOwner {
		return fmt.Errorf("only workspace owner can delete workspace")
	}
	
	if err := s.workspaceRepo.Delete(ctx, workspaceID); err != nil {
		return fmt.Errorf("failed to delete workspace: %w", err)
	}
	
	// Invalidate cache
	s.invalidateWorkspaceCache(ctx, workspaceID)
	s.invalidateUserWorkspacesCache(ctx, userID)
	
	return nil
}

// ListWorkspaces lists workspaces for a user
func (s *WorkspaceService) ListWorkspaces(ctx context.Context, userID string, status models.WorkspaceStatus, page, pageSize int) ([]*models.Workspace, int, error) {
	// Try to get from cache first
	if workspaces, total := s.getUserWorkspacesFromCache(ctx, userID, status, page, pageSize); workspaces != nil {
		return workspaces, total, nil
	}
	
	workspaces, total, err := s.workspaceRepo.ListByUserID(ctx, userID, status, page, pageSize)
	if err != nil {
		return nil, 0, err
	}
	
	// Cache the result
	s.cacheUserWorkspaces(ctx, userID, status, page, pageSize, workspaces, total)
	
	return workspaces, total, nil
}

// UpdateWorkspaceSettings updates workspace settings
func (s *WorkspaceService) UpdateWorkspaceSettings(ctx context.Context, workspaceID, userID string, settings models.WorkspaceSettings) (*models.WorkspaceSettings, error) {
	// Check permissions
	if err := s.permissionCheck.CanManageWorkspace(ctx, workspaceID, userID); err != nil {
		return nil, err
	}
	
	if err := s.workspaceRepo.UpdateSettings(ctx, workspaceID, settings); err != nil {
		return nil, fmt.Errorf("failed to update settings: %w", err)
	}
	
	// Invalidate cache
	s.invalidateWorkspaceCache(ctx, workspaceID)
	
	return &settings, nil
}

// GetWorkspaceSettings retrieves workspace settings
func (s *WorkspaceService) GetWorkspaceSettings(ctx context.Context, workspaceID, userID string) (*models.WorkspaceSettings, error) {
	// Check permissions
	if err := s.permissionCheck.CanViewWorkspace(ctx, workspaceID, userID); err != nil {
		return nil, err
	}
	
	workspace, err := s.GetWorkspace(ctx, workspaceID, userID)
	if err != nil {
		return nil, err
	}
	
	return &workspace.Settings, nil
}

// Cache methods
func (s *WorkspaceService) cacheWorkspace(ctx context.Context, workspace *models.Workspace) {
	if s.redisClient == nil {
		return
	}
	
	key := fmt.Sprintf("workspace:%s", workspace.ID)
	s.redisClient.Set(ctx, key, workspace, 10*time.Minute)
}

func (s *WorkspaceService) getWorkspaceFromCache(ctx context.Context, workspaceID string) *models.Workspace {
	if s.redisClient == nil {
		return nil
	}
	
	key := fmt.Sprintf("workspace:%s", workspaceID)
	val, err := s.redisClient.Get(ctx, key).Result()
	if err != nil {
		return nil
	}
	
	var workspace models.Workspace
	// Note: In production, you'd use proper JSON serialization
	_ = val // Placeholder for proper deserialization
	
	return &workspace
}

func (s *WorkspaceService) invalidateWorkspaceCache(ctx context.Context, workspaceID string) {
	if s.redisClient == nil {
		return
	}
	
	key := fmt.Sprintf("workspace:%s", workspaceID)
	s.redisClient.Del(ctx, key)
}

func (s *WorkspaceService) cacheUserWorkspaces(ctx context.Context, userID string, status models.WorkspaceStatus, page, pageSize int, workspaces []*models.Workspace, total int) {
	if s.redisClient == nil {
		return
	}
	
	key := fmt.Sprintf("user_workspaces:%s:%s:%d:%d", userID, status, page, pageSize)
	// Note: In production, you'd use proper JSON serialization
	s.redisClient.Set(ctx, key, fmt.Sprintf("%d", total), 5*time.Minute)
}

func (s *WorkspaceService) getUserWorkspacesFromCache(ctx context.Context, userID string, status models.WorkspaceStatus, page, pageSize int) ([]*models.Workspace, int) {
	if s.redisClient == nil {
		return nil, 0
	}
	
	// Note: Simplified implementation - in production you'd cache the actual data
	return nil, 0
}

func (s *WorkspaceService) invalidateUserWorkspacesCache(ctx context.Context, userID string) {
	if s.redisClient == nil {
		return
	}
	
	pattern := fmt.Sprintf("user_workspaces:%s:*", userID)
	keys, err := s.redisClient.Keys(ctx, pattern).Result()
	if err != nil {
		return
	}
	
	if len(keys) > 0 {
		s.redisClient.Del(ctx, keys...)
	}
}