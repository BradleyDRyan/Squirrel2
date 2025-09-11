const express = require('express');
const router = express.Router();
const { Entry, Collection, CollectionEntry } = require('../models');
const { inferCollectionFromContent, generateCollectionDetails } = require('../services/collectionInference');

// No authentication for worker routes - they're internal only
// QStash will be the only one calling these endpoints

// Health check endpoint - no auth required
router.get('/health', (req, res) => {
  res.json({ 
    status: 'ok',
    message: 'Worker endpoint is accessible',
    timestamp: new Date().toISOString(),
    version: '2.0.2'
  });
});

/**
 * Process collection inference for an entry
 * Called by QStash after entry creation
 */
router.post('/process-inference', async (req, res) => {
  try {
    const { entryId, userId, content } = req.body;
    
    console.log(`[WORKER-INFERENCE] Processing inference for entry ${entryId}`);
    
    // Get existing collections for this user
    const existingCollections = await Collection.findByUserId(userId);
    const collectionNames = existingCollections.map(c => c.name);
    
    // Build instructions map for existing collections
    const collectionInstructions = {};
    existingCollections.forEach(col => {
      if (col.instructions) {
        collectionInstructions[col.name] = col.instructions;
      }
    });
    
    console.log(`[WORKER-INFERENCE] Found ${existingCollections.length} existing collections`);
    
    // Run inference with instructions
    const inference = await inferCollectionFromContent(content, collectionNames, collectionInstructions);
    
    if (!inference || !inference.collectionName) {
      console.log(`[WORKER-INFERENCE] No collection pattern detected for entry ${entryId}`);
      return res.json({ 
        success: true,
        message: 'No collection pattern detected',
        entryId 
      });
    }
    
    console.log(`[WORKER-INFERENCE] Inference suggests collection: ${inference.collectionName} (create new: ${inference.shouldCreateCollection})`);
    
    // Check if collection exists
    let collection = await Collection.findByName(userId, inference.collectionName);
    let wasNewCollection = false;
    
    if (!collection) {
      console.log(`[WORKER-INFERENCE] Creating new collection: ${inference.collectionName}`);
      
      // Generate icon, color, and instructions
      const details = await generateCollectionDetails(
        inference.collectionName,
        '',
        content
      );
      
      collection = await Collection.create({
        userId: userId,
        name: details.name,
        instructions: details.instructions || `Add entries related to ${details.name}`,
        icon: details.icon || '📝',
        color: details.color || '#6366f1',
        entryFormat: inference.entryFormat ? { fields: inference.entryFormat, version: 1 } : null,
        metadata: { 
          source: 'background_inference',
          firstEntry: entryId,
          inferredAt: new Date()
        }
      });
      
      wasNewCollection = true;
      console.log(`[WORKER-INFERENCE] Created collection ${collection.id}`);
    } else {
      console.log(`[WORKER-INFERENCE] Using existing collection ${collection.id}`);
    }
    
    // Check if entry is already in this collection
    const existingCollectionEntry = await CollectionEntry.findByEntryAndCollection(
      entryId, 
      collection.id
    );
    
    if (existingCollectionEntry) {
      console.log(`[WORKER-INFERENCE] Entry already in collection`);
      return res.json({
        success: true,
        message: 'Entry already in collection',
        collection,
        wasNewCollection: false
      });
    }
    
    // Create CollectionEntry with formatted data
    const collectionEntry = await CollectionEntry.create({
      userId: userId,
      collectionId: collection.id,
      entryId: entryId,
      formattedData: inference.extractedData || {},
      metadata: {
        source: 'background_inference',
        inferredAt: new Date()
      }
    });
    
    console.log(`[WORKER-INFERENCE] Created CollectionEntry ${collectionEntry.id}`);
    
    res.json({
      success: true,
      collection,
      collectionEntry,
      wasNewCollection,
      message: wasNewCollection 
        ? `Created new collection "${collection.name}" and added entry`
        : `Added entry to existing collection "${collection.name}"`
    });
    
  } catch (error) {
    console.error('[WORKER-INFERENCE] Error:', error);
    res.status(500).json({ 
      error: error.message,
      entryId: req.body.entryId 
    });
  }
});

