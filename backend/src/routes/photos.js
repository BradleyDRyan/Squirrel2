const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');
const { Collection, Entry, Space } = require('../models');
const multer = require('multer');
const OpenAI = require('openai');

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
    const userId = req.user.uid;
    
    if (!req.file) {
      return res.status(400).json({ error: 'No photo provided' });
    }
    
    // Convert image to base64
    const base64Image = req.file.buffer.toString('base64');
    const imageUrl = `data:${req.file.mimetype};base64,${base64Image}`;
    
    // Get user's collections for context
    const collections = await Collection.findByUserId(userId);
    const collectionNames = collections.map(c => c.name).join(', ') || 'no collections yet';
    
    // Use OpenAI Vision API to analyze the image
    const visionResponse = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You are analyzing a photo to determine:
1. What the photo contains (brief description)
2. Which collection it should be saved to

Available collections: ${collectionNames}

If none of the existing collections fit well, suggest creating a new collection with an appropriate name.

Respond in JSON format:
{
  "description": "brief description of what's in the photo",
  "collectionName": "name of collection to save to",
  "createNewCollection": true/false,
  "suggestedTitle": "optional title for the entry"
}`
        },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: 'What is in this photo and which collection should it go to?'
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
    
    const analysis = JSON.parse(visionResponse.choices[0].message.content);
    
    // Find or create the collection
    let targetCollection;
    if (analysis.createNewCollection || !collections.find(c => c.name === analysis.collectionName)) {
      // Create new collection if needed
      targetCollection = await Collection.findOrCreateByName(userId, analysis.collectionName);
    } else {
      targetCollection = collections.find(c => c.name === analysis.collectionName);
    }
    
    // Get or create default space
    const defaultSpace = await Space.findDefaultSpace(userId) || 
                         await Space.createDefaultSpace(userId);
    const spaceIds = defaultSpace ? [defaultSpace.id] : [];
    
    // Create the entry with the photo description
    const entry = await Entry.create({
      userId: userId,
      collectionId: targetCollection.id,
      title: analysis.suggestedTitle || 'Photo',
      content: analysis.description,
      type: 'photo',
      tags: ['photo'],
      spaceIds: spaceIds,
      metadata: { 
        source: 'camera',
        hasImage: true,
        imageData: imageUrl // Store the image data (in production, use proper storage like S3)
      }
    });
    
    // Update collection stats
    await targetCollection.updateStats();
    
    res.json({
      success: true,
      entryId: entry.id,
      collectionId: targetCollection.id,
      collectionName: targetCollection.name,
      description: analysis.description,
      message: `Photo saved to "${targetCollection.name}"`
    });
    
  } catch (error) {
    console.error('[Photos] Error processing photo:', error);
    res.status(500).json({ 
      error: 'Failed to process photo',
      details: error.message 
    });
  }
});

module.exports = router;