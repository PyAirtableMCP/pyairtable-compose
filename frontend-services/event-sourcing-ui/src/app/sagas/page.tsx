'use client';

import { useState, useEffect } from 'react';
import MainLayout from '@/components/Layout/MainLayout';
import SagaList from '@/components/Sagas/SagaList';
import SagaDetails from '@/components/Sagas/SagaDetails';
import SagaStateMachine from '@/components/Sagas/SagaStateMachine';
import { SagaInstance, SagaStatus, SagaStepStatus } from '@/types';
import {
  PlayIcon,
  PauseIcon,
  StopIcon,
  ArrowPathIcon,
  ExclamationTriangleIcon,
  CheckCircleIcon,
  ClockIcon
} from '@heroicons/react/24/outline';

// Mock SAGA data
const mockSagas: SagaInstance[] = [
  {
    id: 'saga-1',
    sagaType: 'UserRegistrationSaga',
    status: SagaStatus.IN_PROGRESS,
    currentStep: 'ValidateEmail',
    startedAt: new Date(Date.now() - 300000), // 5 minutes ago
    updatedAt: new Date(Date.now() - 30000), // 30 seconds ago
    data: {
      userId: 'user-123',
      email: 'user@example.com',
      plan: 'premium'
    },
    steps: [
      {
        id: 'step-1',
        name: 'CreateUser',
        status: SagaStepStatus.COMPLETED,
        startedAt: new Date(Date.now() - 300000),
        completedAt: new Date(Date.now() - 240000),
        retryCount: 0,
        maxRetries: 3
      },
      {
        id: 'step-2',
        name: 'ValidateEmail',
        status: SagaStepStatus.IN_PROGRESS,
        startedAt: new Date(Date.now() - 240000),
        retryCount: 1,
        maxRetries: 3
      },
      {
        id: 'step-3',
        name: 'SendWelcomeEmail',
        status: SagaStepStatus.PENDING,
        retryCount: 0,
        maxRetries: 3
      },
      {
        id: 'step-4',
        name: 'CreateWorkspace',
        status: SagaStepStatus.PENDING,
        retryCount: 0,
        maxRetries: 3
      }
    ]
  },
  {
    id: 'saga-2',
    sagaType: 'PaymentProcessingSaga',
    status: SagaStatus.COMPLETED,
    currentStep: 'ProcessPayment',
    startedAt: new Date(Date.now() - 600000), // 10 minutes ago
    updatedAt: new Date(Date.now() - 120000), // 2 minutes ago
    completedAt: new Date(Date.now() - 120000),
    data: {
      orderId: 'order-456',
      amount: 99.99,
      currency: 'USD'
    },
    steps: [
      {
        id: 'step-1',
        name: 'ValidateOrder',
        status: SagaStepStatus.COMPLETED,
        startedAt: new Date(Date.now() - 600000),
        completedAt: new Date(Date.now() - 540000),
        retryCount: 0,
        maxRetries: 3
      },
      {
        id: 'step-2',
        name: 'ProcessPayment',
        status: SagaStepStatus.COMPLETED,
        startedAt: new Date(Date.now() - 540000),
        completedAt: new Date(Date.now() - 480000),
        retryCount: 0,
        maxRetries: 3
      },
      {
        id: 'step-3',
        name: 'UpdateInventory',
        status: SagaStepStatus.COMPLETED,
        startedAt: new Date(Date.now() - 480000),
        completedAt: new Date(Date.now() - 420000),
        retryCount: 0,
        maxRetries: 3
      },
      {
        id: 'step-4',
        name: 'SendConfirmation',
        status: SagaStepStatus.COMPLETED,
        startedAt: new Date(Date.now() - 420000),
        completedAt: new Date(Date.now() - 120000),
        retryCount: 0,
        maxRetries: 3
      }
    ]
  },
  {
    id: 'saga-3',
    sagaType: 'DataImportSaga',
    status: SagaStatus.FAILED,
    currentStep: 'ProcessData',
    startedAt: new Date(Date.now() - 900000), // 15 minutes ago
    updatedAt: new Date(Date.now() - 60000), // 1 minute ago
    data: {
      importId: 'import-789',
      fileName: 'data.csv',
      recordCount: 10000
    },
    error: 'Failed to validate data format on row 5432',
    steps: [
      {
        id: 'step-1',
        name: 'ValidateFile',
        status: SagaStepStatus.COMPLETED,
        startedAt: new Date(Date.now() - 900000),
        completedAt: new Date(Date.now() - 840000),
        retryCount: 0,
        maxRetries: 3
      },
      {
        id: 'step-2',
        name: 'ProcessData',
        status: SagaStepStatus.FAILED,
        startedAt: new Date(Date.now() - 840000),
        retryCount: 3,
        maxRetries: 3,
        error: 'Failed to validate data format on row 5432'
      }
    ]
  }
];

