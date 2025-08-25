const express = require('express');
const router = express.Router();
const { auth, firestore } = require('../config/firebase');

// Store verification sessions temporarily (in production, use Redis or similar)
const verificationSessions = new Map();

// Test phone numbers configuration
// Store in E.164 format as Firebase expects
// Example: TEST_PHONE_NUMBERS=+15555555555,+12125551234,+14155551234
const TEST_PHONE_NUMBERS = process.env.TEST_PHONE_NUMBERS ? 
  process.env.TEST_PHONE_NUMBERS.split(',').map(n => n.trim()) : 
  ['+15555555555']; // Default test number for development

const TEST_VERIFICATION_CODE = process.env.TEST_VERIFICATION_CODE || '123456';

// Helper function to format phone number to E.164 format
function formatToE164(phoneNumber) {
  // Remove all non-digit characters
  const digitsOnly = phoneNumber.replace(/\D/g, '');
  
  // Handle different formats
  if (digitsOnly.length === 10) {
    // US number without country code
    return '+1' + digitsOnly;
  } else if (digitsOnly.length === 11 && digitsOnly.startsWith('1')) {
    // US number with country code
    return '+' + digitsOnly;
  } else if (phoneNumber.startsWith('+')) {
    // Already has country code
    return '+' + digitsOnly;
  }
  
  // Default to US if we can't determine
  return '+1' + digitsOnly;
}

// Helper function to check if a phone number is a test number
function isTestPhoneNumber(formattedPhone) {
  return TEST_PHONE_NUMBERS.includes(formattedPhone);
}

// Send verification code
router.post('/send-code', async (req, res) => {
  try {
    const { phoneNumber } = req.body;
    
    if (!phoneNumber) {
      return res.status(400).json({ error: 'Phone number is required' });
    }
    
    // Format to E.164 for Firebase compatibility
    const formattedPhone = formatToE164(phoneNumber);
    
    // Check if this is a test phone number
    const isTestNumber = process.env.NODE_ENV === 'development' && isTestPhoneNumber(formattedPhone);
    
    // Generate verification code
    const verificationCode = isTestNumber ? TEST_VERIFICATION_CODE : 
      Math.floor(100000 + Math.random() * 900000).toString();
    
    const sessionId = 'session-' + Date.now();
    verificationSessions.set(sessionId, {
      phoneNumber: formattedPhone, // Store in E.164 format
      originalPhoneNumber: phoneNumber,
      code: verificationCode,
      createdAt: Date.now(),
      attempts: 0,
      isTest: isTestNumber
    });
    
    // Log the code for development
    if (process.env.NODE_ENV === 'development') {
      console.log(`Verification code for ${phoneNumber}: ${verificationCode}`);
      if (isTestNumber) {
        console.log('(Test number detected)');
      }
    }
    
    // Clean up old sessions after 10 minutes
    setTimeout(() => {
      verificationSessions.delete(sessionId);
    }, 10 * 60 * 1000);
    
    return res.json({ 
      success: true,
      sessionId,
      message: isTestNumber ? 
        `Test verification code sent (use ${TEST_VERIFICATION_CODE})` : 
        'Verification code sent'
    });
  } catch (error) {
    console.error('Send code error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to send verification code'
    });
  }
});

// Verify code and create/sign in user
router.post('/verify-code', async (req, res) => {
  try {
    const { sessionId, code } = req.body;
    
    if (!sessionId || !code) {
      return res.status(400).json({ error: 'Session ID and code are required' });
    }
    
    const session = verificationSessions.get(sessionId);
    
    if (!session) {
      return res.status(400).json({ error: 'Invalid or expired session' });
    }
    
    // Check if too many attempts
    if (session.attempts >= 5) {
      verificationSessions.delete(sessionId);
      return res.status(429).json({ error: 'Too many attempts. Please request a new code.' });
    }
    
    session.attempts++;
    
    // Verify the code
    if (session.code !== code) {
      return res.status(400).json({ 
        error: 'Invalid verification code',
        attemptsRemaining: 5 - session.attempts
      });
    }
    
    // Code is valid, create or get user
    const phoneNumber = session.phoneNumber; // This is already in E.164 format
    let userRecord;
    
    try {
      // Try to get existing user by phone number
      userRecord = await auth.getUserByPhoneNumber(phoneNumber);
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        // Create new user
        userRecord = await auth.createUser({
          phoneNumber: phoneNumber,
          disabled: false
        });
        
        // Create user document in Firestore
        await firestore.collection('users').doc(userRecord.uid).set({
          phoneNumber: phoneNumber,
          createdAt: new Date().toISOString(),
          lastLogin: new Date().toISOString()
        });
      } else {
        throw error;
      }
    }
    
    // Update last login
    await firestore.collection('users').doc(userRecord.uid).update({
      lastLogin: new Date().toISOString()
    });
    
    // Create custom token for the user
    const customToken = await auth.createCustomToken(userRecord.uid, {
      phoneNumber: phoneNumber,
      signInMethod: 'phone'
    });
    
    // Clean up the verification session
    verificationSessions.delete(sessionId);
    
    res.json({
      success: true,
      uid: userRecord.uid,
      customToken,
      phoneNumber: phoneNumber,
      isNewUser: !userRecord.metadata.lastSignInTime
    });
  } catch (error) {
    console.error('Verify code error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to verify code'
    });
  }
});

// Resend code
router.post('/resend-code', async (req, res) => {
  try {
    const { sessionId } = req.body;
    
    if (!sessionId) {
      return res.status(400).json({ error: 'Session ID is required' });
    }
    
    const session = verificationSessions.get(sessionId);
    
    if (!session) {
      return res.status(400).json({ error: 'Invalid or expired session' });
    }
    
    // Generate new code
    const newCode = Math.floor(100000 + Math.random() * 900000).toString();
    session.code = newCode;
    session.attempts = 0;
    session.createdAt = Date.now();
    
    // Here you would actually resend the SMS
    console.log(`New verification code for ${session.phoneNumber}: ${newCode}`);
    
    res.json({ 
      success: true,
      message: 'Verification code resent'
    });
  } catch (error) {
    console.error('Resend code error:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to resend code'
    });
  }
});

module.exports = router;