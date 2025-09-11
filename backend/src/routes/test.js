const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');

// Simple ping endpoint (no auth required)
router.get('/ping', (req, res) => {
  res.json({ 
    pong: true, 
    timestamp: new Date().toISOString(),
    message: 'Test endpoint working',
    version: '2.0.1' 
  });
});

// Test QStash connectivity and configuration
router.get('/qstash-config', verifyToken, async (req, res) => {
  try {
    const config = {
      QSTASH_TOKEN: !!process.env.QSTASH_TOKEN,
      QSTASH_URL: !!process.env.QSTASH_URL,
      QSTASH_CURRENT_SIGNING_KEY: !!process.env.QSTASH_CURRENT_SIGNING_KEY,
      QSTASH_NEXT_SIGNING_KEY: !!process.env.QSTASH_NEXT_SIGNING_KEY,
      NODE_ENV: process.env.NODE_ENV,
      WORKER_URL: process.env.NODE_ENV === 'production' 
        ? 'https://squirrel2.vercel.app/api/workers/process-inference'
        : 'http://localhost:3001/api/workers/process-inference'
    };
    
    res.json(config);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Test QStash by sending a test message
router.post('/qstash-test', verifyToken, async (req, res) => {
  try {
    const { enqueueInference } = require('../services/queue');
    
    console.log('[TEST] Attempting to queue test inference job...');
    const jobId = await enqueueInference('test-entry-id', req.user.uid, 'Test content for QStash');
    console.log('[TEST] Successfully queued job:', jobId);
    
    res.json({ 
      success: true, 
      jobId,
      message: 'Test job queued successfully'
    });
  } catch (error) {
    console.error('[TEST] Failed to queue test job:', error);
    res.status(500).json({ 
      error: error.message,
      stack: error.stack 
    });
  }
});

// Test the worker endpoint directly
router.post('/worker-test', verifyToken, async (req, res) => {
  try {
    const axios = require('axios');
    const workerUrl = process.env.NODE_ENV === 'production' 
      ? 'https://squirrel2.vercel.app/api/workers/process-inference'
      : 'http://localhost:3001/api/workers/process-inference';
    
    console.log('[TEST] Testing worker endpoint:', workerUrl);
    
    const response = await axios.post(workerUrl, {
      entryId: 'test-entry-id',
      userId: req.user.uid,
      content: 'Test content for worker'
    }, {
      headers: {
        'upstash-signature': 'test-signature' // Fake signature for testing
      }
    });
    
    console.log('[TEST] Worker response:', response.data);
    res.json(response.data);
  } catch (error) {
    console.error('[TEST] Worker test failed:', error.message);
    res.status(500).json({ 
      error: error.message,
      response: error.response?.data 
    });
  }
});

module.exports = router;