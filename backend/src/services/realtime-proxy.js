const WebSocket = require('ws');
const { EventEmitter } = require('events');

class RealtimeProxy extends EventEmitter {
  constructor(apiKey, userId) {
    super();
    this.apiKey = apiKey;
    this.userId = userId;
    this.openAIWs = null;
    this.isConnected = false;
    this.sessionId = null;
    this.functionCallStates = new Map();
    this.processedFunctionCalls = new Set();
  }

  async connect() {
    return new Promise((resolve, reject) => {
      try {
        // Connect to OpenAI Realtime API
        const url = 'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview';
        this.openAIWs = new WebSocket(url, {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
            'OpenAI-Beta': 'realtime=v1'
          }
        });

        this.openAIWs.on('open', () => {
          console.log(`✅ Connected to OpenAI Realtime API for user ${this.userId}`);
          this.isConnected = true;
          resolve();
        });

        this.openAIWs.on('message', (data) => {
          this.handleOpenAIMessage(data.toString());
        });

        this.openAIWs.on('error', (error) => {
          console.error(`❌ OpenAI WebSocket error for user ${this.userId}:`, error);
          this.emit('error', { type: 'connection', message: error.message });
          reject(error);
        });

        this.openAIWs.on('close', () => {
          console.log(`🔌 OpenAI connection closed for user ${this.userId}`);
          this.isConnected = false;
          this.emit('disconnected');
        });
      } catch (error) {
        reject(error);
      }
    });
  }

  handleOpenAIMessage(data) {
    try {
      const event = JSON.parse(data);
      
      // Log for debugging
      if (process.env.DEBUG === 'true') {
        console.log(`📥 OpenAI event (${this.userId}):`, event.type);
      }

      // Handle different event types
      switch (event.type) {
        case 'session.created':
          this.sessionId = event.session.id;
          this.emit('client-message', {
            type: 'status',
            data: { connected: true, sessionId: this.sessionId }
          });
          break;

        case 'session.updated':
          this.emit('client-message', {
            type: 'status',
            data: { sessionUpdated: true }
          });
          break;

        case 'input_audio_buffer.speech_started':
          this.emit('client-message', {
            type: 'status',
            data: { listening: true, speechStarted: true }
          });
          break;

        case 'input_audio_buffer.speech_stopped':
          this.emit('client-message', {
            type: 'status',
            data: { listening: false, speechStopped: true }
          });
          break;

        case 'input_audio_buffer.committed':
          this.emit('client-message', {
            type: 'status',
            data: { audioCommitted: true }
          });
          break;

        case 'response.audio.delta':
          // Forward audio chunks to client
          this.emit('client-message', {
            type: 'audio',
            data: { 
              chunk: event.delta,
              done: false 
            }
          });
          break;

        case 'response.audio.done':
          this.emit('client-message', {
            type: 'audio',
            data: { done: true }
          });
          break;

        case 'response.text.delta':
          this.emit('client-message', {
            type: 'text',
            data: { 
              content: event.delta,
              done: false 
            }
          });
          break;

        case 'response.text.done':
          this.emit('client-message', {
            type: 'text',
            data: { 
              content: event.text,
              done: true 
            }
          });
          break;

        case 'response.audio_transcript.delta':
          this.emit('client-message', {
            type: 'transcript',
            data: {
              text: event.delta,
              role: 'assistant',
              final: false
            }
          });
          break;

        case 'response.audio_transcript.done':
          this.emit('client-message', {
            type: 'transcript',
            data: {
              text: event.transcript,
              role: 'assistant',
              final: true
            }
          });
          break;

        case 'conversation.item.input_audio_transcription.completed':
          this.emit('client-message', {
            type: 'transcript',
            data: {
              text: event.transcript,
              role: 'user',
              final: true
            }
          });
          break;

        case 'response.function_call_arguments.delta':
          // Track streaming function arguments
          const callId = event.call_id;
          if (!this.functionCallStates.has(callId)) {
            this.functionCallStates.set(callId, {
              name: event.name,
              arguments: '',
              state: 'pending'
            });
          }
          const callState = this.functionCallStates.get(callId);
          callState.arguments += event.delta;
          break;

        case 'response.done':
          // Check for function calls in the response
          if (event.response && event.response.output) {
            for (const output of event.response.output) {
              if (output.type === 'function_call') {
                await this.handleFunctionCall(output);
              }
            }
          }
          
          // Notify client that response is complete
          this.emit('client-message', {
            type: 'status',
            data: { responseDone: true }
          });
          break;

        case 'error':
          this.emit('client-message', {
            type: 'error',
            data: { 
              message: event.error?.message || 'Unknown error',
              code: event.error?.code
            }
          });
          break;

        case 'rate_limits.updated':
          // Log rate limit info but don't forward to client
          console.log(`📊 Rate limits for ${this.userId}:`, event.rate_limits);
          break;
      }
    } catch (error) {
      console.error(`❌ Error handling OpenAI message for ${this.userId}:`, error);
      this.emit('error', { type: 'parse', message: error.message });
    }
  }

  async handleFunctionCall(functionCall) {
    const { call_id, name, arguments: args } = functionCall;
    
    // Check if already processed
    if (this.processedFunctionCalls.has(call_id)) {
      return;
    }
    
    this.processedFunctionCalls.add(call_id);
    
    console.log(`🔧 Executing function ${name} for user ${this.userId}`);
    
    // Import function handler
    const { RealtimeFunctionHandler } = require('./realtime-functions');
    const handler = new RealtimeFunctionHandler(this.userId);
    
    try {
      // Execute function
      const result = await handler.handleFunctionCall(name, args);
      
      // Send result back to OpenAI
      this.sendToOpenAI({
        type: 'conversation.item.create',
        item: {
          type: 'function_call_output',
          call_id: call_id,
          output: result
        }
      });
      
      // Request response after function output
      this.sendToOpenAI({
        type: 'response.create'
      });
      
      // Notify client
      this.emit('client-message', {
        type: 'function',
        data: {
          name: name,
          executed: true,
          result: JSON.parse(result)
        }
      });
    } catch (error) {
      console.error(`❌ Function execution error for ${this.userId}:`, error);
      
      // Send error as function output
      this.sendToOpenAI({
        type: 'conversation.item.create',
        item: {
          type: 'function_call_output',
          call_id: call_id,
          output: JSON.stringify({
            error: true,
            message: error.message
          })
        }
      });
    }
  }

  sendToOpenAI(event) {
    if (!this.isConnected || !this.openAIWs) {
      console.error(`❌ Cannot send to OpenAI - not connected (${this.userId})`);
      return;
    }

    try {
      this.openAIWs.send(JSON.stringify(event));
      
      if (process.env.DEBUG === 'true') {
        console.log(`📤 Sent to OpenAI (${this.userId}):`, event.type);
      }
    } catch (error) {
      console.error(`❌ Error sending to OpenAI (${this.userId}):`, error);
      this.emit('error', { type: 'send', message: error.message });
    }
  }

  handleClientMessage(message) {
    try {
      const { type, data } = message;

      switch (type) {
        case 'session.config':
          this.configureSession(data);
          break;

        case 'audio.append':
          this.sendToOpenAI({
            type: 'input_audio_buffer.append',
            audio: data.audio
          });
          break;

        case 'audio.commit':
          this.sendToOpenAI({
            type: 'input_audio_buffer.commit'
          });
          break;

        case 'text.send':
          this.sendToOpenAI({
            type: 'conversation.item.create',
            item: {
              type: 'message',
              role: 'user',
              content: [{
                type: 'input_text',
                text: data.text
              }]
            }
          });
          // Request response after text input
          this.sendToOpenAI({
            type: 'response.create'
          });
          break;

        case 'interrupt':
          this.sendToOpenAI({
            type: 'response.cancel'
          });
          break;

        case 'response.create':
          this.sendToOpenAI({
            type: 'response.create'
          });
          break;

        default:
          console.warn(`⚠️ Unknown client message type: ${type}`);
      }
    } catch (error) {
      console.error(`❌ Error handling client message (${this.userId}):`, error);
      this.emit('error', { type: 'client-message', message: error.message });
    }
  }

  configureSession(config) {
    const { conversationId, history, voice = 'shimmer', temperature = 0.6 } = config;

    // Build instructions from chat history
    let instructions = `You are a helpful assistant. Be concise and natural.
When users ask you to create tasks or reminders, do so efficiently.`;

    if (history && history.length > 0) {
      instructions += '\n\nPrevious conversation context:\n';
      for (const msg of history.slice(-10)) { // Last 10 messages
        const role = msg.isFromUser ? 'User' : 'Assistant';
        instructions += `${role}: ${msg.content}\n`;
      }
      instructions += '\nContinue the conversation naturally based on this context.';
    }

    // Import function definitions
    const { getToolDefinitions } = require('./realtime-functions');
    const tools = getToolDefinitions();

    // Send session update
    this.sendToOpenAI({
      type: 'session.update',
      session: {
        instructions: instructions,
        voice: voice,
        temperature: temperature,
        input_audio_format: 'pcm16',
        output_audio_format: 'pcm16',
        input_audio_transcription: {
          model: 'whisper-1'
        },
        turn_detection: {
          type: 'server_vad',
          threshold: 0.5,
          prefix_padding_ms: 300,
          silence_duration_ms: 200
        },
        tools: tools,
        tool_choice: 'auto'
      }
    });

    console.log(`✅ Session configured for user ${this.userId} with ${tools.length} tools`);
  }

  disconnect() {
    if (this.openAIWs) {
      this.openAIWs.close();
      this.openAIWs = null;
    }
    this.isConnected = false;
    this.functionCallStates.clear();
    this.processedFunctionCalls.clear();
  }
}

module.exports = RealtimeProxy;