"use client";

import React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import {
  LayoutDashboard,
  Users,
  FolderOpen,
  CreditCard,
  Settings,
  Shield,
  Building2,
  BarChart3,
  Key,
  Webhook,
  FileText,
  Download,
  UserCheck,
  Activity,
  AlertTriangle,
  Home,
} from "lucide-react";

const navigationItems = [
  {
    id: "overview",
    label: "Overview",
    href: "/",
    icon: Home,
    badge: null,
  },
  {
    id: "dashboard",
    label: "Dashboard",
    href: "/dashboard",
    icon: LayoutDashboard,
    badge: null,
  },
  {
    id: "team",
    label: "Team Management",
    href: "/team",
    icon: Users,
    badge: null,
    children: [
      {
        id: "team-members",
        label: "Members",
        href: "/team/members",
        icon: Users,
      },
      {
        id: "team-roles",
        label: "Roles & Permissions",
        href: "/team/roles",
        icon: UserCheck,
      },
      {
        id: "team-invitations",
        label: "Invitations",
        href: "/team/invitations",
        icon: Users,
        badge: "2",
      },
      {
        id: "team-activity",
        label: "Activity Logs",
        href: "/team/activity",
        icon: Activity,
      },
    ],
  },
  {
    id: "workspaces",
    label: "Workspaces",
    href: "/workspaces",
    icon: FolderOpen,
    badge: null,
    children: [
      {
        id: "workspaces-all",
        label: "All Workspaces",
        href: "/workspaces",
        icon: FolderOpen,
      },
      {
        id: "workspaces-templates",
        label: "Templates",
        href: "/workspaces/templates",
        icon: FileText,
      },
      {
        id: "workspaces-archived",
        label: "Archived",
        href: "/workspaces/archived",
        icon: FolderOpen,
      },
    ],
  },
  {
    id: "billing",
    label: "Billing & Usage",
    href: "/billing",
    icon: CreditCard,
    badge: null,
    children: [
      {
        id: "billing-overview",
        label: "Overview",
        href: "/billing",
        icon: BarChart3,
      },
      {
        id: "billing-subscription",
        label: "Subscription",
        href: "/billing/subscription",
        icon: CreditCard,
      },
      {
        id: "billing-usage",
        label: "Usage & Limits",
        href: "/billing/usage",
        icon: BarChart3,
      },
      {
        id: "billing-invoices",
        label: "Invoices",
        href: "/billing/invoices",
        icon: FileText,
      },
    ],
  },
  {
    id: "settings",
    label: "Settings",
    href: "/settings",
    icon: Settings,
    badge: null,
    children: [
      {
        id: "settings-general",
        label: "General",
        href: "/settings/general",
        icon: Building2,
      },
      {
        id: "settings-domain",
        label: "Custom Domain",
        href: "/settings/domain",
        icon: Settings,
      },
      {
        id: "settings-sso",
        label: "Single Sign-On",
        href: "/settings/sso",
        icon: Shield,
      },
      {
        id: "settings-api",
        label: "API Keys",
        href: "/settings/api",
        icon: Key,
      },
      {
        id: "settings-webhooks",
        label: "Webhooks",
        href: "/settings/webhooks",
        icon: Webhook,
      },
      {
        id: "settings-integrations",
        label: "Integrations",
        href: "/settings/integrations",
        icon: Settings,
      },
    ],
  },
  {
    id: "security",
    label: "Security & Compliance",
    href: "/security",
    icon: Shield,
    badge: null,
    children: [
      {
        id: "security-2fa",
        label: "Two-Factor Auth",
        href: "/security/2fa",
        icon: Shield,
      },
      {
        id: "security-sessions",
        label: "Active Sessions",
        href: "/security/sessions",
        icon: Activity,
      },
      {
        id: "security-audit",
        label: "Audit Logs",
        href: "/security/audit",
        icon: FileText,
      },
      {
        id: "security-export",
        label: "Data Export",
        href: "/security/export",
        icon: Download,
      },
      {
        id: "security-gdpr",
        label: "GDPR Tools",
        href: "/security/gdpr",
        icon: AlertTriangle,
      },
    ],
  },
];

