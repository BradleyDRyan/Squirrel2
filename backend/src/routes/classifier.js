const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');
const { Collection, Entry, Space } = require('../models');
const { classifyAndRoute } = require('../services/entryClassifier');

router.use(verifyToken);

// Classify and save content if appropriate
router.post('/classify', async (req, res) => {
  try {
    const { content } = req.body;
    const userId = req.user.uid;
    
    if (!content) {
      return res.status(400).json({ error: 'Content is required' });
    }
    
    // Do heavy classification and routing
    const classification = await classifyAndRoute(userId, content);
    
    if (!classification.shouldSave || !classification.collectionId) {
      // Content not worth saving
      return res.json({
        saved: false,
        reasoning: classification.reasoning
      });
    }
    
    // Get or create default space for the entry
    const defaultSpace = await Space.findDefaultSpace(userId) || 
                         await Space.createDefaultSpace(userId);
    const spaceIds = defaultSpace ? [defaultSpace.id] : [];
    
    // Create the entry
    const entry = await Entry.create({
      userId: userId,
      collectionId: classification.collectionId,
      title: '',
      content: content,
      type: 'journal',
      tags: [],
      spaceIds: spaceIds,
      metadata: { 
        source: 'voice',
        autoSaved: true,
        confidence: classification.confidence
      }
    });
    
    // Update collection stats
    const collection = await Collection.findById(classification.collectionId);
    if (collection) {
      await collection.updateStats();
    }
    
    res.json({
      saved: true,
      entryId: entry.id,
      collectionId: classification.collectionId,
      collectionName: collection?.name,
      confidence: classification.confidence
    });
    
  } catch (error) {
    console.error('[Classifier] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;