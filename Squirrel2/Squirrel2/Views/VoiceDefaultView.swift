//
//  VoiceDefaultView.swift
//  Squirrel2
//
//  Voice interface with real-time API and camera button
//

import SwiftUI
import PhotosUI

struct VoiceDefaultView: View {
    @Binding var conversation: ChatConversation?
    @Binding var messages: [ChatMessage]
    let onSwitchToChat: () -> Void
    let onDismiss: () -> Void
    
    @StateObject private var voiceManager = VoiceAIManager.shared
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Close") {
                    onDismiss()
                }
                .foregroundColor(.squirrelPrimary)
                
                Spacer()
                
                // Connection status
                if voiceManager.isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if isConnecting {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onSwitchToChat) {
                    Image(systemName: "text.bubble")
                        .foregroundColor(.squirrelPrimary)
                }
            }
            .padding()
            
            Spacer()
            
            // Main voice UI
            VStack(spacing: 40) {
                // Animated voice indicator
                ZStack {
                    if voiceManager.isListening {
                        // Pulsing circles when listening
                        ForEach(0..<3) { index in
                            Circle()
                                .stroke(Color.squirrelPrimary.opacity(0.3), lineWidth: 2)
                                .frame(width: 150 + CGFloat(index * 50), 
                                       height: 150 + CGFloat(index * 50))
                                .scaleEffect(voiceManager.isListening ? 1.2 : 1.0)
                                .opacity(voiceManager.isListening ? 0.0 : 0.5)
                                .animation(
                                    Animation.easeOut(duration: 1.5)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(index) * 0.3),
                                    value: voiceManager.isListening
                                )
                        }
                    }
                    
                    // Center microphone icon
                    Circle()
                        .fill(voiceManager.isListening ? Color.squirrelPrimary : Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: voiceManager.isListening ? "mic.fill" : "mic.slash.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        )
                        .scaleEffect(voiceManager.isSpeaking ? 0.95 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: voiceManager.isSpeaking)
                }
                
                // Status text
                VStack(spacing: 8) {
                    if let error = connectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if voiceManager.isSpeaking {
                        Text("Speaking...")
                            .font(.headline)
                            .foregroundColor(.squirrelPrimary)
                    } else if voiceManager.isListening {
                        Text("Listening...")
                            .font(.headline)
                            .foregroundColor(.squirrelPrimary)
                    } else if voiceManager.isConnected {
                        Text("Tap to start")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Connecting to voice assistant...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let transcript = voiceManager.lastTranscript, !transcript.isEmpty {
                        Text(transcript)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .lineLimit(3)
                    }
                }
                
                // Action buttons
                HStack(spacing: 40) {
                    // Camera button
                    Button(action: {
                        showingCamera = true
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
                    
                    // Photo picker button
                    PhotosPicker(selection: $selectedPhoto,
                                matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.squirrelPrimary)
                                .frame(width: 60, height: 60)
                                .background(Color.squirrelPrimary.opacity(0.1))
                                .clipShape(Circle())
                            
                            Text("Photos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            
            Spacer()
        }
        .background(Color.squirrelBackground)
        .onAppear {
            connectToVoiceAPI()
        }
        .onDisappear {
            Task {
                await voiceManager.disconnect()
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView { image in
                handleCapturedPhoto(image)
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    handleCapturedPhoto(uiImage)
                }
            }
        }
    }
    
    private func connectToVoiceAPI() {
        isConnecting = true
        connectionError = nil
        
        Task {
            do {
                let convId = conversation?.id ?? UUID().uuidString
                await voiceManager.initialize(withChatHistory: messages, conversationId: convId)
                
                if !voiceManager.isConnected {
                    try await voiceManager.connect()
                }
                
                await MainActor.run {
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    connectionError = "Failed to connect: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleCapturedPhoto(_ image: UIImage) {
        // Process and save the photo
        Task {
            await processPhoto(image)
        }
    }
    
    private func processPhoto(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to data")
            return
        }
        
        guard let user = VoiceAIManager.shared.firebaseManager?.currentUser else {
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
                        await MainActor.run {
                            // You could add a toast or alert here
                            if let message = responseDict["message"] as? String {
                                print(message)
                            }
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