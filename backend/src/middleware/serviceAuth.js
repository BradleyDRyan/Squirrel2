const admin = require('firebase-admin');

/**
 * Middleware that accepts either:
 * 1. Regular Firebase ID tokens (from client apps)
 * 2. Custom tokens with service claims (from internal services)
 * 3. Service-to-service auth with shared secret
 */
async function verifyServiceToken(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader) {
      return res.status(401).json({ error: 'No authorization header' });
    }
    
    const token = authHeader.replace('Bearer ', '');
    
    // First try to verify as a regular Firebase ID token
    try {
      const decodedToken = await admin.auth().verifyIdToken(token);
      req.user = {
        uid: decodedToken.uid,
        email: decodedToken.email,
        source: 'firebase'
      };
      return next();
    } catch (firebaseError) {
      // Not a valid Firebase ID token, try custom token verification
    }
    
    // Check if it's a service token (custom token with service claims)
    try {
      // For service-to-service calls, we use a custom token that includes
      // the userId and service identifier
      const decodedToken = await admin.auth().verifyIdToken(token, true);
      
      // Check if this is a service token
      if (decodedToken.service) {
        req.user = {
          uid: decodedToken.uid || decodedToken.sub,
          service: decodedToken.service,
          source: 'service'
        };
        return next();
      }
    } catch (customTokenError) {
      // Not a valid custom token either
    }
    
    // As a last resort, check for internal service secret
    // This is for server-to-server calls within our own infrastructure
    const internalSecret = process.env.INTERNAL_SERVICE_SECRET;
    if (internalSecret && token === internalSecret) {
      // For internal service calls, we need to get the user ID from the request
      const userId = req.headers['x-user-id'] || req.body.userId;
      
      if (!userId) {
        return res.status(400).json({ 
          error: 'User ID required for service authentication' 
        });
      }
      
      req.user = {
        uid: userId,
        source: 'internal-service'
      };
      return next();
    }
    
    // None of the authentication methods worked
    return res.status(401).json({ 
      error: 'Invalid authentication token' 
    });
    
  } catch (error) {
    console.error('Service auth error:', error);
    return res.status(401).json({ 
      error: 'Authentication failed',
      details: error.message 
    });
  }
}

/**
 * Middleware for endpoints that should accept both user and service tokens
 */
async function flexibleAuth(req, res, next) {
  return verifyServiceToken(req, res, next);
}

module.exports = {
  verifyServiceToken,
  flexibleAuth
};