//
//  RealtimeVoiceModeView.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import SwiftUI
import OpenAIRealtime

struct RealtimeVoiceModeView: View {
    @StateObject private var voiceAI = VoiceAIManager()
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false
    @State private var showError = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.squirrelWarmBackground, Color.squirrelWarmGrayBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if voiceAI.isLoadingKey {
                // Loading state while fetching API key
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Setting up voice AI...")
                        .font(.squirrelHeadline)
                        .foregroundColor(.squirrelTextSecondary)
                }
            } else {
                VStack(spacing: 30) {
                    // Header
                    HStack {
                    Button("Cancel") {
                        Task {
                            await voiceAI.disconnect()
                            dismiss()
                        }
                    }
                    .foregroundColor(.squirrelTextSecondary)
                    
                    Spacer()
                    
                    Text("Voice Mode")
                        .font(.squirrelHeadline)
                        .foregroundColor(.squirrelTextPrimary)
                    
                    Spacer()
                    
                    // Connection status indicator
                    Circle()
                        .fill(voiceAI.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                }
                .padding(.horizontal)
                .padding(.top)
                
                Spacer()
                
                // Messages/Transcript Display
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(voiceAI.messages, id: \.id) { message in
                            MessageBubbleView(message: message)
                        }
                        
                        if !voiceAI.currentTranscript.isEmpty && isRecording {
                            HStack {
                                Image(systemName: "mic.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text(voiceAI.currentTranscript)
                                    .font(.squirrelBody)
                                    .foregroundColor(.squirrelTextSecondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 400)
                
                // Voice visualization
                if isRecording {
                    VoiceWaveformView()
                        .frame(height: 60)
                        .padding(.horizontal)
                }
                
                // Main recording button
                Button(action: toggleRecording) {
                    ZStack {
                        // Animated circles
                        if isRecording {
                            Circle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 2)
                                .frame(width: 140, height: 140)
                                .scaleEffect(isRecording ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isRecording)
                            
                            Circle()
                                .stroke(Color.red.opacity(0.2), lineWidth: 2)
                                .frame(width: 160, height: 160)
                                .scaleEffect(isRecording ? 1.3 : 1.0)
                                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isRecording)
                        }
                        
                        // Main button
                        Circle()
                            .fill(isRecording ? Color.red : Color.squirrelPrimary)
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            )
                            .scaleEffect(isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isRecording)
                    }
                }
                .disabled(!voiceAI.isConnected && !isRecording)
                
                // Status text
                Text(statusText)
                    .font(.squirrelCallout)
                    .foregroundColor(.squirrelTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Interrupt button (only show when AI is speaking)
                if voiceAI.messages.last?.role == .assistant {
                    Button(action: {
                        Task {
                            await voiceAI.interrupt()
                        }
                    }) {
                        Text("Interrupt")
                            .font(.squirrelButtonSecondary)
                            .foregroundColor(.squirrelSecondary)
                    }
                }
                
                Spacer()
            }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(voiceAI.error ?? "An unknown error occurred")
        }
        .onChange(of: voiceAI.error) { _, newError in
            showError = newError != nil
        }
        .onAppear {
            // Auto-start voice handling when view appears
            Task {
                do {
                    try await voiceAI.startHandlingVoice()
                    try await voiceAI.startListening()
                    isRecording = true
                } catch {
                    print("Failed to start voice mode: \(error)")
                }
            }
        }
        .onDisappear {
            Task {
                await voiceAI.disconnect()
            }
        }
    }
    
    private var statusText: String {
        if !voiceAI.isConnected {
            return "Connecting..."
        } else if isRecording {
            return "Listening... Tap to stop"
        } else {
            return "Tap to start speaking"
        }
    }
    
    private func toggleRecording() {
        Task {
            if isRecording {
                await voiceAI.stopListening()
                isRecording = false
            } else {
                do {
                    try await voiceAI.startListening()
                    isRecording = true
                } catch {
                    print("Error starting recording: \(error)")
                    voiceAI.error = error.localizedDescription
                }
            }
        }
    }
}

// Message bubble view for displaying conversation
struct MessageBubbleView: View {
    let message: Item.Message
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(messageText)
                    .font(.squirrelBody)
                    .foregroundColor(message.role == .user ? .white : .squirrelTextPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(message.role == .user ? Color.squirrelPrimary : Color.white)
                    )
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role != .user {
                Spacer()
            }
        }
    }
    
    private var messageText: String {
        message.content.compactMap { content in
            switch content {
            case .text(let text):
                return text
            case .input_text(let text):
                return text
            case .audio(let audio):
                return audio.transcript
            case .input_audio(let audio):
                return audio.transcript
            }
        }.joined(separator: " ")
    }
}

// Animated waveform visualization
struct VoiceWaveformView: View {
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.2, count: 20)
    @State private var timer: Timer?
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<amplitudes.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: 4, height: CGFloat.random(in: 10...40))
                    .animation(.easeInOut(duration: 0.3), value: amplitudes[index])
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                amplitudes = amplitudes.map { _ in CGFloat.random(in: 0.2...1.0) * 40 }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

#Preview {
    RealtimeVoiceModeView()
}
