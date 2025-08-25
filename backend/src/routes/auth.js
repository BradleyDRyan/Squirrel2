const express = require('express');
const router = express.Router();
const { auth, firestore } = require('../config/firebase');
const { verifyToken } = require('../middleware/auth');

router.post('/verify', async (req, res) => {
  try {
    const { idToken } = req.body;
    
    if (!idToken) {
      return res.status(400).json({ error: 'ID token is required' });
    }
    
    const decodedToken = await auth.verifyIdToken(idToken, true);
    
    // Store session info
    await firestore.collection('sessions').doc(decodedToken.uid).set({
      lastVerified: new Date().toISOString(),
      sessionId: decodedToken.auth_time,
      email: decodedToken.email,
      phoneNumber: decodedToken.phone_number,
      provider: decodedToken.firebase?.sign_in_provider || 'phone'
    }, { merge: true });
    
    // Update user document if phone auth
    if (decodedToken.phone_number) {
      await firestore.collection('users').doc(decodedToken.uid).set({
        phoneNumber: decodedToken.phone_number,
        lastLogin: new Date().toISOString()
      }, { merge: true });
    }
    
    res.json({ 
      verified: true,
      uid: decodedToken.uid,
      email: decodedToken.email,
      phoneNumber: decodedToken.phone_number,
      emailVerified: decodedToken.email_verified,
      authTime: decodedToken.auth_time,
      expiresAt: decodedToken.exp * 1000
    });
  } catch (error) {
    console.error('Token verification error:', error);
    res.status(401).json({ 
      verified: false,
      error: 'Invalid token',
      code: error.code
    });
  }
});

router.post('/refresh', verifyToken, async (req, res) => {
  try {
    const { refreshToken } = req.body;
    
    if (!refreshToken) {
      return res.status(400).json({ error: 'Refresh token is required' });
    }
    
    const userRecord = await auth.getUser(req.user.uid);
    
    const customToken = await auth.createCustomToken(req.user.uid, {
      ...req.user.customClaims,
      refreshedAt: Date.now()
    });
    
    await firestore.collection('sessions').doc(req.user.uid).set({
      lastRefreshed: new Date().toISOString(),
      refreshCount: firestore.FieldValue.increment(1)
    }, { merge: true });
    
    res.json({ 
      success: true,
      customToken,
      uid: req.user.uid
    });
  } catch (error) {
    console.error('Token refresh error:', error);
    res.status(401).json({ 
      success: false,
      error: 'Failed to refresh token'
    });
  }
});

router.post('/create-custom-token', verifyToken, async (req, res) => {
  try {
    const { uid, claims } = req.body;
    
    const targetUid = uid || req.user.uid;
    
    if (uid && uid !== req.user.uid && !req.user.customClaims?.admin) {
      return res.status(403).json({ 
        error: 'Admin privileges required to create tokens for other users' 
      });
    }
    
    const customToken = await auth.createCustomToken(targetUid, claims);
    res.json({ token: customToken });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/logout', verifyToken, async (req, res) => {
  try {
    await auth.revokeRefreshTokens(req.user.uid);
    
    await firestore.collection('sessions').doc(req.user.uid).delete();
    
    res.json({ 
      success: true,
      message: 'Logged out successfully'
    });
  } catch (error) {
    console.error('Logout error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to logout'
    });
  }
});

router.get('/session', verifyToken, async (req, res) => {
  try {
    const sessionDoc = await firestore.collection('sessions').doc(req.user.uid).get();
    
    if (!sessionDoc.exists) {
      return res.status(404).json({ error: 'No active session found' });
    }
    
    const sessionData = sessionDoc.data();
    
    res.json({
      active: true,
      uid: req.user.uid,
      email: req.user.email,
      ...sessionData
    });
  } catch (error) {
    console.error('Session fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch session' });
  }
});

router.post('/password-reset', async (req, res) => {
  try {
    const { email } = req.body;
    
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }
    
    const link = await auth.generatePasswordResetLink(email);
    
    res.json({ 
      success: true,
      message: 'Password reset link generated',
      link
    });
  } catch (error) {
    console.error('Password reset error:', error);
    res.status(500).json({ error: 'Failed to generate password reset link' });
  }
});

module.exports = router;