#!/usr/bin/env node

const { Queue, Worker, QueueEvents } = require('bullmq');
const Redis = require('redis');

// Redis configuration
const redisConfig = {
  host: process.env.REDIS_HOST || 'redis',
  port: parseInt(process.env.REDIS_PORT) || 6379,
  password: process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: 3,
  retryDelayOnFailure: 1000,
  lazyConnect: true
};

const DLQ_QUEUE_NAME = process.env.DLQ_QUEUE_NAME || 'dead-letter-queue';
const RETRY_ATTEMPTS = parseInt(process.env.RETRY_ATTEMPTS) || 3;
const RETRY_DELAY = parseInt(process.env.RETRY_DELAY) || 60000; // 1 minute

console.log('DLQ Processor Configuration:', {
  redisHost: redisConfig.host,
  redisPort: redisConfig.port,
  queueName: DLQ_QUEUE_NAME,
  retryAttempts: RETRY_ATTEMPTS,
  retryDelay: RETRY_DELAY
});

class DLQProcessor {
  constructor() {
    this.dlqQueue = null;
    this.retryQueues = new Map();
    this.worker = null;
    this.redisClient = null;
    this.stats = {
      processed: 0,
      retried: 0,
      permanentFailures: 0,
      alerts: 0
    };
  }

  async initialize() {
    try {
      // Initialize Redis client
      this.redisClient = Redis.createClient(redisConfig);
      await this.redisClient.connect();
      
      // Initialize DLQ queue
      this.dlqQueue = new Queue(DLQ_QUEUE_NAME, {
        connection: redisConfig,
        defaultJobOptions: {
          removeOnComplete: 0, // Keep all completed DLQ jobs
          removeOnFail: 0,     // Keep all failed DLQ jobs
          attempts: 1          // DLQ jobs get only 1 attempt
        }
      });

      // Initialize worker
      this.worker = new Worker(DLQ_QUEUE_NAME, 
        async (job) => await this.processFailedJob(job),
        {
          connection: redisConfig,
          concurrency: 2
        }
      );

      // Set up event listeners
      this.setupEventListeners();

      console.log('✅ DLQ Processor initialized successfully');
      
    } catch (error) {
      console.error('❌ Failed to initialize DLQ processor:', error);
      throw error;
    }
  }

  setupEventListeners() {
    this.worker.on('completed', (job, result) => {
      console.log(`✅ DLQ job ${job.id} completed:`, result);
      this.stats.processed++;
    });

    this.worker.on('failed', (job, err) => {
      console.error(`❌ DLQ job ${job.id} failed:`, err.message);
      this.stats.permanentFailures++;
      this.sendAlert('DLQ_JOB_FAILED', { jobId: job.id, error: err.message });
    });

    this.worker.on('error', (err) => {
      console.error('❌ DLQ worker error:', err);
    });

    this.dlqQueue.on('error', (err) => {
      console.error('❌ DLQ queue error:', err);
    });
  }

  async processFailedJob(job) {
    console.log(`🔄 Processing DLQ job ${job.id} from queue: ${job.data.originalQueue}`);
    
    const {
      originalQueue,
      originalJobId,
      originalJobName,
      originalJobData,
      failureReason,
      failedAt,
      attempts
    } = job.data;

    try {
      // Analyze the failure
      const analysis = await this.analyzeFailure(job.data);
      
      switch (analysis.action) {
        case 'RETRY':
          return await this.retryJob(job.data, analysis);
          
        case 'ALERT':
          return await this.sendAlert('MANUAL_INTERVENTION_REQUIRED', job.data);
          
        case 'DISCARD':
          return await this.discardJob(job.data, analysis.reason);
          
        case 'ESCALATE':
          return await this.escalateJob(job.data, analysis);
          
        default:
          return await this.logAndArchive(job.data);
      }
      
    } catch (error) {
      console.error(`❌ Error processing DLQ job ${job.id}:`, error);
      throw error;
    }
  }

