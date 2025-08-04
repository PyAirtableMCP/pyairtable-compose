"use client";

import React from "react";
import { useSession } from "next-auth/react";
import { MainLayout } from "@/components/layout/MainLayout";
import { DashboardOverview } from "@/components/dashboard/DashboardOverview";
import { useTenant } from "@/hooks/useTenant";
import { Card, CardContent } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { AlertCircle, Loader2 } from "lucide-react";
import type { Tenant } from "@/types";
import { useFeatureFlag } from "./posthog-provider";

// Mock tenant data for development
const mockTenant: Tenant = {
  id: "tenant_1",
  name: "Acme Corporation",
  slug: "acme-corp",
  description: "Leading provider of innovative solutions",
  logo: undefined,
  website: "https://acme.com",
  status: "active",
  plan: {
    id: "plan_pro",
    name: "pro",
    displayName: "Pro Plan",
    tier: "pro",
    limits: {
      users: 50,
      workspaces: 25,
      storage: 107374182400, // 100GB
      apiCalls: 1000000,
      automations: 100,
      fileUploads: 10000,
      dataTransfer: 107374182400,
      customFields: 500,
      views: 1000,
      records: 500000,
      webhooks: 50,
    },
    features: [
      {
        id: "sso",
        name: "Single Sign-On",
        description: "SAML and OAuth integration",
        category: "security",
        enabled: true,
      },
      {
        id: "advanced_analytics",
        name: "Advanced Analytics",
        description: "Detailed usage reports and insights",
        category: "analytics",
        enabled: true,
      },
    ],
    pricing: {
      basePrice: 4900, // $49.00
      currency: "USD",
      billingCycle: "monthly",
      usageTiers: [],
      discounts: [],
    },
    isActive: true,
  },
  owner: {
    id: "member_1",
    userId: "user_1",
    user: {
      id: "user_1",
      email: "owner@acme.com",
      firstName: "Sarah",
      lastName: "Johnson",
      fullName: "Sarah Johnson",
      avatar: undefined,
      timezone: "America/New_York",
      locale: "en-US",
      emailVerified: true,
      phoneVerified: false,
      twoFactorEnabled: true,
      loginCount: 156,
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
      createdAt: "2024-01-01T00:00:00Z",
      updatedAt: "2024-08-03T10:00:00Z",
    },
    role: {
      id: "role_owner",
      name: "owner",
      displayName: "Owner",
      description: "Full access to all features",
      permissions: [],
      isSystemRole: true,
      isCustom: false,
      level: 100,
    },
    permissions: [],
    status: "active",
    joinedAt: "2024-01-01T00:00:00Z",
    metadata: {},
  },
  members: [
    {
      id: "member_1",
      userId: "user_1",
      user: {
        id: "user_1",
        email: "owner@acme.com",
        firstName: "Sarah",
        lastName: "Johnson",
        fullName: "Sarah Johnson",
        avatar: undefined,
        timezone: "America/New_York",
        locale: "en-US",
        emailVerified: true,
        phoneVerified: false,
        twoFactorEnabled: true,
        loginCount: 156,
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
        createdAt: "2024-01-01T00:00:00Z",
        updatedAt: "2024-08-03T10:00:00Z",
      },
      role: {
        id: "role_owner",
        name: "owner",
        displayName: "Owner",
        description: "Full access to all features",
        permissions: [],
        isSystemRole: true,
        isCustom: false,
        level: 100,
      },
      permissions: [],
      status: "active",
      joinedAt: "2024-01-01T00:00:00Z",
      metadata: {},
    },
  ],
  usage: {
    current: {
      users: 12,
      workspaces: 8,
      records: 15420,
      storage: 2147483648, // 2GB
      apiCalls: 45000,
      automations: 15,
      fileUploads: 234,
      dataTransfer: 1073741824, // 1GB
      webhooks: 5,
      computeHours: 120,
    },
    limits: {
      users: 50,
      workspaces: 25,
      storage: 107374182400,
      apiCalls: 1000000,
      automations: 100,
      fileUploads: 10000,
      dataTransfer: 107374182400,
      customFields: 500,
      views: 1000,
      records: 500000,
      webhooks: 50,
    },
    period: {
      start: "2024-08-01T00:00:00Z",
      end: "2024-08-31T23:59:59Z",
      type: "monthly",
    },
    history: [],
    projections: [],
    lastCalculated: "2024-08-03T10:00:00Z",
  },
  settings: {
    general: {
      timezone: "America/New_York",
      dateFormat: "MM/dd/yyyy",
      timeFormat: "12h",
      language: "en",
      currency: "USD",
      weekStart: "sunday",
      allowUserRegistration: false,
      requireEmailVerification: true,
      customDomain: "acme.pyairtable.com",
      domainVerified: true,
    },
    security: {
      passwordPolicy: {
        minLength: 8,
        requireUppercase: true,
        requireLowercase: true,
        requireNumbers: true,
        requireSymbols: false,
        preventReuse: 5,
        maxAge: 90,
      },
      sessionTimeout: 480,
      twoFactorRequired: false,
      ipWhitelist: [],
      ssoEnabled: true,
      auditLogRetention: 365,
      encryptionAtRest: true,
      dataResidency: "US",
    },
    notifications: {
      channels: [],
      templates: [],
      preferences: {
        systemAlerts: true,
        billingNotifications: true,
        securityAlerts: true,
        usageWarnings: true,
        maintenanceUpdates: true,
        featureUpdates: false,
      },
    },
    integrations: {
      apiKeys: [],
      webhooks: [],
      connectedApps: [],
      rateLimits: [],
    },
    data: {
      backupEnabled: true,
      backupFrequency: "daily",
      backupRetention: 30,
      exportFormats: ["json", "csv"],
      dataResidency: "US",
      encryptionEnabled: true,
      complianceMode: "gdpr",
      retentionPolicies: [],
    },
    appearance: {
      theme: "light",
      primaryColor: "#3b82f6",
      branding: {
        companyName: "Acme Corporation",
        primaryColor: "#3b82f6",
        secondaryColor: "#1e40af",
        fontFamily: "Inter",
        hideFooter: false,
      },
    },
  },
  billing: {
    customerId: "cus_123456789",
    subscriptionId: "sub_123456789",
    status: "active",
    currentPeriod: {
      start: "2024-08-01T00:00:00Z",
      end: "2024-08-31T23:59:59Z",
      amount: 4900,
      currency: "USD",
      status: "current",
    },
    nextBilling: {
      start: "2024-09-01T00:00:00Z",
      end: "2024-09-30T23:59:59Z",
      amount: 4900,
      currency: "USD",
      status: "upcoming",
    },
    paymentMethod: {
      id: "pm_123456789",
      type: "card",
      last4: "4242",
      brand: "visa",
      expiryMonth: 12,
      expiryYear: 2025,
      isDefault: true,
      billingAddress: {
        line1: "123 Business St",
        city: "New York",
        state: "NY",
        postalCode: "10001",
        country: "US",
      },
    },
    invoices: [],
    credits: [],
    tax: {
      exemptStatus: false,
      rate: 8.25,
      region: "NY",
    },
  },
  security: {
    passwordPolicy: {
      minLength: 8,
      requireUppercase: true,
      requireLowercase: true,
      requireNumbers: true,
      requireSymbols: false,
      preventReuse: 5,
      maxAge: 90,
    },
    sessionTimeout: 480,
    twoFactorRequired: false,
    ipWhitelist: [],
    ssoEnabled: true,
    auditLogRetention: 365,
    encryptionAtRest: true,
    dataResidency: "US",
  },
  integrations: [],
  createdAt: "2024-01-01T00:00:00Z",
  updatedAt: "2024-08-03T10:00:00Z",
  lastActivityAt: "2024-08-03T09:30:00Z",
};

