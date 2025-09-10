const express = require('express');
const router = express.Router();
const { verifyToken, optionalAuth } = require('../middleware/auth');
const crypto = require('crypto');
const admin = require('firebase-admin');

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
        instructions: 'You are a helpful assistant. Be concise and natural.',
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
        // Create task in Firebase
        const db = admin.firestore();
        const taskData = {
          title: args.title || 'Untitled Task',
          description: args.description || '',
          completed: false,
          userId: userId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          source: 'voice',
          priority: 'medium'
        };
        
        if (args.dueDate) {
          taskData.dueDate = new Date(args.dueDate);
        }
        
        const taskRef = await db.collection('tasks').add(taskData);
        result = {
          success: true,
          taskId: taskRef.id,
          message: `Task "${args.title}" created successfully`
        };
        break;
        
      case 'list_tasks':
        // List tasks from Firebase
        const tasksSnapshot = await admin.firestore()
          .collection('tasks')
          .where('userId', '==', userId)
          .where('completed', '==', false)
          .orderBy('createdAt', 'desc')
          .limit(10)
          .get();
          
        const tasks = tasksSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data()
        }));
        
        result = {
          success: true,
          tasks: tasks,
          count: tasks.length
        };
        break;
        
      case 'complete_task':
        // Mark task as completed
        if (args.taskId) {
          await admin.firestore()
            .collection('tasks')
            .doc(args.taskId)
            .update({
              completed: true,
              completedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            
          result = {
            success: true,
            message: 'Task marked as completed'
          };
        } else {
          result = {
            success: false,
            message: 'Task ID required'
          };
        }
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