  async analyzeFailure(jobData) {
    const { originalJobName, failureReason, attempts } = jobData;
    
    // Simple failure analysis logic
    // In a real system, this could be much more sophisticated
    
    if (failureReason.includes('ECONNREFUSED') || 
        failureReason.includes('timeout') ||
        failureReason.includes('ETIMEDOUT')) {
      return {
        action: 'RETRY',
        reason: 'Network or timeout error - likely transient',
        retryDelay: RETRY_DELAY * Math.min(attempts, 5) // Exponential backoff
      };
    }
    
    if (failureReason.includes('validation') ||
        failureReason.includes('invalid') ||
        failureReason.includes('malformed')) {
      return {
        action: 'DISCARD',
        reason: 'Validation error - data is malformed'
      };
    }
    
    if (failureReason.includes('authentication') ||
        failureReason.includes('unauthorized') ||
        failureReason.includes('forbidden')) {
      return {
        action: 'ALERT',
        reason: 'Authentication/authorization error - needs manual fix'
      };
    }
    
    if (originalJobName === 'critical-operation' || 
        originalJobName === 'payment-processing') {
      return {
        action: 'ESCALATE',
        reason: 'Critical job failure requires immediate attention'
      };
    }
    
    if (attempts >= 5) {
      return {
        action: 'ALERT',
        reason: 'Too many failed attempts - manual intervention required'
      };
    }
    
    // Default: retry once more
    return {
      action: 'RETRY',
      reason: 'Generic failure - attempting retry',
      retryDelay: RETRY_DELAY
    };
  }

  async retryJob(jobData, analysis) {
    const { originalQueue, originalJobName, originalJobData } = jobData;
    
    try {
      // Get or create the retry queue
      let retryQueue = this.retryQueues.get(originalQueue);
      if (!retryQueue) {
        retryQueue = new Queue(originalQueue, { connection: redisConfig });
        this.retryQueues.set(originalQueue, retryQueue);
      }
      
      // Add job back to original queue with delay
      const retryJob = await retryQueue.add(
        `retry-${originalJobName}`,
        {
          ...originalJobData,
          retryAttempt: (originalJobData.retryAttempt || 0) + 1,
          dlqRetryReason: analysis.reason
        },
        {
          delay: analysis.retryDelay || RETRY_DELAY,
          attempts: 2 // Give it 2 more attempts
        }
      );
      
      this.stats.retried++;
      
      console.log(`🔄 Retried job ${retryJob.id} in queue ${originalQueue} with ${analysis.retryDelay}ms delay`);
      
      return {
        action: 'retried',
        newJobId: retryJob.id,
        queue: originalQueue,
        delay: analysis.retryDelay,
        reason: analysis.reason
      };
      
    } catch (error) {
      console.error(`❌ Failed to retry job:`, error);
      
      // If retry fails, escalate
      return await this.escalateJob(jobData, {
        reason: `Retry failed: ${error.message}`
      });
    }
  }

  async sendAlert(alertType, jobData) {
    const alert = {
      type: alertType,
      timestamp: new Date().toISOString(),
      jobData: jobData,
      severity: this.getAlertSeverity(alertType),
      message: this.getAlertMessage(alertType, jobData)
    };
    
    console.log(`🚨 ALERT [${alert.severity}]: ${alert.message}`);
    
    // Store alert in Redis for external monitoring
    await this.redisClient.lPush('dlq:alerts', JSON.stringify(alert));
    await this.redisClient.expire('dlq:alerts', 86400 * 7); // Keep for 7 days
    
    // Could also send to external alerting system (Slack, PagerDuty, etc.)
    this.stats.alerts++;
    
    return {
      action: 'alerted',
      alert: alert
    };
  }

  async escalateJob(jobData, analysis) {
    console.log(`🚨 ESCALATING job from ${jobData.originalQueue}: ${analysis.reason}`);
    
    const escalation = {
      timestamp: new Date().toISOString(),
      jobData: jobData,
      reason: analysis.reason,
      severity: 'CRITICAL',
      requiresImmediateAttention: true
    };
    
    // Store in escalation queue
    await this.redisClient.lPush('dlq:escalations', JSON.stringify(escalation));
    
    // Send high-priority alert
    await this.sendAlert('ESCALATED_JOB', escalation);
    
    return {
      action: 'escalated',
      escalation: escalation
    };
  }

