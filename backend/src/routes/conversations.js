const express = require('express');
const router = express.Router();
const { Conversation, Message } = require('../models');
const { verifyToken } = require('../middleware/auth');

router.use(verifyToken);

router.get('/', async (req, res) => {
  try {
    const spaceId = req.query.spaceId || null;
    const conversations = await Conversation.findByUserId(req.user.uid, spaceId);
    res.json(conversations);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const conversation = await Conversation.findById(req.params.id);
    if (!conversation || conversation.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    res.json(conversation);
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
    
    const conversation = await Conversation.create({
      ...req.body,
      spaceIds,
      userId: req.user.uid
    });
    res.status(201).json(conversation);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const conversation = await Conversation.findById(req.params.id);
    if (!conversation || conversation.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    
    Object.assign(conversation, req.body);
    await conversation.save();
    res.json(conversation);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const conversation = await Conversation.findById(req.params.id);
    if (!conversation || conversation.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    
    await conversation.delete();
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/:id/messages', async (req, res) => {
  try {
    const conversation = await Conversation.findById(req.params.id);
    if (!conversation || conversation.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    
    const limit = parseInt(req.query.limit) || 50;
    const messages = await Message.findByConversationId(req.params.id, limit);
    res.json(messages);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/:id/spaces', async (req, res) => {
  try {
    const conversation = await Conversation.findById(req.params.id);
    if (!conversation || conversation.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    
    const { spaceId } = req.body;
    if (!conversation.spaceIds.includes(spaceId)) {
      conversation.spaceIds.push(spaceId);
      await conversation.save();
    }
    res.json(conversation);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id/spaces/:spaceId', async (req, res) => {
  try {
    const conversation = await Conversation.findById(req.params.id);
    if (!conversation || conversation.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Conversation not found' });
    }
    
    conversation.spaceIds = conversation.spaceIds.filter(id => id !== req.params.spaceId);
    await conversation.save();
    res.json(conversation);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;