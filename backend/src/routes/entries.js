const express = require('express');
const router = express.Router();
const { Entry, Collection, CollectionEntry } = require('../models');
const { verifyToken } = require('../middleware/auth');
const { flexibleAuth } = require('../middleware/serviceAuth');
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

// Create entry from voice input (extract_entries) - accepts both user and service tokens
router.post('/extract-voice-entry', flexibleAuth, async (req, res) => {
  try {
    const { content } = req.body;
    
    if (!content) {
      return res.status(400).json({ error: 'Content is required' });
    }
    
    console.log(`[VOICE-ENTRY] Creating entry from voice: "${content.substring(0, 50)}..."`);
    
    // Get or create default space
    const { Space } = require('../models');
    const defaultSpace = await Space.findDefaultSpace(req.user.uid) || 
                         await Space.createDefaultSpace(req.user.uid);
    const spaceIds = defaultSpace ? [defaultSpace.id] : [];
    
    // Create the entry
    const entryData = {
      userId: req.user.uid,
      title: '',
      content: content,
      type: 'journal',
      spaceIds: spaceIds,
      metadata: { 
        source: 'voice',
        extractedAt: new Date()
      }
    };
    
    const entry = await Entry.create(entryData);
    console.log(`[VOICE-ENTRY] Created entry ${entry.id}`);
    
    // Trigger inference independently using internal service auth
    console.log(`[VOICE-ENTRY] Triggering collection inference for entry ${entry.id}`);
    
    // Generate service secret if not set
    if (!process.env.INTERNAL_SERVICE_SECRET) {
      const crypto = require('crypto');
      process.env.INTERNAL_SERVICE_SECRET = crypto.randomBytes(32).toString('hex');
    }
    
    // Fire and forget the inference using service authentication
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
        'Authorization': `Bearer ${process.env.INTERNAL_SERVICE_SECRET}`,
        'X-User-Id': req.user.uid,  // Pass user ID in header for service auth
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
    
    res.status(201).json({
      success: true,
      entryId: entry.id,
      message: `Entry saved successfully`
    });
  } catch (error) {
    console.error('[VOICE-ENTRY] Error creating entry:', error);
    res.status(500).json({ error: error.message });
  }
});

// Trigger inference for an existing entry - accepts both user and service tokens
router.post('/:id/infer-collection', flexibleAuth, async (req, res) => {
  try {
    console.log(`[INFER-COLLECTION] Starting inference for entry ${req.params.id}`);
    
    const entry = await Entry.findById(req.params.id);
    if (!entry || entry.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Entry not found' });
    }
    
    // Get existing collections for this user
    const existingCollections = await Collection.findByUserId(req.user.uid);
    const collectionNames = existingCollections.map(c => c.name);
    
    console.log(`[INFER-COLLECTION] Found ${existingCollections.length} existing collections for user`);
    
    // Run inference
    const inference = await inferCollectionFromContent(entry.content, collectionNames);
    
    if (!inference || !inference.shouldCreateCollection) {
      console.log(`[INFER-COLLECTION] No collection inference for entry ${entry.id}`);
      return res.json({ 
        message: 'No collection pattern detected',
        entryId: entry.id 
      });
    }
    
    console.log(`[INFER-COLLECTION] Inference suggests collection: ${inference.collectionName}`);
    
    // Check if collection exists
    let collection = await Collection.findByName(req.user.uid, inference.collectionName);
    let wasNewCollection = false;
    
    if (!collection) {
      console.log(`[INFER-COLLECTION] Creating new collection: ${inference.collectionName}`);
      
      // Generate detailed collection structure
      const details = await generateCollectionDetails(
        inference.collectionName,
        inference.description,
        entry.content
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
          source: 'async_inference',
          firstEntry: entry.id,
          inferredAt: new Date()
        }
      });
      
      wasNewCollection = true;
      console.log(`[INFER-COLLECTION] Created collection ${collection.id}`);
    } else {
      console.log(`[INFER-COLLECTION] Using existing collection ${collection.id}`);
    }
    
    // Check if entry is already in this collection
    const existingCollectionEntry = await CollectionEntry.findByEntryAndCollection(
      entry.id, 
      collection.id
    );
    
    if (existingCollectionEntry) {
      console.log(`[INFER-COLLECTION] Entry already in collection`);
      return res.json({
        message: 'Entry already in collection',
        collection,
        wasNewCollection: false
      });
    }
    
    // Create CollectionEntry with formatted data
    const collectionEntry = await CollectionEntry.create({
      userId: req.user.uid,
      collectionId: collection.id,
      entryId: entry.id,
      formattedData: inference.extractedData || {},
      metadata: {
        source: 'async_inference',
        inferredAt: new Date()
      }
    });
    
    console.log(`[INFER-COLLECTION] Created CollectionEntry ${collectionEntry.id}`);
    
    res.json({
      collection,
      collectionEntry,
      wasNewCollection,
      inference: {
        collectionName: collection.name,
        collectionId: collection.id,
        extractedData: inference.extractedData
      }
    });
    
  } catch (error) {
    console.error('[INFER-COLLECTION] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;