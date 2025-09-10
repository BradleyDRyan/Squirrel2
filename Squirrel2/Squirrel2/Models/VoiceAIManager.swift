//
//  VoiceAIManager.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import SwiftUI
import Combine
import FirebaseAuth

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
    
    private var webSocketClient: VoiceWebSocketClient?
    private var audioManager: VoiceAudioManager?
    private var conversationId: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var audioDataTask: Task<Void, Never>?
    
    // Get voice messages as ChatMessages for unified conversation
    func getVoiceMessages() -> [ChatMessage] {
        return messages
    }
    
    
    private init() {
        setupComponents()
    }
    
    private func setupComponents() {
        webSocketClient = VoiceWebSocketClient()
        audioManager = VoiceAudioManager()
        
        // Set up audio data callback
        audioManager?.onAudioData = { [weak self] data in
            Task { @MainActor [weak self] in
                try? await self?.webSocketClient?.sendAudio(data)
            }
        }
        
        // Observe WebSocket messages
        webSocketClient?.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleServerMessage(message)
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
            // Get WebSocket URL from backend
            // Use Firebase Auth to get the current user (works for anonymous users too)
            guard let firebaseUser = Auth.auth().currentUser else {
                throw VoiceAIError.notAuthenticated
            }
            
            let token = try await firebaseUser.getIDToken()
            let urlString = "\(AppConfig.apiBaseURL)/realtime/connect"
            print("📡 Connecting to: \(urlString)")
            guard let url = URL(string: urlString) else {
                throw VoiceAIError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check if we got an HTTP error
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Realtime connect response status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw VoiceAIError.invalidURL
                }
            }
            
            // Debug: Print what we received
            if let responseText = String(data: data, encoding: .utf8) {
                print("📡 Realtime connect response: \(responseText)")
            }
            
            let connectResponse = try JSONDecoder().decode(RealtimeConnectResponse.self, from: data)
            
            // Connect to WebSocket
            try await webSocketClient?.connect(websocketUrl: connectResponse.websocketUrl)
            
            // Configure session after connection
            await configureSession()
            
        } catch {
            self.error = "Failed to connect: \(error.localizedDescription)"
            print("❌ Connection failed: \(error)")
        }
    }
    
    private func configureSession() async {
        guard let webSocketClient = webSocketClient else { return }
        
        do {
            // Send session configuration to backend
            try await webSocketClient.configureSession(
                conversationId: conversationId,
                history: chatHistory,
                voice: "shimmer"
            )
            
            print("✅ Session configured with backend")
        } catch {
            print("❌ Failed to configure session: \(error)")
            self.error = "Failed to configure session: \(error.localizedDescription)"
        }
    }
    
    private func handleServerMessage(_ message: VoiceServerMessage) {
        switch message.type {
        case .status:
            // Connection status is already handled by WebSocketClient
            break
            
        case .transcript:
            if let transcript = message.data?["text"] as? String,
               let isUser = message.data?["isUser"] as? Bool {
                currentTranscript = transcript
                
                // Add transcript as a message
                let chatMessage = ChatMessage(
                    content: transcript,
                    isFromUser: isUser,
                    conversationId: conversationId,
                    source: .voice,
                    voiceTranscript: transcript
                )
                messages.append(chatMessage)
            }
            
        case .audio:
            if let base64Audio = message.data?["audio"] as? String {
                audioManager?.playAudioData(base64Audio)
            }
            
        case .text:
            if let text = message.data?["text"] as? String {
                // Add AI response text
                let chatMessage = ChatMessage(
                    content: text,
                    isFromUser: false,
                    conversationId: conversationId,
                    source: .voice
                )
                messages.append(chatMessage)
                
                // Check for conversation ending signals
                let endSignals = ["goodbye", "bye", "done", "that's all", "all set", "you're all set"]
                if endSignals.contains(where: { text.lowercased().contains($0) }) {
                    print("🔚 AI signaled end of conversation")
                    shouldDismiss = true
                }
            }
            
        case .function:
            if let functionName = message.data?["name"] as? String,
               let result = message.data?["result"] as? String {
                lastFunctionCall = "\(functionName): \(result)"
                print("✅ Function executed: \(lastFunctionCall ?? "")")
            }
            
        case .error:
            if let errorMessage = message.data?["message"] as? String {
                self.error = errorMessage
            }
            
        case .pong:
            break
        }
        
        // Update connection state from WebSocketClient
        isConnected = webSocketClient?.isConnected ?? false
        isListening = webSocketClient?.isListening ?? false
    }
    
    // Remove old setupObservers method - it's no longer needed
    private func setupObservers_old() async {
        // This method is removed
    }
    // All function handling is now done on the backend
    
    func startListening() async throws {
        guard audioManager != nil else {
            self.error = "Audio manager not initialized"
            throw VoiceAIError.notInitialized
        }
        
        do {
            try audioManager?.startRecording()
            error = nil
        } catch {
            self.error = "Failed to start listening: \(error.localizedDescription)"
            throw error
        }
    }
    
    func stopListening() async {
        audioManager?.stopRecording()
        
        // Commit audio to backend
        try? await webSocketClient?.commitAudio()
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
        
        // Start audio streaming
        audioDataTask = Task {
            // Audio data is automatically sent via the callback
        }
        
        error = nil
    }
    
    func stopHandlingVoice() async {
        audioDataTask?.cancel()
        audioDataTask = nil
        audioManager?.stopRecording()
        audioManager?.stopPlayback()
    }
    
    func sendMessage(_ text: String) async throws {
        guard let webSocketClient = webSocketClient else {
            throw VoiceAIError.notInitialized
        }
        
        do {
            try await webSocketClient.sendText(text)
            
            // Add to messages
            let chatMessage = ChatMessage(
                content: text,
                isFromUser: true,
                conversationId: conversationId,
                source: .voice
            )
            messages.append(chatMessage)
            
            error = nil
        } catch {
            self.error = "Failed to send message: \(error.localizedDescription)"
            throw error
        }
    }
    
    func interrupt() async {
        try? await webSocketClient?.interrupt()
        audioManager?.stopPlayback()
    }
    
    func closeVoiceMode() async {
        // Stop audio recording and playback
        audioManager?.stopRecording()
        audioManager?.stopPlayback()
        
        // Cancel audio streaming
        audioDataTask?.cancel()
        audioDataTask = nil
        
        isListening = false
        
        // Keep connection alive for potential reuse
        print("📊 Voice mode closed, messages count: \(messages.count)")
    }
    
    func disconnect() async {
        // Complete teardown - only called when leaving ChatView entirely
        audioManager?.cleanup()
        audioDataTask?.cancel()
        audioDataTask = nil
        
        webSocketClient?.disconnect()
        
        isListening = false
        isConnected = false
        isInitialized = false
        
        messages.removeAll()
        currentTranscript = ""
        error = nil
        
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

// Response struct for realtime connection
struct RealtimeConnectResponse: Codable {
    let success: Bool
    let websocketUrl: String
    let message: String?
}
