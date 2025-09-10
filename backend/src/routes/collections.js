const express = require('express');
const router = express.Router();
const { Collection, Entry } = require('../models');
const { verifyToken } = require('../middleware/auth');
const { formatDatesInObject } = require('../utils/dateUtils');

router.use(verifyToken);

// Get all collections for user
router.get('/', async (req, res) => {
  try {
    console.log('[Collections GET /] Request from user:', req.user.uid);
    const collections = await Collection.findByUserId(req.user.uid);
    console.log('[Collections GET /] Found collections:', collections.length);
    
    // Format dates to ISO8601
    const formattedCollections = collections.map(c => formatDatesInObject(c));
    
    res.json(formattedCollections);
  } catch (error) {
    console.error('[Collections GET /] Error:', error);
    console.error('[Collections GET /] Error stack:', error.stack);
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