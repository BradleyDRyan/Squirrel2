//
//  SpeechRecognizer.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import AVFoundation
import Foundation
import Speech
import SwiftUI

class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isTranscribing = false
    @Published var isAvailable = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        requestTranscriptionPermission()
    }

    private func requestTranscriptionPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("SpeechRecognizer: Speech recognition authorized")
                    self?.isAvailable = true
                case .denied:
                    print("SpeechRecognizer: Speech recognition denied")
                    self?.isAvailable = false
                case .restricted:
                    print("SpeechRecognizer: Speech recognition restricted")
                    self?.isAvailable = false
                case .notDetermined:
                    print("SpeechRecognizer: Speech recognition not determined")
                    self?.isAvailable = false
                @unknown default:
                    print("SpeechRecognizer: Speech recognition unknown status")
                    self?.isAvailable = false
                }
            }
        }
    }

    func startTranscribing() {
        print("SpeechRecognizer: startTranscribing called - isAvailable: \(isAvailable), isTranscribing: \(isTranscribing)")
        guard isAvailable, !isTranscribing else {
            print("SpeechRecognizer: Cannot start - not available or already transcribing")
            return
        }

        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("SpeechRecognizer: Audio session configured successfully")
        } catch {
            print("SpeechRecognizer: Audio session setup failed: \(error)")
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request")
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
            return
        }

        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            var isFinal = false

            if let result = result {
                let newTranscript = result.bestTranscription.formattedString
                print("SpeechRecognizer: Got result: '\(newTranscript)' (isFinal: \(result.isFinal))")
                DispatchQueue.main.async {
                    self?.transcript = newTranscript
                }
                isFinal = result.isFinal
            }

            if let error = error {
                print("SpeechRecognizer: Recognition error: \(error)")
            }

            if error != nil || isFinal {
                print("SpeechRecognizer: Recognition ended - error: \(error != nil), isFinal: \(isFinal)")
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self?.recognitionRequest = nil
                self?.recognitionTask = nil

                DispatchQueue.main.async {
                    self?.isTranscribing = false
                }
            }
        }

        isTranscribing = true
        print("SpeechRecognizer: Started transcribing successfully")
    }

    func stopTranscribing() {
        print("SpeechRecognizer: stopTranscribing called - isTranscribing: \(isTranscribing), current transcript: '\(transcript)'")
        guard isTranscribing else { return }

        // Safely stop the audio engine and clean up
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        // Don't cancel immediately - let it finish gracefully
        // recognitionTask?.cancel()

        isTranscribing = false
        print("SpeechRecognizer: Stopped transcribing - final transcript: '\(transcript)'")
    }

    func reset() {
        stopTranscribing()
        transcript = ""

        // Additional cleanup to prevent engine issues
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // Remove any existing taps to prevent conflicts
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest = nil
        recognitionTask = nil
    }
}
