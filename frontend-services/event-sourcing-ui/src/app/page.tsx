'use client';

import { useEffect, useState } from 'react';
import MainLayout from '@/components/Layout/MainLayout';
import { 
  ChartBarIcon, 
  DocumentTextIcon, 
  PlayIcon, 
  ServerIcon,
  ExclamationTriangleIcon,
  CheckCircleIcon
} from '@heroicons/react/24/outline';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, AreaChart, Area } from 'recharts';

// Mock data for demonstration
const eventThroughputData = [
  { time: '09:00', events: 150 },
  { time: '09:05', events: 180 },
  { time: '09:10', events: 220 },
  { time: '09:15', events: 190 },
  { time: '09:20', events: 240 },
  { time: '09:25', events: 280 },
  { time: '09:30', events: 260 },
];

const sagaMetrics = [
  { time: '09:00', completed: 45, failed: 2 },
  { time: '09:05', completed: 52, failed: 1 },
  { time: '09:10', completed: 48, failed: 3 },
  { time: '09:15', completed: 55, failed: 1 },
  { time: '09:20', completed: 62, failed: 2 },
  { time: '09:25', completed: 58, failed: 0 },
  { time: '09:30', completed: 65, failed: 1 },
];

interface MetricCardProps {
  title: string;
  value: string | number;
  change?: string;
  changeType?: 'positive' | 'negative' | 'neutral';
  icon: React.ComponentType<{ className?: string }>;
}

function MetricCard({ title, value, change, changeType, icon: Icon }: MetricCardProps) {
  return (
    <div className="card">
      <div className="flex items-center">
        <div className="flex-shrink-0">
          <Icon className="h-8 w-8 text-gray-400" />
        </div>
        <div className="ml-5 w-0 flex-1">
          <dl>
            <dt className="text-sm font-medium text-gray-500 truncate">{title}</dt>
            <dd className="flex items-baseline">
              <div className="text-2xl font-semibold text-gray-900">{value}</div>
              {change && (
                <div className={`ml-2 flex items-baseline text-sm font-semibold ${
                  changeType === 'positive' 
                    ? 'text-green-600' 
                    : changeType === 'negative' 
                    ? 'text-red-600' 
                    : 'text-gray-600'
                }`}>
                  {change}
                </div>
              )}
            </dd>
          </dl>
        </div>
      </div>
    </div>
  );
}

