const admin = require('firebase-admin');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = {
  projectId: process.env.FIREBASE_PROJECT_ID,
  clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
  privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n')
};

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

async function testConfigEndpoint() {
  try {
    // Create a custom token for testing
    const customToken = await admin.auth().createCustomToken('test-user-123');
    console.log('✅ Custom token created');
    
    // Use the custom token to get an ID token
    // Note: We need to use Firebase client SDK for this, or test with a real user token
    
    // For now, let's test if the endpoint exists
    const response = await fetch('https://backend-sigma-drab.vercel.app/api/config/openai-key', {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        // We'll need a real token here
        'Authorization': 'Bearer test-token'
      }
    });
    
    console.log('Response status:', response.status);
    const data = await response.text();
    console.log('Response:', data);
    
  } catch (error) {
    console.error('Error:', error);
  }
}

testConfigEndpoint();