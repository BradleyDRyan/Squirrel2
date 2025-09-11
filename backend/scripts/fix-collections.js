require('dotenv').config();
const { firestore } = require('../src/config/firebase');

const db = firestore;

async function fixCollections() {
  console.log('Fixing collections without userId...');
  
  // The userId we need to add (from your logs)
  const userId = '3ORk6bii4WfKYwgujdsOSQy8Jyf1';
  
  try {
    // Get all collections
    const snapshot = await db.collection('collections').get();
    
    if (snapshot.empty) {
      console.log('No collections found');
      return;
    }
    
    console.log(`Found ${snapshot.size} collections`);
    
    // Update each collection that doesn't have a userId
    const batch = db.batch();
    let updateCount = 0;
    
    snapshot.forEach(doc => {
      const data = doc.data();
      if (!data.userId) {
        console.log(`Updating collection ${doc.id} (${data.name}) with userId`);
        batch.update(doc.ref, { userId: userId });
        updateCount++;
      } else {
        console.log(`Collection ${doc.id} (${data.name}) already has userId: ${data.userId}`);
      }
    });
    
    if (updateCount > 0) {
      await batch.commit();
      console.log(`✅ Updated ${updateCount} collections with userId`);
    } else {
      console.log('✅ All collections already have userId');
    }
    
  } catch (error) {
    console.error('Error fixing collections:', error);
  } finally {
    // Exit the process
    process.exit(0);
  }
}

// Run the fix
fixCollections();