const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');
const crypto = require('crypto');
const admin = require('firebase-admin');
const axios = require('axios');

// Store active sessions temporarily (in production, use Redis or similar)
const activeSessions = new Map();

// Export for use in websocket-server.js
module.exports.activeSessions = activeSessions;

// Generate a session token for the client
router.post('/session', verifyToken, async (req, res) => {
  try {
    if (!process.env.OPENAI_API_KEY || process.env.OPENAI_API_KEY === 'your-openai-api-key-here') {
      return res.status(500).json({ 
        error: 'OpenAI API key not configured on server' 
      });
    }

    // Generate a unique session token
    const sessionToken = crypto.randomBytes(32).toString('hex');
    const sessionId = crypto.randomBytes(16).toString('hex');
    
    // Store session info (expires after 1 hour)
    activeSessions.set(sessionToken, {
      userId: req.user.uid,
      sessionId,
      createdAt: Date.now(),
      apiKey: process.env.OPENAI_API_KEY
    });

    // Clean up expired sessions
    setTimeout(() => {
      activeSessions.delete(sessionToken);
    }, 3600000); // 1 hour

    res.json({ 
      success: true,
      sessionToken,
      sessionId,
      expiresIn: 3600 // seconds
    });
  } catch (error) {
    console.error('Session creation error:', error);
    res.status(500).json({ 
      error: 'Failed to create session' 
    });
  }
});

// Create ephemeral token for WebRTC connection
router.post('/token', verifyToken, async (req, res) => {
  try {
    if (!process.env.OPENAI_API_KEY || process.env.OPENAI_API_KEY === 'your-openai-api-key-here') {
      return res.status(500).json({ 
        error: 'OpenAI API key not configured on server' 
      });
    }

    // Create an ephemeral token using OpenAI's REST API
    const response = await axios.post('https://api.openai.com/v1/realtime/sessions', {
        model: 'gpt-realtime',
        voice: 'shimmer',
        instructions: `You are a helpful assistant. Be concise and natural.
        
When the user shares something entry-worthy (like ratings, reviews, notes, observations, ideas), use extract_entries to capture it.

Don't worry about which collection it belongs to - just extract any meaningful content the user shares. The system will automatically sort it into the right collection.

Examples of entry-worthy content:
- "Boy Smells Ash candle is 8/10"
- "Just watched Dune 2, amazing cinematography"
- "Recipe: Mix flour, eggs, milk for pancakes"
- "Idea: app that tracks mood with weather"
- "The movie F1 with Brad Pitt: 7 out of 10"
- "Life advice: get sun in the morning"

For tasks and todos, use create_task.

Only use create_collection when explicitly asked.`,
        input_audio_transcription: {
          model: 'whisper-1'
        },
        turn_detection: {
          type: 'server_vad',
          threshold: 0.5,
          prefix_padding_ms: 300,
          silence_duration_ms: 500
        },
        tools: [
          {
            type: 'function',
            name: 'create_task',
            description: 'Create a new task or reminder',
            parameters: {
              type: 'object',
              properties: {
                title: {
                  type: 'string',
                  description: 'The task title'
                },
                description: {
                  type: 'string',
                  description: 'Optional task description'
                },
                dueDate: {
                  type: 'string',
                  description: 'Optional due date in ISO format'
                }
              },
              required: ['title']
            }
          },
          {
            type: 'function',
            name: 'create_collection',
            description: 'Create a new collection for organizing entries',
            parameters: {
              type: 'object',
              properties: {
                name: {
                  type: 'string',
                  description: 'The name of the collection'
                },
                description: {
                  type: 'string',
                  description: 'Optional description of what belongs in this collection'
                }
              },
              required: ['name']
            }
          },
          {
            type: 'function',
            name: 'extract_entries',
            description: 'Extract and save any entry-worthy content the user shares',
            parameters: {
              type: 'object',
              properties: {
                content: {
                  type: 'string',
                  description: 'The exact content to save as the user said it'
                }
              },
              required: ['content']
            }
          }
        ]
      }, {
        headers: {
          'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
          'Content-Type': 'application/json'
        }
      });
    
    const data = response.data;
    
    res.json({ 
      success: true,
      token: data.client_secret.value,
      expires_at: data.client_secret.expires_at,
      session_id: data.id,
      model: data.model
    });
  } catch (error) {
    console.error('Token creation error:', error);
    console.error('Error response:', error.response?.data);
    
    const errorMessage = error.response?.data?.error?.message || 
                        error.response?.data?.error || 
                        error.message || 
                        'Failed to create ephemeral token';
    
    res.status(500).json({ 
      error: errorMessage,
      details: error.response?.data
    });
  }
});

// Execute function calls from the client - properly route to dedicated endpoints
router.post('/function', verifyToken, async (req, res) => {
  try {
    const { name, arguments: args } = req.body;
    const userId = req.user.uid;
    
    console.log(`[REALTIME-FUNCTION] Executing ${name} for user ${userId}`);
    
    // Map function names to API endpoints
    const functionEndpoints = {
      'create_task': '/api/tasks/create-voice-task',
      'create_collection': '/api/collections/create-voice-collection',
      'extract_entries': '/api/entries/extract-voice-entry'
    };
    
    const endpoint = functionEndpoints[name];
    
    if (!endpoint) {
      console.log(`[REALTIME-FUNCTION] Unknown function: ${name}`);
      return res.status(400).json({ 
        error: `Unknown function: ${name}` 
      });
    }
    
    // Build the API URL
    const apiUrl = process.env.NODE_ENV === 'production' 
      ? `https://squirrel2.vercel.app${endpoint}`
      : `http://localhost:3001${endpoint}`;
    
    console.log(`[REALTIME-FUNCTION] Forwarding to ${apiUrl}`);
    
    // Prepare request body based on function type
    let body = {};
    switch (name) {
      case 'create_task':
        body = {
          title: args.title,
          description: args.description,
          priority: args.priority,
          dueDate: args.dueDate
        };
        break;
      case 'create_collection':
        body = {
          name: args.name,
          description: args.description
        };
        break;
      case 'extract_entries':
        body = {
          content: args.content
        };
        break;
    }
    
    // Get the user's Firebase token from the request
    const token = req.headers.authorization?.split(' ')[1];
    
    // Make the API call using the user's token
    try {
      const response = await axios.post(apiUrl, body, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      
      console.log(`[REALTIME-FUNCTION] ${name} completed successfully`);
      res.json(response.data);
    } catch (apiError) {
      console.error(`[REALTIME-FUNCTION] API call failed:`, apiError.message);
      if (apiError.response) {
        console.error(`[REALTIME-FUNCTION] Response status:`, apiError.response.status);
        console.error(`[REALTIME-FUNCTION] Response data:`, apiError.response.data);
      }
      
      // Return appropriate error to client
      res.status(apiError.response?.status || 500).json({
        success: false,
        error: apiError.response?.data?.error || apiError.message
      });
    }
  } catch (error) {
    console.error('[REALTIME-FUNCTION] Error:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

module.exports = router;