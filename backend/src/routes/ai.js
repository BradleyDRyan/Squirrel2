const express = require('express');
const router = express.Router();
const { chatCompletion, chatCompletionStream, generateEmbedding } = require('../services/openai');
const { verifyToken } = require('../middleware/auth');

// Chat completion endpoint
router.post('/chat', verifyToken, async (req, res) => {
  try {
    const { messages } = req.body;
    
    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: 'Messages array is required' });
    }

    const response = await chatCompletion(messages);
    res.json({ 
      success: true,
      message: response 
    });
  } catch (error) {
    console.error('Chat error:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to process chat request' 
    });
  }
});

// Chat completion streaming endpoint using SSE
router.post('/chat/stream', verifyToken, async (req, res) => {
  try {
    const { messages } = req.body;
    
    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: 'Messages array is required' });
    }

    // Set SSE headers
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });

    // Send initial connection message
    res.write('data: {"type":"connected"}\n\n');

    try {
      // Stream the response
      for await (const chunk of chatCompletionStream(messages)) {
        const data = JSON.stringify({ type: 'content', content: chunk });
        res.write(`data: ${data}\n\n`);
      }

      // Send completion message
      res.write('data: {"type":"done"}\n\n');
    } catch (streamError) {
      const errorData = JSON.stringify({ 
        type: 'error', 
        error: streamError.message || 'Stream processing failed' 
      });
      res.write(`data: ${errorData}\n\n`);
    }

    res.end();
  } catch (error) {
    console.error('Stream setup error:', error);
    if (!res.headersSent) {
      res.status(500).json({ 
        error: error.message || 'Failed to setup stream' 
      });
    } else {
      res.end();
    }
  }
});

// Generate embedding endpoint
router.post('/embedding', verifyToken, async (req, res) => {
  try {
    const { text } = req.body;
    
    if (!text) {
      return res.status(400).json({ error: 'Text is required' });
    }

    const embedding = await generateEmbedding(text);
    res.json({ 
      success: true,
      embedding 
    });
  } catch (error) {
    console.error('Embedding error:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to generate embedding' 
    });
  }
});

// Check if OpenAI is configured
router.get('/status', async (req, res) => {
  const isConfigured = process.env.OPENAI_API_KEY && 
                       process.env.OPENAI_API_KEY !== 'your-openai-api-key-here';
  
  res.json({ 
    configured: isConfigured,
    message: isConfigured ? 'OpenAI API is configured' : 'OpenAI API key not configured'
  });
});

module.exports = router;