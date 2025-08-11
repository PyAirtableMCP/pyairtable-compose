package handlers

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/pyairtable/workspace-service/internal/models"
	"github.com/pyairtable/workspace-service/internal/service"
	pb "github.com/pyairtable/workspace-service/proto"
)

// WorkspaceHandler implements the gRPC WorkspaceService
type WorkspaceHandler struct {
	pb.UnimplementedWorkspaceServiceServer
	workspaceService  *service.WorkspaceService
	memberService     *service.MemberService
	permissionService *service.PermissionService
}

// NewWorkspaceHandler creates a new workspace handler
func NewWorkspaceHandler(
	workspaceService *service.WorkspaceService,
	memberService *service.MemberService,
	permissionService *service.PermissionService,
) *WorkspaceHandler {
	return &WorkspaceHandler{
		workspaceService:  workspaceService,
		memberService:     memberService,
		permissionService: permissionService,
	}
}

// CreateWorkspace creates a new workspace
func (h *WorkspaceHandler) CreateWorkspace(ctx context.Context, req *pb.CreateWorkspaceRequest) (*pb.CreateWorkspaceResponse, error) {
	if req.Name == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace name is required")
	}
	
	if req.OwnerId == "" {
		return nil, status.Error(codes.InvalidArgument, "owner ID is required")
	}
	
	var settings *models.WorkspaceSettings
	if req.Settings != nil {
		settings = &models.WorkspaceSettings{
			AllowExternalSharing: req.Settings.AllowExternalSharing,
			RequireTwoFactor:     req.Settings.RequireTwoFactor,
			MaxMembers:           int(req.Settings.MaxMembers),
			Timezone:             req.Settings.Timezone,
			AutoArchiveInactive:  req.Settings.AutoArchiveInactive,
			ArchiveAfterDays:     int(req.Settings.ArchiveAfterDays),
			CustomSettings:       req.Settings.CustomSettings,
		}
	}
	
	workspace, err := h.workspaceService.CreateWorkspace(ctx, req.Name, req.Description, req.OwnerId, settings)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.CreateWorkspaceResponse{
		Workspace: h.workspaceToProto(workspace),
	}, nil
}

// GetWorkspace retrieves a workspace by ID
func (h *WorkspaceHandler) GetWorkspace(ctx context.Context, req *pb.GetWorkspaceRequest) (*pb.GetWorkspaceResponse, error) {
	if req.Id == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	workspace, err := h.workspaceService.GetWorkspace(ctx, req.Id, req.UserId)
	if err != nil {
		return nil, status.Error(codes.NotFound, err.Error())
	}
	
	return &pb.GetWorkspaceResponse{
		Workspace: h.workspaceToProto(workspace),
	}, nil
}

// UpdateWorkspace updates a workspace
func (h *WorkspaceHandler) UpdateWorkspace(ctx context.Context, req *pb.UpdateWorkspaceRequest) (*pb.UpdateWorkspaceResponse, error) {
	if req.Id == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	updates := make(map[string]interface{})
	
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	
	if req.Description != nil {
		updates["description"] = *req.Description
	}
	
	if req.Status != nil {
		updates["status"] = h.protoToWorkspaceStatus(*req.Status)
	}
	
	workspace, err := h.workspaceService.UpdateWorkspace(ctx, req.Id, req.UserId, updates)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.UpdateWorkspaceResponse{
		Workspace: h.workspaceToProto(workspace),
	}, nil
}

// DeleteWorkspace deletes a workspace
func (h *WorkspaceHandler) DeleteWorkspace(ctx context.Context, req *pb.DeleteWorkspaceRequest) (*pb.DeleteWorkspaceResponse, error) {
	if req.Id == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	err := h.workspaceService.DeleteWorkspace(ctx, req.Id, req.UserId)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.DeleteWorkspaceResponse{
		Success: true,
	}, nil
}

// ListWorkspaces lists workspaces for a user
func (h *WorkspaceHandler) ListWorkspaces(ctx context.Context, req *pb.ListWorkspacesRequest) (*pb.ListWorkspacesResponse, error) {
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	page := req.Page
	if page <= 0 {
		page = 1
	}
	
	pageSize := req.PageSize
	if pageSize <= 0 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	
	status := h.protoToWorkspaceStatus(req.Status)
	
	workspaces, total, err := h.workspaceService.ListWorkspaces(ctx, req.UserId, status, int(page), int(pageSize))
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	protoWorkspaces := make([]*pb.Workspace, len(workspaces))
	for i, w := range workspaces {
		protoWorkspaces[i] = h.workspaceToProto(w)
	}
	
	return &pb.ListWorkspacesResponse{
		Workspaces:  protoWorkspaces,
		TotalCount:  int32(total),
		Page:        page,
		PageSize:    pageSize,
	}, nil
}

