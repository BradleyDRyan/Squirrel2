const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');
const { Collection, Entry, Space, Conversation, Message, Photo, CollectionEntry } = require('../models');
const multer = require('multer');
const OpenAI = require('openai');
const { getStorage } = require('firebase-admin/storage');

// Configure multer for memory storage
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB limit
  }
});

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

router.use(verifyToken);

// Process and save a photo
router.post('/process', upload.single('photo'), async (req, res) => {
  try {
    console.log('📸 [Photos] ========== PHOTO PROCESSING START ==========');
    console.log('👤 [Photos] User ID:', req.user?.uid);
    const userId = req.user.uid;
    const { conversationId } = req.body; // Get existing conversation ID if provided
    
    if (conversationId) {
      console.log('💬 [Photos] Adding to existing conversation:', conversationId);
    } else {
      console.log('🆕 [Photos] Will create new conversation');
    }
    
    if (!req.file) {
      console.error('❌ [Photos] No file in request');
      return res.status(400).json({ error: 'No photo provided' });
    }
    
    console.log('📁 [Photos] File received:', req.file.mimetype);
    console.log('📏 [Photos] File size:', (req.file.size / 1024).toFixed(2), 'KB');
    
    // Upload to Firebase Storage
    console.log('☁️ [Photos] Starting Firebase Storage upload...');
    const storage = getStorage();
    const bucket = storage.bucket();
    const timestamp = Date.now();
    const fileName = `photos/${userId}/${timestamp}-${req.file.originalname || 'photo.jpg'}`;
    const file = bucket.file(fileName);
    
    console.log('📤 [Photos] Uploading to path:', fileName);
    console.log('🪣 [Photos] Bucket:', bucket.name);
    
    // Upload the file
    console.log('⏳ [Photos] Saving file to storage...');
    await file.save(req.file.buffer, {
      metadata: {
        contentType: req.file.mimetype,
        metadata: {
          userId: userId,
          uploadedAt: new Date().toISOString()
        }
      }
    });
    console.log('✅ [Photos] File saved to Firebase Storage');
    
    // Make the file publicly accessible
    console.log('🔓 [Photos] Making file publicly accessible...');
    await file.makePublic();
    
    // Get the public URL
    const publicUrl = `https://storage.googleapis.com/${bucket.name}/${fileName}`;
    console.log('✅ [Photos] Photo uploaded successfully!');
    console.log('🔗 [Photos] Public URL:', publicUrl);
    
    // Create Photo object in database
    console.log('📸 [Photos] Creating Photo object...');
    const photo = await Photo.create({
      userId: userId,
      urls: {
        original: publicUrl,
        // Thumbnails will be added later via background processing
        thumbnail: null,
        small: null,
        medium: null,
        large: null
      },
      storagePaths: {
        original: fileName,
        thumbnail: null,
        small: null,
        medium: null,
        large: null
      },
      mimeType: req.file.mimetype,
      originalSize: req.file.size,
      dimensions: {
        width: null, // Will be extracted during processing
        height: null
      },
      analysis: {
        description: '',  // Will be filled after AI analysis
        collectionName: '',
        suggestedTitle: '',
        tags: []
      },
      metadata: {
        source: 'camera',
        uploadedAt: new Date().toISOString()
      }
    });
    console.log('✅ [Photos] Photo object created with ID:', photo.id);
    
    // Convert image to base64 for OpenAI Vision API
    const base64Image = req.file.buffer.toString('base64');
    const imageUrl = `data:${req.file.mimetype};base64,${base64Image}`;
    
    // Use OpenAI Vision API to analyze the image
    console.log('🤖 [Photos] Starting AI analysis with GPT-4 Vision...');
    const visionResponse = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You are analyzing a photo. Provide a brief, natural description of what you see.
Respond in JSON format:
{
  "description": "brief description of what's in the photo",
  "suggestedTitle": "optional title for the entry"
}`
        },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: 'What is in this photo?'
            },
            {
              type: 'image_url',
              image_url: {
                url: imageUrl,
                detail: 'low'
              }
            }
          ]
        }
      ],
      max_tokens: 200,
      temperature: 0.3
    });
    
    console.log('✅ [Photos] Vision API responded');
    
    // Parse the response, handling markdown-wrapped JSON
    let content = visionResponse.choices[0].message.content;
    // Strip markdown code block if present
    if (content.includes('```json')) {
      content = content.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    }
    const analysis = JSON.parse(content);
    // Ensure all fields have values (no undefined)
    analysis.description = analysis.description || 'Photo';
    analysis.suggestedTitle = analysis.suggestedTitle || null;
    console.log('📊 [Photos] AI Analysis:');
    console.log('  📝 Description:', analysis.description);
    console.log('  🏷️ Suggested title:', analysis.suggestedTitle);
    
    // Update Photo with AI analysis
    photo.analysis = {
      description: analysis.description || '',
      collectionName: '', // Will be determined by inference
      suggestedTitle: analysis.suggestedTitle || null,
      tags: ['photo']
    };
    await photo.updateSizes({});  // This updates the analysis in the database
    console.log('✅ [Photos] Photo analysis saved');
    
    // Get or create default space
    const defaultSpace = await Space.findDefaultSpace(userId) || 
                         await Space.createDefaultSpace(userId);
    const spaceIds = defaultSpace ? [defaultSpace.id] : [];
    
    // First, create the Entry with photo description
    console.log('📝 [Photos] Creating entry with photo description...');
    const entry = await Entry.create({
      userId: userId,
      title: analysis.suggestedTitle || 'Photo',
      content: analysis.description,
      type: 'photo',
      tags: ['photo'],
      spaceIds: spaceIds,
      photoId: photo.id,  // Reference to Photo object
      imageUrl: publicUrl, // Keep for backward compatibility
      metadata: { 
        source: 'camera',
        hasImage: true,
        photoId: photo.id,
        storagePath: fileName,
        addedToExistingConversation: !!conversationId
      }
    });
    console.log('✅ [Photos] Entry created:', entry.id);
    
    // Now run the standard inference to determine collection
    console.log('🤔 [Photos] Running collection inference...');
    const { inferCollectionFromContent, generateCollectionDetails } = require('../services/collectionInference');
    
    // Get existing collections for this user
    const existingCollections = await Collection.findByUserId(userId);
    const collectionNames = existingCollections.map(c => c.name);
    const collectionInstructions = {};
    existingCollections.forEach(c => {
      collectionInstructions[c.name] = c.instructions || '';
    });
    
    console.log('🔍 [Photos] Available collections:', collectionNames.join(', ') || 'none');
    
    // Run inference on the photo description
    const inference = await inferCollectionFromContent(
      analysis.description,
      collectionNames,
      collectionInstructions
    );
    
    let targetCollection = null;
    
    if (inference && inference.shouldCreateCollection) {
      console.log(`📁 [Photos] Inference suggests collection: ${inference.collectionName}`);
      console.log(`🎯 [Photos] Confidence: ${inference.confidence || 'N/A'}, Reasoning: ${inference.reasoning || 'N/A'}`);
      
      // Check if collection exists
      targetCollection = await Collection.findByName(userId, inference.collectionName);
      
      if (!targetCollection) {
        console.log(`🆕 [Photos] Creating new collection: ${inference.collectionName}`);
        
        // Generate detailed collection structure
        const details = await generateCollectionDetails(
          inference.collectionName,
          inference.description,
          analysis.description
        );
        
        targetCollection = await Collection.create({
          userId: userId,
          name: details.name,
          instructions: details.instructions || `Add entries related to ${details.name}`,
          icon: Collection.getDefaultIcon(details.name),
          color: details.color || '#6366f1',
          entryFormat: inference.entryFormat,
          metadata: { 
            source: 'photo_inference',
            firstEntry: entry.id,
            inferredAt: new Date()
          }
        });
        
        console.log(`✅ [Photos] Created collection ${targetCollection.id}`);
      } else {
        console.log(`📁 [Photos] Using existing collection: ${targetCollection.name}`);
      }
      
      // Create CollectionEntry with formatted data
      if (inference.extractedData) {
        console.log('🔗 [Photos] Creating CollectionEntry junction record...');
        await CollectionEntry.create({
          userId: userId,
          collectionId: targetCollection.id,
          entryId: entry.id,
          formattedData: {
            ...inference.extractedData,
            imageUrl: publicUrl,
            photoId: photo.id,
            title: analysis.suggestedTitle || 'Photo',
            description: analysis.description
          },
          metadata: {
            source: 'photo_inference',
            inferredAt: new Date()
          }
        });
        console.log('✅ [Photos] CollectionEntry created');
      }
    } else {
      console.log('ℹ️ [Photos] No collection pattern detected, using default');
      // Find or create a default Photos collection
      targetCollection = await Collection.findOrCreateByName(userId, 'Photos', 'Your photo memories');
      
      // Create CollectionEntry
      console.log('🔗 [Photos] Creating CollectionEntry for default Photos collection...');
      await CollectionEntry.create({
        userId: userId,
        collectionId: targetCollection.id,
        entryId: entry.id,
        formattedData: {
          imageUrl: publicUrl,
          photoId: photo.id,
          title: analysis.suggestedTitle || 'Photo',
          description: analysis.description
        },
        metadata: {
          source: 'photo',
          autoProcessed: true
        }
      });
      console.log('✅ [Photos] CollectionEntry created for default collection');
    }
    
    let conversation;
    
    // Check if we should add to existing conversation or create new one
    if (conversationId) {
      // Add to existing conversation
      console.log('💬 [Photos] Loading existing conversation:', conversationId);
      conversation = await Conversation.findById(conversationId);
      if (!conversation || conversation.userId !== userId) {
        console.error('❌ [Photos] Invalid conversation ID or unauthorized');
        return res.status(403).json({ error: 'Invalid conversation' });
      }
      
      console.log('📝 [Photos] Updating conversation last message');
      // Update conversation's last message
      conversation.lastMessage = analysis.description;
      await conversation.save();
      console.log('✅ [Photos] Conversation updated');
    } else {
      // Create a new conversation for this photo
      console.log('🆕 [Photos] Creating new conversation');
      conversation = await Conversation.create({
        userId: userId,
        spaceIds: spaceIds,
        title: analysis.suggestedTitle || 'Photo',
        lastMessage: analysis.description,
        metadata: {
          collectionId: targetCollection.id,
          type: 'photo'
        }
      });
      console.log('✅ [Photos] Conversation created with ID:', conversation.id);
    }
    
    // Create user message with the photo
    console.log('💬 [Photos] Creating user message with photo...');
    const userMessage = await Message.create({
      conversationId: conversation.id,
      userId: userId,
      content: 'Photo captured',
      type: 'photo',
      photoId: photo.id,  // Reference to Photo object
      attachments: [publicUrl],  // Keep for backward compatibility
      metadata: {
        photoId: photo.id,
        imageUrl: publicUrl,
        storagePath: fileName
      }
    });
    console.log('✅ [Photos] User message created:', userMessage.id);
    
    // Create AI assistant message with the analysis
    console.log('🤖 [Photos] Creating assistant message with analysis...');
    const assistantMessage = await Message.create({
      conversationId: conversation.id,
      userId: 'assistant',
      content: analysis.description,
      type: 'text',
      metadata: {
        role: 'assistant',
        collectionName: targetCollection.name,
        suggestedTitle: analysis.suggestedTitle || null
      }
    });
    console.log('✅ [Photos] Assistant message created:', assistantMessage.id);
    
    // Update entry with conversation ID now that it exists
    entry.conversationId = conversation.id;
    await entry.save();
    console.log('✅ [Photos] Entry updated with conversation ID');
    
    if (conversationId) {
      console.log('ℹ️ [Photos] Photo added to existing conversation and created entry for Photos tab');
    }
    
    // Update collection stats
    console.log('📊 [Photos] Updating collection stats...');
    await targetCollection.updateStats();
    console.log('✅ [Photos] Collection stats updated');
    
    const responseData = {
      success: true,
      photoId: photo.id,  // Include Photo ID
      conversationId: conversation.id,
      entryId: entry.id,
      collectionId: targetCollection.id,
      collectionName: targetCollection.name,
      description: analysis.description,
      message: conversationId 
        ? `Photo added to conversation and Photos tab` 
        : `Photo saved to "${targetCollection.name}"`
    };
    
    console.log('🎉 [Photos] ========== PHOTO PROCESSING COMPLETE ==========');
    console.log('📊 [Photos] Summary:');
    console.log('  🆔 Photo ID:', photo.id);
    console.log('  📸 Photo URL:', publicUrl);
    console.log('  📁 Collection:', targetCollection.name);
    console.log('  💬 Conversation:', conversation.id);
    console.log('  📝 Entry:', entry.id);
    console.log('  📱 Shows in Photos tab: Yes');
    console.log('============================================');
    
    res.json(responseData);
    
  } catch (error) {
    console.error('❌ [Photos] ========== ERROR PROCESSING PHOTO ==========');
    console.error('❌ [Photos] Error:', error.message);
    console.error('❌ [Photos] Stack:', error.stack);
    console.error('============================================');
    
    // More specific error messages
    let errorMessage = 'Failed to process photo';
    let statusCode = 500;
    
    if (error.message?.includes('OpenAI')) {
      errorMessage = 'Failed to analyze image';
      console.error('❌ [Photos] OpenAI Vision API failed');
    } else if (error.message?.includes('Collection')) {
      errorMessage = 'Failed to create or find collection';
      console.error('❌ [Photos] Collection operation failed');
    } else if (error.message?.includes('Entry')) {
      errorMessage = 'Failed to save photo entry';
      console.error('❌ [Photos] Entry creation failed');
    } else if (error.message?.includes('Storage') || error.message?.includes('Firebase')) {
      errorMessage = 'Failed to upload photo to storage';
      console.error('❌ [Photos] Firebase Storage upload failed');
    }
    
    res.status(statusCode).json({ 
      error: errorMessage,
      details: error.message 
    });
  }
});

module.exports = router;