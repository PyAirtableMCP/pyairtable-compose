'use client';

import { ServiceHealth, ServiceStatus } from '@/types';
import {
  CheckCircleIcon,
  ExclamationTriangleIcon,
  XCircleIcon,
  ClockIcon,
  CpuChipIcon,
  ServerIcon
} from '@heroicons/react/24/outline';

interface ServiceMetricsProps {
  services: ServiceHealth[];
}

export default function ServiceMetrics({ services }: ServiceMetricsProps) {
  const getStatusIcon = (status: ServiceStatus) => {
    switch (status) {
      case ServiceStatus.HEALTHY:
        return <CheckCircleIcon className="h-5 w-5 text-green-500" />;
      case ServiceStatus.DEGRADED:
        return <ExclamationTriangleIcon className="h-5 w-5 text-yellow-500" />;
      case ServiceStatus.UNHEALTHY:
        return <XCircleIcon className="h-5 w-5 text-red-500" />;
      default:
        return <ServerIcon className="h-5 w-5 text-gray-500" />;
    }
  };

  const getStatusColor = (status: ServiceStatus) => {
    switch (status) {
      case ServiceStatus.HEALTHY:
        return 'status-success';
      case ServiceStatus.DEGRADED:
        return 'status-warning';
      case ServiceStatus.UNHEALTHY:
        return 'status-error';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const getMetricColor = (value: number, thresholds: { warning: number; critical: number }) => {
    if (value >= thresholds.critical) return 'text-red-600';
    if (value >= thresholds.warning) return 'text-yellow-600';
    return 'text-green-600';
  };

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
  };

  // Sort services by status (unhealthy first, then degraded, then healthy)
  const sortedServices = [...services].sort((a, b) => {
    const statusOrder = {
      [ServiceStatus.UNHEALTHY]: 0,
      [ServiceStatus.DEGRADED]: 1,
      [ServiceStatus.HEALTHY]: 2,
      [ServiceStatus.UNKNOWN]: 3
    };
    return statusOrder[a.status] - statusOrder[b.status];
  });

  return (
    <div className="card p-0">
      <div className="px-6 py-4 border-b border-gray-200">
        <h3 className="text-lg font-medium text-gray-900">Service Metrics</h3>
      </div>

      <div className="max-h-[500px] overflow-y-auto scrollbar-thin">
        <div className="divide-y divide-gray-200">
          {sortedServices.map((service) => (
            <div key={service.name} className="px-6 py-4 hover:bg-gray-50">
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  {/* Service Name and Status */}
                  <div className="flex items-center space-x-3 mb-3">
                    {getStatusIcon(service.status)}
                    <div>
                      <div className="text-sm font-medium text-gray-900">
                        {service.name}
                      </div>
                      <div className="text-xs text-gray-500">
                        v{service.version} • Uptime: {formatUptime(service.uptime)}
                      </div>
                    </div>
                    <span className={`status-badge ${getStatusColor(service.status)}`}>
                      {service.status}
                    </span>
                  </div>

                  {/* Metrics Grid */}
                  <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 text-sm">
                    <div className="flex items-center space-x-2">
                      <ClockIcon className="h-4 w-4 text-gray-400" />
                      <div>
                        <div className="text-gray-500">Requests/sec</div>
                        <div className="font-medium text-gray-900">
                          {service.metrics.requestRate.toFixed(1)}
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <ExclamationTriangleIcon className="h-4 w-4 text-gray-400" />
                      <div>
                        <div className="text-gray-500">Error Rate</div>
                        <div className={`font-medium ${getMetricColor(service.metrics.errorRate * 100, { warning: 1, critical: 5 })}`}>
                          {(service.metrics.errorRate * 100).toFixed(2)}%
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <ClockIcon className="h-4 w-4 text-gray-400" />
                      <div>
                        <div className="text-gray-500">Avg Latency</div>
                        <div className={`font-medium ${getMetricColor(service.metrics.averageLatency, { warning: 100, critical: 500 })}`}>
                          {service.metrics.averageLatency}ms
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <ClockIcon className="h-4 w-4 text-gray-400" />
                      <div>
                        <div className="text-gray-500">P95 Latency</div>
                        <div className={`font-medium ${getMetricColor(service.metrics.p95Latency, { warning: 200, critical: 1000 })}`}>
                          {service.metrics.p95Latency}ms
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <CpuChipIcon className="h-4 w-4 text-gray-400" />
                      <div>
                        <div className="text-gray-500">CPU Usage</div>
                        <div className={`font-medium ${getMetricColor(service.metrics.cpuUsage, { warning: 70, critical: 90 })}`}>
                          {service.metrics.cpuUsage.toFixed(1)}%
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <ServerIcon className="h-4 w-4 text-gray-400" />
                      <div>
                        <div className="text-gray-500">Memory Usage</div>
                        <div className={`font-medium ${getMetricColor(service.metrics.memoryUsage, { warning: 80, critical: 95 })}`}>
                          {service.metrics.memoryUsage.toFixed(1)}%
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <CheckCircleIcon className="h-4 w-4 text-gray-400" />
                      <div>
                        <div className="text-gray-500">Dependencies</div>
                        <div className="font-medium text-gray-900">
                          {service.dependencies.filter(d => d.status === ServiceStatus.HEALTHY).length}/
                          {service.dependencies.length}
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-2">
                      <ClockIcon className="h-4 w-4 text-gray-400" />
                      <div>
                        <div className="text-gray-500">Last Check</div>
                        <div className="font-medium text-gray-900">
                          {service.lastChecked.toLocaleTimeString()}
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Dependencies Status */}
                  {service.dependencies.length > 0 && (
                    <div className="mt-3">
                      <div className="text-xs text-gray-500 mb-2">Dependencies:</div>
                      <div className="flex flex-wrap gap-2">
                        {service.dependencies.map((dep, index) => (
                          <div
                            key={index}
                            className={`inline-flex items-center px-2 py-1 rounded text-xs ${
                              dep.status === ServiceStatus.HEALTHY
                                ? 'bg-green-100 text-green-800'
                                : dep.status === ServiceStatus.DEGRADED
                                ? 'bg-yellow-100 text-yellow-800'
                                : 'bg-red-100 text-red-800'
                            }`}
                          >
                            <span>{dep.name}</span>
                            <span className="ml-1 opacity-75">({dep.latency}ms)</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>

                {/* Health Score */}
                <div className="flex-shrink-0 ml-4">
                  <div className="text-center">
                    <div className={`text-2xl font-bold ${
                      service.status === ServiceStatus.HEALTHY ? 'text-green-600' :
                      service.status === ServiceStatus.DEGRADED ? 'text-yellow-600' :
                      'text-red-600'
                    }`}>
                      {service.status === ServiceStatus.HEALTHY ? '100' :
                       service.status === ServiceStatus.DEGRADED ? '70' : '25'}
                    </div>
                    <div className="text-xs text-gray-500">Health</div>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}