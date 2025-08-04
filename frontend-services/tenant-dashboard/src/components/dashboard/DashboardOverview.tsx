"use client";

import React from "react";
import { MetricCard } from "./MetricCard";
import { UsageChart } from "./UsageChart";
import { UsageProgress } from "./UsageProgress";
import { ActivityFeed } from "./ActivityFeed";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { 
  Users, 
  FolderOpen, 
  Database, 
  Activity,
  CreditCard,
  Zap,
  HardDrive,
  Globe,
  TrendingUp,
  Calendar,
  AlertTriangle,
} from "lucide-react";
import { cn, formatCurrency, formatBytes, formatNumber } from "@/lib/utils";
import type { Tenant, ActivityLog } from "@/types";

interface DashboardOverviewProps {
  tenant: Tenant;
  className?: string;
}

export function DashboardOverview({ tenant, className }: DashboardOverviewProps) {
  // Mock data - in real app, this would come from API
  const usageData = [
    { date: "Jan", value: 2400 },
    { date: "Feb", value: 1398 },
    { date: "Mar", value: 9800 },
    { date: "Apr", value: 3908 },
    { date: "May", value: 4800 },
    { date: "Jun", value: 3800 },
    { date: "Jul", value: 4300 },
  ];

  const storageData = [
    { date: "Jan", value: 1200000000 },
    { date: "Feb", value: 1800000000 },
    { date: "Mar", value: 2100000000 },
    { date: "Apr", value: 2400000000 },
    { date: "May", value: 2800000000 },
    { date: "Jun", value: 3200000000 },
    { date: "Jul", value: 3600000000 },
  ];

  const recentActivities: ActivityLog[] = [
    {
      id: "1",
      tenantId: tenant.id,
      userId: "user1",
      user: {
        id: "user1",
        email: "john@company.com",
        firstName: "John",
        lastName: "Doe",
        fullName: "John Doe",
        avatar: undefined,
        timezone: "UTC",
        locale: "en-US",
        emailVerified: true,
        phoneVerified: false,
        twoFactorEnabled: false,
        loginCount: 25,
        preferences: {
          theme: "light",
          notifications: {
            email: true,
            push: true,
            sms: false,
            inApp: true,
            digest: "daily",
            categories: {},
          },
          dateFormat: "MM/dd/yyyy",
          timeFormat: "12h",
          language: "en",
        },
        createdAt: "2024-01-15T00:00:00Z",
        updatedAt: "2024-01-15T00:00:00Z",
      },
      action: {
        type: "workspace.created",
        category: "data",
        displayName: "Created workspace",
        description: "Created a new workspace",
      },
      resource: {
        type: "workspace",
        displayName: "Workspace",
        category: "data",
      },
      resourceId: "ws1",
      details: {
        workspaceName: "Customer Database",
      },
      ipAddress: "192.168.1.100",
      userAgent: "Mozilla/5.0...",
      timestamp: "2024-08-03T10:30:00Z",
      severity: "low",
    },
    {
      id: "2",
      tenantId: tenant.id,
      userId: "user2",
      user: {
        id: "user2",
        email: "sarah@company.com",
        firstName: "Sarah",
        lastName: "Johnson",
        fullName: "Sarah Johnson",
        avatar: undefined,
        timezone: "UTC",
        locale: "en-US",
        emailVerified: true,
        phoneVerified: false,
        twoFactorEnabled: true,
        loginCount: 42,
        preferences: {
          theme: "dark",
          notifications: {
            email: true,
            push: true,
            sms: false,
            inApp: true,
            digest: "weekly",
            categories: {},
          },
          dateFormat: "MM/dd/yyyy",
          timeFormat: "24h",
          language: "en",
        },
        createdAt: "2024-01-10T00:00:00Z",
        updatedAt: "2024-01-10T00:00:00Z",
      },
      action: {
        type: "user.invited",
        category: "admin",
        displayName: "Invited user",
        description: "Invited a new user to join",
      },
      resource: {
        type: "user",
        displayName: "User",
        category: "admin",
      },
      resourceId: "user3",
      details: {
        email: "mike@company.com",
        role: "Editor",
      },
      ipAddress: "192.168.1.101",
      userAgent: "Mozilla/5.0...",
      timestamp: "2024-08-03T09:15:00Z",
      severity: "medium",
    },
  ];

  const quickActions = [
    {
      title: "Invite Team Member",
      description: "Add someone to your organization",
      href: "/team/invitations",
      icon: <Users className="h-5 w-5" />,
      color: "bg-blue-500",
    },
    {
      title: "Create Workspace",
      description: "Start a new project workspace",
      href: "/workspaces/new",
      icon: <FolderOpen className="h-5 w-5" />,
      color: "bg-green-500",
    },
    {
      title: "View Usage",
      description: "Check your current usage limits",
      href: "/billing/usage",
      icon: <Activity className="h-5 w-5" />,
      color: "bg-purple-500",
    },
    {
      title: "Billing Settings",
      description: "Manage your subscription",
      href: "/billing",
      icon: <CreditCard className="h-5 w-5" />,
      color: "bg-orange-500",
    },
  ];

  return (
    <div className={cn("space-y-6", className)}>
      {/* Welcome Section */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Welcome back!</h1>
          <p className="text-muted-foreground">
            Here's what's happening with {tenant.name} today.
          </p>
        </div>
        <div className="flex items-center space-x-2">
          <Badge variant="outline" className="flex items-center space-x-1">
            <Calendar className="h-3 w-3" />
            <span>{new Date().toLocaleDateString()}</span>
          </Badge>
        </div>
      </div>

      {/* Key Metrics */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          title="Team Members"
          value={tenant.members.length}
          change={8.2}
          changeType="increase"
          description="vs last month"
          icon={<Users className="h-4 w-4" />}
        />
        <MetricCard
          title="Active Workspaces"
          value={tenant.usage.workspaces}
          change={-2.1}
          changeType="decrease"
          description="vs last month"
          icon={<FolderOpen className="h-4 w-4" />}
        />
        <MetricCard
          title="Storage Used"
          value={tenant.usage.storage}
          format="bytes"
          change={12.5}
          changeType="increase"
          description="vs last month"
          icon={<HardDrive className="h-4 w-4" />}
        />
        <MetricCard
          title="API Calls"
          value={tenant.usage.apiCalls}
          change={5.4}
          changeType="increase"
          description="this month"
          icon={<Zap className="h-4 w-4" />}
        />
      </div>

      {/* Charts and Usage */}
      <div className="grid gap-6 md:grid-cols-2">
        <UsageChart
          title="API Usage Trend"
          description="Daily API calls over the last 7 days"
          data={usageData}
          type="area"
          color="#3b82f6"
          format="number"
          badge="This Month"
        />
        <UsageChart
          title="Storage Growth"
          description="Storage usage over time"
          data={storageData}
          type="line"
          color="#10b981"
          format="bytes"
          badge="All Time"
        />
      </div>

      {/* Usage Limits and Activity */}
      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-1">
          <UsageProgress
            title="Current Usage"
            items={[
              {
                name: "Team Members",
                current: tenant.usage.users,
                limit: tenant.plan.limits.users,
                description: "Users in your organization",
              },
              {
                name: "Workspaces",
                current: tenant.usage.workspaces,
                limit: tenant.plan.limits.workspaces,
                description: "Active workspaces",
              },
              {
                name: "Storage",
                current: tenant.usage.storage,
                limit: tenant.plan.limits.storage,
                format: "bytes",
                description: "Files and data storage",
              },
              {
                name: "API Calls",
                current: tenant.usage.apiCalls,
                limit: tenant.plan.limits.apiCalls,
                description: "This month",
              },
            ]}
          />
        </div>
        
        <div className="lg:col-span-2">
          <ActivityFeed 
            activities={recentActivities}
            maxItems={6}
            onViewAll={() => window.location.href = "/security/audit"}
          />
        </div>
      </div>

      {/* Quick Actions */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium">Quick Actions</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            {quickActions.map((action, index) => (
              <Button
                key={index}
                variant="outline"
                className="h-auto p-4 flex flex-col items-start space-y-2 hover:bg-accent"
                onClick={() => window.location.href = action.href}
              >
                <div className={cn("w-8 h-8 rounded-lg flex items-center justify-center text-white", action.color)}>
                  {action.icon}
                </div>
                <div className="text-left">
                  <h3 className="font-medium text-sm">{action.title}</h3>
                  <p className="text-xs text-muted-foreground">{action.description}</p>
                </div>
              </Button>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Plan Status */}
      {tenant.plan.tier !== "enterprise" && (
        <Card className="border-primary/20 bg-gradient-to-r from-primary/5 to-transparent">
          <CardContent className="flex items-center justify-between p-6">
            <div className="flex items-center space-x-4">
              <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                <TrendingUp className="h-5 w-5 text-primary" />
              </div>
              <div>
                <h3 className="font-medium">Upgrade Your Plan</h3>
                <p className="text-sm text-muted-foreground">
                  Get more features and higher limits with our Pro plan
                </p>
              </div>
            </div>
            <Button onClick={() => window.location.href = "/billing/subscription"}>
              Upgrade Now
            </Button>
          </CardContent>
        </Card>
      )}
    </div>
  );
}