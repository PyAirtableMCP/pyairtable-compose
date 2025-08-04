'use client'

import { MainLayout } from '@/components/layout/MainLayout'
import { AnalyticsDashboard } from '@/components/analytics/AnalyticsDashboard'

export default function AnalyticsPage() {
  return (
    <MainLayout title="Usage Analytics">
      <AnalyticsDashboard />
    </MainLayout>
  )
}