"use client";

import React from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { cn, formatRelativeTime, getInitials } from "@/lib/utils";
import { 
  User, 
  UserPlus, 
  Settings, 
  CreditCard, 
  FileText, 
  Shield,
  Trash2,
  Edit,
  Eye,
  Download,
  Upload,
  Key,
  Webhook,
} from "lucide-react";
import type { ActivityLog } from "@/types";

interface ActivityFeedProps {
  activities: ActivityLog[];
  className?: string;
  maxItems?: number;
  showViewAll?: boolean;
  onViewAll?: () => void;
}

const activityIcons: Record<string, React.ReactNode> = {
  "user.login": <User className="h-4 w-4" />,
  "user.logout": <User className="h-4 w-4" />,
  "user.invited": <UserPlus className="h-4 w-4" />,
  "user.removed": <Trash2 className="h-4 w-4" />,
  "user.role_changed": <Settings className="h-4 w-4" />,
  "workspace.created": <FileText className="h-4 w-4" />,
  "workspace.updated": <Edit className="h-4 w-4" />,
  "workspace.deleted": <Trash2 className="h-4 w-4" />,
  "workspace.viewed": <Eye className="h-4 w-4" />,
  "settings.updated": <Settings className="h-4 w-4" />,
  "billing.payment": <CreditCard className="h-4 w-4" />,
  "billing.plan_changed": <CreditCard className="h-4 w-4" />,
  "security.2fa_enabled": <Shield className="h-4 w-4" />,
  "security.password_changed": <Shield className="h-4 w-4" />,
  "data.exported": <Download className="h-4 w-4" />,
  "data.imported": <Upload className="h-4 w-4" />,
  "api.key_created": <Key className="h-4 w-4" />,
  "api.key_revoked": <Key className="h-4 w-4" />,
  "webhook.created": <Webhook className="h-4 w-4" />,
  "webhook.deleted": <Webhook className="h-4 w-4" />,
};

const severityColors: Record<string, string> = {
  low: "text-green-600 bg-green-50 border-green-200",
  medium: "text-blue-600 bg-blue-50 border-blue-200",
  high: "text-yellow-600 bg-yellow-50 border-yellow-200",
  critical: "text-red-600 bg-red-50 border-red-200",
};

export function ActivityFeed({ 
  activities, 
  className, 
  maxItems = 10,
  showViewAll = true,
  onViewAll 
}: ActivityFeedProps) {
  const displayedActivities = activities.slice(0, maxItems);

  const getActivityDescription = (activity: ActivityLog) => {
    const actionType = activity.action.type;
    const details = activity.details;
    
    switch (actionType) {
      case "user.invited":
        return `invited ${details.email} to join as ${details.role}`;
      case "user.removed":
        return `removed ${details.email} from the organization`;
      case "user.role_changed":
        return `changed ${details.email}'s role from ${details.oldRole} to ${details.newRole}`;
      case "workspace.created":
        return `created workspace "${details.workspaceName}"`;
      case "workspace.updated":
        return `updated workspace "${details.workspaceName}"`;
      case "workspace.deleted":
        return `deleted workspace "${details.workspaceName}"`;
      case "billing.plan_changed":
        return `upgraded plan from ${details.oldPlan} to ${details.newPlan}`;
      case "settings.updated":
        return `updated ${details.section} settings`;
      case "security.2fa_enabled":
        return "enabled two-factor authentication";
      case "api.key_created":
        return `created API key "${details.keyName}"`;
      case "webhook.created":
        return `created webhook for ${details.events?.join(", ")} events`;
      default:
        return activity.action.displayName;
    }
  };

  return (
    <Card className={cn("", className)}>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-base font-medium">Recent Activity</CardTitle>
        {showViewAll && activities.length > maxItems && (
          <Button 
            variant="ghost" 
            size="sm" 
            onClick={onViewAll}
            className="text-sm"
          >
            View all
          </Button>
        )}
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {displayedActivities.length === 0 ? (
            <div className="text-center py-6">
              <p className="text-sm text-muted-foreground">No recent activity</p>
            </div>
          ) : (
            displayedActivities.map((activity) => (
              <div key={activity.id} className="flex items-start space-x-3">
                <div className="flex-shrink-0">
                  <div className="w-8 h-8 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-xs font-medium">
                    {activity.user.avatar ? (
                      <img 
                        src={activity.user.avatar} 
                        alt={activity.user.fullName}
                        className="w-full h-full rounded-full"
                      />
                    ) : (
                      getInitials(activity.user.fullName)
                    )}
                  </div>
                </div>
                
                <div className="flex-1 min-w-0">
                  <div className="flex items-center space-x-2">
                    <div className="flex items-center space-x-1 text-muted-foreground">
                      {activityIcons[activity.action.type] || <Settings className="h-4 w-4" />}
                    </div>
                    <Badge 
                      variant="secondary" 
                      className={cn("text-xs", severityColors[activity.severity])}
                    >
                      {activity.severity}
                    </Badge>
                  </div>
                  
                  <div className="mt-1">
                    <p className="text-sm">
                      <span className="font-medium">{activity.user.fullName}</span>
                      {" "}
                      {getActivityDescription(activity)}
                    </p>
                    <div className="flex items-center space-x-2 mt-1">
                      <p className="text-xs text-muted-foreground">
                        {formatRelativeTime(activity.timestamp)}
                      </p>
                      {activity.ipAddress && (
                        <span className="text-xs text-muted-foreground">
                          • {activity.ipAddress}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
        
        {showViewAll && activities.length > maxItems && (
          <div className="mt-4 pt-4 border-t">
            <Button 
              variant="outline" 
              className="w-full" 
              onClick={onViewAll}
            >
              View all {activities.length} activities
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}