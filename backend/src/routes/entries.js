const express = require('express');
const router = express.Router();
const { Entry, Collection, CollectionEntry } = require('../models');
const { verifyToken } = require('../middleware/auth');
const { inferCollectionFromContent, generateCollectionDetails } = require('../services/collectionInference');

router.use(verifyToken);

router.get('/', async (req, res) => {
  try {
    const filters = {
      collectionId: req.query.collectionId,
      type: req.query.type,
      mood: req.query.mood,
      conversationId: req.query.conversationId,
      startDate: req.query.startDate ? new Date(req.query.startDate) : undefined,
      endDate: req.query.endDate ? new Date(req.query.endDate) : undefined
    };
    
    const entries = await Entry.findByUserId(req.user.uid, filters);
    res.json(entries);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/search', async (req, res) => {
  try {
    const { q } = req.query;
    if (!q) {
      return res.status(400).json({ error: 'Search query required' });
    }
    
    const entries = await Entry.searchContent(req.user.uid, q);
    res.json(entries);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/tags', async (req, res) => {
  try {
    const { tags } = req.query;
    if (!tags) {
      return res.status(400).json({ error: 'Tags required' });
    }
    
    const tagArray = Array.isArray(tags) ? tags : tags.split(',');
    const entries = await Entry.findByTags(req.user.uid, tagArray);
    res.json(entries);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const entry = await Entry.findById(req.params.id);
    if (!entry || entry.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Entry not found' });
    }
    res.json(entry);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const { Space } = require('../models');
    let spaceIds = req.body.spaceIds || [];
    
    if (spaceIds.length === 0) {
      const defaultSpace = await Space.findDefaultSpace(req.user.uid) || 
                           await Space.createDefaultSpace(req.user.uid);
      spaceIds = [defaultSpace.id];
    }
    
    const entry = await Entry.create({
      ...req.body,
      spaceIds,
      userId: req.user.uid
    });
    res.status(201).json(entry);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create entry with automatic collection inference
router.post('/with-inference', async (req, res) => {
  try {
    const { Space } = require('../models');
    const { content, enableInference = true, ...entryData } = req.body;
    
    let spaceIds = entryData.spaceIds || [];
    if (spaceIds.length === 0) {
      const defaultSpace = await Space.findDefaultSpace(req.user.uid) || 
                           await Space.createDefaultSpace(req.user.uid);
      spaceIds = [defaultSpace.id];
    }
    
    // Create the base entry first
    const entry = await Entry.create({
      ...entryData,
      content,
      spaceIds,
      userId: req.user.uid
    });
    
    let collectionCreated = null;
    let collectionEntry = null;
    
    // Try to infer collection if enabled
    if (enableInference && content) {
      try {
        const inference = await inferCollectionFromContent(content);
        
        if (inference && inference.shouldCreateCollection) {
          // Check if collection already exists
          let collection = await Collection.findByName(req.user.uid, inference.collectionName);
          
          if (!collection) {
            // Create new collection with AI-generated details
            const details = await generateCollectionDetails(
              inference.collectionName,
              inference.description,
              content
            );
            
            collection = await Collection.create({
              userId: req.user.uid,
              name: details.name,
              description: details.description,
              icon: details.icon || '📝',
              color: details.color || '#6366f1',
              rules: details.rules,
              entryFormat: details.entryFormat,
              metadata: { 
                source: 'auto_inference',
                firstEntry: entry.id
              }
            });
            
            collectionCreated = collection;
          }
          
          // Create CollectionEntry with formatted data
          if (collection && inference.extractedData) {
            collectionEntry = await CollectionEntry.create({
              userId: req.user.uid,
              collectionId: collection.id,
              entryId: entry.id,
              formattedData: inference.extractedData,
              metadata: {
                source: 'auto_inference',
                inferredAt: new Date()
              }
            });
          }
        }
      } catch (inferenceError) {
        console.error('Collection inference failed:', inferenceError);
        // Continue without inference - entry is already created
      }
    }
    
    res.status(201).json({
      entry,
      collectionCreated,
      collectionEntry,
      inference: collectionCreated ? {
        collectionName: collectionCreated.name,
        collectionId: collectionCreated.id,
        wasNewCollection: true
      } : null
    });
  } catch (error) {
    console.error('[Create Entry with Inference] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const entry = await Entry.findById(req.params.id);
    if (!entry || entry.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Entry not found' });
    }
    
    Object.assign(entry, req.body);
    await entry.save();
    res.json(entry);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const entry = await Entry.findById(req.params.id);
    if (!entry || entry.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Entry not found' });
    }
    
    await entry.delete();
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;