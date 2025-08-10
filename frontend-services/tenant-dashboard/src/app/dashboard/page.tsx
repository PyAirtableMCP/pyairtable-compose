'use client'

import React, { useEffect, useState } from 'react'
import { useSession } from 'next-auth/react'
import { useRouter } from 'next/navigation'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Loader2, Database, Users, Activity, ChevronRight, Eye, Edit, Key, RefreshCw } from 'lucide-react'
import toast from 'react-hot-toast'

interface AirtableBase {
  id: string
  name: string
  permissionLevel: 'read' | 'write' | 'comment'
  tableCount: number
  recordCount: number | null
  createdTime: string
  description?: string
}

export default function DashboardPage() {
  const { data: session, status } = useSession()
  const router = useRouter()
  const [bases, setBases] = useState<AirtableBase[]>([])
  const [isLoadingBases, setIsLoadingBases] = useState(false)
  const [personalAccessToken, setPersonalAccessToken] = useState('')
  const [hasAttemptedLoad, setHasAttemptedLoad] = useState(false)

  useEffect(() => {
    if (status === 'loading') return // Still loading
    if (!session) {
      router.push('/auth/login') // Redirect to login if not authenticated
      return
    }
  }, [session, status, router])

  const fetchAirtableBases = async () => {
    if (!personalAccessToken.trim()) {
      toast.error('Please enter your Airtable Personal Access Token')
      return
    }

    setIsLoadingBases(true)
    try {
      const response = await fetch('/api/airtable/bases', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ personalAccessToken }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Failed to fetch bases')
      }

      setBases(data.bases || [])
      setHasAttemptedLoad(true)
      toast.success(`Found ${data.bases?.length || 0} Airtable bases`)
    } catch (error) {
      console.error('Error fetching Airtable bases:', error)
      toast.error(error instanceof Error ? error.message : 'Failed to fetch Airtable bases')
    } finally {
      setIsLoadingBases(false)
    }
  }

  const refreshBases = () => {
    if (personalAccessToken.trim()) {
      fetchAirtableBases()
    }
  }

  if (status === 'loading') {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="h-8 w-8 animate-spin" />
        <span className="ml-2 text-lg">Loading dashboard...</span>
      </div>
    )
  }

  if (!session) {
    return null // Will redirect
  }

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-7xl mx-auto">
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900">PyAirtable Dashboard</h1>
          <p className="text-gray-600 mt-2">
            Welcome back, {session.user?.email}! Manage your Airtable integrations from here.
          </p>
        </div>

        {/* Airtable Connection Section */}
        <Card className="mb-8">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Key className="h-5 w-5" />
              Connect to Airtable
            </CardTitle>
            <CardDescription>
              Enter your Airtable Personal Access Token to view and manage your bases
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex gap-4 items-end">
              <div className="flex-1">
                <Input
                  type="password"
                  placeholder="Enter your Airtable Personal Access Token"
                  value={personalAccessToken}
                  onChange={(e) => setPersonalAccessToken(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      fetchAirtableBases()
                    }
                  }}
                />
                <p className="text-xs text-gray-500 mt-1">
                  Get your token from{' '}
                  <a
                    href="https://airtable.com/developers/web/api/authentication"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-blue-600 hover:underline"
                  >
                    Airtable Developer Hub
                  </a>
                </p>
              </div>
              <Button 
                onClick={fetchAirtableBases} 
                disabled={isLoadingBases || !personalAccessToken.trim()}
              >
                {isLoadingBases ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  'Connect'
                )}
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Airtable Bases Section */}
        {hasAttemptedLoad && (
          <Card className="mb-8">
            <CardHeader>
              <div className="flex justify-between items-center">
                <div>
                  <CardTitle className="flex items-center gap-2">
                    <Database className="h-5 w-5" />
                    Your Airtable Bases
                  </CardTitle>
                  <CardDescription>
                    {bases.length > 0 
                      ? `Found ${bases.length} accessible bases`
                      : 'No bases found with the provided token'
                    }
                  </CardDescription>
                </div>
                <Button variant="outline" size="sm" onClick={refreshBases}>
                  <RefreshCw className="h-4 w-4 mr-2" />
                  Refresh
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              {bases.length > 0 ? (
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                  {bases.map((base) => (
                    <Card key={base.id} className="cursor-pointer hover:shadow-md transition-shadow">
                      <CardHeader className="pb-2">
                        <div className="flex justify-between items-start">
                          <CardTitle className="text-lg">{base.name}</CardTitle>
                          <Badge variant={base.permissionLevel === 'write' ? 'default' : 'secondary'}>
                            {base.permissionLevel}
                          </Badge>
                        </div>
                        {base.description && (
                          <CardDescription>{base.description}</CardDescription>
                        )}
                      </CardHeader>
                      <CardContent>
                        <div className="space-y-2 text-sm text-gray-600">
                          <div className="flex items-center justify-between">
                            <span>Tables:</span>
                            <span className="font-medium">{base.tableCount}</span>
                          </div>
                          {base.recordCount && (
                            <div className="flex items-center justify-between">
                              <span>Records:</span>
                              <span className="font-medium">{base.recordCount.toLocaleString()}</span>
                            </div>
                          )}
                          <div className="flex items-center gap-2 mt-3">
                            <Button variant="outline" size="sm" className="flex-1">
                              <Eye className="h-4 w-4 mr-2" />
                              View
                            </Button>
                            {base.permissionLevel === 'write' && (
                              <Button variant="outline" size="sm" className="flex-1">
                                <Edit className="h-4 w-4 mr-2" />
                                Edit
                              </Button>
                            )}
                          </div>
                        </div>
                      </CardContent>
                    </Card>
                  ))}
                </div>
              ) : (
                <div className="text-center py-8 text-gray-500">
                  <Database className="h-12 w-12 mx-auto mb-4 text-gray-300" />
                  <p>No Airtable bases found.</p>
                  <p className="text-sm">Make sure your token has access to at least one base.</p>
                </div>
              )}
            </CardContent>
          </Card>
        )}

        {/* Quick Actions Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
          <Card className="cursor-pointer hover:shadow-md transition-shadow" onClick={() => router.push('/chat')}>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Activity className="h-5 w-5" />
                AI Chat Interface
              </CardTitle>
              <CardDescription>
                Interact with your Airtable data using natural language
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button variant="ghost" className="w-full justify-between">
                Open Chat
                <ChevronRight className="h-4 w-4" />
              </Button>
            </CardContent>
          </Card>

          <Card className="cursor-pointer hover:shadow-md transition-shadow">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Users className="h-5 w-5" />
                Team Management
              </CardTitle>
              <CardDescription>
                Manage team members and permissions
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button variant="ghost" className="w-full justify-between">
                Manage Team
                <ChevronRight className="h-4 w-4" />
              </Button>
            </CardContent>
          </Card>

          <Card className="cursor-pointer hover:shadow-md transition-shadow">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Database className="h-5 w-5" />
                API Documentation
              </CardTitle>
              <CardDescription>
                Learn how to integrate with PyAirtable APIs
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button variant="ghost" className="w-full justify-between">
                View Docs
                <ChevronRight className="h-4 w-4" />
              </Button>
            </CardContent>
          </Card>
        </div>

        {/* User Session Debug Info */}
        {process.env.NODE_ENV === 'development' && (
          <Card>
            <CardHeader>
              <CardTitle className="text-sm">Debug Information</CardTitle>
            </CardHeader>
            <CardContent>
              <pre className="text-xs text-gray-600 bg-gray-50 p-3 rounded">
                {JSON.stringify({
                  user: session.user?.email,
                  role: session.user?.role,
                  tenant: session.user?.tenantId,
                  hasToken: !!session.accessToken,
                }, null, 2)}
              </pre>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}