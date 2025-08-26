//
//  AudioRecorder.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import AVFoundation
import Foundation
import SwiftUI

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isReady = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            // Request permission using AVAudioApplication (iOS 17+)
            AVAudioApplication.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    self?.isReady = allowed
                }
            }
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    func startRecording() {
        guard isReady, !isRecording else { return }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "recording-\(Date().timeIntervalSince1970).m4a"
        let audioURL = documentsPath.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            recordingURL = audioURL
            recordingDuration = 0
            recordingStartTime = Date() // Record when we started

            // Start timer to update duration
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.updateRecordingDuration()
            }

        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        recordingStartTime = nil
    }

    func playRecording() {
        guard let url = recordingURL else { return }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Failed to play recording: \(error)")
        }
    }

    func reset() {
        stopRecording()
        audioPlayer?.stop()
        recordingURL = nil
        recordingDuration = 0
        recordingStartTime = nil
    }

    private func updateRecordingDuration() {
        guard let recorder = audioRecorder, recorder.isRecording, let startTime = recordingStartTime else { return }
        // Calculate duration from start time instead of using accumulated recorder.currentTime
        recordingDuration = Date().timeIntervalSince(startTime)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            print("Recording finished successfully")
        } else {
            print("Recording failed")
            recordingURL = nil
        }
        isRecording = false
    }

    func audioRecorderEncodeErrorDidOccur(_: AVAudioRecorder, error: Error?) {
        print("Recording error: \(error?.localizedDescription ?? "Unknown error")")
        isRecording = false
        recordingURL = nil
    }
}
