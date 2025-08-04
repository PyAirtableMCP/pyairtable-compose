'use client';

import { useState } from 'react';
import { Event } from '@/types';
import { formatDistanceToNow } from 'date-fns';
import ReactJsonView from 'react-json-view';
import {
  XMarkIcon,
  ClipboardDocumentIcon,
  ArrowPathIcon,
  LinkIcon,
  InformationCircleIcon
} from '@heroicons/react/24/outline';
import { toast } from 'react-hot-toast';

interface EventDetailsProps {
  event: Event | null;
  onClose: () => void;
}

export default function EventDetails({ event, onClose }: EventDetailsProps) {
  const [activeTab, setActiveTab] = useState<'data' | 'metadata' | 'raw'>('data');

  if (!event) {
    return (
      <div className="card">
        <div className="text-center py-12">
          <InformationCircleIcon className="mx-auto h-12 w-12 text-gray-400" />
          <h3 className="mt-2 text-sm font-medium text-gray-900">No event selected</h3>
          <p className="mt-1 text-sm text-gray-500">
            Select an event from the list to view its details.
          </p>
        </div>
      </div>
    );
  }

  const copyToClipboard = (text: string, type: string) => {
    navigator.clipboard.writeText(text).then(() => {
      toast.success(`${type} copied to clipboard`);
    }).catch(() => {
      toast.error('Failed to copy to clipboard');
    });
  };

  const tabs = [
    { id: 'data', label: 'Event Data' },
    { id: 'metadata', label: 'Metadata' },
    { id: 'raw', label: 'Raw JSON' }
  ];

  return (
    <div className="card p-0">
      {/* Header */}
      <div className="px-6 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-medium text-gray-900">Event Details</h3>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600"
          >
            <XMarkIcon className="h-6 w-6" />
          </button>
        </div>
      </div>

      {/* Event Summary */}
      <div className="px-6 py-4 bg-gray-50 border-b border-gray-200">
        <div className="space-y-3">
          {/* Event Type and Aggregate */}
          <div className="flex items-center space-x-3">
            <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800">
              {event.eventType}
            </span>
            <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-gray-100 text-gray-800">
              {event.aggregateType}
            </span>
            <span className="text-sm text-gray-500">Version {event.version}</span>
          </div>

          {/* IDs */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-700">Event ID:</span>
              <div className="flex items-center space-x-2">
                <span className="font-mono text-sm text-gray-900">{event.id}</span>
                <button
                  onClick={() => copyToClipboard(event.id, 'Event ID')}
                  className="text-gray-400 hover:text-gray-600"
                >
                  <ClipboardDocumentIcon className="h-4 w-4" />
                </button>
              </div>
            </div>

            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-700">Aggregate ID:</span>
              <div className="flex items-center space-x-2">
                <span className="font-mono text-sm text-gray-900">{event.aggregateId}</span>
                <button
                  onClick={() => copyToClipboard(event.aggregateId, 'Aggregate ID')}
                  className="text-gray-400 hover:text-gray-600"
                >
                  <ClipboardDocumentIcon className="h-4 w-4" />
                </button>
              </div>
            </div>

            {event.correlationId && (
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-gray-700">Correlation ID:</span>
                <div className="flex items-center space-x-2">
                  <span className="font-mono text-sm text-gray-900">{event.correlationId}</span>
                  <button
                    onClick={() => copyToClipboard(event.correlationId!, 'Correlation ID')}
                    className="text-gray-400 hover:text-gray-600"
                  >
                    <ClipboardDocumentIcon className="h-4 w-4" />
                  </button>
                </div>
              </div>
            )}

            {event.causationId && (
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-gray-700">Causation ID:</span>
                <div className="flex items-center space-x-2">
                  <span className="font-mono text-sm text-gray-900">{event.causationId}</span>
                  <button
                    onClick={() => copyToClipboard(event.causationId!, 'Causation ID')}
                    className="text-gray-400 hover:text-gray-600"
                  >
                    <ClipboardDocumentIcon className="h-4 w-4" />
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Timestamp */}
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-gray-700">Timestamp:</span>
            <div className="text-right">
              <div className="text-sm text-gray-900">
                {formatDistanceToNow(new Date(event.timestamp), { addSuffix: true })}
              </div>
              <div className="text-xs text-gray-500">
                {new Date(event.timestamp).toLocaleString()}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as 'data' | 'metadata' | 'raw')}
              className={`py-2 px-4 text-sm font-medium border-b-2 ${
                activeTab === tab.id
                  ? 'border-primary-500 text-primary-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Tab Content */}
      <div className="px-6 py-4 max-h-96 overflow-y-auto scrollbar-thin">
        {activeTab === 'data' && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium text-gray-900">Event Data</h4>
              <button
                onClick={() => copyToClipboard(JSON.stringify(event.data, null, 2), 'Event data')}
                className="text-sm text-primary-600 hover:text-primary-900 flex items-center space-x-1"
              >
                <ClipboardDocumentIcon className="h-4 w-4" />
                <span>Copy</span>
              </button>
            </div>
            {Object.keys(event.data).length > 0 ? (
              <ReactJsonView
                src={event.data}
                theme="bright:inverted"
                name={false}
                collapsed={false}
                displayDataTypes={false}
                displayObjectSize={false}
                enableClipboard={false}
                style={{ backgroundColor: 'transparent', fontSize: '12px' }}
              />
            ) : (
              <div className="text-sm text-gray-500 italic">No data available</div>
            )}
          </div>
        )}

        {activeTab === 'metadata' && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium text-gray-900">Metadata</h4>
              {event.metadata && (
                <button
                  onClick={() => copyToClipboard(JSON.stringify(event.metadata, null, 2), 'Metadata')}
                  className="text-sm text-primary-600 hover:text-primary-900 flex items-center space-x-1"
                >
                  <ClipboardDocumentIcon className="h-4 w-4" />
                  <span>Copy</span>
                </button>
              )}
            </div>
            {event.metadata && Object.keys(event.metadata).length > 0 ? (
              <ReactJsonView
                src={event.metadata}
                theme="bright:inverted"
                name={false}
                collapsed={false}
                displayDataTypes={false}
                displayObjectSize={false}
                enableClipboard={false}
                style={{ backgroundColor: 'transparent', fontSize: '12px' }}
              />
            ) : (
              <div className="text-sm text-gray-500 italic">No metadata available</div>
            )}
          </div>
        )}

        {activeTab === 'raw' && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-medium text-gray-900">Raw JSON</h4>
              <button
                onClick={() => copyToClipboard(JSON.stringify(event, null, 2), 'Raw event')}
                className="text-sm text-primary-600 hover:text-primary-900 flex items-center space-x-1"
              >
                <ClipboardDocumentIcon className="h-4 w-4" />
                <span>Copy</span>
              </button>
            </div>
            <ReactJsonView
              src={event}
              theme="bright:inverted"
              name={false}
              collapsed={1}
              displayDataTypes={true}
              displayObjectSize={true}
              enableClipboard={false}
              style={{ backgroundColor: 'transparent', fontSize: '12px' }}
            />
          </div>
        )}
      </div>

      {/* Actions */}
      <div className="px-6 py-4 border-t border-gray-200 bg-gray-50">
        <div className="flex justify-between">
          <div className="flex space-x-3">
            <button className="btn-secondary flex items-center space-x-2">
              <ArrowPathIcon className="h-4 w-4" />
              <span>Replay</span>
            </button>
            <button className="btn-secondary flex items-center space-x-2">
              <LinkIcon className="h-4 w-4" />
              <span>View Related</span>
            </button>
          </div>
          <button
            onClick={() => copyToClipboard(window.location.href + `?eventId=${event.id}`, 'Event URL')}
            className="text-sm text-gray-500 hover:text-gray-700"
          >
            Share Event
          </button>
        </div>
      </div>
    </div>
  );
}