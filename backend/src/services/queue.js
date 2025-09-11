const { Client } = require('@upstash/qstash');

// Initialize QStash client
const qstashClient = new Client({
  token: process.env.QSTASH_TOKEN || ''
});

// Base URL for worker endpoints
const getWorkerUrl = (path) => {
  const baseUrl = process.env.NODE_ENV === 'production' 
    ? 'https://squirrel2.vercel.app'
    : process.env.WORKER_BASE_URL || 'http://localhost:3001';
  return `${baseUrl}/api/workers${path}`;
};

/**
 * Enqueue collection inference job
 */
async function enqueueInference(entryId, userId, content) {
  try {
    console.log(`[QUEUE] Enqueuing inference for entry ${entryId}`);
    
    const response = await qstashClient.publishJSON({
      url: getWorkerUrl('/process-inference'),
      body: {
        entryId,
        userId,
        content,
        timestamp: new Date().toISOString()
      },
      retries: 3,
      delay: 0 // Process immediately
    });
    
    console.log(`[QUEUE] Inference job queued with ID: ${response.messageId}`);
    return response.messageId;
  } catch (error) {
    console.error('[QUEUE] Failed to enqueue inference:', error);
    throw error;
  }
}

/**
 * Enqueue collection rule processing job
 */
async function enqueueCollectionProcessing(collectionId, userId, data = {}) {
  try {
    console.log(`[QUEUE] Enqueuing collection processing for ${collectionId}`);
    
    const response = await qstashClient.publishJSON({
      url: getWorkerUrl('/process-collection'),
      body: {
        collectionId,
        userId,
        ...data,
        timestamp: new Date().toISOString()
      },
      retries: 3,
      delay: 0
    });
    
    console.log(`[QUEUE] Collection job queued with ID: ${response.messageId}`);
    return response.messageId;
  } catch (error) {
    console.error('[QUEUE] Failed to enqueue collection processing:', error);
    throw error;
  }
}

/**
 * Enqueue AI generation job (for complex AI tasks)
 */
async function enqueueAIGeneration(type, data) {
  try {
    console.log(`[QUEUE] Enqueuing AI generation of type: ${type}`);
    
    const response = await qstashClient.publishJSON({
      url: getWorkerUrl('/process-ai'),
      body: {
        type,
        data,
        timestamp: new Date().toISOString()
      },
      retries: 2,
      delay: 0
    });
    
    console.log(`[QUEUE] AI generation job queued with ID: ${response.messageId}`);
    return response.messageId;
  } catch (error) {
    console.error('[QUEUE] Failed to enqueue AI generation:', error);
    throw error;
  }
}

/**
 * Enqueue batch processing job
 */
async function enqueueBatchProcessing(userId, operation, items) {
  try {
    console.log(`[QUEUE] Enqueuing batch ${operation} for ${items.length} items`);
    
    const response = await qstashClient.publishJSON({
      url: getWorkerUrl('/process-batch'),
      body: {
        userId,
        operation,
        items,
        timestamp: new Date().toISOString()
      },
      retries: 3,
      delay: 0
    });
    
    console.log(`[QUEUE] Batch job queued with ID: ${response.messageId}`);
    return response.messageId;
  } catch (error) {
    console.error('[QUEUE] Failed to enqueue batch processing:', error);
    throw error;
  }
}

/**
 * Schedule a delayed job
 */
async function scheduleJob(type, data, delaySeconds) {
  try {
    console.log(`[QUEUE] Scheduling ${type} job with ${delaySeconds}s delay`);
    
    const response = await qstashClient.publishJSON({
      url: getWorkerUrl(`/process-${type}`),
      body: {
        ...data,
        scheduled: true,
        timestamp: new Date().toISOString()
      },
      retries: 3,
      delay: delaySeconds
    });
    
    console.log(`[QUEUE] Scheduled job queued with ID: ${response.messageId}`);
    return response.messageId;
  } catch (error) {
    console.error('[QUEUE] Failed to schedule job:', error);
    throw error;
  }
}

module.exports = {
  enqueueInference,
  enqueueCollectionProcessing,
  enqueueAIGeneration,
  enqueueBatchProcessing,
  scheduleJob
};