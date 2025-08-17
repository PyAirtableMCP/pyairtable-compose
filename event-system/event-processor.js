#!/usr/bin/env node

const Redis = require('redis');

// Redis Streams configuration
const redisConfig = {
  host: process.env.REDIS_HOST || 'redis-streams',
  port: parseInt(process.env.REDIS_PORT) || 6379,
  password: process.env.REDIS_PASSWORD,
  lazyConnect: true,
  maxRetriesPerRequest: 3,
  retryDelayOnFailure: 1000
};

const STREAM_NAME = 'pyairtable-events';
const CONSUMER_GROUP = process.env.STREAM_CONSUMER_GROUP || 'event-processors';
const CONSUMER_NAME = process.env.STREAM_CONSUMER_NAME || 'processor-1';
const BATCH_SIZE = parseInt(process.env.BATCH_SIZE) || 10;
const BLOCK_TIME = parseInt(process.env.BLOCK_TIME) || 5000;

console.log('Event Processor Configuration:', {
  redisHost: redisConfig.host,
  redisPort: redisConfig.port,
  streamName: STREAM_NAME,
  consumerGroup: CONSUMER_GROUP,
  consumerName: CONSUMER_NAME,
  batchSize: BATCH_SIZE,
  blockTime: BLOCK_TIME
});

class EventProcessor {
  constructor() {
    this.client = null;
    this.running = false;
    this.processedCount = 0;
    this.errorCount = 0;
  }

  async initialize() {
    try {
      // Create Redis client
      this.client = Redis.createClient(redisConfig);
      
      this.client.on('error', (err) => {
        console.error('Redis client error:', err);
        this.errorCount++;
      });
      
      this.client.on('connect', () => {
        console.log('✅ Connected to Redis Streams');
      });
      
      this.client.on('ready', () => {
        console.log('🚀 Redis client ready for event processing');
      });
      
      // Connect to Redis
      await this.client.connect();
      
      // Create consumer group if it doesn't exist
      try {
        await this.client.xGroupCreate(STREAM_NAME, CONSUMER_GROUP, '0', {
          MKSTREAM: true
        });
        console.log(`✅ Created consumer group: ${CONSUMER_GROUP}`);
      } catch (error) {
        if (error.message.includes('BUSYGROUP')) {
          console.log(`ℹ️ Consumer group ${CONSUMER_GROUP} already exists`);
        } else {
          throw error;
        }
      }
      
      console.log('🎯 Event processor initialized successfully');
      
    } catch (error) {
      console.error('❌ Failed to initialize event processor:', error);
      throw error;
    }
  }

  async start() {
    this.running = true;
    console.log(`🏃 Starting event processor (${CONSUMER_NAME})...`);
    
    while (this.running) {
      try {
        await this.processEventBatch();
      } catch (error) {
        console.error('❌ Error in event processing loop:', error);
        this.errorCount++;
        
        // Backoff on consecutive errors
        if (this.errorCount > 5) {
          console.log('⏳ Too many errors, backing off for 10 seconds...');
          await this.sleep(10000);
          this.errorCount = 0;
        } else {
          await this.sleep(1000);
        }
      }
    }
    
    console.log('🛑 Event processor stopped');
  }

  async processEventBatch() {
    try {
      // Read events from stream
      const events = await this.client.xReadGroup(
        CONSUMER_GROUP,
        CONSUMER_NAME,
        [
          {
            key: STREAM_NAME,
            id: '>'  // Read only new messages
          }
        ],
        {
          COUNT: BATCH_SIZE,
          BLOCK: BLOCK_TIME
        }
      );

      if (!events || events.length === 0) {
        return; // No events to process
      }

      const streamEvents = events[0];
      if (!streamEvents || !streamEvents.messages) {
        return;
      }

      console.log(`📥 Processing ${streamEvents.messages.length} events from ${streamEvents.name}`);

      // Process each event
      for (const message of streamEvents.messages) {
        try {
          await this.processEvent(message);
          
          // Acknowledge the message
          await this.client.xAck(STREAM_NAME, CONSUMER_GROUP, message.id);
          this.processedCount++;
          
        } catch (error) {
          console.error(`❌ Failed to process event ${message.id}:`, error);
          this.errorCount++;
          
          // For now, still acknowledge to prevent reprocessing
          // In a real system, you might want to retry or send to DLQ
          await this.client.xAck(STREAM_NAME, CONSUMER_GROUP, message.id);
        }
      }

      console.log(`✅ Processed ${streamEvents.messages.length} events (Total: ${this.processedCount})`);
      
    } catch (error) {
      if (!error.message.includes('NOGROUP')) {
        throw error;
      }
    }
  }

