'use client';

import { useState } from 'react';
import MainLayout from '@/components/Layout/MainLayout';
import {
  Cog6ToothIcon,
  BellIcon,
  ShieldCheckIcon,
  ServerIcon,
  ClockIcon,
  EyeIcon
} from '@heroicons/react/24/outline';

interface Settings {
  // General Settings
  autoRefresh: boolean;
  refreshInterval: number;
  theme: 'light' | 'dark' | 'system';
  timezone: string;
  
  // Notifications
  emailNotifications: boolean;
  slackIntegration: boolean;
  webhookUrl: string;
  alertThresholds: {
    eventLag: number;
    errorRate: number;
    sagaFailureRate: number;
    projectionLag: number;
  };
  
  // Security
  sessionTimeout: number;
  requireMFA: boolean;
  auditLogging: boolean;
  
  // Performance
  maxEventsPerPage: number;
  metricsRetention: number;
  realTimeUpdates: boolean;
  
  // API Configuration
  apiEndpoint: string;
  apiTimeout: number;
  maxRetries: number;
}

export default function SettingsPage() {
  const [settings, setSettings] = useState<Settings>({
    autoRefresh: true,
    refreshInterval: 5,
    theme: 'system',
    timezone: 'UTC',
    emailNotifications: true,
    slackIntegration: false,
    webhookUrl: '',
    alertThresholds: {
      eventLag: 10,
      errorRate: 5,
      sagaFailureRate: 10,
      projectionLag: 30
    },
    sessionTimeout: 480,
    requireMFA: false,
    auditLogging: true,
    maxEventsPerPage: 100,
    metricsRetention: 30,
    realTimeUpdates: true,
    apiEndpoint: 'http://localhost:8080',
    apiTimeout: 30,
    maxRetries: 3
  });

  const [activeTab, setActiveTab] = useState<'general' | 'notifications' | 'security' | 'performance' | 'api'>('general');
  const [hasChanges, setHasChanges] = useState(false);

  const updateSetting = <K extends keyof Settings>(key: K, value: Settings[K]) => {
    setSettings(prev => ({ ...prev, [key]: value }));
    setHasChanges(true);
  };

  const updateAlertThreshold = (key: keyof Settings['alertThresholds'], value: number) => {
    setSettings(prev => ({
      ...prev,
      alertThresholds: { ...prev.alertThresholds, [key]: value }
    }));
    setHasChanges(true);
  };

  const saveSettings = () => {
    // In a real app, this would save to backend
    console.log('Saving settings:', settings);
    setHasChanges(false);
    // Show success toast
  };

  const resetSettings = () => {
    // Reset to defaults
    setHasChanges(false);
  };

  const tabs = [
    { id: 'general', label: 'General', icon: Cog6ToothIcon },
    { id: 'notifications', label: 'Notifications', icon: BellIcon },
    { id: 'security', label: 'Security', icon: ShieldCheckIcon },
    { id: 'performance', label: 'Performance', icon: ServerIcon },
    { id: 'api', label: 'API', icon: ServerIcon }
  ];

  return (
    <MainLayout>
      <div className="space-y-6">
        {/* Header */}
        <div className="border-b border-gray-200 pb-5">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold leading-7 text-gray-900">Settings</h1>
              <p className="mt-1 text-sm text-gray-500">
                Configure your event sourcing dashboard preferences and system settings
              </p>
            </div>
            <div className="flex space-x-3">
              {hasChanges && (
                <>
                  <button
                    onClick={resetSettings}
                    className="btn-secondary"
                  >
                    Reset
                  </button>
                  <button
                    onClick={saveSettings}
                    className="btn-primary"
                  >
                    Save Changes
                  </button>
                </>
              )}
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
          {/* Settings Navigation */}
          <div className="lg:col-span-1">
            <nav className="space-y-1">
              {tabs.map((tab) => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id as any)}
                  className={`w-full flex items-center space-x-3 px-3 py-2 text-sm font-medium rounded-md ${
                    activeTab === tab.id
                      ? 'bg-primary-100 text-primary-700 border border-primary-200'
                      : 'text-gray-600 hover:text-gray-900 hover:bg-gray-100'
                  }`}
                >
                  <tab.icon className="h-5 w-5" />
                  <span>{tab.label}</span>
                </button>
              ))}
            </nav>
          </div>

          {/* Settings Content */}
          <div className="lg:col-span-3">
            <div className="card">
              {activeTab === 'general' && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-gray-900">General Settings</h3>
                  
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">Theme</label>
                      <select
                        value={settings.theme}
                        onChange={(e) => updateSetting('theme', e.target.value as 'light' | 'dark' | 'system')}
                        className="input-field w-full mt-1"
                      >
                        <option value="light">Light</option>
                        <option value="dark">Dark</option>
                        <option value="system">System</option>
                      </select>
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700">Timezone</label>
                      <select
                        value={settings.timezone}
                        onChange={(e) => updateSetting('timezone', e.target.value)}
                        className="input-field w-full mt-1"
                      >
                        <option value="UTC">UTC</option>
                        <option value="America/New_York">Eastern Time</option>
                        <option value="America/Chicago">Central Time</option>
                        <option value="America/Denver">Mountain Time</option>
                        <option value="America/Los_Angeles">Pacific Time</option>
                        <option value="Europe/London">London</option>
                        <option value="Europe/Paris">Paris</option>
                        <option value="Asia/Tokyo">Tokyo</option>
                      </select>
                    </div>
                  </div>

                  <div className="space-y-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <label className="text-sm font-medium text-gray-700">Auto Refresh</label>
                        <p className="text-sm text-gray-500">Automatically refresh data at regular intervals</p>
                      </div>
                      <label className="relative inline-flex items-center cursor-pointer">
                        <input
                          type="checkbox"
                          checked={settings.autoRefresh}
                          onChange={(e) => updateSetting('autoRefresh', e.target.checked)}
                          className="sr-only peer"
                        />
                        <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-600"></div>
                      </label>
                    </div>

                    {settings.autoRefresh && (
                      <div>
                        <label className="block text-sm font-medium text-gray-700">
                          Refresh Interval (seconds)
                        </label>
                        <input
                          type="number"
                          min="1"
                          max="300"
                          value={settings.refreshInterval}
                          onChange={(e) => updateSetting('refreshInterval', parseInt(e.target.value))}
                          className="input-field w-32 mt-1"
                        />
                      </div>
                    )}

                    <div className="flex items-center justify-between">
                      <div>
                        <label className="text-sm font-medium text-gray-700">Real-time Updates</label>
                        <p className="text-sm text-gray-500">Receive live updates via WebSocket</p>
                      </div>
                      <label className="relative inline-flex items-center cursor-pointer">
                        <input
                          type="checkbox"
                          checked={settings.realTimeUpdates}
                          onChange={(e) => updateSetting('realTimeUpdates', e.target.checked)}
                          className="sr-only peer"
                        />
                        <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-600"></div>
                      </label>
                    </div>
                  </div>
                </div>
              )}

              {activeTab === 'notifications' && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-gray-900">Notification Settings</h3>
                  
                  <div className="space-y-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <label className="text-sm font-medium text-gray-700">Email Notifications</label>
                        <p className="text-sm text-gray-500">Receive alerts via email</p>
                      </div>
                      <label className="relative inline-flex items-center cursor-pointer">
                        <input
                          type="checkbox"
                          checked={settings.emailNotifications}
                          onChange={(e) => updateSetting('emailNotifications', e.target.checked)}
                          className="sr-only peer"
                        />
                        <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-600"></div>
                      </label>
                    </div>

                    <div className="flex items-center justify-between">
                      <div>
                        <label className="text-sm font-medium text-gray-700">Slack Integration</label>
                        <p className="text-sm text-gray-500">Send alerts to Slack channels</p>
                      </div>
                      <label className="relative inline-flex items-center cursor-pointer">
                        <input
                          type="checkbox"
                          checked={settings.slackIntegration}
                          onChange={(e) => updateSetting('slackIntegration', e.target.checked)}
                          className="sr-only peer"
                        />
                        <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-600"></div>
                      </label>
                    </div>

                    {settings.slackIntegration && (
                      <div>
                        <label className="block text-sm font-medium text-gray-700">Webhook URL</label>
                        <input
                          type="url"
                          value={settings.webhookUrl}
                          onChange={(e) => updateSetting('webhookUrl', e.target.value)}
                          className="input-field w-full mt-1"
                          placeholder="https://hooks.slack.com/services/..."
                        />
                      </div>
                    )}
                  </div>

                  <div>
                    <h4 className="text-md font-medium text-gray-900 mb-4">Alert Thresholds</h4>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div>
                        <label className="block text-sm font-medium text-gray-700">
                          Event Lag (seconds)
                        </label>
                        <input
                          type="number"
                          min="1"
                          value={settings.alertThresholds.eventLag}
                          onChange={(e) => updateAlertThreshold('eventLag', parseInt(e.target.value))}
                          className="input-field w-full mt-1"
                        />
                      </div>

                      <div>
                        <label className="block text-sm font-medium text-gray-700">
                          Error Rate (%)
                        </label>
                        <input
                          type="number"
                          min="0"
                          max="100"
                          value={settings.alertThresholds.errorRate}
                          onChange={(e) => updateAlertThreshold('errorRate', parseInt(e.target.value))}
                          className="input-field w-full mt-1"
                        />
                      </div>

                      <div>
                        <label className="block text-sm font-medium text-gray-700">
                          SAGA Failure Rate (%)
                        </label>
                        <input
                          type="number"
                          min="0"
                          max="100"
                          value={settings.alertThresholds.sagaFailureRate}
                          onChange={(e) => updateAlertThreshold('sagaFailureRate', parseInt(e.target.value))}
                          className="input-field w-full mt-1"
                        />
                      </div>

                      <div>
                        <label className="block text-sm font-medium text-gray-700">
                          Projection Lag (seconds)
                        </label>
                        <input
                          type="number"
                          min="1"
                          value={settings.alertThresholds.projectionLag}
                          onChange={(e) => updateAlertThreshold('projectionLag', parseInt(e.target.value))}
                          className="input-field w-full mt-1"
                        />
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {activeTab === 'security' && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-gray-900">Security Settings</h3>
                  
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">
                        Session Timeout (minutes)
                      </label>
                      <input
                        type="number"
                        min="15"
                        max="1440"
                        value={settings.sessionTimeout}
                        onChange={(e) => updateSetting('sessionTimeout', parseInt(e.target.value))}
                        className="input-field w-32 mt-1"
                      />
                      <p className="text-sm text-gray-500 mt-1">
                        Automatically log out after period of inactivity
                      </p>
                    </div>

                    <div className="flex items-center justify-between">
                      <div>
                        <label className="text-sm font-medium text-gray-700">Require Multi-Factor Authentication</label>
                        <p className="text-sm text-gray-500">Require MFA for all users</p>
                      </div>
                      <label className="relative inline-flex items-center cursor-pointer">
                        <input
                          type="checkbox"
                          checked={settings.requireMFA}
                          onChange={(e) => updateSetting('requireMFA', e.target.checked)}
                          className="sr-only peer"
                        />
                        <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-600"></div>
                      </label>
                    </div>

                    <div className="flex items-center justify-between">
                      <div>
                        <label className="text-sm font-medium text-gray-700">Audit Logging</label>
                        <p className="text-sm text-gray-500">Log all user actions and system events</p>
                      </div>
                      <label className="relative inline-flex items-center cursor-pointer">
                        <input
                          type="checkbox"
                          checked={settings.auditLogging}
                          onChange={(e) => updateSetting('auditLogging', e.target.checked)}
                          className="sr-only peer"
                        />
                        <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-primary-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-600"></div>
                      </label>
                    </div>
                  </div>
                </div>
              )}

              {activeTab === 'performance' && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-gray-900">Performance Settings</h3>
                  
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">
                        Max Events Per Page
                      </label>
                      <input
                        type="number"
                        min="10"
                        max="1000"
                        value={settings.maxEventsPerPage}
                        onChange={(e) => updateSetting('maxEventsPerPage', parseInt(e.target.value))}
                        className="input-field w-full mt-1"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700">
                        Metrics Retention (days)
                      </label>
                      <input
                        type="number"
                        min="1"
                        max="365"
                        value={settings.metricsRetention}
                        onChange={(e) => updateSetting('metricsRetention', parseInt(e.target.value))}
                        className="input-field w-full mt-1"
                      />
                    </div>
                  </div>
                </div>
              )}

              {activeTab === 'api' && (
                <div className="space-y-6">
                  <h3 className="text-lg font-medium text-gray-900">API Configuration</h3>
                  
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">API Endpoint</label>
                      <input
                        type="url"
                        value={settings.apiEndpoint}
                        onChange={(e) => updateSetting('apiEndpoint', e.target.value)}
                        className="input-field w-full mt-1"
                      />
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div>
                        <label className="block text-sm font-medium text-gray-700">
                          Timeout (seconds)
                        </label>
                        <input
                          type="number"
                          min="5"
                          max="300"
                          value={settings.apiTimeout}
                          onChange={(e) => updateSetting('apiTimeout', parseInt(e.target.value))}
                          className="input-field w-full mt-1"
                        />
                      </div>

                      <div>
                        <label className="block text-sm font-medium text-gray-700">
                          Max Retries
                        </label>
                        <input
                          type="number"
                          min="0"
                          max="10"
                          value={settings.maxRetries}
                          onChange={(e) => updateSetting('maxRetries', parseInt(e.target.value))}
                          className="input-field w-full mt-1"
                        />
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </MainLayout>
  );
}