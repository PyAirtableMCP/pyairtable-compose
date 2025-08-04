'use client';

import { SagaInstance, SagaStepStatus } from '@/types';
import {
  CheckCircleIcon,
  ClockIcon,
  ExclamationTriangleIcon,
  ArrowRightIcon,
  PlayIcon,
  PauseIcon
} from '@heroicons/react/24/outline';

interface SagaStateMachineProps {
  saga: SagaInstance;
}

export default function SagaStateMachine({ saga }: SagaStateMachineProps) {
  const getStepIcon = (status: SagaStepStatus) => {
    switch (status) {
      case SagaStepStatus.COMPLETED:
        return <CheckCircleIcon className="h-6 w-6 text-green-500" />;
      case SagaStepStatus.IN_PROGRESS:
        return <ClockIcon className="h-6 w-6 text-blue-500 animate-pulse" />;
      case SagaStepStatus.FAILED:
        return <ExclamationTriangleIcon className="h-6 w-6 text-red-500" />;
      case SagaStepStatus.COMPENSATING:
        return <ArrowRightIcon className="h-6 w-6 text-yellow-500 animate-pulse transform rotate-180" />;
      case SagaStepStatus.COMPENSATED:
        return <CheckCircleIcon className="h-6 w-6 text-yellow-600" />;
      case SagaStepStatus.PENDING:
        return <PauseIcon className="h-6 w-6 text-gray-400" />;
      default:
        return <PlayIcon className="h-6 w-6 text-gray-400" />;
    }
  };

  const getStepColor = (status: SagaStepStatus) => {
    switch (status) {
      case SagaStepStatus.COMPLETED:
        return 'border-green-300 bg-green-50';
      case SagaStepStatus.IN_PROGRESS:
        return 'border-blue-300 bg-blue-50 ring-2 ring-blue-200';
      case SagaStepStatus.FAILED:
        return 'border-red-300 bg-red-50';
      case SagaStepStatus.COMPENSATING:
        return 'border-yellow-300 bg-yellow-50 ring-2 ring-yellow-200';
      case SagaStepStatus.COMPENSATED:
        return 'border-yellow-400 bg-yellow-100';
      case SagaStepStatus.PENDING:
        return 'border-gray-200 bg-gray-50';
      default:
        return 'border-gray-200 bg-white';
    }
  };

  const getConnectorColor = (currentStatus: SagaStepStatus, nextStatus?: SagaStepStatus) => {
    if (currentStatus === SagaStepStatus.COMPLETED && nextStatus === SagaStepStatus.IN_PROGRESS) {
      return 'bg-blue-400';
    }
    if (currentStatus === SagaStepStatus.COMPLETED) {
      return 'bg-green-400';
    }
    if (currentStatus === SagaStepStatus.FAILED) {
      return 'bg-red-400';
    }
    return 'bg-gray-300';
  };

  const formatDuration = (start?: Date, end?: Date) => {
    if (!start) return 'Not started';
    if (!end) return 'In progress';
    
    const duration = new Date(end).getTime() - new Date(start).getTime();
    const seconds = Math.floor(duration / 1000);
    const minutes = Math.floor(seconds / 60);
    
    if (minutes > 0) {
      return `${minutes}m ${seconds % 60}s`;
    }
    return `${seconds}s`;
  };

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-medium text-gray-900">State Machine</h3>
        <div className="text-sm text-gray-500">
          {saga.sagaType} • {saga.steps.length} steps
        </div>
      </div>

      {/* Desktop Flow View */}
      <div className="hidden lg:block">
        <div className="flex items-center space-x-4 overflow-x-auto pb-4">
          {saga.steps.map((step, index) => (
            <div key={step.id} className="flex items-center space-x-4 flex-shrink-0">
              {/* Step Node */}
              <div className="flex flex-col items-center">
                <div className={`relative rounded-lg border-2 p-4 min-w-[200px] ${getStepColor(step.status)}`}>
                  <div className="flex items-center space-x-3">
                    {getStepIcon(step.status)}
                    <div className="flex-1">
                      <div className="font-medium text-gray-900">{step.name}</div>
                      <div className="text-xs text-gray-500 mt-1">
                        {formatDuration(step.startedAt, step.completedAt)}
                      </div>
                      {step.retryCount > 0 && (
                        <div className="text-xs text-orange-600 mt-1">
                          Retry {step.retryCount}/{step.maxRetries}
                        </div>
                      )}
                    </div>
                  </div>
                  
                  {step.error && (
                    <div className="mt-2 text-xs text-red-600 bg-red-100 rounded px-2 py-1">
                      {step.error}
                    </div>
                  )}
                  
                  {step.compensated && (
                    <div className="absolute -top-2 -right-2 bg-yellow-500 text-white text-xs rounded-full px-2 py-1">
                      Compensated
                    </div>
                  )}
                </div>
              </div>

              {/* Connector */}
              {index < saga.steps.length - 1 && (
                <div className="flex items-center">
                  <div className={`h-0.5 w-8 ${getConnectorColor(step.status, saga.steps[index + 1]?.status)}`}></div>
                  <ArrowRightIcon className="h-4 w-4 text-gray-400 ml-1" />
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Mobile/Tablet Vertical View */}
      <div className="lg:hidden">
        <div className="space-y-4">
          {saga.steps.map((step, index) => (
            <div key={step.id}>
              <div className={`rounded-lg border-2 p-4 ${getStepColor(step.status)}`}>
                <div className="flex items-start space-x-3">
                  {getStepIcon(step.status)}
                  <div className="flex-1">
                    <div className="flex items-center justify-between">
                      <div className="font-medium text-gray-900">{step.name}</div>
                      <div className="text-xs text-gray-500">
                        Step {index + 1}
                      </div>
                    </div>
                    
                    <div className="mt-1 text-sm text-gray-600">
                      Duration: {formatDuration(step.startedAt, step.completedAt)}
                    </div>
                    
                    {step.retryCount > 0 && (
                      <div className="mt-1 text-sm text-orange-600">
                        Retries: {step.retryCount}/{step.maxRetries}
                      </div>
                    )}
                    
                    {step.error && (
                      <div className="mt-2 text-sm text-red-600 bg-red-100 rounded px-2 py-1">
                        {step.error}
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Vertical Connector */}
              {index < saga.steps.length - 1 && (
                <div className="flex justify-center py-2">
                  <div className={`w-0.5 h-6 ${getConnectorColor(step.status, saga.steps[index + 1]?.status)}`}></div>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Timeline Summary */}
      <div className="mt-6 pt-6 border-t border-gray-200">
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 text-sm">
          <div>
            <div className="text-gray-500">Started</div>
            <div className="font-medium">{new Date(saga.startedAt).toLocaleString()}</div>
          </div>
          <div>
            <div className="text-gray-500">Last Updated</div>
            <div className="font-medium">{new Date(saga.updatedAt).toLocaleString()}</div>
          </div>
          <div>
            <div className="text-gray-500">Duration</div>
            <div className="font-medium">
              {formatDuration(saga.startedAt, saga.completedAt || new Date())}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}