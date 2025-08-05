/**
 * Test Data Factory for PyAirtable Test Suite
 * 
 * Provides consistent, reliable test data generation for:
 * - User accounts and authentication
 * - Airtable base configurations
 * - JWT tokens and sessions
 * - Service responses and mock data
 */

import { faker } from '@faker-js/faker'
import * as jwt from 'jsonwebtoken'

export interface TestUser {
  id: string
  email: string
  name: string
  tenantId: string
  roles: string[]
  createdAt: string
  lastLoginAt?: string
}

export interface TestAirtableBase {
  id: string
  name: string
  tables: TestAirtableTable[]
  permissions: string[]
}

export interface TestAirtableTable {
  id: string
  name: string
  fields: TestAirtableField[]
  records: TestAirtableRecord[]
}

export interface TestAirtableField {
  id: string
  name: string
  type: string
  options?: any
}

export interface TestAirtableRecord {
  id: string
  fields: Record<string, any>
  createdTime: string
}

export interface JWTPayload {
  userId: string
  tenantId: string
  roles: string[]
  iat: number
  exp: number
}

export class TestDataFactory {
  private static readonly JWT_SECRET = 'test-secret-key'
  private static readonly DEFAULT_TENANT_ID = 'test-tenant-default'

  /**
   * Create a test user with realistic data
   */
  static createTestUser(overrides: Partial<TestUser> = {}): TestUser {
    const defaultUser: TestUser = {
      id: `user-${faker.string.uuid()}`,
      email: faker.internet.email(),
      name: faker.person.fullName(),
      tenantId: this.DEFAULT_TENANT_ID,
      roles: ['user'],
      createdAt: faker.date.past().toISOString(),
      lastLoginAt: faker.date.recent().toISOString()
    }

    return { ...defaultUser, ...overrides }
  }

  /**
   * Create multiple test users
   */
  static createTestUsers(count: number, baseOverrides: Partial<TestUser> = {}): TestUser[] {
    return Array.from({ length: count }, (_, index) => 
      this.createTestUser({
        ...baseOverrides,
        email: `testuser${index + 1}@example.com`,
        name: `Test User ${index + 1}`
      })
    )
  }

  /**
   * Create a JWT token for testing
   */
  static createJWTToken(overrides: Partial<JWTPayload> = {}): string {
    const payload: JWTPayload = {
      userId: faker.string.uuid(),
      tenantId: this.DEFAULT_TENANT_ID,
      roles: ['user'],
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + (24 * 60 * 60), // 24 hours
      ...overrides
    }

    return jwt.sign(payload, this.JWT_SECRET)
  }

  /**
   * Create a refresh token
   */
  static createRefreshToken(): string {
    return `refresh_${faker.string.alphanumeric(32)}`
  }

  /**
   * Create a test Airtable base with realistic structure
   */
  static createTestAirtableBase(overrides: Partial<TestAirtableBase> = {}): TestAirtableBase {
    const defaultBase: TestAirtableBase = {
      id: `app${faker.string.alphanumeric(14)}`,
      name: faker.company.name() + ' Base',
      tables: [
        this.createProjectsTable(),
        this.createTasksTable(),
        this.createUsersTable(),
        this.createFacebookPostsTable()
      ],
      permissions: ['read', 'write', 'create', 'delete']
    }

    return { ...defaultBase, ...overrides }
  }