/**
 * Process collection rule updates
 */
router.post('/process-collection', async (req, res) => {
  try {
    const { collectionId, userId, operation } = req.body;
    
    console.log(`[WORKER-COLLECTION] Processing ${operation} for collection ${collectionId}`);
    
    const collection = await Collection.findById(collectionId);
    if (!collection || collection.userId !== userId) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    // Different operations based on what's needed
    switch (operation) {
      case 'regenerate-rules':
        // Regenerate AI rules for the collection
        const { generateCollectionRules } = require('../services/collectionInference');
        const newRules = await generateCollectionRules(
          collection.name,
          collection.instructions
        );
        collection.rules = newRules;
        await collection.save();
        break;
        
      case 'reprocess-entries':
        // Reprocess all entries in the collection
        const entries = await CollectionEntry.findByCollection(collectionId);
        console.log(`[WORKER-COLLECTION] Reprocessing ${entries.length} entries`);
        // Process entries...
        break;
        
      default:
        console.log(`[WORKER-COLLECTION] Unknown operation: ${operation}`);
    }
    
    res.json({
      success: true,
      message: `Completed ${operation} for collection`,
      collectionId
    });
    
  } catch (error) {
    console.error('[WORKER-COLLECTION] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * Process AI generation tasks
 */
router.post('/process-ai', async (req, res) => {
  try {
    const { type, data } = req.body;
    
    console.log(`[WORKER-AI] Processing AI generation of type: ${type}`);
    
    let result;
    
    switch (type) {
      case 'summary':
        // Generate summary for multiple entries
        const { generateEntrySummary } = require('../services/openai');
        result = await generateEntrySummary(data.entries);
        break;
        
      case 'insights':
        // Generate insights from user data
        const { generateInsights } = require('../services/openai');
        result = await generateInsights(data.userId, data.timeframe);
        break;
        
      case 'bulk-categorize':
        // Categorize multiple entries at once
        const { bulkCategorize } = require('../services/entryClassifier');
        result = await bulkCategorize(data.entries);
        break;
        
      default:
        return res.status(400).json({ error: `Unknown AI type: ${type}` });
    }
    
    res.json({
      success: true,
      type,
      result
    });
    
  } catch (error) {
    console.error('[WORKER-AI] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * Process batch operations
 */
router.post('/process-batch', async (req, res) => {
  try {
    const { userId, operation, items } = req.body;
    
    console.log(`[WORKER-BATCH] Processing batch ${operation} for ${items.length} items`);
    
    const results = [];
    const errors = [];
    
    for (const item of items) {
      try {
        let result;
        
        switch (operation) {
          case 'delete-entries':
            const entry = await Entry.findById(item.id);
            if (entry && entry.userId === userId) {
              await entry.delete();
              result = { id: item.id, deleted: true };
            }
            break;
            
          case 'move-to-collection':
            // Move entries to a different collection
            result = await CollectionEntry.moveEntry(
              item.entryId,
              item.fromCollectionId,
              item.toCollectionId
            );
            break;
            
          case 'update-tags':
            // Batch update tags
            const entryToTag = await Entry.findById(item.id);
            if (entryToTag && entryToTag.userId === userId) {
              entryToTag.tags = item.tags;
              await entryToTag.save();
              result = { id: item.id, tags: item.tags };
            }
            break;
        }
        
        results.push(result);
      } catch (error) {
        errors.push({ item, error: error.message });
      }
    }
    
    console.log(`[WORKER-BATCH] Completed: ${results.length} success, ${errors.length} errors`);
    
    res.json({
      success: true,
      operation,
      processed: results.length,
      failed: errors.length,
      results,
      errors
    });
    
  } catch (error) {
    console.error('[WORKER-BATCH] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;