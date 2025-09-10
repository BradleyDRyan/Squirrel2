const WebSocket = require('ws');
const url = require('url');
const { verifyToken } = require('./middleware/auth');
const RealtimeProxy = require('./services/realtime-proxy');

class WebSocketServer {
  constructor(server) {
    this.wss = new WebSocket.Server({ 
      noServer: true,
      path: '/api/realtime/ws'
    });
    
    this.connections = new Map();
    this.setupServer(server);
    this.setupHeartbeat();
  }

  setupServer(server) {
    // Handle HTTP upgrade requests
    server.on('upgrade', async (request, socket, head) => {
      const pathname = url.parse(request.url).pathname;
      
      // Only handle our realtime WebSocket path
      if (pathname === '/api/realtime/ws') {
        try {
          // Extract token from query parameters
          const urlParams = new URLSearchParams(url.parse(request.url).query);
          const token = urlParams.get('token');
          
          if (!token) {
            socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
            socket.destroy();
            return;
          }

          // Verify Firebase token
          const user = await this.verifyWebSocketToken(token);
          
          if (!user) {
            socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
            socket.destroy();
            return;
          }

          // Handle the WebSocket connection
          this.wss.handleUpgrade(request, socket, head, (ws) => {
            this.wss.emit('connection', ws, request, user);
          });
        } catch (error) {
          console.error('WebSocket upgrade error:', error);
          socket.write('HTTP/1.1 500 Internal Server Error\r\n\r\n');
          socket.destroy();
        }
      }
    });

    // Handle new WebSocket connections
    this.wss.on('connection', (ws, request, user) => {
      console.log(`🔌 New WebSocket connection from user: ${user.uid}`);
      this.handleConnection(ws, user);
    });
  }

  async verifyWebSocketToken(token) {
    try {
      // This token could be either:
      // 1. A Firebase ID token (for direct connections)
      // 2. A session token we generated (for extra security)
      
      // First try as Firebase token
      const admin = require('firebase-admin');
      try {
        const decodedToken = await admin.auth().verifyIdToken(token);
        return { uid: decodedToken.uid, email: decodedToken.email };
      } catch (firebaseError) {
        // Not a Firebase token, try session token
        const activeSessions = require('./routes/realtime').activeSessions;
        const session = activeSessions.get(token);
        
        if (session && Date.now() - session.createdAt < 3600000) {
          return { uid: session.userId };
        }
      }
      
      return null;
    } catch (error) {
      console.error('Token verification error:', error);
      return null;
    }
  }

  async handleConnection(ws, user) {
    const connectionId = `${user.uid}_${Date.now()}`;
    
    // Create OpenAI proxy for this connection
    const proxy = new RealtimeProxy(process.env.OPENAI_API_KEY, user.uid);
    
    // Store connection info
    this.connections.set(connectionId, {
      ws: ws,
      proxy: proxy,
      userId: user.uid,
      isAlive: true,
      connectedAt: Date.now()
    });

    // Setup WebSocket event handlers
    ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString());
        
        // Handle different message types
        if (message.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong' }));
          return;
        }

        // Forward to OpenAI proxy
        proxy.handleClientMessage(message);
      } catch (error) {
        console.error(`WebSocket message error (${user.uid}):`, error);
        ws.send(JSON.stringify({
          type: 'error',
          data: { message: 'Invalid message format' }
        }));
      }
    });

    ws.on('close', () => {
      console.log(`🔌 WebSocket closed for user: ${user.uid}`);
      this.cleanupConnection(connectionId);
    });

    ws.on('error', (error) => {
      console.error(`WebSocket error for user ${user.uid}:`, error);
      this.cleanupConnection(connectionId);
    });

    ws.on('pong', () => {
      const connection = this.connections.get(connectionId);
      if (connection) {
        connection.isAlive = true;
      }
    });

    // Setup proxy event handlers
    proxy.on('client-message', (message) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(message));
      }
    });

    proxy.on('error', (error) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          type: 'error',
          data: error
        }));
      }
    });

    proxy.on('disconnected', () => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          type: 'status',
          data: { connected: false }
        }));
      }
    });

    // Connect to OpenAI
    try {
      await proxy.connect();
      
      // Send initial connection success
      ws.send(JSON.stringify({
        type: 'status',
        data: { 
          connected: true,
          message: 'Connected to voice service'
        }
      }));
    } catch (error) {
      console.error(`Failed to connect to OpenAI for user ${user.uid}:`, error);
      ws.send(JSON.stringify({
        type: 'error',
        data: { 
          message: 'Failed to connect to voice service',
          details: error.message
        }
      }));
      ws.close();
    }
  }

  cleanupConnection(connectionId) {
    const connection = this.connections.get(connectionId);
    if (connection) {
      // Disconnect from OpenAI
      if (connection.proxy) {
        connection.proxy.disconnect();
      }
      
      // Close WebSocket if still open
      if (connection.ws.readyState === WebSocket.OPEN) {
        connection.ws.close();
      }
      
      // Remove from connections map
      this.connections.delete(connectionId);
      
      console.log(`🧹 Cleaned up connection ${connectionId}`);
    }
  }

  setupHeartbeat() {
    // Ping all connections every 30 seconds to keep them alive
    setInterval(() => {
      this.connections.forEach((connection, id) => {
        if (!connection.isAlive) {
          // Connection didn't respond to last ping, terminate it
          console.log(`💔 Terminating inactive connection: ${id}`);
          this.cleanupConnection(id);
          return;
        }

        // Mark as not alive and send ping
        connection.isAlive = false;
        if (connection.ws.readyState === WebSocket.OPEN) {
          connection.ws.ping();
        }
      });
    }, 30000);

    // Clean up old connections (>30 minutes)
    setInterval(() => {
      const now = Date.now();
      const maxAge = 30 * 60 * 1000; // 30 minutes
      
      this.connections.forEach((connection, id) => {
        if (now - connection.connectedAt > maxAge) {
          console.log(`⏰ Closing old connection: ${id}`);
          if (connection.ws.readyState === WebSocket.OPEN) {
            connection.ws.send(JSON.stringify({
              type: 'error',
              data: { message: 'Session expired. Please reconnect.' }
            }));
          }
          this.cleanupConnection(id);
        }
      });
    }, 60000); // Check every minute
  }

  getStats() {
    const stats = {
      totalConnections: this.connections.size,
      userConnections: {}
    };

    this.connections.forEach((connection) => {
      if (!stats.userConnections[connection.userId]) {
        stats.userConnections[connection.userId] = 0;
      }
      stats.userConnections[connection.userId]++;
    });

    return stats;
  }
}

module.exports = WebSocketServer;