export default function Dashboard() {
  const [isConnected, setIsConnected] = useState(false);
  const [lastUpdate, setLastUpdate] = useState<Date>(new Date());

  useEffect(() => {
    // Simulate connection status
    setIsConnected(true);
    
    // Update timestamp every 30 seconds
    const interval = setInterval(() => {
      setLastUpdate(new Date());
    }, 30000);

    return () => clearInterval(interval);
  }, []);

  return (
    <MainLayout>
      <div className="space-y-6">
        {/* Header */}
        <div className="border-b border-gray-200 pb-5">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold leading-7 text-gray-900 sm:truncate sm:text-3xl">
                Event Sourcing Dashboard
              </h1>
              <p className="mt-1 text-sm text-gray-500">
                Real-time monitoring and management of your event-driven architecture
              </p>
            </div>
            <div className="flex items-center space-x-4">
              <div className="flex items-center space-x-2">
                {isConnected ? (
                  <CheckCircleIcon className="h-5 w-5 text-green-500" />
                ) : (
                  <ExclamationTriangleIcon className="h-5 w-5 text-red-500" />
                )}
                <span className="text-sm text-gray-600">
                  {isConnected ? 'Connected' : 'Disconnected'}
                </span>
              </div>
              <div className="text-sm text-gray-500">
                Last updated: {lastUpdate.toLocaleTimeString()}
              </div>
            </div>
          </div>
        </div>

        {/* Key Metrics */}
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard
            title="Events/sec"
            value="1,247"
            change="+12%"
            changeType="positive"
            icon={DocumentTextIcon}
          />
          <MetricCard
            title="Active SAGAs"
            value="23"
            change="-2"
            changeType="neutral"
            icon={PlayIcon}
          />
          <MetricCard
            title="Projection Lag"
            value="1.2s"
            change="+0.3s"
            changeType="negative"
            icon={ChartBarIcon}
          />
          <MetricCard
            title="System Health"
            value="98.5%"
            change="+0.2%"
            changeType="positive"
            icon={ServerIcon}
          />
        </div>

        {/* Charts */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Event Throughput */}
          <div className="card">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-medium text-gray-900">Event Throughput</h3>
              <div className="flex space-x-2">
                <button className="text-sm text-gray-500 hover:text-gray-700">1H</button>
                <button className="text-sm bg-primary-100 text-primary-700 px-2 py-1 rounded">6H</button>
                <button className="text-sm text-gray-500 hover:text-gray-700">24H</button>
              </div>
            </div>
            <div className="mt-4 h-64">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={eventThroughputData}>
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
                  <Area 
                    type="monotone" 
                    dataKey="events" 
                    stroke="#3b82f6" 
                    fill="#3b82f6"
                    fillOpacity={0.1}
                    strokeWidth={2}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* SAGA Completion */}
          <div className="card">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-medium text-gray-900">SAGA Completion Rate</h3>
              <div className="flex items-center space-x-2">
                <div className="h-2 w-2 rounded-full bg-green-500"></div>
                <span className="text-sm text-gray-600">Completed</span>
                <div className="h-2 w-2 rounded-full bg-red-500"></div>
                <span className="text-sm text-gray-600">Failed</span>
              </div>
            </div>
            <div className="mt-4 h-64">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={sagaMetrics}>
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
                    dataKey="completed" 
                    stroke="#10b981" 
                    strokeWidth={2}
                    dot={{ r: 4 }}
                  />
                  <Line 
                    type="monotone" 
                    dataKey="failed" 
                    stroke="#ef4444" 
                    strokeWidth={2}
                    dot={{ r: 4 }}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>

        {/* Recent Events and Alerts */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Recent Events */}
          <div className="card">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-medium text-gray-900">Recent Events</h3>
              <a href="/events" className="text-sm text-primary-600 hover:text-primary-900">
                View all →
              </a>
            </div>
            <div className="mt-4 space-y-3">
              {[
                { type: 'UserRegistered', aggregate: 'User-123', time: '2 minutes ago' },
                { type: 'PaymentProcessed', aggregate: 'Order-456', time: '5 minutes ago' },
                { type: 'WorkspaceCreated', aggregate: 'Workspace-789', time: '8 minutes ago' },
                { type: 'DataImported', aggregate: 'Import-321', time: '12 minutes ago' },
              ].map((event, index) => (
                <div key={index} className="flex items-center justify-between py-2 border-b border-gray-100 last:border-b-0">
                  <div className="flex items-center space-x-3">
                    <div className="h-2 w-2 rounded-full bg-green-400"></div>
                    <div>
                      <div className="text-sm font-medium text-gray-900">{event.type}</div>
                      <div className="text-xs text-gray-500">{event.aggregate}</div>
                    </div>
                  </div>
                  <div className="text-xs text-gray-500">{event.time}</div>
                </div>
              ))}
            </div>
          </div>

          {/* System Alerts */}
          <div className="card">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-medium text-gray-900">System Alerts</h3>
              <a href="/health" className="text-sm text-primary-600 hover:text-primary-900">
                View all →
              </a>
            </div>
            <div className="mt-4 space-y-3">
              {[
                { level: 'warning', message: 'High memory usage in projection service', time: '10 minutes ago' },
                { level: 'info', message: 'Kafka consumer lag normalized', time: '25 minutes ago' },
                { level: 'error', message: 'Failed to process 3 events in user-projection', time: '1 hour ago' },
              ].map((alert, index) => (
                <div key={index} className="flex items-start space-x-3 py-2">
                  <div className={`h-2 w-2 rounded-full mt-2 ${
                    alert.level === 'error' ? 'bg-red-400' :
                    alert.level === 'warning' ? 'bg-yellow-400' : 'bg-blue-400'
                  }`}></div>
                  <div className="flex-1">
                    <div className="text-sm text-gray-900">{alert.message}</div>
                    <div className="text-xs text-gray-500">{alert.time}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </MainLayout>
  );
}