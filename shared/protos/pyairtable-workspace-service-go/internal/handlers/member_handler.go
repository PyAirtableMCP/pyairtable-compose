package handlers

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/pyairtable/workspace-service/internal/models"
	pb "github.com/pyairtable/workspace-service/proto"
)

// InviteMember invites a member to the workspace
func (h *WorkspaceHandler) InviteMember(ctx context.Context, req *pb.InviteMemberRequest) (*pb.InviteMemberResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.InvitedBy == "" {
		return nil, status.Error(codes.InvalidArgument, "invited by user ID is required")
	}
	
	if req.Email == "" {
		return nil, status.Error(codes.InvalidArgument, "email is required")
	}
	
	role := h.protoToMemberRole(req.Role)
	if role == "" {
		return nil, status.Error(codes.InvalidArgument, "invalid role")
	}
	
	invitation, err := h.memberService.InviteMember(ctx, req.WorkspaceId, req.InvitedBy, req.Email, role, req.Message)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.InviteMemberResponse{
		Invitation: h.invitationToProto(invitation),
	}, nil
}

// AcceptInvitation accepts a workspace invitation
func (h *WorkspaceHandler) AcceptInvitation(ctx context.Context, req *pb.AcceptInvitationRequest) (*pb.AcceptInvitationResponse, error) {
	if req.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "invitation token is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	member, err := h.memberService.AcceptInvitation(ctx, req.Token, req.UserId)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.AcceptInvitationResponse{
		Member: h.memberToProto(member),
	}, nil
}

// DeclineInvitation declines a workspace invitation
func (h *WorkspaceHandler) DeclineInvitation(ctx context.Context, req *pb.DeclineInvitationRequest) (*pb.DeclineInvitationResponse, error) {
	if req.Token == "" {
		return nil, status.Error(codes.InvalidArgument, "invitation token is required")
	}
	
	err := h.memberService.DeclineInvitation(ctx, req.Token)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.DeclineInvitationResponse{
		Success: true,
	}, nil
}

// RemoveMember removes a member from the workspace
func (h *WorkspaceHandler) RemoveMember(ctx context.Context, req *pb.RemoveMemberRequest) (*pb.RemoveMemberResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	if req.MemberId == "" {
		return nil, status.Error(codes.InvalidArgument, "member ID is required")
	}
	
	err := h.memberService.RemoveMember(ctx, req.WorkspaceId, req.UserId, req.MemberId)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.RemoveMemberResponse{
		Success: true,
	}, nil
}

// UpdateMemberRole updates a member's role
func (h *WorkspaceHandler) UpdateMemberRole(ctx context.Context, req *pb.UpdateMemberRoleRequest) (*pb.UpdateMemberRoleResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
	if req.UserId == "" {
		return nil, status.Error(codes.InvalidArgument, "user ID is required")
	}
	
	if req.MemberId == "" {
		return nil, status.Error(codes.InvalidArgument, "member ID is required")
	}
	
	newRole := h.protoToMemberRole(req.NewRole)
	if newRole == "" {
		return nil, status.Error(codes.InvalidArgument, "invalid role")
	}
	
	member, err := h.memberService.UpdateMemberRole(ctx, req.WorkspaceId, req.UserId, req.MemberId, newRole)
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	return &pb.UpdateMemberRoleResponse{
		Member: h.memberToProto(member),
	}, nil
}

// ListMembers lists members of a workspace
func (h *WorkspaceHandler) ListMembers(ctx context.Context, req *pb.ListMembersRequest) (*pb.ListMembersResponse, error) {
	if req.WorkspaceId == "" {
		return nil, status.Error(codes.InvalidArgument, "workspace ID is required")
	}
	
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
	
	roleFilter := h.protoToMemberRole(req.RoleFilter)
	
	members, total, err := h.memberService.ListMembers(ctx, req.WorkspaceId, req.UserId, roleFilter, int(page), int(pageSize))
	if err != nil {
		return nil, status.Error(codes.Internal, err.Error())
	}
	
	protoMembers := make([]*pb.Member, len(members))
	for i, m := range members {
		protoMembers[i] = h.memberToProto(m)
	}
	
	return &pb.ListMembersResponse{
		Members:    protoMembers,
		TotalCount: int32(total),
		Page:       page,
		PageSize:   pageSize,
	}, nil
}

// Helper methods for member handling
func (h *WorkspaceHandler) memberToProto(m *models.Member) *pb.Member {
	return &pb.Member{
		Id:          m.ID,
		WorkspaceId: m.WorkspaceID,
		UserId:      m.UserID,
		Email:       m.Email,
		Name:        m.Name,
		Role:        h.memberRoleToProto(m.Role),
		JoinedAt:    timestamppb.New(m.JoinedAt),
		LastActive:  timestamppb.New(m.LastActive),
		IsActive:    m.IsActive,
	}
}

func (h *WorkspaceHandler) invitationToProto(i *models.Invitation) *pb.Invitation {
	return &pb.Invitation{
		Id:          i.ID,
		WorkspaceId: i.WorkspaceID,
		InvitedBy:   i.InvitedBy,
		Email:       i.Email,
		Role:        h.memberRoleToProto(i.Role),
		Status:      h.invitationStatusToProto(i.Status),
		ExpiresAt:   timestamppb.New(i.ExpiresAt),
		CreatedAt:   timestamppb.New(i.CreatedAt),
		Token:       i.Token,
	}
}

func (h *WorkspaceHandler) memberRoleToProto(role models.MemberRole) pb.MemberRole {
	switch role {
	case models.MemberRoleOwner:
		return pb.MemberRole_MEMBER_ROLE_OWNER
	case models.MemberRoleAdmin:
		return pb.MemberRole_MEMBER_ROLE_ADMIN
	case models.MemberRoleEditor:
		return pb.MemberRole_MEMBER_ROLE_EDITOR
	case models.MemberRoleViewer:
		return pb.MemberRole_MEMBER_ROLE_VIEWER
	default:
		return pb.MemberRole_MEMBER_ROLE_UNSPECIFIED
	}
}

func (h *WorkspaceHandler) protoToMemberRole(role pb.MemberRole) models.MemberRole {
	switch role {
	case pb.MemberRole_MEMBER_ROLE_OWNER:
		return models.MemberRoleOwner
	case pb.MemberRole_MEMBER_ROLE_ADMIN:
		return models.MemberRoleAdmin
	case pb.MemberRole_MEMBER_ROLE_EDITOR:
		return models.MemberRoleEditor
	case pb.MemberRole_MEMBER_ROLE_VIEWER:
		return models.MemberRoleViewer
	default:
		return ""
	}
}

func (h *WorkspaceHandler) invitationStatusToProto(status models.InvitationStatus) pb.InvitationStatus {
	switch status {
	case models.InvitationStatusPending:
		return pb.InvitationStatus_INVITATION_STATUS_PENDING
	case models.InvitationStatusAccepted:
		return pb.InvitationStatus_INVITATION_STATUS_ACCEPTED
	case models.InvitationStatusDeclined:
		return pb.InvitationStatus_INVITATION_STATUS_DECLINED
	case models.InvitationStatusExpired:
		return pb.InvitationStatus_INVITATION_STATUS_EXPIRED
	default:
		return pb.InvitationStatus_INVITATION_STATUS_UNSPECIFIED
	}
}