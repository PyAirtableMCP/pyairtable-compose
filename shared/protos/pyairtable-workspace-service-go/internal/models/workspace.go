package models

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// WorkspaceStatus represents the status of a workspace
type WorkspaceStatus string

const (
	WorkspaceStatusActive    WorkspaceStatus = "active"
	WorkspaceStatusSuspended WorkspaceStatus = "suspended"
	WorkspaceStatusArchived  WorkspaceStatus = "archived"
)

// MemberRole represents the role of a member in a workspace
type MemberRole string

const (
	MemberRoleOwner  MemberRole = "owner"
	MemberRoleAdmin  MemberRole = "admin"
	MemberRoleEditor MemberRole = "editor"
	MemberRoleViewer MemberRole = "viewer"
)

// InvitationStatus represents the status of an invitation
type InvitationStatus string

const (
	InvitationStatusPending  InvitationStatus = "pending"
	InvitationStatusAccepted InvitationStatus = "accepted"
	InvitationStatusDeclined InvitationStatus = "declined"
	InvitationStatusExpired  InvitationStatus = "expired"
)

// Permission represents different permission types
type Permission string

const (
	PermissionRead           Permission = "read"
	PermissionWrite          Permission = "write"
	PermissionDelete         Permission = "delete"
	PermissionManageMembers  Permission = "manage_members"
	PermissionManageSettings Permission = "manage_settings"
	PermissionAdmin          Permission = "admin"
)

// WorkspaceSettings represents workspace configuration
type WorkspaceSettings struct {
	AllowExternalSharing bool              `json:"allow_external_sharing" db:"allow_external_sharing"`
	RequireTwoFactor     bool              `json:"require_two_factor" db:"require_two_factor"`
	MaxMembers           int               `json:"max_members" db:"max_members"`
	Timezone             string            `json:"timezone" db:"timezone"`
	AutoArchiveInactive  bool              `json:"auto_archive_inactive" db:"auto_archive_inactive"`
	ArchiveAfterDays     int               `json:"archive_after_days" db:"archive_after_days"`
	CustomSettings       map[string]string `json:"custom_settings" db:"custom_settings"`
}

// Value implements the driver.Valuer interface for database storage
func (ws WorkspaceSettings) Value() (driver.Value, error) {
	return json.Marshal(ws)
}

// Scan implements the sql.Scanner interface for database retrieval
func (ws *WorkspaceSettings) Scan(value interface{}) error {
	if value == nil {
		return nil
	}
	
	bytes, ok := value.([]byte)
	if !ok {
		return fmt.Errorf("cannot scan %T into WorkspaceSettings", value)
	}
	
	return json.Unmarshal(bytes, ws)
}

