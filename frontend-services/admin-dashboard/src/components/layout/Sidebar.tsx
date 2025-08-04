'use client'

import React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { cn } from '@/lib/utils'
import {
  BarChart3,
  Users,
  Building2,
  Settings,
  Activity,
  Database,
  FileText,
  AlertTriangle,
  Shield,
  Zap,
  LogOut,
  Monitor,
  ChevronDown,
  ChevronRight,
} from 'lucide-react'

interface SidebarItem {
  label: string
  href: string
  icon: React.ComponentType<{ className?: string }>
  children?: SidebarItem[]
}

const sidebarItems: SidebarItem[] = [
  {
    label: 'Overview',
    href: '/dashboard',
    icon: Monitor,
  },
  {
    label: 'System Health',
    href: '/system',
    icon: Activity,
    children: [
      { label: 'Health Status', href: '/system/health', icon: Activity },
      { label: 'Service Topology', href: '/system/topology', icon: Monitor },
      { label: 'Alerts', href: '/system/alerts', icon: AlertTriangle },
    ],
  },
  {
    label: 'Tenant Management',
    href: '/tenants',
    icon: Building2,
    children: [
      { label: 'All Tenants', href: '/tenants', icon: Building2 },
      { label: 'Usage Analytics', href: '/tenants/usage', icon: BarChart3 },
      { label: 'Plans & Billing', href: '/tenants/billing', icon: FileText },
    ],
  },
  {
    label: 'User Administration',
    href: '/users',
    icon: Users,
    children: [
      { label: 'User Management', href: '/users', icon: Users },
      { label: 'Roles & Permissions', href: '/users/roles', icon: Shield },
      { label: 'Activity Logs', href: '/users/activity', icon: Activity },
    ],
  },
  {
    label: 'System Configuration',
    href: '/config',
    icon: Settings,
    children: [
      { label: 'Feature Flags', href: '/config/features', icon: Zap },
      { label: 'System Settings', href: '/config/settings', icon: Settings },
      { label: 'Rate Limits', href: '/config/rate-limits', icon: Shield },
    ],
  },
  {
    label: 'Analytics & Reports',
    href: '/analytics',
    icon: BarChart3,
    children: [
      { label: 'Usage Analytics', href: '/analytics/usage', icon: BarChart3 },
      { label: 'Financial Reports', href: '/analytics/financial', icon: FileText },
      { label: 'Performance Metrics', href: '/analytics/performance', icon: Activity },
    ],
  },
  {
    label: 'Operational Tools',
    href: '/operations',
    icon: Database,
    children: [
      { label: 'Log Viewer', href: '/operations/logs', icon: FileText },
      { label: 'Database Query', href: '/operations/database', icon: Database },
      { label: 'Job Queue Monitor', href: '/operations/jobs', icon: Activity },
      { label: 'Cache Management', href: '/operations/cache', icon: Zap },
    ],
  },
]

interface SidebarProps {
  isCollapsed?: boolean
  onToggle?: () => void
}

export function Sidebar({ isCollapsed = false }: SidebarProps) {
  const pathname = usePathname()
  const [expandedItems, setExpandedItems] = React.useState<string[]>([])

  const toggleExpanded = (href: string) => {
    setExpandedItems(prev =>
      prev.includes(href)
        ? prev.filter(item => item !== href)
        : [...prev, href]
    )
  }

  const isActive = (href: string) => {
    return pathname === href || pathname.startsWith(href + '/')
  }

  const isExpanded = (href: string) => {
    return expandedItems.includes(href) || isActive(href)
  }

  const renderItem = (item: SidebarItem, level = 0) => {
    const hasChildren = item.children && item.children.length > 0
    const expanded = isExpanded(item.href)
    const active = isActive(item.href)

    return (
      <div key={item.href}>
        <div
          className={cn(
            'flex items-center w-full px-3 py-2 rounded-lg transition-colors',
            'hover:bg-muted/50',
            active && 'bg-primary/10 text-primary',
            level > 0 && 'ml-4'
          )}
        >
          {hasChildren ? (
            <button
              onClick={() => toggleExpanded(item.href)}
              className="flex items-center w-full text-left"
            >
              <item.icon className="w-4 h-4 mr-3 flex-shrink-0" />
              {!isCollapsed && (
                <>
                  <span className="flex-1 text-sm font-medium">
                    {item.label}
                  </span>
                  {expanded ? (
                    <ChevronDown className="w-4 h-4" />
                  ) : (
                    <ChevronRight className="w-4 h-4" />
                  )}
                </>
              )}
            </button>
          ) : (
            <Link href={item.href} className="flex items-center w-full">
              <item.icon className="w-4 h-4 mr-3 flex-shrink-0" />
              {!isCollapsed && (
                <span className="text-sm font-medium">{item.label}</span>
              )}
            </Link>
          )}
        </div>

        {hasChildren && expanded && !isCollapsed && (
          <div className="mt-1 space-y-1">
            {item.children?.map(child => renderItem(child, level + 1))}
          </div>
        )}
      </div>
    )
  }

  return (
    <div
      className={cn(
        'flex flex-col h-full bg-card border-r transition-all duration-300',
        isCollapsed ? 'w-16' : 'w-64'
      )}
    >
      {/* Header */}
      <div className="p-4 border-b">
        <div className="flex items-center">
          <div className="w-8 h-8 bg-primary rounded-lg flex items-center justify-center">
            <Monitor className="w-4 h-4 text-primary-foreground" />
          </div>
          {!isCollapsed && (
            <div className="ml-3">
              <h1 className="text-lg font-semibold">PyAirtable</h1>
              <p className="text-xs text-muted-foreground">Admin Dashboard</p>
            </div>
          )}
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 p-4 space-y-2 overflow-y-auto">
        {sidebarItems.map(item => renderItem(item))}
      </nav>

      {/* Footer */}
      <div className="p-4 border-t">
        <button
          className={cn(
            'flex items-center w-full px-3 py-2 rounded-lg transition-colors',
            'hover:bg-muted/50 text-muted-foreground hover:text-foreground'
          )}
        >
          <LogOut className="w-4 h-4 mr-3 flex-shrink-0" />
          {!isCollapsed && <span className="text-sm font-medium">Logout</span>}
        </button>
      </div>
    </div>
  )
}