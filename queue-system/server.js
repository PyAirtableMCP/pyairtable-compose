#!/usr/bin/env node

const express = require('express');
const { Queue, Worker, QueueEvents } = require('bullmq');
const { createBullBoard } = require('@bull-board/api');
const { BullMQAdapter } = require('@bull-board/api/bullMQAdapter');
const { ExpressAdapter } = require('@bull-board/express');
const Redis = require('redis');

const app = express();
app.use(express.json());

// Redis connection configuration
const redisConfig = {
  host: process.env.REDIS_HOST || 'redis-queue',
  port: parseInt(process.env.REDIS_PORT) || 6379,
  password: process.env.REDIS_PASSWORD,
  db: parseInt(process.env.REDIS_DB) || 0,
  maxRetriesPerRequest: 3,
  retryDelayOnFailure: 1000,
  lazyConnect: true
};

console.log('Redis Queue Configuration:', {
  host: redisConfig.host,
  port: redisConfig.port,
  db: redisConfig.db
});

// Queue definitions for different job types
const queues = {
  'long-running-jobs': new Queue('long-running-jobs', {
    connection: redisConfig,
    defaultJobOptions: {
      removeOnComplete: 10,
      removeOnFail: 50,
      attempts: parseInt(process.env.MAX_JOB_ATTEMPTS) || 3,
      backoff: {
        type: 'exponential',
        delay: 5000,
      },
      delay: 0,
      // 60 minutes timeout
      timeout: parseInt(process.env.JOB_TIMEOUT) || 3600000
    }
  }),
  
  'async-processing': new Queue('async-processing', {
    connection: redisConfig,
    defaultJobOptions: {
      removeOnComplete: 20,
      removeOnFail: 100,
      attempts: 3,
      backoff: {
        type: 'exponential',
        delay: 2000,
      },
      timeout: 600000 // 10 minutes
    }
  }),
  
  'event-driven-jobs': new Queue('event-driven-jobs', {
    connection: redisConfig,
    defaultJobOptions: {
      removeOnComplete: 50,
      removeOnFail: 200,
      attempts: 5,
      backoff: {
        type: 'exponential',
        delay: 1000,
      },
      timeout: 300000 // 5 minutes
    }
  }),
  
  'dlq': new Queue('dead-letter-queue', {
    connection: redisConfig,
    defaultJobOptions: {
      removeOnComplete: 0, // Never remove completed DLQ jobs
      removeOnFail: 0,     // Never remove failed DLQ jobs
      attempts: 1,          // DLQ jobs get only 1 attempt
      timeout: 30000       // 30 seconds
    }
  })
};

// Workers for processing different types of jobs
Object.keys(queues).forEach(queueName => {
  if (queueName === 'dlq') return; // Skip DLQ worker creation here
  
  const worker = new Worker(queueName, async (job) => {
    console.log(`[${queueName}] Processing job ${job.id}:`, job.name);
    
    try {
      // Simulate different types of job processing
      switch (job.name) {
        case 'ai-processing':
          return await processAIJob(job);
        case 'data-sync':
          return await processDataSyncJob(job);
        case 'bulk-operation':
          return await processBulkOperationJob(job);
        case 'notification':
          return await processNotificationJob(job);
        default:
          console.log(`Processing generic job: ${job.name}`, job.data);
          // Simulate processing time based on job data
          const duration = job.data.duration || Math.random() * 10000;
          await new Promise(resolve => setTimeout(resolve, duration));
          return { status: 'completed', processedAt: new Date().toISOString() };
      }
    } catch (error) {
      console.error(`[${queueName}] Job ${job.id} failed:`, error);
      
      // Send failed jobs to DLQ if they've exhausted retries
      if (job.attemptsMade >= (job.opts.attempts || 3)) {
        await queues.dlq.add('failed-job', {
          originalQueue: queueName,
          originalJobId: job.id,
          originalJobName: job.name,
          originalJobData: job.data,
          failureReason: error.message,
          failedAt: new Date().toISOString(),
          attempts: job.attemptsMade
        });
        console.log(`[${queueName}] Job ${job.id} sent to DLQ after ${job.attemptsMade} attempts`);
      }
      
      throw error;
    }
  }, {
    connection: redisConfig,
    concurrency: parseInt(process.env.CONCURRENCY) || 5
  });
  
  worker.on('completed', (job, result) => {
    console.log(`[${queueName}] Job ${job.id} completed:`, result);
  });
  
  worker.on('failed', (job, err) => {
    console.error(`[${queueName}] Job ${job.id} failed:`, err.message);
  });
  
  worker.on('error', (err) => {
    console.error(`[${queueName}] Worker error:`, err);
  });
});

