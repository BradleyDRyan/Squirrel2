const express = require('express');
const router = express.Router();
const { Message, Conversation } = require('../models');
const { verifyToken } = require('../middleware/auth');

router.use(verifyToken);

router.get('/:id', async (req, res) => {
  try {
    const message = await Message.findById(req.params.id);
    if (!message) {
      return res.status(404).json({ error: 'Message not found' });
    }
    
    const conversation = await Conversation.findById(message.conversationId);
    if (!conversation || conversation.userId !== req.user.uid) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    res.json(message);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const conversation = await Conversation.findById(req.body.conversationId);
    if (!conversation || conversation.userId !== req.user.uid) {
      return res.status(403).json({ error: 'Access denied' });
    }
    
    const message = await Message.create({
      ...req.body,
      userId: req.user.uid
    });
    
    conversation.lastMessage = message.content;
    await conversation.save();
    
    res.status(201).json(message);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const message = await Message.findById(req.params.id);
    if (!message || message.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Message not found' });
    }
    
    message.content = req.body.content || message.content;
    message.attachments = req.body.attachments || message.attachments;
    message.metadata = req.body.metadata || message.metadata;
    await message.save();
    
    res.json(message);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const message = await Message.findById(req.params.id);
    if (!message || message.userId !== req.user.uid) {
      return res.status(404).json({ error: 'Message not found' });
    }
    
    await message.delete();
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;