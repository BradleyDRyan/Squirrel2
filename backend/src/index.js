const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const firebaseAdmin = require('./config/firebase');
const apiRoutes = require('./routes/api');
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const phoneAuthRoutes = require('./routes/phone-auth');
const conversationRoutes = require('./routes/conversations');
const messageRoutes = require('./routes/messages');
const taskRoutes = require('./routes/tasks');
const entryRoutes = require('./routes/entries');
const thoughtRoutes = require('./routes/thoughts');
const spaceRoutes = require('./routes/spaces');

const app = express();
const PORT = process.env.PORT || 3000;

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100
});

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan('dev'));
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
app.use('/api/thoughts', thoughtRoutes);

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ 
    error: 'Something went wrong!',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined
  });
});

app.listen(PORT, () => {
  console.log(`Squirrel 2.0 Backend running on port ${PORT}`);
});