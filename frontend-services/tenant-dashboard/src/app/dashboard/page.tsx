'use client'

import { useSession } from 'next-auth/react'
import { useRouter } from 'next/navigation'
import { useEffect } from 'react'

export default function DashboardPage() {
  const { data: session, status } = useSession()
  const router = useRouter()

  useEffect(() => {
    if (status === 'loading') return // Still loading
    if (!session) {
      router.push('/auth/login') // Redirect to login if not authenticated
      return
    }
  }, [session, status, router])

  if (status === 'loading') {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-lg">Loading dashboard...</div>
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
          <h1 className="text-3xl font-bold text-gray-900">Dashboard</h1>
          <p className="text-gray-600 mt-2">
            Welcome back, {session.user?.email}!
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-xl font-semibold mb-4">Overview</h2>
            <p className="text-gray-600">Dashboard overview content</p>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-xl font-semibold mb-4">Analytics</h2>
            <p className="text-gray-600">Analytics content</p>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-xl font-semibold mb-4">Quick Actions</h2>
            <div className="space-y-2">
              <a
                href="/chat"
                className="block text-blue-600 hover:text-blue-800"
              >
                Go to Chat
              </a>
              <a
                href="/auth/register"
                className="block text-blue-600 hover:text-blue-800"
              >
                User Management
              </a>
            </div>
          </div>
        </div>

        {/* Debug info for testing */}
        <div className="mt-8 bg-gray-100 p-4 rounded-lg">
          <h3 className="text-sm font-semibold text-gray-700 mb-2">Debug Info</h3>
          <pre className="text-xs text-gray-600">
            User: {session.user?.email}
            Role: {session.user?.role}
            Tenant: {session.user?.tenantId}
          </pre>
        </div>
      </div>
    </div>
  )
}