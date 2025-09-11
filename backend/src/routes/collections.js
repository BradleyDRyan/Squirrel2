const express = require('express');
const router = express.Router();
const { Collection, Entry } = require('../models');
const { verifyToken } = require('../middleware/auth');
const { flexibleAuth } = require('../middleware/serviceAuth');
const { formatDatesInObject } = require('../utils/dateUtils');
const { generateCollectionRules } = require('../services/collectionRules');
const { inferCollectionFromContent, generateCollectionDetails } = require('../services/collectionInference');

router.use(verifyToken);

// Get all collections for user
router.get('/', async (req, res) => {
  try {
    const collections = await Collection.findByUserId(req.user.uid);
    
    // Format dates to ISO8601
    const formattedCollections = collections.map(c => formatDatesInObject(c));
    
    res.json(formattedCollections);
  } catch (error) {
    console.error('[Collections GET /] Error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// Get a single collection by ID
router.get('/:id', async (req, res) => {
  try {
    const collection = await Collection.findById(req.params.id);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    res.json(collection);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get all entries in a collection
router.get('/:id/entries', async (req, res) => {
  try {
    const collection = await Collection.findById(req.params.id);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    const entries = await Entry.findByCollection(req.params.id);
    // Format dates to ISO8601
    const formattedEntries = entries.map(e => formatDatesInObject(e));
    res.json(formattedEntries);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create a new collection
router.post('/', async (req, res) => {
  try {
    const collection = await Collection.create({
      ...req.body,
      userId: req.user.uid
    });
    res.status(201).json(collection);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update a collection
router.put('/:id', async (req, res) => {
  try {
    const collection = await Collection.findById(req.params.id);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    Object.assign(collection, req.body);
    await collection.save();
    res.json(collection);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update collection stats
router.post('/:id/update-stats', async (req, res) => {
  try {
    const collection = await Collection.findById(req.params.id);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    const stats = await collection.updateStats();
    res.json({ stats });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Generate AI rules for a collection
router.post('/:id/generate-rules', async (req, res) => {
  try {
    const collection = await Collection.findById(req.params.id);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    // Generate rules based on collection name and description
    const rules = await generateCollectionRules(
      collection.name, 
      collection.description || req.body.description || ''
    );
    
    // Update the collection with the generated rules
    collection.rules = rules;
    if (rules.description && !collection.description) {
      collection.description = rules.description;
    }
    await collection.save();
    
    res.json({ 
      success: true,
      rules,
      collection: {
        id: collection.id,
        name: collection.name,
        description: collection.description
      }
    });
  } catch (error) {
    console.error('[Generate Rules] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Generate rules without updating collection (preview mode)
router.post('/generate-rules-preview', async (req, res) => {
  try {
    const { name, description } = req.body;
    
    if (!name) {
      return res.status(400).json({ error: 'Collection name is required' });
    }
    
    // Generate rules for preview
    const rules = await generateCollectionRules(name, description || '');
    
    res.json({ 
      success: true,
      rules,
      preview: true
    });
  } catch (error) {
    console.error('[Generate Rules Preview] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Infer collection from content (used when creating entries)
router.post('/infer-from-content', async (req, res) => {
  try {
    const { content } = req.body;
    
    if (!content) {
      return res.status(400).json({ error: 'Content is required' });
    }
    
    // Use AI to infer collection details from content
    const inference = await inferCollectionFromContent(content);
    
    if (!inference || !inference.shouldCreateCollection) {
      return res.json({ 
        shouldCreateCollection: false,
        inference: null
      });
    }
    
    res.json({ 
      shouldCreateCollection: true,
      inference
    });
  } catch (error) {
    console.error('[Infer Collection] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Generate comprehensive collection details (rules + format)
router.post('/generate-details', async (req, res) => {
  try {
    const { name, description, sampleContent } = req.body;
    
    if (!name) {
      return res.status(400).json({ error: 'Collection name is required' });
    }
    
    // Generate comprehensive details including entry format
    const details = await generateCollectionDetails(name, description || '', sampleContent || '');
    
    res.json({ 
      success: true,
      details
    });
  } catch (error) {
    console.error('[Generate Details] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Test inference endpoint (for debugging)
router.post('/test-inference', async (req, res) => {
  try {
    const { content } = req.body;
    
    if (!content) {
      return res.status(400).json({ error: 'Content is required' });
    }
    
    console.log(`[TEST-INFERENCE] Testing with content: "${content}"`);
    
    // Test the inference function directly
    const inference = await inferCollectionFromContent(content);
    
    console.log('[TEST-INFERENCE] Result:', JSON.stringify(inference, null, 2));
    
    res.json({ 
      success: true,
      content,
      inference,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('[TEST-INFERENCE] Error:', error);
    res.status(500).json({ 
      error: error.message,
      stack: error.stack
    });
  }
});

// Create collection from voice input - accepts both user and service tokens
router.post('/create-voice-collection', flexibleAuth, async (req, res) => {
  try {
    const { name, description } = req.body;
    
    if (!name) {
      return res.status(400).json({ error: 'Collection name is required' });
    }
    
    console.log(`[VOICE-COLLECTION] Creating collection from voice: "${name}"`);
    
    // Check if collection already exists
    const existing = await Collection.findByName(req.user.uid, name);
    if (existing) {
      console.log(`[VOICE-COLLECTION] Collection "${name}" already exists`);
      return res.json({
        success: false,
        message: `Collection "${name}" already exists`,
        collection: existing
      });
    }
    
    // Generate collection details with AI if available
    let details;
    try {
      details = await generateCollectionDetails(name, description);
    } catch (error) {
      console.log(`[VOICE-COLLECTION] AI generation failed, using defaults`);
      // Fallback to basic structure
      details = {
        name: name,
        description: description || `Collection for ${name}`,
        icon: '📝',
        color: '#6366f1',
        rules: {
          keywords: [name.toLowerCase()],
          patterns: [],
          description: `Entries related to ${name}`
        },
        entryFormat: null
      };
    }
    
    // Create the collection
    const collection = await Collection.create({
      userId: req.user.uid,
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
    
    console.log(`[VOICE-COLLECTION] Created collection ${collection.id}: "${collection.name}"`);
    
    res.status(201).json({
      success: true,
      collection: collection,
      message: `Collection "${collection.name}" created successfully`
    });
  } catch (error) {
    console.error('[VOICE-COLLECTION] Error creating collection:', error);
    res.status(500).json({ error: error.message });
  }
});

// Delete a collection (only if empty)
router.delete('/:id', async (req, res) => {
  try {
    const collection = await Collection.findById(req.params.id);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    await collection.delete();
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;