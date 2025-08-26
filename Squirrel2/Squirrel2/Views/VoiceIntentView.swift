//
//  VoiceIntentView.swift
//  Squirrel2
//
//  Initial voice capture that routes to appropriate handler
//

import SwiftUI
import Speech
import AVFoundation

struct VoiceIntentView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var voiceHandler = VoiceIntentHandler()
    @StateObject private var quickCapture = QuickTaskCapture()
    
    @State private var phase: CapturePhase = .listening
    @State private var transcript = ""
    @State private var errorMessage: String?
    @State private var showRealtime = false
    
    enum CapturePhase {
        case listening
        case processing
        case taskCreated
        case routingToConversation
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.squirrelWarmBackground
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.squirrelAccent)
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // Main Content
                VStack(spacing: 30) {
                    // Status Icon
                    Group {
                        switch phase {
                        case .listening:
                            Image(systemName: "mic.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.squirrelAccent)
                                .symbolEffect(.pulse)
                            
                        case .processing:
                            ProgressView()
                                .scaleEffect(2)
                                .progressViewStyle(CircularProgressViewStyle(tint: .squirrelAccent))
                            
                        case .taskCreated:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            
                        case .routingToConversation:
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.squirrelAccent)
                        }
                    }
                    .frame(height: 80)
                    
                    // Status Text
                    VStack(spacing: 10) {
                        Text(phaseTitle)
                            .font(.squirrelTitle3)
                            .foregroundColor(.squirrelTextPrimary)
                        
                        if !transcript.isEmpty {
                            Text("\"\(transcript)\"")
                                .font(.squirrelBody)
                                .foregroundColor(.squirrelTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Instructions
                    Text(phaseInstructions)
                        .font(.squirrelFootnote)
                        .foregroundColor(.squirrelTextTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Recording control
                if phase == .listening {
                    Button(action: stopAndProcess) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 80, height: 80)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 25, height: 25)
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            Task {
                await startListening()
            }
        }
        .fullScreenCover(isPresented: $showRealtime) {
            RealtimeVoiceModeView()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private var phaseTitle: String {
        switch phase {
        case .listening:
            return "Listening..."
        case .processing:
            return "Understanding..."
        case .taskCreated:
            return "Task Created!"
        case .routingToConversation:
            return "Starting Conversation..."
        }
    }
    
    private var phaseInstructions: String {
        switch phase {
        case .listening:
            return "Speak your command or question\nTap to stop when done"
        case .processing:
            return "Analyzing your request"
        case .taskCreated:
            return "Your task has been added"
        case .routingToConversation:
            return "Opening conversation mode"
        }
    }
    
    private func startListening() async {
        // Initialize handlers with API key
        if let apiKey = FirebaseManager.shared.openAIKey {
            voiceHandler.initialize(apiKey: apiKey)
            quickCapture.initialize(apiKey: apiKey)
        }
        
        // Start recording
        do {
            try await voiceHandler.startRecordingWithLiveTranscription { liveTranscript in
                self.transcript = liveTranscript
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func stopAndProcess() {
        Task {
            await processRecording()
        }
    }
    
    private func processRecording() async {
        phase = .processing
        
        do {
            // Stop recording and get final transcript
            let finalTranscript = voiceHandler.stopRecording()
            guard !finalTranscript.isEmpty else {
                errorMessage = "No speech detected"
                return
            }
            
            transcript = finalTranscript
            
            // Classify intent
            let result = try await voiceHandler.classifyIntent(finalTranscript)
            
            switch result.intent {
            case .command:
                // Handle task creation locally
                phase = .taskCreated
                
                if let task = result.task {
                    await createTaskLocally(
                        title: task.title,
                        dueDate: task.dueDate,
                        priority: task.priority
                    )
                } else {
                    // Fallback: use full transcript as task
                    await createTaskLocally(
                        title: finalTranscript,
                        dueDate: nil,
                        priority: nil
                    )
                }
                
                // Auto-dismiss after 1.5 seconds
                try await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
                
            case .question:
                // Route to Realtime for conversation
                phase = .routingToConversation
                
                // Pass the initial transcript to VoiceAIManager
                VoiceAIManager.shared.setInitialPrompt(finalTranscript)
                
                // Open Realtime view
                try await Task.sleep(nanoseconds: 500_000_000) // Brief delay for animation
                showRealtime = true
            }
            
        } catch {
            errorMessage = "Failed to process: \(error.localizedDescription)"
        }
    }
    
    private func createTaskLocally(title: String, dueDate: String?, priority: String?) async {
        // Use the function handler directly to create task
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
        
        print("✅ Task created locally without Realtime API")
    }
}

// Update the VoiceIntentHandler to support live transcription
extension VoiceIntentHandler {
    func startRecordingWithLiveTranscription(onTranscriptionUpdate: @escaping (String) -> Void) async throws {
        // Request speech recognition permission
        guard await requestSpeechAuthorization() else {
            throw VoiceError.noSpeechPermission
        }
        
        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceError.recognitionFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        transcription = ""
        
        // Start recognition task with live updates
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.transcription = result.bestTranscription.formattedString
                onTranscriptionUpdate(self.transcription)
            }
            
            if error != nil || result?.isFinal == true {
                // Don't auto-stop on final, let user control
            }
        }
    }
    
    func classifyIntent(_ transcript: String) async throws -> IntentResult {
        return try await intentRouter.classifyIntent(transcript)
    }
}

#Preview {
    VoiceIntentView()
}