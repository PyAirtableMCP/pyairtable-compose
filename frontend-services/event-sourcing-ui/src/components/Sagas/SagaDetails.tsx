'use client';

import { useState } from 'react';
import { SagaInstance } from '@/types';
import ReactJsonView from 'react-json-view';
import {
  ClipboardDocumentIcon,
  ArrowPathIcon,
  StopIcon,
  InformationCircleIcon
} from '@heroicons/react/24/outline';
import { toast } from 'react-hot-toast';

interface SagaDetailsProps {
  saga: SagaInstance;
}

export default function SagaDetails({ saga }: SagaDetailsProps) {
  const [activeTab, setActiveTab] = useState<'data' | 'compensation' | 'steps' | 'events'>('data');

  const copyToClipboard = (text: string, type: string) => {
    navigator.clipboard.writeText(text).then(() => {
      toast.success(`${type} copied to clipboard`);
    }).catch(() => {
      toast.error('Failed to copy to clipboard');
    });
  };

  const tabs = [
    { id: 'data', label: 'SAGA Data' },
    { id: 'compensation', label: 'Compensation' },
    { id: 'steps', label: 'Step Details' },
    { id: 'events', label: 'Related Events' }
  ];

  const getStepStatusColor = (status: string) => {
    switch (status) {
      case 'COMPLETED':
        return 'text-green-600 bg-green-100';
      case 'IN_PROGRESS':
        return 'text-blue-600 bg-blue-100';
      case 'FAILED':
        return 'text-red-600 bg-red-100';
      case 'COMPENSATING':
        return 'text-yellow-600 bg-yellow-100';
      case 'COMPENSATED':
        return 'text-yellow-700 bg-yellow-200';
      default:
        return 'text-gray-600 bg-gray-100';
    }
  };

  return (
    <div className="card p-0">
      {/* Header */}
      <div className="px-6 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-medium text-gray-900">SAGA Details</h3>
          <div className="flex space-x-2">
            <button
              onClick={() => copyToClipboard(saga.id, 'SAGA ID')}
              className="text-sm text-gray-500 hover:text-gray-700 flex items-center space-x-1"
            >
              <ClipboardDocumentIcon className="h-4 w-4" />
              <span>Copy ID</span>
            </button>
          </div>
        </div>
      </div>

      {/* SAGA Summary */}
      <div className="px-6 py-4 bg-gray-50 border-b border-gray-200">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 text-sm">
          <div>
            <div className="text-gray-500">SAGA ID</div>
            <div className="font-mono text-gray-900 break-all">{saga.id}</div>
          </div>
          <div>
            <div className="text-gray-500">Type</div>
            <div className="font-medium text-gray-900">{saga.sagaType}</div>
          </div>
          <div>
            <div className="text-gray-500">Status</div>
            <div className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
              saga.status === 'COMPLETED' ? 'bg-green-100 text-green-800' :
              saga.status === 'IN_PROGRESS' ? 'bg-blue-100 text-blue-800' :
              saga.status === 'FAILED' ? 'bg-red-100 text-red-800' :
              saga.status === 'COMPENSATING' ? 'bg-yellow-100 text-yellow-800' :
              'bg-gray-100 text-gray-800'
            }`}>
              {saga.status}
            </div>
          </div>
          <div>
            <div className="text-gray-500">Current Step</div>
            <div className="font-medium text-gray-900">{saga.currentStep}</div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as 'data' | 'compensation' | 'steps' | 'events')}
              className={`py-2 px-4 text-sm font-medium border-b-2 ${
                activeTab === tab.id
                  ? 'border-primary-500 text-primary-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      <div className="px-6 py-4 max-h-96 overflow-y-auto scrollbar-thin">
        {activeTab === 'data' && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium text-gray-900">SAGA Data</h4>
              <button
                onClick={() => copyToClipboard(JSON.stringify(saga.data, null, 2), 'SAGA data')}
                className="text-sm text-primary-600 hover:text-primary-900 flex items-center space-x-1"
              >
                <ClipboardDocumentIcon className="h-4 w-4" />
                <span>Copy</span>
              </button>
            </div>
            {Object.keys(saga.data).length > 0 ? (
              <ReactJsonView
                src={saga.data}
                theme="bright:inverted"
                name={false}
                collapsed={false}
                displayDataTypes={false}
                displayObjectSize={false}
                enableClipboard={false}
                style={{ backgroundColor: 'transparent', fontSize: '12px' }}
              />
            ) : (
              <div className="text-sm text-gray-500 italic">No data available</div>
            )}
          </div>
        )}

        {activeTab === 'compensation' && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium text-gray-900">Compensation Data</h4>
              {saga.compensationData && (
                <button
                  onClick={() => copyToClipboard(JSON.stringify(saga.compensationData, null, 2), 'Compensation data')}
                  className="text-sm text-primary-600 hover:text-primary-900 flex items-center space-x-1"
                >
                  <ClipboardDocumentIcon className="h-4 w-4" />
                  <span>Copy</span>
                </button>
              )}
            </div>
            {saga.compensationData && Object.keys(saga.compensationData).length > 0 ? (
              <ReactJsonView
                src={saga.compensationData}
                theme="bright:inverted"
                name={false}
                collapsed={false}
                displayDataTypes={false}
                displayObjectSize={false}
                enableClipboard={false}
                style={{ backgroundColor: 'transparent', fontSize: '12px' }}
              />
            ) : (
              <div className="text-sm text-gray-500 italic">
                No compensation data available
              </div>
            )}
          </div>
        )}

        {activeTab === 'steps' && (
          <div>
            <h4 className="text-sm font-medium text-gray-900 mb-4">Step Details</h4>
            <div className="space-y-4">
              {saga.steps.map((step, index) => (
                <div key={step.id} className="border border-gray-200 rounded-lg p-4">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center space-x-3">
                      <span className="text-sm font-medium text-gray-900">
                        {index + 1}. {step.name}
                      </span>
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getStepStatusColor(step.status)}`}>
                        {step.status}
                      </span>
                    </div>
                    {step.compensated && (
                      <span className="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-yellow-100 text-yellow-800">
                        Compensated
                      </span>
                    )}
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
                    <div>
                      <div className="text-gray-500">Started</div>
                      <div className="text-gray-900">
                        {step.startedAt ? new Date(step.startedAt).toLocaleString() : 'Not started'}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500">Completed</div>
                      <div className="text-gray-900">
                        {step.completedAt ? new Date(step.completedAt).toLocaleString() : 'Not completed'}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500">Retries</div>
                      <div className="text-gray-900">
                        {step.retryCount}/{step.maxRetries}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500">Duration</div>
                      <div className="text-gray-900">
                        {step.startedAt && step.completedAt
                          ? `${Math.round((new Date(step.completedAt).getTime() - new Date(step.startedAt).getTime()) / 1000)}s`
                          : step.startedAt
                          ? `${Math.round((new Date().getTime() - new Date(step.startedAt).getTime()) / 1000)}s`
                          : 'N/A'
                        }
                      </div>
                    </div>
                  </div>

                  {step.error && (
                    <div className="mt-3 p-3 bg-red-50 border border-red-200 rounded text-sm text-red-700">
                      <div className="font-medium">Error:</div>
                      <div>{step.error}</div>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {activeTab === 'events' && (
          <div>
            <h4 className="text-sm font-medium text-gray-900 mb-4">Related Events</h4>
            <div className="text-center py-8">
              <InformationCircleIcon className="mx-auto h-12 w-12 text-gray-400" />
              <h3 className="mt-2 text-sm font-medium text-gray-900">Events Coming Soon</h3>
              <p className="mt-1 text-sm text-gray-500">
                Related events for this SAGA will be displayed here.
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Actions */}
      <div className="px-6 py-4 border-t border-gray-200 bg-gray-50">
        <div className="flex justify-between">
          <div className="flex space-x-3">
            {saga.status === 'FAILED' && (
              <>
                <button className="btn-primary flex items-center space-x-2">
                  <ArrowPathIcon className="h-4 w-4" />
                  <span>Retry Failed Steps</span>
                </button>
                <button className="btn-secondary flex items-center space-x-2">
                  <StopIcon className="h-4 w-4" />
                  <span>Compensate</span>
                </button>
              </>
            )}
            {saga.status === 'IN_PROGRESS' && (
              <button className="btn-danger flex items-center space-x-2">
                <StopIcon className="h-4 w-4" />
                <span>Cancel SAGA</span>
              </button>
            )}
          </div>
          <button
            onClick={() => copyToClipboard(JSON.stringify(saga, null, 2), 'Full SAGA data')}
            className="text-sm text-gray-500 hover:text-gray-700"
          >
            Export SAGA
          </button>
        </div>
      </div>
    </div>
  );
}