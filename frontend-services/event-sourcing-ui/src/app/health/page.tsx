'use client';

import { useState, useEffect } from 'react';
import MainLayout from '@/components/Layout/MainLayout';
import ServiceTopology from '@/components/Health/ServiceTopology';
import ServiceMetrics from '@/components/Health/ServiceMetrics';
import QueueMetrics from '@/components/Health/QueueMetrics';
import { ServiceHealth, ServiceStatus, QueueMetrics as QueueMetricsType } from '@/types';
import {
  ServerIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  XCircleIcon,
  ArrowPathIcon,
  ChartBarIcon
} from '@heroicons/react/24/outline';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, AreaChart, Area } from 'recharts';

// Mock service health data
const mockServices: ServiceHealth[] = [
  {
    name: 'api-gateway',
    status: ServiceStatus.HEALTHY,
    uptime: 172800, // 48 hours in seconds
    version: '1.2.0',
    lastChecked: new Date(),
    dependencies: [
      { name: 'auth-service', status: ServiceStatus.HEALTHY, latency: 12 },
      { name: 'user-service', status: ServiceStatus.HEALTHY, latency: 8 },
      { name: 'postgres', status: ServiceStatus.HEALTHY, latency: 3 }
    ],
    metrics: {
      requestRate: 145.2,
      errorRate: 0.02,
      averageLatency: 89,
      p95Latency: 156,
      memoryUsage: 68.5,
      cpuUsage: 23.4
    }
  },
  {
    name: 'auth-service',
    status: ServiceStatus.HEALTHY,
    uptime: 259200, // 72 hours
    version: '2.1.0',
    lastChecked: new Date(),
    dependencies: [
      { name: 'postgres', status: ServiceStatus.HEALTHY, latency: 4 },
      { name: 'redis', status: ServiceStatus.HEALTHY, latency: 2 }
    ],
    metrics: {
      requestRate: 67.8,
      errorRate: 0.01,
      averageLatency: 45,
      p95Latency: 78,
      memoryUsage: 45.2,
      cpuUsage: 15.7
    }
  },
  {
    name: 'user-service',
    status: ServiceStatus.DEGRADED,
    uptime: 86400, // 24 hours
    version: '1.5.2',
    lastChecked: new Date(),
    dependencies: [
      { name: 'postgres', status: ServiceStatus.HEALTHY, latency: 5 },
      { name: 'event-store', status: ServiceStatus.DEGRADED, latency: 45 }
    ],
    metrics: {
      requestRate: 89.3,
      errorRate: 0.08,
      averageLatency: 156,
      p95Latency: 284,
      memoryUsage: 82.1,
      cpuUsage: 45.6
    }
  },
  {
    name: 'notification-service',
    status: ServiceStatus.UNHEALTHY,
    uptime: 3600, // 1 hour
    version: '1.0.8',
    lastChecked: new Date(),
    dependencies: [
      { name: 'kafka', status: ServiceStatus.UNHEALTHY, latency: 1200 },
      { name: 'smtp-server', status: ServiceStatus.HEALTHY, latency: 234 }
    ],
    metrics: {
      requestRate: 12.4,
      errorRate: 0.45,
      averageLatency: 678,
      p95Latency: 1234,
      memoryUsage: 91.3,
      cpuUsage: 78.9
    }
  },
  {
    name: 'workspace-service',
    status: ServiceStatus.HEALTHY,
    uptime: 345600, // 96 hours
    version: '1.8.0',
    lastChecked: new Date(),
    dependencies: [
      { name: 'postgres', status: ServiceStatus.HEALTHY, latency: 6 },
      { name: 'event-store', status: ServiceStatus.DEGRADED, latency: 34 }
    ],
    metrics: {
      requestRate: 34.7,
      errorRate: 0.01,
      averageLatency: 67,
      p95Latency: 123,
      memoryUsage: 52.8,
      cpuUsage: 18.3
    }
  }
];

