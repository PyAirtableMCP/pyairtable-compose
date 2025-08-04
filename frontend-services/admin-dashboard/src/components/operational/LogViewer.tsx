'use client'

import React from 'react'
import { useSearchLogs } from '@/hooks/useApi'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { formatRelativeTime, getSeverityColor } from '@/lib/utils'
import { Search, Filter, Download, Refresh, Terminal, AlertTriangle, Info, Bug, Zap } from 'lucide-react'
import { LogEntry, LogQuery } from '@/types'

export function LogViewer() {
  const [query, setQuery] = React.useState('')
  const [selectedLevel, setSelectedLevel] = React.useState<string>('')
  const [selectedService, setSelectedService] = React.useState<string>('')
  const [timeRange, setTimeRange] = React.useState('1h')
  const [autoRefresh, setAutoRefresh] = React.useState(false)
  const [expandedLogs, setExpandedLogs] = React.useState<Set<string>>(new Set())

  const searchLogs = useSearchLogs()

  const logQuery: LogQuery = {
    query,
    level: selectedLevel ? [selectedLevel] : undefined,
    service: selectedService ? [selectedService] : undefined,
    timeRange: {
      start: new Date(Date.now() - getTimeRangeMs(timeRange)).toISOString(),
      end: new Date().toISOString(),
    },
    limit: 100,
    offset: 0,
  }

  function getTimeRangeMs(range: string): number {
    switch (range) {
      case '15m': return 15 * 60 * 1000
      case '1h': return 60 * 60 * 1000
      case '6h': return 6 * 60 * 60 * 1000
      case '24h': return 24 * 60 * 60 * 1000
      case '7d': return 7 * 24 * 60 * 60 * 1000
      default: return 60 * 60 * 1000
    }
  }

  const handleSearch = () => {
    searchLogs.mutate(logQuery)
  }

  const toggleExpanded = (logId: string) => {
    const newExpanded = new Set(expandedLogs)
    if (newExpanded.has(logId)) {
      newExpanded.delete(logId)
    } else {
      newExpanded.add(logId)
    }
    setExpandedLogs(newExpanded)
  }

  const getLevelIcon = (level: string) => {
    switch (level) {
      case 'error':
      case 'fatal':
        return <AlertTriangle className="w-4 h-4" />
      case 'warn':
        return <AlertTriangle className="w-4 h-4" />
      case 'info':
        return <Info className="w-4 h-4" />
      case 'debug':
        return <Bug className="w-4 h-4" />
      default:
        return <Terminal className="w-4 h-4" />
    }
  }

  const getLevelColor = (level: string) => {
    switch (level) {
      case 'error':
      case 'fatal':
        return 'text-red-600 bg-red-100'
      case 'warn':
        return 'text-yellow-600 bg-yellow-100'
      case 'info':
        return 'text-blue-600 bg-blue-100'
      case 'debug':
        return 'text-gray-600 bg-gray-100'
      default:
        return 'text-gray-600 bg-gray-100'
    }
  }

  // Auto-refresh effect
  React.useEffect(() => {
    if (autoRefresh) {
      const interval = setInterval(() => {
        handleSearch()
      }, 5000)
      return () => clearInterval(interval)
    }
  }, [autoRefresh, logQuery])

  // Mock logs for demonstration
  const mockLogs: LogEntry[] = [
    {
      id: '1',
      timestamp: new Date().toISOString(),
      level: 'error',
      service: 'api-gateway',
      message: 'Database connection failed',
      metadata: { 
        error: 'ECONNREFUSED',
        host: 'postgres-primary',
        port: 5432,
        retryCount: 3
      },
      traceId: 'trace-123',
      userId: 'user-456',
      tenantId: 'tenant-789'
    },
    {
      id: '2',
      timestamp: new Date(Date.now() - 30000).toISOString(),
      level: 'warn',
      service: 'auth-service',
      message: 'Rate limit exceeded for IP address',
      metadata: { 
        ip: '192.168.1.100',
        endpoint: '/api/v1/auth/login',
        attempts: 15
      },
      traceId: 'trace-124'
    },
    {
      id: '3',
      timestamp: new Date(Date.now() - 60000).toISOString(),
      level: 'info',
      service: 'user-service',
      message: 'User profile updated successfully',
      metadata: { 
        userId: 'user-789',
        fields: ['firstName', 'lastName', 'email']
      },
      userId: 'user-789',
      tenantId: 'tenant-123'
    },
    {
      id: '4',
      timestamp: new Date(Date.now() - 120000).toISOString(),
      level: 'debug',
      service: 'workflow-engine',
      message: 'Processing automation trigger',
      metadata: { 
        workflowId: 'wf-456',
        trigger: 'webhook',
        payload: { type: 'record_created' }
      },
      tenantId: 'tenant-456'
    }
  ]

  const logs = searchLogs.data?.data || mockLogs

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Log Viewer</h1>
          <p className="text-muted-foreground">
            Search and analyze system logs in real-time
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant={autoRefresh ? "default" : "outline"}
            size="sm"
            onClick={() => setAutoRefresh(!autoRefresh)}
          >
            <Refresh className={`w-4 h-4 mr-2 ${autoRefresh ? 'animate-spin' : ''}`} />
            Auto Refresh
          </Button>
          <Button variant="outline" size="sm">
            <Download className="w-4 h-4 mr-2" />
            Export
          </Button>
        </div>
      </div>

      {/* Search and Filters */}
      <Card>
        <CardHeader>
          <CardTitle>Search Logs</CardTitle>
          <CardDescription>
            Use keywords, service names, or trace IDs to filter logs
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div className="flex flex-col sm:flex-row gap-4">
              <div className="flex-1 relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search logs... (e.g., error, user-123, trace-id)"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  className="pl-10"
                  onKeyPress={(e) => e.key === 'Enter' && handleSearch()}
                />
              </div>
              <Button onClick={handleSearch} disabled={searchLogs.isPending}>
                <Search className="w-4 h-4 mr-2" />
                Search
              </Button>
            </div>

            <div className="flex flex-wrap gap-4">
              <select
                value={selectedLevel}
                onChange={(e) => setSelectedLevel(e.target.value)}
                className="px-3 py-2 border rounded-md bg-background"
              >
                <option value="">All Levels</option>
                <option value="debug">Debug</option>
                <option value="info">Info</option>
                <option value="warn">Warning</option>
                <option value="error">Error</option>
                <option value="fatal">Fatal</option>
              </select>

              <select
                value={selectedService}
                onChange={(e) => setSelectedService(e.target.value)}
                className="px-3 py-2 border rounded-md bg-background"
              >
                <option value="">All Services</option>
                <option value="api-gateway">API Gateway</option>
                <option value="auth-service">Auth Service</option>
                <option value="user-service">User Service</option>
                <option value="tenant-service">Tenant Service</option>
                <option value="workflow-engine">Workflow Engine</option>
              </select>

              <select
                value={timeRange}
                onChange={(e) => setTimeRange(e.target.value)}
                className="px-3 py-2 border rounded-md bg-background"
              >
                <option value="15m">Last 15 minutes</option>
                <option value="1h">Last hour</option>
                <option value="6h">Last 6 hours</option>
                <option value="24h">Last 24 hours</option>
                <option value="7d">Last 7 days</option>
              </select>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Log Entries */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            Log Entries
            <Badge variant="outline">
              {logs.length} entries
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent>
          {searchLogs.isPending ? (
            <div className="space-y-3">
              {[...Array(5)].map((_, i) => (
                <div key={i} className="animate-pulse p-4 border rounded-lg">
                  <div className="flex items-center space-x-4">
                    <div className="w-4 h-4 bg-gray-200 rounded" />
                    <div className="flex-1 space-y-2">
                      <div className="h-4 bg-gray-200 rounded w-3/4" />
                      <div className="h-3 bg-gray-200 rounded w-1/2" />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : logs.length === 0 ? (
            <div className="text-center py-8">
              <Terminal className="w-12 h-12 text-muted-foreground mx-auto mb-4" />
              <p className="text-muted-foreground">No logs found for the current filters</p>
            </div>
          ) : (
            <div className="space-y-2">
              {logs.map((log: LogEntry) => (
                <div
                  key={log.id}
                  className="border rounded-lg p-4 hover:bg-muted/50 transition-colors"
                >
                  <div className="flex items-start space-x-3">
                    <div className={`mt-1 ${getLevelColor(log.level)} rounded-full p-1`}>
                      {getLevelIcon(log.level)}
                    </div>
                    
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center space-x-2 mb-1">
                        <Badge variant="outline" className="text-xs">
                          {log.service}
                        </Badge>
                        <Badge className={`text-xs ${getLevelColor(log.level)}`}>
                          {log.level.toUpperCase()}
                        </Badge>
                        <span className="text-xs text-muted-foreground">
                          {formatRelativeTime(log.timestamp)}
                        </span>
                        {log.traceId && (
                          <Badge variant="outline" className="text-xs font-mono">
                            {log.traceId}
                          </Badge>
                        )}
                      </div>
                      
                      <p className="text-sm font-medium mb-1">{log.message}</p>
                      
                      <div className="flex items-center space-x-4 text-xs text-muted-foreground">
                        {log.userId && <span>User: {log.userId}</span>}
                        {log.tenantId && <span>Tenant: {log.tenantId}</span>}
                        <span>{new Date(log.timestamp).toLocaleString()}</span>
                      </div>
                      
                      {log.metadata && (
                        <div className="mt-2">
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => toggleExpanded(log.id)}
                            className="h-6 px-2 text-xs"
                          >
                            {expandedLogs.has(log.id) ? 'Hide' : 'Show'} Details
                          </Button>
                          
                          {expandedLogs.has(log.id) && (
                            <div className="mt-2 p-2 bg-muted rounded text-xs font-mono overflow-x-auto">
                              <pre>{JSON.stringify(log.metadata, null, 2)}</pre>
                            </div>
                          )}
                        </div>
                      )}
                    </div>
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