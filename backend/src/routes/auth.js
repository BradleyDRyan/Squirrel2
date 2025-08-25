const express = require('express');
const router = express.Router();
const { auth } = require('../config/firebase');

router.post('/verify', async (req, res) => {
  try {
    const { idToken } = req.body;
    
    if (!idToken) {
      return res.status(400).json({ error: 'ID token is required' });
    }
    
    const decodedToken = await auth.verifyIdToken(idToken);
    res.json({ 
      verified: true,
      uid: decodedToken.uid,
      email: decodedToken.email
    });
  } catch (error) {
    res.status(401).json({ 
      verified: false,
      error: 'Invalid token'
    });
  }
});

router.post('/create-custom-token', async (req, res) => {
  try {
    const { uid, claims } = req.body;
    
    const customToken = await auth.createCustomToken(uid, claims);
    res.json({ token: customToken });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;