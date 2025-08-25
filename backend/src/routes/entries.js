const express = require('express');
const router = express.Router();
const { Entry } = require('../models');
const { verifyToken } = require('../middleware/auth');

router.use(verifyToken);

router.get('/', async (req, res) => {
  try {
    const filters = {
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