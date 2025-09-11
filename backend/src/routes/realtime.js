const express = require('express');
const router = express.Router();
const { verifyToken, optionalAuth } = require('../middleware/auth');
const crypto = require('crypto');
const admin = require('firebase-admin');
const axios = require('axios');
const { UserTask, Space, Entry, Collection, CollectionEntry } = require('../models');
const { inferCollectionFromContent, generateCollectionDetails } = require('../services/collectionInference');

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

    // Fetch user's collections to include in instructions
    const userId = req.user.uid;
    const collections = await Collection.findByUserId(userId);
    const collectionNames = collections.map(c => c.name).join(', ') || 'no collections yet';

    // Create an ephemeral token using OpenAI's REST API
    const response = await axios.post('https://api.openai.com/v1/realtime/sessions', {
        model: 'gpt-realtime',
        voice: 'shimmer',
        instructions: `You are a helpful assistant. Be concise and natural.
        
The user has these collections: ${collectionNames}

When the user shares something meaningful that fits their collections, use save_entry.

When users want to create a collection, use create_collection.

For tasks and todos, use create_task.`,
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
            name: 'save_entry',
            description: 'Save meaningful content to a collection',
            parameters: {
              type: 'object',
              properties: {
                content: {
                  type: 'string',
                  description: 'The content to save'
                },
                collectionName: {
                  type: 'string',
                  description: 'The collection to save to'
                }
              },
              required: ['content', 'collectionName']
            }
          },
          {
            type: 'function',
            name: 'create_entry',
            description: 'Explicitly create an entry when the user asks to save something specific',
            parameters: {
              type: 'object',
              properties: {
                content: {
                  type: 'string',
                  description: 'The content of the entry'
                },
                collectionName: {
                  type: 'string',
                  description: 'The name of the collection to add this entry to'
                }
              },
              required: ['content', 'collectionName']
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
    console.error('Error status:', error.response?.status);
    
    // More detailed error response
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

// Execute function calls from the client
router.post('/function', verifyToken, async (req, res) => {
  try {
    const { name, arguments: args } = req.body;
    const userId = req.user.uid;
    
    
    let result = {};
    
    try {
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
        
      case 'create_collection':
        // Create a new collection - simplified without AI-generated rules
        const collectionNameToCreate = args.name;
        const collectionDescription = args.description || '';
        
        if (!collectionNameToCreate) {
          result = {
            success: false,
            message: 'Collection name is required'
          };
          break;
        }
        
        // Check if collection already exists
        const existingCollection = await Collection.findByName(userId, collectionNameToCreate);
        if (existingCollection) {
          result = {
            success: false,
            message: `Collection "${collectionNameToCreate}" already exists`,
            collectionId: existingCollection.id
          };
          break;
        }
        
        // Create the collection without AI rules - just the basics
        const newCollection = await Collection.create({
          userId: userId,
          name: collectionNameToCreate,
          description: collectionDescription || '',
          icon: Collection.getDefaultIcon(collectionNameToCreate),
          metadata: { source: 'voice' }
        });
        
        // Simple response - just the collection name
        result = {
          success: true,
          collection: newCollection.name
        };
        break;
        
      case 'save_entry':
        // Enhanced save with AI inference for the "hard path"
        if (!args.content) {
          result = {
            success: false,
            message: 'Content is required'
          };
          break;
        }
        
        let targetCollection = null;
        let formattedData = { content: args.content };
        let wasInferred = false;
        
        // Easy path: collection name provided explicitly
        if (args.collectionName) {
          targetCollection = await Collection.findOrCreateByName(userId, args.collectionName);
        } else {
          // Hard path: Try to infer collection from content
          console.log(`[INFERENCE] Attempting to infer collection from: "${args.content}"`);
          
          try {
            const inference = await inferCollectionFromContent(args.content);
            
            if (inference && inference.shouldCreateCollection) {
              console.log(`[INFERENCE] AI suggests creating collection: "${inference.collectionName}"`);
              
              // Check if collection already exists
              targetCollection = await Collection.findByName(userId, inference.collectionName);
              
              if (!targetCollection) {
                // Create new collection with AI-generated details
                const details = await generateCollectionDetails(
                  inference.collectionName,
                  inference.description,
                  args.content
                );
                
                targetCollection = await Collection.create({
                  userId: userId,
                  name: details.name,
                  description: details.description,
                  icon: details.icon || '📝',
                  color: details.color || '#6366f1',
                  rules: details.rules,
                  entryFormat: details.entryFormat,
                  metadata: { 
                    source: 'voice_inference',
                    firstEntry: args.content
                  }
                });
                
                console.log(`[INFERENCE] Created new collection: "${targetCollection.name}" with entry format`);
                wasInferred = true;
              }
              
              // Use extracted data if available
              if (inference.extractedData) {
                formattedData = inference.extractedData;
                console.log(`[INFERENCE] Using extracted data:`, formattedData);
              }
            }
          } catch (inferenceError) {
            console.error('[INFERENCE] Error:', inferenceError);
            // Fall back to default collection
          }
        }
        
        // If still no collection, use or create a default one
        if (!targetCollection) {
          targetCollection = await Collection.findOrCreateByName(userId, 'General Notes', 'General notes and thoughts');
        }
        
        // Get or create default space
        const saveEntrySpace = await Space.findDefaultSpace(userId) || 
                               await Space.createDefaultSpace(userId);
        const saveEntrySpaceIds = saveEntrySpace ? [saveEntrySpace.id] : [];
        
        // Create the raw entry (no collectionIds anymore)
        const savedEntry = await Entry.create({
          userId: userId,
          title: '',
          content: args.content,
          type: 'journal',
          tags: [],
          spaceIds: saveEntrySpaceIds,
          metadata: { 
            source: 'voice',
            wasInferred: wasInferred
          }
        });
        
        // Create CollectionEntry to link entry to collection
        const collectionEntry = await CollectionEntry.create({
          entryId: savedEntry.id,
          collectionId: targetCollection.id,
          userId: userId,
          formattedData: formattedData,
          metadata: {
            source: 'voice',
            wasInferred: wasInferred
          }
        });
        
        // Update collection stats
        await targetCollection.updateStats();
        
        result = {
          success: true,
          entryId: savedEntry.id,
          collectionEntryId: collectionEntry.id,
          collectionId: targetCollection.id,
          collectionName: targetCollection.name,
          message: wasInferred 
            ? `Created "${targetCollection.name}" collection and saved entry` 
            : `Saved to "${targetCollection.name}"`,
          wasInferred: wasInferred
        };
        break;
        
      case 'create_entry':
        // Explicit save - user specifically asked to save something
        let entryContent = args.content;
        let entryTargetCollection = null;
        
        if (!entryContent) {
          result = {
            success: false,
            message: 'Content is required'
          };
          break;
        }
        
        // First, check if content matches an existing collection's rules
        // This handles patterns like "words to live by: choose optimism"
        const matchResult = await Collection.findBestMatch(userId, entryContent);
        
        if (matchResult && matchResult.confidence > 0.3) {
          // Found a matching collection
          entryTargetCollection = matchResult.collection;
          entryContent = matchResult.content; // Use cleaned content (e.g., without "collection_name:" prefix)
        } else if (args.collectionName) {
          // If no match but collection name explicitly provided, find or create it
          entryTargetCollection = await Collection.findOrCreateByName(userId, args.collectionName);
        } else {
          // No collection specified and no match found - create a general collection or reject
          result = {
            success: false,
            message: 'Could not determine which collection to save this entry to. Please specify a collection or create one first.'
          };
          break;
        }
        
        // Get or create default space
        const entryDefaultSpace = await Space.findDefaultSpace(userId) || 
                                  await Space.createDefaultSpace(userId);
        const entrySpaceIds = entryDefaultSpace ? [entryDefaultSpace.id] : [];
        
        // Create the raw entry (no collectionIds)
        const entryData = {
          userId: userId,
          title: args.title || '',
          content: entryContent,
          type: 'journal',
          tags: args.tags || [],
          spaceIds: entrySpaceIds,
          metadata: { 
            source: 'voice',
            collectionName: entryTargetCollection.name,
            matchConfidence: matchResult ? matchResult.confidence : 1.0
          }
        };
        
        const entry = await Entry.create(entryData);
        
        // Create CollectionEntry to link entry to collection
        const newCollectionEntry = await CollectionEntry.create({
          entryId: entry.id,
          collectionId: entryTargetCollection.id,
          userId: userId,
          formattedData: {
            // For now, just store the raw content
            // Later, AI extraction can format this based on collection.entryFormat
            content: entryContent
          },
          metadata: {
            source: 'voice',
            wasMatched: !!matchResult,
            matchConfidence: matchResult ? matchResult.confidence : 1.0
          }
        });
        
        // Update collection stats
        await entryTargetCollection.updateStats();
        
        result = {
          success: true,
          entryId: entry.id,
          collectionEntryId: newCollectionEntry.id,
          collectionId: entryTargetCollection.id,
          collectionName: entryTargetCollection.name,
          message: `Entry saved to "${entryTargetCollection.name}" collection`,
          wasMatched: !!matchResult
        };
        console.log(`Created entry ${entry.id} with CollectionEntry ${newCollectionEntry.id} in collection "${entryTargetCollection.name}" for user ${userId}`);
        break;
        
      default:
        result = {
          success: false,
          message: `Unknown function: ${name}`
        };
      }
    } catch (functionError) {
      console.error(`[FUNCTION ERROR] Error in ${name}:`, functionError);
      console.error('Stack trace:', functionError.stack);
      result = {
        success: false,
        error: functionError.message,
        details: functionError.toString()
      };
    }
    
    console.log(`[FUNCTION RESULT] ${name}:`, JSON.stringify(result, null, 2));
    res.json(result);
    
  } catch (error) {
    console.error('[FUNCTION] Top-level error:', error);
    console.error('Stack trace:', error.stack);
    res.status(500).json({ 
      success: false,
      error: 'Failed to execute function',
      message: error.message
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