'use client'

import { MainLayout } from '@/components/layout/MainLayout'
import { TenantList } from '@/components/tenant/TenantList'

export default function TenantsPage() {
  return (
    <MainLayout title="Tenant Management">
      <TenantList />
    </MainLayout>
  )
}