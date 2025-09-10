const express = require('express');
const router = express.Router();
const { verifyToken, optionalAuth } = require('../middleware/auth');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { UserTask, Space, Entry, Collection } = require('../models');

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
    const response = await fetch('https://api.openai.com/v1/realtime/sessions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: 'gpt-4o-realtime-preview-2024-12-17',
        voice: 'shimmer',
        instructions: 'You are a helpful assistant. Be concise and natural. When users mention things they want to remember or journal about, use create_entry to save them to appropriate collections. For tasks and todos, use create_task. For journal entries, notes, and things to remember, use create_entry with a suitable collection name.',
        input_audio_transcription: {
          model: 'whisper-1'
        },
        turn_detection: {
          type: 'server_vad',
          threshold: 0.5,
          prefix_padding_ms: 300,
          silence_duration_ms: 500
        },
        // Tools are defined but OpenAI will call them through the WebRTC data channel
        // The iOS client needs to intercept function calls and send them to our backend
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
            name: 'create_entry',
            description: 'Create a journal entry or note in a collection',
            parameters: {
              type: 'object',
              properties: {
                content: {
                  type: 'string',
                  description: 'The content of the entry'
                },
                collectionName: {
                  type: 'string',
                  description: 'The name of the collection to add this entry to (e.g., "Baking", "Travel", "Ideas")'
                },
                title: {
                  type: 'string',
                  description: 'Optional title for the entry'
                },
                tags: {
                  type: 'array',
                  items: { type: 'string' },
                  description: 'Optional tags for the entry'
                }
              },
              required: ['content', 'collectionName']
            }
          }
        ]
      })
    });

    if (!response.ok) {
      const error = await response.text();
      console.error('OpenAI API error:', error);
      return res.status(response.status).json({ 
        error: 'Failed to create session' 
      });
    }

    const data = await response.json();
    
    res.json({ 
      success: true,
      token: data.client_secret.value,
      expires_at: data.client_secret.expires_at,
      session_id: data.id,
      model: data.model
    });
  } catch (error) {
    console.error('Token creation error:', error);
    res.status(500).json({ 
      error: 'Failed to create ephemeral token' 
    });
  }
});

// Execute function calls from the client
router.post('/function', verifyToken, async (req, res) => {
  try {
    const { name, arguments: args } = req.body;
    const userId = req.user.uid;
    
    console.log(`Executing function ${name} for user ${userId}`, args);
    
    let result = {};
    
    switch (name) {
      case 'create_task':
        // Get or create default space (same as tasks.js route)
        let spaceIds = [];
        
        const defaultSpace = await Space.findDefaultSpace(userId) || 
                             await Space.createDefaultSpace(userId);
        if (defaultSpace) {
          spaceIds = [defaultSpace.id];
        }
        
        // Create task using UserTask model
        const taskData = {
          userId: userId,  // Include userId in the data object
          title: args.title || 'Untitled Task',
          description: args.description || '',
          priority: args.priority || 'medium',
          status: 'pending',
          source: 'voice',
          spaceIds: spaceIds,  // Use the default space
          conversationId: null,  // Can be added if you track voice conversation IDs
          metadata: { source: 'voice' }
        };
        
        if (args.dueDate) {
          taskData.dueDate = args.dueDate;
        }
        
        const task = await UserTask.create(taskData);
        result = {
          success: true,
          taskId: task.id,
          message: `Task "${args.title}" created successfully`
        };
        console.log(`Created task ${task.id} for user ${userId} with spaceIds: ${spaceIds}`);
        break;
        
      case 'list_tasks':
        // List tasks using UserTask model
        const tasks = await UserTask.findPending(userId);
        
        result = {
          success: true,
          tasks: tasks.slice(0, 10), // Limit to 10 most recent
          count: tasks.length
        };
        break;
        
      case 'complete_task':
        // Mark task as completed using UserTask model
        if (args.taskId) {
          const taskToComplete = await UserTask.findById(args.taskId);
          
          if (taskToComplete && taskToComplete.userId === userId) {
            await taskToComplete.markComplete();
            result = {
              success: true,
              message: 'Task marked as completed'
            };
          } else {
            result = {
              success: false,
              message: 'Task not found or unauthorized'
            };
          }
        } else {
          result = {
            success: false,
            message: 'Task ID required'
          };
        }
        break;
        
      case 'create_entry':
        // Create an entry in a collection
        const collectionName = args.collectionName;
        const entryContent = args.content;
        
        if (!collectionName || !entryContent) {
          result = {
            success: false,
            message: 'Collection name and content are required'
          };
          break;
        }
        
        // Find or create the collection
        const collection = await Collection.findOrCreateByName(userId, collectionName);
        
        // Get or create default space
        const entryDefaultSpace = await Space.findDefaultSpace(userId) || 
                                  await Space.createDefaultSpace(userId);
        const entrySpaceIds = entryDefaultSpace ? [entryDefaultSpace.id] : [];
        
        // Create the entry
        const entryData = {
          userId: userId,
          collectionId: collection.id,
          title: args.title || '',
          content: entryContent,
          type: 'journal',
          tags: args.tags || [],
          spaceIds: entrySpaceIds,
          metadata: { 
            source: 'voice',
            collectionName: collectionName
          }
        };
        
        const entry = await Entry.create(entryData);
        
        // Update collection stats
        await collection.updateStats();
        
        result = {
          success: true,
          entryId: entry.id,
          collectionId: collection.id,
          collectionName: collection.name,
          message: `Entry created in "${collection.name}" collection`
        };
        console.log(`Created entry ${entry.id} in collection "${collection.name}" for user ${userId}`);
        break;
        
      default:
        result = {
          success: false,
          message: `Unknown function: ${name}`
        };
    }
    
    res.json(result);
    
  } catch (error) {
    console.error('Function execution error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to execute function' 
    });
  }
});

// Check if OpenAI Realtime is configured
router.get('/status', async (req, res) => {
  const isConfigured = process.env.OPENAI_API_KEY && 
                       process.env.OPENAI_API_KEY !== 'your-openai-api-key-here';
  
  res.json({ 
    configured: isConfigured,
    message: isConfigured ? 'OpenAI Realtime API is configured' : 'OpenAI API key not configured'
  });
});

module.exports = router;