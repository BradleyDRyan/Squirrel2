const express = require('express');
const router = express.Router();
const { auth, firestore } = require('../config/firebase');
const { verifyToken, requireRole, requireVerifiedEmail } = require('../middleware/auth');

router.get('/profile', verifyToken, async (req, res) => {
  try {
    const userRecord = await auth.getUser(req.user.uid);
    
    const userDoc = await firestore.collection('users').doc(req.user.uid).get();
    const userData = userDoc.exists ? userDoc.data() : {};
    
    res.json({
      uid: userRecord.uid,
      email: userRecord.email,
      emailVerified: userRecord.emailVerified,
      displayName: userRecord.displayName,
      photoURL: userRecord.photoURL,
      phoneNumber: userRecord.phoneNumber,
      disabled: userRecord.disabled,
      metadata: {
        creationTime: userRecord.metadata.creationTime,
        lastSignInTime: userRecord.metadata.lastSignInTime,
        lastRefreshTime: userRecord.metadata.lastRefreshTime
      },
      customClaims: userRecord.customClaims || {},
      profileData: userData
    });
  } catch (error) {
    console.error('Error fetching user profile:', error);
    res.status(500).json({ error: 'Failed to fetch user profile' });
  }
});

router.put('/profile', verifyToken, async (req, res) => {
  try {
    const { displayName, photoURL, phoneNumber, additionalData } = req.body;
    
    const updateData = {};
    if (displayName !== undefined) updateData.displayName = displayName;
    if (photoURL !== undefined) updateData.photoURL = photoURL;
    if (phoneNumber !== undefined) updateData.phoneNumber = phoneNumber;
    
    if (Object.keys(updateData).length > 0) {
      await auth.updateUser(req.user.uid, updateData);
    }
    
    if (additionalData) {
      await firestore.collection('users').doc(req.user.uid).set(
        {
          ...additionalData,
          updatedAt: new Date().toISOString()
        },
        { merge: true }
      );
    }
    
    res.json({ success: true, message: 'Profile updated successfully' });
  } catch (error) {
    console.error('Error updating user profile:', error);
    res.status(500).json({ error: 'Failed to update user profile' });
  }
});

router.post('/verify-email', verifyToken, async (req, res) => {
  try {
    const link = await auth.generateEmailVerificationLink(req.user.email);
    
    res.json({ 
      success: true,
      message: 'Verification email link generated',
      link 
    });
  } catch (error) {
    console.error('Error generating verification link:', error);
    res.status(500).json({ error: 'Failed to generate verification link' });
  }
});

router.post('/set-custom-claims', verifyToken, requireRole('admin'), async (req, res) => {
  try {
    const { userId, claims } = req.body;
    
    if (!userId || !claims) {
      return res.status(400).json({ error: 'userId and claims are required' });
    }
    
    await auth.setCustomUserClaims(userId, claims);
    
    res.json({ 
      success: true,
      message: 'Custom claims set successfully',
      userId,
      claims
    });
  } catch (error) {
    console.error('Error setting custom claims:', error);
    res.status(500).json({ error: 'Failed to set custom claims' });
  }
});

router.get('/list', verifyToken, requireRole('admin'), async (req, res) => {
  try {
    const { pageToken, maxResults = 100 } = req.query;
    
    const listUsersResult = await auth.listUsers(maxResults, pageToken);
    
    const users = listUsersResult.users.map(user => ({
      uid: user.uid,
      email: user.email,
      emailVerified: user.emailVerified,
      displayName: user.displayName,
      photoURL: user.photoURL,
      disabled: user.disabled,
      metadata: user.metadata,
      customClaims: user.customClaims
    }));
    
    res.json({
      users,
      pageToken: listUsersResult.pageToken,
      hasMore: !!listUsersResult.pageToken
    });
  } catch (error) {
    console.error('Error listing users:', error);
    res.status(500).json({ error: 'Failed to list users' });
  }
});

router.post('/disable', verifyToken, requireRole('admin'), async (req, res) => {
  try {
    const { userId, disabled } = req.body;
    
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }
    
    await auth.updateUser(userId, { disabled: !!disabled });
    
    res.json({ 
      success: true,
      message: `User ${disabled ? 'disabled' : 'enabled'} successfully`,
      userId
    });
  } catch (error) {
    console.error('Error updating user status:', error);
    res.status(500).json({ error: 'Failed to update user status' });
  }
});

router.delete('/delete-account', verifyToken, async (req, res) => {
  try {
    const { password } = req.body;
    
    await firestore.collection('users').doc(req.user.uid).delete();
    
    await auth.deleteUser(req.user.uid);
    
    res.json({ 
      success: true,
      message: 'Account deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting account:', error);
    res.status(500).json({ error: 'Failed to delete account' });
  }
});

router.post('/revoke-tokens', verifyToken, async (req, res) => {
  try {
    await auth.revokeRefreshTokens(req.user.uid);
    
    res.json({ 
      success: true,
      message: 'All refresh tokens revoked'
    });
  } catch (error) {
    console.error('Error revoking tokens:', error);
    res.status(500).json({ error: 'Failed to revoke tokens' });
  }
});

module.exports = router;