package service

import (
	"context"
	"fmt"

	"github.com/pyairtable/workspace-service/internal/models"
	"github.com/pyairtable/workspace-service/internal/permissions"
	"github.com/pyairtable/workspace-service/internal/repository"
	"github.com/redis/go-redis/v9"
)

// PermissionService handles business logic for permissions
type PermissionService struct {
	permissionRepo  *repository.PermissionRepository
	permissionCheck *permissions.PermissionChecker
	redisClient     *redis.Client
}

// NewPermissionService creates a new permission service
func NewPermissionService(
	permissionRepo *repository.PermissionRepository,
	permissionCheck *permissions.PermissionChecker,
	redisClient *redis.Client,
) *PermissionService {
	return &PermissionService{
		permissionRepo:  permissionRepo,
		permissionCheck: permissionCheck,
		redisClient:     redisClient,
	}
}

// CheckPermission checks if a user has a specific permission
func (s *PermissionService) CheckPermission(ctx context.Context, workspaceID, userID, resourceType, resourceID string, permission models.Permission) (bool, error) {
	return s.permissionCheck.HasPermission(ctx, workspaceID, userID, resourceType, resourceID, permission)
}

// GrantPermission grants a permission to a user
func (s *PermissionService) GrantPermission(ctx context.Context, workspaceID, grantedBy, userID, resourceType, resourceID string, permission models.Permission) (*models.PermissionGrant, error) {
	// Check if the grantor has permission to grant this permission
	if err := s.permissionCheck.CanGrantPermission(ctx, workspaceID, grantedBy, permission); err != nil {
		return nil, err
	}
	
	// Create permission grant
	grant := models.NewPermissionGrant(workspaceID, userID, resourceType, resourceID, permission, grantedBy)
	
	if err := s.permissionRepo.Grant(ctx, grant); err != nil {
		return nil, fmt.Errorf("failed to grant permission: %w", err)
	}
	
	// Invalidate permission cache
	s.invalidatePermissionCache(ctx, workspaceID, userID, resourceType, resourceID)
	
	return grant, nil
}

// RevokePermission revokes a permission from a user
func (s *PermissionService) RevokePermission(ctx context.Context, workspaceID, revokedBy, userID, resourceType, resourceID string, permission models.Permission) error {
	// Check if the revoker has permission to revoke this permission
	if err := s.permissionCheck.CanRevokePermission(ctx, workspaceID, revokedBy, permission); err != nil {
		return err
	}
	
	if err := s.permissionRepo.Revoke(ctx, workspaceID, userID, resourceType, resourceID, permission); err != nil {
		return fmt.Errorf("failed to revoke permission: %w", err)
	}
	
	// Invalidate permission cache
	s.invalidatePermissionCache(ctx, workspaceID, userID, resourceType, resourceID)
	
	return nil
}

// ListPermissions lists permissions for a workspace
func (s *PermissionService) ListPermissions(ctx context.Context, workspaceID, userID string, filters map[string]interface{}) ([]*models.PermissionGrant, error) {
	// Check if user can view permissions (members can view, but only admins+ can see all)
	if err := s.permissionCheck.CanViewWorkspace(ctx, workspaceID, userID); err != nil {
		return nil, err
	}
	
	// If not admin, filter to only show user's own permissions
	canManageMembers := s.permissionCheck.CanManageMembers(ctx, workspaceID, userID) == nil
	if !canManageMembers {
		filters["user_id"] = userID
	}
	
	permissions, err := s.permissionRepo.ListByWorkspace(ctx, workspaceID, filters)
	if err != nil {
		return nil, err
	}
	
	return permissions, nil
}

// ListUserPermissions lists all permissions for a specific user
func (s *PermissionService) ListUserPermissions(ctx context.Context, workspaceID, requestingUserID, targetUserID string) ([]*models.PermissionGrant, error) {
	// Check permissions - user can view their own permissions, admins+ can view others
	if requestingUserID != targetUserID {
		if err := s.permissionCheck.CanManageMembers(ctx, workspaceID, requestingUserID); err != nil {
			return nil, fmt.Errorf("insufficient permissions to view user permissions")
		}
	} else {
		if err := s.permissionCheck.CanViewWorkspace(ctx, workspaceID, requestingUserID); err != nil {
			return nil, err
		}
	}
	
	permissions, err := s.permissionRepo.ListByUser(ctx, workspaceID, targetUserID)
	if err != nil {
		return nil, err
	}
	
	return permissions, nil
}

// ListResourcePermissions lists all permissions for a specific resource
func (s *PermissionService) ListResourcePermissions(ctx context.Context, workspaceID, userID, resourceType, resourceID string, targetUserID string) ([]*models.PermissionGrant, error) {
	// Check permissions
	if err := s.permissionCheck.CanViewWorkspace(ctx, workspaceID, userID); err != nil {
		return nil, err
	}
	
	permissions, err := s.permissionRepo.ListByResource(ctx, workspaceID, resourceType, resourceID, targetUserID)
	if err != nil {
		return nil, err
	}
	
	return permissions, nil
}