  async discardJob(jobData, reason) {
    console.log(`🗑️ DISCARDING job ${jobData.originalJobId}: ${reason}`);
    
    const discard = {
      timestamp: new Date().toISOString(),
      jobData: jobData,
      reason: reason,
      action: 'discarded'
    };
    
    // Store in discarded jobs log
    await this.redisClient.lPush('dlq:discarded', JSON.stringify(discard));
    
    return discard;
  }

  async logAndArchive(jobData) {
    console.log(`📁 ARCHIVING job ${jobData.originalJobId} for manual review`);
    
    const archive = {
      timestamp: new Date().toISOString(),
      jobData: jobData,
      action: 'archived',
      status: 'pending_manual_review'
    };
    
    // Store in archive
    await this.redisClient.lPush('dlq:archive', JSON.stringify(archive));
    
    return archive;
  }

  getAlertSeverity(alertType) {
    const severityMap = {
      'DLQ_JOB_FAILED': 'HIGH',
      'MANUAL_INTERVENTION_REQUIRED': 'MEDIUM',
      'ESCALATED_JOB': 'CRITICAL',
      'RETRY_FAILED': 'HIGH'
    };
    
    return severityMap[alertType] || 'MEDIUM';
  }

  getAlertMessage(alertType, jobData) {
    const messages = {
      'DLQ_JOB_FAILED': `DLQ job ${jobData.originalJobId} failed permanently`,
      'MANUAL_INTERVENTION_REQUIRED': `Job ${jobData.originalJobId} requires manual intervention`,
      'ESCALATED_JOB': `Critical job ${jobData.originalJobId} escalated`,
      'RETRY_FAILED': `Failed to retry job ${jobData.originalJobId}`
    };
    
    return messages[alertType] || `DLQ alert for job ${jobData.originalJobId}`;
  }

  async getStats() {
    const [alertsCount, escalationsCount, discardedCount, archivedCount] = await Promise.all([
      this.redisClient.lLen('dlq:alerts'),
      this.redisClient.lLen('dlq:escalations'),
      this.redisClient.lLen('dlq:discarded'),
      this.redisClient.lLen('dlq:archive')
    ]);

    return {
      ...this.stats,
      totalAlerts: alertsCount,
      totalEscalations: escalationsCount,
      totalDiscarded: discardedCount,
      totalArchived: archivedCount,
      timestamp: new Date().toISOString()
    };
  }

  async stop() {
    console.log('🛑 Stopping DLQ processor...');
    
    if (this.worker) {
      await this.worker.close();
    }
    
    if (this.dlqQueue) {
      await this.dlqQueue.close();
    }
    
    // Close all retry queues
    for (const queue of this.retryQueues.values()) {
      await queue.close();
    }
    
    if (this.redisClient) {
      await this.redisClient.quit();
    }
    
    console.log('✅ DLQ processor stopped');
  }
}

// Main execution
async function main() {
  const processor = new DLQProcessor();
  
  // Graceful shutdown handlers
  process.on('SIGINT', async () => {
    console.log('\n🛑 Received SIGINT, shutting down DLQ processor...');
    await processor.stop();
    process.exit(0);
  });
  
  process.on('SIGTERM', async () => {
    console.log('\n🛑 Received SIGTERM, shutting down DLQ processor...');
    await processor.stop();
    process.exit(0);
  });
  
  try {
    await processor.initialize();
    console.log('🚀 DLQ Processor is running...');
    
    // Keep the process alive and periodically log stats
    setInterval(async () => {
      const stats = await processor.getStats();
      console.log('📊 DLQ Stats:', stats);
    }, 60000); // Every minute
    
    // Keep process alive
    await new Promise(() => {}); 
    
  } catch (error) {
    console.error('💥 Fatal error in DLQ processor:', error);
    process.exit(1);
  }
}

// Start the DLQ processor
if (require.main === module) {
  main().catch(console.error);
}

module.exports = DLQProcessor;