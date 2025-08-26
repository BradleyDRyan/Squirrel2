//
//  ContentView.swift
//  Squirrel2
//
//  Created by Bradley Ryan on 8/25/25.
//

import SwiftUI
import FirebaseFirestore
import Combine

struct ContentView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var authService = AuthService.shared
    @State private var showingChat = false
    @State private var showingPhoneAuth = false
    @State private var isSigningIn = false
    @State private var conversations: [ChatConversation] = []
    @State private var selectedConversation: ChatConversation?
    @State private var tasks: [UserTask] = []
    @State private var showingTaskDetail = false
    @State private var selectedTask: UserTask?
    @State private var showingSettings = false
    @State private var conversationsListener: ListenerRegistration?
    @State private var tasksListener: ListenerRegistration?
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Auth status and actions
                VStack(spacing: 16) {
                    if isSigningIn {
                        // Loading state
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Setting up your account...")
                                .font(.squirrelCallout)
                                .foregroundColor(.squirrelTextSecondary)
                        }
                    } else if firebaseManager.isAuthenticated {
                        // Authenticated state
                        VStack(spacing: 16) {
                            if let phoneNumber = firebaseManager.currentUser?.phoneNumber {
                                HStack {
                                    Image(systemName: "phone.circle.fill")
                                        .foregroundColor(.squirrelPrimary.opacity(0.8))
                                    Text(phoneNumber)
                                        .font(.squirrelFootnote)
                                        .foregroundColor(.squirrelTextSecondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.squirrelSurfaceBackground)
                                .cornerRadius(20)
                            }
                            
                            /*
                            // Conversations section - commented out for now
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recent Conversations")
                                    .font(.squirrelHeadline)
                                    .foregroundColor(.squirrelTextPrimary)
                                    .padding(.horizontal, 24)
                                
                                if !conversations.isEmpty {
                                    VStack(spacing: 8) {
                                        ForEach(conversations.prefix(3)) { conversation in
                                            conversationRow(for: conversation)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                } else {
                                    Text("No conversations yet")
                                        .font(.squirrelFootnote)
                                        .foregroundColor(.squirrelTextSecondary)
                                        .padding(.horizontal, 24)
                                }
                            }
                            */
                            
                            // Tasks section with floating button
                            ZStack(alignment: .bottomTrailing) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Tasks")
                                            .font(.squirrelLargeTitle)
                                            .foregroundColor(.squirrelTextPrimary)
                                        Spacer()
                                        if !tasks.isEmpty {
                                            Text("\(tasks.filter { $0.status == .pending }.count) pending")
                                                .font(.squirrelSubheadline)
                                                .foregroundColor(.squirrelTextSecondary)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.top, 8)
                                    
                                    ScrollView {
                                        VStack(spacing: 16) {
                                            if !tasks.isEmpty {
                                                ForEach(tasks) { task in
                                                    taskRow(for: task)
                                                }
                                            } else {
                                                VStack(spacing: 12) {
                                                    Image(systemName: "checkmark.circle")
                                                        .font(.system(size: 48))
                                                        .foregroundColor(.squirrelTextSecondary.opacity(0.5))
                                                    Text("No tasks yet")
                                                        .font(.squirrelBody)
                                                        .foregroundColor(.squirrelTextSecondary)
                                                    Text("Tasks created in chat will appear here")
                                                        .font(.squirrelFootnote)
                                                        .foregroundColor(.squirrelTextSecondary.opacity(0.8))
                                                }
                                                .padding(.top, 60)
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.bottom, 80) // Extra padding for floating button
                                    }
                                    .ignoresSafeArea(edges: .horizontal)
                                }
                                
                                // Floating circular button
                                Button(action: { 
                                    selectedConversation = nil
                                    showingChat = true
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(firebaseManager.openAIKey == nil ? Color.squirrelPrimary.opacity(0.6) : Color.squirrelPrimary)
                                            .frame(width: 60, height: 60)
                                        
                                        if firebaseManager.openAIKey == nil {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "plus")
                                                .font(.system(size: 24, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                                }
                                .disabled(firebaseManager.openAIKey == nil)
                                .padding(.trailing, 24)
                                .padding(.bottom, 24)
                            }
                        }
                    } else {
                        // Not authenticated state - will auto sign in
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Preparing your experience...")
                                .font(.squirrelCallout)
                                .foregroundColor(.squirrelTextSecondary)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.squirrelBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.squirrelPrimary)
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .sheet(isPresented: $showingChat) {
            ChatView()
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showingPhoneAuth) {
            PhoneAuthView()
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(firebaseManager)
        }
        .onAppear {
            // Start real-time listeners if authenticated
            if firebaseManager.isAuthenticated {
                startConversationsListener()
                startTasksListener()
            }
            
            // Pre-warm VoiceAIManager for faster startup
            Task {
                if firebaseManager.openAIKey != nil {
                    await VoiceAIManager.shared.initialize(
                        withChatHistory: [],
                        conversationId: UUID().uuidString
                    )
                    print("🔥 VoiceAIManager pre-warmed")
                }
            }
            
            // Automatically sign in anonymously if not authenticated
            if !firebaseManager.isAuthenticated && !isSigningIn {
                Task {
                    isSigningIn = true
                    do {
                        try await authService.signInAnonymously()
                        
                        // Wait for FirebaseManager's auth state to be updated via listener
                        var retries = 0
                        while firebaseManager.currentUser == nil && retries < 20 {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            retries += 1
                        }
                        
                        // Wait for API key to be fetched
                        if firebaseManager.currentUser != nil {
                            print("✅ User authenticated: \(firebaseManager.currentUser!.uid)")
                            
                            // Wait for API key
                            var keyRetries = 0
                            while firebaseManager.openAIKey == nil && keyRetries < 30 {
                                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                keyRetries += 1
                            }
                            
                            if firebaseManager.openAIKey != nil {
                                print("✅ API key ready")
                                // Start real-time listeners after auth
                                startConversationsListener()
                                startTasksListener()
                            } else {
                                print("⚠️ API key not available after \(keyRetries) retries")
                            }
                        } else {
                            print("⚠️ Auth completed but FirebaseManager.currentUser not available after \(retries) retries")
                        }
                        
                        isSigningIn = false
                    } catch {
                        print("❌ Failed to sign in: \(error)")
                        isSigningIn = false
                        // Retry after a delay
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        if !firebaseManager.isAuthenticated {
                            try? await authService.signInAnonymously()
                        }
                    }
                }
            }
        }
        .onDisappear {
            // Clean up listeners when view disappears
            conversationsListener?.remove()
            tasksListener?.remove()
        }
    }
    
    @ViewBuilder
    private var conversationsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Conversations")
                .font(.squirrelHeadline)
                .foregroundColor(.squirrelTextPrimary)
                .padding(.horizontal, 24)
            
            VStack(spacing: 8) {
                ForEach(conversations.prefix(3)) { conversation in
                    conversationRow(for: conversation)
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func conversationRow(for conversation: ChatConversation) -> some View {
        Button(action: {
            selectedConversation = conversation
            showingChat = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.squirrelBody)
                        .foregroundColor(.squirrelTextPrimary)
                        .lineLimit(1)
                    
                    Text(formatDate(conversation.lastMessageAt))
                        .font(.squirrelFootnote)
                        .foregroundColor(.squirrelTextSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.squirrelTextSecondary.opacity(0.5))
            }
            .padding(12)
            .background(Color.squirrelSurfaceBackground)
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var tasksList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.squirrelHeadline)
                    .foregroundColor(.squirrelTextPrimary)
                Spacer()
                Text("\(tasks.filter { $0.status == .pending }.count) pending")
                    .font(.squirrelFootnote)
                    .foregroundColor(.squirrelTextSecondary)
            }
            .padding(.horizontal, 24)
            
            VStack(spacing: 8) {
                ForEach(tasks.prefix(3)) { task in
                    taskRow(for: task)
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    private func taskRow(for task: UserTask) -> some View {
        Button(action: {
            selectedTask = task
            showingTaskDetail = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with status and priority
                HStack {
                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(taskStatusColor(task.status))
                            .frame(width: 10, height: 10)
                        Text(task.status.rawValue.capitalized)
                            .font(.squirrelFootnote)
                            .foregroundColor(taskStatusColor(task.status))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(taskStatusColor(task.status).opacity(0.1))
                    .cornerRadius(12)
                    
                    Spacer()
                    
                    // Priority badge
                    Text(task.priority.rawValue.capitalized)
                        .font(.squirrelFootnote)
                        .fontWeight(.semibold)
                        .foregroundColor(priorityColor(task.priority))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(priorityColor(task.priority).opacity(0.1))
                        .cornerRadius(12)
                }
                
                // Task title
                Text(task.title)
                    .font(.squirrelHeadline)
                    .foregroundColor(.squirrelTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                
                // Task description if available
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.squirrelBody)
                        .foregroundColor(.squirrelTextSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Footer with due date and tags
                HStack {
                    // Due date
                    if let dueDate = task.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                            Text(formatDate(dueDate))
                                .font(.squirrelFootnote)
                        }
                        .foregroundColor(dueDateColor(dueDate))
                    }
                    
                    Spacer()
                    
                    // Tags if available
                    if !task.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(task.tags.prefix(2), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.squirrelFootnote)
                                    .foregroundColor(.squirrelPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.squirrelPrimary.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            if task.tags.count > 2 {
                                Text("+\(task.tags.count - 2)")
                                    .font(.squirrelFootnote)
                                    .foregroundColor(.squirrelTextSecondary)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.squirrelSurfaceBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.squirrelPrimary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func taskStatusColor(_ status: UserTask.TaskStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .gray
        }
    }
    
    private func priorityColor(_ priority: UserTask.TaskPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .gray
        case .urgent: return .red
        }
    }
    
    private func dueDateColor(_ date: Date) -> Color {
        let now = Date()
        let daysUntil = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
        
        if daysUntil < 0 {
            return .red // Overdue
        } else if daysUntil <= 1 {
            return .orange // Due soon
        } else {
            return .squirrelTextSecondary
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
    
    private func startConversationsListener() {
        guard let userId = firebaseManager.currentUser?.uid else { return }
        
        // Remove existing listener if any
        conversationsListener?.remove()
        
        // Set up real-time listener for conversations
        conversationsListener = db.collection("conversations")
            .whereField("userId", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to conversations: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                self.conversations = documents.compactMap { document in
                    let data = document.data()
                    guard let title = data["title"] as? String,
                          let userId = data["userId"] as? String else {
                        return nil
                    }
                    
                    // Parse timestamps
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
                    
                    return ChatConversation(
                        id: document.documentID,
                        title: title,
                        lastMessageAt: updatedAt,
                        createdAt: createdAt,
                        userId: userId
                    )
                }
                
                print("📱 Live update: \(self.conversations.count) conversations")
            }
    }
    
    private func startTasksListener() {
        guard let userId = firebaseManager.currentUser?.uid else { return }
        
        // Remove existing listener if any
        tasksListener?.remove()
        
        // Set up real-time listener for pending tasks
        tasksListener = db.collection("tasks")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to tasks: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                self.tasks = documents.compactMap { document in
                    let data = document.data()
                    guard let title = data["title"] as? String,
                          let userId = data["userId"] as? String,
                          let statusStr = data["status"] as? String,
                          let status = UserTask.TaskStatus(rawValue: statusStr),
                          let priorityStr = data["priority"] as? String,
                          let priority = UserTask.TaskPriority(rawValue: priorityStr) else {
                        return nil
                    }
                    
                    // Parse timestamps
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
                    let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
                    let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
                    
                    return UserTask(
                        id: document.documentID,
                        userId: userId,
                        spaceIds: data["spaceIds"] as? [String] ?? [],
                        conversationId: data["conversationId"] as? String,
                        title: title,
                        description: data["description"] as? String ?? "",
                        status: status,
                        priority: priority,
                        dueDate: dueDate,
                        completedAt: completedAt,
                        tags: data["tags"] as? [String] ?? [],
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        metadata: data["metadata"] as? [String: String]
                    )
                }
                
                print("📱 Live update: \(self.tasks.count) tasks")
            }
    }
    
    // Keep the old functions for backward compatibility but they're not used anymore
    private func loadConversations() {
        guard let user = firebaseManager.currentUser else { return }
        
        Task {
            do {
                // Get Firebase auth token
                let token = try await user.getIDToken()
                
                // Fetch conversations from backend API
                guard let url = URL(string: "\(AppConfig.apiBaseURL)/conversations") else { return }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Conversations API Response: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 200 {
                        // Parse the JSON response
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        
                        if let conversationDicts = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        self.conversations = conversationDicts.compactMap { dict in
                            guard let id = dict["id"] as? String,
                                  let title = dict["title"] as? String,
                                  let userId = dict["userId"] as? String else {
                                return nil
                            }
                            
                            // Parse dates - backend may send them as ISO strings
                            let dateFormatter = ISO8601DateFormatter()
                            let createdAt = (dict["createdAt"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
                            // Backend uses 'updatedAt' not 'lastMessageAt'
                            let lastMessageAt = (dict["updatedAt"] as? String).flatMap { dateFormatter.date(from: $0) } ?? createdAt
                            
                            return ChatConversation(
                                id: id,
                                title: title,
                                lastMessageAt: lastMessageAt,
                                createdAt: createdAt,
                                userId: userId
                            )
                        }
                        .sorted { $0.lastMessageAt > $1.lastMessageAt } // Sort by most recent
                        .prefix(10) // Limit to 10 most recent
                        .map { $0 } // Convert back to array
                    }
                    
                        print("✅ Loaded \(self.conversations.count) conversations from backend")
                    } else if httpResponse.statusCode == 500 {
                        // Try to parse error message
                        if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorMessage = errorDict["error"] as? String {
                            print("❌ Conversations API error: \(errorMessage)")
                        } else {
                            print("❌ Conversations API returned 500")
                        }
                    } else {
                        print("Error loading conversations: HTTP \(httpResponse.statusCode)")
                    }
                }
            } catch {
                print("Error loading conversations: \(error)")
            }
        }
    }
    
    private func loadTasks() {
        guard let user = firebaseManager.currentUser else { return }
        
        Task {
            do {
                // Get Firebase auth token
                let token = try await user.getIDToken()
                
                // Fetch tasks from backend API - specifically pending tasks
                guard let url = URL(string: "\(AppConfig.apiBaseURL)/tasks/pending") else { return }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Tasks API Response: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 200 {
                        if let taskDicts = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        self.tasks = taskDicts.compactMap { dict in
                            guard let id = dict["id"] as? String,
                                  let title = dict["title"] as? String,
                                  let userId = dict["userId"] as? String,
                                  let statusStr = dict["status"] as? String,
                                  let status = UserTask.TaskStatus(rawValue: statusStr),
                                  let priorityStr = dict["priority"] as? String,
                                  let priority = UserTask.TaskPriority(rawValue: priorityStr) else {
                                return nil
                            }
                            
                            // Parse dates
                            let dateFormatter = ISO8601DateFormatter()
                            let createdAt = (dict["createdAt"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
                            let updatedAt = (dict["updatedAt"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
                            let dueDate = (dict["dueDate"] as? String).flatMap { dateFormatter.date(from: $0) }
                            let completedAt = (dict["completedAt"] as? String).flatMap { dateFormatter.date(from: $0) }
                            
                            return UserTask(
                                id: id,
                                userId: userId,
                                spaceIds: dict["spaceIds"] as? [String] ?? [],
                                conversationId: dict["conversationId"] as? String,
                                title: title,
                                description: dict["description"] as? String ?? "",
                                status: status,
                                priority: priority,
                                dueDate: dueDate,
                                completedAt: completedAt,
                                tags: dict["tags"] as? [String] ?? [],
                                createdAt: createdAt,
                                updatedAt: updatedAt,
                                metadata: dict["metadata"] as? [String: String]
                            )
                        }
                        // Backend already sorts by createdAt desc, so just take first 10
                        .prefix(10)
                        .map { $0 }
                    }
                    
                        print("✅ Loaded \(self.tasks.count) tasks from backend")
                    } else if httpResponse.statusCode == 500 {
                        // Try to parse error message
                        if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorMessage = errorDict["error"] as? String {
                            print("❌ Tasks API error: \(errorMessage)")
                        } else {
                            print("❌ Tasks API returned 500")
                        }
                    } else {
                        print("Error loading tasks: HTTP \(httpResponse.statusCode)")
                    }
                }
            } catch {
                print("Error loading tasks: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(FirebaseManager.shared)
}
