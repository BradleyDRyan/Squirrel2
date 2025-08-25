const { auth } = require('../config/firebase');

const verifyToken = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'No token provided' });
    }
    
    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await auth.verifyIdToken(idToken);
    
    req.user = {
      uid: decodedToken.uid,
      email: decodedToken.email,
      emailVerified: decodedToken.email_verified,
      displayName: decodedToken.name,
      photoURL: decodedToken.picture,
      phoneNumber: decodedToken.phone_number,
      customClaims: decodedToken.customClaims || {},
      token: decodedToken
    };
    
    next();
  } catch (error) {
    console.error('Token verification error:', error);
    
    if (error.code === 'auth/id-token-expired') {
      return res.status(401).json({ error: 'Token expired', code: 'TOKEN_EXPIRED' });
    } else if (error.code === 'auth/id-token-revoked') {
      return res.status(401).json({ error: 'Token revoked', code: 'TOKEN_REVOKED' });
    } else if (error.code === 'auth/invalid-id-token') {
      return res.status(401).json({ error: 'Invalid token', code: 'INVALID_TOKEN' });
    }
    
    res.status(401).json({ error: 'Authentication failed', code: 'AUTH_FAILED' });
  }
};

const optionalAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      req.user = null;
      return next();
    }
    
    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await auth.verifyIdToken(idToken);
    
    req.user = {
      uid: decodedToken.uid,
      email: decodedToken.email,
      emailVerified: decodedToken.email_verified,
      displayName: decodedToken.name,
      photoURL: decodedToken.picture,
      phoneNumber: decodedToken.phone_number,
      customClaims: decodedToken.customClaims || {},
      token: decodedToken
    };
    
    next();
  } catch (error) {
    req.user = null;
    next();
  }
};

const requireRole = (role) => {
  return async (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Authentication required' });
    }
    
    const userRole = req.user.customClaims?.role || req.user.token?.role;
    
    if (userRole !== role) {
      return res.status(403).json({ 
        error: 'Insufficient permissions',
        required: role,
        current: userRole || 'none'
      });
    }
    
    next();
  };
};

const requireVerifiedEmail = async (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  
  if (!req.user.emailVerified) {
    return res.status(403).json({ error: 'Email verification required' });
  }
  
  next();
};

module.exports = { 
  verifyToken, 
  optionalAuth, 
  requireRole,
  requireVerifiedEmail
};