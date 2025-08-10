import { FullConfig } from '@playwright/test'
import { PrismaClient } from '@prisma/client'

// Global teardown for E2E tests
async function globalTeardown(config: FullConfig) {
  console.log('🧼 Starting global teardown for E2E tests...')

  // Set database URL for tests
  const testDbUrl = 'postgresql://postgres:lIDvbpxaArutRwGz@localhost:5432/pyairtable'
  process.env.DATABASE_URL = testDbUrl

  const prisma = new PrismaClient({
    datasources: {
      db: {
        url: testDbUrl
      }
    }
  })

  try {
    // Clean up test data
    console.log('🗑️ Cleaning up test data...')
    await cleanupTestData(prisma)

    // Close any remaining connections
    await prisma.$disconnect()

    console.log('✅ Global teardown completed successfully')
  } catch (error) {
    console.error('❌ Global teardown failed:', error)
    // Don't throw error to avoid masking test failures
  }
}

async function cleanupTestData(prisma: PrismaClient) {
  try {
    // Delete test sessions
    await prisma.session.deleteMany({
      where: {
        user: {
          email: {
            contains: 'test'
          }
        }
      }
    })

    // Delete test users
    await prisma.user.deleteMany({
      where: {
        email: {
          contains: 'test'
        }
      }
    })

    // Clean up verification tokens
    await prisma.verificationToken.deleteMany({
      where: {
        identifier: {
          contains: 'test'
        }
      }
    })

    console.log('✅ Test data cleanup completed')
  } catch (error) {
    console.warn('⚠️ Some test data cleanup failed:', error)
  }
}

export default globalTeardown