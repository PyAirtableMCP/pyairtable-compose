'use client'

import React from 'react'
import { useTenants, useSuspendTenant, useReactivateTenant } from '@/hooks/useApi'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { formatRelativeTime, formatBytes, formatCurrency, getStatusColor } from '@/lib/utils'
import { Search, Filter, MoreHorizontal, Users, HardDrive, CreditCard, AlertTriangle, CheckCircle, Settings } from 'lucide-react'
import { Tenant, FilterOptions } from '@/types'

export function TenantList() {
  const [searchTerm, setSearchTerm] = React.useState('')
  const [statusFilter, setStatusFilter] = React.useState<string>('')
  const [planFilter, setPlanFilter] = React.useState<string>('')
  const [currentPage, setCurrentPage] = React.useState(1)
  const pageSize = 20

  const filterOptions: FilterOptions = {
    search: searchTerm,
    filters: {
      ...(statusFilter && { status: statusFilter }),
      ...(planFilter && { plan: planFilter }),
    },
    pagination: {
      page: currentPage,
      limit: pageSize,
    },
    sort: {
      field: 'createdAt',
      direction: 'desc',
    },
  }

  const { data: tenantsData, isLoading, error } = useTenants(filterOptions)
  const suspendTenant = useSuspendTenant()
  const reactivateTenant = useReactivateTenant()

  const tenants = tenantsData?.data || []
  const pagination = tenantsData?.pagination

  const handleSuspend = (tenantId: string) => {
    if (confirm('Are you sure you want to suspend this tenant?')) {
      suspendTenant.mutate(tenantId)
    }
  }

  const handleReactivate = (tenantId: string) => {
    if (confirm('Are you sure you want to reactivate this tenant?')) {
      reactivateTenant.mutate(tenantId)
    }
  }

  const getUsagePercentage = (used: number, limit: number) => {
    if (limit === 0) return 0
    return Math.min((used / limit) * 100, 100)
  }

  const getUsageColor = (percentage: number) => {
    if (percentage >= 90) return 'text-red-600'
    if (percentage >= 75) return 'text-yellow-600'
    return 'text-green-600'
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Tenant Management</h1>
          <p className="text-muted-foreground">
            Manage all tenants and their configurations
          </p>
        </div>
        <Button>
          <Settings className="w-4 h-4 mr-2" />
          Create Tenant
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Tenants</CardTitle>
            <Users className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {pagination?.total || 0}
            </div>
            <p className="text-xs text-muted-foreground">
              Across all plans
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Active Tenants</CardTitle>
            <CheckCircle className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {tenants.filter((t: Tenant) => t.status === 'active').length}
            </div>
            <p className="text-xs text-muted-foreground">
              Currently active
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Suspended</CardTitle>
            <AlertTriangle className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {tenants.filter((t: Tenant) => t.status === 'suspended').length}
            </div>
            <p className="text-xs text-muted-foreground">
              Requires attention
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Monthly Revenue</CardTitle>
            <CreditCard className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatCurrency(
                tenants.reduce((sum: number, t: Tenant) => sum + (t.plan?.price || 0), 0)
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              From active tenants
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <CardHeader>
          <CardTitle>Filter Tenants</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search tenants..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="pl-10"
              />
            </div>
            
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="px-3 py-2 border rounded-md bg-background"
            >
              <option value="">All Statuses</option>
              <option value="active">Active</option>
              <option value="suspended">Suspended</option>
              <option value="pending">Pending</option>
            </select>
            
            <select
              value={planFilter}
              onChange={(e) => setPlanFilter(e.target.value)}
              className="px-3 py-2 border rounded-md bg-background"
            >
              <option value="">All Plans</option>
              <option value="free">Free</option>
              <option value="pro">Pro</option>
              <option value="enterprise">Enterprise</option>
            </select>
          </div>
        </CardContent>
      </Card>

      {/* Tenant Table */}
      <Card>
        <CardHeader>
          <CardTitle>Tenants</CardTitle>
          <CardDescription>
            {pagination ? `Showing ${tenants.length} of ${pagination.total} tenants` : 'Loading...'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-3">
              {[...Array(5)].map((_, i) => (
                <div key={i} className="animate-pulse flex items-center space-x-4">
                  <div className="w-12 h-12 bg-gray-200 rounded-lg" />
                  <div className="flex-1 space-y-2">
                    <div className="h-4 bg-gray-200 rounded w-1/4" />
                    <div className="h-3 bg-gray-200 rounded w-1/3" />
                  </div>
                  <div className="w-20 h-6 bg-gray-200 rounded" />
                </div>
              ))}
            </div>
          ) : error ? (
            <div className="text-center py-8">
              <p className="text-red-600">Error loading tenants: {error.message}</p>
            </div>
          ) : tenants.length === 0 ? (
            <div className="text-center py-8">
              <p className="text-muted-foreground">No tenants found</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Tenant</TableHead>
                    <TableHead>Plan</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Usage</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {tenants.map((tenant: Tenant) => (
                    <TableRow key={tenant.id}>
                      <TableCell>
                        <div className="flex items-center space-x-3">
                          <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
                            <span className="text-sm font-medium text-primary">
                              {tenant.name.charAt(0).toUpperCase()}
                            </span>
                          </div>
                          <div>
                            <p className="font-medium">{tenant.name}</p>
                            <p className="text-sm text-muted-foreground">{tenant.slug}</p>
                          </div>
                        </div>
                      </TableCell>
                      
                      <TableCell>
                        <Badge variant={
                          tenant.plan.tier === 'enterprise' ? 'default' :
                          tenant.plan.tier === 'pro' ? 'secondary' : 'gray'
                        }>
                          {tenant.plan.name}
                        </Badge>
                      </TableCell>
                      
                      <TableCell>
                        <Badge className={getStatusColor(tenant.status)}>
                          {tenant.status}
                        </Badge>
                      </TableCell>
                      
                      <TableCell>
                        <div className="space-y-1">
                          <div className="flex justify-between text-xs">
                            <span>Users:</span>
                            <span className={getUsageColor(getUsagePercentage(tenant.usage.users, tenant.plan.limits.users))}>
                              {tenant.usage.users}/{tenant.plan.limits.users}
                            </span>
                          </div>
                          <div className="flex justify-between text-xs">
                            <span>Storage:</span>
                            <span className={getUsageColor(getUsagePercentage(tenant.usage.storage, tenant.plan.limits.storage))}>
                              {formatBytes(tenant.usage.storage)}/{formatBytes(tenant.plan.limits.storage)}
                            </span>
                          </div>
                        </div>
                      </TableCell>
                      
                      <TableCell>
                        <span className="text-sm">
                          {formatRelativeTime(tenant.createdAt)}
                        </span>
                      </TableCell>
                      
                      <TableCell>
                        <div className="flex items-center space-x-2">
                          {tenant.status === 'active' ? (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleSuspend(tenant.id)}
                              disabled={suspendTenant.isPending}
                            >
                              Suspend
                            </Button>
                          ) : (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleReactivate(tenant.id)}
                              disabled={reactivateTenant.isPending}
                            >
                              Reactivate
                            </Button>
                          )}
                          
                          <Button variant="ghost" size="icon">
                            <MoreHorizontal className="w-4 h-4" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
          
          {/* Pagination */}
          {pagination && pagination.totalPages > 1 && (
            <div className="flex justify-between items-center mt-4">
              <p className="text-sm text-muted-foreground">
                Page {pagination.page} of {pagination.totalPages}
              </p>
              <div className="flex space-x-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setCurrentPage(Math.max(1, currentPage - 1))}
                  disabled={currentPage === 1}
                >
                  Previous
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setCurrentPage(Math.min(pagination.totalPages, currentPage + 1))}
                  disabled={currentPage === pagination.totalPages}
                >
                  Next
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}