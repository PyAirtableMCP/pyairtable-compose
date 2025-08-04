'use client';

import { useState } from 'react';
import MainLayout from '@/components/Layout/MainLayout';
import EventSchemaBrowser from '@/components/DevTools/EventSchemaBrowser';
import EventTester from '@/components/DevTools/EventTester';
import EventSimulator from '@/components/DevTools/EventSimulator';
import PerformanceProfiler from '@/components/DevTools/PerformanceProfiler';
import { EventSchema, EventTest, TestStatus } from '@/types';
import {
  CodeBracketIcon,
  PlayIcon,
  ChartBarIcon,
  CpuChipIcon,
  BeakerIcon
} from '@heroicons/react/24/outline';

// Mock event schemas
const mockSchemas: EventSchema[] = [
  {
    eventType: 'UserRegistered',
    version: '1.0.0',
    description: 'Event fired when a new user registers in the system',
    schema: {
      type: 'object',
      properties: {
        userId: { type: 'string', description: 'Unique identifier for the user' },
        email: { type: 'string', description: 'User email address' },
        name: { type: 'string', description: 'User full name' },
        plan: { type: 'string', description: 'Subscription plan', enum: ['free', 'premium', 'enterprise'] },
        registeredAt: { type: 'string', description: 'ISO timestamp of registration' }
      },
      required: ['userId', 'email', 'name', 'plan', 'registeredAt']
    },
    examples: [
      {
        userId: 'user-123',
        email: 'john.doe@example.com',
        name: 'John Doe',
        plan: 'premium',
        registeredAt: '2024-01-15T10:30:00Z'
      }
    ]
  },
  {
    eventType: 'PaymentProcessed',
    version: '2.1.0',
    description: 'Event fired when a payment is successfully processed',
    schema: {
      type: 'object',
      properties: {
        paymentId: { type: 'string', description: 'Unique payment identifier' },
        orderId: { type: 'string', description: 'Associated order identifier' },
        amount: { type: 'number', description: 'Payment amount' },
        currency: { type: 'string', description: 'Currency code (ISO 4217)' },
        paymentMethod: { type: 'string', description: 'Payment method used' },
        processedAt: { type: 'string', description: 'ISO timestamp of processing' },
        fees: {
          type: 'object',
          properties: {
            platform: { type: 'number', description: 'Platform fee' },
            processing: { type: 'number', description: 'Processing fee' }
          }
        }
      },
      required: ['paymentId', 'orderId', 'amount', 'currency', 'paymentMethod', 'processedAt']
    },
    examples: [
      {
        paymentId: 'pay-456',
        orderId: 'order-789',
        amount: 99.99,
        currency: 'USD',
        paymentMethod: 'credit_card',
        processedAt: '2024-01-15T11:15:00Z',
        fees: {
          platform: 2.99,
          processing: 0.30
        }
      }
    ]
  },
  {
    eventType: 'WorkspaceCreated',
    version: '1.2.0',
    description: 'Event fired when a new workspace is created',
    schema: {
      type: 'object',
      properties: {
        workspaceId: { type: 'string', description: 'Unique workspace identifier' },
        name: { type: 'string', description: 'Workspace name' },
        ownerId: { type: 'string', description: 'Owner user ID' },
        plan: { type: 'string', description: 'Workspace plan', enum: ['personal', 'team', 'enterprise'] },
        settings: {
          type: 'object',
          properties: {
            isPublic: { type: 'boolean', description: 'Whether workspace is public' },
            allowGuests: { type: 'boolean', description: 'Whether guests are allowed' },
            defaultPermissions: { type: 'string', description: 'Default permission level' }
          }
        },
        createdAt: { type: 'string', description: 'ISO timestamp of creation' }
      },
      required: ['workspaceId', 'name', 'ownerId', 'plan', 'createdAt']
    },
    examples: [
      {
        workspaceId: 'ws-321',
        name: 'My Team Workspace',
        ownerId: 'user-123',
        plan: 'team',
        settings: {
          isPublic: false,
          allowGuests: true,
          defaultPermissions: 'read'
        },
        createdAt: '2024-01-15T12:00:00Z'
      }
    ]
  }
];

// Mock event tests
const mockTests: EventTest[] = [
  {
    id: 'test-1',
    name: 'User Registration Flow',
    eventType: 'UserRegistered',
    aggregateId: 'user-test-123',
    data: {
      userId: 'user-test-123',
      email: 'test@example.com',
      name: 'Test User',
      plan: 'premium',
      registeredAt: new Date().toISOString()
    },
    expectedOutcome: 'User aggregate created, welcome email queued, workspace initialized',
    status: TestStatus.PASSED,
    result: {
      success: true,
      message: 'All expected events were generated successfully',
      executionTime: 245
    }
  },
  {
    id: 'test-2',
    name: 'Payment Processing Validation',
    eventType: 'PaymentProcessed',
    aggregateId: 'payment-test-456',
    data: {
      paymentId: 'pay-test-456',
      orderId: 'order-test-789',
      amount: 0, // Invalid amount
      currency: 'USD',
      paymentMethod: 'credit_card',
      processedAt: new Date().toISOString()
    },
    expectedOutcome: 'Payment validation should fail for zero amount',
    status: TestStatus.FAILED,
    result: {
      success: false,
      message: 'Payment amount must be greater than zero',
      executionTime: 12
    }
  }
];

