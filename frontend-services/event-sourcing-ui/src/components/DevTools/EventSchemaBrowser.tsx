'use client';

import { useState } from 'react';
import { EventSchema } from '@/types';
import ReactJsonView from 'react-json-view';
import {
  MagnifyingGlassIcon,
  DocumentTextIcon,
  ClipboardDocumentIcon,
  CodeBracketIcon,
  EyeIcon,
  InformationCircleIcon
} from '@heroicons/react/24/outline';
import { toast } from 'react-hot-toast';

interface EventSchemaBrowserProps {
  schemas: EventSchema[];
}

export default function EventSchemaBrowser({ schemas }: EventSchemaBrowserProps) {
  const [selectedSchema, setSelectedSchema] = useState<EventSchema | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [viewMode, setViewMode] = useState<'schema' | 'example'>('schema');

  const filteredSchemas = schemas.filter(schema =>
    schema.eventType.toLowerCase().includes(searchTerm.toLowerCase()) ||
    schema.description?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const copyToClipboard = (text: string, type: string) => {
    navigator.clipboard.writeText(text).then(() => {
      toast.success(`${type} copied to clipboard`);
    }).catch(() => {
      toast.error('Failed to copy to clipboard');
    });
  };

  const generateTypescriptInterface = (schema: EventSchema) => {
    const generateTypeFromProperty = (prop: any, propName: string): string => {
      switch (prop.type) {
        case 'string':
          return prop.enum ? prop.enum.map((e: string) => `'${e}'`).join(' | ') : 'string';
        case 'number':
          return 'number';
        case 'boolean':
          return 'boolean';
        case 'object':
          if (prop.properties) {
            const objectProps = Object.entries(prop.properties)
              .map(([key, value]: [string, any]) => `  ${key}: ${generateTypeFromProperty(value, key)};`)
              .join('\n');
            return `{\n${objectProps}\n}`;
          }
          return 'Record<string, any>';
        case 'array':
          return prop.items ? `${generateTypeFromProperty(prop.items, propName)}[]` : 'any[]';
        default:
          return 'any';
      }
    };

    const interfaceName = `${schema.eventType}Data`;
    const properties = Object.entries(schema.schema.properties)
      .map(([key, prop]: [string, any]) => {
        const optional = !schema.schema.required?.includes(key) ? '?' : '';
        const type = generateTypeFromProperty(prop, key);
        const comment = prop.description ? `  /** ${prop.description} */\n` : '';
        return `${comment}  ${key}${optional}: ${type};`;
      })
      .join('\n');

    return `interface ${interfaceName} {\n${properties}\n}`;
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      {/* Schema List */}
      <div className="lg:col-span-1">
        <div className="card p-0">
          <div className="px-6 py-4 border-b border-gray-200">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-medium text-gray-900">Event Schemas</h3>
              <span className="text-sm text-gray-500">{schemas.length} schemas</span>
            </div>
            <div className="mt-4 relative">
              <MagnifyingGlassIcon className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
              <input
                type="text"
                placeholder="Search schemas..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="input-field pl-10 w-full"
              />
            </div>
          </div>

          <div className="max-h-[500px] overflow-y-auto scrollbar-thin">
            <div className="divide-y divide-gray-200">
              {filteredSchemas.map((schema) => (
                <div
                  key={`${schema.eventType}-${schema.version}`}
                  onClick={() => setSelectedSchema(schema)}
                  className={`px-6 py-4 hover:bg-gray-50 cursor-pointer transition-colors ${
                    selectedSchema?.eventType === schema.eventType && selectedSchema?.version === schema.version
                      ? 'bg-primary-50 border-l-4 border-primary-500'
                      : ''
                  }`}
                >
                  <div className="flex items-start justify-between">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center space-x-2 mb-1">
                        <DocumentTextIcon className="h-4 w-4 text-gray-400" />
                        <span className="text-sm font-medium text-gray-900">
                          {schema.eventType}
                        </span>
                      </div>
                      <div className="text-xs text-gray-500 mb-2">
                        Version {schema.version}
                      </div>
                      {schema.description && (
                        <div className="text-xs text-gray-600 line-clamp-2">
                          {schema.description}
                        </div>
                      )}
                    </div>
                  </div>
                  <div className="mt-2 flex items-center space-x-3 text-xs text-gray-500">
                    <span>{Object.keys(schema.schema.properties).length} fields</span>
                    <span>•</span>
                    <span>{schema.examples.length} example{schema.examples.length !== 1 ? 's' : ''}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Schema Details */}
      <div className="lg:col-span-2">
        {selectedSchema ? (
          <div className="space-y-6">
            {/* Header */}
            <div className="card">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h3 className="text-xl font-semibold text-gray-900">
                    {selectedSchema.eventType}
                  </h3>
                  <p className="text-sm text-gray-500">
                    Version {selectedSchema.version}
                  </p>
                </div>
                <div className="flex space-x-2">
                  <button
                    onClick={() => setViewMode('schema')}
                    className={`px-3 py-2 rounded-md text-sm font-medium ${
                      viewMode === 'schema'
                        ? 'bg-primary-100 text-primary-700'
                        : 'text-gray-600 hover:text-gray-900'
                    }`}
                  >
                    <CodeBracketIcon className="h-4 w-4 inline mr-1" />
                    Schema
                  </button>
                  <button
                    onClick={() => setViewMode('example')}
                    className={`px-3 py-2 rounded-md text-sm font-medium ${
                      viewMode === 'example'
                        ? 'bg-primary-100 text-primary-700'
                        : 'text-gray-600 hover:text-gray-900'
                    }`}
                  >
                    <EyeIcon className="h-4 w-4 inline mr-1" />
                    Examples
                  </button>
                </div>
              </div>

              {selectedSchema.description && (
                <div className="mb-4 p-3 bg-blue-50 border border-blue-200 rounded">
                  <div className="flex items-start space-x-2">
                    <InformationCircleIcon className="h-5 w-5 text-blue-500 mt-0.5 flex-shrink-0" />
                    <div className="text-sm text-blue-800">
                      {selectedSchema.description}
                    </div>
                  </div>
                </div>
              )}

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                <div>
                  <div className="text-gray-500">Required Fields</div>
                  <div className="font-medium text-gray-900">
                    {selectedSchema.schema.required?.length || 0}
                  </div>
                </div>
                <div>
                  <div className="text-gray-500">Optional Fields</div>
                  <div className="font-medium text-gray-900">
                    {Object.keys(selectedSchema.schema.properties).length - (selectedSchema.schema.required?.length || 0)}
                  </div>
                </div>
                <div>
                  <div className="text-gray-500">Examples</div>
                  <div className="font-medium text-gray-900">
                    {selectedSchema.examples.length}
                  </div>
                </div>
              </div>
            </div>

            {/* Schema View */}
            {viewMode === 'schema' && (
              <div className="card">
                <div className="flex items-center justify-between mb-4">
                  <h4 className="text-lg font-medium text-gray-900">JSON Schema</h4>
                  <div className="flex space-x-2">
                    <button
                      onClick={() => copyToClipboard(JSON.stringify(selectedSchema.schema, null, 2), 'JSON Schema')}
                      className="btn-secondary text-xs flex items-center space-x-1"
                    >
                      <ClipboardDocumentIcon className="h-3 w-3" />
                      <span>Copy JSON</span>
                    </button>
                    <button
                      onClick={() => copyToClipboard(generateTypescriptInterface(selectedSchema), 'TypeScript Interface')}
                      className="btn-secondary text-xs flex items-center space-x-1"
                    >
                      <ClipboardDocumentIcon className="h-3 w-3" />
                      <span>Copy TS</span>
                    </button>
                  </div>
                </div>

                <div className="space-y-4">
                  {/* Properties Table */}
                  <div className="overflow-x-auto">
                    <table className="min-w-full divide-y divide-gray-200">
                      <thead className="bg-gray-50">
                        <tr>
                          <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                            Field
                          </th>
                          <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                            Type
                          </th>
                          <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                            Required
                          </th>
                          <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                            Description
                          </th>
                        </tr>
                      </thead>
                      <tbody className="bg-white divide-y divide-gray-200">
                        {Object.entries(selectedSchema.schema.properties).map(([field, prop]: [string, any]) => (
                          <tr key={field}>
                            <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                              {field}
                            </td>
                            <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                              <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                                {prop.type}
                                {prop.enum && ' (enum)'}
                              </span>
                            </td>
                            <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                              {selectedSchema.schema.required?.includes(field) ? (
                                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                                  Required
                                </span>
                              ) : (
                                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                                  Optional
                                </span>
                              )}
                            </td>
                            <td className="px-6 py-4 text-sm text-gray-500">
                              {prop.description || '-'}
                              {prop.enum && (
                                <div className="mt-1 text-xs text-gray-400">
                                  Values: {prop.enum.join(', ')}
                                </div>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>

                  {/* Raw Schema JSON */}
                  <div>
                    <h5 className="text-sm font-medium text-gray-900 mb-2">Raw Schema</h5>
                    <div className="bg-gray-50 rounded-lg p-4 max-h-64 overflow-y-auto">
                      <ReactJsonView
                        src={selectedSchema.schema}
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
                </div>
              </div>
            )}

            {/* Examples View */}
            {viewMode === 'example' && (
              <div className="card">
                <div className="flex items-center justify-between mb-4">
                  <h4 className="text-lg font-medium text-gray-900">Examples</h4>
                  <span className="text-sm text-gray-500">
                    {selectedSchema.examples.length} example{selectedSchema.examples.length !== 1 ? 's' : ''}
                  </span>
                </div>

                <div className="space-y-4">
                  {selectedSchema.examples.map((example, index) => (
                    <div key={index} className="border border-gray-200 rounded-lg p-4">
                      <div className="flex items-center justify-between mb-3">
                        <h5 className="text-sm font-medium text-gray-900">
                          Example {index + 1}
                        </h5>
                        <button
                          onClick={() => copyToClipboard(JSON.stringify(example, null, 2), 'Example')}
                          className="text-xs text-primary-600 hover:text-primary-900 flex items-center space-x-1"
                        >
                          <ClipboardDocumentIcon className="h-3 w-3" />
                          <span>Copy</span>
                        </button>
                      </div>
                      <div className="bg-gray-50 rounded p-3 max-h-64 overflow-y-auto">
                        <ReactJsonView
                          src={example}
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
                  ))}
                </div>
              </div>
            )}
          </div>
        ) : (
          <div className="card">
            <div className="text-center py-12">
              <DocumentTextIcon className="mx-auto h-12 w-12 text-gray-400" />
              <h3 className="mt-2 text-sm font-medium text-gray-900">No schema selected</h3>
              <p className="mt-1 text-sm text-gray-500">
                Select a schema from the list to view its details and examples.
              </p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}