//
//  UnifiedChatView.swift
//  Squirrel2
//
//  Unified chat view with voice as default
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct UnifiedChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var aiManager = ChatAIManager()
    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var conversation: ChatConversation?
    @State private var streamingMessageId: String?
    @State private var streamingMessageContent = ""
    @State private var showingChatMode = false
    @State private var showingCameraMode = false
    @State private var capturedImage: UIImage?
    @State private var isProcessingPhoto = false
    @FocusState private var isInputFocused: Bool
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Camera mode overlay (shows behind voice/chat modes)
                if showingCameraMode {
                    CameraPreviewView(
                        capturedImage: $capturedImage,
                        isCapturing: $isProcessingPhoto,
                        onError: { errorMessage in
                            print("Camera error: \(errorMessage)")
                            showingCameraMode = false
                        }
                    )
                    .ignoresSafeArea()
                    .overlay(
                        VStack {
                            Spacer()
                            captureControls
                                .padding(.bottom, 50)
                        }
                    )
                }
                
                // Voice mode is default
                if !showingChatMode && !showingCameraMode {
                    VoiceDefaultView(
                        conversation: $conversation,
                        messages: $messages,
                        onSwitchToChat: {
                            showingChatMode = true
                        },
                        onDismiss: {
                            dismiss()
                        },
                        onCameraActivate: {
                            print("📸 [Photo] Camera button pressed - activating camera mode")
                            showingCameraMode = true
                        }
                    )
                    .transition(.opacity)
                } else if showingChatMode && !showingCameraMode {
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
        .animation(.easeInOut(duration: 0.3), value: showingChatMode)
        .animation(.easeInOut(duration: 0.3), value: showingCameraMode)
        .onChange(of: capturedImage) { _, image in
            if let image = image {
                Task {
                    await processPhoto(image)
                }
            }
        }
        .onAppear {
            setupConversation()
            
            // Initialize VoiceAIManager for this conversation
            Task {
                let convId = conversation?.id ?? UUID().uuidString
                await VoiceAIManager.shared.initialize(withChatHistory: messages, conversationId: convId)
                print("✅ VoiceAIManager initialized with \(messages.count) messages of context")
            }
        }
        .onDisappear {
            // Clean up VoiceAIManager when leaving
            Task {
                await VoiceAIManager.shared.disconnect()
                print("✅ VoiceAIManager disconnected")
            }
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
        guard let userId = firebaseManager.currentUser?.uid else { return }
        
        let newConversation = ChatConversation(
            title: "New Chat",
            userId: userId
        )
        
        let conversationData: [String: Any] = [
            "id": newConversation.id,
            "title": newConversation.title,
            "userId": newConversation.userId,
            "createdAt": Timestamp(date: newConversation.createdAt),
            "lastMessageAt": Timestamp(date: newConversation.lastMessageAt)
        ]
        
        db.collection("conversations").document(newConversation.id).setData(conversationData) { error in
            if let error = error {
                print("Error creating conversation: \(error)")
            } else {
                self.conversation = newConversation
                loadMessages()
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
                
                // Update voice AI with latest messages
                Task {
                    await VoiceAIManager.shared.updateChatHistory(self.messages)
                }
            }
    }
    
    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              let conversationId = conversation?.id else { return }
        
        let userMessage = ChatMessage(
            content: content,
            isFromUser: true,
            conversationId: conversationId,
            source: .text
        )
        
        messageText = ""
        isInputFocused = false
        
        Task {
            guard let conversation = self.conversation else { return }
            await saveMessage(userMessage, to: conversation)
            self.simulateAIResponse(for: content, conversationId: conversationId)
        }
        
        db.collection("conversations")
            .document(conversationId)
            .updateData(["lastMessageAt": Timestamp(date: Date())])
    }
    
    private func simulateAIResponse(for userMessage: String, conversationId: String) {
        isLoading = true
        
        Task {
            do {
                let aiResponse = ChatMessage(
                    content: "",
                    isFromUser: false,
                    conversationId: conversationId
                )
                
                streamingMessageId = aiResponse.id
                streamingMessageContent = ""
                
                await MainActor.run {
                    self.messages.append(aiResponse)
                }
                
                try await aiManager.streamMessageWithHistory(
                    userMessage,
                    history: messages.dropLast()
                ) { chunk in
                    self.streamingMessageContent += chunk
                }
                
                let finalContent = streamingMessageContent
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
                
                let updateData: [String: Any] = ["lastMessageAt": Timestamp(date: Date())]
                try await db.collection("conversations")
                    .document(conversationId)
                    .updateData(updateData)
                
                await MainActor.run {
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
                    if let streamId = self.streamingMessageId {
                        self.messages.removeAll { $0.id == streamId }
                    }
                    
                    self.streamingMessageId = nil
                    self.streamingMessageContent = ""
                    self.isLoading = false
                    
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
    private var captureControls: some View {
        HStack(spacing: 50) {
            // Cancel button
            Button(action: {
                print("❌ [Photo] Cancel button pressed - exiting camera mode")
                showingCameraMode = false
                capturedImage = nil
            }) {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                    )
            }
            
            // Capture button
            Button(action: {
                print("📸 [Photo] Capture button pressed - taking photo")
                // Trigger photo capture via binding
                NotificationCenter.default.post(name: NSNotification.Name("CapturePhoto"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                }
            }
            .disabled(isProcessingPhoto)
            .opacity(isProcessingPhoto ? 0.5 : 1.0)
            
            // Spacer for symmetry
            Color.clear
                .frame(width: 60, height: 60)
        }
    }
    
    private func processPhoto(_ image: UIImage) async {
        guard !isProcessingPhoto else {
            print("⚠️ [Photo] Already processing a photo, skipping")
            return
        }
        
        print("🔄 [Photo] Starting photo processing...")
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ [Photo] Failed to convert image to JPEG data")
            capturedImage = nil
            return
        }
        
        print("✅ [Photo] Image converted to JPEG, size: \(imageData.count / 1024)KB")
        
        guard let user = firebaseManager.currentUser else {
            print("❌ [Photo] No authenticated user found")
            capturedImage = nil
            return
        }
        
        print("👤 [Photo] User authenticated: \(user.uid)")
        isProcessingPhoto = true
        
        do {
            print("🔑 [Photo] Getting auth token...")
            let token = try await user.getIDToken()
            print("✅ [Photo] Auth token obtained")
            
            // Create multipart form data
            let boundary = UUID().uuidString
            var body = Data()
            
            // Add conversation ID if we have one
            if let conversationId = conversation?.id {
                print("💬 [Photo] Adding to existing conversation: \(conversationId)")
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"conversationId\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(conversationId)".data(using: .utf8)!)
                body.append("\r\n".data(using: .utf8)!)
            } else {
                print("🆕 [Photo] Will create new conversation for photo")
            }
            
            // Add image data
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Create request
            guard let url = URL(string: "\(AppConfig.apiBaseURL)/photos/process") else {
                print("❌ [Photo] Invalid API URL")
                return
            }
            
            print("📤 [Photo] Uploading to: \(url.absoluteString)")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            
            print("⏳ [Photo] Sending photo to backend (\(body.count / 1024)KB)...")
            // Send request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 [Photo] Received response: HTTP \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = responseDict["success"] as? Bool,
                       success {
                        
                        // Log success details
                        print("✅ [Photo] Photo processed successfully!")
                        if let collectionName = responseDict["collectionName"] as? String {
                            print("📁 [Photo] Saved to collection: \(collectionName)")
                        }
                        if let description = responseDict["description"] as? String {
                            print("📝 [Photo] AI description: \(description)")
                        }
                        if let message = responseDict["message"] as? String {
                            print("💬 [Photo] Status: \(message)")
                        }
                        
                        // If this created a new conversation, update our local reference
                        if conversation == nil,
                           let newConversationId = responseDict["conversationId"] as? String {
                            print("🆕 [Photo] New conversation created: \(newConversationId)")
                        }
                        
                        print("🎉 [Photo] Photo saved to Firebase Storage and processed")
                        print("🔄 [Photo] Closing camera mode and returning to voice mode")
                        
                        // Close camera mode and return to voice mode
                        await MainActor.run {
                            showingCameraMode = false
                            capturedImage = nil
                            isProcessingPhoto = false
                        }
                    } else {
                        print("❌ [Photo] Processing failed - success flag false or missing")
                        if let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("❌ [Photo] Response data: \(responseDict)")
                        }
                        await MainActor.run {
                            capturedImage = nil
                            isProcessingPhoto = false
                        }
                    }
                } else {
                    print("❌ [Photo] Error processing photo: HTTP \(httpResponse.statusCode)")
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("❌ [Photo] Error details: \(errorData)")
                    }
                    await MainActor.run {
                        capturedImage = nil
                        isProcessingPhoto = false
                    }
                }
            }
        } catch {
            print("❌ [Photo] Error uploading photo: \(error.localizedDescription)")
            print("❌ [Photo] Error details: \(error)")
            await MainActor.run {
                capturedImage = nil
                isProcessingPhoto = false
            }
        }
    }
}

#Preview {
    UnifiedChatView()
        .environmentObject(FirebaseManager.shared)
}