  /**
   * Create a Projects table with realistic data
   */
  static createProjectsTable(): TestAirtableTable {
    return {
      id: `tbl${faker.string.alphanumeric(14)}`,
      name: 'Projects',
      fields: [
        { id: 'fld001', name: 'Name', type: 'singleLineText' },
        { id: 'fld002', name: 'Status', type: 'singleSelect', options: { 
          choices: ['Planning', 'In Progress', 'Completed', 'On Hold'] 
        }},
        { id: 'fld003', name: 'Budget', type: 'currency' },
        { id: 'fld004', name: 'Start Date', type: 'date' },
        { id: 'fld005', name: 'Description', type: 'multilineText' }
      ],
      records: [
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Name': 'Website Redesign',
            'Status': 'In Progress',
            'Budget': 15000,
            'Start Date': '2024-01-15',
            'Description': 'Complete redesign of company website'
          },
          createdTime: faker.date.past().toISOString()
        },
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Name': 'Mobile App Development',
            'Status': 'Planning',
            'Budget': 50000,
            'Start Date': '2024-03-01',
            'Description': 'Native mobile app for iOS and Android'
          },
          createdTime: faker.date.past().toISOString()
        }
      ]
    }
  }

  /**
   * Create a Tasks table
   */
  static createTasksTable(): TestAirtableTable {
    return {
      id: `tbl${faker.string.alphanumeric(14)}`,
      name: 'Tasks',
      fields: [
        { id: 'fld101', name: 'Task Name', type: 'singleLineText' },
        { id: 'fld102', name: 'Assignee', type: 'singleSelect' },
        { id: 'fld103', name: 'Priority', type: 'singleSelect', options: {
          choices: ['Low', 'Medium', 'High', 'Critical']
        }},
        { id: 'fld104', name: 'Due Date', type: 'date' },
        { id: 'fld105', name: 'Hours Estimated', type: 'number' },
        { id: 'fld106', name: 'Hours Actual', type: 'number' }
      ],
      records: [
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Task Name': 'Design mockups',
            'Assignee': 'John Smith',
            'Priority': 'High',
            'Due Date': '2024-02-01',
            'Hours Estimated': 16,
            'Hours Actual': 14
          },
          createdTime: faker.date.past().toISOString()
        },
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Task Name': 'Frontend implementation',
            'Assignee': 'Jane Doe',
            'Priority': 'Medium',
            'Due Date': '2024-02-15',
            'Hours Estimated': 40,
            'Hours Actual': 38
          },
          createdTime: faker.date.past().toISOString()
        }
      ]
    }
  }

  /**
   * Create a Users table
   */
  static createUsersTable(): TestAirtableTable {
    return {
      id: `tbl${faker.string.alphanumeric(14)}`,
      name: 'Users',
      fields: [
        { id: 'fld201', name: 'Name', type: 'singleLineText' },
        { id: 'fld202', name: 'Email', type: 'email' },
        { id: 'fld203', name: 'Role', type: 'singleSelect' },
        { id: 'fld204', name: 'Department', type: 'singleSelect' },
        { id: 'fld205', name: 'Start Date', type: 'date' }
      ],
      records: [
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Name': 'John Smith',
            'Email': 'john.smith@example.com',
            'Role': 'Designer',
            'Department': 'Creative',
            'Start Date': '2023-06-01'
          },
          createdTime: faker.date.past().toISOString()
        },
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Name': 'Jane Doe',
            'Email': 'jane.doe@example.com',
            'Role': 'Developer',
            'Department': 'Engineering',
            'Start Date': '2023-08-15'
          },
          createdTime: faker.date.past().toISOString()
        }
      ]
    }
  }

  /**
   * Create a Facebook Posts table for social media testing
   */
  static createFacebookPostsTable(): TestAirtableTable {
    return {
      id: `tbl${faker.string.alphanumeric(14)}`,
      name: 'Facebook Posts',
      fields: [
        { id: 'fld301', name: 'Post Content', type: 'multilineText' },
        { id: 'fld302', name: 'Post Date', type: 'date' },
        { id: 'fld303', name: 'Engagement', type: 'number' },
        { id: 'fld304', name: 'Reach', type: 'number' },
        { id: 'fld305', name: 'Status', type: 'singleSelect', options: {
          choices: ['Draft', 'Scheduled', 'Published', 'Archived']
        }}
      ],
      records: [
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Post Content': 'Excited to announce our new product launch! 🚀',
            'Post Date': '2024-01-10',
            'Engagement': 245,
            'Reach': 1200,
            'Status': 'Published'
          },
          createdTime: faker.date.past().toISOString()
        },
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Post Content': 'Behind the scenes of our team working on amazing projects',
            'Post Date': '2024-01-08',
            'Engagement': 180,
            'Reach': 950,
            'Status': 'Published'
          },
          createdTime: faker.date.past().toISOString()
        }
      ]
    }
  }

  /**
   * Create working hours table for time tracking tests
   */
  static createWorkingHoursTable(): TestAirtableTable {
    return {
      id: `tbl${faker.string.alphanumeric(14)}`,
      name: 'Working Hours',
      fields: [
        { id: 'fld401', name: 'Date', type: 'date' },
        { id: 'fld402', name: 'Employee', type: 'singleSelect' },
        { id: 'fld403', name: 'Project', type: 'singleSelect' },
        { id: 'fld404', name: 'Hours Worked', type: 'number' },
        { id: 'fld405', name: 'Description', type: 'multilineText' }
      ],
      records: [
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Date': '2024-01-15',
            'Employee': 'John Smith',
            'Project': 'Website Redesign',
            'Hours Worked': 8,
            'Description': 'Created initial design mockups'
          },
          createdTime: faker.date.past().toISOString()
        },
        {
          id: `rec${faker.string.alphanumeric(14)}`,
          fields: {
            'Date': '2024-01-16',
            'Employee': 'Jane Doe',
            'Project': 'Website Redesign',
            'Hours Worked': 6.5,
            'Description': 'Implemented responsive layout'
          },
          createdTime: faker.date.past().toISOString()
        }
      ]
    }
  }

  /**
   * Create chat session data for AI testing
   */
  static createChatSession(overrides: any = {}) {
    return {
      sessionId: `session_${faker.string.alphanumeric(16)}`,
      userId: faker.string.uuid(),
      messages: [
        {
          id: `msg_${faker.string.alphanumeric(12)}`,
          role: 'user',
          content: 'Hello, can you help me analyze my Airtable data?',
          timestamp: faker.date.recent().toISOString()
        },
        {
          id: `msg_${faker.string.alphanumeric(12)}`,
          role: 'assistant',
          content: 'I\'d be happy to help you analyze your Airtable data. What specific information are you looking for?',
          timestamp: faker.date.recent().toISOString()
        }
      ],
      createdAt: faker.date.recent().toISOString(),
      lastActiveAt: faker.date.recent().toISOString(),
      ...overrides
    }
  }

  /**
   * Create API response data for service mocking
   */
  static createApiResponse(data: any, status: 'success' | 'error' = 'success') {
    return {
      status: status,
      data: data,
      timestamp: new Date().toISOString(),
      requestId: faker.string.uuid()
    }
  }

  /**
   * Create service health check response
   */
  static createHealthCheckResponse(serviceName: string, healthy: boolean = true) {
    return {
      service: serviceName,
      status: healthy ? 'healthy' : 'unhealthy',
      version: '1.0.0',
      timestamp: new Date().toISOString(),
      uptime: faker.number.int({ min: 1000, max: 86400 }),
      dependencies: healthy ? [] : ['Database connection failed']
    }
  }

  /**
   * Create error response data
   */
  static createErrorResponse(message: string, code: string = 'GENERIC_ERROR') {
    return {
      error: {
        code: code,
        message: message,
        timestamp: new Date().toISOString(),
        requestId: faker.string.uuid()
      }
    }
  }

  /**
   * Create performance metrics for testing
   */
  static createPerformanceMetrics() {
    return {
      responseTime: faker.number.int({ min: 50, max: 500 }),
      memoryUsage: faker.number.int({ min: 100, max: 1000 }),
      cpuUsage: faker.number.float({ min: 0.1, max: 0.8, precision: 0.01 }),
      activeConnections: faker.number.int({ min: 1, max: 100 }),
      requestsPerSecond: faker.number.int({ min: 10, max: 1000 })
    }
  }

  /**
   * Create load test data
   */
  static createLoadTestScenario(virtualUsers: number = 10, duration: number = 60) {
    return {
      virtualUsers: virtualUsers,
      duration: duration,
      rampUpTime: Math.floor(duration * 0.1),
      endpoints: [
        { path: '/api/health', weight: 10 },
        { path: '/api/chat', weight: 40 },
        { path: '/api/airtable/tables', weight: 30 },
        { path: '/dashboard', weight: 20 }
      ],
      expectedMetrics: {
        maxResponseTime: 2000,
        errorRate: 0.01,
        throughput: virtualUsers * 0.5
      }
    }
  }

  /**
   * Reset all faker seeds for consistent testing
   */
  static resetSeed(seed: number = 12345) {
    faker.seed(seed)
  }

  /**
   * Generate test data for specific scenarios
   */
  static createScenarioData(scenario: string) {
    switch (scenario) {
      case 'facebook_analysis':
        return {
          base: this.createTestAirtableBase({
            tables: [this.createFacebookPostsTable()]
          }),
          expectedAnalysis: {
            totalPosts: 2,
            avgEngagement: 212.5,
            topPerformingPost: 'Excited to announce our new product launch! 🚀',
            recommendations: [
              'Increase posting frequency',
              'Use more engaging visuals',
              'Post during peak hours'
            ]
          }
        }
      
      case 'working_hours':
        return {
          base: this.createTestAirtableBase({
            tables: [this.createWorkingHoursTable(), this.createProjectsTable()]
          }),
          expectedCalculations: {
            totalHours: 14.5,
            projectBreakdown: {
              'Website Redesign': 14.5
            },
            averageHoursPerDay: 7.25
          }
        }
      
      case 'project_status':
        return {
          base: this.createTestAirtableBase({
            tables: [this.createProjectsTable()]
          }),
          expectedSummary: {
            totalProjects: 2,
            inProgressProjects: 1,
            plannedProjects: 1,
            totalBudget: 65000,
            averageBudget: 32500
          }
        }
      
      default:
        return this.createTestAirtableBase()
    }
  }
}