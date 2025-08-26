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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var aiManager = ChatAIManager()
    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var conversation: ChatConversation?
    @State private var showingVoiceMode = false
    @State private var streamingMessageId: String?
    @State private var streamingMessageContent = ""
    @FocusState private var isInputFocused: Bool
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
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
                        showingVoiceMode = true
                    }) {
                        Image(systemName: "mic.circle.fill")
                            .foregroundColor(.squirrelPrimary)
                            .font(.system(size: 22))
                    }
                }
            }
            .background(Color.squirrelSurfaceBackground)
        }
        .onAppear {
            setupConversation()
        }
        .sheet(isPresented: $showingVoiceMode) {
            RealtimeVoiceModeView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
    
    private func setupConversation() {
        guard let userId = firebaseManager.currentUser?.uid else { return }
        
        // Create a new conversation
        let newConversation = ChatConversation(
            title: "New Chat",
            userId: userId
        )
        
        // Save to Firestore
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
            conversationId: conversationId
        )
        
        // Clear input
        messageText = ""
        isInputFocused = false
        
        // Save user message to Firestore
        let messageData: [String: Any] = [
            "content": userMessage.content,
            "isFromUser": userMessage.isFromUser,
            "timestamp": Timestamp(date: userMessage.timestamp),
            "conversationId": conversationId
        ]
        
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(userMessage.id)
            .setData(messageData) { error in
                if let error = error {
                    print("Error sending message: \(error)")
                    return
                }
                
                // Simulate AI response (replace with actual AI service)
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
}

#Preview {
    ChatView()
        .environmentObject(FirebaseManager.shared)
}
