# OpenAI Realtime API Implementation Guide for Swift

## Key Implementation Facts for LLM

### 1. Core Architecture
- **Protocol**: WebSocket (primary) or WebRTC (for browser-based clients)
- **Endpoint**: `wss://api.openai.com/v1/realtime` (WebSocket)
- **Model**: `gpt-4o-realtime-preview` or `gpt-4o-realtime-preview-2024-12-17`
- **Max Session Duration**: 30 minutes
- **Authentication**: Bearer token with OpenAI API key

### 2. Swift Library (swift-realtime-openai)
```swift
// Installation via SPM
.package(url: "https://github.com/m1guelpf/swift-realtime-openai.git", .branch("main"))
```

### 3. Session Configuration
```swift
// Key session properties that can be updated
session.instructions = "System prompt"
session.voice = .alloy // Options: alloy, ash, ballad, coral, echo, sage, shimmer, verse
session.temperature = 0.8
session.inputAudioTranscription = Session.InputAudioTranscription()
session.modalities = ["text", "audio"]
session.inputAudioFormat = "pcm16" // 16-bit PCM, 24kHz, mono
session.outputAudioFormat = "pcm16"
```

### 4. Function Calling Implementation

#### 4.1 Define Functions in Session
```swift
try await conversation.updateSession { session in
    session.tools = [
        Session.Tool(
            type: "function",
            function: Session.Tool.Function(
                name: "create_task",
                description: "Create a new task",
                parameters: [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "Task title"
                        ]
                    ],
                    "required": ["title"]
                ]
            )
        )
    ]
    session.tool_choice = "auto" // or "none", "required", or specific function
}
```

#### 4.2 Function Call Event Flow
1. **Model decides to call function** → Emits `response.function_call_arguments.delta`
2. **Complete call info** → Available in `response.done` event
3. **Execute function** → Run your custom code
4. **Return result** → Send `conversation.item.create` with `function_call_output` type

### 5. Critical Event Types

#### Client Events (You Send)
```javascript
// Key events to send
{
    type: "session.update",        // Update session config
    type: "conversation.item.create", // Add user message or function output
    type: "response.create",        // Request model response
    type: "input_audio_buffer.append", // Stream audio chunks
    type: "input_audio_buffer.commit", // Finalize audio input
    type: "input_audio_buffer.clear"  // Clear audio buffer
}
```

#### Server Events (You Receive)
```javascript
// Key events to handle
{
    type: "session.created",       // Session ready
    type: "session.updated",       // Config updated
    type: "response.created",      // Response started
    type: "response.done",         // Response complete (contains function calls!)
    type: "response.function_call_arguments.delta", // Streaming function args
    type: "response.audio.delta",  // Audio chunks
    type: "response.text.delta",   // Text chunks
    type: "input_audio_buffer.speech_started",
    type: "input_audio_buffer.speech_stopped"
}
```

### 6. Audio Format Specifications
- **Input**: PCM16 (16-bit), 24kHz, mono, little-endian
- **Output**: PCM16 (16-bit), 24kHz, mono, little-endian
- **Base64 Encoding**: Required for WebSocket audio transmission
- **Chunk Size**: Max 15MB per chunk

### 7. Voice Activity Detection (VAD)
```swift
// VAD is enabled by default
session.turn_detection = Session.TurnDetection(
    type: "server_vad",
    threshold: 0.5,
    prefix_padding_ms: 300,
    silence_duration_ms: 200,
    create_response: true  // Auto-respond when speech stops
)

// Disable VAD for push-to-talk
session.turn_detection = nil
```

### 8. Function Call Response Format
```json
{
    "type": "response.done",
    "response": {
        "output": [{
            "type": "function_call",
            "name": "create_task",
            "call_id": "call_abc123",
            "arguments": "{\"title\":\"Buy milk\"}"
        }]
    }
}
```

### 9. Function Output Format
```json
{
    "type": "conversation.item.create",
    "item": {
        "type": "function_call_output",
        "call_id": "call_abc123",
        "output": "{\"success\":true,\"taskId\":\"task_123\"}"
    }
}
```

