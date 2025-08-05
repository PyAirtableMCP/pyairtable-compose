'use client'

import React from 'react'
import Image from 'next/image'
import { useUsers, useSuspendUser, useReactivateUser, useRoles } from '@/hooks/useApi'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { formatRelativeTime, getStatusColor } from '@/lib/utils'
import { Search, MoreHorizontal, Users, UserCheck, UserX, Shield, Mail, Calendar } from 'lucide-react'
import { User, FilterOptions } from '@/types'

export function UserList() {
  const [searchTerm, setSearchTerm] = React.useState('')
  const [statusFilter, setStatusFilter] = React.useState<string>('')
  const [roleFilter, setRoleFilter] = React.useState<string>('')
  const [currentPage, setCurrentPage] = React.useState(1)
  const pageSize = 20

  const filterOptions: FilterOptions = {
    search: searchTerm,
    filters: {
      ...(statusFilter && { status: statusFilter }),
      ...(roleFilter && { role: roleFilter }),
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

  const { data: usersData, isLoading, error } = useUsers(filterOptions)
  const { data: roles } = useRoles()
  const suspendUser = useSuspendUser()
  const reactivateUser = useReactivateUser()

  const users = usersData?.data || []
  const pagination = usersData?.pagination

  const handleSuspend = (userId: string) => {
    if (confirm('Are you sure you want to suspend this user?')) {
      suspendUser.mutate(userId)
    }
  }

  const handleReactivate = (userId: string) => {
    if (confirm('Are you sure you want to reactivate this user?')) {
      reactivateUser.mutate(userId)
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-semibold">User Administration</h1>
          <p className="text-muted-foreground">
            Manage users, roles, and permissions across the platform
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline">
            <Shield className="w-4 h-4 mr-2" />
            Manage Roles
          </Button>
          <Button>
            <Users className="w-4 h-4 mr-2" />
            Invite User
          </Button>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Users</CardTitle>
            <Users className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {pagination?.total || 0}
            </div>
            <p className="text-xs text-muted-foreground">
              Across all tenants
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Active Users</CardTitle>
            <UserCheck className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {users.filter((u: User) => u.status === 'active').length}
            </div>
            <p className="text-xs text-muted-foreground">
              Currently active
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Suspended</CardTitle>
            <UserX className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {users.filter((u: User) => u.status === 'suspended').length}
            </div>
            <p className="text-xs text-muted-foreground">
              Requires attention
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Unverified</CardTitle>
            <Mail className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {users.filter((u: User) => !u.emailVerified).length}
            </div>
            <p className="text-xs text-muted-foreground">
              Email not verified
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <CardHeader>
          <CardTitle>Filter Users</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search users by name or email..."
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
              <option value="inactive">Inactive</option>
              <option value="suspended">Suspended</option>
            </select>
            
            <select
              value={roleFilter}
              onChange={(e) => setRoleFilter(e.target.value)}
              className="px-3 py-2 border rounded-md bg-background"
            >
              <option value="">All Roles</option>
              {(Array.isArray(roles) ? roles : []).map((role: any) => (
                <option key={role.id} value={role.name}>
                  {role.name}
                </option>
              ))}
            </select>
          </div>
        </CardContent>
      </Card>

      {/* User Table */}
      <Card>
        <CardHeader>
          <CardTitle>Users</CardTitle>
          <CardDescription>
            {pagination ? `Showing ${users.length} of ${pagination.total} users` : 'Loading...'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-3">
              {[...Array(5)].map((_, i) => (
                <div key={i} className="animate-pulse flex items-center space-x-4">
                  <div className="w-12 h-12 bg-gray-200 rounded-full" />
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
              <p className="text-red-600">Error loading users: {error.message}</p>
            </div>
          ) : users.length === 0 ? (
            <div className="text-center py-8">
              <p className="text-muted-foreground">No users found</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>User</TableHead>
                    <TableHead>Role</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Tenants</TableHead>
                    <TableHead>Last Login</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {users.map((user: User) => (
                    <TableRow key={user.id}>
                      <TableCell>
                        <div className="flex items-center space-x-3">
                          <div className="w-10 h-10 bg-primary/10 rounded-full flex items-center justify-center">
                            {user.avatar ? (
                              <Image
                                src={user.avatar}
                                alt={`${user.firstName} ${user.lastName}`}
                                width={40}
                                height={40}
                                className="w-10 h-10 rounded-full"
                              />
                            ) : (
                              <span className="text-sm font-medium text-primary">
                                {user.firstName.charAt(0)}{user.lastName.charAt(0)}
                              </span>
                            )}
                          </div>
                          <div>
                            <p className="font-medium">{user.firstName} {user.lastName}</p>
                            <p className="text-sm text-muted-foreground">{user.email}</p>
                            <div className="flex items-center gap-2 mt-1">
                              {!user.emailVerified && (
                                <Badge variant="warning" className="text-xs">
                                  Unverified
                                </Badge>
                              )}
                              {user.twoFactorEnabled && (
                                <Badge variant="success" className="text-xs">
                                  2FA
                                </Badge>
                              )}
                            </div>
                          </div>
                        </div>
                      </TableCell>
                      
                      <TableCell>
                        <Badge variant="secondary">
                          {user.role.name}
                        </Badge>
                      </TableCell>
                      
                      <TableCell>
                        <Badge className={getStatusColor(user.status)}>
                          {user.status}
                        </Badge>
                      </TableCell>
                      
                      <TableCell>
                        <div className="flex flex-wrap gap-1">
                          {user.tenants.slice(0, 2).map((tenant) => (
                            <Badge key={tenant.tenantId} variant="outline" className="text-xs">
                              {tenant.tenantName}
                            </Badge>
                          ))}
                          {user.tenants.length > 2 && (
                            <Badge variant="outline" className="text-xs">
                              +{user.tenants.length - 2} more
                            </Badge>
                          )}
                        </div>
                      </TableCell>
                      
                      <TableCell>
                        <div className="flex items-center text-sm">
                          <Calendar className="w-3 h-3 mr-1 text-muted-foreground" />
                          {user.lastLogin ? formatRelativeTime(user.lastLogin) : 'Never'}
                        </div>
                        <p className="text-xs text-muted-foreground">
                          {user.loginCount} logins
                        </p>
                      </TableCell>
                      
                      <TableCell>
                        <span className="text-sm">
                          {formatRelativeTime(user.createdAt)}
                        </span>
                      </TableCell>
                      
                      <TableCell>
                        <div className="flex items-center space-x-2">
                          {user.status === 'active' ? (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleSuspend(user.id)}
                              disabled={suspendUser.isPending}
                            >
                              Suspend
                            </Button>
                          ) : (
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => handleReactivate(user.id)}
                              disabled={reactivateUser.isPending}
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