  async processEvent(message) {
    const eventData = this.parseEventData(message.message);
    const eventType = eventData.type || 'unknown';
    
    console.log(`🎯 Processing ${eventType} event ${message.id}:`, {
      timestamp: eventData.timestamp,
      source: eventData.source,
      data: Object.keys(eventData.data || {})
    });

    // Route event to appropriate handler
    switch (eventType) {
      case 'user.created':
        await this.handleUserCreated(eventData);
        break;
        
      case 'user.updated':
        await this.handleUserUpdated(eventData);
        break;
        
      case 'workspace.created':
        await this.handleWorkspaceCreated(eventData);
        break;
        
      case 'workspace.updated':
        await this.handleWorkspaceUpdated(eventData);
        break;
        
      case 'airtable.sync.completed':
        await this.handleAirtableSyncCompleted(eventData);
        break;
        
      case 'airtable.sync.failed':
        await this.handleAirtableSyncFailed(eventData);
        break;
        
      case 'job.completed':
        await this.handleJobCompleted(eventData);
        break;
        
      case 'job.failed':
        await this.handleJobFailed(eventData);
        break;
        
      case 'notification.send':
        await this.handleNotificationSend(eventData);
        break;
        
      default:
        console.log(`⚠️ Unknown event type: ${eventType}`);
        await this.handleUnknownEvent(eventData);
    }
  }

  parseEventData(redisMessage) {
    try {
      const data = {};
      
      // Redis XADD stores data as key-value pairs
      for (let i = 0; i < redisMessage.length; i += 2) {
        const key = redisMessage[i];
        let value = redisMessage[i + 1];
        
        // Try to parse JSON values
        if (value.startsWith('{') || value.startsWith('[')) {
          try {
            value = JSON.parse(value);
          } catch (e) {
            // Keep as string if JSON parsing fails
          }
        }
        
        data[key] = value;
      }
      
      return data;
      
    } catch (error) {
      console.error('Failed to parse event data:', error);
      return { type: 'parse.error', error: error.message };
    }
  }

  // Event handlers
  async handleUserCreated(eventData) {
    console.log('👤 Handling user created event:', eventData.data?.userId);
    // Simulate processing
    await this.sleep(100);
  }

  async handleUserUpdated(eventData) {
    console.log('👤 Handling user updated event:', eventData.data?.userId);
    await this.sleep(50);
  }

  async handleWorkspaceCreated(eventData) {
    console.log('🏢 Handling workspace created event:', eventData.data?.workspaceId);
    await this.sleep(200);
  }

  async handleWorkspaceUpdated(eventData) {
    console.log('🏢 Handling workspace updated event:', eventData.data?.workspaceId);
    await this.sleep(100);
  }

  async handleAirtableSyncCompleted(eventData) {
    console.log('✅ Handling Airtable sync completed:', eventData.data?.syncId);
    await this.sleep(50);
  }

  async handleAirtableSyncFailed(eventData) {
    console.log('❌ Handling Airtable sync failed:', eventData.data?.syncId);
    // Could trigger retry logic or alerts
    await this.sleep(100);
  }

  async handleJobCompleted(eventData) {
    console.log('✅ Handling job completed:', eventData.data?.jobId);
    await this.sleep(50);
  }

  async handleJobFailed(eventData) {
    console.log('❌ Handling job failed:', eventData.data?.jobId);
    await this.sleep(100);
  }

  async handleNotificationSend(eventData) {
    console.log('📧 Handling notification send:', eventData.data?.recipientId);
    await this.sleep(150);
  }

  async handleUnknownEvent(eventData) {
    console.log('❓ Handling unknown event type:', eventData.type);
    await this.sleep(50);
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async stop() {
    console.log('🛑 Stopping event processor...');
    this.running = false;
    
    if (this.client) {
      await this.client.quit();
    }
  }

  // Health check method
  getStats() {
    return {
      running: this.running,
      processedCount: this.processedCount,
      errorCount: this.errorCount,
      consumerGroup: CONSUMER_GROUP,
      consumerName: CONSUMER_NAME
    };
  }
}

// Initialize and start the event processor
async function main() {
  const processor = new EventProcessor();
  
  // Graceful shutdown handlers
  process.on('SIGINT', async () => {
    console.log('\n🛑 Received SIGINT, shutting down gracefully...');
    await processor.stop();
    process.exit(0);
  });
  
  process.on('SIGTERM', async () => {
    console.log('\n🛑 Received SIGTERM, shutting down gracefully...');
    await processor.stop();
    process.exit(0);
  });
  
  try {
    await processor.initialize();
    await processor.start();
  } catch (error) {
    console.error('💥 Fatal error in event processor:', error);
    process.exit(1);
  }
}

// Start the processor
if (require.main === module) {
  main().catch(console.error);
}

module.exports = EventProcessor;