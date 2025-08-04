'use client'

import { MainLayout } from '@/components/layout/MainLayout'
import { SystemOverview } from '@/components/dashboard/SystemOverview'

export default function DashboardPage() {
  return (
    <MainLayout title="System Overview">
      <SystemOverview />
    </MainLayout>
  )
}