// Mock queue metrics
const mockQueues: QueueMetricsType[] = [
  {
    name: 'user-events',
    depth: 234,
    consumerCount: 3,
    messageRate: 45.6,
    errorRate: 0.02,
    oldestMessage: new Date(Date.now() - 30000)
  },
  {
    name: 'notification-queue',
    depth: 1567,
    consumerCount: 1,
    messageRate: 12.3,
    errorRate: 0.15,
    oldestMessage: new Date(Date.now() - 300000)
  },
  {
    name: 'workspace-events',
    depth: 45,
    consumerCount: 2,
    messageRate: 23.4,
    errorRate: 0.01,
    oldestMessage: new Date(Date.now() - 15000)
  },
  {
    name: 'saga-orchestrator',
    depth: 12,
    consumerCount: 4,
    messageRate: 67.8,
    errorRate: 0.03,
    oldestMessage: new Date(Date.now() - 5000)
  }
];

// Mock metrics history
const metricsHistory = Array.from({ length: 20 }, (_, i) => ({
  time: new Date(Date.now() - (19 - i) * 60000).toISOString().substr(11, 8),
  requestRate: 100 + Math.random() * 50,
  errorRate: Math.random() * 0.1,
  latency: 50 + Math.random() * 100,
  memoryUsage: 40 + Math.random() * 40,
  cpuUsage: 20 + Math.random() * 60
}));

interface StatusCardProps {
  title: string;
  count: number;
  icon: React.ComponentType<{ className?: string }>;
  color: string;
}

function StatusCard({ title, count, icon: Icon, color }: StatusCardProps) {
  return (
    <div className="card">
      <div className="flex items-center">
        <div className="flex-shrink-0">
          <Icon className={`h-8 w-8 ${color}`} />
        </div>
        <div className="ml-5 w-0 flex-1">
          <dl>
            <dt className="text-sm font-medium text-gray-500 truncate">{title}</dt>
            <dd className="text-2xl font-semibold text-gray-900">{count}</dd>
          </dl>
        </div>
      </div>
    </div>
  );
}