// Workspace represents a workspace entity
type Workspace struct {
	ID          string            `json:"id" db:"id"`
	Name        string            `json:"name" db:"name"`
	Description string            `json:"description" db:"description"`
	OwnerID     string            `json:"owner_id" db:"owner_id"`
	Status      WorkspaceStatus   `json:"status" db:"status"`
	Settings    WorkspaceSettings `json:"settings" db:"settings"`
	CreatedAt   time.Time         `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time         `json:"updated_at" db:"updated_at"`
	MemberCount int               `json:"member_count,omitempty"`
}

// NewWorkspace creates a new workspace with default values
func NewWorkspace(name, description, ownerID string) *Workspace {
	now := time.Now()
	return &Workspace{
		ID:          uuid.New().String(),
		Name:        name,
		Description: description,
		OwnerID:     ownerID,
		Status:      WorkspaceStatusActive,
		Settings: WorkspaceSettings{
			AllowExternalSharing: false,
			RequireTwoFactor:     false,
			MaxMembers:          100,
			Timezone:            "UTC",
			AutoArchiveInactive:  false,
			ArchiveAfterDays:     365,
			CustomSettings:       make(map[string]string),
		},
		CreatedAt: now,
		UpdatedAt: now,
	}
}

// Member represents a workspace member
type Member struct {
	ID          string     `json:"id" db:"id"`
	WorkspaceID string     `json:"workspace_id" db:"workspace_id"`
	UserID      string     `json:"user_id" db:"user_id"`
	Email       string     `json:"email" db:"email"`
	Name        string     `json:"name" db:"name"`
	Role        MemberRole `json:"role" db:"role"`
	JoinedAt    time.Time  `json:"joined_at" db:"joined_at"`
	LastActive  time.Time  `json:"last_active" db:"last_active"`
	IsActive    bool       `json:"is_active" db:"is_active"`
}

// NewMember creates a new member
func NewMember(workspaceID, userID, email, name string, role MemberRole) *Member {
	now := time.Now()
	return &Member{
		ID:          uuid.New().String(),
		WorkspaceID: workspaceID,
		UserID:      userID,
		Email:       email,
		Name:        name,
		Role:        role,
		JoinedAt:    now,
		LastActive:  now,
		IsActive:    true,
	}
}

// Invitation represents a workspace invitation
type Invitation struct {
	ID          string           `json:"id" db:"id"`
	WorkspaceID string           `json:"workspace_id" db:"workspace_id"`
	InvitedBy   string           `json:"invited_by" db:"invited_by"`
	Email       string           `json:"email" db:"email"`
	Role        MemberRole       `json:"role" db:"role"`
	Status      InvitationStatus `json:"status" db:"status"`
	Token       string           `json:"token" db:"token"`
	ExpiresAt   time.Time        `json:"expires_at" db:"expires_at"`
	CreatedAt   time.Time        `json:"created_at" db:"created_at"`
}

// NewInvitation creates a new invitation
func NewInvitation(workspaceID, invitedBy, email string, role MemberRole) *Invitation {
	now := time.Now()
	return &Invitation{
		ID:          uuid.New().String(),
		WorkspaceID: workspaceID,
		InvitedBy:   invitedBy,
		Email:       email,
		Role:        role,
		Status:      InvitationStatusPending,
		Token:       uuid.New().String(),
		ExpiresAt:   now.AddDate(0, 0, 7), // 7 days expiration
		CreatedAt:   now,
	}
}

// IsExpired checks if the invitation is expired
func (i *Invitation) IsExpired() bool {
	return time.Now().After(i.ExpiresAt)
}

// PermissionGrant represents a permission grant
type PermissionGrant struct {
	ID           string     `json:"id" db:"id"`
	WorkspaceID  string     `json:"workspace_id" db:"workspace_id"`
	UserID       string     `json:"user_id" db:"user_id"`
	ResourceType string     `json:"resource_type" db:"resource_type"`
	ResourceID   string     `json:"resource_id" db:"resource_id"`
	Permission   Permission `json:"permission" db:"permission"`
	GrantedAt    time.Time  `json:"granted_at" db:"granted_at"`
	GrantedBy    string     `json:"granted_by" db:"granted_by"`
}

// NewPermissionGrant creates a new permission grant
func NewPermissionGrant(workspaceID, userID, resourceType, resourceID string, permission Permission, grantedBy string) *PermissionGrant {
	return &PermissionGrant{
		ID:           uuid.New().String(),
		WorkspaceID:  workspaceID,
		UserID:       userID,
		ResourceType: resourceType,
		ResourceID:   resourceID,
		Permission:   permission,
		GrantedAt:    time.Now(),
		GrantedBy:    grantedBy,
	}
}

// HasRole checks if a member has a specific role or higher
func (m *Member) HasRole(requiredRole MemberRole) bool {
	roleHierarchy := map[MemberRole]int{
		MemberRoleViewer: 1,
		MemberRoleEditor: 2,
		MemberRoleAdmin:  3,
		MemberRoleOwner:  4,
	}
	
	return roleHierarchy[m.Role] >= roleHierarchy[requiredRole]
}

// CanManageMembers checks if a member can manage other members
func (m *Member) CanManageMembers() bool {
	return m.Role == MemberRoleOwner || m.Role == MemberRoleAdmin
}

// CanManageSettings checks if a member can manage workspace settings
func (m *Member) CanManageSettings() bool {
	return m.Role == MemberRoleOwner || m.Role == MemberRoleAdmin
}