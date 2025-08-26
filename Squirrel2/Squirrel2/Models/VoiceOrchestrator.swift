//
//  VoiceOrchestrator.swift
//  Squirrel2
//
//  Orchestrates voice input between local commands and Realtime conversations
//

import SwiftUI
import Combine
import AVFoundation
import OpenAIRealtime

@MainActor
class VoiceOrchestrator: ObservableObject {
    // MARK: - Published Properties
    @Published var isListening = false
    @Published var transcript = ""
    @Published var currentMode: VoiceMode = .idle
    @Published var lastResult: String?
    @Published var error: String?
    @Published var isProcessing = false
    
    // MARK: - Components
    private let speechRecognizer = SpeechRecognizer()
    private let voiceAI = VoiceAIManager()
    private let commandExecutor = VoiceCommandExecutor()
    private let audioRecorder = AudioRecorder()
    
    // MARK: - State
    private var warmupTask: Task<Void, Never>?
    private var classificationTask: Task<IntentClassification, Never>?
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    enum VoiceMode {
        case idle
        case listening
        case classifying
        case processingCommand
        case conversation
    }
    
    enum IntentClassification {
        case command
        case conversation
    }
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe speech recognizer transcript
        speechRecognizer.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] newTranscript in
                self?.transcript = newTranscript
            }
            .store(in: &cancellables)
        
        // Observe speech recognizer state
        speechRecognizer.$isTranscribing
            .receive(on: RunLoop.main)
            .sink { [weak self] isTranscribing in
                if !isTranscribing && !(self?.transcript.isEmpty ?? true) {
                    // Speech ended with content - process it
                    Task {
                        await self?.processSpeechEnd()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func startListening() {
        guard !isListening else { return }
        
        print("🎙️ VoiceOrchestrator: Starting to listen")
        isListening = true
        currentMode = .listening
        transcript = ""
        lastResult = nil
        error = nil
        recordingStartTime = Date()
        
        // Start speech recognition
        speechRecognizer.startTranscribing()
        
        // Start warming up Realtime connection immediately (parallel processing)
        warmupTask = Task {
            await warmUpRealtimeConnection()
        }
    }
    
    func stopListening() {
        guard isListening else { return }
        
        print("🛑 VoiceOrchestrator: Stopping listening")
        isListening = false
        
        // Stop speech recognition
        speechRecognizer.stopTranscribing()
        
        // Process if we have a transcript
        if !transcript.isEmpty {
            Task {
                await processSpeechEnd()
            }
        } else {
            currentMode = .idle
            warmupTask?.cancel()
        }
    }
    
    func reset() {
        print("🔄 VoiceOrchestrator: Resetting")
        
        // Cancel any ongoing tasks
        warmupTask?.cancel()
        classificationTask?.cancel()
        
        // Reset components
        speechRecognizer.reset()
        Task {
            await voiceAI.disconnect()
        }
        
        // Reset state
        isListening = false
        transcript = ""
        currentMode = .idle
        lastResult = nil
        error = nil
        isProcessing = false
    }
    
    // MARK: - Private Methods
    
    private func processSpeechEnd() async {
        guard !transcript.isEmpty else { return }
        
        print("📝 VoiceOrchestrator: Processing transcript: '\(transcript)'")
        currentMode = .classifying
        isProcessing = true
        
        // Start classification
        let classification = await classifyIntent(transcript)
        
        switch classification {
        case .command:
            await handleCommand()
        case .conversation:
            await handleConversation()
        }
        
        isProcessing = false
    }
    
    private func classifyIntent(_ text: String) async -> IntentClassification {
        print("🤖 VoiceOrchestrator: Classifying intent for: '\(text)'")
        
        // Quick local checks for obvious commands
        let lowercased = text.lowercased()
        let commandKeywords = ["remind", "task", "timer", "alarm", "complete", "done", "delete", "remove", "shopping", "grocery"]
        
        for keyword in commandKeywords {
            if lowercased.contains(keyword) {
                print("✅ VoiceOrchestrator: Quick classification - COMMAND (keyword: \(keyword))")
                return .command
            }
        }
        
        // Use API classification for ambiguous cases
        do {
            guard let user = FirebaseManager.shared.currentUser,
                  let token = try? await user.getIDToken() else {
                print("⚠️ VoiceOrchestrator: No auth, defaulting to command")
                return .command
            }
            
            let url = URL(string: "\(AppConfig.apiBaseURL)/ai/classify")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
            request.timeoutInterval = 1.0 // Fast timeout for classification
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let responseData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let isCommand = responseData["isCommand"] as? Bool {
                
                print("✅ VoiceOrchestrator: API classification - \(isCommand ? "COMMAND" : "CONVERSATION")")
                return isCommand ? .command : .conversation
            }
        } catch {
            print("⚠️ VoiceOrchestrator: Classification error: \(error), defaulting to conversation")
        }
        
        // Default to conversation for questions and complex queries
        return .conversation
    }
    
    private func handleCommand() async {
        print("⚡ VoiceOrchestrator: Handling as COMMAND")
        
        // Cancel Realtime warmup since we don't need it
        warmupTask?.cancel()
        warmupTask = nil
        
        currentMode = .processingCommand
        
        // Execute command locally for instant feedback
        let result = await commandExecutor.executeCommand(from: transcript)
        
        if result.success {
            lastResult = result.message
            commandExecutor.playSuccessSound()
            print("✅ VoiceOrchestrator: Command executed successfully")
        } else {
            error = result.message
            commandExecutor.playErrorSound()
            print("❌ VoiceOrchestrator: Command failed: \(result.message)")
            
            // Fall back to conversation mode if command failed
            await handleConversation()
            return
        }
        
        // Reset for next interaction
        transcript = ""
        currentMode = .idle
        isListening = false
    }
    
    private func handleConversation() async {
        print("💬 VoiceOrchestrator: Handling as CONVERSATION")
        
        currentMode = .conversation
        
        // Wait for warmup to complete (should be mostly done already)
        if let warmup = warmupTask {
            await warmup.value
        }
        
        // Send transcript to Realtime
        do {
            if !voiceAI.isConnected {
                print("⏳ VoiceOrchestrator: Waiting for Realtime connection...")
                // Give it a moment to connect
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            try await voiceAI.sendMessage(transcript)
            print("✅ VoiceOrchestrator: Sent to Realtime conversation")
            
            // Keep connection open for follow-ups
            lastResult = "Conversation mode active"
        } catch {
            self.error = "Failed to send to conversation: \(error.localizedDescription)"
            print("❌ VoiceOrchestrator: Failed to send to Realtime: \(error)")
        }
        
        // Don't reset - keep conversation mode active
        currentMode = .conversation
    }
    
    private func warmUpRealtimeConnection() async {
        print("🔥 VoiceOrchestrator: Starting Realtime warmup")
        
        do {
            // Start handling voice (this initiates the connection)
            try await voiceAI.startHandlingVoice()
            print("✅ VoiceOrchestrator: Realtime connection warmed up")
        } catch {
            print("⚠️ VoiceOrchestrator: Warmup failed: \(error)")
            // Don't set error here - it's just a warmup
        }
    }
    
    // MARK: - Conversation Management
    
    func switchToConversationMode() async {
        print("🔄 VoiceOrchestrator: Switching to conversation mode")
        
        currentMode = .conversation
        
        // Ensure Realtime is connected
        if !voiceAI.isConnected {
            do {
                try await voiceAI.startHandlingVoice()
                try await voiceAI.startListening()
            } catch {
                self.error = "Failed to start conversation: \(error.localizedDescription)"
            }
        }
    }
    
    func exitConversationMode() async {
        print("🔄 VoiceOrchestrator: Exiting conversation mode")
        
        await voiceAI.disconnect()
        currentMode = .idle
    }
    
    // MARK: - Computed Properties
    
    var statusText: String {
        switch currentMode {
        case .idle:
            return "Ready to listen"
        case .listening:
            return "Listening..."
        case .classifying:
            return "Processing..."
        case .processingCommand:
            return "Executing command..."
        case .conversation:
            return voiceAI.isConnected ? "Conversation mode" : "Connecting..."
        }
    }
    
    var isInConversation: Bool {
        currentMode == .conversation && voiceAI.isConnected
    }
    
    // Pass through VoiceAI properties for conversation mode
    var conversationMessages: [Item.Message] {
        voiceAI.messages
    }
    
    var isRealtimeListening: Bool {
        voiceAI.isListening
    }
}
