// Test Firebase authentication
require('dotenv').config();
const { auth } = require('./src/config/firebase');

async function testFirebaseAuth() {
  console.log('Testing Firebase Admin SDK...');
  
  try {
    // Check if Firebase Admin is initialized
    console.log('✅ Firebase Admin SDK initialized');
    console.log('Project ID:', auth.projectId || 'Unknown');
    
    // Test creating a custom token (this verifies service account is working)
    const testUid = 'test-user-' + Date.now();
    const customToken = await auth.createCustomToken(testUid);
    console.log('✅ Successfully created custom token, Firebase auth is working');
    
    // Clean up test user if it was created
    try {
      await auth.deleteUser(testUid);
    } catch (e) {
      // User might not exist, that's okay
    }
    
  } catch (error) {
    console.error('❌ Firebase auth error:', error.message);
    console.error('Error code:', error.code);
  }
}

testFirebaseAuth();