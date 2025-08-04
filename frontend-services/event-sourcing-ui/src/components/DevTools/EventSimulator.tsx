'use client';

import { useState, useEffect } from 'react';
import { EventSchema } from '@/types';
import {
  PlayIcon,
  StopIcon,
  PauseIcon,
  ArrowPathIcon,
  ChartBarIcon,
  ClockIcon
} from '@heroicons/react/24/outline';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

interface EventSimulatorProps {
  schemas: EventSchema[];
}

interface SimulationConfig {
  eventType: string;
  rate: number; // events per second
  duration: number; // seconds
  variability: number; // percentage variance in timing
}

interface SimulationStats {
  totalEvents: number;
  eventsPerSecond: number;
  startTime?: Date;
  elapsedTime: number;
  isRunning: boolean;
}

export default function EventSimulator({ schemas }: EventSimulatorProps) {
  const [simulations, setSimulations] = useState<SimulationConfig[]>([]);
  const [stats, setStats] = useState<SimulationStats>({
    totalEvents: 0,
    eventsPerSecond: 0,
    elapsedTime: 0,
    isRunning: false
  });
  const [metricsHistory, setMetricsHistory] = useState<Array<{
    time: string;
    eventsPerSecond: number;
    totalEvents: number;
  }>>([]);
  const [showAddForm, setShowAddForm] = useState(false);

  const [newSimulation, setNewSimulation] = useState<SimulationConfig>({
    eventType: '',
    rate: 10,
    duration: 60,
    variability: 20
  });

  // Simulation engine
  useEffect(() => {
    if (!stats.isRunning) return;

    const interval = setInterval(() => {
      setStats(prev => {
        const newElapsed = prev.startTime 
          ? (Date.now() - prev.startTime.getTime()) / 1000 
          : prev.elapsedTime + 1;
        
        // Calculate events generated in this second
        const eventsThisSecond = simulations.reduce((total, sim) => {
          const baseRate = sim.rate;
          const variance = (Math.random() - 0.5) * 2 * (sim.variability / 100);
          const actualRate = Math.max(0, baseRate * (1 + variance));
          return total + actualRate;
        }, 0);

        const newTotal = prev.totalEvents + eventsThisSecond;

        // Update metrics history
        setMetricsHistory(prevHistory => {
          const newPoint = {
            time: new Date().toISOString().substr(11, 8),
            eventsPerSecond: eventsThisSecond,
            totalEvents: newTotal
          };
          return [...prevHistory.slice(-19), newPoint];
        });

        return {
          ...prev,
          totalEvents: newTotal,
          eventsPerSecond: eventsThisSecond,
          elapsedTime: newElapsed
        };
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [stats.isRunning, simulations]);

  const startSimulation = () => {
    setStats(prev => ({
      ...prev,
      isRunning: true,
      startTime: new Date(),
      totalEvents: 0,
      elapsedTime: 0
    }));
  };

  const stopSimulation = () => {
    setStats(prev => ({
      ...prev,
      isRunning: false,
      startTime: undefined
    }));
  };

  const resetSimulation = () => {
    setStats({
      totalEvents: 0,
      eventsPerSecond: 0,
      elapsedTime: 0,
      isRunning: false
    });
    setMetricsHistory([]);
  };

  const addSimulation = () => {
    if (newSimulation.eventType && newSimulation.rate > 0) {
      setSimulations(prev => [...prev, { ...newSimulation }]);
      setNewSimulation({
        eventType: '',
        rate: 10,
        duration: 60,
        variability: 20
      });
      setShowAddForm(false);
    }
  };

  const removeSimulation = (index: number) => {
    setSimulations(prev => prev.filter((_, i) => i !== index));
  };

  const totalConfiguredRate = simulations.reduce((sum, sim) => sum + sim.rate, 0);

  return (
    <div className="space-y-6">
      {/* Control Panel */}
      <div className="card">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-medium text-gray-900">Event Simulator</h3>
          <div className="flex space-x-3">
            {!stats.isRunning ? (
              <button
                onClick={startSimulation}
                disabled={simulations.length === 0}
                className="btn-primary flex items-center space-x-2"
              >
                <PlayIcon className="h-4 w-4" />
                <span>Start</span>
              </button>
            ) : (
              <button
                onClick={stopSimulation}
                className="btn-danger flex items-center space-x-2"
              >
                <StopIcon className="h-4 w-4" />
                <span>Stop</span>
              </button>
            )}
            <button
              onClick={resetSimulation}
              className="btn-secondary flex items-center space-x-2"
            >
              <ArrowPathIcon className="h-4 w-4" />
              <span>Reset</span>
            </button>
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          <div className="text-center">
            <div className="text-2xl font-bold text-gray-900">{stats.totalEvents}</div>
            <div className="text-sm text-gray-500">Total Events</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-blue-600">
              {stats.eventsPerSecond.toFixed(1)}
            </div>
            <div className="text-sm text-gray-500">Events/sec</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-green-600">
              {totalConfiguredRate}
            </div>
            <div className="text-sm text-gray-500">Target Rate</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-purple-600">
              {Math.floor(stats.elapsedTime)}s
            </div>
            <div className="text-sm text-gray-500">Elapsed</div>
          </div>
        </div>

        {/* Status Indicator */}
        <div className="flex items-center justify-center space-x-2">
          <div className={`h-3 w-3 rounded-full ${
            stats.isRunning ? 'bg-green-400 animate-pulse' : 'bg-gray-400'
          }`}></div>
          <span className="text-sm text-gray-600">
            {stats.isRunning ? 'Simulation Running' : 'Simulation Stopped'}
          </span>
        </div>
      </div>

      {/* Metrics Chart */}
      <div className="card">
        <div className="flex items-center justify-between mb-4">
          <h4 className="text-lg font-medium text-gray-900">Event Generation Rate</h4>
          <div className="flex items-center space-x-4 text-sm">
            <div className="flex items-center space-x-2">
              <div className="h-3 w-3 bg-blue-500 rounded"></div>
              <span>Events/sec</span>
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
                dataKey="eventsPerSecond" 
                stroke="#3b82f6" 
                strokeWidth={2}
                dot={false}
                name="Events/sec"
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Configured Simulations */}
        <div className="card p-0">
          <div className="px-6 py-4 border-b border-gray-200">
            <div className="flex items-center justify-between">
              <h4 className="text-lg font-medium text-gray-900">Event Simulations</h4>
              <button
                onClick={() => setShowAddForm(true)}
                className="btn-primary text-sm flex items-center space-x-1"
              >
                <PlayIcon className="h-3 w-3" />
                <span>Add</span>
              </button>
            </div>
          </div>

          <div className="max-h-[400px] overflow-y-auto scrollbar-thin">
            {simulations.length === 0 ? (
              <div className="px-6 py-12 text-center">
                <ChartBarIcon className="mx-auto h-12 w-12 text-gray-400" />
                <h3 className="mt-2 text-sm font-medium text-gray-900">No simulations configured</h3>
                <p className="mt-1 text-sm text-gray-500">
                  Add event simulations to start generating test events.
                </p>
              </div>
            ) : (
              <div className="divide-y divide-gray-200">
                {simulations.map((sim, index) => (
                  <div key={index} className="px-6 py-4">
                    <div className="flex items-center justify-between">
                      <div className="flex-1">
                        <div className="flex items-center space-x-3 mb-2">
                          <span className="text-sm font-medium text-gray-900">
                            {sim.eventType}
                          </span>
                          <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                            {sim.rate}/sec
                          </span>
                        </div>
                        
                        <div className="grid grid-cols-2 gap-4 text-xs text-gray-600">
                          <div>
                            <span className="text-gray-500">Duration:</span> {sim.duration}s
                          </div>
                          <div>
                            <span className="text-gray-500">Variability:</span> ±{sim.variability}%
                          </div>
                        </div>
                      </div>
                      
                      <button
                        onClick={() => removeSimulation(index)}
                        disabled={stats.isRunning}
                        className="text-red-600 hover:text-red-800 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        ×
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Event Preview */}
        <div className="card">
          <h4 className="text-lg font-medium text-gray-900 mb-4">Recent Events</h4>
          
          {stats.totalEvents === 0 ? (
            <div className="text-center py-8">
              <ClockIcon className="mx-auto h-8 w-8 text-gray-400" />
              <p className="mt-2 text-sm text-gray-500">
                No events generated yet. Start a simulation to see events here.
              </p>
            </div>
          ) : (
            <div className="space-y-3 max-h-[300px] overflow-y-auto scrollbar-thin">
              {/* Mock recent events - in real implementation, this would show actual generated events */}
              {Array.from({ length: Math.min(10, Math.floor(stats.totalEvents / 10)) }, (_, i) => (
                <div key={i} className="flex items-center space-x-3 text-sm">
                  <div className="h-2 w-2 bg-green-400 rounded-full"></div>
                  <div className="flex-1">
                    <div className="font-medium text-gray-900">
                      {simulations[i % simulations.length]?.eventType || 'TestEvent'}
                    </div>
                    <div className="text-gray-500 text-xs">
                      aggregate-{Math.floor(Math.random() * 1000)} • {new Date().toLocaleTimeString()}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Add Simulation Modal */}
      {showAddForm && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50 flex items-center justify-center">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="p-6">
              <div className="flex items-center justify-between mb-6">
                <h3 className="text-lg font-medium text-gray-900">Add Event Simulation</h3>
                <button
                  onClick={() => setShowAddForm(false)}
                  className="text-gray-400 hover:text-gray-600"
                >
                  ×
                </button>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">Event Type</label>
                  <select
                    value={newSimulation.eventType}
                    onChange={(e) => setNewSimulation(prev => ({ ...prev, eventType: e.target.value }))}
                    className="input-field w-full mt-1"
                  >
                    <option value="">Select event type</option>
                    {schemas.map(schema => (
                      <option key={`${schema.eventType}-${schema.version}`} value={schema.eventType}>
                        {schema.eventType} (v{schema.version})
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">
                    Rate (events per second)
                  </label>
                  <input
                    type="number"
                    min="0.1"
                    max="1000"
                    step="0.1"
                    value={newSimulation.rate}
                    onChange={(e) => setNewSimulation(prev => ({ ...prev, rate: parseFloat(e.target.value) }))}
                    className="input-field w-full mt-1"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">
                    Duration (seconds)
                  </label>
                  <input
                    type="number"
                    min="1"
                    max="3600"
                    value={newSimulation.duration}
                    onChange={(e) => setNewSimulation(prev => ({ ...prev, duration: parseInt(e.target.value) }))}
                    className="input-field w-full mt-1"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">
                    Variability (±%)
                  </label>
                  <input
                    type="number"
                    min="0"
                    max="100"
                    value={newSimulation.variability}
                    onChange={(e) => setNewSimulation(prev => ({ ...prev, variability: parseInt(e.target.value) }))}
                    className="input-field w-full mt-1"
                  />
                  <p className="mt-1 text-xs text-gray-500">
                    Random variance in event timing
                  </p>
                </div>
              </div>

              <div className="mt-6 flex justify-end space-x-3">
                <button
                  onClick={() => setShowAddForm(false)}
                  className="btn-secondary"
                >
                  Cancel
                </button>
                <button
                  onClick={addSimulation}
                  disabled={!newSimulation.eventType || newSimulation.rate <= 0}
                  className="btn-primary"
                >
                  Add Simulation
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}