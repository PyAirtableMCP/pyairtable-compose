'use client';

import { useState, useEffect, useCallback } from 'react';
import MainLayout from '@/components/Layout/MainLayout';
import EventFilters from '@/components/Events/EventFilters';
import EventList from '@/components/Events/EventList';
import EventDetails from '@/components/Events/EventDetails';
import { Event, EventFilter } from '@/types';
import { 
  MagnifyingGlassIcon,
  FunnelIcon,
  ArrowPathIcon,
  PlayIcon,
  PauseIcon
} from '@heroicons/react/24/outline';

// Mock data for demonstration
const mockEvents: Event[] = [
  {
    id: '1',
    aggregateId: 'user-123',
    aggregateType: 'User',
    eventType: 'UserRegistered',
    version: 1,
    timestamp: new Date(Date.now() - 60000),
    data: {
      email: 'user@example.com',
      name: 'John Doe',
      plan: 'premium'
    },
    metadata: {
      source: 'web-app',
      userId: 'admin-456'
    },
    correlationId: 'corr-123',
    causationId: 'cause-456'
  },
  {
    id: '2',
    aggregateId: 'order-456',
    aggregateType: 'Order',
    eventType: 'PaymentProcessed',
    version: 2,
    timestamp: new Date(Date.now() - 120000),
    data: {
      amount: 99.99,
      currency: 'USD',
      paymentMethod: 'credit_card'
    },
    metadata: {
      source: 'payment-service',
      requestId: 'req-789'
    },
    correlationId: 'corr-456'
  },
  {
    id: '3',
    aggregateId: 'workspace-789',
    aggregateType: 'Workspace',
    eventType: 'WorkspaceCreated',
    version: 1,
    timestamp: new Date(Date.now() - 180000),
    data: {
      name: 'My Workspace',
      ownerId: 'user-123',
      plan: 'team'
    },
    metadata: {
      source: 'workspace-service'
    },
    correlationId: 'corr-789'
  }
];

