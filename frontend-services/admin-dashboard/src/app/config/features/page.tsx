'use client'

import { MainLayout } from '@/components/layout/MainLayout'
import { FeatureFlags } from '@/components/config/FeatureFlags'

export default function FeatureFlagsPage() {
  return (
    <MainLayout title="Feature Flags">
      <FeatureFlags />
    </MainLayout>
  )
}