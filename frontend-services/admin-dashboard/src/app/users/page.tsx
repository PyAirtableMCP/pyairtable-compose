'use client'

import { MainLayout } from '@/components/layout/MainLayout'
import { UserList } from '@/components/user/UserList'

export default function UsersPage() {
  return (
    <MainLayout title="User Administration">
      <UserList />
    </MainLayout>
  )
}