const admin = require('firebase-admin');

const initializeFirebase = () => {
  // Check for full service account JSON (local development)
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: process.env.FIREBASE_DATABASE_URL,
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET || 'squirrel2-77579.appspot.com'
    });
  } 
  // Check for individual Firebase credentials (Vercel deployment)
  else if (process.env.FIREBASE_PROJECT_ID && 
           process.env.FIREBASE_CLIENT_EMAIL && 
           process.env.FIREBASE_PRIVATE_KEY) {
    
    const serviceAccount = {
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      // Handle escaped newlines in private key
      privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n')
    };
    
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: process.env.FIREBASE_DATABASE_URL,
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET || 'squirrel2-77579.appspot.com'
    });
  } 
  // Default initialization (for environments with default credentials)
  else {
    admin.initializeApp({
      storageBucket: process.env.FIREBASE_STORAGE_BUCKET || 'squirrel2-77579.appspot.com'
    });
  }
  
  console.log('Firebase Admin initialized');
  return admin;
};

const firebaseAdmin = initializeFirebase();

module.exports = {
  admin: firebaseAdmin,
  auth: firebaseAdmin.auth(),
  firestore: firebaseAdmin.firestore()
};