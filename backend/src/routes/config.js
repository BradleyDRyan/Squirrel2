const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');

// Get OpenAI API key (protected)
router.get('/openai-key', verifyToken, async (req, res) => {
  try {
    // Only return key if it's configured
    const apiKey = process.env.OPENAI_API_KEY;
    
    if (!apiKey || apiKey === 'your-openai-api-key-here') {
      return res.status(500).json({
        success: false,
        error: 'OpenAI API key not configured on server'
      });
    }
    
    // Return the key (only to authenticated users)
    res.json({
      success: true,
      apiKey: apiKey
    });
  } catch (error) {
    console.error('Error fetching API key:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch API key'
    });
  }
});

module.exports = router;