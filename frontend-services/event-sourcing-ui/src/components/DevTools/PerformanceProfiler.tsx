'use client';

import { useState, useEffect } from 'react';
import {
  CpuChipIcon,
  ClockIcon,
  ChartBarIcon,
  ServerIcon,
  ExclamationTriangleIcon,
  PlayIcon,
  StopIcon
} from '@heroicons/react/24/outline';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, AreaChart, Area, BarChart, Bar } from 'recharts';

interface PerformanceMetric {
  timestamp: Date;
  eventThroughput: number;
  avgLatency: number;
  p95Latency: number;
  memoryUsage: number;
  cpuUsage: number;
  errorRate: number;
  queueDepth: number;
}

interface ProfileSession {
  id: string;
  name: string;
  startTime: Date;
  endTime?: Date;
  duration: number;
  status: 'running' | 'completed' | 'failed';
  metrics: PerformanceMetric[];
}

interface BottleneckAnalysis {
  component: string;
  severity: 'high' | 'medium' | 'low';
  description: string;
  impact: string;
  recommendation: string;
}

export default function PerformanceProfiler() {
  const [sessions, setSessions] = useState<ProfileSession[]>([]);
  const [currentSession, setCurrentSession] = useState<ProfileSession | null>(null);
  const [isProfileting, setIsProfileting] = useState(false);
  const [sessionName, setSessionName] = useState('');
  const [showCreateForm, setShowCreateForm] = useState(false);

  // Mock bottlenecks for demonstration
  const [bottlenecks] = useState<BottleneckAnalysis[]>([
    {
      component: 'Event Serialization',
      severity: 'high',
      description: 'JSON serialization is consuming 45% of processing time',
      impact: 'Reducing overall throughput by ~30%',
      recommendation: 'Consider switching to more efficient serialization format like Protocol Buffers'
    },
    {
      component: 'Database Writes',
      severity: 'medium',
      description: 'Event store writes showing high latency during peak loads',
      impact: 'P95 latency increased to 250ms during traffic spikes',
      recommendation: 'Implement write batching and connection pooling optimization'
    },
    {
      component: 'SAGA State Persistence',
      severity: 'medium',
      description: 'SAGA state updates creating lock contention',
      impact: 'Occasional timeouts during concurrent SAGA execution',
      recommendation: 'Optimize SAGA state storage with better isolation levels'
    },
    {
      component: 'Projection Updates',
      severity: 'low',
      description: 'Read model updates lagging behind event stream',
      impact: 'Average lag of 2.5 seconds in projection updates',
      recommendation: 'Increase projection consumer instances and optimize queries'
    }
  ]);

  // Generate mock performance data
  const generateMockMetrics = (): PerformanceMetric => ({
    timestamp: new Date(),
    eventThroughput: 80 + Math.random() * 40,
    avgLatency: 45 + Math.random() * 30,
    p95Latency: 120 + Math.random() * 80,
    memoryUsage: 60 + Math.random() * 20,
    cpuUsage: 30 + Math.random() * 40,
    errorRate: Math.random() * 2,
    queueDepth: 50 + Math.random() * 100
  });

  // Start profiling session
  const startProfiling = () => {
    if (!sessionName.trim()) return;

    const newSession: ProfileSession = {
      id: `session-${Date.now()}`,
      name: sessionName,
      startTime: new Date(),
      duration: 0,
      status: 'running',
      metrics: []
    };

    setSessions(prev => [newSession, ...prev]);
    setCurrentSession(newSession);
    setIsProfileting(true);
    setSessionName('');
    setShowCreateForm(false);
  };

  // Stop profiling session
  const stopProfiling = () => {
    if (!currentSession) return;

    const updatedSession: ProfileSession = {
      ...currentSession,
      endTime: new Date(),
      status: 'completed',
      duration: Date.now() - currentSession.startTime.getTime()
    };

    setSessions(prev => prev.map(s => s.id === currentSession.id ? updatedSession : s));
    setCurrentSession(null);
    setIsProfileting(false);
  };

  // Update current session with new metrics
  useEffect(() => {
    if (!isProfileting || !currentSession) return;

    const interval = setInterval(() => {
      const newMetric = generateMockMetrics();
      
      setCurrentSession(prev => {
        if (!prev) return null;
        const updatedSession = {
          ...prev,
          duration: Date.now() - prev.startTime.getTime(),
          metrics: [...prev.metrics, newMetric].slice(-50) // Keep last 50 metrics
        };
        
        // Update in sessions array
        setSessions(prevSessions => 
          prevSessions.map(s => s.id === prev.id ? updatedSession : s)
        );
        
        return updatedSession;
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [isProfileting, currentSession]);

  const getSeverityColor = (severity: 'high' | 'medium' | 'low') => {
    switch (severity) {
      case 'high':
        return 'bg-red-100 text-red-800 border-red-200';
      case 'medium':
        return 'bg-yellow-100 text-yellow-800 border-yellow-200';
      case 'low':
        return 'bg-blue-100 text-blue-800 border-blue-200';
    }
  };

  const formatDuration = (ms: number) => {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    return minutes > 0 ? `${minutes}m ${seconds % 60}s` : `${seconds}s`;
  };

  // Prepare chart data
  const chartData = currentSession?.metrics.slice(-20).map((metric, index) => ({
    time: `${index}s`,
    throughput: metric.eventThroughput,
    latency: metric.avgLatency,
    p95Latency: metric.p95Latency,
    cpu: metric.cpuUsage,
    memory: metric.memoryUsage,
    errorRate: metric.errorRate,
    queueDepth: metric.queueDepth
  })) || [];

  return (
    <div className="space-y-6">
      {/* Control Panel */}
      <div className="card">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-medium text-gray-900">Performance Profiler</h3>
          <div className="flex space-x-3">
            {!isProfileting ? (
              <button
                onClick={() => setShowCreateForm(true)}
                className="btn-primary flex items-center space-x-2"
              >
                <PlayIcon className="h-4 w-4" />
                <span>Start Profiling</span>
              </button>
            ) : (
              <button
                onClick={stopProfiling}
                className="btn-danger flex items-center space-x-2"
              >
                <StopIcon className="h-4 w-4" />
                <span>Stop Profiling</span>
              </button>
            )}
          </div>
        </div>

        {/* Current Session Status */}
        {currentSession && (
          <div className="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
            <div className="flex items-center justify-between">
              <div>
                <h4 className="font-medium text-blue-900">{currentSession.name}</h4>
                <p className="text-sm text-blue-700">
                  Running for {formatDuration(currentSession.duration)}
                </p>
              </div>
              <div className="flex items-center space-x-2">
                <div className="h-3 w-3 bg-green-400 rounded-full animate-pulse"></div>
                <span className="text-sm text-blue-700">Recording</span>
              </div>
            </div>
          </div>
        )}

        {/* Quick Stats */}
        {currentSession && currentSession.metrics.length > 0 && (
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {(() => {
              const latest = currentSession.metrics[currentSession.metrics.length - 1];
              return (
                <>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-gray-900">
                      {latest.eventThroughput.toFixed(0)}
                    </div>
                    <div className="text-sm text-gray-500">Events/sec</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-blue-600">
                      {latest.avgLatency.toFixed(0)}ms
                    </div>
                    <div className="text-sm text-gray-500">Avg Latency</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-purple-600">
                      {latest.cpuUsage.toFixed(0)}%
                    </div>
                    <div className="text-sm text-gray-500">CPU Usage</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-green-600">
                      {latest.memoryUsage.toFixed(0)}%
                    </div>
                    <div className="text-sm text-gray-500">Memory</div>
                  </div>
                </>
              );
            })()}
          </div>
        )}
      </div>

      {/* Real-time Charts */}
      {isProfileting && chartData.length > 0 && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Throughput & Latency */}
          <div className="card">
            <h4 className="text-lg font-medium text-gray-900 mb-4">Throughput & Latency</h4>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
                  <XAxis dataKey="time" className="text-xs" axisLine={false} tickLine={false} />
                  <YAxis className="text-xs" axisLine={false} tickLine={false} />
                  <Tooltip 
                    contentStyle={{
                      backgroundColor: '#374151',
                      border: 'none',
                      borderRadius: '8px',
                      color: 'white'
                    }}
                  />
                  <Line type="monotone" dataKey="throughput" stroke="#3b82f6" strokeWidth={2} dot={false} name="Events/sec" />
                  <Line type="monotone" dataKey="latency" stroke="#ef4444" strokeWidth={2} dot={false} name="Avg Latency (ms)" />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Resource Usage */}
          <div className="card">
            <h4 className="text-lg font-medium text-gray-900 mb-4">Resource Usage</h4>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
                  <XAxis dataKey="time" className="text-xs" axisLine={false} tickLine={false} />
                  <YAxis className="text-xs" axisLine={false} tickLine={false} domain={[0, 100]} />
                  <Tooltip 
                    contentStyle={{
                      backgroundColor: '#374151',
                      border: 'none',
                      borderRadius: '8px',
                      color: 'white'
                    }}
                  />
                  <Area type="monotone" dataKey="cpu" stackId="1" stroke="#f59e0b" fill="#f59e0b" fillOpacity={0.3} name="CPU %" />
                  <Area type="monotone" dataKey="memory" stackId="1" stroke="#10b981" fill="#10b981" fillOpacity={0.3} name="Memory %" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Error Rate */}
          <div className="card">
            <h4 className="text-lg font-medium text-gray-900 mb-4">Error Rate</h4>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
                  <XAxis dataKey="time" className="text-xs" axisLine={false} tickLine={false} />
                  <YAxis className="text-xs" axisLine={false} tickLine={false} />
                  <Tooltip 
                    contentStyle={{
                      backgroundColor: '#374151',
                      border: 'none',
                      borderRadius: '8px',
                      color: 'white'
                    }}
                  />
                  <Bar dataKey="errorRate" fill="#ef4444" name="Error Rate %" />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Queue Depth */}
          <div className="card">
            <h4 className="text-lg font-medium text-gray-900 mb-4">Queue Depth</h4>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
                  <XAxis dataKey="time" className="text-xs" axisLine={false} tickLine={false} />
                  <YAxis className="text-xs" axisLine={false} tickLine={false} />
                  <Tooltip 
                    contentStyle={{
                      backgroundColor: '#374151',
                      border: 'none',
                      borderRadius: '8px',
                      color: 'white'
                    }}
                  />
                  <Line type="monotone" dataKey="queueDepth" stroke="#8b5cf6" strokeWidth={2} dot={false} name="Queue Depth" />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Bottleneck Analysis */}
        <div className="card p-0">
          <div className="px-6 py-4 border-b border-gray-200">
            <h4 className="text-lg font-medium text-gray-900">Bottleneck Analysis</h4>
          </div>
          <div className="max-h-[400px] overflow-y-auto scrollbar-thin">
            <div className="divide-y divide-gray-200">
              {bottlenecks.map((bottleneck, index) => (
                <div key={index} className="px-6 py-4">
                  <div className="flex items-start space-x-3">
                    <ExclamationTriangleIcon className={`h-5 w-5 mt-0.5 ${
                      bottleneck.severity === 'high' ? 'text-red-500' :
                      bottleneck.severity === 'medium' ? 'text-yellow-500' :
                      'text-blue-500'
                    }`} />
                    <div className="flex-1">
                      <div className="flex items-center space-x-2 mb-2">
                        <span className="font-medium text-gray-900">{bottleneck.component}</span>
                        <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border ${getSeverityColor(bottleneck.severity)}`}>
                          {bottleneck.severity}
                        </span>
                      </div>
                      <p className="text-sm text-gray-600 mb-2">{bottleneck.description}</p>
                      <p className="text-sm text-gray-500 mb-2">
                        <span className="font-medium">Impact:</span> {bottleneck.impact}
                      </p>
                      <p className="text-sm text-blue-600">
                        <span className="font-medium">Recommendation:</span> {bottleneck.recommendation}
                      </p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Session History */}
        <div className="card p-0">
          <div className="px-6 py-4 border-b border-gray-200">
            <h4 className="text-lg font-medium text-gray-900">Session History</h4>
          </div>
          <div className="max-h-[400px] overflow-y-auto scrollbar-thin">
            {sessions.length === 0 ? (
              <div className="px-6 py-12 text-center">
                <CpuChipIcon className="mx-auto h-12 w-12 text-gray-400" />
                <h3 className="mt-2 text-sm font-medium text-gray-900">No sessions yet</h3>
                <p className="mt-1 text-sm text-gray-500">
                  Start your first profiling session to see data here.
                </p>
              </div>
            ) : (
              <div className="divide-y divide-gray-200">
                {sessions.map((session) => (
                  <div key={session.id} className="px-6 py-4 hover:bg-gray-50">
                    <div className="flex items-center justify-between">
                      <div className="flex-1">
                        <div className="flex items-center space-x-3 mb-1">
                          <span className="text-sm font-medium text-gray-900">
                            {session.name}
                          </span>
                          <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                            session.status === 'running' ? 'bg-blue-100 text-blue-800' :
                            session.status === 'completed' ? 'bg-green-100 text-green-800' :
                            'bg-red-100 text-red-800'
                          }`}>
                            {session.status}
                          </span>
                        </div>
                        <div className="text-xs text-gray-500">
                          Started: {session.startTime.toLocaleString()}
                        </div>
                        <div className="text-xs text-gray-500">
                          Duration: {formatDuration(session.duration)}
                        </div>
                        <div className="text-xs text-gray-500">
                          Metrics: {session.metrics.length} data points
                        </div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Create Session Modal */}
      {showCreateForm && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50 flex items-center justify-center">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="p-6">
              <div className="flex items-center justify-between mb-6">
                <h3 className="text-lg font-medium text-gray-900">Start Profiling Session</h3>
                <button
                  onClick={() => setShowCreateForm(false)}
                  className="text-gray-400 hover:text-gray-600"
                >
                  ×
                </button>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">Session Name</label>
                  <input
                    type="text"
                    value={sessionName}
                    onChange={(e) => setSessionName(e.target.value)}
                    className="input-field w-full mt-1"
                    placeholder="e.g., Load Test - 1000 users"
                  />
                </div>

                <div className="text-sm text-gray-600">
                  <p className="mb-2">This will start collecting performance metrics including:</p>
                  <ul className="list-disc list-inside space-y-1 text-xs">
                    <li>Event throughput and latency</li>
                    <li>CPU and memory usage</li>
                    <li>Error rates and queue depths</li>
                    <li>SAGA and projection performance</li>
                  </ul>
                </div>
              </div>

              <div className="mt-6 flex justify-end space-x-3">
                <button
                  onClick={() => setShowCreateForm(false)}
                  className="btn-secondary"
                >
                  Cancel
                </button>
                <button
                  onClick={startProfiling}
                  disabled={!sessionName.trim()}
                  className="btn-primary"
                >
                  Start Profiling
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}