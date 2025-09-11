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

// Execute function calls from the client - direct execution
router.post('/function', verifyToken, async (req, res) => {
  try {
    const { name, arguments: args } = req.body;
    const userId = req.user.uid;
    
    console.log(`[REALTIME-FUNCTION] Executing ${name} for user ${userId}`);
    
    // Import required models and services
    const { UserTask, Space, Entry, Collection } = require('../models');
    
    let result = {};
    
    switch (name) {
      case 'create_task':
        console.log(`[VOICE-TASK] Creating task from voice: "${args.title}"`);
        
        // Get or create default space
        const defaultSpace = await Space.findDefaultSpace(userId) || 
                             await Space.createDefaultSpace(userId);
        const spaceIds = defaultSpace ? [defaultSpace.id] : [];
        
        const taskData = {
          userId: userId,
          title: args.title || 'Untitled Task',
          description: args.description || '',
          priority: args.priority || 'medium',
          status: 'pending',
          source: 'voice',
          spaceIds: spaceIds,
          metadata: { 
            source: 'voice',
            createdAt: new Date()
          }
        };
        
        if (args.dueDate) {
          taskData.dueDate = new Date(args.dueDate);
        }
        
        const task = await UserTask.create(taskData);
        
        result = {
          success: true,
          task: task,
          message: `Task "${task.title}" created successfully`
        };
        break;
        
      case 'create_collection':
        console.log(`[VOICE-COLLECTION] Creating collection from voice: "${args.name}"`);
        
        // Check if collection already exists
        const existing = await Collection.findByName(userId, args.name);
        if (existing) {
          result = {
            success: false,
            message: `Collection "${args.name}" already exists`,
            collection: existing
          };
          break;
        }
        
        // Generate collection details with AI if available
        const { generateCollectionDetails } = require('../services/collectionInference');
        let details;
        try {
          details = await generateCollectionDetails(args.name, args.description);
        } catch (error) {
          console.log(`[VOICE-COLLECTION] AI generation failed, using defaults`);
          details = {
            name: args.name,
            description: args.description || `Collection for ${args.name}`,
            icon: '📝',
            color: '#6366f1',
            rules: {
              keywords: [args.name.toLowerCase()],
              patterns: [],
              description: `Entries related to ${args.name}`
            },
            entryFormat: null
          };
        }
        
        const collection = await Collection.create({
          userId: userId,
          name: details.name,
          description: details.description,
          icon: details.icon,
          color: details.color,
          rules: details.rules,
          entryFormat: details.entryFormat,
          metadata: { 
            source: 'voice',
            createdAt: new Date()
          }
        });
        
        result = {
          success: true,
          collection: collection,
          message: `Collection "${collection.name}" created successfully`
        };
        break;
        
      case 'extract_entries':
        console.log(`[VOICE-ENTRY] Creating entry from voice: "${args.content.substring(0, 50)}..."`);
        
        // Get or create default space
        const entrySpace = await Space.findDefaultSpace(userId) || 
                           await Space.createDefaultSpace(userId);
        const entrySpaceIds = entrySpace ? [entrySpace.id] : [];
        
        // Create the entry
        const entryData = {
          userId: userId,
          title: '',
          content: args.content,
          type: 'journal',
          spaceIds: entrySpaceIds,
          metadata: { 
            source: 'voice',
            extractedAt: new Date()
          }
        };
        
        const entry = await Entry.create(entryData);
        console.log(`[VOICE-ENTRY] Created entry ${entry.id}`);
        
        // Trigger inference independently
        console.log(`[VOICE-ENTRY] Triggering collection inference for entry ${entry.id}`);
        
        const serviceToken = await admin.auth().createCustomToken(userId, {
          service: 'voice-inference',
          entryId: entry.id
        });
        
        // Fire and forget the inference
        const https = require('https');
        const inferenceUrl = process.env.NODE_ENV === 'production' 
          ? 'https://squirrel2.vercel.app/api/entries/' 
          : 'http://localhost:3001/api/entries/';
        
        const url = new URL(`${inferenceUrl}${entry.id}/infer-collection`);
        const postData = JSON.stringify({});
        
        const options = {
          hostname: url.hostname,
          port: url.port,
          path: url.pathname,
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${serviceToken}`,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData)
          }
        };
        
        const inferenceReq = https.request(options, (inferenceRes) => {
          let data = '';
          inferenceRes.on('data', (chunk) => data += chunk);
          inferenceRes.on('end', () => {
            console.log(`[VOICE-ENTRY] Inference completed for entry ${entry.id}`);
          });
        });
        
        inferenceReq.on('error', (error) => {
          console.error(`[VOICE-ENTRY] Inference request error:`, error.message);
        });
        
        inferenceReq.write(postData);
        inferenceReq.end();
        
        result = {
          success: true,
          entryId: entry.id,
          message: `Entry saved successfully`
        };
        break;
        
      default:
        console.log(`[REALTIME-FUNCTION] Unknown function: ${name}`);
        result = {
          success: false,
          error: `Unknown function: ${name}`
        };
        break;
    }
    
    res.json(result);
  } catch (error) {
    console.error('[REALTIME-FUNCTION] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;