function LoadingState() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <Card className="w-96">
        <CardContent className="flex flex-col items-center justify-center p-8">
          <Loader2 className="h-8 w-8 animate-spin text-primary mb-4" />
          <h3 className="text-lg font-medium mb-2">Loading Dashboard</h3>
          <p className="text-sm text-muted-foreground text-center">
            Fetching your organization data...
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

function ErrorState({ error }: { error: Error }) {
  return (
    <div className="flex items-center justify-center min-h-screen p-4">
      <Card className="w-full max-w-md">
        <CardContent className="p-6">
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription className="mt-2">
              <strong>Unable to load dashboard</strong>
              <br />
              {error.message}
              <br />
              <button 
                onClick={() => window.location.reload()} 
                className="mt-2 text-sm underline hover:no-underline"
              >
                Try again
              </button>
            </AlertDescription>
          </Alert>
        </CardContent>
      </Card>
    </div>
  );
}

export default function HomePage() {
  const { data: session, status } = useSession();
  const isDevelopment = process.env.NODE_ENV === "development";
  const { data: tenant, isLoading, error } = useTenant();
  
  // Feature flags for progressive disclosure
  const showAdvancedMetrics = useFeatureFlag("advanced-metrics", false);
  const showBillingSection = useFeatureFlag("billing-controls", false);
  
  // Use mock data in development
  const currentTenant = isDevelopment ? mockTenant : tenant;
  
  // Show loading state while session is loading
  if (status === "loading" || (!isDevelopment && isLoading)) {
    return <LoadingState />;
  }

  // Handle errors
  if (!isDevelopment && error) {
    return <ErrorState error={error as Error} />;
  }

  if (!currentTenant) {
    return <ErrorState error={new Error("No tenant data available")} />;
  }

  return (
    <MainLayout>
      <DashboardOverview 
        tenant={currentTenant} 
        showAdvancedMetrics={showAdvancedMetrics}
        showBillingSection={showBillingSection}
      />
    </MainLayout>
  );
}