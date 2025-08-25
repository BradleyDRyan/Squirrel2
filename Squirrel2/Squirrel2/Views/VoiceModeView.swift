//
//  VoiceModeView.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import AVFoundation
import SwiftUI

struct VoiceModeView: View {
    @Binding var isRecording: Bool
    @Binding var transcription: String
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var speechRecognizer: SpeechRecognizer

    var body: some View {
        ZStack {
            Color.squirrelWarmBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                // Recording Button
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.orange)
                            .frame(width: 120, height: 120)
                            .scaleEffect(isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording)

                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                }
                .disabled(!audioRecorder.isReady)

                // Recording Status
                VStack(spacing: 8) {
                    if isRecording {
                        Text("Recording...")
                            .font(.headline)
                            .foregroundColor(.red)

                        // Duration display
                        Text(formatDuration(audioRecorder.recordingDuration))
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        // 60-second limit warning
                        if audioRecorder.recordingDuration > 50 {
                            Text("⏰ \(60 - Int(audioRecorder.recordingDuration))s remaining")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else if audioRecorder.recordingURL != nil {
                        Text("Recording saved")
                            .font(.headline)
                            .foregroundColor(.green)

                        Button("Play Recording") {
                            audioRecorder.playRecording()
                        }
                        .font(.subheadline)
                        .foregroundColor(Color.squirrelPrimary)
                    } else {
                        Text("Tap to start recording")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }

                // Real-time transcription status
                if speechRecognizer.isTranscribing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onReceive(speechRecognizer.$transcript) { newTranscript in
            transcription = newTranscript
        }
        .onReceive(audioRecorder.$recordingDuration) { duration in
            // Auto-stop at 60 seconds
            if duration >= 60.0 && isRecording {
                stopRecording()
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        audioRecorder.startRecording()
        speechRecognizer.startTranscribing()
        isRecording = true
    }

    private func stopRecording() {
        audioRecorder.stopRecording()
        speechRecognizer.stopTranscribing()
        isRecording = false
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    VoiceModeView(
        isRecording: .constant(false),
        transcription: .constant(""),
        audioRecorder: AudioRecorder(),
        speechRecognizer: SpeechRecognizer()
    )
}
