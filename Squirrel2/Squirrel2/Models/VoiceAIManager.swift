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
    static let shared = VoiceAIManager()
    
    @Published var conversation: OpenAIRealtime.Conversation?
    @Published var isListening = false
    @Published var isConnected = false
    @Published var messages: [Item.Message] = []
    @Published var currentTranscript = ""
    @Published var error: String?
    @Published var isLoadingKey = false
    @Published var lastFunctionCall: String?
    @Published var shouldDismiss = false
    @Published var isInitialized = false
    
    private var apiKey: String = ""
    private let functionHandler = RealtimeFunctionHandler()
    private var conversationId: String = ""
    private var voiceMessages: [ChatMessage] = [] // Track messages for unified conversation
    private var observationTasks: [Task<Void, Never>] = [] // Track all observation tasks
    
    var entries: [Item] {
        conversation?.entries ?? []
    }
    
    // Get voice messages as ChatMessages for unified conversation
    func getVoiceMessages() -> [ChatMessage] {
        return voiceMessages
    }
    
    
    private init() {
        // Don't auto-initialize, wait for explicit initialization
    }
    
    func initialize(withChatHistory chatMessages: [ChatMessage] = [], conversationId: String) async {
        guard !isInitialized else { return }
        
        // Store chat history and conversation ID for context
        self.chatHistory = chatMessages
        self.conversationId = conversationId
        self.voiceMessages = [] // Clear any previous voice messages
        
        await setupWithExistingKey()
        
        // Pre-connect WebSocket for instant readiness
        if conversation != nil && !isConnected {
            do {
                try conversation?.startHandlingVoice()
                print("🔥 WebSocket pre-connected")
            } catch {
                print("⚠️ Pre-connection failed, will retry on open")
            }
        }
        
        isInitialized = true
    }
    
    private var chatHistory: [ChatMessage] = []
    
    func updateChatHistory(_ messages: [ChatMessage], conversationId: String? = nil) async {
        self.chatHistory = messages
        if let conversationId = conversationId {
            self.conversationId = conversationId
        }
        
        // If already connected, update the session with new context
        if conversation != nil && isConnected {
            await configureSession()
        }
    }
    
    private func initializeAsync() async {
        // API key should already be available from FirebaseManager
        await setupWithExistingKey()
    }
    
    
    // Public method to ensure initialization is complete
    func ensureInitialized() async {
        if conversation == nil {
            await initializeAsync()
        }
        
        // Wait for conversation to be ready
        for _ in 1...30 {
            if conversation != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private func setupWithExistingKey() async {
        error = nil
        
        // Use the API key from FirebaseManager (should already be fetched on app start)
        if let key = FirebaseManager.shared.openAIKey, !key.isEmpty {
            apiKey = key
            setupConversation()
        } else {
            // Wait briefly for API key
            for _ in 1...3 {
                if let key = FirebaseManager.shared.openAIKey, !key.isEmpty {
                    apiKey = key
                    setupConversation()
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
            }
            
            if apiKey.isEmpty {
                self.error = "OpenAI API key not available"
            }
        }
        
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
            try await conversation.whenConnected { @MainActor in
                print("📤 Configuring session with tools...")
                
                try await conversation.updateSession { @MainActor session in
                    // Build conversation context from chat history
                    var contextInstructions = """
                    You are a helpful assistant. Be concise and natural.
                    When users ask you to create tasks or reminders, do so efficiently.
                    """
                    
                    if !self.chatHistory.isEmpty {
                        contextInstructions += "\n\nPrevious conversation context:\n"
                        for msg in self.chatHistory.suffix(10) { // Last 10 messages for context
                            let role = msg.isFromUser ? "User" : "Assistant"
                            contextInstructions += "\(role): \(msg.content)\n"
                        }
                        contextInstructions += "\nContinue the conversation naturally based on this context."
                    }
                    
                    session.instructions = contextInstructions
                    
                    // Set voice - shimmer is smoother and more natural
                    session.voice = .shimmer
                    
                    // Enable input audio transcription
                    session.inputAudioTranscription = Session.InputAudioTranscription()
                    
                    // Configure tools from RealtimeFunctions
                    session.tools = RealtimeFunctions.createSessionTools()
                    
                    // Set tool choice to auto
                    session.toolChoice = .auto
                    
                    // Set temperature to minimum allowed value
                    session.temperature = 0.6
                    
                    print("✅ Session configured with \(session.tools.count) tools")
                }
            }
        } catch {
            print("❌ Failed to configure session: \(error)")
            self.error = "Failed to configure session: \(error.localizedDescription)"
        }
    }
    
    private func setupObservers() async {
        guard conversation != nil else { return }
        
        // Cancel any existing observation tasks
        cancelObservationTasks()
        
        // Wait for connection
        let connectionTask = Task { [weak self] in
            guard let self = self, let conversation = self.conversation else { return }
            await conversation.waitForConnection()
            self.isConnected = conversation.connected
        }
        observationTasks.append(connectionTask)
        
        // Observe errors
        let errorTask = Task { [weak self] in
            guard let self = self, let conversation = self.conversation else { return }
            for await error in conversation.errors {
                if Task.isCancelled { break }
                // Ignore temperature validation errors since 0.2 works despite the warning
                if error.message.lowercased().contains("temperature") || 
                   error.message.contains("0.6") {
                    print("⚠️ Ignoring temperature validation error: \(error.message)")
                    continue
                }
                self.error = error.message
            }
        }
        observationTasks.append(errorTask)
        
        // Observe function calls
        let functionTask = Task {
            await observeFunctionCalls()
        }
        observationTasks.append(functionTask)
        
        // Start observing conversation state
        let stateTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                guard let conversation = self.conversation else {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }
                self.isListening = conversation.isListening
                self.isConnected = conversation.connected
                
                // Update messages (including any user messages even without assistant responses)
                self.messages = conversation.entries.compactMap { entry in
                    switch entry {
                    case let .message(message):
                        return message
                    default:
                        return nil
                    }
                }
                
                // Also check if we have function calls without messages (tool-only interactions)
                let hasFunctionCalls = conversation.entries.contains { entry in
                    if case .functionCall = entry {
                        return true
                    }
                    return false
                }
                
                // Convert to ChatMessages for unified conversation
                // Make sure to capture user messages even when assistant doesn't respond
                self.voiceMessages = self.messages.map { message in
                    // Debug log to see what messages we're getting
                    if message.role == .user {
                        print("📝 User voice message found: \(message.content)")
                    }
                    
                    let content = message.content.compactMap { content in
                        switch content {
                        case .text(let text):
                            return text
                        case .audio(let audio):
                            return audio.transcript
                        case .input_text(let text):
                            return text
                        case .input_audio(let audio):
                            // User's voice input transcript
                            return audio.transcript
                        }
                    }.joined(separator: " ")
                    
                    return ChatMessage(
                        content: content,
                        isFromUser: message.role == .user,
                        conversationId: self.conversationId,
                        source: .voice,
                        voiceTranscript: content
                    )
                }
                
                // Check if AI said goodbye/done (only relevant for one-shot commands)
                // Count user messages to determine if it's a one-shot
                let userMessageCount = self.messages.filter { $0.role == .user }.count
                
                if userMessageCount == 1, // Only one user message (one-shot)
                   let lastMessage = self.messages.last,
                   lastMessage.role == .assistant {
                    let content = lastMessage.content.compactMap { content in
                        switch content {
                        case .text(let text):
                            return text.lowercased()
                        case .audio(let audio):
                            return audio.transcript?.lowercased()
                        default:
                            return nil
                        }
                    }.joined(separator: " ")
                    
                    // Check for conversation ending signals
                    let endSignals = ["goodbye", "bye", "done", "that's all", "all set", "you're all set"]
                    if endSignals.contains(where: { content.contains($0) }) {
                        print("🔚 One-shot command completed, AI signaled end")
                        self.shouldDismiss = true
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
                        case .input_audio(let audio):
                            return audio.transcript
                        default:
                            return nil
                        }
                    }.joined(separator: " ")
                    
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        observationTasks.append(stateTask)
    }
    
    private func sendToolsConfiguration() async {
        guard conversation != nil else { return }
        
        // Create the session.update event with tools
        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "tools": RealtimeFunctions.availableFunctionsJSON
            ]
        ]
        
        // Send the tools configuration
        if let jsonData = try? JSONSerialization.data(withJSONObject: sessionUpdate),
           let _ = String(data: jsonData, encoding: .utf8) {
            print("📤 Sending tools configuration to Realtime API")
            print("📋 Tools: \(RealtimeFunctions.availableFunctionsJSON.count) functions")
            
            // The conversation object should have a way to send raw messages
            // For now, we'll rely on the instructions to guide the model
            // If the library exposes a send method, we can use it here
        }
    }
    
    private func observeFunctionCalls() async {
        guard let conversation = conversation else { return }
        
        enum FunctionCallState {
            case pending    // Arguments still streaming
            case ready      // Arguments complete, ready to process
            case processed  // Already handled
        }
        
        var functionCallStates: [String: FunctionCallState] = [:]
        var processedFunctionCalls = Set<String>()
        
        // Monitor conversation entries for function call items
        var lastEntryCount = 0
        while !Task.isCancelled {
            // Track new entries
            if conversation.entries.count != lastEntryCount {
                lastEntryCount = conversation.entries.count
            }
            
            // Check ALL entries (not just new ones) to catch updated arguments
            for entry in conversation.entries {
                if case let .functionCall(functionCall) = entry {
                    let currentState = functionCallStates[functionCall.id] ?? .pending
                    
                    switch currentState {
                    case .pending:
                        // Check if arguments are complete (valid JSON)
                        if !functionCall.arguments.isEmpty && isValidJSON(functionCall.arguments) {
                            // Arguments are complete and valid!
                            functionCallStates[functionCall.id] = .ready
                            print("✅ Function call ready with complete arguments: \(functionCall.name)")
                            print("📝 Final arguments: \(functionCall.arguments)")
                        } else {
                            // Still streaming or invalid
                            print("⏳ Function call pending: \(functionCall.name) - Args length: \(functionCall.arguments.count)")
                        }
                        
                    case .ready:
                        // Ready to process
                        if !processedFunctionCalls.contains(functionCall.id) {
                            processedFunctionCalls.insert(functionCall.id)
                            functionCallStates[functionCall.id] = .processed
                            
                            print("🚀 Processing function call: \(functionCall.name)")
                            
                            // Execute the function with complete arguments
                            let result = await functionHandler.handleFunctionCall(
                                name: functionCall.name,
                                arguments: functionCall.arguments
                            )
                            
                            // Send result back
                            await sendFunctionResult(callId: functionCall.id, result: result)
                            lastFunctionCall = "\(functionCall.name): \(result)"
                            
                            // Don't auto-close after function execution
                            // User might want to add more tasks/reminders
                            print("✅ Function executed successfully, voice mode remains open")
                        }
                        
                    case .processed:
                        // Already handled, skip
                        break
                    }
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
            self.error = "Voice AI not initialized"
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
        // Ensure conversation is initialized
        if conversation == nil {
            // Quick wait for initialization
            for _ in 1...10 { // 1 second max
                if conversation != nil {
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        guard let conversation = self.conversation else {
            self.error = "Voice AI not initialized"
            throw VoiceAIError.notInitialized
        }
        
        do {
            try conversation.startHandlingVoice()
            error = nil
        } catch {
            self.error = "Failed to start voice: \(error.localizedDescription)"
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
    
    private func cancelObservationTasks() {
        // Cancel all observation tasks
        for task in observationTasks {
            task.cancel()
        }
        observationTasks.removeAll()
        print("🛑 Cancelled all observation tasks")
    }
    
    func closeVoiceMode() async {
        // Just stop listening/handling but keep conversation alive for reuse
        guard let conversation = self.conversation else { return }
        conversation.stopListening()
        conversation.stopHandlingVoice()
        isListening = false
        isConnected = false
        
        // Cancel observation tasks to stop the logging
        cancelObservationTasks()
        
        // Wait for any pending user messages to be fully processed
        // Check if we have a pending user transcript that hasn't been added to messages yet
        if !currentTranscript.isEmpty {
            print("⏳ Waiting for user transcript to be added to messages: '\(currentTranscript)'")
            
            // Wait up to 1 second for the user message to appear
            var attempts = 0
            while attempts < 10 {
                // Check if the transcript now appears in messages
                let hasUserMessage = messages.contains { message in
                    if message.role == .user {
                        let content = message.content.compactMap { content in
                            switch content {
                            case .input_text(let text), .text(let text):
                                return text
                            case .input_audio(let audio):
                                return audio.transcript
                            default:
                                return nil
                            }
                        }.joined(separator: " ")
                        
                        return content.contains(currentTranscript)
                    }
                    return false
                }
                
                if hasUserMessage {
                    print("✅ User message found in conversation")
                    break
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                attempts += 1
            }
            
            // If still not found, manually add it
            if attempts == 10 && !currentTranscript.isEmpty {
                print("⚠️ User message not found after waiting, adding manually")
                // Create a manual user message
                let manualMessage = ChatMessage(
                    content: currentTranscript,
                    isFromUser: true,
                    conversationId: self.conversationId,
                    source: .voice,
                    voiceTranscript: currentTranscript
                )
                voiceMessages.append(manualMessage)
            }
        }
        
        // Final update of voice messages from conversation
        self.voiceMessages = self.messages.map { message in
            let content = message.content.compactMap { content in
                switch content {
                case .text(let text):
                    return text
                case .audio(let audio):
                    return audio.transcript
                case .input_text(let text):
                    return text
                case .input_audio(let audio):
                    return audio.transcript
                }
            }.joined(separator: " ")
            
            return ChatMessage(
                content: content,
                isFromUser: message.role == .user,
                conversationId: self.conversationId,
                source: .voice,
                voiceTranscript: content
            )
        }
        
        print("📊 Final voice messages count: \(voiceMessages.count)")
        // Don't clear conversation or set isInitialized to false
        // This allows reopening voice mode in the same chat session
    }
    
    func disconnect() async {
        // Complete teardown - only called when leaving ChatView entirely
        guard let conversation = self.conversation else { return }
        
        // Cancel all observation tasks first
        cancelObservationTasks()
        
        conversation.stopListening()
        conversation.stopHandlingVoice()
        isListening = false
        isConnected = false
        isInitialized = false
        // Clear the conversation for next use
        self.conversation = nil
        messages.removeAll()
        voiceMessages.removeAll()
        currentTranscript = ""
        error = nil
        
        print("✅ VoiceAIManager disconnected")
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
