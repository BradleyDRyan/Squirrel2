const express = require('express');
const router = express.Router();
const { UserTask } = require('../models');
const { verifyToken } = require('../middleware/auth');

router.use(verifyToken);

router.get('/', async (req, res) => {
  try {
    const filters = {
      status: req.query.status,
      priority: req.query.priority,
      conversationId: req.query.conversationId
    };
    
    const tasks = await UserTask.findByUserId(req.user.uid, filters);
    res.json(tasks);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/pending', async (req, res) => {
  try {
    const tasks = await UserTask.findPending(req.user.uid);
    res.json(tasks);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/completed', async (req, res) => {
  try {
    const tasks = await UserTask.findCompleted(req.user.uid);
    res.json(tasks);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const task = await UserTask.findById(req.params.id);
    if (!task || task.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Task not found' });
    }
    res.json(task);
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
    
    const task = await UserTask.create({
      ...req.body,
      spaceIds,
      userId: req.user.uid
    });
    res.status(201).json(task);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const task = await UserTask.findById(req.params.id);
    if (!task || task.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Task not found' });
    }
    
    Object.assign(task, req.body);
    await task.save();
    res.json(task);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/:id/complete', async (req, res) => {
  try {
    const task = await UserTask.findById(req.params.id);
    if (!task || task.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Task not found' });
    }
    
    await task.markComplete();
    res.json(task);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const task = await UserTask.findById(req.params.id);
    if (!task || task.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Task not found' });
    }
    
    await task.delete();
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create task from voice input
router.post('/create-voice-task', async (req, res) => {
  try {
    const { title, description, priority, dueDate } = req.body;
    
    if (!title) {
      return res.status(400).json({ error: 'Task title is required' });
    }
    
    console.log(`[VOICE-TASK] Creating task from voice: "${title}"`);
    
    // Get or create default space
    const { Space } = require('../models');
    const defaultSpace = await Space.findDefaultSpace(req.user.uid) || 
                         await Space.createDefaultSpace(req.user.uid);
    const spaceIds = defaultSpace ? [defaultSpace.id] : [];
    
    const taskData = {
      userId: req.user.uid,
      title: title,
      description: description || '',
      priority: priority || 'medium',
      status: 'pending',
      source: 'voice',
      spaceIds: spaceIds,
      metadata: { 
        source: 'voice',
        createdAt: new Date()
      }
    };
    
    if (dueDate) {
      taskData.dueDate = new Date(dueDate);
    }
    
    const task = await UserTask.create(taskData);
    
    console.log(`[VOICE-TASK] Created task ${task.id}: "${task.title}"`);
    
    res.status(201).json({
      success: true,
      task: task,
      message: `Task "${task.title}" created successfully`
    });
  } catch (error) {
    console.error('[VOICE-TASK] Error creating task:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;