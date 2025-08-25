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
    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var conversation: ChatConversation?
    @State private var showingVoiceMode = false
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
                            MessageBubble(message: message)
                                .id(message.id)
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
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let aiResponse = ChatMessage(
                content: "I understand you said: \"\(userMessage)\". This is a simulated response. Integration with Claude API would go here.",
                isFromUser: false,
                conversationId: conversationId
            )
            
            let responseData: [String: Any] = [
                "content": aiResponse.content,
                "isFromUser": aiResponse.isFromUser,
                "timestamp": Timestamp(date: aiResponse.timestamp),
                "conversationId": conversationId
            ]
            
            self.db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(aiResponse.id)
                .setData(responseData) { error in
                    self.isLoading = false
                    if let error = error {
                        print("Error saving AI response: \(error)")
                    }
                }
            
            // Update conversation's last message timestamp
            self.db.collection("conversations")
                .document(conversationId)
                .updateData(["lastMessageAt": Timestamp(date: Date())])
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(FirebaseManager.shared)
}
