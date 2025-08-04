'use client';

import { QueueMetrics } from '@/types';
import { formatDistanceToNow } from 'date-fns';
import {
  QueueListIcon,
  UsersIcon,
  ChartBarIcon,
  ExclamationTriangleIcon,
  ClockIcon
} from '@heroicons/react/24/outline';

interface QueueMetricsProps {
  queues: QueueMetrics[];
}

export default function QueueMetrics({ queues }: QueueMetricsProps) {
  const getDepthColor = (depth: number) => {
    if (depth > 1000) return 'text-red-600';
    if (depth > 500) return 'text-yellow-600';
    return 'text-green-600';
  };

  const getErrorRateColor = (errorRate: number) => {
    if (errorRate > 0.1) return 'text-red-600';
    if (errorRate > 0.05) return 'text-yellow-600';
    return 'text-green-600';
  };

  const getAgeColor = (oldestMessage?: Date) => {
    if (!oldestMessage) return 'text-gray-600';
    
    const ageMinutes = (Date.now() - oldestMessage.getTime()) / (1000 * 60);
    if (ageMinutes > 60) return 'text-red-600';
    if (ageMinutes > 10) return 'text-yellow-600';
    return 'text-green-600';
  };

  const formatAge = (oldestMessage?: Date) => {
    if (!oldestMessage) return 'N/A';
    return formatDistanceToNow(oldestMessage, { addSuffix: true });
  };

  const getHealthScore = (queue: QueueMetrics) => {
    let score = 100;
    
    // Deduct for high queue depth
    if (queue.depth > 1000) score -= 40;
    else if (queue.depth > 500) score -= 20;
    else if (queue.depth > 100) score -= 10;
    
    // Deduct for high error rate
    if (queue.errorRate > 0.1) score -= 30;
    else if (queue.errorRate > 0.05) score -= 15;
    
    // Deduct for old messages
    if (queue.oldestMessage) {
      const ageMinutes = (Date.now() - queue.oldestMessage.getTime()) / (1000 * 60);
      if (ageMinutes > 60) score -= 20;
      else if (ageMinutes > 10) score -= 10;
    }
    
    // Deduct for no consumers
    if (queue.consumerCount === 0) score -= 50;
    
    return Math.max(0, score);
  };

  // Sort queues by health score (worst first)
  const sortedQueues = [...queues].sort((a, b) => {
    return getHealthScore(a) - getHealthScore(b);
  });

  return (
    <div className="card p-0">
      <div className="px-6 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-medium text-gray-900">Message Queue Metrics</h3>
          <div className="text-sm text-gray-500">
            {queues.length} queues
          </div>
        </div>
      </div>

      <div className="max-h-[500px] overflow-y-auto scrollbar-thin">
        <div className="divide-y divide-gray-200">
          {sortedQueues.map((queue) => {
            const healthScore = getHealthScore(queue);
            return (
              <div key={queue.name} className="px-6 py-4 hover:bg-gray-50">
                <div className="flex items-start justify-between">
                  <div className="flex-1 min-w-0">
                    {/* Queue Name */}
                    <div className="flex items-center space-x-3 mb-3">
                      <QueueListIcon className="h-5 w-5 text-gray-400" />
                      <div>
                        <div className="text-sm font-medium text-gray-900">
                          {queue.name}
                        </div>
                        <div className="text-xs text-gray-500">
                          {queue.consumerCount} consumer{queue.consumerCount !== 1 ? 's' : ''}
                        </div>
                      </div>
                      {queue.consumerCount === 0 && (
                        <span className="status-badge status-error">
                          No Consumers
                        </span>
                      )}
                    </div>

                    {/* Metrics Grid */}
                    <div className="grid grid-cols-2 lg:grid-cols-5 gap-4 text-sm">
                      <div className="flex items-center space-x-2">
                        <QueueListIcon className="h-4 w-4 text-gray-400" />
                        <div>
                          <div className="text-gray-500">Queue Depth</div>
                          <div className={`font-medium ${getDepthColor(queue.depth)}`}>
                            {queue.depth.toLocaleString()}
                          </div>
                        </div>
                      </div>

                      <div className="flex items-center space-x-2">
                        <UsersIcon className="h-4 w-4 text-gray-400" />
                        <div>
                          <div className="text-gray-500">Consumers</div>
                          <div className={`font-medium ${queue.consumerCount === 0 ? 'text-red-600' : 'text-green-600'}`}>
                            {queue.consumerCount}
                          </div>
                        </div>
                      </div>

                      <div className="flex items-center space-x-2">
                        <ChartBarIcon className="h-4 w-4 text-gray-400" />
                        <div>
                          <div className="text-gray-500">Message Rate</div>
                          <div className="font-medium text-gray-900">
                            {queue.messageRate.toFixed(1)}/sec
                          </div>
                        </div>
                      </div>

                      <div className="flex items-center space-x-2">
                        <ExclamationTriangleIcon className="h-4 w-4 text-gray-400" />
                        <div>
                          <div className="text-gray-500">Error Rate</div>
                          <div className={`font-medium ${getErrorRateColor(queue.errorRate)}`}>
                            {(queue.errorRate * 100).toFixed(1)}%
                          </div>
                        </div>
                      </div>

                      <div className="flex items-center space-x-2">
                        <ClockIcon className="h-4 w-4 text-gray-400" />
                        <div>
                          <div className="text-gray-500">Oldest Message</div>
                          <div className={`font-medium ${getAgeColor(queue.oldestMessage)}`}>
                            {formatAge(queue.oldestMessage)}
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Progress Bar for Queue Depth */}
                    <div className="mt-3">
                      <div className="flex items-center justify-between text-xs text-gray-500 mb-1">
                        <span>Queue Utilization</span>
                        <span>{Math.min(100, Math.round((queue.depth / 1000) * 100))}%</span>
                      </div>
                      <div className="w-full bg-gray-200 rounded-full h-2">
                        <div
                          className={`h-2 rounded-full transition-all duration-300 ${
                            queue.depth > 1000
                              ? 'bg-red-500'
                              : queue.depth > 500
                              ? 'bg-yellow-500'
                              : 'bg-green-500'
                          }`}
                          style={{ 
                            width: `${Math.min(100, Math.round((queue.depth / 1000) * 100))}%` 
                          }}
                        ></div>
                      </div>
                    </div>

                    {/* Alerts */}
                    {(queue.depth > 1000 || queue.consumerCount === 0 || queue.errorRate > 0.1) && (
                      <div className="mt-3 space-y-1">
                        {queue.depth > 1000 && (
                          <div className="text-xs text-red-600 bg-red-50 rounded px-2 py-1">
                            ⚠️ High queue depth: {queue.depth.toLocaleString()} messages
                          </div>
                        )}
                        {queue.consumerCount === 0 && (
                          <div className="text-xs text-red-600 bg-red-50 rounded px-2 py-1">
                            ⚠️ No consumers attached to this queue
                          </div>
                        )}
                        {queue.errorRate > 0.1 && (
                          <div className="text-xs text-red-600 bg-red-50 rounded px-2 py-1">
                            ⚠️ High error rate: {(queue.errorRate * 100).toFixed(1)}%
                          </div>
                        )}
                      </div>
                    )}
                  </div>

                  {/* Health Score */}
                  <div className="flex-shrink-0 ml-4">
                    <div className="text-center">
                      <div className={`text-2xl font-bold ${
                        healthScore >= 80 ? 'text-green-600' :
                        healthScore >= 60 ? 'text-yellow-600' :
                        'text-red-600'
                      }`}>
                        {healthScore}
                      </div>
                      <div className="text-xs text-gray-500">Health</div>
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Summary Footer */}
      <div className="px-6 py-4 bg-gray-50 border-t border-gray-200">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <div className="text-gray-500">Total Messages</div>
            <div className="font-medium text-gray-900">
              {queues.reduce((sum, q) => sum + q.depth, 0).toLocaleString()}
            </div>
          </div>
          <div>
            <div className="text-gray-500">Total Consumers</div>
            <div className="font-medium text-gray-900">
              {queues.reduce((sum, q) => sum + q.consumerCount, 0)}
            </div>
          </div>
          <div>
            <div className="text-gray-500">Total Rate</div>
            <div className="font-medium text-gray-900">
              {queues.reduce((sum, q) => sum + q.messageRate, 0).toFixed(1)}/sec
            </div>
          </div>
          <div>
            <div className="text-gray-500">Avg Error Rate</div>
            <div className="font-medium text-gray-900">
              {(queues.reduce((sum, q) => sum + q.errorRate, 0) / queues.length * 100).toFixed(1)}%
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}