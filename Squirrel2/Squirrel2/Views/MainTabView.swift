//
//  MainTabView.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth

struct MainTabView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @State private var selectedTab = 0
    @State private var showingChat = false
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                TasksTabView()
                    .tabItem {
                        Label("Tasks", systemImage: "checklist")
                    }
                    .tag(0)
                
                CollectionsView()
                    .tabItem {
                        Label("Collections", systemImage: "folder.fill")
                    }
                    .tag(1)
            }
            
            // Floating + button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    Button(action: {
                        showingChat = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.squirrelPrimary)
                                .frame(width: 60, height: 60)
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .offset(y: -30) // Position above tab bar
                    .padding(.trailing, 20)
                }
            }
        }
        .sheet(isPresented: $showingChat) {
            ChatView()
                .environmentObject(firebaseManager)
        }
    }
}

// Separate TasksTabView to organize the tasks UI
struct TasksTabView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @State private var tasks: [UserTask] = []
    @State private var showingTaskDetail = false
    @State private var selectedTask: UserTask?
    @State private var tasksListener: ListenerRegistration?
    @State private var showingSettings = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !tasks.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(tasks.filter { $0.status == .pending }) { task in
                                TaskRow(task: task) {
                                    selectedTask = task
                                    showingTaskDetail = true
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "checklist")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Tasks Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Create tasks to stay organized")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.squirrelPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(firebaseManager)
            }
            .sheet(isPresented: $showingTaskDetail) {
                if let task = selectedTask {
                    TaskDetailView(task: task)
                }
            }
        }
        .onAppear {
            startTasksListener()
        }
        .onDisappear {
            tasksListener?.remove()
        }
    }
    
    private func startTasksListener() {
        guard let userId = firebaseManager.currentUser?.uid else { return }
        
        tasksListener?.remove()
        
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
                          let statusString = data["status"] as? String else { return nil }
                    
                    return UserTask(
                        id: document.documentID,
                        title: title,
                        description: data["description"] as? String,
                        status: TaskStatus(rawValue: statusString) ?? .pending,
                        priority: TaskPriority(rawValue: data["priority"] as? String ?? "medium") ?? .medium,
                        dueDate: (data["dueDate"] as? Timestamp)?.dateValue(),
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        metadata: data["metadata"] as? [String: String]
                    )
                }
            }
    }
}

struct TaskRow: View {
    let task: UserTask
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let description = task.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 12) {
                        Label("\(task.priority.displayName)", systemImage: "flag.fill")
                            .font(.caption)
                            .foregroundColor(task.priority.color)
                        
                        if let dueDate = task.dueDate {
                            Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TaskDetailView: View {
    let task: UserTask
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text(task.title)
                    .font(.title)
                    .fontWeight(.bold)
                
                if let description = task.description {
                    Text(description)
                        .font(.body)
                }
                
                HStack {
                    Label("Priority", systemImage: "flag.fill")
                    Spacer()
                    Text(task.priority.displayName)
                        .foregroundColor(task.priority.color)
                }
                
                if let dueDate = task.dueDate {
                    HStack {
                        Label("Due Date", systemImage: "calendar")
                        Spacer()
                        Text(dueDate.formatted(date: .long, time: .shortened))
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}