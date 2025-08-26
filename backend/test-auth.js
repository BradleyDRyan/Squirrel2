// Test script to debug authentication issue
require('dotenv').config();
const axios = require('axios');

async function testAuth() {
  try {
    // First, test the status endpoint
    console.log('Testing status endpoint...');
    const statusResponse = await axios.get('http://localhost:3000/api/realtime/status');
    console.log('Status:', statusResponse.data);
    
    // Test with a mock Firebase token (this should fail with 401)
    console.log('\nTesting with invalid token...');
    try {
      await axios.get('http://localhost:3000/api/realtime/key', {
        headers: {
          'Authorization': 'Bearer invalid-token'
        }
      });
    } catch (error) {
      if (error.response && error.response.status === 401) {
        console.log('✅ Correctly rejected invalid token:', error.response.data);
      } else {
        console.log('❌ Unexpected error:', error.message);
      }
    }
    
    // Check if OPENAI_API_KEY is set
    if (process.env.OPENAI_API_KEY) {
      console.log('\n✅ OPENAI_API_KEY is set in environment');
    } else {
      console.log('\n❌ OPENAI_API_KEY is NOT set in environment');
    }
    
  } catch (error) {
    console.error('Test failed:', error.message);
    if (error.response) {
      console.error('Response data:', error.response.data);
    }
  }
}

testAuth();