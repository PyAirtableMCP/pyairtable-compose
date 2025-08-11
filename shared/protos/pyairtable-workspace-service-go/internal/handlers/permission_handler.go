package handlers

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/pyairtable/workspace-service/internal/models"
	pb "github.com/pyairtable/workspace-service/proto"
)

// CheckPermission checks if a user has a specific permission
func (h *WorkspaceHandler) CheckPermission(ctx context.Context, req *pb.CheckPermissionRequest) (*pb.CheckPermissionResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	if req.ResourceType == "" {
		return nil, status.Error(codes.InvalidArgument, "resource type is required")
	}
	
	if req.ResourceId == "" {
		return nil, status.Error(codes.InvalidArgument, "resource ID is required")
	}
	
	permission := h.protoToPermission(req.Permission)
	if permission == "" {
		return nil, status.Error(codes.InvalidArgument, "invalid permission")
	}
	
	hasPermission, err := h.permissionService.CheckPermission(ctx, req.WorkspaceId, req.UserId, req.ResourceType, req.ResourceId, permission)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.CheckPermissionResponse{
		HasPermission: hasPermission,
	}, nil
}

// GrantPermission grants a permission to a user
func (h *WorkspaceHandler) GrantPermission(ctx context.Context, req *pb.GrantPermissionRequest) (*pb.GrantPermissionResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.GrantedBy == "" {
		return nil, status.Error(codes.InvalidArgument, "granted by user ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	if req.ResourceType == "" {
		return nil, status.Error(codes.InvalidArgument, "resource type is required")
	}
	
	if req.ResourceId == "" {
		return nil, status.Error(codes.InvalidArgument, "resource ID is required")
	}
	
	permission := h.protoToPermission(req.Permission)
	if permission == "" {
		return nil, status.Error(codes.InvalidArgument, "invalid permission")
	}
	
	grant, err := h.permissionService.GrantPermission(ctx, req.WorkspaceId, req.GrantedBy, req.UserId, req.ResourceType, req.ResourceId, permission)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.GrantPermissionResponse{
		PermissionGrant: h.permissionGrantToProto(grant),
	}, nil
}

// RevokePermission revokes a permission from a user
func (h *WorkspaceHandler) RevokePermission(ctx context.Context, req *pb.RevokePermissionRequest) (*pb.RevokePermissionResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.RevokedBy == "" {
		return nil, status.Error(codes.InvalidArgument, "revoked by user ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	if req.ResourceType == "" {
		return nil, status.Error(codes.InvalidArgument, "resource type is required")
	}
	
	if req.ResourceId == "" {
		return nil, status.Error(codes.InvalidArgument, "resource ID is required")
	}
	
	permission := h.protoToPermission(req.Permission)
	if permission == "" {
		return nil, status.Error(codes.InvalidArgument, "invalid permission")
	}
	
	err := h.permissionService.RevokePermission(ctx, req.WorkspaceId, req.RevokedBy, req.UserId, req.ResourceType, req.ResourceId, permission)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.RevokePermissionResponse{
		Success: true,
	}, nil
}

// ListPermissions lists permissions for a workspace
func (h *WorkspaceHandler) ListPermissions(ctx context.Context, req *pb.ListPermissionsRequest) (*pb.ListPermissionsResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	filters := make(map[string]interface{})
	
	if req.TargetUserId != nil && *req.TargetUserId != "" {
		filters["user_id"] = *req.TargetUserId
	}
	
	if req.ResourceType != "" {
		filters["resource_type"] = req.ResourceType
	}
	
	if req.ResourceId != "" {
		filters["resource_id"] = req.ResourceId
	}
	
	permissions, err := h.permissionService.ListPermissions(ctx, req.WorkspaceId, req.UserId, filters)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	protoPermissions := make([]*pb.PermissionGrant, len(permissions))
	for i, p := range permissions {
		protoPermissions[i] = h.permissionGrantToProto(p)
	}
	
	return &pb.ListPermissionsResponse{
		Permissions: protoPermissions,
	}, nil
}

// Helper methods for permission handling
func (h *WorkspaceHandler) permissionGrantToProto(p *models.PermissionGrant) *pb.PermissionGrant {
	return &pb.PermissionGrant{
		Id:           p.ID,
		WorkspaceId:  p.WorkspaceID,
		UserId:       p.UserID,
		ResourceType: p.ResourceType,
		ResourceId:   p.ResourceID,
		Permission:   h.permissionToProto(p.Permission),
		GrantedAt:    timestamppb.New(p.GrantedAt),
		GrantedBy:    p.GrantedBy,
	}
}

func (h *WorkspaceHandler) permissionToProto(permission models.Permission) pb.Permission {
	switch permission {
	case models.PermissionRead:
		return pb.Permission_PERMISSION_READ
	case models.PermissionWrite:
		return pb.Permission_PERMISSION_WRITE
	case models.PermissionDelete:
		return pb.Permission_PERMISSION_DELETE
	case models.PermissionManageMembers:
		return pb.Permission_PERMISSION_MANAGE_MEMBERS
	case models.PermissionManageSettings:
		return pb.Permission_PERMISSION_MANAGE_SETTINGS
	case models.PermissionAdmin:
		return pb.Permission_PERMISSION_ADMIN
	default:
		return pb.Permission_PERMISSION_UNSPECIFIED
	}
}

func (h *WorkspaceHandler) protoToPermission(permission pb.Permission) models.Permission {
	switch permission {
	case pb.Permission_PERMISSION_READ:
		return models.PermissionRead
	case pb.Permission_PERMISSION_WRITE:
		return models.PermissionWrite
	case pb.Permission_PERMISSION_DELETE:
		return models.PermissionDelete
	case pb.Permission_PERMISSION_MANAGE_MEMBERS:
		return models.PermissionManageMembers
	case pb.Permission_PERMISSION_MANAGE_SETTINGS:
		return models.PermissionManageSettings
	case pb.Permission_PERMISSION_ADMIN:
		return models.PermissionAdmin
	default:
		return ""
	}
}