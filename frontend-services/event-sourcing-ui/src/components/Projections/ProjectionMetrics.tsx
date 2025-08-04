'use client';

import { Projection, ProjectionStatus } from '@/types';
import { formatDistanceToNow } from 'date-fns';
import {
  ChartBarIcon,
  ClockIcon,
  CpuChipIcon,
  ServerIcon
} from '@heroicons/react/24/outline';

interface ProjectionMetricsProps {
  projection: Projection;
}

export default function ProjectionMetrics({ projection }: ProjectionMetricsProps) {
  const formatNumber = (num: number) => {
    if (num >= 1000000) {
      return `${(num / 1000000).toFixed(1)}M`;
    }
    if (num >= 1000) {
      return `${(num / 1000).toFixed(1)}K`;
    }
    return num.toString();
  };

  const formatLag = (lag: number) => {
    if (lag < 60) return `${lag.toFixed(1)}s`;
    const minutes = Math.floor(lag / 60);
    const seconds = Math.floor(lag % 60);
    return `${minutes}m ${seconds}s`;
  };

  const getLagColor = (lag: number) => {
    if (lag < 5) return 'text-green-600';
    if (lag < 30) return 'text-yellow-600';
    return 'text-red-600';
  };

  const getHealthScore = () => {
    let score = 100;
    
    // Deduct points based on status
    if (projection.status === ProjectionStatus.ERROR) score -= 50;
    if (projection.status === ProjectionStatus.STOPPED) score -= 30;
    if (projection.status === ProjectionStatus.REBUILDING) score -= 20;
    
    // Deduct points based on lag
    if (projection.lag > 60) score -= 30;
    else if (projection.lag > 30) score -= 20;
    else if (projection.lag > 5) score -= 10;
    
    return Math.max(0, score);
  };

  const healthScore = getHealthScore();
  const healthColor = healthScore >= 80 ? 'text-green-600' : healthScore >= 60 ? 'text-yellow-600' : 'text-red-600';

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-medium text-gray-900">Metrics</h3>
        <div className={`text-2xl font-bold ${healthColor}`}>
          {healthScore}%
        </div>
      </div>

      <div className="space-y-4">
        {/* Key Metrics */}
        <div className="grid grid-cols-2 gap-4">
          <div className="flex items-center space-x-3">
            <ChartBarIcon className="h-8 w-8 text-blue-400" />
            <div>
              <div className="text-sm text-gray-500">Events Processed</div>
              <div className="text-lg font-semibold text-gray-900">
                {formatNumber(projection.eventsProcessed)}
              </div>
            </div>
          </div>

          <div className="flex items-center space-x-3">
            <ClockIcon className={`h-8 w-8 ${getLagColor(projection.lag)}`} />
            <div>
              <div className="text-gray-500 text-sm">Lag</div>
              <div className={`text-lg font-semibold ${getLagColor(projection.lag)}`}>
                {formatLag(projection.lag)}
              </div>
            </div>
          </div>
        </div>

        {/* Status and Position */}
        <div className="border-t border-gray-200 pt-4">
          <div className="grid grid-cols-1 gap-3 text-sm">
            <div className="flex justify-between">
              <span className="text-gray-500">Status:</span>
              <span className={`font-medium ${
                projection.status === ProjectionStatus.RUNNING ? 'text-green-600' :
                projection.status === ProjectionStatus.ERROR ? 'text-red-600' :
                projection.status === ProjectionStatus.REBUILDING ? 'text-blue-600' :
                'text-gray-600'
              }`}>
                {projection.status}
              </span>
            </div>

            <div className="flex justify-between">
              <span className="text-gray-500">Last Position:</span>
              <span className="font-medium text-gray-900">
                {projection.lastEventPosition.toLocaleString()}
              </span>
            </div>

            <div className="flex justify-between">
              <span className="text-gray-500">Version:</span>
              <span className="font-medium text-gray-900">
                {projection.metadata?.version || 'N/A'}
              </span>
            </div>

            <div className="flex justify-between">
              <span className="text-gray-500">Last Updated:</span>
              <span className="font-medium text-gray-900">
                {formatDistanceToNow(new Date(projection.lastUpdated), { addSuffix: true })}
              </span>
            </div>
          </div>
        </div>

        {/* Infrastructure Details */}
        {projection.metadata && (
          <div className="border-t border-gray-200 pt-4">
            <h4 className="text-sm font-medium text-gray-900 mb-3">Infrastructure</h4>
            <div className="grid grid-cols-2 gap-4">
              {projection.metadata.partitions && (
                <div className="flex items-center space-x-2">
                  <ServerIcon className="h-5 w-5 text-gray-400" />
                  <div>
                    <div className="text-xs text-gray-500">Partitions</div>
                    <div className="text-sm font-medium text-gray-900">
                      {projection.metadata.partitions}
                    </div>
                  </div>
                </div>
              )}

              {projection.metadata.consumers !== undefined && (
                <div className="flex items-center space-x-2">
                  <CpuChipIcon className="h-5 w-5 text-gray-400" />
                  <div>
                    <div className="text-xs text-gray-500">Consumers</div>
                    <div className="text-sm font-medium text-gray-900">
                      {projection.metadata.consumers}
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Rebuild Progress */}
        {projection.status === ProjectionStatus.REBUILDING && projection.metadata?.rebuildProgress !== undefined && (
          <div className="border-t border-gray-200 pt-4">
            <h4 className="text-sm font-medium text-gray-900 mb-3">Rebuild Progress</h4>
            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-500">Progress</span>
                <span className="font-medium text-gray-900">
                  {Math.round(projection.metadata.rebuildProgress)}%
                </span>
              </div>
              <div className="w-full bg-gray-200 rounded-full h-2">
                <div
                  className="bg-blue-500 h-2 rounded-full transition-all duration-300"
                  style={{ width: `${projection.metadata.rebuildProgress}%` }}
                ></div>
              </div>
              <div className="text-xs text-gray-500">
                Estimated time remaining: {
                  projection.metadata.rebuildProgress > 0 
                    ? `${Math.ceil((100 - projection.metadata.rebuildProgress) / 2)} minutes`
                    : 'Calculating...'
                }
              </div>
            </div>
          </div>
        )}

        {/* Error Details */}
        {projection.error && (
          <div className="border-t border-gray-200 pt-4">
            <h4 className="text-sm font-medium text-red-600 mb-2">Error Details</h4>
            <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">
              {projection.error}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}