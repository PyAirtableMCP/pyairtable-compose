'use client';

import { useState } from 'react';
import { Event, EventFilter } from '@/types';
import { XMarkIcon } from '@heroicons/react/24/outline';

interface EventFiltersProps {
  filters: EventFilter;
  onFiltersChange: (filters: EventFilter) => void;
  events: Event[];
}

export default function EventFilters({ filters, onFiltersChange, events }: EventFiltersProps) {
  const [localFilters, setLocalFilters] = useState<EventFilter>(filters);

  // Get unique values for dropdowns
  const aggregateTypes = Array.from(new Set(events.map(e => e.aggregateType))).filter(Boolean);
  const eventTypes = Array.from(new Set(events.map(e => e.eventType))).filter(Boolean);

  const handleFilterChange = (key: keyof EventFilter, value: any) => {
    const newFilters = { ...localFilters, [key]: value };
    setLocalFilters(newFilters);
    onFiltersChange(newFilters);
  };

  const clearFilter = (key: keyof EventFilter) => {
    const newFilters = { ...localFilters };
    delete newFilters[key];
    setLocalFilters(newFilters);
    onFiltersChange(newFilters);
  };

  const clearAllFilters = () => {
    setLocalFilters({});
    onFiltersChange({});
  };

  return (
    <div className="card">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-medium text-gray-900">Filters</h3>
        {Object.keys(localFilters).length > 0 && (
          <button
            onClick={clearAllFilters}
            className="text-sm text-gray-500 hover:text-gray-700"
          >
            Clear all
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Aggregate Type */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Aggregate Type
          </label>
          <div className="relative">
            <select
              value={localFilters.aggregateType || ''}
              onChange={(e) => handleFilterChange('aggregateType', e.target.value || undefined)}
              className="input-field w-full"
            >
              <option value="">All Types</option>
              {aggregateTypes.map(type => (
                <option key={type} value={type}>
                  {type}
                </option>
              ))}
            </select>
            {localFilters.aggregateType && (
              <button
                onClick={() => clearFilter('aggregateType')}
                className="absolute right-8 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
              >
                <XMarkIcon className="h-4 w-4" />
              </button>
            )}
          </div>
        </div>

        {/* Event Type */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Event Type
          </label>
          <div className="relative">
            <select
              value={localFilters.eventType || ''}
              onChange={(e) => handleFilterChange('eventType', e.target.value || undefined)}
              className="input-field w-full"
            >
              <option value="">All Events</option>
              {eventTypes.map(type => (
                <option key={type} value={type}>
                  {type}
                </option>
              ))}
            </select>
            {localFilters.eventType && (
              <button
                onClick={() => clearFilter('eventType')}
                className="absolute right-8 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
              >
                <XMarkIcon className="h-4 w-4" />
              </button>
            )}
          </div>
        </div>

        {/* Aggregate ID */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Aggregate ID
          </label>
          <div className="relative">
            <input
              type="text"
              placeholder="Enter aggregate ID"
              value={localFilters.aggregateId || ''}
              onChange={(e) => handleFilterChange('aggregateId', e.target.value || undefined)}
              className="input-field w-full"
            />
            {localFilters.aggregateId && (
              <button
                onClick={() => clearFilter('aggregateId')}
                className="absolute right-2 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
              >
                <XMarkIcon className="h-4 w-4" />
              </button>
            )}
          </div>
        </div>

        {/* Correlation ID */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Correlation ID
          </label>
          <div className="relative">
            <input
              type="text"
              placeholder="Enter correlation ID"
              value={localFilters.correlationId || ''}
              onChange={(e) => handleFilterChange('correlationId', e.target.value || undefined)}
              className="input-field w-full"
            />
            {localFilters.correlationId && (
              <button
                onClick={() => clearFilter('correlationId')}
                className="absolute right-2 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
              >
                <XMarkIcon className="h-4 w-4" />
              </button>
            )}
          </div>
        </div>

        {/* Start Time */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Start Time
          </label>
          <div className="relative">
            <input
              type="datetime-local"
              value={localFilters.startTime ? localFilters.startTime.toISOString().slice(0, 16) : ''}
              onChange={(e) => handleFilterChange('startTime', e.target.value ? new Date(e.target.value) : undefined)}
              className="input-field w-full"
            />
            {localFilters.startTime && (
              <button
                onClick={() => clearFilter('startTime')}
                className="absolute right-2 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
              >
                <XMarkIcon className="h-4 w-4" />
              </button>
            )}
          </div>
        </div>

        {/* End Time */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            End Time
          </label>
          <div className="relative">
            <input
              type="datetime-local"
              value={localFilters.endTime ? localFilters.endTime.toISOString().slice(0, 16) : ''}
              onChange={(e) => handleFilterChange('endTime', e.target.value ? new Date(e.target.value) : undefined)}
              className="input-field w-full"
            />
            {localFilters.endTime && (
              <button
                onClick={() => clearFilter('endTime')}
                className="absolute right-2 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
              >
                <XMarkIcon className="h-4 w-4" />
              </button>
            )}
          </div>
        </div>

        {/* Limit */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Limit
          </label>
          <select
            value={localFilters.limit || 100}
            onChange={(e) => handleFilterChange('limit', parseInt(e.target.value))}
            className="input-field w-full"
          >
            <option value={50}>50</option>
            <option value={100}>100</option>
            <option value={250}>250</option>
            <option value={500}>500</option>
            <option value={1000}>1000</option>
          </select>
        </div>

        {/* Quick Time Filters */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Quick Time Filter
          </label>
          <select
            onChange={(e) => {
              const now = new Date();
              let startTime: Date | undefined;
              
              switch (e.target.value) {
                case '1h':
                  startTime = new Date(now.getTime() - 60 * 60 * 1000);
                  break;
                case '6h':
                  startTime = new Date(now.getTime() - 6 * 60 * 60 * 1000);
                  break;
                case '24h':
                  startTime = new Date(now.getTime() - 24 * 60 * 60 * 1000);
                  break;
                case '7d':
                  startTime = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
                  break;
                default:
                  startTime = undefined;
              }
              
              handleFilterChange('startTime', startTime);
              if (startTime) {
                handleFilterChange('endTime', now);
              } else {
                clearFilter('endTime');
              }
            }}
            className="input-field w-full"
          >
            <option value="">Custom Range</option>
            <option value="1h">Last Hour</option>
            <option value="6h">Last 6 Hours</option>
            <option value="24h">Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
          </select>
        </div>
      </div>

      {/* Active Filters Display */}
      {Object.keys(localFilters).length > 0 && (
        <div className="mt-4 flex flex-wrap gap-2">
          {Object.entries(localFilters).map(([key, value]) => {
            if (!value) return null;
            
            const displayValue = value instanceof Date 
              ? value.toLocaleString() 
              : typeof value === 'string' 
              ? value 
              : String(value);
            
            return (
              <span
                key={key}
                className="inline-flex items-center gap-1 px-2 py-1 bg-primary-100 text-primary-800 text-xs rounded-full"
              >
                <span className="font-medium">{key}:</span>
                <span>{displayValue}</span>
                <button
                  onClick={() => clearFilter(key as keyof EventFilter)}
                  className="hover:text-primary-600"
                >
                  <XMarkIcon className="h-3 w-3" />
                </button>
              </span>
            );
          })}
        </div>
      )}
    </div>
  );
}