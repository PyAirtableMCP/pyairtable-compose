'use client'

import React from 'react'
import { useAnalytics } from '@/hooks/useApi'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { UsageChart, RevenueChart, StorageChart, PerformanceChart } from '@/components/charts/MetricsChart'
import { formatNumber, formatCurrency, formatBytes } from '@/lib/utils'
import {
  TrendingUp,
  TrendingDown,
  Users,
  DollarSign,
  Database,
  Activity,
  Download,
} from 'lucide-react'

export function AnalyticsDashboard() {
  const [timeRange, setTimeRange] = React.useState('24h')
  const { isLoading: usageLoading } = useAnalytics('usage', timeRange)
  const { isLoading: revenueLoading } = useAnalytics('revenue', timeRange)
  const { isLoading: performanceLoading } = useAnalytics('performance', timeRange)
  const { isLoading: storageLoading } = useAnalytics('storage', timeRange)

  // Mock data for demonstration - replace with real data
  const mockKPIs = {
    totalUsers: 12543,
    totalUsersChange: 12.5,
    totalRevenue: 125430,
    totalRevenueChange: 8.2,
    totalStorage: 567890123456,
    totalStorageChange: 15.3,
    avgResponseTime: 245,
    avgResponseTimeChange: -5.2,
  }

  const mockUsageData = [
    { hour: '00:00', apiCalls: 1200 },
    { hour: '04:00', apiCalls: 890 },
    { hour: '08:00', apiCalls: 2340 },
    { hour: '12:00', apiCalls: 3450 },
    { hour: '16:00', apiCalls: 2890 },
    { hour: '20:00', apiCalls: 1890 },
  ]

  const mockRevenueData = [
    { month: 'Jan', revenue: 45000 },
    { month: 'Feb', revenue: 52000 },
    { month: 'Mar', revenue: 48000 },
    { month: 'Apr', revenue: 61000 },
    { month: 'May', revenue: 58000 },
    { month: 'Jun', revenue: 67000 },
  ]

  const mockStorageData = [
    { name: 'Free Users', storage: 123456789 },
    { name: 'Pro Users', storage: 234567890 },
    { name: 'Enterprise', storage: 345678901 },
  ]

  const mockPerformanceData = [
    { timestamp: '00:00', responseTime: 245 },
    { timestamp: '04:00', responseTime: 230 },
    { timestamp: '08:00', responseTime: 280 },
    { timestamp: '12:00', responseTime: 320 },
    { timestamp: '16:00', responseTime: 295 },
    { timestamp: '20:00', responseTime: 250 },
  ]

  const getTrendIcon = (change: number) => {
    return change >= 0 ? (
      <TrendingUp className="w-4 h-4 text-green-600" />
    ) : (
      <TrendingDown className="w-4 h-4 text-red-600" />
    )
  }

  const getTrendColor = (change: number) => {
    return change >= 0 ? 'text-green-600' : 'text-red-600'
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Analytics & Reports</h1>
          <p className="text-muted-foreground">
            Comprehensive insights into platform usage and performance
          </p>
        </div>
        <div className="flex items-center gap-2">
          <select
            value={timeRange}
            onChange={(e) => setTimeRange(e.target.value)}
            className="px-3 py-2 border rounded-md bg-background"
          >
            <option value="1h">Last Hour</option>
            <option value="24h">Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
            <option value="30d">Last 30 Days</option>
            <option value="90d">Last 90 Days</option>
          </select>
          <Button variant="outline">
            <Download className="w-4 h-4 mr-2" />
            Export
          </Button>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Users</CardTitle>
            <Users className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatNumber(mockKPIs.totalUsers)}
            </div>
            <div className="flex items-center mt-1">
              {getTrendIcon(mockKPIs.totalUsersChange)}
              <span className={`text-xs ml-1 ${getTrendColor(mockKPIs.totalUsersChange)}`}>
                {Math.abs(mockKPIs.totalUsersChange)}% from last period
              </span>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Revenue</CardTitle>
            <DollarSign className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatCurrency(mockKPIs.totalRevenue)}
            </div>
            <div className="flex items-center mt-1">
              {getTrendIcon(mockKPIs.totalRevenueChange)}
              <span className={`text-xs ml-1 ${getTrendColor(mockKPIs.totalRevenueChange)}`}>
                {Math.abs(mockKPIs.totalRevenueChange)}% from last period
              </span>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Storage Used</CardTitle>
            <Database className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {formatBytes(mockKPIs.totalStorage)}
            </div>
            <div className="flex items-center mt-1">
              {getTrendIcon(mockKPIs.totalStorageChange)}
              <span className={`text-xs ml-1 ${getTrendColor(mockKPIs.totalStorageChange)}`}>
                {Math.abs(mockKPIs.totalStorageChange)}% from last period
              </span>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Avg Response Time</CardTitle>
            <Activity className="w-4 h-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {mockKPIs.avgResponseTime}ms
            </div>
            <div className="flex items-center mt-1">
              {getTrendIcon(mockKPIs.avgResponseTimeChange)}
              <span className={`text-xs ml-1 ${getTrendColor(mockKPIs.avgResponseTimeChange)}`}>
                {Math.abs(mockKPIs.avgResponseTimeChange)}% from last period
              </span>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Charts Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <UsageChart data={mockUsageData} loading={usageLoading} />
        <PerformanceChart data={mockPerformanceData} loading={performanceLoading} />
        <RevenueChart data={mockRevenueData} loading={revenueLoading} />
        <StorageChart data={mockStorageData} loading={storageLoading} />
      </div>

      {/* Detailed Analytics Tables */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Top Tenants by Usage */}
        <Card>
          <CardHeader>
            <CardTitle>Top Tenants by API Usage</CardTitle>
            <CardDescription>Highest API consumers this period</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {[
                { name: 'Acme Corp', usage: 125430, change: 12.5 },
                { name: 'TechStart Inc', usage: 98760, change: -3.2 },
                { name: 'Global Solutions', usage: 87650, change: 8.7 },
                { name: 'Innovation Labs', usage: 76540, change: 15.4 },
                { name: 'Data Systems', usage: 65430, change: -1.8 },
              ].map((tenant, index) => (
                <div key={index} className="flex items-center justify-between p-3 rounded-lg border">
                  <div className="flex items-center space-x-3">
                    <div className="w-8 h-8 bg-primary/10 rounded-lg flex items-center justify-center">
                      <span className="text-sm font-medium text-primary">
                        {index + 1}
                      </span>
                    </div>
                    <div>
                      <p className="font-medium">{tenant.name}</p>
                      <p className="text-sm text-muted-foreground">
                        {formatNumber(tenant.usage)} requests
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center">
                    {getTrendIcon(tenant.change)}
                    <span className={`text-xs ml-1 ${getTrendColor(tenant.change)}`}>
                      {Math.abs(tenant.change)}%
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Error Rate Breakdown */}
        <Card>
          <CardHeader>
            <CardTitle>Error Rate Breakdown</CardTitle>
            <CardDescription>HTTP status codes distribution</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {[
                { status: '2xx Success', count: 2456789, percentage: 92.5, color: 'bg-green-500' },
                { status: '4xx Client Error', count: 145678, percentage: 5.5, color: 'bg-yellow-500' },
                { status: '5xx Server Error', count: 53210, percentage: 2.0, color: 'bg-red-500' },
              ].map((status, index) => (
                <div key={index} className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-medium">{status.status}</span>
                    <span className="text-sm text-muted-foreground">
                      {formatNumber(status.count)} ({status.percentage}%)
                    </span>
                  </div>
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div
                      className={`${status.color} h-2 rounded-full`}
                      style={{ width: `${status.percentage}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}