interface SidebarProps {
  className?: string;
}

export function Sidebar({ className }: SidebarProps) {
  const pathname = usePathname();
  const [expandedItems, setExpandedItems] = React.useState<string[]>([]);

  const toggleExpanded = (itemId: string) => {
    setExpandedItems((prev) =>
      prev.includes(itemId)
        ? prev.filter((id) => id !== itemId)
        : [...prev, itemId]
    );
  };

  const isActiveItem = (href: string) => {
    if (href === "/") {
      return pathname === "/";
    }
    return pathname.startsWith(href);
  };

  const hasActiveChild = (children: any[]) => {
    return children.some((child) => isActiveItem(child.href));
  };

  React.useEffect(() => {
    // Auto-expand sections with active items
    const activeSection = navigationItems.find((item) => {
      if (item.children) {
        return hasActiveChild(item.children);
      }
      return isActiveItem(item.href);
    });

    if (activeSection && activeSection.children && !expandedItems.includes(activeSection.id)) {
      setExpandedItems((prev) => [...prev, activeSection.id]);
    }
  }, [pathname]);

  return (
    <div className={cn("pb-12 w-64 border-r bg-background", className)}>
      <div className="space-y-4 py-4">
        <div className="px-3 py-2">
          <div className="flex items-center mb-6">
            <Building2 className="w-8 h-8 text-primary mr-3" />
            <div>
              <h2 className="text-lg font-semibold">Organization</h2>
              <p className="text-sm text-muted-foreground">Management Hub</p>
            </div>
          </div>
          <div className="space-y-1">
            {navigationItems.map((item) => (
              <div key={item.id}>
                <div
                  className={cn(
                    "flex items-center justify-between rounded-lg px-3 py-2 text-sm transition-all hover:bg-accent hover:text-accent-foreground cursor-pointer",
                    isActiveItem(item.href) || (item.children && hasActiveChild(item.children))
                      ? "bg-accent text-accent-foreground"
                      : "text-muted-foreground"
                  )}
                  onClick={() => {
                    if (item.children) {
                      toggleExpanded(item.id);
                    }
                  }}
                >
                  {item.children ? (
                    <div className="flex items-center flex-1">
                      <item.icon className="mr-2 h-4 w-4" />
                      <span>{item.label}</span>
                      {item.badge && (
                        <Badge variant="secondary" className="ml-auto">
                          {item.badge}
                        </Badge>
                      )}
                    </div>
                  ) : (
                    <Link href={item.href} className="flex items-center flex-1">
                      <item.icon className="mr-2 h-4 w-4" />
                      <span>{item.label}</span>
                      {item.badge && (
                        <Badge variant="secondary" className="ml-auto">
                          {item.badge}
                        </Badge>
                      )}
                    </Link>
                  )}
                  {item.children && (
                    <svg
                      className={cn(
                        "h-4 w-4 transition-transform",
                        expandedItems.includes(item.id) ? "rotate-90" : ""
                      )}
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M9 5l7 7-7 7"
                      />
                    </svg>
                  )}
                </div>
                {item.children && expandedItems.includes(item.id) && (
                  <div className="ml-4 space-y-1 mt-1">
                    {item.children.map((child) => (
                      <Link
                        key={child.id}
                        href={child.href}
                        className={cn(
                          "flex items-center rounded-lg px-3 py-2 text-sm transition-all hover:bg-accent hover:text-accent-foreground",
                          isActiveItem(child.href)
                            ? "bg-accent text-accent-foreground"
                            : "text-muted-foreground"
                        )}
                      >
                        <child.icon className="mr-2 h-4 w-4" />
                        <span>{child.label}</span>
                        {child.badge && (
                          <Badge variant="secondary" className="ml-auto">
                            {child.badge}
                          </Badge>
                        )}
                      </Link>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}