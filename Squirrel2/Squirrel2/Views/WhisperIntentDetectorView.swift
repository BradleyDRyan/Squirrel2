//
//  WhisperIntentDetectorView.swift
//  Squirrel2
//
//  Intent detection using OpenAI Whisper API instead of Apple Speech Recognition
//

import SwiftUI
import AVFoundation

struct WhisperIntentDetectorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var transcript = ""
    @State private var detectedIntent = ""
    @State private var isRecording = false
    @State private var isProcessing = false
    
    // Audio recording
    @StateObject private var audioRecorder = WhisperAudioRecorder()
    
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
                    
                    if isRecording {
                        // Animated recording indicator
                        Circle()
                            .fill(Color.red)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(), value: isRecording)
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
                Button(action: toggleRecording) {
                    if isRecording {
                        Text("Stop")
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                            .background(Color.red)
                            .cornerRadius(25)
                    } else if !isProcessing {
                        Text(detectedIntent.isEmpty ? "Start" : "Try Again")
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                            .background(Color.blue)
                            .cornerRadius(25)
                    }
                }
                .disabled(isProcessing)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            // Delay setup to ensure Firebase is ready
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                setupIntentRouter()
            }
        }
    }
    
    private func setupIntentRouter() {
        Task {
            // Wait for Firebase authentication if needed
            for _ in 1...10 {
                if FirebaseManager.shared.currentUser != nil {
                    break
                }
                print("⏳ Waiting for Firebase auth...")
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            }
            
            var apiKey = FirebaseManager.shared.openAIKey
            if apiKey == nil {
                print("⏳ Fetching API key...")
                await FirebaseManager.shared.fetchOpenAIKey()
                apiKey = FirebaseManager.shared.openAIKey
            }
            
            if let key = apiKey {
                print("✅ Initializing with API key")
                intentRouter.initialize(apiKey: key)
                audioRecorder.initialize(apiKey: key)
            } else {
                print("❌ Failed to get API key")
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecordingAndProcess()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        // Reset state
        transcript = ""
        detectedIntent = ""
        isRecording = true
        
        audioRecorder.startRecording()
    }
    
    private func stopRecordingAndProcess() {
        isRecording = false
        isProcessing = true
        
        Task {
            do {
                // Ensure API key is available before processing
                var apiKey = FirebaseManager.shared.openAIKey
                if apiKey == nil {
                    print("⏳ API key not cached, fetching...")
                    await FirebaseManager.shared.fetchOpenAIKey()
                    apiKey = FirebaseManager.shared.openAIKey
                }
                
                guard let key = apiKey else {
                    print("❌ API key not available")
                    detectedIntent = "error"
                    isProcessing = false
                    return
                }
                
                // Re-initialize with fresh API key
                audioRecorder.initialize(apiKey: key)
                intentRouter.initialize(apiKey: key)
                
                // Stop recording and get transcription from Whisper
                let transcribedText = try await audioRecorder.stopRecordingAndTranscribe()
                transcript = transcribedText
                
                guard !transcript.isEmpty else {
                    isProcessing = false
                    return
                }
                
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
                    
                    // Initialize and open voice mode
                    await openVoiceMode()
                }
            } catch {
                print("Processing failed: \(error)")
                detectedIntent = "error"
            }
            
            isProcessing = false
        }
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
        
        // Small delay to ensure dismiss completes
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Notify ContentView to open voice mode
        NotificationCenter.default.post(name: NSNotification.Name("OpenVoiceModeWithPrompt"), object: nil)
    }
}

// Audio recorder using AVAudioRecorder for Whisper API
@MainActor
class WhisperAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var audioFilename: URL?
    private var apiKey: String = ""
    
    func initialize(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // Configure audio session for recording
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
            
            // Create audio file URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            audioFilename = documentsPath.appendingPathComponent("recording.m4a")
            
            // Configure audio settings for Whisper (it prefers m4a/mp4)
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000, // Whisper works best with 16kHz
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            // Start recording
            audioRecorder = try AVAudioRecorder(url: audioFilename!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            
            print("🎙️ Started recording audio for Whisper")
        } catch {
            print("❌ Failed to start recording: \(error)")
        }
    }
    
    func stopRecordingAndTranscribe() async throws -> String {
        guard let recorder = audioRecorder else {
            throw WhisperError.noRecording
        }
        
        recorder.stop()
        
        // Deactivate audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setActive(false)
        
        guard let fileURL = audioFilename else {
            throw WhisperError.noAudioFile
        }
        
        print("📤 Sending audio to Whisper API...")
        
        // Transcribe using Whisper API
        let transcription = try await transcribeWithWhisper(fileURL: fileURL)
        
        // Clean up audio file
        try? FileManager.default.removeItem(at: fileURL)
        
        return transcription
    }
    
    private func transcribeWithWhisper(fileURL: URL) async throws -> String {
        guard !apiKey.isEmpty else {
            throw WhisperError.noApiKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WhisperError.apiError
        }
        
        struct WhisperResponse: Codable {
            let text: String
        }
        
        let whisperResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
        print("✅ Whisper transcription: \(whisperResponse.text)")
        
        return whisperResponse.text
    }
}

enum WhisperError: LocalizedError {
    case noRecording
    case noAudioFile
    case noApiKey
    case apiError
    
    var errorDescription: String? {
        switch self {
        case .noRecording:
            return "No active recording"
        case .noAudioFile:
            return "Audio file not found"
        case .noApiKey:
            return "OpenAI API key not available"
        case .apiError:
            return "Whisper API request failed"
        }
    }
}

#Preview {
    WhisperIntentDetectorView()
}