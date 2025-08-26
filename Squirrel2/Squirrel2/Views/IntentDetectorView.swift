//
//  IntentDetectorView.swift
//  Squirrel2
//
//  Clean intent detection before routing to voice or task mode
//

import SwiftUI
import Speech
import AVFoundation

struct IntentDetectorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var transcript = ""
    @State private var detectedIntent = ""
    @State private var isListening = false
    @State private var isProcessing = false
    
    // Speech recognition
    @StateObject private var speechRecognizer = SpeechRecognizerService()
    
    // Intent classification
    private let intentRouter = IntentRouter()
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Close button
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding()
                }
                
                Spacer()
                
                // Visual indicator
                ZStack {
                    Circle()
                        .stroke(lineWidth: 3)
                        .foregroundColor(.white.opacity(0.2))
                        .frame(width: 150, height: 150)
                    
                    if isListening {
                        // Animated listening indicator
                        Circle()
                            .fill(Color.red)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isListening ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(), value: isListening)
                    } else if isProcessing {
                        ProgressView()
                            .scaleEffect(2)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if !detectedIntent.isEmpty {
                        // Show intent result
                        VStack {
                            Image(systemName: detectedIntent == "capture" ? "checkmark.circle" : "bubble.left.and.bubble.right")
                                .font(.system(size: 50))
                                .foregroundColor(.green)
                        }
                    }
                }
                
                // Transcript
                Text(transcript.isEmpty ? "Tap to speak" : "\"\(transcript)\"")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .frame(minHeight: 60)
                
                // Intent result
                if !detectedIntent.isEmpty {
                    Text("Intent: \(detectedIntent)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                // Action button
                if !isListening && !isProcessing {
                    Button(action: startListening) {
                        Text(detectedIntent.isEmpty ? "Start" : "Try Again")
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                            .background(Color.blue)
                            .cornerRadius(25)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            setupIntentRouter()
            speechRecognizer.onTranscriptUpdate = { newTranscript in
                transcript = newTranscript
            }
            speechRecognizer.onSilenceDetected = {
                Task {
                    await processIntent()
                }
            }
        }
    }
    
    private func setupIntentRouter() {
        if let apiKey = FirebaseManager.shared.openAIKey {
            intentRouter.initialize(apiKey: apiKey)
        }
    }
    
    private func startListening() {
        // Reset state
        transcript = ""
        detectedIntent = ""
        isListening = true
        
        Task {
            do {
                try await speechRecognizer.startListening()
            } catch {
                print("Failed to start listening: \(error)")
                isListening = false
            }
        }
    }
    
    private func processIntent() async {
        guard !transcript.isEmpty else {
            isListening = false
            return
        }
        
        isListening = false
        isProcessing = true
        
        // Ensure API key is available
        var apiKey = FirebaseManager.shared.openAIKey
        if apiKey == nil {
            print("⏳ API key not cached, fetching...")
            await FirebaseManager.shared.fetchOpenAIKey()
            apiKey = FirebaseManager.shared.openAIKey
        }
        
        guard let key = apiKey else {
            print("❌ API key not available for intent classification")
            detectedIntent = "error"
            isProcessing = false
            return
        }
        
        intentRouter.initialize(apiKey: key)
        
        do {
            // Classify intent
            let result = try await intentRouter.classifyIntent(transcript)
            
            // Map to simple terms
            switch result.intent {
            case .command:
                detectedIntent = "capture"
                // Create task
                if let task = result.task {
                    await createTask(title: task.title, dueDate: task.dueDate, priority: task.priority)
                }
                
            case .question:
                detectedIntent = "converse"
                // Wait a moment to show the result
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Ensure speech recognition is fully stopped
                speechRecognizer.stopListening()
                
                // Force complete audio session reset
                await resetAudioSessionCompletely()
                
                // MAJOR DELAY: Give audio session time to fully release
                print("⏳ Waiting 3 seconds for audio session cleanup...")
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                
                // Initialize and open voice mode
                await openVoiceMode()
            }
        } catch {
            print("Intent classification failed: \(error)")
            detectedIntent = "error"
        }
        
        isProcessing = false
    }
    
    private func resetAudioSessionCompletely() async {
        print("🔄 Forcing complete audio session reset...")
        
        let audioSession = AVAudioSession.sharedInstance()
        
        // Try multiple resets to ensure complete cleanup
        for i in 1...3 {
            do {
                // Deactivate
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("  [\(i)] Audio session deactivated")
                
                // Wait a bit
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Set to ambient (least intrusive)
                try audioSession.setCategory(.ambient, mode: .default, options: [])
                print("  [\(i)] Audio category reset to ambient")
                
                // Another pause
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Try playback category (what Realtime API needs)
                try audioSession.setCategory(.playback, mode: .default, options: [])
                print("  [\(i)] Audio category set to playback")
                
                // Final pause
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Deactivate again
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("  [\(i)] Final deactivation")
                
            } catch {
                print("  ⚠️ Reset attempt \(i) error: \(error)")
            }
        }
        
        print("✅ Audio session reset complete")
    }
    
    private func createTask(title: String, dueDate: String?, priority: String?) async {
        // Use the function handler to create task
        let handler = RealtimeFunctionHandler()
        
        let args: [String: Any] = [
            "title": title,
            "dueDate": dueDate ?? "",
            "priority": priority ?? "medium"
        ]
        
        let argsJSON = try? JSONSerialization.data(withJSONObject: args)
        let argsString = argsJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        _ = await handler.handleFunctionCall(
            name: "create_task",
            arguments: argsString
        )
        
        print("✅ Task created: \(title)")
    }
    
    private func openVoiceMode() async {
        // Initialize VoiceAIManager if needed
        if !VoiceAIManager.shared.isInitialized {
            await VoiceAIManager.shared.initialize(
                withChatHistory: [],
                conversationId: UUID().uuidString
            )
        }
        
        // Set the initial question
        VoiceAIManager.shared.setInitialPrompt(transcript)
        
        // Dismiss this view first, then open voice mode from ContentView
        dismiss()
        
        // MAJOR DELAY: Ensure dismiss completes and UI settles
        print("⏳ Waiting 2 seconds for view dismissal...")
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Notify ContentView to open voice mode
        NotificationCenter.default.post(name: NSNotification.Name("OpenVoiceModeWithPrompt"), object: nil)
    }
}

// Speech recognizer service with silence detection
@MainActor
class SpeechRecognizerService: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5 // 1.5 seconds of silence
    
    var onTranscriptUpdate: ((String) -> Void)?
    var onSilenceDetected: (() -> Void)?
    
    func startListening() async throws {
        // Request permission
        guard await requestSpeechAuthorization() else {
            throw SpeechError.noPermission
        }
        
        // Stop any existing session
        stopListening()
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.recognitionFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Setup audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcript = result.bestTranscription.formattedString
                self.onTranscriptUpdate?(transcript)
                
                // Reset silence timer on new speech
                self.resetSilenceTimer()
            }
            
            if error != nil || result?.isFinal == true {
                // Let silence detection handle stopping
            }
        }
    }
    
    func stopListening() {
        print("🛑 Stopping speech recognition...")
        
        // Stop silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            print("  ✓ Audio engine stopped")
        }
        
        // Remove audio tap
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
            print("  ✓ Audio tap removed")
        }
        
        // End recognition
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        print("  ✓ Recognition task cancelled")
        
        // NUCLEAR OPTION: Reset the audio engine completely
        audioEngine.reset()
        print("  ✓ Audio engine reset")
        
        // Create a new audio engine for next time
        audioEngine = AVAudioEngine()
        print("  ✓ New audio engine created")
        
        // AGGRESSIVE audio session cleanup
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // First deactivate
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("  ✓ Audio session deactivated")
            
            // Then reset category to ambient
            try audioSession.setCategory(.ambient, mode: .default, options: [])
            print("  ✓ Audio session category reset")
        } catch {
            print("  ⚠️ Audio session cleanup error: \(error)")
        }
        
        print("✅ Speech recognition fully stopped")
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleSilence()
            }
        }
    }
    
    private func handleSilence() {
        print("Silence detected - stopping recording")
        stopListening()
        onSilenceDetected?()
    }
    
    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

enum SpeechError: Error {
    case noPermission
    case recognitionFailed
}

#Preview {
    IntentDetectorView()
}
