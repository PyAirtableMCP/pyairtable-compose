import PushNotification, { Importance } from 'react-native-push-notification';
import { Platform } from 'react-native';
import { PushNotificationConfig } from '../types';
import { NOTIFICATION_CHANNELS } from '../utils/constants';
import { PyAirtableSDKError } from '../utils/errors';

export interface NotificationManagerOptions {
  enableSound?: boolean;
  enableVibration?: boolean;
  defaultChannelId?: string;
  requestPermissions?: boolean;
}

export class NotificationManager {
  private options: Required<NotificationManagerOptions>;
  private isInitialized = false;

  constructor(options: NotificationManagerOptions = {}) {
    this.options = {
      enableSound: true,
      enableVibration: true,
      defaultChannelId: NOTIFICATION_CHANNELS.DEFAULT,
      requestPermissions: true,
      ...options,
    };
  }

  /**
   * Initialize push notifications
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;

    return new Promise((resolve, reject) => {
      PushNotification.configure({
        // Called when Token is generated (iOS and Android)
        onRegister: (token) => {
          console.log('Push notification token:', token);
        },

        // Called when a remote is received or opened/clicked
        onNotification: (notification) => {
          console.log('Notification received:', notification);
          
          // Required on iOS only
          notification.finish(PushNotification.FetchResult.NoData);
        },

        // Called when the user fails to register for push notifications
        onRegistrationError: (error) => {
          console.error('Push notification registration error:', error);
          reject(new PyAirtableSDKError('Failed to register for push notifications'));
        },

        // IOS ONLY (optional): default: all - Permissions to register.
        permissions: {
          alert: true,
          badge: true,
          sound: true,
        },

        // Should the initial notification be popped automatically
        popInitialNotification: true,

        // (optional) default: true
        requestPermissions: this.options.requestPermissions,
      });

      this.createNotificationChannels();
      this.isInitialized = true;
      resolve();
    });
  }

  /**
   * Create notification channels (Android)
   */
  private createNotificationChannels(): void {
    if (Platform.OS === 'android') {
      // Default channel
      PushNotification.createChannel(
        {
          channelId: NOTIFICATION_CHANNELS.DEFAULT,
          channelName: 'PyAirtable Default',
          channelDescription: 'Default notifications from PyAirtable',
          importance: Importance.DEFAULT,
          vibrate: this.options.enableVibration,
          playSound: this.options.enableSound,
        },
        (created) => console.log(`Default channel created: ${created}`)
      );

      // Sync channel
      PushNotification.createChannel(
        {
          channelId: NOTIFICATION_CHANNELS.SYNC,
          channelName: 'PyAirtable Sync',
          channelDescription: 'Data synchronization notifications',
          importance: Importance.LOW,
          vibrate: false,
          playSound: false,
        },
        (created) => console.log(`Sync channel created: ${created}`)
      );

      // Updates channel
      PushNotification.createChannel(
        {
          channelId: NOTIFICATION_CHANNELS.UPDATES,
          channelName: 'PyAirtable Updates',
          channelDescription: 'Real-time data update notifications',
          importance: Importance.HIGH,
          vibrate: this.options.enableVibration,
          playSound: this.options.enableSound,
        },
        (created) => console.log(`Updates channel created: ${created}`)
      );
    }
  }

  /**
   * Show local notification
   */
  showNotification(config: PushNotificationConfig): void {
    if (!this.isInitialized) {
      throw new PyAirtableSDKError('NotificationManager not initialized');
    }

    PushNotification.localNotification({
      title: config.title,
      message: config.body,
      channelId: config.channelId || this.options.defaultChannelId,
      playSound: this.options.enableSound && (config.sound !== undefined ? !!config.sound : true),
      soundName: config.sound || 'default',
      importance: this.getImportance(config.priority),
      priority: config.priority || 'normal',
      vibrate: this.options.enableVibration,
      userInfo: config.data || {},
      number: config.badge,
      color: config.color,
      largeIcon: config.icon,
      smallIcon: config.icon,
    });
  }

