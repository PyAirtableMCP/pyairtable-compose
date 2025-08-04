'use client';

import { useState, useEffect } from 'react';
import MainLayout from '@/components/Layout/MainLayout';
import ProjectionList from '@/components/Projections/ProjectionList';
import ProjectionMetrics from '@/components/Projections/ProjectionMetrics';
import ProjectionControls from '@/components/Projections/ProjectionControls';
import { Projection, ProjectionStatus, ProjectionMetrics as ProjectionMetricsType } from '@/types';
import {
  ChartBarIcon,
  PlayIcon,
  StopIcon,
  ArrowPathIcon,
  ExclamationTriangleIcon
} from '@heroicons/react/24/outline';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

// Mock projection data
const mockProjections: Projection[] = [
  {
    name: 'UserProjection',
    status: ProjectionStatus.RUNNING,
    lastEventPosition: 12547,
    lastUpdated: new Date(Date.now() - 30000),
    eventsProcessed: 12547,
    lag: 0.5,
    metadata: {
      version: '1.2.0',
      partitions: 4,
      consumers: 2
    }
  },
  {
    name: 'OrderProjection',
    status: ProjectionStatus.RUNNING,
    lastEventPosition: 8932,
    lastUpdated: new Date(Date.now() - 15000),
    eventsProcessed: 8932,
    lag: 1.2,
    metadata: {
      version: '1.1.0',
      partitions: 2,
      consumers: 1
    }
  },
  {
    name: 'WorkspaceProjection',
    status: ProjectionStatus.ERROR,
    lastEventPosition: 5423,
    lastUpdated: new Date(Date.now() - 300000),
    eventsProcessed: 5423,
    lag: 45.8,
    error: 'Database connection timeout',
    metadata: {
      version: '1.0.5',
      partitions: 1,
      consumers: 1
    }
  },
  {
    name: 'AnalyticsProjection',
    status: ProjectionStatus.REBUILDING,
    lastEventPosition: 0,
    lastUpdated: new Date(Date.now() - 120000),
    eventsProcessed: 2341,
    lag: 0,
    metadata: {
      version: '2.0.0',
      partitions: 8,
      consumers: 4,
      rebuildProgress: 25
    }
  },
  {
    name: 'NotificationProjection',
    status: ProjectionStatus.STOPPED,
    lastEventPosition: 9876,
    lastUpdated: new Date(Date.now() - 600000),
    eventsProcessed: 9876,
    lag: 0,
    metadata: {
      version: '1.3.0',
      partitions: 2,
      consumers: 0
    }
  }
];