// GetEffectivePermissions gets all effective permissions for a user on a resource
func (s *PermissionService) GetEffectivePermissions(ctx context.Context, workspaceID, requestingUserID, targetUserID, resourceType, resourceID string) ([]models.Permission, error) {
	// Check permissions - user can view their own permissions, admins+ can view others
	if requestingUserID != targetUserID {
		if err := s.permissionCheck.CanManageMembers(ctx, workspaceID, requestingUserID); err != nil {
			return nil, fmt.Errorf("insufficient permissions to view user permissions")
		}
	} else {
		if err := s.permissionCheck.CanViewWorkspace(ctx, workspaceID, requestingUserID); err != nil {
			return nil, err
		}
	}
	
	permissions, err := s.permissionCheck.GetEffectivePermissions(ctx, workspaceID, targetUserID, resourceType, resourceID)
	if err != nil {
		return nil, err
	}
	
	return permissions, nil
}

// RevokeAllUserPermissions revokes all permissions for a user in a workspace
func (s *PermissionService) RevokeAllUserPermissions(ctx context.Context, workspaceID, revokedBy, targetUserID string) error {
	// Check permissions
	if err := s.permissionCheck.CanManageMembers(ctx, workspaceID, revokedBy); err != nil {
		return err
	}
	
	if err := s.permissionRepo.RevokeAllForUser(ctx, workspaceID, targetUserID); err != nil {
		return fmt.Errorf("failed to revoke all permissions: %w", err)
	}
	
	// Invalidate permission cache for this user
	s.invalidateUserPermissionCache(ctx, workspaceID, targetUserID)
	
	return nil
}

// RevokeAllResourcePermissions revokes all permissions for a specific resource
func (s *PermissionService) RevokeAllResourcePermissions(ctx context.Context, workspaceID, revokedBy, resourceType, resourceID string) error {
	// Check permissions
	if err := s.permissionCheck.CanManageMembers(ctx, workspaceID, revokedBy); err != nil {
		return err
	}
	
	if err := s.permissionRepo.RevokeAllForResource(ctx, workspaceID, resourceType, resourceID); err != nil {
		return fmt.Errorf("failed to revoke resource permissions: %w", err)
	}
	
	// Invalidate permission cache for this resource
	s.invalidateResourcePermissionCache(ctx, workspaceID, resourceType, resourceID)
	
	return nil
}

// BulkGrantPermissions grants multiple permissions at once
func (s *PermissionService) BulkGrantPermissions(ctx context.Context, workspaceID, grantedBy string, grants []models.PermissionGrant) error {
	// Check permissions for each grant
	for _, grant := range grants {
		if err := s.permissionCheck.CanGrantPermission(ctx, workspaceID, grantedBy, grant.Permission); err != nil {
			return fmt.Errorf("insufficient permissions to grant %s: %w", grant.Permission, err)
		}
	}
	
	// Grant all permissions
	for _, grant := range grants {
		grant.GrantedBy = grantedBy
		if err := s.permissionRepo.Grant(ctx, &grant); err != nil {
			return fmt.Errorf("failed to grant permission %s to user %s: %w", grant.Permission, grant.UserID, err)
		}
		
		// Invalidate cache for each grant
		s.invalidatePermissionCache(ctx, workspaceID, grant.UserID, grant.ResourceType, grant.ResourceID)
	}
	
	return nil
}

// Cache methods
func (s *PermissionService) invalidatePermissionCache(ctx context.Context, workspaceID, userID, resourceType, resourceID string) {
	if s.redisClient == nil {
		return
	}
	
	// Invalidate specific permission cache
	key := fmt.Sprintf("permission:%s:%s:%s:%s", workspaceID, userID, resourceType, resourceID)
	s.redisClient.Del(ctx, key)
	
	// Invalidate user permission cache
	s.invalidateUserPermissionCache(ctx, workspaceID, userID)
}

func (s *PermissionService) invalidateUserPermissionCache(ctx context.Context, workspaceID, userID string) {
	if s.redisClient == nil {
		return
	}
	
	pattern := fmt.Sprintf("user_permissions:%s:%s:*", workspaceID, userID)
	keys, err := s.redisClient.Keys(ctx, pattern).Result()
	if err != nil {
		return
	}
	
	if len(keys) > 0 {
		s.redisClient.Del(ctx, keys...)
	}
}

func (s *PermissionService) invalidateResourcePermissionCache(ctx context.Context, workspaceID, resourceType, resourceID string) {
	if s.redisClient == nil {
		return
	}
	
	pattern := fmt.Sprintf("resource_permissions:%s:%s:%s:*", workspaceID, resourceType, resourceID)
	keys, err := s.redisClient.Keys(ctx, pattern).Result()
	if err != nil {
		return
	}
	
	if len(keys) > 0 {
		s.redisClient.Del(ctx, keys...)
	}
}