  /**
   * Schedule a notification
   */
  scheduleNotification(config: PushNotificationConfig, date: Date): void {
    if (!this.isInitialized) {
      throw new PyAirtableSDKError('NotificationManager not initialized');
    }

    PushNotification.localNotificationSchedule({
      title: config.title,
      message: config.body,
      date,
      channelId: config.channelId || this.options.defaultChannelId,
      playSound: this.options.enableSound && (config.sound !== undefined ? !!config.sound : true),
      soundName: config.sound || 'default',
      importance: this.getImportance(config.priority),
      priority: config.priority || 'normal',
      vibrate: this.options.enableVibration,
      userInfo: config.data || {},
      number: config.badge,
      color: config.color,
      largeIcon: config.icon,
      smallIcon: config.icon,
    });
  }

  /**
   * Cancel all notifications
   */
  cancelAllNotifications(): void {
    PushNotification.cancelAllLocalNotifications();
  }

  /**
   * Cancel notification by ID
   */
  cancelNotification(id: string): void {
    PushNotification.cancelLocalNotifications({ id });
  }

  /**
   * Set application badge number (iOS)
   */
  setBadgeNumber(number: number): void {
    PushNotification.setApplicationIconBadgeNumber(number);
  }

  /**
   * Get application badge number (iOS)
   */
  getBadgeNumber(): Promise<number> {
    return new Promise((resolve) => {
      PushNotification.getApplicationIconBadgeNumber((badgeNumber) => {
        resolve(badgeNumber);
      });
    });
  }

  /**
   * Request permissions (iOS)
   */
  async requestPermissions(): Promise<boolean> {
    return new Promise((resolve) => {
      PushNotification.requestPermissions((permissions) => {
        resolve(permissions.alert || permissions.badge || permissions.sound);
      });
    });
  }

  /**
   * Check if notifications are enabled
   */
  async checkPermissions(): Promise<{
    alert: boolean;
    badge: boolean;
    sound: boolean;
  }> {
    return new Promise((resolve) => {
      PushNotification.checkPermissions((permissions) => {
        resolve(permissions);
      });
    });
  }

  /**
   * Show sync status notification
   */
  showSyncNotification(status: 'syncing' | 'completed' | 'failed', details?: string): void {
    const config: PushNotificationConfig = {
      title: 'PyAirtable Sync',
      body: this.getSyncMessage(status, details),
      channelId: NOTIFICATION_CHANNELS.SYNC,
      priority: status === 'failed' ? 'high' : 'low',
      data: { type: 'sync', status },
    };

    this.showNotification(config);
  }

  /**
   * Show record update notification
   */
  showRecordUpdateNotification(
    action: 'created' | 'updated' | 'deleted',
    tableName: string,
    recordCount: number = 1
  ): void {
    const config: PushNotificationConfig = {
      title: 'Record Updated',
      body: `${recordCount} record${recordCount > 1 ? 's' : ''} ${action} in ${tableName}`,
      channelId: NOTIFICATION_CHANNELS.UPDATES,
      priority: 'normal',
      data: { type: 'record_update', action, tableName, recordCount },
    };

    this.showNotification(config);
  }

  /**
   * Get importance level for Android
   */
  private getImportance(priority?: 'high' | 'normal' | 'low'): Importance {
    switch (priority) {
      case 'high':
        return Importance.HIGH;
      case 'low':
        return Importance.LOW;
      default:
        return Importance.DEFAULT;
    }
  }

  /**
   * Get sync status message
   */
  private getSyncMessage(status: 'syncing' | 'completed' | 'failed', details?: string): string {
    switch (status) {
      case 'syncing':
        return 'Syncing data with server...';
      case 'completed':
        return details || 'Data synchronized successfully';
      case 'failed':
        return details || 'Sync failed. Will retry automatically.';
      default:
        return 'Sync status update';
    }
  }

  /**
   * Cleanup and remove all listeners
   */
  destroy(): void {
    this.cancelAllNotifications();
    this.isInitialized = false;
  }
}