'use client';

import { ServiceHealth, ServiceStatus } from '@/types';
import { 
  ServerIcon,
  ArrowRightIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  XCircleIcon
} from '@heroicons/react/24/outline';

interface ServiceTopologyProps {
  services: ServiceHealth[];
  selectedService: ServiceHealth | null;
  onServiceSelect: (service: ServiceHealth) => void;
}

export default function ServiceTopology({ services, selectedService, onServiceSelect }: ServiceTopologyProps) {
  const getStatusColor = (status: ServiceStatus) => {
    switch (status) {
      case ServiceStatus.HEALTHY:
        return 'border-green-300 bg-green-50 text-green-800';
      case ServiceStatus.DEGRADED:
        return 'border-yellow-300 bg-yellow-50 text-yellow-800';
      case ServiceStatus.UNHEALTHY:
        return 'border-red-300 bg-red-50 text-red-800';
      default:
        return 'border-gray-300 bg-gray-50 text-gray-800';
    }
  };

  const getStatusIcon = (status: ServiceStatus) => {
    switch (status) {
      case ServiceStatus.HEALTHY:
        return <CheckCircleIcon className="h-4 w-4 text-green-500" />;
      case ServiceStatus.DEGRADED:
        return <ExclamationTriangleIcon className="h-4 w-4 text-yellow-500" />;
      case ServiceStatus.UNHEALTHY:
        return <XCircleIcon className="h-4 w-4 text-red-500" />;
      default:
        return <ServerIcon className="h-4 w-4 text-gray-500" />;
    }
  };

  const getDependencyColor = (status: ServiceStatus) => {
    switch (status) {
      case ServiceStatus.HEALTHY:
        return 'bg-green-400';
      case ServiceStatus.DEGRADED:
        return 'bg-yellow-400';
      case ServiceStatus.UNHEALTHY:
        return 'bg-red-400';
      default:
        return 'bg-gray-400';
    }
  };

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${Math.floor((seconds % 3600) / 60)}m`;
    return `${Math.floor(seconds / 60)}m`;
  };

  // Group services by layer
  const gatewayServices = services.filter(s => s.name.includes('gateway'));
  const appServices = services.filter(s => 
    s.name.includes('service') && !s.name.includes('gateway')
  );
  const infraServices = services.filter(s => 
    !s.name.includes('service') && !s.name.includes('gateway')
  );

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-medium text-gray-900">Service Topology</h3>
        <div className="flex items-center space-x-4 text-sm">
          <div className="flex items-center space-x-1">
            <div className="h-3 w-3 bg-green-400 rounded-full"></div>
            <span className="text-gray-600">Healthy</span>
          </div>
          <div className="flex items-center space-x-1">
            <div className="h-3 w-3 bg-yellow-400 rounded-full"></div>
            <span className="text-gray-600">Degraded</span>
          </div>
          <div className="flex items-center space-x-1">
            <div className="h-3 w-3 bg-red-400 rounded-full"></div>
            <span className="text-gray-600">Unhealthy</span>
          </div>
        </div>
      </div>

      {/* Desktop Layout */}
      <div className="hidden lg:block">
        <div className="space-y-8">
          {/* Gateway Layer */}
          {gatewayServices.length > 0 && (
            <div>
              <div className="text-sm font-medium text-gray-500 mb-3">Gateway Layer</div>
              <div className="flex justify-center">
                <div className="flex space-x-4">
                  {gatewayServices.map((service) => (
                    <div
                      key={service.name}
                      onClick={() => onServiceSelect(service)}
                      className={`relative p-4 rounded-lg border-2 cursor-pointer transition-all duration-200 min-w-[200px] ${
                        getStatusColor(service.status)
                      } ${
                        selectedService?.name === service.name ? 'ring-2 ring-primary-500' : ''
                      }`}
                    >
                      <div className="flex items-center space-x-2 mb-2">
                        {getStatusIcon(service.status)}
                        <span className="font-medium">{service.name}</span>
                      </div>
                      <div className="text-xs space-y-1">
                        <div>v{service.version}</div>
                        <div>Uptime: {formatUptime(service.uptime)}</div>
                        <div>
                          {service.metrics.requestRate.toFixed(1)} req/s
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Connection Arrow */}
          {gatewayServices.length > 0 && appServices.length > 0 && (
            <div className="flex justify-center">
              <ArrowRightIcon className="h-6 w-6 text-gray-400 transform rotate-90" />
            </div>
          )}

          {/* Application Services Layer */}
          {appServices.length > 0 && (
            <div>
              <div className="text-sm font-medium text-gray-500 mb-3">Application Services</div>
              <div className="flex flex-wrap justify-center gap-4">
                {appServices.map((service) => (
                  <div key={service.name} className="flex flex-col items-center">
                    <div
                      onClick={() => onServiceSelect(service)}
                      className={`relative p-4 rounded-lg border-2 cursor-pointer transition-all duration-200 min-w-[180px] ${
                        getStatusColor(service.status)
                      } ${
                        selectedService?.name === service.name ? 'ring-2 ring-primary-500' : ''
                      }`}
                    >
                      <div className="flex items-center space-x-2 mb-2">
                        {getStatusIcon(service.status)}
                        <span className="font-medium text-sm">{service.name}</span>
                      </div>
                      <div className="text-xs space-y-1">
                        <div>v{service.version}</div>
                        <div>Uptime: {formatUptime(service.uptime)}</div>
                        <div>
                          {service.metrics.requestRate.toFixed(1)} req/s
                        </div>
                        <div>
                          {service.metrics.errorRate.toFixed(2)}% errors
                        </div>
                      </div>
                    </div>

                    {/* Dependencies */}
                    {service.dependencies.length > 0 && (
                      <div className="mt-2">
                        <ArrowRightIcon className="h-4 w-4 text-gray-400 transform rotate-90 mx-auto" />
                        <div className="flex flex-wrap justify-center gap-2 mt-2">
                          {service.dependencies.map((dep, index) => (
                            <div
                              key={index}
                              className="flex items-center space-x-1 bg-white border border-gray-200 rounded px-2 py-1 text-xs"
                            >
                              <div className={`h-2 w-2 rounded-full ${getDependencyColor(dep.status)}`}></div>
                              <span>{dep.name}</span>
                              <span className="text-gray-500">({dep.latency}ms)</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Mobile Layout */}
      <div className="lg:hidden">
        <div className="space-y-4">
          {services.map((service) => (
            <div
              key={service.name}
              onClick={() => onServiceSelect(service)}
              className={`p-4 rounded-lg border-2 cursor-pointer transition-all duration-200 ${
                getStatusColor(service.status)
              } ${
                selectedService?.name === service.name ? 'ring-2 ring-primary-500' : ''
              }`}
            >
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center space-x-2">
                  {getStatusIcon(service.status)}
                  <span className="font-medium">{service.name}</span>
                </div>
                <div className="text-xs text-gray-500">v{service.version}</div>
              </div>

              <div className="grid grid-cols-2 gap-2 text-xs mb-3">
                <div>
                  <div className="text-gray-500">Uptime</div>
                  <div className="font-medium">{formatUptime(service.uptime)}</div>
                </div>
                <div>
                  <div className="text-gray-500">Requests/sec</div>
                  <div className="font-medium">{service.metrics.requestRate.toFixed(1)}</div>
                </div>
                <div>
                  <div className="text-gray-500">Error Rate</div>
                  <div className="font-medium">{service.metrics.errorRate.toFixed(2)}%</div>
                </div>
                <div>
                  <div className="text-gray-500">Avg Latency</div>
                  <div className="font-medium">{service.metrics.averageLatency}ms</div>
                </div>
              </div>

              {/* Dependencies */}
              {service.dependencies.length > 0 && (
                <div>
                  <div className="text-xs text-gray-500 mb-2">Dependencies:</div>
                  <div className="flex flex-wrap gap-1">
                    {service.dependencies.map((dep, index) => (
                      <div
                        key={index}
                        className="flex items-center space-x-1 bg-white bg-opacity-50 rounded px-2 py-1 text-xs"
                      >
                        <div className={`h-2 w-2 rounded-full ${getDependencyColor(dep.status)}`}></div>
                        <span>{dep.name}</span>
                        <span className="text-gray-500">({dep.latency}ms)</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Selected Service Info */}
      {selectedService && (
        <div className="mt-6 p-4 bg-gray-50 rounded-lg border border-gray-200">
          <div className="flex items-center justify-between mb-3">
            <h4 className="font-medium text-gray-900">{selectedService.name}</h4>
            <button
              onClick={() => onServiceSelect(null as any)}
              className="text-gray-400 hover:text-gray-600"
            >
              ×
            </button>
          </div>
          
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <div className="text-gray-500">CPU Usage</div>
              <div className="font-medium">{selectedService.metrics.cpuUsage.toFixed(1)}%</div>
            </div>
            <div>
              <div className="text-gray-500">Memory Usage</div>
              <div className="font-medium">{selectedService.metrics.memoryUsage.toFixed(1)}%</div>
            </div>
            <div>
              <div className="text-gray-500">P95 Latency</div>
              <div className="font-medium">{selectedService.metrics.p95Latency}ms</div>
            </div>
            <div>
              <div className="text-gray-500">Last Check</div>
              <div className="font-medium">
                {selectedService.lastChecked.toLocaleTimeString()}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}