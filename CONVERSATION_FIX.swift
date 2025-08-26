// Add this to Conversation.swift handleEvent method around line 380:

case let .responseDone(event):
    print("🎉 response.done received in Conversation")
    
    // Process function calls with COMPLETE arguments
    for item in event.response.output {
        if case .functionCall(let functionCall) = item {
            // Add to entries if not already there
            if !entries.contains(where: { 
                if case .functionCall(let fc) = $0 {
                    return fc.id == functionCall.id
                }
                return false
            }) {
                entries.append(.functionCall(functionCall))
            }
        }
    }
    
    // Notify observers or trigger a callback
    // Could add a public callback property:
    // onResponseDone?(event.response)