//
//  VoiceAIManager.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import SwiftUI
import Combine
import FirebaseAuth
import WebRTC

@MainActor
class VoiceAIManager: ObservableObject {
    static let shared = VoiceAIManager()
    
    @Published var isListening = false
    @Published var isConnected = false
    @Published var messages: [ChatMessage] = []
    @Published var currentTranscript = ""
    @Published var error: String?
    @Published var lastFunctionCall: String?
    @Published var shouldDismiss = false
    @Published var isInitialized = false
    
    private var webRTCClient: VoiceWebRTCClient?
    private var conversationId: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var ephemeralToken: String?
    private var sessionId: String?
    
    // Get voice messages as ChatMessages for unified conversation
    func getVoiceMessages() -> [ChatMessage] {
        return messages
    }
    
    
    private init() {
        setupComponents()
    }
    
    private func setupComponents() {
        webRTCClient = VoiceWebRTCClient()
        
        // Observe WebRTC messages
        webRTCClient?.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleRealtimeMessage(message)
            }
            .store(in: &cancellables)
    }
    
    func initialize(withChatHistory chatMessages: [ChatMessage] = [], conversationId: String) async {
        guard !isInitialized else { return }
        
        self.conversationId = conversationId
        self.messages = [] // Clear any previous messages
        
        // Store chat history for context
        self.chatHistory = chatMessages
        
        // Connect to backend WebSocket
        await connectToBackend()
        
        isInitialized = true
    }
    
    private var chatHistory: [ChatMessage] = []
    
    func updateChatHistory(_ messages: [ChatMessage], conversationId: String? = nil) async {
        self.chatHistory = messages
        if let conversationId = conversationId {
            self.conversationId = conversationId
        }
        
        // If already connected, update the session with new context
        if isConnected {
            await configureSession()
        }
    }
    
    // Public method to ensure initialization is complete
    func ensureInitialized() async {
        if !isConnected {
            await connectToBackend()
        }
        
        // Wait for connection to be ready
        for _ in 1...30 {
            if isConnected {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    private func connectToBackend() async {
        error = nil
        
        do {
            // Get ephemeral token from backend
            guard let firebaseUser = Auth.auth().currentUser else {
                throw VoiceAIError.notAuthenticated
            }
            
            let token = try await firebaseUser.getIDToken()
            let safeToken = token.sanitizedForHTTPHeader
            
            let urlString = "\(AppConfig.apiBaseURL)/realtime/token"
            print("🔑 Getting ephemeral token from: \(urlString)")
            guard let url = URL(string: urlString) else {
                throw VoiceAIError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(safeToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check if we got an HTTP error
            if let httpResponse = response as? HTTPURLResponse {
                print("🔑 Token response status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ Token error: \(errorText)")
                    throw VoiceAIError.invalidURL
                }
            }
            
            // Parse token response
            let tokenResponse = try JSONDecoder().decode(RealtimeTokenResponse.self, from: data)
            self.ephemeralToken = tokenResponse.token
            self.sessionId = tokenResponse.session_id
            
            print("✅ Got ephemeral token, session: \(tokenResponse.session_id)")
            
            // Connect WebRTC
            try await webRTCClient?.connect(token: tokenResponse.token, sessionId: tokenResponse.session_id)
            
            isConnected = webRTCClient?.isConnected ?? false
            
        } catch {
            self.error = "Failed to connect: \(error.localizedDescription)"
            print("❌ Connection failed: \(error)")
        }
    }
    
    private func configureSession() async {
        // Session is already configured when we get the ephemeral token
        // The backend sets up voice, tools, and instructions
        print("✅ Session configured via ephemeral token")
    }
    
    private func handleRealtimeMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "response.audio.delta":
            // Audio is handled automatically by WebRTC
            break
            
        case "response.audio_transcript.delta":
            if let delta = message["delta"] as? String {
                currentTranscript += delta
            }
            
        case "response.audio_transcript.done":
            if !currentTranscript.isEmpty {
                let chatMessage = ChatMessage(
                    content: currentTranscript,
                    isFromUser: false,
                    conversationId: conversationId,
                    source: .voice,
                    voiceTranscript: currentTranscript
                )
                messages.append(chatMessage)
                currentTranscript = ""
            }
            
        case "input_audio_buffer.speech_started":
            isListening = true
            
        case "input_audio_buffer.speech_stopped":
            isListening = false
            
        case "input_audio_buffer.committed":
            // User's speech was committed
            break
            
        case "conversation.item.created":
            if let item = message["item"] as? [String: Any],
               let role = item["role"] as? String {
                if role == "user", let content = item["content"] as? [[String: Any]] {
                    for contentItem in content {
                        if contentItem["type"] as? String == "input_audio",
                           let transcript = contentItem["transcript"] as? String {
                            let chatMessage = ChatMessage(
                                content: transcript,
                                isFromUser: true,
                                conversationId: conversationId,
                                source: .voice,
                                voiceTranscript: transcript
                            )
                            messages.append(chatMessage)
                        }
                    }
                }
            }
            
        case "response.function_call_arguments.done":
            if let name = message["name"] as? String,
               let callId = message["call_id"] as? String,
               let argumentsString = message["arguments"] as? String {
                lastFunctionCall = "Function called: \(name)"
                print("📦 Function call: \(name) with args: \(argumentsString)")
                
                // Execute function on backend and send result back to OpenAI
                Task {
                    await executeFunctionOnBackend(name: name, arguments: argumentsString, callId: callId)
                }
            }
            
        case "error":
            if let error = message["error"] as? [String: Any],
               let errorMessage = error["message"] as? String {
                self.error = errorMessage
            }
            
        default:
            break
        }
        
        // Update connection state
        isConnected = webRTCClient?.isConnected ?? false
    }
    
    
    // Remove old setupObservers method - it's no longer needed
    private func setupObservers_old() async {
        // This method is removed
    }
    // All function handling is now done on the backend
    
    func startListening() async throws {
        // WebRTC handles audio automatically
        // Just update state
        isListening = true
        error = nil
    }
    
    func stopListening() async {
        // WebRTC handles audio automatically
        isListening = false
    }
    
    func startHandlingVoice() async throws {
        // Ensure connection is ready
        if !isConnected {
            await connectToBackend()
        }
        
        guard isConnected else {
            self.error = "Not connected to server"
            throw VoiceAIError.notConnected
        }
        
        // WebRTC handles audio automatically
        error = nil
    }
    
    func stopHandlingVoice() async {
        // WebRTC handles audio automatically
        isListening = false
    }
    
    func sendMessage(_ text: String) async throws {
        guard let webRTCClient = webRTCClient else {
            throw VoiceAIError.notInitialized
        }
        
        // Send text message via data channel
        let message: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [[
                    "type": "input_text",
                    "text": text
                ]]
            ]
        ]
        
        webRTCClient.sendMessage(message)
        
        // Also send response.create to trigger response
        webRTCClient.sendMessage(["type": "response.create"])
        
        // Add to messages
        let chatMessage = ChatMessage(
            content: text,
            isFromUser: true,
            conversationId: conversationId,
            source: .voice
        )
        messages.append(chatMessage)
        
        error = nil
    }
    
    func interrupt() async {
        // Send interrupt command via data channel
        webRTCClient?.sendMessage(["type": "response.cancel"])
    }
    
    func closeVoiceMode() async {
        // WebRTC handles audio cleanup
        isListening = false
        
        // Keep connection alive for potential reuse
        print("📊 Voice mode closed, messages count: \(messages.count)")
    }
    
    func disconnect() async {
        // Complete teardown - only called when leaving ChatView entirely
        webRTCClient?.disconnect()
        
        isListening = false
        isConnected = false
        isInitialized = false
        
        messages.removeAll()
        currentTranscript = ""
        error = nil
        ephemeralToken = nil
        sessionId = nil
        
        print("✅ VoiceAIManager disconnected")
    }
    
    func reset() {
        messages.removeAll()
        currentTranscript = ""
        error = nil
        // Reconnect if needed
        Task {
            await connectToBackend()
        }
    }
    
    private func executeFunctionOnBackend(name: String, arguments: String, callId: String) async {
        do {
            // Parse arguments
            guard let argsData = arguments.data(using: .utf8),
                  let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
                print("Failed to parse function arguments")
                return
            }
            
            // Get auth token
            guard let firebaseUser = Auth.auth().currentUser else { return }
            let token = try await firebaseUser.getIDToken()
            let safeToken = token.sanitizedForHTTPHeader
            
            // Call backend to execute function
            guard let url = URL(string: "\(AppConfig.apiBaseURL)/realtime/function") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(safeToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = [
                "name": name,
                "arguments": args
            ] as [String: Any]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Function execution failed - no response")
                return
            }
            
            if httpResponse.statusCode != 200 {
                print("Function execution failed with status: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("Error: \(errorText)")
                }
                return
            }
            
            // Parse result
            guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Failed to parse function result")
                return
            }
            
            print("📋 Function result from backend: \(result)")
            
            // Send result back to OpenAI via data channel
            // The output should be a JSON string, not base64
            let outputString = String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8) ?? "{}"
            
            let functionOutput: [String: Any] = [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": callId,
                    "output": outputString
                ]
            ]
            
            webRTCClient?.sendMessage(functionOutput)
            
            // Trigger response
            webRTCClient?.sendMessage(["type": "response.create"])
            
            print("✅ Function \(name) executed and result sent back")
            
        } catch {
            print("❌ Function execution error: \(error)")
        }
    }
}

enum VoiceAIError: LocalizedError {
    case notInitialized
    case notAuthenticated
    case notConnected
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Voice AI not initialized"
        case .notAuthenticated:
            return "User not authenticated"
        case .notConnected:
            return "Not connected to voice server"
        case .invalidURL:
            return "Invalid server URL"
        }
    }
}

// Response struct for ephemeral token
struct RealtimeTokenResponse: Codable {
    let success: Bool
    let token: String
    let expires_at: Int?
    let session_id: String
    let model: String?
}
