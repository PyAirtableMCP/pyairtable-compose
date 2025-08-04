'use client';

import { Projection, ProjectionStatus } from '@/types';
import { formatDistanceToNow } from 'date-fns';
import {
  PlayIcon,
  StopIcon,
  ExclamationTriangleIcon,
  ArrowPathIcon,
  ChartBarIcon,
  ClockIcon
} from '@heroicons/react/24/outline';

interface ProjectionListProps {
  projections: Projection[];
  selectedProjection: Projection | null;
  onProjectionSelect: (projection: Projection) => void;
  onProjectionAction: (name: string, action: 'start' | 'stop' | 'rebuild' | 'reset') => void;
}

export default function ProjectionList({ 
  projections, 
  selectedProjection, 
  onProjectionSelect, 
  onProjectionAction 
}: ProjectionListProps) {
  const getStatusIcon = (status: ProjectionStatus) => {
    switch (status) {
      case ProjectionStatus.RUNNING:
        return <PlayIcon className="h-5 w-5 text-green-500" />;
      case ProjectionStatus.ERROR:
        return <ExclamationTriangleIcon className="h-5 w-5 text-red-500" />;
      case ProjectionStatus.REBUILDING:
        return <ArrowPathIcon className="h-5 w-5 text-blue-500 animate-spin" />;
      case ProjectionStatus.STOPPED:
        return <StopIcon className="h-5 w-5 text-gray-500" />;
      case ProjectionStatus.INITIALIZING:
        return <ClockIcon className="h-5 w-5 text-yellow-500" />;
      default:
        return <ChartBarIcon className="h-5 w-5 text-gray-500" />;
    }
  };

  const getStatusColor = (status: ProjectionStatus) => {
    switch (status) {
      case ProjectionStatus.RUNNING:
        return 'status-success';
      case ProjectionStatus.ERROR:
        return 'status-error';
      case ProjectionStatus.REBUILDING:
        return 'status-info';
      case ProjectionStatus.STOPPED:
        return 'bg-gray-100 text-gray-800';
      case ProjectionStatus.INITIALIZING:
        return 'status-warning';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const getLagColor = (lag: number) => {
    if (lag < 5) return 'text-green-600';
    if (lag < 30) return 'text-yellow-600';
    return 'text-red-600';
  };

  const formatLag = (lag: number) => {
    if (lag < 60) return `${lag.toFixed(1)}s`;
    const minutes = Math.floor(lag / 60);
    const seconds = Math.floor(lag % 60);
    return `${minutes}m ${seconds}s`;
  };

  if (projections.length === 0) {
    return (
      <div className="card">
        <div className="text-center py-12">
          <ChartBarIcon className="mx-auto h-12 w-12 text-gray-400" />
          <h3 className="mt-2 text-sm font-medium text-gray-900">No projections found</h3>
          <p className="mt-1 text-sm text-gray-500">
            No projections match your current filters.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="card p-0">
      <div className="px-6 py-4 border-b border-gray-200">
        <h3 className="text-lg font-medium text-gray-900">
          Projections ({projections.length})
        </h3>
      </div>

      <div className="max-h-[600px] overflow-y-auto scrollbar-thin">
        <div className="divide-y divide-gray-200">
          {projections.map((projection) => (
            <div
              key={projection.name}
              onClick={() => onProjectionSelect(projection)}
              className={`px-6 py-4 hover:bg-gray-50 cursor-pointer transition-colors duration-150 ${
                selectedProjection?.name === projection.name ? 'bg-primary-50 border-l-4 border-primary-500' : ''
              }`}
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  {/* Projection Name and Status */}
                  <div className="flex items-center space-x-3 mb-2">
                    <div className="flex items-center space-x-2">
                      {getStatusIcon(projection.status)}
                      <span className="text-lg font-medium text-gray-900">
                        {projection.name}
                      </span>
                    </div>
                    <span className={`status-badge ${getStatusColor(projection.status)}`}>
                      {projection.status}
                    </span>
                  </div>

                  {/* Progress Bar for Rebuilding */}
                  {projection.status === ProjectionStatus.REBUILDING && projection.metadata?.rebuildProgress !== undefined && (
                    <div className="mb-3">
                      <div className="flex items-center justify-between text-sm text-gray-600 mb-1">
                        <span>Rebuilding</span>
                        <span>{Math.round(projection.metadata.rebuildProgress)}%</span>
                      </div>
                      <div className="w-full bg-gray-200 rounded-full h-2">
                        <div
                          className="bg-blue-500 h-2 rounded-full transition-all duration-300"
                          style={{ width: `${projection.metadata.rebuildProgress}%` }}
                        ></div>
                      </div>
                    </div>
                  )}

                  {/* Metrics */}
                  <div className="grid grid-cols-2 gap-4 mb-3 text-sm">
                    <div>
                      <div className="text-gray-500">Events Processed</div>
                      <div className="font-medium text-gray-900">
                        {projection.eventsProcessed.toLocaleString()}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500">Last Position</div>
                      <div className="font-medium text-gray-900">
                        {projection.lastEventPosition.toLocaleString()}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500">Lag</div>
                      <div className={`font-medium ${getLagColor(projection.lag)}`}>
                        {formatLag(projection.lag)}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500">Version</div>
                      <div className="font-medium text-gray-900">
                        {projection.metadata?.version || 'N/A'}
                      </div>
                    </div>
                  </div>

                  {/* Error Message */}
                  {projection.error && (
                    <div className="mb-3 p-3 bg-red-50 border border-red-200 rounded text-sm text-red-700">
                      <div className="font-medium">Error:</div>
                      <div>{projection.error}</div>
                    </div>
                  )}

                  {/* Metadata */}
                  {projection.metadata && (
                    <div className="mb-3 text-xs text-gray-500">
                      <div className="flex items-center space-x-4">
                        {projection.metadata.partitions && (
                          <span>Partitions: {projection.metadata.partitions}</span>
                        )}
                        {projection.metadata.consumers !== undefined && (
                          <span>Consumers: {projection.metadata.consumers}</span>
                        )}
                      </div>
                    </div>
                  )}

                  {/* Last Updated */}
                  <div className="text-xs text-gray-500">
                    Last updated {formatDistanceToNow(new Date(projection.lastUpdated), { addSuffix: true })}
                  </div>

                  {/* Quick Actions */}
                  <div className="mt-3 flex space-x-2">
                    {projection.status === ProjectionStatus.STOPPED && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          onProjectionAction(projection.name, 'start');
                        }}
                        className="text-xs bg-green-100 text-green-800 hover:bg-green-200 px-2 py-1 rounded transition-colors"
                      >
                        Start
                      </button>
                    )}
                    
                    {projection.status === ProjectionStatus.RUNNING && (
                      <>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onProjectionAction(projection.name, 'stop');
                          }}
                          className="text-xs bg-red-100 text-red-800 hover:bg-red-200 px-2 py-1 rounded transition-colors"
                        >
                          Stop
                        </button>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onProjectionAction(projection.name, 'rebuild');
                          }}
                          className="text-xs bg-blue-100 text-blue-800 hover:bg-blue-200 px-2 py-1 rounded transition-colors"
                        >
                          Rebuild
                        </button>
                      </>
                    )}

                    {projection.status === ProjectionStatus.ERROR && (
                      <>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onProjectionAction(projection.name, 'start');
                          }}
                          className="text-xs bg-green-100 text-green-800 hover:bg-green-200 px-2 py-1 rounded transition-colors"
                        >
                          Restart
                        </button>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onProjectionAction(projection.name, 'rebuild');
                          }}
                          className="text-xs bg-blue-100 text-blue-800 hover:bg-blue-200 px-2 py-1 rounded transition-colors"
                        >
                          Rebuild
                        </button>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onProjectionAction(projection.name, 'reset');
                          }}
                          className="text-xs bg-yellow-100 text-yellow-800 hover:bg-yellow-200 px-2 py-1 rounded transition-colors"
                        >
                          Reset
                        </button>
                      </>
                    )}
                  </div>
                </div>

                {/* Health Indicator */}
                <div className="flex-shrink-0 ml-4">
                  <div className={`h-3 w-3 rounded-full ${
                    projection.status === ProjectionStatus.RUNNING
                      ? 'bg-green-400'
                      : projection.status === ProjectionStatus.ERROR
                      ? 'bg-red-400'
                      : projection.status === ProjectionStatus.REBUILDING
                      ? 'bg-blue-400 animate-pulse'
                      : 'bg-gray-400'
                  }`}></div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}