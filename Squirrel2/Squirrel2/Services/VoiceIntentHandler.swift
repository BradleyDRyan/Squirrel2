//
//  VoiceIntentHandler.swift
//  Squirrel2
//
//  Handles initial voice capture and routing BEFORE Realtime API
//

import Foundation
import AVFoundation
import Speech

@MainActor
class VoiceIntentHandler: NSObject, ObservableObject {
    
    @Published var isRecording = false
    @Published var transcription = ""
    @Published var isProcessing = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let intentRouter = IntentRouter()
    
    override init() {
        super.init()
    }
    
    func initialize(apiKey: String) {
        intentRouter.initialize(apiKey: apiKey)
    }
    
    // Start recording and return intent classification
    func startRecordingForIntent() async throws -> IntentResult {
        // Request speech recognition permission
        guard await requestSpeechAuthorization() else {
            throw VoiceError.noSpeechPermission
        }
        
        // Start recording
        try startRecording()
        
        // Wait for user to finish speaking (detect silence or timeout)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds max
        
        // Stop recording and get transcription
        let finalTranscript = stopRecording()
        
        guard !finalTranscript.isEmpty else {
            throw VoiceError.noTranscription
        }
        
        print("🎤 Initial transcription: \(finalTranscript)")
        
        // Classify intent
        isProcessing = true
        let result = try await intentRouter.classifyIntent(finalTranscript)
        isProcessing = false
        
        return result
    }
    
    private func startRecording() throws {
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
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.transcription = result.bestTranscription.formattedString
            }
            
            if error != nil || result?.isFinal == true {
                self.stopRecordingInternal()
            }
        }
    }
    
    private func stopRecording() -> String {
        stopRecordingInternal()
        return transcription
    }
    
    private func stopRecordingInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
    }
    
    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

enum VoiceError: Error {
    case noSpeechPermission
    case noTranscription
    case recognitionFailed
}