'use client';

import { useState } from 'react';
import { Projection, ProjectionStatus } from '@/types';
import {
  PlayIcon,
  StopIcon,
  ArrowPathIcon,
  TrashIcon,
  DocumentTextIcon,
  Cog6ToothIcon
} from '@heroicons/react/24/outline';
import { toast } from 'react-hot-toast';

interface ProjectionControlsProps {
  projection: Projection;
  onAction: (name: string, action: 'start' | 'stop' | 'rebuild' | 'reset') => void;
}

export default function ProjectionControls({ projection, onAction }: ProjectionControlsProps) {
  const [showConfirmModal, setShowConfirmModal] = useState<string | null>(null);

  const handleAction = (action: 'start' | 'stop' | 'rebuild' | 'reset') => {
    // Show confirmation for destructive actions
    if (action === 'rebuild' || action === 'reset') {
      setShowConfirmModal(action);
      return;
    }

    onAction(projection.name, action);
    
    switch (action) {
      case 'start':
        toast.success(`Started ${projection.name}`);
        break;
      case 'stop':
        toast.success(`Stopped ${projection.name}`);
        break;
    }
  };

  const confirmAction = (action: 'rebuild' | 'reset') => {
    onAction(projection.name, action);
    setShowConfirmModal(null);
    
    switch (action) {
      case 'rebuild':
        toast.success(`Rebuilding ${projection.name}`);
        break;
      case 'reset':
        toast.success(`Reset ${projection.name}`);
        break;
    }
  };

  const canStart = projection.status === ProjectionStatus.STOPPED || projection.status === ProjectionStatus.ERROR;
  const canStop = projection.status === ProjectionStatus.RUNNING || projection.status === ProjectionStatus.REBUILDING;
  const canRebuild = projection.status !== ProjectionStatus.REBUILDING;

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-medium text-gray-900">Controls</h3>
        <div className="text-sm text-gray-500">
          {projection.name}
        </div>
      </div>

      <div className="space-y-4">
        {/* Primary Actions */}
        <div className="space-y-3">
          {canStart && (
            <button
              onClick={() => handleAction('start')}
              className="w-full btn-primary flex items-center justify-center space-x-2"
            >
              <PlayIcon className="h-4 w-4" />
              <span>Start Projection</span>
            </button>
          )}

          {canStop && (
            <button
              onClick={() => handleAction('stop')}
              className="w-full btn-danger flex items-center justify-center space-x-2"
            >
              <StopIcon className="h-4 w-4" />
              <span>Stop Projection</span>
            </button>
          )}
        </div>

        {/* Secondary Actions */}
        <div className="border-t border-gray-200 pt-4">
          <div className="space-y-2">
            <button
              onClick={() => handleAction('rebuild')}
              disabled={!canRebuild}
              className={`w-full flex items-center justify-center space-x-2 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
                canRebuild
                  ? 'bg-blue-100 text-blue-800 hover:bg-blue-200'
                  : 'bg-gray-100 text-gray-400 cursor-not-allowed'
              }`}
            >
              <ArrowPathIcon className="h-4 w-4" />
              <span>Rebuild Projection</span>
            </button>

            <button
              onClick={() => handleAction('reset')}
              className="w-full bg-yellow-100 text-yellow-800 hover:bg-yellow-200 flex items-center justify-center space-x-2 px-4 py-2 rounded-md text-sm font-medium transition-colors"
            >
              <TrashIcon className="h-4 w-4" />
              <span>Reset Position</span>
            </button>
          </div>
        </div>

        {/* Information Section */}
        <div className="border-t border-gray-200 pt-4">
          <h4 className="text-sm font-medium text-gray-900 mb-3">Actions</h4>
          <div className="space-y-3 text-sm text-gray-600">
            <div className="flex items-start space-x-2">
              <PlayIcon className="h-4 w-4 text-green-500 mt-0.5 flex-shrink-0" />
              <div>
                <div className="font-medium text-gray-900">Start</div>
                <div>Resume processing events from the last position</div>
              </div>
            </div>

            <div className="flex items-start space-x-2">
              <StopIcon className="h-4 w-4 text-red-500 mt-0.5 flex-shrink-0" />
              <div>
                <div className="font-medium text-gray-900">Stop</div>
                <div>Pause event processing while maintaining position</div>
              </div>
            </div>

            <div className="flex items-start space-x-2">
              <ArrowPathIcon className="h-4 w-4 text-blue-500 mt-0.5 flex-shrink-0" />
              <div>
                <div className="font-medium text-gray-900">Rebuild</div>
                <div>Replay all events from the beginning to rebuild the projection</div>
              </div>
            </div>

            <div className="flex items-start space-x-2">
              <TrashIcon className="h-4 w-4 text-yellow-500 mt-0.5 flex-shrink-0" />
              <div>
                <div className="font-medium text-gray-900">Reset</div>
                <div>Reset the position to zero without rebuilding</div>
              </div>
            </div>
          </div>
        </div>

        {/* Status-specific Information */}
        {projection.status === ProjectionStatus.ERROR && (
          <div className="border-t border-gray-200 pt-4">
            <div className="bg-red-50 border border-red-200 rounded p-3">
              <div className="text-sm text-red-800">
                <div className="font-medium">Error Recovery</div>
                <div className="mt-1">
                  This projection has encountered an error. Try starting it again, or rebuild if the issue persists.
                </div>
              </div>
            </div>
          </div>
        )}

        {projection.status === ProjectionStatus.REBUILDING && (
          <div className="border-t border-gray-200 pt-4">
            <div className="bg-blue-50 border border-blue-200 rounded p-3">
              <div className="text-sm text-blue-800">
                <div className="font-medium">Rebuild in Progress</div>
                <div className="mt-1">
                  The projection is currently rebuilding. This process may take some time depending on the number of events.
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Utility Actions */}
        <div className="border-t border-gray-200 pt-4">
          <div className="grid grid-cols-2 gap-2">
            <button className="btn-secondary flex items-center justify-center space-x-1 text-xs">
              <DocumentTextIcon className="h-3 w-3" />
              <span>View Logs</span>
            </button>
            <button className="btn-secondary flex items-center justify-center space-x-1 text-xs">
              <Cog6ToothIcon className="h-3 w-3" />
              <span>Settings</span>
            </button>
          </div>
        </div>
      </div>

      {/* Confirmation Modal */}
      {showConfirmModal && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50 flex items-center justify-center">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="p-6">
              <div className="flex items-start space-x-3">
                <div className="flex-shrink-0">
                  <ArrowPathIcon className="h-6 w-6 text-yellow-400" />
                </div>
                <div className="flex-1">
                  <h3 className="text-lg font-medium text-gray-900">
                    Confirm {showConfirmModal === 'rebuild' ? 'Rebuild' : 'Reset'}
                  </h3>
                  <div className="mt-2 text-sm text-gray-500">
                    {showConfirmModal === 'rebuild' ? (
                      <>
                        This will rebuild the <strong>{projection.name}</strong> projection from scratch.
                        All events will be replayed and the projection will be unavailable during this process.
                      </>
                    ) : (
                      <>
                        This will reset the position of <strong>{projection.name}</strong> to zero.
                        The projection data will remain but the position counter will be reset.
                      </>
                    )}
                  </div>
                </div>
              </div>
              
              <div className="mt-5 flex justify-end space-x-3">
                <button
                  onClick={() => setShowConfirmModal(null)}
                  className="btn-secondary"
                >
                  Cancel
                </button>
                <button
                  onClick={() => confirmAction(showConfirmModal as 'rebuild' | 'reset')}
                  className="btn-primary"
                >
                  {showConfirmModal === 'rebuild' ? 'Rebuild' : 'Reset'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}