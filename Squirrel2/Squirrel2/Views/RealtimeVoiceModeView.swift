//
//  RealtimeVoiceModeView.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import SwiftUI
import OpenAIRealtime

struct RealtimeVoiceModeView: View {
    @StateObject private var voiceAI = VoiceAIManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false
    @State private var showError = false
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            if voiceAI.isLoadingKey {
                loadingView
            } else {
                mainContent
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
        .onChange(of: voiceAI.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss {
                // Auto-dismiss after simple command
                Task {
                    await voiceAI.closeVoiceMode()
                    dismiss()
                }
            }
        }
        .onAppear {
            // Auto-start listening immediately (already connected)
            Task {
                do {
                    print("🚀 Starting voice mode...")
                    
                    // Check if already connected from pre-initialization
                    if !voiceAI.isConnected {
                        // Connect if not already connected
                        try await voiceAI.startHandlingVoice()
                        print("✅ Voice handling started")
                    } else {
                        print("✅ Already connected to Realtime API")
                    }
                    
                    // Start listening immediately
                    try await voiceAI.startListening()
                    isRecording = true
                    
                    // Send initial prompt if available
                    if let initialPrompt = voiceAI.getInitialPrompt() {
                        print("📨 Sending initial prompt: \(initialPrompt)")
                        try await voiceAI.sendMessage(initialPrompt)
                        // Clear the initial prompt after sending
                        voiceAI.clearInitialPrompt()
                    }
                    
                    print("🎙️ Voice mode ready")
                } catch {
                    print("❌ Failed to start voice mode: \(error)")
                    voiceAI.error = error.localizedDescription
                    isRecording = false
                }
            }
        }
        .onDisappear {
            Task {
                await voiceAI.closeVoiceMode()
            }
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.squirrelWarmBackground, Color.squirrelWarmGrayBackground],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Setting up voice AI...")
                .font(.squirrelHeadline)
                .foregroundColor(.squirrelTextSecondary)
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 30) {
                    // Header
                    HStack {
                    Button("Cancel") {
                        Task {
                            await voiceAI.closeVoiceMode()
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
                
                // Current transcript display
                VStack(spacing: 20) {
                    // Show current status
                    if voiceAI.isListening {
                        HStack(spacing: 12) {
                            Image(systemName: "mic.fill")
                                .foregroundColor(.red)
                                .font(.title3)
                                .symbolEffect(.pulse)
                            Text("Listening...")
                                .font(.squirrelHeadline)
                                .foregroundColor(.squirrelTextPrimary)
                        }
                    } else if voiceAI.isConnected {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("Ready")
                                .font(.squirrelHeadline)
                                .foregroundColor(.squirrelTextPrimary)
                        }
                    }
                    
                    // Show current transcript
                    if !voiceAI.currentTranscript.isEmpty {
                        Text(voiceAI.currentTranscript)
                            .font(.squirrelBody)
                            .foregroundColor(.squirrelTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    
                    // Show last AI response (simplified)
                    if let lastAssistantMessage = voiceAI.messages.last(where: { $0.role == .assistant }) {
                        let content = lastAssistantMessage.content.compactMap { content in
                            switch content {
                            case .text(let text):
                                return text
                            case .audio(let audio):
                                return audio.transcript
                            default:
                                return nil
                            }
                        }.joined(separator: " ")
                        
                        if !content.isEmpty {
                            Text(content)
                                .font(.squirrelBody)
                                .foregroundColor(.squirrelTextPrimary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                                .background(Color.squirrelSurfaceBackground)
                                .cornerRadius(16)
                        }
                    }
                }
                .padding()
                .frame(maxHeight: 300)
                
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
