'use client'

import React from 'react'
import { LineChart, Line, AreaChart, Area, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { formatNumber, formatBytes, formatCurrency } from '@/lib/utils'

interface MetricsChartProps {
  title: string
  description?: string
  data: any[]
  type: 'line' | 'area' | 'bar' | 'pie'
  dataKey?: string
  xAxisKey?: string
  color?: string
  valueFormatter?: (value: any) => string
  height?: number
  showGrid?: boolean
  showTooltip?: boolean
  loading?: boolean
}

const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#84cc16', '#f97316']

export function MetricsChart({
  title,
  description,
  data,
  type,
  dataKey = 'value',
  xAxisKey = 'timestamp',
  color = '#3b82f6',
  valueFormatter = (value) => formatNumber(value),
  height = 300,
  showGrid = true,
  showTooltip = true,
  loading = false,
}: MetricsChartProps) {
  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div className="bg-background border rounded-lg shadow-lg p-3">
          <p className="text-sm font-medium">{label}</p>
          {payload.map((entry: any, index: number) => (
            <p key={index} className="text-sm" style={{ color: entry.color }}>
              {entry.name}: {valueFormatter(entry.value)}
            </p>
          ))}
        </div>
      )
    }
    return null
  }

  const renderChart = () => {
    if (loading) {
      return (
        <div className="flex items-center justify-center h-full">
          <div className="animate-pulse bg-gray-200 w-full h-full rounded" />
        </div>
      )
    }

    switch (type) {
      case 'line':
        return (
          <ResponsiveContainer width="100%" height={height}>
            <LineChart data={data}>
              {showGrid && <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />}
              <XAxis dataKey={xAxisKey} stroke="#6b7280" fontSize={12} />
              <YAxis stroke="#6b7280" fontSize={12} tickFormatter={valueFormatter} />
              {showTooltip && <Tooltip content={<CustomTooltip />} />}
              <Line
                type="monotone"
                dataKey={dataKey}
                stroke={color}
                strokeWidth={2}
                dot={{ fill: color, strokeWidth: 2, r: 4 }}
                activeDot={{ r: 6 }}
              />
            </LineChart>
          </ResponsiveContainer>
        )

      case 'area':
        return (
          <ResponsiveContainer width="100%" height={height}>
            <AreaChart data={data}>
              {showGrid && <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />}
              <XAxis dataKey={xAxisKey} stroke="#6b7280" fontSize={12} />
              <YAxis stroke="#6b7280" fontSize={12} tickFormatter={valueFormatter} />
              {showTooltip && <Tooltip content={<CustomTooltip />} />}
              <Area
                type="monotone"
                dataKey={dataKey}
                stroke={color}
                strokeWidth={2}
                fill={color}
                fillOpacity={0.1}
              />
            </AreaChart>
          </ResponsiveContainer>
        )

      case 'bar':
        return (
          <ResponsiveContainer width="100%" height={height}>
            <BarChart data={data}>
              {showGrid && <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />}
              <XAxis dataKey={xAxisKey} stroke="#6b7280" fontSize={12} />
              <YAxis stroke="#6b7280" fontSize={12} tickFormatter={valueFormatter} />
              {showTooltip && <Tooltip content={<CustomTooltip />} />}
              <Bar dataKey={dataKey} fill={color} radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        )

      case 'pie':
        return (
          <ResponsiveContainer width="100%" height={height}>
            <PieChart>
              <Pie
                data={data}
                cx="50%"
                cy="50%"
                labelLine={false}
                label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                outerRadius={80}
                fill="#8884d8"
                dataKey={dataKey}
              >
                {data.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                ))}
              </Pie>
              {showTooltip && <Tooltip formatter={(value) => valueFormatter(value)} />}
            </PieChart>
          </ResponsiveContainer>
        )

      default:
        return null
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          {title}
          {loading && <Badge variant="outline">Loading...</Badge>}
        </CardTitle>
        {description && <CardDescription>{description}</CardDescription>}
      </CardHeader>
      <CardContent>
        {renderChart()}
      </CardContent>
    </Card>
  )
}

// Specialized chart components
export function UsageChart({ data, loading }: { data: any[], loading?: boolean }) {
  return (
    <MetricsChart
      title="API Usage Over Time"
      description="Total API calls per hour"
      data={data}
      type="area"
      dataKey="apiCalls"
      xAxisKey="hour"
      color="#3b82f6"
      valueFormatter={formatNumber}
      loading={loading}
    />
  )
}

export function RevenueChart({ data, loading }: { data: any[], loading?: boolean }) {
  return (
    <MetricsChart
      title="Monthly Revenue"
      description="Revenue breakdown by plan type"
      data={data}
      type="bar"
      dataKey="revenue"
      xAxisKey="month"
      color="#10b981"
      valueFormatter={formatCurrency}
      loading={loading}
    />
  )
}

export function StorageChart({ data, loading }: { data: any[], loading?: boolean }) {
  return (
    <MetricsChart
      title="Storage Usage"
      description="Storage consumption by tenant"
      data={data}
      type="pie"
      dataKey="storage"
      valueFormatter={formatBytes}
      loading={loading}
    />
  )
}

export function PerformanceChart({ data, loading }: { data: any[], loading?: boolean }) {
  return (
    <MetricsChart
      title="Average Response Time"
      description="API response times over the last 24 hours"
      data={data}
      type="line"
      dataKey="responseTime"
      xAxisKey="timestamp"
      color="#f59e0b"
      valueFormatter={(value) => `${value}ms`}
      loading={loading}
    />
  )
}