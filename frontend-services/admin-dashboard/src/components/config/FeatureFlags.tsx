'use client'

import React from 'react'
import { useFeatureFlags, useUpdateFeatureFlag } from '@/hooks/useApi'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { formatRelativeTime } from '@/lib/utils'
import { Search, ToggleLeft, Zap, Settings, Users, Shield, AlertTriangle } from 'lucide-react'
import { FeatureFlag } from '@/types'

export function FeatureFlags() {
  const [searchTerm, setSearchTerm] = React.useState('')
  const [categoryFilter, setCategoryFilter] = React.useState<string>('')

  const { data: flags, isLoading, error } = useFeatureFlags()
  const updateFeatureFlag = useUpdateFeatureFlag()

  const filteredFlags = flags?.filter((flag: FeatureFlag) => {
    const matchesSearch = flag.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         flag.description.toLowerCase().includes(searchTerm.toLowerCase())
    const matchesCategory = !categoryFilter || flag.name.toLowerCase().includes(categoryFilter.toLowerCase())
    return matchesSearch && matchesCategory
  }) || []

  const handleToggle = (flagId: string, enabled: boolean) => {
    updateFeatureFlag.mutate({
      flagId,
      updates: { enabled: !enabled }
    })
  }

  const handleRolloutChange = (flagId: string, percentage: number) => {
    updateFeatureFlag.mutate({
      flagId,
      updates: { rolloutPercentage: percentage }
    })
  }

  const getCategoryIcon = (flagName: string) => {
    if (flagName.toLowerCase().includes('auth') || flagName.toLowerCase().includes('security')) {
      return <Shield className="w-4 h-4" />
    }
    if (flagName.toLowerCase().includes('user') || flagName.toLowerCase().includes('profile')) {
      return <Users className="w-4 h-4" />
    }
    if (flagName.toLowerCase().includes('api') || flagName.toLowerCase().includes('performance')) {
      return <Zap className="w-4 h-4" />
    }
    return <Settings className="w-4 h-4" />
  }

  const getRiskLevel = (flag: FeatureFlag) => {
    if (flag.name.toLowerCase().includes('experimental') || flag.rolloutPercentage < 10) {
      return { level: 'high', color: 'destructive' }
    }
    if (flag.rolloutPercentage < 50) {
      return { level: 'medium', color: 'warning' }
    }
    return { level: 'low', color: 'success' }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Feature Flags</h1>
          <p className="text-muted-foreground">
            Control feature rollouts and system behavior
          </p>
        </div>
        <Button>
          <Zap className="w-4 h-4 mr-2" />
          Create Flag
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Flags</CardTitle>
            <ToggleLeft className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {flags?.length || 0}
            </div>
            <p className="text-xs text-muted-foreground">
              Across all environments
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Enabled</CardTitle>
            <Zap className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {flags?.filter((f: FeatureFlag) => f.enabled).length || 0}
            </div>
            <p className="text-xs text-muted-foreground">
              Currently active
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">In Rollout</CardTitle>
            <Settings className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {flags?.filter((f: FeatureFlag) => f.enabled && f.rolloutPercentage < 100).length || 0}
            </div>
            <p className="text-xs text-muted-foreground">
              Partial deployment
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">High Risk</CardTitle>
            <AlertTriangle className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {flags?.filter((f: FeatureFlag) => getRiskLevel(f).level === 'high').length || 0}
            </div>
            <p className="text-xs text-muted-foreground">
              Requires attention
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <CardHeader>
          <CardTitle>Filter Feature Flags</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="flex-1 relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search feature flags..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="pl-10"
              />
            </div>
            
            <select
              value={categoryFilter}
              onChange={(e) => setCategoryFilter(e.target.value)}
              className="px-3 py-2 border rounded-md bg-background"
            >
              <option value="">All Categories</option>
              <option value="auth">Authentication</option>
              <option value="user">User Features</option>
              <option value="performance">Performance</option>
              <option value="experimental">Experimental</option>
            </select>
          </div>
        </CardContent>
      </Card>

      {/* Feature Flags Table */}
      <Card>
        <CardHeader>
          <CardTitle>Feature Flags</CardTitle>
          <CardDescription>
            {filteredFlags.length} feature flags
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-3">
              {[...Array(5)].map((_, i) => (
                <div key={i} className="animate-pulse flex items-center space-x-4">
                  <div className="w-8 h-5 bg-gray-200 rounded" />
                  <div className="flex-1 space-y-2">
                    <div className="h-4 bg-gray-200 rounded w-1/4" />
                    <div className="h-3 bg-gray-200 rounded w-1/2" />
                  </div>
                  <div className="w-20 h-6 bg-gray-200 rounded" />
                </div>
              ))}
            </div>
          ) : error ? (
            <div className="text-center py-8">
              <p className="text-red-600">Error loading feature flags: {error.message}</p>
            </div>
          ) : filteredFlags.length === 0 ? (
            <div className="text-center py-8">
              <p className="text-muted-foreground">No feature flags found</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Flag</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Rollout</TableHead>
                    <TableHead>Risk Level</TableHead>
                    <TableHead>Environments</TableHead>
                    <TableHead>Updated</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredFlags.map((flag: FeatureFlag) => {
                    const risk = getRiskLevel(flag)
                    return (
                      <TableRow key={flag.id}>
                        <TableCell>
                          <div className="flex items-center space-x-3">
                            {getCategoryIcon(flag.name)}
                            <div>
                              <p className="font-medium">{flag.name}</p>
                              <p className="text-sm text-muted-foreground">{flag.description}</p>
                            </div>
                          </div>
                        </TableCell>
                        
                        <TableCell>
                          <div className="flex items-center space-x-2">
                            <button
                              onClick={() => handleToggle(flag.id, flag.enabled)}
                              disabled={updateFeatureFlag.isPending}
                              className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                                flag.enabled ? 'bg-green-600' : 'bg-gray-200'
                              }`}
                            >
                              <span
                                className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                                  flag.enabled ? 'translate-x-6' : 'translate-x-1'
                                }`}
                              />
                            </button>
                            <Badge variant={flag.enabled ? 'success' : 'gray'}>
                              {flag.enabled ? 'Enabled' : 'Disabled'}
                            </Badge>
                          </div>
                        </TableCell>
                        
                        <TableCell>
                          <div className="space-y-2">
                            <div className="flex items-center justify-between">
                              <span className="text-sm">{flag.rolloutPercentage}%</span>
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => {
                                  const newPercentage = prompt('Enter rollout percentage (0-100):', flag.rolloutPercentage.toString())
                                  if (newPercentage && !isNaN(Number(newPercentage))) {
                                    handleRolloutChange(flag.id, Math.max(0, Math.min(100, Number(newPercentage))))
                                  }
                                }}
                              >
                                Edit
                              </Button>
                            </div>
                            <div className="w-full bg-gray-200 rounded-full h-2">
                              <div
                                className="bg-blue-600 h-2 rounded-full"
                                style={{ width: `${flag.rolloutPercentage}%` }}
                              />
                            </div>
                          </div>
                        </TableCell>
                        
                        <TableCell>
                          <Badge variant={risk.color as any}>
                            {risk.level} risk
                          </Badge>
                        </TableCell>
                        
                        <TableCell>
                          <div className="flex flex-wrap gap-1">
                            {flag.environments.map((env) => (
                              <Badge key={env} variant="outline" className="text-xs">
                                {env}
                              </Badge>
                            ))}
                          </div>
                        </TableCell>
                        
                        <TableCell>
                          <div className="text-sm">
                            {formatRelativeTime(flag.updatedAt)}
                            <p className="text-xs text-muted-foreground">
                              by {flag.createdBy}
                            </p>
                          </div>
                        </TableCell>
                        
                        <TableCell>
                          <div className="flex items-center space-x-2">
                            <Button variant="ghost" size="sm">
                              Edit
                            </Button>
                            <Button variant="ghost" size="sm">
                              History
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}