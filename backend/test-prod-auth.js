// Test production authentication
const axios = require('axios');

async function testProdAuth() {
  const baseURL = 'https://backend-sigma-drab.vercel.app';
  
  try {
    // Test status endpoint
    console.log('Testing production status endpoint...');
    const statusResponse = await axios.get(`${baseURL}/api/realtime/status`);
    console.log('✅ Status:', statusResponse.data);
    
    // Test with invalid token (should fail with 401)
    console.log('\nTesting with invalid token...');
    try {
      await axios.get(`${baseURL}/api/realtime/key`, {
        headers: {
          'Authorization': 'Bearer invalid-token'
        }
      });
      console.log('❌ Should have failed with invalid token');
    } catch (error) {
      if (error.response && error.response.status === 401) {
        console.log('✅ Correctly rejected invalid token');
      } else if (error.response && error.response.status === 500) {
        console.log('❌ Server error (500):', error.response.data);
      } else {
        console.log('❌ Unexpected error:', error.message);
      }
    }
    
  } catch (error) {
    console.error('Test failed:', error.message);
    if (error.response) {
      console.error('Response:', error.response.data);
    }
  }
}

testProdAuth();