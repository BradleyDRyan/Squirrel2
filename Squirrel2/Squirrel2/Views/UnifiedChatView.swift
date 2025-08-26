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
    @FocusState private var isInputFocused: Bool
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Voice mode is default
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
        .animation(.easeInOut(duration: 0.3), value: showingChatMode)
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
}

// Voice mode as default view
struct VoiceDefaultView: View {
    @StateObject private var voiceAI = VoiceAIManager.shared
    @State private var isRecording = false
    @State private var showError = false
    @State private var showVoiceIntent = false  // New: Show intent capture first
    @Binding var conversation: ChatConversation?
    @Binding var messages: [ChatMessage]
    let onSwitchToChat: () -> Void
    let onDismiss: () -> Void
    
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
                Task {
                    await voiceAI.closeVoiceMode()
                    onDismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $showVoiceIntent) {
            VoiceIntentView()
        }
        .onAppear {
            // Don't auto-start Realtime anymore
            // Wait for user to tap mic button which shows intent view
            print("🎤 Voice mode ready - tap mic to start")
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
        if isRecording {
            // Stop existing Realtime recording
            Task {
                await voiceAI.stopListening()
                isRecording = false
            }
        } else {
            // Show intent capture view instead of directly starting Realtime
            showVoiceIntent = true
        }
    }
}

#Preview {
    UnifiedChatView()
        .environmentObject(FirebaseManager.shared)
}