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
        
        // Don't pre-connect WebSocket here - audio session not ready at app launch
        // Connection will happen when voice view opens
        
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
        isLoadingKey = true
        error = nil
        
        // Use the API key from FirebaseManager (should already be fetched on app start)
        if let key = FirebaseManager.shared.openAIKey, !key.isEmpty {
            apiKey = key
            print("✅ Using API key from FirebaseManager")
            setupConversation()
        } else {
            // Key should be available, but wait briefly in case of race condition
            print("⏳ API key not immediately available, waiting briefly...")
            
            // Brief wait for API key
            for _ in 1...5 {
                if let key = FirebaseManager.shared.openAIKey, !key.isEmpty {
                    apiKey = key
                    print("✅ API key now available")
                    setupConversation()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            if apiKey.isEmpty {
                self.error = "OpenAI API key not available. Please check backend configuration."
                print("❌ API key not available - this shouldn't happen if ContentView waits properly")
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
                    You are a helpful assistant that can create and manage tasks for the user.
                    When users ask you to create reminders, tasks, or manage their to-do list, use the available functions.
                    """
                    
                    if !self.chatHistory.isEmpty {
                        contextInstructions += "\n\nPrevious conversation context:\n"
                        for msg in self.chatHistory.suffix(10) { // Last 10 messages for context
                            let role = msg.isFromUser ? "User" : "Assistant"
                            contextInstructions += "\(role): \(msg.content)\n"
                        }
                        contextInstructions += "\nContinue the conversation naturally based on this context."
                    } else {
                        contextInstructions += """
                        
                        IMPORTANT: Only for ONE-SHOT commands (when the user gives a single command with no prior conversation):
                        - After executing the command, give a brief confirmation and say "goodbye" or "done"
                        - Keep confirmations very brief - just 1 sentence
                        
                        If there's been ANY back-and-forth conversation, continue naturally without saying goodbye.
                        For questions or multi-step tasks, continue the conversation normally.
                        """
                    }
                    
                    session.instructions = contextInstructions
                    
                    // Set voice
                    session.voice = .alloy
                    
                    // Enable input audio transcription
                    session.inputAudioTranscription = Session.InputAudioTranscription()
                    
                    // Configure tools from RealtimeFunctions
                    session.tools = RealtimeFunctions.createSessionTools()
                    
                    // Set tool choice to auto
                    session.toolChoice = .auto
                    
                    // Set temperature
                    session.temperature = 0.8
                    
                    print("✅ Session configured with \(session.tools.count) tools")
                    
                    // Log the tools for debugging
                    for tool in session.tools {
                        print("   📌 Tool: \(tool.name)")
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
                
                // Convert to ChatMessages for unified conversation
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
                        default:
                            return nil
                        }
                    }.joined(separator: " ")
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
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
        print("🔍 Starting function call monitoring...")
        var lastEntryCount = 0
        while true {
            // Log new entries
            if conversation.entries.count != lastEntryCount {
                print("📊 Entries count changed: \(lastEntryCount) → \(conversation.entries.count)")
                lastEntryCount = conversation.entries.count
                
                // Log entry types
                for entry in conversation.entries {
                    switch entry {
                    case .message(let msg):
                        print("   💬 Message: role=\(msg.role)")
                    case .functionCall(let fc):
                        print("   🔧 Function call: \(fc.name)")
                    case .functionCallOutput(let fco):
                        print("   📤 Function output: \(fco.callId)")
                    }
                }
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
        // Ensure conversation is initialized
        if conversation == nil {
            print("⏳ Conversation not ready, waiting...")
            // Wait for initialization
            for _ in 1...30 {
                if conversation != nil && isConnected {
                    print("✅ Conversation ready")
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        guard let conversation = self.conversation else {
            self.error = "Voice AI not initialized. Please check your API key."
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
            print("⏳ Waiting for conversation initialization...")
            // Wait for initialization to complete
            for _ in 1...50 { // 5 seconds max
                if conversation != nil {
                    print("✅ Conversation initialized")
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        guard let conversation = self.conversation else {
            self.error = "Voice AI not initialized. Please check your API key configuration."
            throw VoiceAIError.notInitialized
        }
        
        do {
            try conversation.startHandlingVoice()
            error = nil
            
            // Wait a bit for connection to establish
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
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
    
    func closeVoiceMode() async {
        // Just stop listening/handling but keep conversation alive for reuse
        guard let conversation = self.conversation else { return }
        conversation.stopListening()
        conversation.stopHandlingVoice()
        isListening = false
        isConnected = false
        // Don't clear conversation or set isInitialized to false
        // This allows reopening voice mode in the same chat session
    }
    
    func disconnect() async {
        // Complete teardown - only called when leaving ChatView entirely
        guard let conversation = self.conversation else { return }
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
