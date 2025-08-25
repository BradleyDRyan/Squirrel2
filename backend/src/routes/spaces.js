const express = require('express');
const router = express.Router();
const { Space, Conversation, UserTask, Entry, Thought } = require('../models');
const { verifyToken } = require('../middleware/auth');

router.use(verifyToken);

router.get('/', async (req, res) => {
  try {
    const includeArchived = req.query.includeArchived === 'true';
    const spaces = await Space.findByUserId(req.user.uid, includeArchived);
    res.json(spaces);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/default', async (req, res) => {
  try {
    let defaultSpace = await Space.findDefaultSpace(req.user.uid);
    if (!defaultSpace) {
      defaultSpace = await Space.createDefaultSpace(req.user.uid);
    }
    res.json(defaultSpace);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    res.json(space);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id/stats', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    const stats = await space.updateStats();
    res.json(stats);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id/conversations', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    const conversations = await Conversation.findByUserId(req.user.uid, req.params.id);
    res.json(conversations);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id/tasks', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    const filters = {
      spaceId: req.params.id,
      status: req.query.status,
      priority: req.query.priority
    };
    
    const tasks = await UserTask.findByUserId(req.user.uid, filters);
    res.json(tasks);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id/entries', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    const filters = {
      spaceId: req.params.id,
      type: req.query.type,
      mood: req.query.mood
    };
    
    const entries = await Entry.findByUserId(req.user.uid, filters);
    res.json(entries);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id/thoughts', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    const filters = {
      spaceId: req.params.id,
      type: req.query.type,
      category: req.query.category
    };
    
    const thoughts = await Thought.findByUserId(req.user.uid, filters);
    res.json(thoughts);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/', async (req, res) => {
  try {
    if (req.body.isDefault) {
      const existingDefault = await Space.findDefaultSpace(req.user.uid);
      if (existingDefault) {
        existingDefault.isDefault = false;
        await existingDefault.save();
      }
    }
    
    const space = await Space.create({
      ...req.body,
      userId: req.user.uid
    });
    res.status(201).json(space);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    if (req.body.isDefault && !space.isDefault) {
      const existingDefault = await Space.findDefaultSpace(req.user.uid);
      if (existingDefault && existingDefault.id !== space.id) {
        existingDefault.isDefault = false;
        await existingDefault.save();
      }
    }
    
    Object.assign(space, req.body);
    await space.save();
    res.json(space);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/:id/archive', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    if (space.isDefault) {
      return res.status(400).json({ error: 'Cannot archive default space' });
    }
    
    await space.archive();
    res.json(space);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/:id/unarchive', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    await space.unarchive();
    res.json(space);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const space = await Space.findById(req.params.id);
    if (!space || space.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Space not found' });
    }
    
    if (space.isDefault) {
      return res.status(400).json({ error: 'Cannot delete default space' });
    }
    
    await space.delete();
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;