# Implementing response.done Event Handling

## The Problem
Currently, we're trying to detect function calls by monitoring `conversation.entries` and accumulating streaming arguments. This is fragile because:
- Arguments come in chunks and get truncated
- We have to guess when streaming is complete
- We're using timeouts and JSON validation as workarounds

## The Solution: response.done Events
The OpenAI Realtime API sends a `response.done` event when the model has COMPLETELY finished generating a response, including function calls with complete arguments.

## Library Support
The `swift-realtime-openai` library DOES have `response.done` support! We can see `.responseDone` case in the ServerEvent enum.

## Implementation Approach

### Option 1: Use RealtimeAPI Directly
Instead of using the high-level `Conversation` wrapper, use `RealtimeAPI` directly:

```swift
import OpenAIRealtime

class VoiceAIManager {
    private var realtimeAPI: RealtimeAPI?
    
    func setupRealtimeAPI() async {
        let api = RealtimeAPI.webSocket(authToken: apiKey)
        self.realtimeAPI = api
        
        // Listen for events
        for await event in api.events {
            switch event {
            case .responseDone(let event):
                await handleResponseDone(event)
            case .sessionCreated(let event):
                print("Session created: \(event.session.id)")
            default:
                break
            }
        }
    }
    
    func handleResponseDone(_ event: ResponseDoneEvent) async {
        print("🎉 response.done received!")
        
        // Check for function calls in the response
        for item in event.response.output {
            if item.type == "function_call" {
                print("🎯 Complete function call: \(item.name)")
                print("📝 Final arguments: \(item.arguments)")
                
                // Execute function with COMPLETE arguments
                let result = await functionHandler.handleFunctionCall(
                    name: item.name,
                    arguments: item.arguments
                )
                
                // Send result back
                await api.send(event: .conversationItemCreate(
                    item: .functionCallOutput(
                        callId: item.callId,
                        output: result
                    )
                ))
            }
        }
    }
}
```

### Option 2: Extend Conversation Class
Check if `Conversation` exposes the underlying API or events:

```swift
// If Conversation has an api property:
if let api = conversation.api {
    for await event in api.events {
        // Handle events
    }
}

// Or if Conversation itself exposes events:
for await event in conversation.events {
    // Handle events  
}
```

### Option 3: Fork and Modify Library
If the `Conversation` class doesn't expose events, we could:
1. Fork `swift-realtime-openai`
2. Add an `events` property to `Conversation`
3. Expose the underlying `RealtimeAPI.events` stream

## Benefits of response.done

1. **Complete Arguments**: Function arguments are guaranteed to be complete
2. **No Truncation**: No more "walk the dog" getting cut to "walk the"
3. **No Timeouts**: No need for arbitrary 5-second waits
4. **Proper Event Flow**: Following OpenAI's intended architecture
5. **Clean Code**: Remove all the JSON fixing and buffering workarounds

## Next Steps

1. **Test RealtimeAPI directly**: Try using `RealtimeAPI` instead of `Conversation`
2. **Check Conversation source**: See if it exposes the event stream
3. **Fork if needed**: Add event exposure to `Conversation` class

## Example Event Structure

```json
{
  "type": "response.done",
  "event_id": "event_abc123",
  "response": {
    "id": "resp_001",
    "status": "completed",
    "output": [
      {
        "id": "item_fc_001",
        "type": "function_call",
        "status": "completed",
        "name": "create_task",
        "call_id": "call_xyz",
        "arguments": "{\"title\":\"walk the dog tomorrow\"}"
      }
    ]
  }
}
```

With `response.done`, we get the COMPLETE function call with all arguments intact!