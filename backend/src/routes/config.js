const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');

// Get OpenAI API key (protected)
router.get('/openai-key', verifyToken, async (req, res) => {
  try {
    console.log('[Config] Fetching OpenAI API key for user:', req.user?.uid);
    
    // Only return key if it's configured
    const apiKey = process.env.OPENAI_API_KEY;
    
    if (!apiKey || apiKey === 'your-openai-api-key-here' || apiKey === '') {
      console.error('[Config] OpenAI API key not configured:', { 
        hasKey: !!apiKey, 
        isDefault: apiKey === 'your-openai-api-key-here',
        isEmpty: apiKey === ''
      });
      return res.status(500).json({
        success: false,
        error: 'OpenAI API key not configured on server'
      });
    }
    
    console.log('[Config] Successfully returning OpenAI API key');
    // Return the key (only to authenticated users)
    res.json({
      success: true,
      apiKey: apiKey
    });
  } catch (error) {
    console.error('[Config] Error fetching API key:', error.message, error.stack);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch API key',
      details: error.message
    });
  }
});

module.exports = router;