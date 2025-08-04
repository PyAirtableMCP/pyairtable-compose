'use client';

import { SagaInstance, SagaStatus } from '@/types';
import { formatDistanceToNow } from 'date-fns';
import {
  CheckCircleIcon,
  ClockIcon,
  ExclamationTriangleIcon,
  ArrowPathIcon,
  StopIcon,
  PlayIcon
} from '@heroicons/react/24/outline';

interface SagaListProps {
  sagas: SagaInstance[];
  selectedSaga: SagaInstance | null;
  onSagaSelect: (saga: SagaInstance) => void;
  onRetryFailedSteps: (sagaId: string) => void;
  onCompensateSaga: (sagaId: string) => void;
}

export default function SagaList({ 
  sagas, 
  selectedSaga, 
  onSagaSelect, 
  onRetryFailedSteps, 
  onCompensateSaga 
}: SagaListProps) {
  const getStatusIcon = (status: SagaStatus) => {
    switch (status) {
      case SagaStatus.COMPLETED:
        return <CheckCircleIcon className="h-5 w-5 text-green-500" />;
      case SagaStatus.IN_PROGRESS:
        return <ClockIcon className="h-5 w-5 text-blue-500" />;
      case SagaStatus.FAILED:
        return <ExclamationTriangleIcon className="h-5 w-5 text-red-500" />;
      case SagaStatus.COMPENSATING:
        return <ArrowPathIcon className="h-5 w-5 text-yellow-500 animate-spin" />;
      case SagaStatus.COMPENSATED:
        return <StopIcon className="h-5 w-5 text-yellow-600" />;
      default:
        return <PlayIcon className="h-5 w-5 text-gray-500" />;
    }
  };

  const getStatusColor = (status: SagaStatus) => {
    switch (status) {
      case SagaStatus.COMPLETED:
        return 'status-success';
      case SagaStatus.IN_PROGRESS:
        return 'status-info';
      case SagaStatus.FAILED:
        return 'status-error';
      case SagaStatus.COMPENSATING:
        return 'status-warning';
      case SagaStatus.COMPENSATED:
        return 'status-warning';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const getProgressPercentage = (saga: SagaInstance) => {
    const completedSteps = saga.steps.filter(step => 
      step.status === 'COMPLETED' || step.status === 'COMPENSATED'
    ).length;
    return Math.round((completedSteps / saga.steps.length) * 100);
  };

  if (sagas.length === 0) {
    return (
      <div className="card">
        <div className="text-center py-12">
          <PlayIcon className="mx-auto h-12 w-12 text-gray-400" />
          <h3 className="mt-2 text-sm font-medium text-gray-900">No SAGAs found</h3>
          <p className="mt-1 text-sm text-gray-500">
            No SAGAs match your current filters.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="card p-0">
      <div className="px-6 py-4 border-b border-gray-200">
        <h3 className="text-lg font-medium text-gray-900">
          SAGAs ({sagas.length})
        </h3>
      </div>

      <div className="max-h-[800px] overflow-y-auto scrollbar-thin">
        <div className="divide-y divide-gray-200">
          {sagas.map((saga) => (
            <div
              key={saga.id}
              onClick={() => onSagaSelect(saga)}
              className={`px-6 py-4 hover:bg-gray-50 cursor-pointer transition-colors duration-150 ${
                selectedSaga?.id === saga.id ? 'bg-primary-50 border-l-4 border-primary-500' : ''
              }`}
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  {/* SAGA Type and Status */}
                  <div className="flex items-center space-x-3 mb-2">
                    <div className="flex items-center space-x-2">
                      {getStatusIcon(saga.status)}
                      <span className="text-sm font-medium text-gray-900">
                        {saga.sagaType}
                      </span>
                    </div>
                    <span className={`status-badge ${getStatusColor(saga.status)}`}>
                      {saga.status}
                    </span>
                  </div>

                  {/* SAGA ID */}
                  <div className="text-xs text-gray-500 font-mono mb-2">
                    {saga.id}
                  </div>

                  {/* Current Step */}
                  <div className="text-sm text-gray-600 mb-2">
                    Current: <span className="font-medium">{saga.currentStep}</span>
                  </div>

                  {/* Progress Bar */}
                  <div className="mb-2">
                    <div className="flex items-center justify-between text-xs text-gray-500 mb-1">
                      <span>Progress</span>
                      <span>{getProgressPercentage(saga)}%</span>
                    </div>
                    <div className="w-full bg-gray-200 rounded-full h-2">
                      <div
                        className={`h-2 rounded-full transition-all duration-300 ${
                          saga.status === SagaStatus.COMPLETED
                            ? 'bg-green-500'
                            : saga.status === SagaStatus.FAILED
                            ? 'bg-red-500'
                            : 'bg-blue-500'
                        }`}
                        style={{ width: `${getProgressPercentage(saga)}%` }}
                      ></div>
                    </div>
                  </div>

                  {/* Error Message */}
                  {saga.error && (
                    <div className="text-xs text-red-600 bg-red-50 rounded px-2 py-1 mb-2">
                      {saga.error}
                    </div>
                  )}

                  {/* Timestamps */}
                  <div className="flex items-center space-x-4 text-xs text-gray-500">
                    <span>
                      Started {formatDistanceToNow(new Date(saga.startedAt), { addSuffix: true })}
                    </span>
                    <span>•</span>
                    <span>
                      Updated {formatDistanceToNow(new Date(saga.updatedAt), { addSuffix: true })}
                    </span>
                    {saga.completedAt && (
                      <>
                        <span>•</span>
                        <span>
                          Completed {formatDistanceToNow(new Date(saga.completedAt), { addSuffix: true })}
                        </span>
                      </>
                    )}
                  </div>

                  {/* Quick Actions */}
                  {saga.status === SagaStatus.FAILED && (
                    <div className="mt-3 flex space-x-2">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          onRetryFailedSteps(saga.id);
                        }}
                        className="text-xs bg-blue-100 text-blue-800 hover:bg-blue-200 px-2 py-1 rounded transition-colors"
                      >
                        Retry
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          onCompensateSaga(saga.id);
                        }}
                        className="text-xs bg-yellow-100 text-yellow-800 hover:bg-yellow-200 px-2 py-1 rounded transition-colors"
                      >
                        Compensate
                      </button>
                    </div>
                  )}
                </div>

                {/* Step Count Badge */}
                <div className="flex-shrink-0 ml-4">
                  <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                    {saga.steps.length} steps
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}