'use client'

import React from 'react'
import { Sidebar } from './Sidebar'
import { Header } from './Header'
import { cn } from '@/lib/utils'

interface MainLayoutProps {
  children: React.ReactNode
  title?: string
}

export function MainLayout({ children, title }: MainLayoutProps) {
  const [sidebarCollapsed, setSidebarCollapsed] = React.useState(false)

  const toggleSidebar = () => {
    setSidebarCollapsed(!sidebarCollapsed)
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="flex h-screen">
        {/* Sidebar */}
        <aside
          className={cn(
            'hidden lg:block transition-all duration-300',
            sidebarCollapsed ? 'w-16' : 'w-64'
          )}
        >
          <Sidebar isCollapsed={sidebarCollapsed} />
        </aside>

        {/* Mobile sidebar overlay */}
        <aside
          className={cn(
            'lg:hidden fixed inset-y-0 left-0 z-50 transition-transform duration-300',
            sidebarCollapsed ? '-translate-x-full' : 'translate-x-0'
          )}
        >
          <Sidebar />
          {/* Overlay */}
          <div
            className="fixed inset-0 bg-black/50 -z-10"
            onClick={toggleSidebar}
          />
        </aside>

        {/* Main content */}
        <div className="flex-1 flex flex-col overflow-hidden">
          <Header onToggleSidebar={toggleSidebar} title={title} />
          
          <main className="flex-1 overflow-y-auto">
            <div className="container mx-auto px-4 py-6 lg:px-6">
              {children}
            </div>
          </main>
        </div>
      </div>
    </div>
  )
}