interface MetricsCardProps {
  title: string;
  value: number;
  icon: React.ComponentType<{ className?: string }>;
  color: string;
}

function MetricsCard({ title, value, icon: Icon, color }: MetricsCardProps) {
  return (
    <div className="card">
      <div className="flex items-center">
        <div className="flex-shrink-0">
          <Icon className={`h-8 w-8 ${color}`} />
        </div>
        <div className="ml-5 w-0 flex-1">
          <dl>
            <dt className="text-sm font-medium text-gray-500 truncate">{title}</dt>
            <dd className="text-2xl font-semibold text-gray-900">{value}</dd>
          </dl>
        </div>
      </div>
    </div>
  );
}

export default function SagasPage() {
  const [sagas, setSagas] = useState<SagaInstance[]>(mockSagas);
  const [selectedSaga, setSelectedSaga] = useState<SagaInstance | null>(null);
  const [statusFilter, setStatusFilter] = useState<SagaStatus | 'ALL'>('ALL');
  const [sagaTypeFilter, setSagaTypeFilter] = useState<string>('ALL');
  const [isAutoRefresh, setIsAutoRefresh] = useState(true);

  // Filter sagas based on status and type
  const filteredSagas = sagas.filter(saga => {
    if (statusFilter !== 'ALL' && saga.status !== statusFilter) return false;
    if (sagaTypeFilter !== 'ALL' && saga.sagaType !== sagaTypeFilter) return false;
    return true;
  });

  // Calculate metrics
  const metrics = {
    total: sagas.length,
    running: sagas.filter(s => s.status === SagaStatus.IN_PROGRESS).length,
    completed: sagas.filter(s => s.status === SagaStatus.COMPLETED).length,
    failed: sagas.filter(s => s.status === SagaStatus.FAILED).length,
    compensating: sagas.filter(s => s.status === SagaStatus.COMPENSATING).length
  };

  // Get unique saga types
  const sagaTypes = Array.from(new Set(sagas.map(s => s.sagaType)));

  // Auto-refresh effect
  useEffect(() => {
    if (!isAutoRefresh) return;

    const interval = setInterval(() => {
      // Simulate saga updates
      setSagas(prevSagas => 
        prevSagas.map(saga => {
          if (saga.status === SagaStatus.IN_PROGRESS && Math.random() > 0.8) {
            // Randomly progress or complete sagas
            const updatedSaga = { ...saga };
            if (Math.random() > 0.5) {
              // Progress to next step
              const currentStepIndex = saga.steps.findIndex(s => s.status === SagaStepStatus.IN_PROGRESS);
              if (currentStepIndex !== -1 && currentStepIndex < saga.steps.length - 1) {
                updatedSaga.steps = saga.steps.map((step, index) => {
                  if (index === currentStepIndex) {
                    return { ...step, status: SagaStepStatus.COMPLETED, completedAt: new Date() };
                  } else if (index === currentStepIndex + 1) {
                    return { ...step, status: SagaStepStatus.IN_PROGRESS, startedAt: new Date() };
                  }
                  return step;
                });
                updatedSaga.currentStep = saga.steps[currentStepIndex + 1].name;
              }
            } else {
              // Complete saga
              updatedSaga.status = SagaStatus.COMPLETED;
              updatedSaga.completedAt = new Date();
            }
            updatedSaga.updatedAt = new Date();
            return updatedSaga;
          }
          return saga;
        })
      );
    }, 3000);

    return () => clearInterval(interval);
  }, [isAutoRefresh]);

  const handleRetryFailedSteps = (sagaId: string) => {
    setSagas(prevSagas =>
      prevSagas.map(saga => {
        if (saga.id === sagaId) {
          const updatedSteps = saga.steps.map(step => {
            if (step.status === SagaStepStatus.FAILED) {
              return {
                ...step,
                status: SagaStepStatus.PENDING,
                error: undefined,
                retryCount: 0
              };
            }
            return step;
          });
          
          return {
            ...saga,
            status: SagaStatus.IN_PROGRESS,
            steps: updatedSteps,
            error: undefined,
            updatedAt: new Date()
          };
        }
        return saga;
      })
    );
  };

  const handleCompensateSaga = (sagaId: string) => {
    setSagas(prevSagas =>
      prevSagas.map(saga => {
        if (saga.id === sagaId) {
          return {
            ...saga,
            status: SagaStatus.COMPENSATING,
            updatedAt: new Date()
          };
        }
        return saga;
      })
    );
  };

  return (
    <MainLayout>
      <div className="space-y-6">
        {/* Header */}
        <div className="border-b border-gray-200 pb-5">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold leading-7 text-gray-900">SAGA Monitor</h1>
              <p className="mt-1 text-sm text-gray-500">
                Monitor and manage distributed transaction sagas
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <button
                onClick={() => setIsAutoRefresh(!isAutoRefresh)}
                className={`flex items-center space-x-2 px-3 py-2 rounded-md text-sm font-medium ${
                  isAutoRefresh
                    ? 'bg-green-100 text-green-800 hover:bg-green-200'
                    : 'bg-gray-100 text-gray-800 hover:bg-gray-200'
                }`}
              >
                {isAutoRefresh ? (
                  <>
                    <PauseIcon className="h-4 w-4" />
                    <span>Pause</span>
                  </>
                ) : (
                  <>
                    <PlayIcon className="h-4 w-4" />
                    <span>Resume</span>
                  </>
                )}
              </button>
              <button className="btn-secondary flex items-center space-x-2">
                <ArrowPathIcon className="h-4 w-4" />
                <span>Refresh</span>
              </button>
            </div>
          </div>
        </div>

        {/* Metrics */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
          <MetricsCard
            title="Total SAGAs"
            value={metrics.total}
            icon={PlayIcon}
            color="text-gray-400"
          />
          <MetricsCard
            title="Running"
            value={metrics.running}
            icon={ClockIcon}
            color="text-blue-400"
          />
          <MetricsCard
            title="Completed"
            value={metrics.completed}
            icon={CheckCircleIcon}
            color="text-green-400"
          />
          <MetricsCard
            title="Failed"
            value={metrics.failed}
            icon={ExclamationTriangleIcon}
            color="text-red-400"
          />
          <MetricsCard
            title="Compensating"
            value={metrics.compensating}
            icon={ArrowPathIcon}
            color="text-yellow-400"
          />
        </div>

        {/* Filters */}
        <div className="flex flex-wrap gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Status
            </label>
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as SagaStatus | 'ALL')}
              className="input-field"
            >
              <option value="ALL">All Statuses</option>
              <option value={SagaStatus.IN_PROGRESS}>In Progress</option>
              <option value={SagaStatus.COMPLETED}>Completed</option>
              <option value={SagaStatus.FAILED}>Failed</option>
              <option value={SagaStatus.COMPENSATING}>Compensating</option>
              <option value={SagaStatus.COMPENSATED}>Compensated</option>
            </select>
          </div>
          
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              SAGA Type
            </label>
            <select
              value={sagaTypeFilter}
              onChange={(e) => setSagaTypeFilter(e.target.value)}
              className="input-field"
            >
              <option value="ALL">All Types</option>
              {sagaTypes.map(type => (
                <option key={type} value={type}>
                  {type}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Main Content */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* SAGA List */}
          <div className="lg:col-span-1">
            <SagaList
              sagas={filteredSagas}
              selectedSaga={selectedSaga}
              onSagaSelect={setSelectedSaga}
              onRetryFailedSteps={handleRetryFailedSteps}
              onCompensateSaga={handleCompensateSaga}
            />
          </div>

          {/* SAGA Details and State Machine */}
          <div className="lg:col-span-2 space-y-6">
            {selectedSaga && (
              <>
                <SagaStateMachine saga={selectedSaga} />
                <SagaDetails saga={selectedSaga} />
              </>
            )}
            {!selectedSaga && (
              <div className="card">
                <div className="text-center py-12">
                  <PlayIcon className="mx-auto h-12 w-12 text-gray-400" />
                  <h3 className="mt-2 text-sm font-medium text-gray-900">No SAGA selected</h3>
                  <p className="mt-1 text-sm text-gray-500">
                    Select a SAGA from the list to view its details and state machine.
                  </p>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </MainLayout>
  );
}