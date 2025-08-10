import { chromium, FullConfig } from '@playwright/test'
import { PrismaClient } from '@prisma/client'

// Global setup for E2E tests
async function globalSetup(config: FullConfig) {
  console.log('🚀 Starting global setup for E2E tests...')

  // Set database URL for tests
  const testDbUrl = 'postgresql://postgres:lIDvbpxaArutRwGz@localhost:5432/pyairtable'
  process.env.DATABASE_URL = testDbUrl

  // Initialize database connection with explicit URL
  const prisma = new PrismaClient({
    datasources: {
      db: {
        url: testDbUrl
      }
    }
  })

  try {
    // Clean up test data from previous runs
    console.log('🧹 Cleaning up test data...')
    await cleanupTestData(prisma)

    // Create test users and data
    console.log('👤 Creating test users...')
    await createTestUsers(prisma)

    // Setup test tenant data
    console.log('🏢 Setting up test tenant...')
    await setupTestTenant(prisma)

    // Warm up the application by launching a browser and navigating to the app
    console.log('🌡️ Warming up application...')
    const browser = await chromium.launch()
    const page = await browser.newPage()
    
    try {
      await page.goto(process.env.BASE_URL || 'http://localhost:3000', {
        waitUntil: 'networkidle',
        timeout: 30000
      })
      
      // Wait for the app to be ready
      await page.waitForSelector('body', { timeout: 15000 })
      console.log('✅ Application is ready for testing')
    } catch (error) {
      console.warn('⚠️ Application warmup failed, but continuing with tests:', error)
    } finally {
      await browser.close()
    }

    console.log('✨ Global setup completed successfully')
  } catch (error) {
    console.error('❌ Global setup failed:', error)
    throw error
  } finally {
    await prisma.$disconnect()
  }
}

async function cleanupTestData(prisma: PrismaClient) {
  // Delete test users and related data
  await prisma.user.deleteMany({
    where: {
      email: {
        contains: 'test'
      }
    }
  })

  // Clean up any test sessions
  await prisma.session.deleteMany({
    where: {
      user: {
        email: {
          contains: 'test'
        }
      }
    }
  })
}

async function createTestUsers(prisma: PrismaClient) {
  const bcrypt = require('bcryptjs')

  // Test user for registration flow
  const testPassword = await bcrypt.hash('TestPassword123!', 12)

  // Standard test user
  await prisma.user.upsert({
    where: { email: 'testuser@example.com' },
    update: {},
    create: {
      email: 'testuser@example.com',
      name: 'Test User',
      password: testPassword,
      emailVerified: new Date(),
    }
  })

  // Admin test user
  await prisma.user.upsert({
    where: { email: 'admin@example.com' },
    update: {},
    create: {
      email: 'admin@example.com',
      name: 'Admin User',
      password: testPassword,
      emailVerified: new Date(),
    }
  })

  // User for registration testing (will be created during test)
  try {
    await prisma.user.deleteMany({
      where: { email: 'newuser@example.com' }
    })
  } catch (error) {
    // User doesn't exist, which is expected
  }
}

async function setupTestTenant(prisma: PrismaClient) {
  // Create test tenant data if needed
  // This would typically involve setting up organization/tenant records
  // For now, we'll just ensure the database is ready
}

export default globalSetup