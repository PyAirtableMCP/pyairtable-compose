'use client';

import { useEffect, useRef } from 'react';
import { Event } from '@/types';
import { formatDistanceToNow } from 'date-fns';
import { 
  ArrowTopRightOnSquareIcon,
  ClockIcon,
  TagIcon,
  IdentificationIcon
} from '@heroicons/react/24/outline';

interface EventListProps {
  events: Event[];
  selectedEvent: Event | null;
  onEventSelect: (event: Event) => void;
  isRealTime: boolean;
}

export default function EventList({ events, selectedEvent, onEventSelect, isRealTime }: EventListProps) {
  const listRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to top when new events arrive in real-time mode
  useEffect(() => {
    if (isRealTime && listRef.current) {
      listRef.current.scrollTop = 0;
    }
  }, [events, isRealTime]);

  const getEventTypeColor = (eventType: string) => {
    const hash = eventType.split('').reduce((a, b) => {
      a = ((a << 5) - a) + b.charCodeAt(0);
      return a & a;
    }, 0);
    
    const colors = [
      'bg-blue-100 text-blue-800',
      'bg-green-100 text-green-800',
      'bg-yellow-100 text-yellow-800',
      'bg-purple-100 text-purple-800',
      'bg-pink-100 text-pink-800',
      'bg-indigo-100 text-indigo-800',
    ];
    
    return colors[Math.abs(hash) % colors.length];
  };

  const getAggregateTypeColor = (aggregateType: string) => {
    const hash = aggregateType.split('').reduce((a, b) => {
      a = ((a << 5) - a) + b.charCodeAt(0);
      return a & a;
    }, 0);
    
    const colors = [
      'bg-gray-100 text-gray-800',
      'bg-red-100 text-red-800',
      'bg-orange-100 text-orange-800',
      'bg-teal-100 text-teal-800',
      'bg-cyan-100 text-cyan-800',
    ];
    
    return colors[Math.abs(hash) % colors.length];
  };

  if (events.length === 0) {
    return (
      <div className="card">
        <div className="text-center py-12">
          <div className="mx-auto h-12 w-12 text-gray-400">
            <svg fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
          </div>
          <h3 className="mt-2 text-sm font-medium text-gray-900">No events found</h3>
          <p className="mt-1 text-sm text-gray-500">
            No events match your current filters. Try adjusting your search criteria.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="card p-0">
      <div className="px-6 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-medium text-gray-900">
            Events ({events.length})
          </h3>
          {isRealTime && (
            <div className="flex items-center space-x-1 text-sm text-green-600">
              <div className="h-2 w-2 bg-green-400 rounded-full animate-pulse"></div>
              <span>Live</span>
            </div>
          )}
        </div>
      </div>

      <div 
        ref={listRef}
        className="max-h-[600px] overflow-y-auto scrollbar-thin"
      >
        <div className="divide-y divide-gray-200">
          {events.map((event, index) => (
            <div
              key={event.id}
              onClick={() => onEventSelect(event)}
              className={`px-6 py-4 hover:bg-gray-50 cursor-pointer transition-colors duration-150 ${
                selectedEvent?.id === event.id ? 'bg-primary-50 border-l-4 border-primary-500' : ''
              } ${index === 0 && isRealTime ? 'animate-fade-in' : ''}`}
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  {/* Event Type and Aggregate Type */}
                  <div className="flex items-center space-x-2 mb-2">
                    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getEventTypeColor(event.eventType)}`}>
                      {event.eventType}
                    </span>
                    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getAggregateTypeColor(event.aggregateType)}`}>
                      {event.aggregateType}
                    </span>
                    <span className="text-xs text-gray-500">v{event.version}</span>
                  </div>

                  {/* Aggregate ID and Correlation ID */}
                  <div className="flex items-center space-x-4 mb-2">
                    <div className="flex items-center space-x-1 text-sm text-gray-600">
                      <IdentificationIcon className="h-4 w-4" />
                      <span className="font-mono text-xs">{event.aggregateId}</span>
                    </div>
                    {event.correlationId && (
                      <div className="flex items-center space-x-1 text-sm text-gray-500">
                        <TagIcon className="h-4 w-4" />
                        <span className="font-mono text-xs">{event.correlationId}</span>
                      </div>
                    )}
                  </div>

                  {/* Event Data Preview */}
                  <div className="text-sm text-gray-600 mb-2">
                    <div className="font-mono text-xs bg-gray-100 rounded px-2 py-1 truncate">
                      {JSON.stringify(event.data).substring(0, 100)}
                      {JSON.stringify(event.data).length > 100 && '...'}
                    </div>
                  </div>

                  {/* Timestamp */}
                  <div className="flex items-center space-x-1 text-xs text-gray-500">
                    <ClockIcon className="h-4 w-4" />
                    <span>{formatDistanceToNow(new Date(event.timestamp), { addSuffix: true })}</span>
                    <span>•</span>
                    <span>{new Date(event.timestamp).toLocaleString()}</span>
                  </div>
                </div>

                <div className="flex-shrink-0 ml-4">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onEventSelect(event);
                    }}
                    className="text-gray-400 hover:text-gray-600"
                  >
                    <ArrowTopRightOnSquareIcon className="h-5 w-5" />
                  </button>
                </div>
              </div>

              {/* Metadata indicators */}
              {(event.metadata || event.causationId) && (
                <div className="mt-2 flex items-center space-x-2">
                  {event.metadata && Object.keys(event.metadata).length > 0 && (
                    <span className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800">
                      {Object.keys(event.metadata).length} metadata fields
                    </span>
                  )}
                  {event.causationId && (
                    <span className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800">
                      causation
                    </span>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Load More Button */}
      {events.length > 0 && (
        <div className="px-6 py-4 border-t border-gray-200 text-center">
          <button className="text-sm text-primary-600 hover:text-primary-900">
            Load more events
          </button>
        </div>
      )}
    </div>
  );
}