// UpdateSettings updates workspace settings
func (h *WorkspaceHandler) UpdateSettings(ctx context.Context, req *pb.UpdateSettingsRequest) (*pb.UpdateSettingsResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	if req.Settings == nil {
		return nil, status.Error(codes.InvalidArgument, "settings are required")
	}
	
	settings := models.WorkspaceSettings{
		AllowExternalSharing: req.Settings.AllowExternalSharing,
		RequireTwoFactor:     req.Settings.RequireTwoFactor,
		MaxMembers:           int(req.Settings.MaxMembers),
		Timezone:             req.Settings.Timezone,
		AutoArchiveInactive:  req.Settings.AutoArchiveInactive,
		ArchiveAfterDays:     int(req.Settings.ArchiveAfterDays),
		CustomSettings:       req.Settings.CustomSettings,
	}
	
	updatedSettings, err := h.workspaceService.UpdateWorkspaceSettings(ctx, req.WorkspaceId, req.UserId, settings)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.UpdateSettingsResponse{
		Settings: h.settingsToProto(updatedSettings),
	}, nil
}

// GetSettings retrieves workspace settings
func (h *WorkspaceHandler) GetSettings(ctx context.Context, req *pb.GetSettingsRequest) (*pb.GetSettingsResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	settings, err := h.workspaceService.GetWorkspaceSettings(ctx, req.WorkspaceId, req.UserId)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.GetSettingsResponse{
		Settings: h.settingsToProto(settings),
	}, nil
}

// Helper methods
func (h *WorkspaceHandler) workspaceToProto(w *models.Workspace) *pb.Workspace {
	return &pb.Workspace{
		Id:          w.ID,
		Name:        w.Name,
		Description: w.Description,
		OwnerId:     w.OwnerID,
		Status:      h.workspaceStatusToProto(w.Status),
		Settings:    h.settingsToProto(&w.Settings),
		CreatedAt:   timestamppb.New(w.CreatedAt),
		UpdatedAt:   timestamppb.New(w.UpdatedAt),
		MemberCount: int32(w.MemberCount),
	}
}

func (h *WorkspaceHandler) settingsToProto(s *models.WorkspaceSettings) *pb.WorkspaceSettings {
	return &pb.WorkspaceSettings{
		AllowExternalSharing: s.AllowExternalSharing,
		RequireTwoFactor:     s.RequireTwoFactor,
		MaxMembers:           int32(s.MaxMembers),
		Timezone:             s.Timezone,
		AutoArchiveInactive:  s.AutoArchiveInactive,
		ArchiveAfterDays:     int32(s.ArchiveAfterDays),
		CustomSettings:       s.CustomSettings,
	}
}

func (h *WorkspaceHandler) workspaceStatusToProto(status models.WorkspaceStatus) pb.WorkspaceStatus {
	switch status {
	case models.WorkspaceStatusActive:
		return pb.WorkspaceStatus_WORKSPACE_STATUS_ACTIVE
	case models.WorkspaceStatusSuspended:
		return pb.WorkspaceStatus_WORKSPACE_STATUS_SUSPENDED
	case models.WorkspaceStatusArchived:
		return pb.WorkspaceStatus_WORKSPACE_STATUS_ARCHIVED
	default:
		return pb.WorkspaceStatus_WORKSPACE_STATUS_UNSPECIFIED
	}
}

func (h *WorkspaceHandler) protoToWorkspaceStatus(status pb.WorkspaceStatus) models.WorkspaceStatus {
	switch status {
	case pb.WorkspaceStatus_WORKSPACE_STATUS_ACTIVE:
		return models.WorkspaceStatusActive
	case pb.WorkspaceStatus_WORKSPACE_STATUS_SUSPENDED:
		return models.WorkspaceStatusSuspended
	case pb.WorkspaceStatus_WORKSPACE_STATUS_ARCHIVED:
		return models.WorkspaceStatusArchived
	default:
		return ""
	}
}