// DLQ Worker - processes failed jobs for retry or manual intervention
const dlqWorker = new Worker('dead-letter-queue', async (job) => {
  console.log(`[DLQ] Processing failed job from ${job.data.originalQueue}:`, job.data);
  
  // For now, just log the failed job
  // In a real system, this could trigger alerts, retry logic, or manual intervention
  return {
    status: 'logged',
    processedAt: new Date().toISOString(),
    action: 'manual-review-required'
  };
}, {
  connection: redisConfig,
  concurrency: 2
});

// Job processing functions
async function processAIJob(job) {
  console.log('Processing AI job:', job.data);
  // Simulate AI processing
  const processingTime = Math.random() * 30000 + 10000; // 10-40 seconds
  await new Promise(resolve => setTimeout(resolve, processingTime));
  return { 
    status: 'completed', 
    result: 'AI processing completed',
    processingTime: processingTime 
  };
}

async function processDataSyncJob(job) {
  console.log('Processing data sync job:', job.data);
  // Simulate data synchronization
  const syncTime = Math.random() * 60000 + 30000; // 30-90 seconds
  await new Promise(resolve => setTimeout(resolve, syncTime));
  return { 
    status: 'completed', 
    recordsSynced: Math.floor(Math.random() * 1000) + 100,
    syncTime: syncTime 
  };
}

async function processBulkOperationJob(job) {
  console.log('Processing bulk operation job:', job.data);
  // Simulate bulk operations that can take up to 60 minutes
  const operationTime = Math.random() * 1800000 + 600000; // 10-40 minutes
  
  // Simulate progress reporting
  const totalSteps = 10;
  for (let step = 1; step <= totalSteps; step++) {
    await new Promise(resolve => setTimeout(resolve, operationTime / totalSteps));
    await job.updateProgress(Math.round((step / totalSteps) * 100));
    console.log(`[Bulk Operation] Progress: ${step}/${totalSteps}`);
  }
  
  return { 
    status: 'completed', 
    itemsProcessed: Math.floor(Math.random() * 10000) + 1000,
    operationTime: operationTime 
  };
}

async function processNotificationJob(job) {
  console.log('Processing notification job:', job.data);
  // Simulate notification sending
  const notificationTime = Math.random() * 5000 + 1000; // 1-6 seconds
  await new Promise(resolve => setTimeout(resolve, notificationTime));
  return { 
    status: 'completed', 
    notificationsSent: job.data.recipients?.length || 1,
    notificationTime: notificationTime 
  };
}

// Bull Board setup for queue monitoring
const serverAdapter = new ExpressAdapter();
serverAdapter.setBasePath('/admin/queues');

const { addQueue } = createBullBoard({
  queues: Object.keys(queues).map(name => new BullMQAdapter(queues[name])),
  serverAdapter: serverAdapter
});

// Mount Bull Board
app.use('/admin/queues', serverAdapter.getRouter());

// API endpoints
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    timestamp: new Date().toISOString(),
    queues: Object.keys(queues),
    environment: process.env.NODE_ENV
  });
});

app.get('/stats', async (req, res) => {
  try {
    const stats = {};
    
    for (const [name, queue] of Object.entries(queues)) {
      const waiting = await queue.getWaiting();
      const active = await queue.getActive();
      const completed = await queue.getCompleted();
      const failed = await queue.getFailed();
      
      stats[name] = {
        waiting: waiting.length,
        active: active.length,
        completed: completed.length,
        failed: failed.length
      };
    }
    
    res.json(stats);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Job creation endpoint
app.post('/jobs/:queue', async (req, res) => {
  try {
    const { queue: queueName } = req.params;
    const { name, data, options } = req.body;
    
    if (!queues[queueName]) {
      return res.status(404).json({ error: 'Queue not found' });
    }
    
    const job = await queues[queueName].add(name, data, options);
    
    res.json({
      id: job.id,
      name: job.name,
      queue: queueName,
      data: job.data,
      created: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Queue cleanup endpoint
app.post('/queues/:queue/clean', async (req, res) => {
  try {
    const { queue: queueName } = req.params;
    const { status, age = 86400000 } = req.body; // default 24 hours
    
    if (!queues[queueName]) {
      return res.status(404).json({ error: 'Queue not found' });
    }
    
    const cleaned = await queues[queueName].clean(age, status);
    
    res.json({
      queue: queueName,
      cleaned: cleaned.length,
      status: status,
      age: age
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const port = parseInt(process.env.QUEUE_UI_PORT) || 3000;
const host = process.env.QUEUE_UI_HOST || '0.0.0.0';

app.listen(port, host, () => {
  console.log(`🚀 Queue Server running on http://${host}:${port}`);
  console.log(`📊 Queue UI available at http://${host}:${port}/admin/queues`);
  console.log(`🏥 Health check at http://${host}:${port}/health`);
  console.log(`📈 Stats at http://${host}:${port}/stats`);
  console.log('⚙️ Queues initialized:', Object.keys(queues));
});

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n🛑 Shutting down gracefully...');
  
  // Close all queues and workers
  for (const queue of Object.values(queues)) {
    await queue.close();
  }
  
  process.exit(0);
});