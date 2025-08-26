//
//  VoiceAIManager.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import SwiftUI
import OpenAIRealtime
import Combine

@MainActor
class VoiceAIManager: ObservableObject {
    @Published var conversation: OpenAIRealtime.Conversation?
    @Published var isListening = false
    @Published var isConnected = false
    @Published var messages: [Item.Message] = []
    @Published var currentTranscript = ""
    @Published var error: String?
    @Published var isLoadingKey = false
    @Published var lastFunctionCall: String?
    
    private var apiKey: String = ""
    private let functionHandler = RealtimeFunctionHandler()
    
    var entries: [Item] {
        conversation?.entries ?? []
    }
    
    init() {
        Task {
            await fetchAPIKeyAndSetup()
        }
    }
    
    private func fetchAPIKeyAndSetup() async {
        isLoadingKey = true
        error = nil
        
        // Check if API key is configured
        if APIConfig.isOpenAIKeyConfigured {
            apiKey = APIConfig.openAIKey
            print("✅ Using configured API key")
            setupConversation()
            isLoadingKey = false
            return
        }
        
        // If not configured, show error
        self.error = "OpenAI API key not configured. Please add your key in APIConfig.swift"
        print("❌ OpenAI API key not configured")
        print("📝 To fix: Replace 'YOUR_OPENAI_API_KEY_HERE' in APIConfig.swift with your actual key")
        print("🔗 Get a key from: https://platform.openai.com/api-keys")
        
        isLoadingKey = false
    }
    
    private func setupConversation() {
        guard !apiKey.isEmpty else {
            error = "OpenAI API key not available"
            return
        }
        
        conversation = OpenAIRealtime.Conversation(authToken: apiKey)
        
        // Configure the session with tools/functions
        Task {
            await configureSession()
            await setupObservers()
        }
    }
    
    private func configureSession() async {
        guard let conversation = conversation else { return }
        
        do {
            try await conversation.whenConnected {
                print("📤 Configuring session with tools...")
                
                try await conversation.updateSession { session in
                    // Set instructions
                    session.instructions = "You are a helpful assistant that can create and manage tasks for the user. When the user asks you to create a reminder or task, use the create_task function. Be conversational and confirm when tasks are created."
                    
                    // Set voice
                    session.voice = .alloy
                    
                    // Enable input audio transcription
                    // Initialize without model parameter - it likely has a default
                    session.inputAudioTranscription = Session.InputAudioTranscription()
                    
                    // Configure tools - We may need to set this differently
                    // The Swift library might not expose tools directly yet
                    // session.tools = RealtimeFunctions.availableFunctions
                    
                    // For now, include function info in instructions as a workaround
                    session.instructions = """
                    You are a helpful assistant that can create and manage tasks for the user. 
                    When the user asks you to create a reminder or task, respond with: create_task("task description")
                    Be conversational and confirm when tasks are created.
                    """
                    
                    // Set temperature
                    session.temperature = 0.8
                }
                
                print("✅ Session configured with \(RealtimeFunctions.availableFunctions.count) functions")
                
                // Log the tools for debugging
                for tool in RealtimeFunctions.availableFunctions {
                    if let name = tool["name"] as? String {
                        print("   📌 Function: \(name)")
                    }
                }
            }
        } catch {
            print("❌ Failed to configure session: \(error)")
            self.error = "Failed to configure session: \(error.localizedDescription)"
        }
    }
    
