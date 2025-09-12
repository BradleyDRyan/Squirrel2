//
//  VoiceDefaultView.swift
//  Squirrel2
//
//  Voice mode default view with camera support
//

import SwiftUI
import FirebaseAuth

// Voice mode as default view
struct VoiceDefaultView: View {
    @StateObject private var voiceAI = VoiceAIManager.shared
    @State private var isRecording = false
    @State private var showError = false
    @State private var showingPhotoPicker = false
    @Binding var conversation: ChatConversation?
    @Binding var messages: [ChatMessage]
    let onSwitchToChat: () -> Void
    let onDismiss: () -> Void
    let onCameraActivate: () -> Void
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            mainContent
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
                Task {
                    await voiceAI.closeVoiceMode()
                    onDismiss()
                }
            }
        }
        .onAppear {
            Task {
                do {
                    print("🚀 Starting voice mode...")
                    
                    if !voiceAI.isConnected {
                        try await voiceAI.startHandlingVoice()
                        print("✅ Voice handling started")
                    } else {
                        print("✅ Already connected to Realtime API")
                    }
                    
                    try await voiceAI.startListening()
                    isRecording = true
                    
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
                // Merge voice messages back into chat
                let voiceMessages = VoiceAIManager.shared.getVoiceMessages()
                if !voiceMessages.isEmpty {
                    messages.append(contentsOf: voiceMessages)
                    print("✅ Merged \(voiceMessages.count) voice messages into chat")
                }
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
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel") {
                    Task {
                        await voiceAI.closeVoiceMode()
                        onDismiss()
                    }
                }
                .foregroundColor(.squirrelTextSecondary)
                
                Spacer()
                
                Text("Voice Mode")
                    .font(.squirrelHeadline)
                    .foregroundColor(.squirrelTextPrimary)
                
                Spacer()
                
                Circle()
                    .fill(voiceAI.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Spacer()
            
            // Current transcript display
            VStack(spacing: 20) {
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
                
                if !voiceAI.currentTranscript.isEmpty {
                    Text(voiceAI.currentTranscript)
                        .font(.squirrelBody)
                        .foregroundColor(.squirrelTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                if let lastAssistantMessage = voiceAI.messages.last(where: { !$0.isFromUser }) {
                    let content = lastAssistantMessage.content
                    
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
            
            Text(statusText)
                .font(.squirrelCallout)
                .foregroundColor(.squirrelTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if voiceAI.messages.last?.isFromUser == false {
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
            
            // Camera button
            HStack(spacing: 40) {
                Button(action: {
                    onCameraActivate()
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.squirrelPrimary)
                            .frame(width: 60, height: 60)
                            .background(Color.squirrelPrimary.opacity(0.1))
                            .clipShape(Circle())
                        
                        Text("Camera")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.bottom, 20)
            
            Spacer()
            
            // Switch to Chat Mode button at the bottom
            Button(action: {
                onSwitchToChat()
            }) {
                HStack {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 18))
                    Text("Switch to Chat")
                        .font(.squirrelButtonSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.squirrelSurfaceBackground)
                .foregroundColor(.squirrelTextPrimary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.squirrelPrimary.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
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
    
    private func processPhoto(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to data")
            return
        }
        
        guard let user = FirebaseManager.shared.currentUser else {
            print("No authenticated user")
            return
        }
        
        do {
            let token = try await user.getIDToken()
            
            // Create multipart form data
            let boundary = UUID().uuidString
            var body = Data()
            
            // Add image data
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Create request
            guard let url = URL(string: "\(AppConfig.apiBaseURL)/photos/process") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            
            // Send request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = responseDict["success"] as? Bool,
                       success {
                        print("✅ Photo processed and saved to collection: \(responseDict["collectionName"] ?? "unknown")")
                        
                        // Show success feedback
                        if let message = responseDict["message"] as? String {
                            print(message)
                            // You could update the UI here to show success
                        }
                    }
                } else {
                    print("Error processing photo: HTTP \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("Error uploading photo: \(error)")
        }
    }
}