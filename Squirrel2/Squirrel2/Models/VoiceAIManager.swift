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
    
    private var apiKey: String {
        return APIConfig.openAIKey
    }
    
    var entries: [Item] {
        conversation?.entries ?? []
    }
    
    init() {
        setupConversation()
    }
    
    private func setupConversation() {
        guard !apiKey.isEmpty else {
            error = "OpenAI API key not configured"
            return
        }
        
        conversation = OpenAIRealtime.Conversation(authToken: apiKey)
        
        // Set up conversation observers
        Task {
            await setupObservers()
        }
    }
    
    private func setupObservers() async {
        guard let conversation = conversation else { return }
        
        // Wait for connection
        Task {
            await conversation.waitForConnection()
            self.isConnected = conversation.connected
        }
        
        // Observe errors
        Task {
            for await error in conversation.errors {
                self.error = error.message
            }
        }
        
        // Start observing conversation state
        Task {
            while true {
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
    
    func startListening() async throws {
        guard let conversation = conversation else {
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
        guard let conversation = conversation else { return }
        conversation.stopListening()
    }
    
    func startHandlingVoice() async throws {
        guard let conversation = conversation else {
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
        guard let conversation = conversation else { return }
        conversation.stopHandlingVoice()
    }
    
    func sendMessage(_ text: String) async throws {
        guard let conversation = conversation else {
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
        guard let conversation = conversation else { return }
        conversation.interruptSpeech()
    }
    
    func disconnect() async {
        // Stop listening and handling voice
        guard let conversation = conversation else { return }
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
