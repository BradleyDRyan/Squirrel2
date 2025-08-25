const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');

router.get('/status', (req, res) => {
  res.json({ 
    status: 'API is running',
    timestamp: new Date().toISOString()
  });
});

router.get('/user/:id', verifyToken, async (req, res) => {
  try {
    res.json({ 
      userId: req.params.id,
      message: 'User endpoint'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/data', verifyToken, async (req, res) => {
  try {
    const { data } = req.body;
    res.json({ 
      message: 'Data received',
      data,
      userId: req.user.uid
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;