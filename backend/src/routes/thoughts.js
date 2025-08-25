const express = require('express');
const router = express.Router();
const { Thought } = require('../models');
const { verifyToken } = require('../middleware/auth');

router.use(verifyToken);

router.get('/', async (req, res) => {
  try {
    const filters = {
      type: req.query.type,
      category: req.query.category,
      conversationId: req.query.conversationId,
      isPrivate: req.query.isPrivate !== undefined ? req.query.isPrivate === 'true' : undefined
    };
    
    const thoughts = await Thought.findByUserId(req.user.uid, filters);
    res.json(thoughts);
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
    
    const thoughts = await Thought.searchContent(req.user.uid, q);
    res.json(thoughts);
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
    const thoughts = await Thought.findByTags(req.user.uid, tagArray);
    res.json(thoughts);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const thought = await Thought.findById(req.params.id);
    if (!thought || thought.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Thought not found' });
    }
    res.json(thought);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id/linked', async (req, res) => {
  try {
    const thought = await Thought.findById(req.params.id);
    if (!thought || thought.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Thought not found' });
    }
    
    const linkedThoughts = await Thought.findLinkedThoughts(req.params.id);
    res.json(linkedThoughts);
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
    
    const thought = await Thought.create({
      ...req.body,
      spaceIds,
      userId: req.user.uid
    });
    res.status(201).json(thought);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const thought = await Thought.findById(req.params.id);
    if (!thought || thought.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Thought not found' });
    }
    
    Object.assign(thought, req.body);
    await thought.save();
    res.json(thought);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/:id/link', async (req, res) => {
  try {
    const thought = await Thought.findById(req.params.id);
    if (!thought || thought.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Thought not found' });
    }
    
    const { thoughtId } = req.body;
    await thought.linkTo(thoughtId);
    res.json(thought);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/:id/insight', async (req, res) => {
  try {
    const thought = await Thought.findById(req.params.id);
    if (!thought || thought.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Thought not found' });
    }
    
    const { insight } = req.body;
    await thought.addInsight(insight);
    res.json(thought);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const thought = await Thought.findById(req.params.id);
    if (!thought || thought.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Thought not found' });
    }
    
    await thought.delete();
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;