// Mock metrics data
const mockMetricsHistory = Array.from({ length: 20 }, (_, i) => ({
  time: new Date(Date.now() - (19 - i) * 60000).toISOString().substr(11, 8),
  userProjectionLag: Math.random() * 2,
  orderProjectionLag: Math.random() * 3,
  workspaceProjectionLag: 40 + Math.random() * 10,
  analyticsProjectionLag: 0,
  notificationProjectionLag: 0,
  totalThroughput: 150 + Math.random() * 50
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

export default function ProjectionsPage() {
  const [projections, setProjections] = useState<Projection[]>(mockProjections);
  const [selectedProjection, setSelectedProjection] = useState<Projection | null>(null);
  const [statusFilter, setStatusFilter] = useState<ProjectionStatus | 'ALL'>('ALL');
  const [metricsHistory, setMetricsHistory] = useState(mockMetricsHistory);
  const [isAutoRefresh, setIsAutoRefresh] = useState(true);

  // Filter projections
  const filteredProjections = projections.filter(projection => {
    if (statusFilter !== 'ALL' && projection.status !== statusFilter) return false;
    return true;
  });

  // Calculate status counts
  const statusCounts = {
    total: projections.length,
    running: projections.filter(p => p.status === ProjectionStatus.RUNNING).length,
    error: projections.filter(p => p.status === ProjectionStatus.ERROR).length,
    rebuilding: projections.filter(p => p.status === ProjectionStatus.REBUILDING).length,
    stopped: projections.filter(p => p.status === ProjectionStatus.STOPPED).length
  };

  // Auto-refresh effect
  useEffect(() => {
    if (!isAutoRefresh) return;

    const interval = setInterval(() => {
      // Update metrics
      setMetricsHistory(prev => {
        const newPoint = {
          time: new Date().toISOString().substr(11, 8),
          userProjectionLag: Math.random() * 2,
          orderProjectionLag: Math.random() * 3,
          workspaceProjectionLag: 40 + Math.random() * 10,
          analyticsProjectionLag: Math.random() * 0.5,
          notificationProjectionLag: 0,
          totalThroughput: 150 + Math.random() * 50
        };
        return [...prev.slice(1), newPoint];
      });

      // Update projections
      setProjections(prev => prev.map(projection => {
        const updated = { ...projection };
        
        if (projection.status === ProjectionStatus.RUNNING) {
          updated.lastEventPosition += Math.floor(Math.random() * 10);
          updated.eventsProcessed += Math.floor(Math.random() * 10);
          updated.lag = Math.random() * 3;
          updated.lastUpdated = new Date();
        } else if (projection.status === ProjectionStatus.REBUILDING) {
          if (projection.metadata?.rebuildProgress !== undefined) {
            const newProgress = Math.min(100, projection.metadata.rebuildProgress + Math.random() * 5);
            updated.metadata = { ...projection.metadata, rebuildProgress: newProgress };
            updated.eventsProcessed += Math.floor(Math.random() * 20);
            
            if (newProgress >= 100) {
              updated.status = ProjectionStatus.RUNNING;
              updated.lastEventPosition = updated.eventsProcessed;
            }
          }
        }
        
        return updated;
      }));
    }, 2000);

    return () => clearInterval(interval);
  }, [isAutoRefresh]);

  const handleProjectionAction = (name: string, action: 'start' | 'stop' | 'rebuild' | 'reset') => {
    setProjections(prev => prev.map(projection => {
      if (projection.name === name) {
        const updated = { ...projection };
        
        switch (action) {
          case 'start':
            updated.status = ProjectionStatus.RUNNING;
            break;
          case 'stop':
            updated.status = ProjectionStatus.STOPPED;
            break;
          case 'rebuild':
            updated.status = ProjectionStatus.REBUILDING;
            updated.lastEventPosition = 0;
            updated.eventsProcessed = 0;
            updated.metadata = { ...projection.metadata, rebuildProgress: 0 };
            break;
          case 'reset':
            updated.lastEventPosition = 0;
            updated.eventsProcessed = 0;
            updated.lag = 0;
            updated.error = undefined;
            break;
        }
        
        updated.lastUpdated = new Date();
        return updated;
      }
      return projection;
    }));
  };

  return (
    <MainLayout>
      <div className="space-y-6">
        {/* Header */}
        <div className="border-b border-gray-200 pb-5">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold leading-7 text-gray-900">CQRS Projections</h1>
              <p className="mt-1 text-sm text-gray-500">
                Monitor and manage read model projections
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
                {isAutoRefresh ? (
                  <>
                    <StopIcon className="h-4 w-4" />
                    <span>Pause</span>
                  </>
                ) : (
                  <>
                    <PlayIcon className="h-4 w-4" />
                    <span>Resume</span>
                  </>
                )}
              </button>
              <button className="btn-secondary flex items-center space-x-2">
                <ArrowPathIcon className="h-4 w-4" />
                <span>Refresh All</span>
              </button>
            </div>
          </div>
        </div>

        {/* Status Cards */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
          <StatusCard
            title="Total Projections"
            count={statusCounts.total}
            icon={ChartBarIcon}
            color="text-gray-400"
          />
          <StatusCard
            title="Running"
            count={statusCounts.running}
            icon={PlayIcon}
            color="text-green-400"
          />
          <StatusCard
            title="Errors"
            count={statusCounts.error}
            icon={ExclamationTriangleIcon}
            color="text-red-400"
          />
          <StatusCard
            title="Rebuilding"
            count={statusCounts.rebuilding}
            icon={ArrowPathIcon}
            color="text-blue-400"
          />
          <StatusCard
            title="Stopped"
            count={statusCounts.stopped}
            icon={StopIcon}
            color="text-gray-400"
          />
        </div>

        {/* Lag Chart */}
        <div className="card">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-medium text-gray-900">Projection Lag (seconds)</h3>
            <div className="flex space-x-4 text-sm">
              <div className="flex items-center space-x-2">
                <div className="h-3 w-3 bg-blue-500 rounded"></div>
                <span>User</span>
              </div>
              <div className="flex items-center space-x-2">
                <div className="h-3 w-3 bg-green-500 rounded"></div>
                <span>Order</span>
              </div>
              <div className="flex items-center space-x-2">
                <div className="h-3 w-3 bg-red-500 rounded"></div>
                <span>Workspace</span>
              </div>
            </div>
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
                  dataKey="userProjectionLag" 
                  stroke="#3b82f6" 
                  strokeWidth={2}
                  dot={false}
                />
                <Line 
                  type="monotone" 
                  dataKey="orderProjectionLag" 
                  stroke="#10b981" 
                  strokeWidth={2}
                  dot={false}
                />
                <Line 
                  type="monotone" 
                  dataKey="workspaceProjectionLag" 
                  stroke="#ef4444" 
                  strokeWidth={2}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Filters */}
        <div className="flex space-x-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Status Filter
            </label>
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as ProjectionStatus | 'ALL')}
              className="input-field"
            >
              <option value="ALL">All Statuses</option>
              <option value={ProjectionStatus.RUNNING}>Running</option>
              <option value={ProjectionStatus.ERROR}>Error</option>
              <option value={ProjectionStatus.REBUILDING}>Rebuilding</option>
              <option value={ProjectionStatus.STOPPED}>Stopped</option>
              <option value={ProjectionStatus.INITIALIZING}>Initializing</option>
            </select>
          </div>
        </div>

        {/* Main Content */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Projections List */}
          <div className="lg:col-span-2">
            <ProjectionList
              projections={filteredProjections}
              selectedProjection={selectedProjection}
              onProjectionSelect={setSelectedProjection}
              onProjectionAction={handleProjectionAction}
            />
          </div>

          {/* Projection Details */}
          <div className="lg:col-span-1 space-y-6">
            {selectedProjection && (
              <>
                <ProjectionMetrics projection={selectedProjection} />
                <ProjectionControls 
                  projection={selectedProjection}
                  onAction={handleProjectionAction}
                />
              </>
            )}
            {!selectedProjection && (
              <div className="card">
                <div className="text-center py-12">
                  <ChartBarIcon className="mx-auto h-12 w-12 text-gray-400" />
                  <h3 className="mt-2 text-sm font-medium text-gray-900">No projection selected</h3>
                  <p className="mt-1 text-sm text-gray-500">
                    Select a projection from the list to view its details and controls.
                  </p>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </MainLayout>
  );
}