export default function EventsPage() {
  const [events, setEvents] = useState<Event[]>(mockEvents);
  const [filteredEvents, setFilteredEvents] = useState<Event[]>(mockEvents);
  const [selectedEvent, setSelectedEvent] = useState<Event | null>(null);
  const [filters, setFilters] = useState<EventFilter>({});
  const [searchTerm, setSearchTerm] = useState('');
  const [isRealTimeEnabled, setIsRealTimeEnabled] = useState(true);
  const [showFilters, setShowFilters] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  // Filter events based on search term and filters
  const applyFilters = useCallback(() => {
    let filtered = events;

    // Apply search term
    if (searchTerm) {
      filtered = filtered.filter(event => 
        event.eventType.toLowerCase().includes(searchTerm.toLowerCase()) ||
        event.aggregateType.toLowerCase().includes(searchTerm.toLowerCase()) ||
        event.aggregateId.toLowerCase().includes(searchTerm.toLowerCase()) ||
        JSON.stringify(event.data).toLowerCase().includes(searchTerm.toLowerCase())
      );
    }

    // Apply filters
    if (filters.aggregateType) {
      filtered = filtered.filter(event => 
        event.aggregateType === filters.aggregateType
      );
    }

    if (filters.eventType) {
      filtered = filtered.filter(event => 
        event.eventType === filters.eventType
      );
    }

    if (filters.aggregateId) {
      filtered = filtered.filter(event => 
        event.aggregateId === filters.aggregateId
      );
    }

    if (filters.correlationId) {
      filtered = filtered.filter(event => 
        event.correlationId === filters.correlationId
      );
    }

    if (filters.startTime || filters.endTime) {
      filtered = filtered.filter(event => {
        const eventTime = new Date(event.timestamp);
        if (filters.startTime && eventTime < filters.startTime) return false;
        if (filters.endTime && eventTime > filters.endTime) return false;
        return true;
      });
    }

    setFilteredEvents(filtered);
  }, [events, searchTerm, filters]);

  useEffect(() => {
    applyFilters();
  }, [applyFilters]);

  // Simulate real-time event updates
  useEffect(() => {
    if (!isRealTimeEnabled) return;

    const interval = setInterval(() => {
      // Simulate new events coming in
      const newEvent: Event = {
        id: `event-${Date.now()}`,
        aggregateId: `aggregate-${Math.floor(Math.random() * 1000)}`,
        aggregateType: ['User', 'Order', 'Workspace', 'Payment'][Math.floor(Math.random() * 4)],
        eventType: ['Created', 'Updated', 'Deleted', 'Processed'][Math.floor(Math.random() * 4)],
        version: 1,
        timestamp: new Date(),
        data: {
          mockData: true,
          value: Math.floor(Math.random() * 1000)
        },
        correlationId: `corr-${Date.now()}`
      };

      setEvents(prev => [newEvent, ...prev].slice(0, 100)); // Keep only latest 100 events
    }, 5000);

    return () => clearInterval(interval);
  }, [isRealTimeEnabled]);

  const handleRefresh = async () => {
    setIsLoading(true);
    // Simulate API call
    await new Promise(resolve => setTimeout(resolve, 1000));
    setIsLoading(false);
  };

  const handleReplayEvents = () => {
    // Implementation for event replay
    console.log('Replaying events...');
  };

  return (
    <MainLayout>
      <div className="space-y-6">
        {/* Header */}
        <div className="border-b border-gray-200 pb-5">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold leading-7 text-gray-900">Event Explorer</h1>
              <p className="mt-1 text-sm text-gray-500">
                Browse, filter, and analyze events in real-time
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <button
                onClick={() => setIsRealTimeEnabled(!isRealTimeEnabled)}
                className={`flex items-center space-x-2 px-3 py-2 rounded-md text-sm font-medium ${
                  isRealTimeEnabled
                    ? 'bg-green-100 text-green-800 hover:bg-green-200'
                    : 'bg-gray-100 text-gray-800 hover:bg-gray-200'
                }`}
              >
                {isRealTimeEnabled ? (
                  <>
                    <PauseIcon className="h-4 w-4" />
                    <span>Pause</span>
                  </>
                ) : (
                  <>
                    <PlayIcon className="h-4 w-4" />
                    <span>Resume</span>
                  </>
                )}
              </button>
              <button
                onClick={handleRefresh}
                disabled={isLoading}
                className="btn-secondary flex items-center space-x-2"
              >
                <ArrowPathIcon className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
                <span>Refresh</span>
              </button>
              <button
                onClick={handleReplayEvents}
                className="btn-primary flex items-center space-x-2"
              >
                <PlayIcon className="h-4 w-4" />
                <span>Replay</span>
              </button>
            </div>
          </div>
        </div>

        {/* Search and Filters */}
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex-1 relative">
            <MagnifyingGlassIcon className="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-gray-400" />
            <input
              type="text"
              placeholder="Search events..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="input-field pl-10 w-full"
            />
          </div>
          <button
            onClick={() => setShowFilters(!showFilters)}
            className={`btn-secondary flex items-center space-x-2 ${
              showFilters ? 'bg-primary-100 text-primary-800' : ''
            }`}
          >
            <FunnelIcon className="h-4 w-4" />
            <span>Filters</span>
            {Object.keys(filters).length > 0 && (
              <span className="bg-primary-500 text-white text-xs rounded-full px-2 py-1">
                {Object.keys(filters).length}
              </span>
            )}
          </button>
        </div>

        {/* Filters Panel */}
        {showFilters && (
          <EventFilters
            filters={filters}
            onFiltersChange={setFilters}
            events={events}
          />
        )}

        {/* Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
          <div className="bg-white rounded-lg border border-gray-200 p-4">
            <div className="text-2xl font-bold text-gray-900">{filteredEvents.length}</div>
            <div className="text-sm text-gray-500">Total Events</div>
          </div>
          <div className="bg-white rounded-lg border border-gray-200 p-4">
            <div className="text-2xl font-bold text-gray-900">
              {new Set(filteredEvents.map(e => e.aggregateType)).size}
            </div>
            <div className="text-sm text-gray-500">Aggregate Types</div>
          </div>
          <div className="bg-white rounded-lg border border-gray-200 p-4">
            <div className="text-2xl font-bold text-gray-900">
              {new Set(filteredEvents.map(e => e.eventType)).size}
            </div>
            <div className="text-sm text-gray-500">Event Types</div>
          </div>
          <div className="bg-white rounded-lg border border-gray-200 p-4">
            <div className="text-2xl font-bold text-gray-900">
              {isRealTimeEnabled ? 'Live' : 'Paused'}
            </div>
            <div className="text-sm text-gray-500">Status</div>
          </div>
        </div>

        {/* Main Content */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Event List */}
          <div className="lg:col-span-2">
            <EventList
              events={filteredEvents}
              selectedEvent={selectedEvent}
              onEventSelect={setSelectedEvent}
              isRealTime={isRealTimeEnabled}
            />
          </div>

          {/* Event Details */}
          <div className="lg:col-span-1">
            <EventDetails
              event={selectedEvent}
              onClose={() => setSelectedEvent(null)}
            />
          </div>
        </div>
      </div>
    </MainLayout>
  );
}