export default function HealthPage() {
  const [services, setServices] = useState<ServiceHealth[]>(mockServices);
  const [queues, setQueues] = useState<QueueMetricsType[]>(mockQueues);
  const [selectedService, setSelectedService] = useState<ServiceHealth | null>(null);
  const [isAutoRefresh, setIsAutoRefresh] = useState(true);

  // Calculate status counts
  const statusCounts = {
    total: services.length,
    healthy: services.filter(s => s.status === ServiceStatus.HEALTHY).length,
    degraded: services.filter(s => s.status === ServiceStatus.DEGRADED).length,
    unhealthy: services.filter(s => s.status === ServiceStatus.UNHEALTHY).length
  };

  // Auto-refresh effect
  useEffect(() => {
    if (!isAutoRefresh) return;

    const interval = setInterval(() => {
      // Update service metrics
      setServices(prev => prev.map(service => ({
        ...service,
        lastChecked: new Date(),
        metrics: {
          ...service.metrics,
          requestRate: service.metrics.requestRate + (Math.random() - 0.5) * 10,
          errorRate: Math.max(0, service.metrics.errorRate + (Math.random() - 0.5) * 0.02),
          averageLatency: Math.max(1, service.metrics.averageLatency + (Math.random() - 0.5) * 20),
          memoryUsage: Math.max(0, Math.min(100, service.metrics.memoryUsage + (Math.random() - 0.5) * 5)),
          cpuUsage: Math.max(0, Math.min(100, service.metrics.cpuUsage + (Math.random() - 0.5) * 10))
        }
      })));

      // Update queue metrics
      setQueues(prev => prev.map(queue => ({
        ...queue,
        depth: Math.max(0, queue.depth + Math.floor((Math.random() - 0.7) * 20)),
        messageRate: Math.max(0, queue.messageRate + (Math.random() - 0.5) * 5)
      })));
    }, 3000);

    return () => clearInterval(interval);
  }, [isAutoRefresh]);

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return `${days}d ${hours}h ${minutes}m`;
  };

  return (
    <MainLayout>
      <div className="space-y-6">
        {/* Header */}
        <div className="border-b border-gray-200 pb-5">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold leading-7 text-gray-900">System Health</h1>
              <p className="mt-1 text-sm text-gray-500">
                Monitor service topology, performance metrics, and system health
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
                <ArrowPathIcon className={`h-4 w-4 ${isAutoRefresh ? 'animate-spin' : ''}`} />
                <span>{isAutoRefresh ? 'Auto-refresh' : 'Paused'}</span>
              </button>
              <button className="btn-secondary flex items-center space-x-2">
                <ArrowPathIcon className="h-4 w-4" />
                <span>Refresh</span>
              </button>
            </div>
          </div>
        </div>

        {/* Status Overview */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatusCard
            title="Total Services"
            count={statusCounts.total}
            icon={ServerIcon}
            color="text-gray-400"
          />
          <StatusCard
            title="Healthy"
            count={statusCounts.healthy}
            icon={CheckCircleIcon}
            color="text-green-400"
          />
          <StatusCard
            title="Degraded"
            count={statusCounts.degraded}
            icon={ExclamationTriangleIcon}
            color="text-yellow-400"
          />
          <StatusCard
            title="Unhealthy"
            count={statusCounts.unhealthy}
            icon={XCircleIcon}
            color="text-red-400"
          />
        </div>

        {/* System Metrics Chart */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="card">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-medium text-gray-900">Request Rate & Latency</h3>
            </div>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={metricsHistory}>
                  <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
                  <XAxis 
                    dataKey="time" 
                    className="text-xs"
                    axisLine={false}
                    tickLine={false}
                  />
                  <YAxis 
                    className="text-xs"
                    axisLine={false}
                    tickLine={false}
                  />
                  <Tooltip 
                    contentStyle={{
                      backgroundColor: '#374151',
                      border: 'none',
                      borderRadius: '8px',
                      color: 'white'
                    }}
                  />
                  <Line 
                    type="monotone" 
                    dataKey="requestRate" 
                    stroke="#3b82f6" 
                    strokeWidth={2}
                    dot={false}
                    name="Request Rate"
                  />
                  <Line 
                    type="monotone" 
                    dataKey="latency" 
                    stroke="#ef4444" 
                    strokeWidth={2}
                    dot={false}
                    name="Latency (ms)"
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="card">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-medium text-gray-900">Resource Usage</h3>
            </div>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={metricsHistory}>
                  <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
                  <XAxis 
                    dataKey="time" 
                    className="text-xs"
                    axisLine={false}
                    tickLine={false}
                  />
                  <YAxis 
                    className="text-xs"
                    axisLine={false}
                    tickLine={false}
                    domain={[0, 100]}
                  />
                  <Tooltip 
                    contentStyle={{
                      backgroundColor: '#374151',
                      border: 'none',
                      borderRadius: '8px',
                      color: 'white'
                    }}
                  />
                  <Area 
                    type="monotone" 
                    dataKey="cpuUsage" 
                    stackId="1"
                    stroke="#f59e0b" 
                    fill="#f59e0b"
                    fillOpacity={0.3}
                    name="CPU %"
                  />
                  <Area 
                    type="monotone" 
                    dataKey="memoryUsage" 
                    stackId="1"
                    stroke="#10b981" 
                    fill="#10b981"
                    fillOpacity={0.3}
                    name="Memory %"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>

        {/* Service Topology */}
        <ServiceTopology 
          services={services}
          selectedService={selectedService}
          onServiceSelect={setSelectedService}
        />

        {/* Bottom Section */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Service Metrics */}
          <ServiceMetrics services={services} />

          {/* Queue Metrics */}
          <QueueMetrics queues={queues} />
        </div>
      </div>
    </MainLayout>
  );
}