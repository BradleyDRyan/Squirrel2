const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const firebaseAdmin = require('../src/config/firebase');
const apiRoutes = require('../src/routes/api');
const authRoutes = require('../src/routes/auth');
const userRoutes = require('../src/routes/users');
const phoneAuthRoutes = require('../src/routes/phone-auth');
const conversationRoutes = require('../src/routes/conversations');
const messageRoutes = require('../src/routes/messages');
const taskRoutes = require('../src/routes/tasks');
const entryRoutes = require('../src/routes/entries');
const collectionRoutes = require('../src/routes/collections');
const thoughtRoutes = require('../src/routes/thoughts');
const spaceRoutes = require('../src/routes/spaces');
const aiRoutes = require('../src/routes/ai');
const realtimeRoutes = require('../src/routes/realtime');
const configRoutes = require('../src/routes/config');

const app = express();

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100
});

app.use(helmet());
app.use(cors({
  origin: true,
  credentials: true
}));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

if (process.env.NODE_ENV !== 'production') {
  app.use(morgan('dev'));
}

app.use('/api', limiter);

app.get('/', (req, res) => {
  res.json({ 
    message: 'Squirrel 2.0 Backend API',
    version: '2.0.0',
    endpoints: {
      auth: '/auth',
      api: '/api',
      users: '/users',
      spaces: '/api/spaces',
      conversations: '/api/conversations',
      messages: '/api/messages',
      tasks: '/api/tasks',
      entries: '/api/entries',
      collections: '/api/collections',
      thoughts: '/api/thoughts'
    }
  });
});

app.use('/auth', authRoutes);
app.use('/auth/phone', phoneAuthRoutes);
app.use('/api', apiRoutes);
app.use('/users', userRoutes);
app.use('/api/spaces', spaceRoutes);
app.use('/api/conversations', conversationRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/tasks', taskRoutes);
app.use('/api/entries', entryRoutes);
app.use('/api/collections', collectionRoutes);
app.use('/api/thoughts', thoughtRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/realtime', realtimeRoutes);
app.use('/api/config', configRoutes);

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ 
    error: 'Something went wrong!',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

module.exports = app;