### 10. Implementation Challenges & Solutions

#### Challenge 1: Swift Library Function Support
The swift-realtime-openai library may not fully expose the `tools` property yet. 

**Solution**: 
- Check if library has been updated to support `Session.Tool` type
- If not, consider:
  1. Forking and adding tool support
  2. Using raw WebSocket connection for full control
  3. Including function info in instructions as workaround

#### Challenge 2: Event Observation
The Conversation class might not expose all server events directly.

**Solution**:
```swift
// Monitor conversation.entries for function call items
for entry in conversation.entries {
    if case let .functionCall(fc) = entry {
        // Handle function call
    }
}
```

#### Challenge 3: Sending Function Results
The library might not have a direct method to send function call outputs.

**Solution**:
```swift
// Option 1: Check if library supports it
try await conversation.sendFunctionOutput(callId: "...", output: "...")

// Option 2: Send as raw event if WebSocket is exposed
let event = [
    "type": "conversation.item.create",
    "item": [
        "type": "function_call_output",
        "call_id": callId,
        "output": result
    ]
]
```

### 11. Best Practices

1. **Session Lifecycle**
   - Configure session immediately after connection
   - Voice cannot be changed after first audio output
   - Keep sessions under 30 minutes

2. **Function Calling**
   - Always validate function arguments
   - Return structured JSON responses
   - Handle errors gracefully in function output

3. **Audio Handling**
   - Use WebRTC for browser clients (better network resilience)
   - Buffer audio appropriately for smooth playback
   - Handle interruptions cleanly

4. **Error Handling**
   - Listen for error events
   - Implement reconnection logic
   - Cache API keys securely

### 12. Testing Function Calls

```swift
// Test phrases that should trigger functions:
"Create a task to buy groceries"
"Add a reminder to call mom"
"List all my tasks"
"Mark the grocery task as complete"
"Delete the task about calling mom"
```

### 13. Debugging Tips

1. **Log all events**: Print both client and server events
2. **Check entry types**: `conversation.entries` contains various types
3. **Monitor raw responses**: Function calls appear in `response.done`
4. **Validate JSON**: Ensure function arguments and outputs are valid JSON
5. **Use unique call IDs**: Track processed functions to avoid duplicates

### 14. Required Modifications for Full Implementation

1. **Update Session Configuration** (VoiceAIManager.swift:88-116)
   - Properly set `session.tools` array with function definitions
   - Remove workaround instructions

2. **Improve Function Call Detection** (VoiceAIManager.swift:195-439)
   - Listen for proper function call events
   - Remove text parsing workarounds

3. **Fix Function Result Submission** (VoiceAIManager.swift:441-470)
   - Send proper `function_call_output` items
   - Don't send as user messages

4. **Add Missing Event Handlers**
   - Handle `response.function_call_arguments.delta`
   - Process `response.done` for function calls
   - Listen for `conversation.item.created` confirmations

### 15. Alternative Implementation (Raw WebSocket)

If the Swift library doesn't support functions yet:

```swift
class RealtimeWebSocket {
    private var webSocket: URLSessionWebSocketTask?
    
    func connect(apiKey: String) {
        let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket?.resume()
        receiveMessage()
    }
    
    func sendEvent(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let string = String(data: data, encoding: .utf8) else { return }
        
        let message = URLSessionWebSocketTask.Message.string(string)
        webSocket?.send(message) { _ in }
    }
    
    func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleServerEvent(text)
                default:
                    break
                }
            case .failure(let error):
                print("WebSocket error: \(error)")
            }
            self?.receiveMessage() // Continue listening
        }
    }
}
```

## Summary

The OpenAI Realtime API enables real-time voice and text interactions with function calling capabilities. The key to implementation is properly configuring the session with tools, listening for function call events in server responses, executing the functions, and returning results in the correct format. The swift-realtime-openai library simplifies WebSocket management but may require updates or workarounds for full function calling support.