const express = require('express');
const router = express.Router();
const { Collection, Entry, CollectionEntry } = require('../models');
const { verifyToken } = require('../middleware/auth');
const { formatDatesInObject } = require('../utils/dateUtils');

router.use(verifyToken);

// Get all collection entries for a collection
router.get('/collections/:collectionId/entries', async (req, res) => {
  try {
    const { collectionId } = req.params;
    
    // Verify collection belongs to user
    const collection = await Collection.findById(collectionId);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    // Get all CollectionEntries for this collection
    const collectionEntries = await CollectionEntry.findByCollectionAndUser(collectionId, req.user.uid);
    
    // Format dates
    const formatted = collectionEntries.map(ce => formatDatesInObject(ce));
    
    res.json(formatted);
  } catch (error) {
    console.error('[CollectionEntries GET] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Add an entry to a collection (create CollectionEntry)
router.post('/collections/:collectionId/entries', async (req, res) => {
  try {
    const { collectionId } = req.params;
    const { entryId, formattedData } = req.body;
    
    // Verify collection belongs to user
    const collection = await Collection.findById(collectionId);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    // Verify entry belongs to user
    const entry = await Entry.findById(entryId);
    if (!entry || entry.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Entry not found' });
    }
    
    // Check if CollectionEntry already exists
    const existing = await CollectionEntry.findExisting(entryId, collectionId);
    if (existing) {
      return res.status(400).json({ error: 'Entry already in collection' });
    }
    
    // Create CollectionEntry
    const collectionEntry = await CollectionEntry.create({
      entryId,
      collectionId,
      userId: req.user.uid,
      formattedData: formattedData || {},
      metadata: {
        source: 'manual'
      }
    });
    
    // Update collection stats
    await collection.updateStats();
    
    res.status(201).json(collectionEntry);
  } catch (error) {
    console.error('[CollectionEntries POST] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Update a collection entry (user overrides)
router.put('/collection-entries/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { userOverrides } = req.body;
    
    // Get CollectionEntry
    const collectionEntry = await CollectionEntry.findById(id);
    if (!collectionEntry || collectionEntry.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection entry not found' });
    }
    
    // Update user overrides
    collectionEntry.userOverrides = userOverrides;
    await collectionEntry.save();
    
    res.json(collectionEntry);
  } catch (error) {
    console.error('[CollectionEntries PUT] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Remove entry from collection
router.delete('/collection-entries/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    // Get CollectionEntry
    const collectionEntry = await CollectionEntry.findById(id);
    if (!collectionEntry || collectionEntry.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection entry not found' });
    }
    
    // Delete it
    await collectionEntry.delete();
    
    // Update collection stats
    const collection = await Collection.findById(collectionEntry.collectionId);
    if (collection) {
      await collection.updateStats();
    }
    
    res.status(204).send();
  } catch (error) {
    console.error('[CollectionEntries DELETE] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Reprocess all entries in a collection with updated format
router.post('/collections/:collectionId/reprocess', async (req, res) => {
  try {
    const { collectionId } = req.params;
    
    // Verify collection belongs to user
    const collection = await Collection.findById(collectionId);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    if (!collection.entryFormat) {
      return res.status(400).json({ error: 'Collection has no entry format defined' });
    }
    
    // Get all CollectionEntries
    const collectionEntries = await CollectionEntry.findByCollectionAndUser(collectionId, req.user.uid);
    
    // Process each one
    let processed = 0;
    for (const ce of collectionEntries) {
      // Get the source entry
      const entry = await Entry.findById(ce.entryId);
      if (entry) {
        // TODO: Call AI extraction service to reformat based on collection.entryFormat
        // For now, just update timestamp
        await ce.reprocess(entry.content, collection.entryFormat);
        processed++;
      }
    }
    
    res.json({ 
      success: true, 
      message: `Reprocessed ${processed} entries`,
      processed 
    });
  } catch (error) {
    console.error('[CollectionEntries REPROCESS] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get entries that could belong to a collection (AI matching)
router.post('/collections/:collectionId/match-entries', async (req, res) => {
  try {
    const { collectionId } = req.params;
    
    // Verify collection belongs to user
    const collection = await Collection.findById(collectionId);
    if (!collection || collection.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Collection not found' });
    }
    
    // Get all user entries not already in this collection
    const allEntries = await Entry.findByUserId(req.user.uid);
    const existingCEs = await CollectionEntry.findByCollectionAndUser(collectionId, req.user.uid);
    const existingEntryIds = new Set(existingCEs.map(ce => ce.entryId));
    
    const unassignedEntries = allEntries.filter(e => !existingEntryIds.has(e.id));
    
    // TODO: Use AI to match entries based on collection rules
    // For now, return all unassigned entries
    
    res.json({
      collection: {
        id: collection.id,
        name: collection.name,
        rules: collection.rules
      },
      potentialEntries: unassignedEntries.slice(0, 20) // Limit to 20 for now
    });
  } catch (error) {
    console.error('[CollectionEntries MATCH] Error:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;