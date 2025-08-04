'use client'

import React from 'react'
import { useSystemHealth, useResourceMetrics, useServiceStatus } from '@/hooks/useApi'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { formatBytes, formatPercentage, formatRelativeTime, getStatusColor } from '@/lib/utils'
import { Activity, Cpu, HardDrive, MemoryStick, Network, Server, AlertTriangle, CheckCircle, XCircle } from 'lucide-react'

export function SystemOverview() {
  const { data: health, isLoading: healthLoading } = useSystemHealth()
  const { data: metrics, isLoading: metricsLoading } = useResourceMetrics()
  const { data: services, isLoading: servicesLoading } = useServiceStatus()

  const getHealthIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircle className="w-5 h-5 text-green-600" />
      case 'degraded':
        return <AlertTriangle className="w-5 h-5 text-yellow-600" />
      case 'critical':
        return <XCircle className="w-5 h-5 text-red-600" />
      default:
        return <Activity className="w-5 h-5 text-gray-600" />
    }
  }

  return (
    <div className="space-y-6">
      {/* System Health Status */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">System Status</CardTitle>
            {!healthLoading && health && getHealthIcon(health.status)}
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {healthLoading ? (
                <div className="animate-pulse bg-gray-200 h-8 w-20 rounded" />
              ) : (
                health?.status?.charAt(0).toUpperCase() + health?.status?.slice(1) || 'Unknown'
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              {!healthLoading && health && `Last checked ${formatRelativeTime(health.lastChecked)}`}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Uptime</CardTitle>
            <Activity className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {healthLoading ? (
                <div className="animate-pulse bg-gray-200 h-8 w-24 rounded" />
              ) : (
                `${Math.floor((health?.uptime || 0) / 86400)}d ${Math.floor(((health?.uptime || 0) % 86400) / 3600)}h`
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              System uptime
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Active Services</CardTitle>
            <Server className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {servicesLoading ? (
                <div className="animate-pulse bg-gray-200 h-8 w-16 rounded" />
              ) : (
                `${services?.filter((s: any) => s.status === 'online').length || 0}/${services?.length || 0}`
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              Services online
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Response Time</CardTitle>
            <Network className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {servicesLoading ? (
                <div className="animate-pulse bg-gray-200 h-8 w-20 rounded" />
              ) : (
                `${Math.round(services?.reduce((acc: number, s: any) => acc + s.responseTime, 0) / (services?.length || 1) || 0)}ms`
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              Average response
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Resource Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">CPU Usage</CardTitle>
            <Cpu className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {metricsLoading ? (
                <div className="animate-pulse bg-gray-200 h-8 w-16 rounded" />
              ) : (
                `${Math.round(metrics?.cpu?.usage || 0)}%`
              )}
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2 mt-2">
              <div
                className="bg-blue-600 h-2 rounded-full"
                style={{ width: `${metrics?.cpu?.usage || 0}%` }}
              />
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              {metrics?.cpu?.cores} cores available
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Memory Usage</CardTitle>
            <MemoryStick className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {metricsLoading ? (
                <div className="animate-pulse bg-gray-200 h-8 w-16 rounded" />
              ) : (
                `${Math.round(metrics?.memory?.percentage || 0)}%`
              )}
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2 mt-2">
              <div
                className="bg-green-600 h-2 rounded-full"
                style={{ width: `${metrics?.memory?.percentage || 0}%` }}
              />
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              {formatBytes(metrics?.memory?.used || 0)} / {formatBytes(metrics?.memory?.total || 0)}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Disk Usage</CardTitle>
            <HardDrive className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {metricsLoading ? (
                <div className="animate-pulse bg-gray-200 h-8 w-16 rounded" />
              ) : (
                `${Math.round(metrics?.disk?.percentage || 0)}%`
              )}
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2 mt-2">
              <div
                className="bg-purple-600 h-2 rounded-full"
                style={{ width: `${metrics?.disk?.percentage || 0}%` }}
              />
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              {formatBytes(metrics?.disk?.used || 0)} / {formatBytes(metrics?.disk?.total || 0)}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Network I/O</CardTitle>
            <Network className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="space-y-1">
              <div className="flex justify-between text-sm">
                <span>In:</span>
                <span className="font-medium">
                  {metricsLoading ? '...' : formatBytes(metrics?.network?.inbound || 0) + '/s'}
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span>Out:</span>
                <span className="font-medium">
                  {metricsLoading ? '...' : formatBytes(metrics?.network?.outbound || 0) + '/s'}
                </span>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Service Status */}
      <Card>
        <CardHeader>
          <CardTitle>Service Status</CardTitle>
          <CardDescription>
            Current status of all system services
          </CardDescription>
        </CardHeader>
        <CardContent>
          {servicesLoading ? (
            <div className="space-y-2">
              {[...Array(5)].map((_, i) => (
                <div key={i} className="animate-pulse flex items-center space-x-4">
                  <div className="w-3 h-3 bg-gray-200 rounded-full" />
                  <div className="flex-1 bg-gray-200 h-4 rounded" />
                  <div className="w-16 bg-gray-200 h-6 rounded" />
                  <div className="w-20 bg-gray-200 h-4 rounded" />
                </div>
              ))}
            </div>
          ) : (
            <div className="space-y-3">
              {services?.map((service: any) => (
                <div key={service.name} className="flex items-center justify-between p-3 rounded-lg border">
                  <div className="flex items-center space-x-3">
                    <div className={`w-3 h-3 rounded-full ${
                      service.status === 'online' ? 'bg-green-500' :
                      service.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500'
                    }`} />
                    <div>
                      <p className="font-medium">{service.name}</p>
                      <p className="text-sm text-muted-foreground">{service.endpoint}</p>
                    </div>
                  </div>
                  <div className="flex items-center space-x-4">
                    <Badge
                      variant={service.status === 'online' ? 'success' : 
                               service.status === 'warning' ? 'warning' : 'destructive'}
                    >
                      {service.status}
                    </Badge>
                    <span className="text-sm text-muted-foreground">
                      {service.responseTime}ms
                    </span>
                    {service.version && (
                      <span className="text-xs text-muted-foreground">
                        v{service.version}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}