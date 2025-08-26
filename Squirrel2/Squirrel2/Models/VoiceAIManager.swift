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
            // Wait for Firebase auth to be ready first
            await waitForFirebaseAuth()
            await fetchAPIKeyAndSetup()
        }
    }
    
    private func waitForFirebaseAuth() async {
        // Give Firebase auth time to initialize
        for _ in 1...20 {
            if FirebaseManager.shared.currentUser != nil {
                print("✅ Firebase auth ready for VoiceAIManager")
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        print("⚠️ Firebase auth not ready after 2 seconds, continuing anyway")
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
                    session.instructions = """
                    You are a helpful assistant that can create and manage tasks for the user.
                    When users ask you to create reminders, tasks, or manage their to-do list, use the available functions.
                    Be conversational and confirm when tasks are created or modified.
                    """
                    
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
                        print("   📌 Tool: \(tool.name ?? "unknown")")
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
    
    private func sendToolsConfiguration() async {
        guard let conversation = conversation else { return }
        
        // Create the session.update event with tools
        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "tools": RealtimeFunctions.availableFunctionsJSON
            ]
        ]
        
        // Send the tools configuration
        if let jsonData = try? JSONSerialization.data(withJSONObject: sessionUpdate),
           let jsonString = String(data: jsonData, encoding: .utf8) {
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
                    print("📞 Found function call entry: \(functionCall.name)")
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
