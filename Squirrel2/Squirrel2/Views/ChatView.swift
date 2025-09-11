//
//  ChatView.swift
//  Squirrel2
//
//  Main chat view
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatView: View {
    @Binding var showingCameraMode: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var aiManager = ChatAIManager()
    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var conversation: ChatConversation?
    @State private var showingChatMode = false
    @State private var streamingMessageId: String?
    @State private var streamingMessageContent = ""
    @FocusState private var isInputFocused: Bool
    
    // Camera states
    @State private var isCameraActive = false
    @State private var capturedImage: UIImage?
    @State private var isCapturing = false
    @State private var cameraError: String?
    @State private var isProcessingPhoto = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Camera background when active
                if isCameraActive {
                    CameraPreviewView(
                        capturedImage: $capturedImage,
                        isCapturing: $isCapturing,
                        onError: { error in
                            cameraError = error
                            isCameraActive = false
                        }
                    )
                    .ignoresSafeArea()
                    
                    // Camera overlay controls
                    cameraOverlay
                }
                
                // Normal chat/voice view
                if !isCameraActive {
                    if !showingChatMode {
                        VoiceDefaultView(
                            conversation: $conversation,
                            messages: $messages,
                            onSwitchToChat: {
                                showingChatMode = true
                            },
                            onDismiss: {
                                dismiss()
                            }
                        )
                        .transition(.opacity)
                    } else {
                        // Chat mode
                        VStack(spacing: 0) {
                            chatContent
                            ChatInputBar(
                                messageText: $messageText,
                                isLoading: isLoading,
                                onSend: sendMessage
                            )
                        }
                        .navigationTitle(conversation?.title ?? "Chat")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Close") {
                                    dismiss()
                                }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showingChatMode = false
                                    }
                                }) {
                                    Image(systemName: "mic.circle.fill")
                                        .foregroundColor(.squirrelPrimary)
                                        .font(.system(size: 22))
                                }
                            }
                        }
                        .background(Color.squirrelSurfaceBackground)
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingChatMode)
        .animation(.easeInOut(duration: 0.3), value: isCameraActive)
        .onAppear {
            setupConversation()
            
            // Check if camera mode was requested
            if showingCameraMode {
                isCameraActive = true
                showingCameraMode = false
            }
            
            // Initialize VoiceAIManager for this conversation with chat history
            Task {
                let convId = conversation?.id ?? UUID().uuidString
                await VoiceAIManager.shared.initialize(withChatHistory: messages, conversationId: convId)
                print("✅ VoiceAIManager initialized with \(messages.count) messages of context")
            }
        }
        .onDisappear {
            // Clean up VoiceAIManager when leaving chat
            Task {
                await VoiceAIManager.shared.disconnect()
                print("✅ VoiceAIManager disconnected")
            }
        }
        .onChange(of: capturedImage) { _, image in
            if let image = image {
                processPhoto(image)
            }
        }
        .alert("Camera Error", isPresented: .constant(cameraError != nil)) {
            Button("OK") { cameraError = nil }
        } message: {
            Text(cameraError ?? "")
        }
    }
    
    @ViewBuilder
    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty && !isLoading {
                        emptyState
                    } else {
                        ForEach(messages) { message in
                            if message.id == streamingMessageId {
                                MessageBubble(message: ChatMessage(
                                    id: message.id,
                                    content: streamingMessageContent,
                                    isFromUser: message.isFromUser,
                                    timestamp: message.timestamp,
                                    conversationId: message.conversationId
                                ))
                                .id(message.id)
                            } else {
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    
                    if isLoading {
                        loadingIndicator
                            .id("loading")
                    }
                }
                .padding(.vertical, 20)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isLoading) { _, loading in
                if loading {
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.squirrelPrimary.opacity(0.5))
            
            Text("Start a conversation")
                .font(.squirrelHeadline)
                .foregroundColor(.squirrelTextSecondary)
            
            Text("Type a message below to begin")
                .font(.squirrelSubheadline)
                .foregroundColor(.squirrelTextSecondary.opacity(0.8))
        }
        .padding(.top, 100)
    }
    
    @ViewBuilder
    private var loadingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.squirrelPrimary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isLoading ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isLoading
                    )
            }
        }
        .padding(.vertical, 20)
    }
    
    private func saveMessage(_ message: ChatMessage, to conversation: ChatConversation) async {
        guard let user = firebaseManager.currentUser else { return }
        
        do {
            // Get proper Firebase auth token
            let token = try await user.getIDToken()
            
            let messageData: [String: Any] = [
                "content": message.content,
                "isFromUser": message.isFromUser,
                "timestamp": message.timestamp.ISO8601Format(),
                "conversationId": message.conversationId,
                "source": message.source.rawValue,
                "voiceTranscript": message.voiceTranscript as Any,
                "metadata": [
                    "source": message.source.rawValue
                ]
            ]
            
            guard let url = URL(string: "\(AppConfig.apiBaseURL)/messages") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let jsonData = try JSONSerialization.data(withJSONObject: messageData)
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 201 {
                    print("✅ Message saved via backend API")
                } else {
                    print("Error saving message: HTTP \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("Error saving message: \(error)")
        }
    }
    
    private func setupConversation() {
        guard let user = firebaseManager.currentUser else { return }
        
        Task {
            do {
                // Get Firebase auth token
                let token = try await user.getIDToken()
                
                // Create conversation via backend API
                let conversationData: [String: Any] = [
                    "title": "New Chat"
                ]
                
                guard let url = URL(string: "\(AppConfig.apiBaseURL)/conversations") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let jsonData = try JSONSerialization.data(withJSONObject: conversationData)
                request.httpBody = jsonData
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 201 {
                    
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let id = responseDict["id"] as? String {
                        
                        let newConversation = ChatConversation(
                            id: id,
                            title: responseDict["title"] as? String ?? "New Chat",
                            userId: user.uid
                        )
                        
                        await MainActor.run {
                            self.conversation = newConversation
                            self.loadMessages()
                        }
                        
                        print("✅ Created conversation via backend: \(id)")
                    }
                } else {
                    print("Error creating conversation: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
            } catch {
                print("Error creating conversation: \(error)")
            }
        }
    }
    
    private func loadMessages() {
        guard let conversationId = conversation?.id else { return }
        
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error loading messages: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                self.messages = documents.compactMap { document in
                    let data = document.data()
                    return ChatMessage(
                        id: document.documentID,
                        content: data["content"] as? String ?? "",
                        isFromUser: data["isFromUser"] as? Bool ?? false,
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                        conversationId: conversationId
                    )
                }
            }
    }
    
    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              let conversationId = conversation?.id else { return }
        
        // Create user message
        let userMessage = ChatMessage(
            content: content,
            isFromUser: true,
            conversationId: conversationId,
            source: .text
        )
        
        // Clear input
        messageText = ""
        isInputFocused = false
        
        // Save user message via backend API
        Task {
            guard let conversation = self.conversation else { return }
            await saveMessage(userMessage, to: conversation)
            
            // Simulate AI response after message is saved
            self.simulateAIResponse(for: content, conversationId: conversationId)
        }
        
        // Update conversation's last message timestamp
        db.collection("conversations")
            .document(conversationId)
            .updateData(["lastMessageAt": Timestamp(date: Date())])
    }
    
    private func simulateAIResponse(for userMessage: String, conversationId: String) {
        isLoading = true
        
        Task {
            do {
                // Create AI response message placeholder
                let aiResponse = ChatMessage(
                    content: "",
                    isFromUser: false,
                    conversationId: conversationId
                )
                
                // Set up streaming
                streamingMessageId = aiResponse.id
                streamingMessageContent = ""
                
                // Add placeholder to messages for immediate UI feedback
                await MainActor.run {
                    self.messages.append(aiResponse)
                }
                
                // Stream AI response
                try await aiManager.streamMessageWithHistory(
                    userMessage,
                    history: messages.dropLast() // Don't include the placeholder in history
                ) { chunk in
                    // Update streaming content
                    self.streamingMessageContent += chunk
                }
                
                // Save complete message to Firestore
                let finalContent = streamingMessageContent
                // Create response data with explicit types to avoid Sendable warning
                let responseTimestamp = Timestamp(date: aiResponse.timestamp)
                let responseId = aiResponse.id
                let responseIsFromUser = aiResponse.isFromUser
                
                let messageData: [String: Any] = [
                    "content": finalContent,
                    "isFromUser": responseIsFromUser,
                    "timestamp": responseTimestamp,
                    "conversationId": conversationId
                ]
                
                try await db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .document(responseId)
                    .setData(messageData)
                
                // Update conversation's last message timestamp
                let updateData: [String: Any] = ["lastMessageAt": Timestamp(date: Date())]
                try await db.collection("conversations")
                    .document(conversationId)
                    .updateData(updateData)
                
                await MainActor.run {
                    // Update the message in the array with final content
                    if let index = self.messages.firstIndex(where: { $0.id == aiResponse.id }) {
                        self.messages[index] = ChatMessage(
                            id: aiResponse.id,
                            content: finalContent,
                            isFromUser: false,
                            timestamp: aiResponse.timestamp,
                            conversationId: conversationId
                        )
                    }
                    
                    self.streamingMessageId = nil
                    self.streamingMessageContent = ""
                    self.isLoading = false
                }
                
            } catch {
                print("Error getting AI response: \(error)")
                await MainActor.run {
                    // Remove placeholder message if exists
                    if let streamId = self.streamingMessageId {
                        self.messages.removeAll { $0.id == streamId }
                    }
                    
                    self.streamingMessageId = nil
                    self.streamingMessageContent = ""
                    self.isLoading = false
                    
                    // Show error message to user
                    let errorMessage = ChatMessage(
                        content: "Sorry, I couldn't process your message. Error: \(error.localizedDescription)",
                        isFromUser: false,
                        conversationId: conversationId
                    )
                    
                    let errorData: [String: Any] = [
                        "content": errorMessage.content,
                        "isFromUser": errorMessage.isFromUser,
                        "timestamp": Timestamp(date: errorMessage.timestamp),
                        "conversationId": conversationId
                    ]
                    
                    self.db.collection("conversations")
                        .document(conversationId)
                        .collection("messages")
                        .document(errorMessage.id)
                        .setData(errorData)
                }
            }
        }
    }
    
    @ViewBuilder
    private var cameraOverlay: some View {
        VStack {
            // Top bar with close button
            HStack {
                Button(action: {
                    isCameraActive = false
                    capturedImage = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .padding()
                
                Spacer()
            }
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 20) {
                if isProcessingPhoto {
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Processing photo...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    .padding()
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                }
                
                // Capture button
                Button(action: {
                    isCapturing = true
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 70, height: 70)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(isCapturing || isProcessingPhoto)
                .opacity((isCapturing || isProcessingPhoto) ? 0.5 : 1.0)
            }
            .padding(.bottom, 50)
        }
    }
    
    private func processPhoto(_ image: UIImage) {
        guard let user = firebaseManager.currentUser else { return }
        
        isProcessingPhoto = true
        
        Task {
            do {
                let token = try await user.getIDToken()
                
                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    cameraError = "Failed to process image"
                    isProcessingPhoto = false
                    return
                }
                
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
                    print("Photo upload response status: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                        if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let success = responseDict["success"] as? Bool,
                           success {
                            
                            await MainActor.run {
                                // Success - close camera and show confirmation
                                isCameraActive = false
                                capturedImage = nil
                                isProcessingPhoto = false
                                
                                // Could show a success toast here
                                if let collectionName = responseDict["collectionName"] as? String {
                                    print("✅ Photo saved to \(collectionName)")
                                }
                            }
                        } else {
                            // Parse error from response
                            let errorMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                            await MainActor.run {
                                cameraError = errorMessage ?? "Failed to process photo"
                                isProcessingPhoto = false
                            }
                        }
                    } else {
                        // Try to get error details from response
                        let errorDetails = String(data: data, encoding: .utf8) ?? "Unknown error"
                        print("Photo upload error: \(errorDetails)")
                        
                        await MainActor.run {
                            cameraError = "Upload failed (Status: \(httpResponse.statusCode))"
                            isProcessingPhoto = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    cameraError = "Error: \(error.localizedDescription)"
                    isProcessingPhoto = false
                }
            }
        }
    }
}

#Preview {
    ChatView(showingCameraMode: .constant(false))
        .environmentObject(FirebaseManager.shared)
}
