#!/usr/bin/env node

const Redis = require('redis');

/**
 * Event Publisher utility for PyAirtable services
 * Provides simple pub/sub and stream publishing functionality
 */
class EventPublisher {
  constructor(config = {}) {
    this.redisConfig = {
      host: config.host || process.env.REDIS_HOST || 'redis-streams',
      port: parseInt(config.port || process.env.REDIS_PORT) || 6379,
      password: config.password || process.env.REDIS_PASSWORD,
      lazyConnect: true,
      maxRetriesPerRequest: 3,
      retryDelayOnFailure: 1000
    };
    
    this.streamName = config.streamName || 'pyairtable-events';
    this.client = null;
    this.connected = false;
  }

  async connect() {
    if (this.connected) return;
    
    try {
      this.client = Redis.createClient(this.redisConfig);
      
      this.client.on('error', (err) => {
        console.error('Event Publisher Redis error:', err);
        this.connected = false;
      });
      
      this.client.on('connect', () => {
        console.log('✅ Event Publisher connected to Redis');
        this.connected = true;
      });
      
      await this.client.connect();
      
    } catch (error) {
      console.error('❌ Failed to connect Event Publisher to Redis:', error);
      throw error;
    }
  }

  async disconnect() {
    if (this.client && this.connected) {
      await this.client.quit();
      this.connected = false;
      console.log('✅ Event Publisher disconnected from Redis');
    }
  }

  /**
   * Publish an event to Redis Stream
   * @param {string} eventType - Type of event (e.g., 'user.created')
   * @param {object} data - Event data
   * @param {object} metadata - Additional metadata
   */
  async publishEvent(eventType, data = {}, metadata = {}) {
    if (!this.connected) {
      await this.connect();
    }

    const event = {
      type: eventType,
      timestamp: new Date().toISOString(),
      source: metadata.source || 'unknown',
      userId: metadata.userId || null,
      workspaceId: metadata.workspaceId || null,
      correlationId: metadata.correlationId || this.generateCorrelationId(),
      data: JSON.stringify(data)
    };

    try {
      const messageId = await this.client.xAdd(this.streamName, '*', event);
      
      console.log(`📤 Published event ${eventType} with ID: ${messageId}`);
      
      return {
        success: true,
        messageId: messageId,
        eventType: eventType,
        timestamp: event.timestamp
      };
      
    } catch (error) {
      console.error(`❌ Failed to publish event ${eventType}:`, error);
      throw error;
    }
  }

  /**
   * Publish to Redis Pub/Sub for real-time notifications
   * @param {string} channel - Channel name
   * @param {object} message - Message to publish
   */
  async publishMessage(channel, message) {
    if (!this.connected) {
      await this.connect();
    }

    const payload = {
      timestamp: new Date().toISOString(),
      ...message
    };

    try {
      const result = await this.client.publish(channel, JSON.stringify(payload));
      
      console.log(`📢 Published message to ${channel}, ${result} subscribers notified`);
      
      return {
        success: true,
        channel: channel,
        subscribers: result,
        timestamp: payload.timestamp
      };
      
    } catch (error) {
      console.error(`❌ Failed to publish message to ${channel}:`, error);
      throw error;
    }
  }

  /**
   * Convenience methods for common events
   */

  async publishUserEvent(eventType, userId, userData = {}, metadata = {}) {
    return this.publishEvent(`user.${eventType}`, userData, {
      ...metadata,
      userId: userId,
      source: metadata.source || 'user-service'
    });
  }

  async publishWorkspaceEvent(eventType, workspaceId, workspaceData = {}, metadata = {}) {
    return this.publishEvent(`workspace.${eventType}`, workspaceData, {
      ...metadata,
      workspaceId: workspaceId,
      source: metadata.source || 'workspace-service'
    });
  }

  async publishAirtableEvent(eventType, syncData = {}, metadata = {}) {
    return this.publishEvent(`airtable.${eventType}`, syncData, {
      ...metadata,
      source: metadata.source || 'airtable-gateway'
    });
  }

  async publishJobEvent(eventType, jobData = {}, metadata = {}) {
    return this.publishEvent(`job.${eventType}`, jobData, {
      ...metadata,
      source: metadata.source || 'job-processor'
    });
  }

  async publishAuthEvent(eventType, authData = {}, metadata = {}) {
    return this.publishEvent(`auth.${eventType}`, authData, {
      ...metadata,
      source: metadata.source || 'auth-service'
    });
  }

  /**
   * Real-time notification methods
   */

  async notifyUser(userId, message) {
    return this.publishMessage(`user:${userId}`, {
      type: 'notification',
      userId: userId,
      message: message
    });
  }

  async notifyWorkspace(workspaceId, message) {
    return this.publishMessage(`workspace:${workspaceId}`, {
      type: 'notification',
      workspaceId: workspaceId,
      message: message
    });
  }

  async broadcastSystem(message) {
    return this.publishMessage('system:broadcast', {
      type: 'system',
      message: message
    });
  }

  generateCorrelationId() {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Health check
   */
  async healthCheck() {
    if (!this.connected) {
      return { healthy: false, error: 'Not connected' };
    }

    try {
      await this.client.ping();
      return { 
        healthy: true, 
        connected: this.connected,
        streamName: this.streamName,
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      return { 
        healthy: false, 
        error: error.message,
        timestamp: new Date().toISOString()
      };
    }
  }
}

// Factory function for easy use in other services
function createEventPublisher(config = {}) {
  return new EventPublisher(config);
}

// CLI usage
if (require.main === module) {
  const publisher = new EventPublisher();
  
  async function demo() {
    try {
      await publisher.connect();
      
      // Demo events
      await publisher.publishUserEvent('created', 'user123', { 
        email: 'user@example.com', 
        name: 'Test User' 
      });
      
      await publisher.publishWorkspaceEvent('created', 'ws456', { 
        name: 'Test Workspace',
        ownerId: 'user123' 
      });
      
      await publisher.publishAirtableEvent('sync.completed', { 
        baseId: 'base789',
        records: 150,
        duration: 5000 
      });
      
      await publisher.notifyUser('user123', 'Welcome to PyAirtable!');
      
      console.log('✅ Demo events published successfully');
      
      await publisher.disconnect();
      
    } catch (error) {
      console.error('❌ Demo failed:', error);
      process.exit(1);
    }
  }
  
  if (process.argv[2] === 'demo') {
    demo();
  } else {
    console.log('Event Publisher utility');
    console.log('Usage: node event-publisher.js demo');
  }
}

module.exports = { EventPublisher, createEventPublisher };