type ActiveTab = 'schemas' | 'tester' | 'simulator' | 'profiler';

interface TabButtonProps {
  id: ActiveTab;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  activeTab: ActiveTab;
  onClick: (tab: ActiveTab) => void;
  badge?: string | number;
}

function TabButton({ id, label, icon: Icon, activeTab, onClick, badge }: TabButtonProps) {
  return (
    <button
      onClick={() => onClick(id)}
      className={`flex items-center space-x-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
        activeTab === id
          ? 'bg-primary-100 text-primary-700 border border-primary-200'
          : 'text-gray-600 hover:text-gray-900 hover:bg-gray-100'
      }`}
    >
      <Icon className="h-4 w-4" />
      <span>{label}</span>
      {badge && (
        <span className="bg-primary-500 text-white text-xs rounded-full px-2 py-1">
          {badge}
        </span>
      )}
    </button>
  );
}

export default function DevToolsPage() {
  const [activeTab, setActiveTab] = useState<ActiveTab>('schemas');
  const [schemas] = useState<EventSchema[]>(mockSchemas);
  const [tests, setTests] = useState<EventTest[]>(mockTests);

  const handleRunTest = async (test: EventTest) => {
    setTests(prev => prev.map(t => 
      t.id === test.id 
        ? { ...t, status: TestStatus.RUNNING }
        : t
    ));

    // Simulate test execution
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Simulate test result
    const success = Math.random() > 0.3; // 70% success rate
    setTests(prev => prev.map(t => 
      t.id === test.id 
        ? { 
            ...t, 
            status: success ? TestStatus.PASSED : TestStatus.FAILED,
            result: {
              success,
              message: success 
                ? 'Test completed successfully' 
                : 'Test failed: Validation error',
              executionTime: Math.floor(Math.random() * 500) + 100
            }
          }
        : t
    ));
  };

  const handleCreateTest = (test: Omit<EventTest, 'id' | 'status'>) => {
    const newTest: EventTest = {
      ...test,
      id: `test-${Date.now()}`,
      status: TestStatus.PENDING
    };
    setTests(prev => [...prev, newTest]);
  };

  const failedTests = tests.filter(t => t.status === TestStatus.FAILED).length;
  const runningTests = tests.filter(t => t.status === TestStatus.RUNNING).length;

  return (
    <MainLayout>
      <div className="space-y-6">
        {/* Header */}
        <div className="border-b border-gray-200 pb-5">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold leading-7 text-gray-900">Developer Tools</h1>
              <p className="mt-1 text-sm text-gray-500">
                Event schema browser, testing interface, simulation tools, and performance profiling
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <div className="text-sm text-gray-600">
                {schemas.length} schemas • {tests.length} tests
              </div>
            </div>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="flex flex-wrap gap-2">
          <TabButton
            id="schemas"
            label="Event Schemas"
            icon={CodeBracketIcon}
            activeTab={activeTab}
            onClick={setActiveTab}
            badge={schemas.length}
          />
          <TabButton
            id="tester"
            label="Event Tester"
            icon={BeakerIcon}
            activeTab={activeTab}
            onClick={setActiveTab}
            badge={failedTests > 0 ? failedTests : undefined}
          />
          <TabButton
            id="simulator"
            label="Event Simulator"
            icon={PlayIcon}
            activeTab={activeTab}
            onClick={setActiveTab}
            badge={runningTests > 0 ? runningTests : undefined}
          />
          <TabButton
            id="profiler"
            label="Performance Profiler"
            icon={CpuChipIcon}
            activeTab={activeTab}
            onClick={setActiveTab}
          />
        </div>

        {/* Tab Content */}
        <div className="min-h-[600px]">
          {activeTab === 'schemas' && (
            <EventSchemaBrowser schemas={schemas} />
          )}
          
          {activeTab === 'tester' && (
            <EventTester 
              tests={tests}
              schemas={schemas}
              onRunTest={handleRunTest}
              onCreateTest={handleCreateTest}
            />
          )}
          
          {activeTab === 'simulator' && (
            <EventSimulator schemas={schemas} />
          )}
          
          {activeTab === 'profiler' && (
            <PerformanceProfiler />
          )}
        </div>
      </div>
    </MainLayout>
  );
}