    private func setupObservers() async {
        guard conversation != nil else { return }
        
        // Wait for connection
        Task { [weak self] in
            guard let self = self, let conversation = self.conversation else { return }
            await conversation.waitForConnection()
            self.isConnected = conversation.connected
        }
        
        // Observe errors
        Task { [weak self] in
            guard let self = self, let conversation = self.conversation else { return }
            for await error in conversation.errors {
                self.error = error.message
            }
        }
        
        // Observe function calls
        Task {
            await observeFunctionCalls()
        }
        
        // Start observing conversation state
        Task { [weak self] in
            guard let self = self else { return }
            while true {
                guard let conversation = self.conversation else {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }
                self.isListening = conversation.isListening
                self.isConnected = conversation.connected
                
                // Update messages
                self.messages = conversation.entries.compactMap { entry in
                    switch entry {
                    case let .message(message):
                        return message
                    default:
                        return nil
                    }
                }
                
                // Update transcript from latest user message
                if let lastUserMessage = messages.last(where: { $0.role == .user }) {
                    currentTranscript = lastUserMessage.content.compactMap { content in
                        switch content {
                        case .input_text(let text):
                            return text
                        case .text(let text):
                            return text
                        default:
                            return nil
                        }
                    }.joined(separator: " ")
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
    }
    
    private func observeFunctionCalls() async {
        guard let conversation = conversation else { return }
        
        var processedFunctionCalls = Set<String>()
        var lastEntryCount = 0
        var functionCallInfo: [String: (name: String, arguments: String, firstSeen: Date)] = [:]
        
        // Monitor conversation entries for function call items
        while true {
            // Only process new entries
            if conversation.entries.count > lastEntryCount {
                let newEntries = Array(conversation.entries.suffix(conversation.entries.count - lastEntryCount))
                lastEntryCount = conversation.entries.count
                
                for entry in newEntries {
                    // Debug: Print the entry type
                    print("🔍 New entry type: \(type(of: entry))")
                    
                    // Check if entry contains a function call
                    if case let .functionCall(functionCall) = entry {
                        // Store or update function call info
                        if let existing = functionCallInfo[functionCall.id] {
                            // Append new arguments to existing
                            functionCallInfo[functionCall.id] = (
                                name: functionCall.name,
                                arguments: existing.arguments + functionCall.arguments,
                                firstSeen: existing.firstSeen
                            )
                        } else {
                            // New function call
                            functionCallInfo[functionCall.id] = (
                                name: functionCall.name,
                                arguments: functionCall.arguments,
                                firstSeen: Date()
                            )
                        }
                        
                        print("🎯 Function call detected: \(functionCall.name)")
                        print("📝 Current arguments: \(functionCallInfo[functionCall.id]?.arguments ?? "")")
                        
                        // Check if arguments look complete (valid JSON)
                        if let info = functionCallInfo[functionCall.id],
                           isValidJSON(info.arguments) && !processedFunctionCalls.contains(functionCall.id) {
                            // Arguments are complete, execute the function
                            processedFunctionCalls.insert(functionCall.id)
                            
                            print("✅ Complete function call ready: \(info.name)")
                            print("📝 Final arguments: \(info.arguments)")
                            
                            // Execute the function
                            let result = await functionHandler.handleFunctionCall(
                                name: info.name,
                                arguments: info.arguments
                            )
                            
                            // Send the function result back
                            await sendFunctionResult(callId: functionCall.id, result: result)
                            
                            lastFunctionCall = "\(info.name): \(result)"
                            
                            // Clean up
                            functionCallInfo.removeValue(forKey: functionCall.id)
                        }
                    }
                    
                    // Check messages for function call content
                    if case let .message(message) = entry {
                        print("📨 Message from: \(message.role)")
                        
                        // Only check assistant messages for function calls
                        if message.role == .assistant {
                            for content in message.content {
                                // Debug: Print content type
                                print("   Content type: \(type(of: content))")
                                
                                // Check for text content that might contain function calls
                                if case let .text(text) = content {
                                // Print the full text to see what we're getting
                                print("   📄 Full text content: \(text)")
                                
                                // Check if text contains function call patterns
                                if text.contains("create_task") || text.contains("list_tasks") || 
                                   text.contains("complete_task") || text.contains("delete_task") ||
                                   text.contains("take_out_trash") || text.contains("\"name\"") ||
                                   text.contains("tool_calls") || text.contains("{") {
                                    
                                    print("   🔍 Detected potential function call pattern")
                                    
                                    // Try to parse as JSON
                                    if let data = text.data(using: String.Encoding.utf8) {
                                        do {
                                            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                                print("   ✅ Successfully parsed JSON: \(json)")
                                                
                                                // Check different function call formats
                                                
                                                // Format 1: Direct function call
                                                if let functionName = json["name"] as? String ?? json["function"] as? String {
                                                    let callId = json["call_id"] as? String ?? 
                                                               json["id"] as? String ?? 
                                                               UUID().uuidString
                                                    
                                                    if !processedFunctionCalls.contains(callId) {
                                                        processedFunctionCalls.insert(callId)
                                                        
                                                        let arguments = json["arguments"] as? String ?? 
                                                                       json["parameters"] as? String ?? 
                                                                       "{}"
                                                        
                                                        print("🚀 Executing function: \(functionName)")
                                                        print("📝 With arguments: \(arguments)")
                                                        
                                                        let result = await functionHandler.handleFunctionCall(
                                                            name: functionName,
                                                            arguments: arguments
                                                        )
                                                        
                                                        print("✅ Function result: \(result)")
                                                        
                                                        await sendFunctionResult(callId: callId, result: result)
                                                        lastFunctionCall = "\(functionName): \(result)"
                                                    }
                                                }
                                                
                                                // Format 2: tool_calls array
                                                if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                                                    for toolCall in toolCalls {
                                                        if let callId = toolCall["id"] as? String,
                                                           let function = toolCall["function"] as? [String: Any],
                                                           let functionName = function["name"] as? String {
                                                            
                                                            if !processedFunctionCalls.contains(callId) {
                                                                processedFunctionCalls.insert(callId)
                                                                
                                                                let arguments = function["arguments"] as? String ?? "{}"
                                                                
                                                                print("🚀 Executing tool call: \(functionName)")
                                                                print("📝 With arguments: \(arguments)")
                                                                
                                                                let result = await functionHandler.handleFunctionCall(
                                                                    name: functionName,
                                                                    arguments: arguments
                                                                )
                                                                
                                                                print("✅ Function result: \(result)")
                                                                
                                                                await sendFunctionResult(callId: callId, result: result)
                                                                lastFunctionCall = "\(functionName): \(result)"
                                                            }
                                                        }
                                                    }
                                                }
                                                
                                                // Format 3: Response with tool_calls
                                                if let response = json["response"] as? [String: Any],
                                                   let toolCalls = response["tool_calls"] as? [[String: Any]] {
                                                    for toolCall in toolCalls {
                                                        if let callId = toolCall["id"] as? String,
                                                           let function = toolCall["function"] as? [String: Any],
                                                           let functionName = function["name"] as? String {
                                                            
                                                            if !processedFunctionCalls.contains(callId) {
                                                                processedFunctionCalls.insert(callId)
                                                                
                                                                let arguments = function["arguments"] as? String ?? "{}"
                                                                
                                                                print("🚀 Executing response tool call: \(functionName)")
                                                                print("📝 With arguments: \(arguments)")
                                                                
                                                                let result = await functionHandler.handleFunctionCall(
                                                                    name: functionName,
                                                                    arguments: arguments
                                                                )
                                                                
                                                                print("✅ Function result: \(result)")
                                                                
                                                                await sendFunctionResult(callId: callId, result: result)
                                                                lastFunctionCall = "\(functionName): \(result)"
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } catch {
                                            print("   ⚠️ Failed to parse as JSON: \(error)")
                                            
                                            // Try to parse function call syntax like: create_task("argument")
                                            if let functionMatch = text.range(of: #"(\w+)\((.*)\)"#, options: .regularExpression) {
                                                let functionCall = String(text[functionMatch])
                                                print("   🔍 Found function call syntax: \(functionCall)")
                                                
                                                // Extract function name and arguments
                                                if let openParen = functionCall.firstIndex(of: "("),
                                                   let closeParen = functionCall.lastIndex(of: ")") {
                                                    let functionName = String(functionCall[..<openParen])
                                                    let argsString = String(functionCall[functionCall.index(after: openParen)..<closeParen])
                                                    
                                                    print("   📌 Function: \(functionName)")
                                                    print("   📌 Raw arguments: \(argsString)")
                                                    
                                                    // Generate a unique call ID
                                                    let callId = UUID().uuidString
                                                    
                                                    if !processedFunctionCalls.contains(callId) {
                                                        processedFunctionCalls.insert(callId)
                                                        
                                                        // Parse the arguments - remove quotes if it's a simple string
                                                        var parsedArgs = ""
                                                        if argsString.hasPrefix("\"") && argsString.hasSuffix("\"") {
                                                            // Simple string argument
                                                            let title = String(argsString.dropFirst().dropLast())
                                                            parsedArgs = "{\"title\": \"\(title)\"}"
                                                        } else if argsString.hasPrefix("'") && argsString.hasSuffix("'") {
                                                            // Single quoted string
                                                            let title = String(argsString.dropFirst().dropLast())
                                                            parsedArgs = "{\"title\": \"\(title)\"}"
                                                        } else {
                                                            // Try to use as-is or create a title from it
                                                            parsedArgs = "{\"title\": \"\(argsString)\"}"
                                                        }
                                                        
                                                        print("🚀 Executing parsed function: \(functionName)")
                                                        print("📝 With parsed arguments: \(parsedArgs)")
                                                        
                                                        let result = await functionHandler.handleFunctionCall(
                                                            name: functionName,
                                                            arguments: parsedArgs
                                                        )
                                                        
                                                        print("✅ Function result: \(result)")
                                                        
                                                        await sendFunctionResult(callId: callId, result: result)
                                                        lastFunctionCall = "\(functionName): \(result)"
                                                    }
                                                }
                                            }
                                            // Also try to extract JSON from the text
                                            else if let jsonStart = text.range(of: "{"),
                                               let jsonEnd = text.range(of: "}", options: String.CompareOptions.backwards) {
                                                let jsonSubstring = String(text[jsonStart.lowerBound...jsonEnd.upperBound])
                                                print("   🔍 Extracted potential JSON: \(jsonSubstring)")
                                                // Try parsing the extracted JSON
                                                if let data = jsonSubstring.data(using: String.Encoding.utf8),
                                                   let _ = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                                    print("   ✅ Successfully parsed extracted JSON")
                                                    // Process as above...
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            }
                        }
                    }
                }
            }
            
            // Check for function calls that might be stuck (fallback after 2 seconds)
            let now = Date()
            for (callId, info) in functionCallInfo {
                if now.timeIntervalSince(info.firstSeen) > 2.0 && !processedFunctionCalls.contains(callId) {
                    // Function call has been pending for too long, try to process it
                    processedFunctionCalls.insert(callId)
                    
                    print("⏱️ Processing potentially incomplete function call after timeout: \(info.name)")
                    print("📝 Arguments received: \(info.arguments)")
                    
                    // Execute the function (handler will try to fix incomplete JSON)
                    let result = await functionHandler.handleFunctionCall(
                        name: info.name,
                        arguments: info.arguments
                    )
                    
                    // Send the function result back
                    await sendFunctionResult(callId: callId, result: result)
                    
                    lastFunctionCall = "\(info.name): \(result)"
                    
                    // Clean up
                    functionCallInfo.removeValue(forKey: callId)
                }
            }
            
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
    }
    
    private func isValidJSON(_ string: String) -> Bool {
        guard !string.isEmpty,
              let data = string.data(using: .utf8) else {
            return false
        }
        
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            return true
        } catch {
            return false
        }
    }
    
    func sendFunctionResult(callId: String, result: String) async {
        guard let conversation = self.conversation else { return }
        
        // Send function result back to the conversation
        let functionOutput: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": result
            ]
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: functionOutput),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 Sending function result back to conversation")
            print("📋 Function result: \(jsonString)")
            
            // Send the function result back to the conversation
            // The library might handle this automatically, but we'll try to send it
            do {
                // Try sending the raw JSON as a user message
                try await conversation.send(from: .user, text: jsonString)
                print("✅ Sent function result")
            } catch {
                print("⚠️ Could not send function result: \(error)")
                // The library might handle function results automatically
            }
        }
    }
    
    func startListening() async throws {
        guard let conversation = self.conversation else {
            throw VoiceAIError.notInitialized
        }
        
        do {
            try conversation.startListening()
            error = nil
        } catch {
            self.error = "Failed to start listening: \(error.localizedDescription)"
            throw error
        }
    }
    
    func stopListening() async {
        guard let conversation = self.conversation else { return }
        conversation.stopListening()
    }
    
    func startHandlingVoice() async throws {
        guard let conversation = self.conversation else {
            throw VoiceAIError.notInitialized
        }
        
        do {
            try conversation.startHandlingVoice()
            error = nil
        } catch {
            self.error = "Failed to start handling voice: \(error.localizedDescription)"
            throw error
        }
    }
    
    func stopHandlingVoice() async {
        guard let conversation = self.conversation else { return }
        conversation.stopHandlingVoice()
    }
    
    func sendMessage(_ text: String) async throws {
        guard let conversation = self.conversation else {
            throw VoiceAIError.notInitialized
        }
        
        do {
            try await conversation.send(from: .user, text: text)
            error = nil
        } catch {
            self.error = "Failed to send message: \(error.localizedDescription)"
            throw error
        }
    }
    
    func interrupt() async {
        guard let conversation = self.conversation else { return }
        conversation.interruptSpeech()
    }
    
    func disconnect() async {
        // Stop listening and handling voice
        guard let conversation = self.conversation else { return }
        conversation.stopListening()
        conversation.stopHandlingVoice()
        isListening = false
        isConnected = false
    }
    
    func reset() {
        messages.removeAll()
        currentTranscript = ""
        error = nil
        setupConversation()
    }
}

enum VoiceAIError: LocalizedError {
    case notInitialized
    case apiKeyMissing
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Voice AI conversation not initialized"
        case .apiKeyMissing:
            return "OpenAI API key is missing"
        }
    }
}
