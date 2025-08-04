'use client';

import { useState } from 'react';
import { EventTest, EventSchema, TestStatus } from '@/types';
import ReactJsonView from 'react-json-view';
import {
  PlayIcon,
  PlusIcon,
  CheckCircleIcon,
  XCircleIcon,
  ClockIcon,
  StopIcon
} from '@heroicons/react/24/outline';

interface EventTesterProps {
  tests: EventTest[];
  schemas: EventSchema[];
  onRunTest: (test: EventTest) => void;
  onCreateTest: (test: Omit<EventTest, 'id' | 'status'>) => void;
}

export default function EventTester({ tests, schemas, onRunTest, onCreateTest }: EventTesterProps) {
  const [selectedTest, setSelectedTest] = useState<EventTest | null>(null);
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [newTest, setNewTest] = useState({
    name: '',
    eventType: '',
    aggregateId: '',
    data: '{}',
    expectedOutcome: ''
  });

  const getStatusIcon = (status: TestStatus) => {
    switch (status) {
      case TestStatus.PASSED:
        return <CheckCircleIcon className="h-5 w-5 text-green-500" />;
      case TestStatus.FAILED:
        return <XCircleIcon className="h-5 w-5 text-red-500" />;
      case TestStatus.RUNNING:
        return <ClockIcon className="h-5 w-5 text-blue-500 animate-pulse" />;
      default:
        return <StopIcon className="h-5 w-5 text-gray-500" />;
    }
  };

  const getStatusColor = (status: TestStatus) => {
    switch (status) {
      case TestStatus.PASSED:
        return 'status-success';
      case TestStatus.FAILED:
        return 'status-error';
      case TestStatus.RUNNING:
        return 'status-info';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const handleCreateTest = () => {
    try {
      const parsedData = JSON.parse(newTest.data);
      onCreateTest({
        name: newTest.name,
        eventType: newTest.eventType,
        aggregateId: newTest.aggregateId,
        data: parsedData,
        expectedOutcome: newTest.expectedOutcome
      });
      
      setNewTest({
        name: '',
        eventType: '',
        aggregateId: '',
        data: '{}',
        expectedOutcome: ''
      });
      setShowCreateForm(false);
    } catch (error) {
      alert('Invalid JSON data format');
    }
  };

  const loadSchemaExample = (eventType: string) => {
    const schema = schemas.find(s => s.eventType === eventType);
    if (schema && schema.examples.length > 0) {
      setNewTest(prev => ({
        ...prev,
        data: JSON.stringify(schema.examples[0], null, 2)
      }));
    }
  };

  const statusCounts = {
    total: tests.length,
    passed: tests.filter(t => t.status === TestStatus.PASSED).length,
    failed: tests.filter(t => t.status === TestStatus.FAILED).length,
    running: tests.filter(t => t.status === TestStatus.RUNNING).length,
    pending: tests.filter(t => t.status === TestStatus.PENDING).length
  };

  return (
    <div className="space-y-6">
      {/* Header with Stats */}
      <div className="card">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-medium text-gray-900">Event Tests</h3>
          <button
            onClick={() => setShowCreateForm(true)}
            className="btn-primary flex items-center space-x-2"
          >
            <PlusIcon className="h-4 w-4" />
            <span>Create Test</span>
          </button>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 text-sm">
          <div className="text-center">
            <div className="text-2xl font-bold text-gray-900">{statusCounts.total}</div>
            <div className="text-gray-500">Total</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-green-600">{statusCounts.passed}</div>
            <div className="text-gray-500">Passed</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-red-600">{statusCounts.failed}</div>
            <div className="text-gray-500">Failed</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-blue-600">{statusCounts.running}</div>
            <div className="text-gray-500">Running</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-gray-600">{statusCounts.pending}</div>
            <div className="text-gray-500">Pending</div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Test List */}
        <div className="card p-0">
          <div className="px-6 py-4 border-b border-gray-200">
            <h4 className="text-lg font-medium text-gray-900">Test Cases</h4>
          </div>

          <div className="max-h-[600px] overflow-y-auto scrollbar-thin">
            <div className="divide-y divide-gray-200">
              {tests.map((test) => (
                <div
                  key={test.id}
                  onClick={() => setSelectedTest(test)}
                  className={`px-6 py-4 hover:bg-gray-50 cursor-pointer transition-colors ${
                    selectedTest?.id === test.id ? 'bg-primary-50 border-l-4 border-primary-500' : ''
                  }`}
                >
                  <div className="flex items-start justify-between">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center space-x-3 mb-2">
                        {getStatusIcon(test.status)}
                        <span className="text-sm font-medium text-gray-900">
                          {test.name}
                        </span>
                        <span className={`status-badge ${getStatusColor(test.status)}`}>
                          {test.status}
                        </span>
                      </div>

                      <div className="text-xs text-gray-500 mb-2">
                        {test.eventType} • {test.aggregateId}
                      </div>

                      {test.expectedOutcome && (
                        <div className="text-xs text-gray-600 mb-2 line-clamp-2">
                          Expected: {test.expectedOutcome}
                        </div>
                      )}

                      {test.result && (
                        <div className="text-xs">
                          <div className={`${test.result.success ? 'text-green-600' : 'text-red-600'}`}>
                            {test.result.message}
                          </div>
                          <div className="text-gray-500 mt-1">
                            Execution time: {test.result.executionTime}ms
                          </div>
                        </div>
                      )}
                    </div>

                    <div className="flex-shrink-0 ml-4">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          onRunTest(test);
                        }}
                        disabled={test.status === TestStatus.RUNNING}
                        className={`btn-primary text-xs flex items-center space-x-1 ${
                          test.status === TestStatus.RUNNING ? 'opacity-50 cursor-not-allowed' : ''
                        }`}
                      >
                        <PlayIcon className="h-3 w-3" />
                        <span>Run</span>
                      </button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Test Details */}
        <div className="space-y-6">
          {selectedTest ? (
            <>
              <div className="card">
                <div className="flex items-center justify-between mb-4">
                  <h4 className="text-lg font-medium text-gray-900">Test Details</h4>
                  <button
                    onClick={() => onRunTest(selectedTest)}
                    disabled={selectedTest.status === TestStatus.RUNNING}
                    className="btn-primary flex items-center space-x-2"
                  >
                    <PlayIcon className="h-4 w-4" />
                    <span>Run Test</span>
                  </button>
                </div>

                <div className="space-y-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700">Test Name</label>
                    <div className="mt-1 text-sm text-gray-900">{selectedTest.name}</div>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">Event Type</label>
                      <div className="mt-1 text-sm text-gray-900">{selectedTest.eventType}</div>
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700">Aggregate ID</label>
                      <div className="mt-1 text-sm text-gray-900 font-mono">{selectedTest.aggregateId}</div>
                    </div>
                  </div>

                  {selectedTest.expectedOutcome && (
                    <div>
                      <label className="block text-sm font-medium text-gray-700">Expected Outcome</label>
                      <div className="mt-1 text-sm text-gray-900">{selectedTest.expectedOutcome}</div>
                    </div>
                  )}
                </div>
              </div>

              <div className="card">
                <h4 className="text-lg font-medium text-gray-900 mb-4">Test Data</h4>
                <div className="bg-gray-50 rounded-lg p-4 max-h-64 overflow-y-auto">
                  <ReactJsonView
                    src={selectedTest.data}
                    theme="bright:inverted"
                    name={false}
                    collapsed={false}
                    displayDataTypes={false}
                    displayObjectSize={false}
                    enableClipboard={false}
                    style={{ backgroundColor: 'transparent', fontSize: '12px' }}
                  />
                </div>
              </div>

              {selectedTest.result && (
                <div className="card">
                  <h4 className="text-lg font-medium text-gray-900 mb-4">Test Results</h4>
                  <div className="space-y-3">
                    <div className="flex items-center space-x-3">
                      {getStatusIcon(selectedTest.status)}
                      <span className="font-medium">
                        {selectedTest.result.success ? 'Test Passed' : 'Test Failed'}
                      </span>
                    </div>
                    
                    <div className="text-sm text-gray-600">
                      {selectedTest.result.message}
                    </div>
                    
                    <div className="text-sm text-gray-500">
                      Execution time: {selectedTest.result.executionTime}ms
                    </div>

                    {selectedTest.result.actualEvents && (
                      <div>
                        <h5 className="text-sm font-medium text-gray-900 mb-2">Generated Events</h5>
                        <div className="bg-gray-50 rounded-lg p-4 max-h-64 overflow-y-auto">
                          <ReactJsonView
                            src={selectedTest.result.actualEvents}
                            theme="bright:inverted"
                            name={false}
                            collapsed={1}
                            displayDataTypes={false}
                            displayObjectSize={false}
                            enableClipboard={false}
                            style={{ backgroundColor: 'transparent', fontSize: '12px' }}
                          />
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </>
          ) : (
            <div className="card">
              <div className="text-center py-12">
                <PlayIcon className="mx-auto h-12 w-12 text-gray-400" />
                <h3 className="mt-2 text-sm font-medium text-gray-900">No test selected</h3>
                <p className="mt-1 text-sm text-gray-500">
                  Select a test from the list to view its details and run it.
                </p>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Create Test Modal */}
      {showCreateForm && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50 flex items-center justify-center">
          <div className="bg-white rounded-lg shadow-xl max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="p-6">
              <div className="flex items-center justify-between mb-6">
                <h3 className="text-lg font-medium text-gray-900">Create New Test</h3>
                <button
                  onClick={() => setShowCreateForm(false)}
                  className="text-gray-400 hover:text-gray-600"
                >
                  ×
                </button>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">Test Name</label>
                  <input
                    type="text"
                    value={newTest.name}
                    onChange={(e) => setNewTest(prev => ({ ...prev, name: e.target.value }))}
                    className="input-field w-full mt-1"
                    placeholder="Enter test name"
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700">Event Type</label>
                    <select
                      value={newTest.eventType}
                      onChange={(e) => {
                        setNewTest(prev => ({ ...prev, eventType: e.target.value }));
                        if (e.target.value) {
                          loadSchemaExample(e.target.value);
                        }
                      }}
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
                    <label className="block text-sm font-medium text-gray-700">Aggregate ID</label>
                    <input
                      type="text"
                      value={newTest.aggregateId}
                      onChange={(e) => setNewTest(prev => ({ ...prev, aggregateId: e.target.value }))}
                      className="input-field w-full mt-1"
                      placeholder="test-aggregate-123"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">Event Data (JSON)</label>
                  <textarea
                    value={newTest.data}
                    onChange={(e) => setNewTest(prev => ({ ...prev, data: e.target.value }))}
                    className="input-field w-full mt-1 font-mono text-sm"
                    rows={8}
                    placeholder='{"field": "value"}'
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700">Expected Outcome</label>
                  <textarea
                    value={newTest.expectedOutcome}
                    onChange={(e) => setNewTest(prev => ({ ...prev, expectedOutcome: e.target.value }))}
                    className="input-field w-full mt-1"
                    rows={3}
                    placeholder="Describe what should happen when this event is processed..."
                  />
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
                  onClick={handleCreateTest}
                  disabled={!newTest.name || !newTest.eventType || !newTest.aggregateId}
                  className="btn-primary"
                >
                  Create Test
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}