package permissions

import (
	"context"
	"fmt"

	"github.com/pyairtable/workspace-service/internal/models"
	"github.com/pyairtable/workspace-service/internal/repository"
)

// PermissionChecker handles permission checks and validation
type PermissionChecker struct {
	memberRepo     *repository.MemberRepository
	permissionRepo *repository.PermissionRepository
}

// NewPermissionChecker creates a new permission checker
func NewPermissionChecker(memberRepo *repository.MemberRepository, permissionRepo *repository.PermissionRepository) *PermissionChecker {
	return &PermissionChecker{
		memberRepo:     memberRepo,
		permissionRepo: permissionRepo,
	}
}

// CanManageWorkspace checks if a user can manage a workspace (admin actions)
func (pc *PermissionChecker) CanManageWorkspace(ctx context.Context, workspaceID, userID string) error {
	member, err := pc.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return fmt.Errorf("user is not a member of this workspace")
	}
	
	if !member.CanManageSettings() {
		return fmt.Errorf("insufficient permissions to manage workspace")
	}
	
	return nil
}

// CanManageMembers checks if a user can manage members
func (pc *PermissionChecker) CanManageMembers(ctx context.Context, workspaceID, userID string) error {
	member, err := pc.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return fmt.Errorf("user is not a member of this workspace")
	}
	
	if !member.CanManageMembers() {
		return fmt.Errorf("insufficient permissions to manage members")
	}
	
	return nil
}

// CanViewWorkspace checks if a user can view workspace details
func (pc *PermissionChecker) CanViewWorkspace(ctx context.Context, workspaceID, userID string) error {
	_, err := pc.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return fmt.Errorf("user is not a member of this workspace")
	}
	
	return nil
}

// CanUpdateMemberRole checks if a user can update another member's role
func (pc *PermissionChecker) CanUpdateMemberRole(ctx context.Context, workspaceID, userID, targetMemberID string, newRole models.MemberRole) error {
	// Check if user can manage members
	if err := pc.CanManageMembers(ctx, workspaceID, userID); err != nil {
		return err
	}
	
	// Get the requester's role
	requester, err := pc.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return fmt.Errorf("requester not found")
	}
	
	// Get the target member
	targetMember, err := pc.memberRepo.GetByID(ctx, targetMemberID)
	if err != nil {
		return fmt.Errorf("target member not found")
	}
	
	// Owners can do anything
	if requester.Role == models.MemberRoleOwner {
		return nil
	}
	
	// Admins cannot modify owners or promote to owner
	if requester.Role == models.MemberRoleAdmin {
		if targetMember.Role == models.MemberRoleOwner {
			return fmt.Errorf("cannot modify workspace owner")
		}
		if newRole == models.MemberRoleOwner {
			return fmt.Errorf("cannot promote to owner role")
		}
		return nil
	}
	
	return fmt.Errorf("insufficient permissions to update member role")
}

// CanRemoveMember checks if a user can remove another member
func (pc *PermissionChecker) CanRemoveMember(ctx context.Context, workspaceID, userID, targetMemberID string) error {
	// Check if user can manage members
	if err := pc.CanManageMembers(ctx, workspaceID, userID); err != nil {
		return err
	}
	
	// Get the requester's role
	requester, err := pc.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return fmt.Errorf("requester not found")
	}
	
	// Get the target member
	targetMember, err := pc.memberRepo.GetByID(ctx, targetMemberID)
	if err != nil {
		return fmt.Errorf("target member not found")
	}
	
	// Cannot remove the owner
	if targetMember.Role == models.MemberRoleOwner {
		return fmt.Errorf("cannot remove workspace owner")
	}
	
	// Owners can remove anyone (except other owners, handled above)
	if requester.Role == models.MemberRoleOwner {
		return nil
	}
	
	// Admins can remove editors and viewers, but not other admins
	if requester.Role == models.MemberRoleAdmin {
		if targetMember.Role == models.MemberRoleAdmin {
			return fmt.Errorf("cannot remove another admin")
		}
		return nil
	}
	
	return fmt.Errorf("insufficient permissions to remove member")
}

// CanGrantPermission checks if a user can grant permissions
func (pc *PermissionChecker) CanGrantPermission(ctx context.Context, workspaceID, userID string, permission models.Permission) error {
	member, err := pc.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return fmt.Errorf("user is not a member of this workspace")
	}
	
	// Only owners and admins can grant permissions
	if member.Role != models.MemberRoleOwner && member.Role != models.MemberRoleAdmin {
		return fmt.Errorf("insufficient permissions to grant permissions")
	}
	
	// Only owners can grant admin permissions
	if permission == models.PermissionAdmin && member.Role != models.MemberRoleOwner {
		return fmt.Errorf("only owners can grant admin permissions")
	}
	
	return nil
}

// CanRevokePermission checks if a user can revoke permissions
func (pc *PermissionChecker) CanRevokePermission(ctx context.Context, workspaceID, userID string, permission models.Permission) error {
	return pc.CanGrantPermission(ctx, workspaceID, userID, permission)
}

// HasPermission checks if a user has a specific permission on a resource
func (pc *PermissionChecker) HasPermission(ctx context.Context, workspaceID, userID, resourceType, resourceID string, permission models.Permission) (bool, error) {
	// Check if user is a member of the workspace
	member, err := pc.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return false, nil // User is not a member
	}
	
	// Owners have all permissions
	if member.Role == models.MemberRoleOwner {
		return true, nil
	}
	
	// Check explicit permission grants
	hasExplicit, err := pc.permissionRepo.CheckPermission(ctx, workspaceID, userID, resourceType, resourceID, permission)
	if err != nil {
		return false, err
	}
	
	if hasExplicit {
		return true, nil
	}
	
	// Check role-based permissions
	return pc.checkRoleBasedPermission(member.Role, permission), nil
}

// checkRoleBasedPermission checks if a role inherently has a permission
func (pc *PermissionChecker) checkRoleBasedPermission(role models.MemberRole, permission models.Permission) bool {
	switch role {
	case models.MemberRoleOwner:
		return true // Owners have all permissions
	case models.MemberRoleAdmin:
		return permission != models.PermissionAdmin // Admins have all except admin permission
	case models.MemberRoleEditor:
		return permission == models.PermissionRead || permission == models.PermissionWrite
	case models.MemberRoleViewer:
		return permission == models.PermissionRead
	default:
		return false
	}
}

// GetEffectivePermissions returns all effective permissions for a user on a resource
func (pc *PermissionChecker) GetEffectivePermissions(ctx context.Context, workspaceID, userID, resourceType, resourceID string) ([]models.Permission, error) {
	// Check if user is a member
	member, err := pc.memberRepo.GetByWorkspaceAndUser(ctx, workspaceID, userID)
	if err != nil {
		return nil, err
	}
	
	var permissions []models.Permission
	
	// Get explicit permissions
	explicitPerms, err := pc.permissionRepo.GetUserPermissions(ctx, workspaceID, userID, resourceType, resourceID)
	if err != nil {
		return nil, err
	}
	
	permissions = append(permissions, explicitPerms...)
	
	// Add role-based permissions
	rolePerms := pc.getRoleBasedPermissions(member.Role)
	
	// Merge and deduplicate
	permissionSet := make(map[models.Permission]bool)
	for _, perm := range permissions {
		permissionSet[perm] = true
	}
	for _, perm := range rolePerms {
		permissionSet[perm] = true
	}
	
	var result []models.Permission
	for perm := range permissionSet {
		result = append(result, perm)
	}
	
	return result, nil
}

// getRoleBasedPermissions returns the default permissions for a role
func (pc *PermissionChecker) getRoleBasedPermissions(role models.MemberRole) []models.Permission {
	switch role {
	case models.MemberRoleOwner:
		return []models.Permission{
			models.PermissionRead,
			models.PermissionWrite,
			models.PermissionDelete,
			models.PermissionManageMembers,
			models.PermissionManageSettings,
			models.PermissionAdmin,
		}
	case models.MemberRoleAdmin:
		return []models.Permission{
			models.PermissionRead,
			models.PermissionWrite,
			models.PermissionDelete,
			models.PermissionManageMembers,
			models.PermissionManageSettings,
		}
	case models.MemberRoleEditor:
		return []models.Permission{
			models.PermissionRead,
			models.PermissionWrite,
		}
	case models.MemberRoleViewer:
		return []models.Permission{
			models.PermissionRead,
		}
	default:
		return []models.Permission{}
	}
}