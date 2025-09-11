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
    @State private var showingCameraMode = false
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                TasksTabView()
                    .tabItem {
                        Label("Tasks", systemImage: "checklist")
                    }
                    .tag(0)
                
                PhotosView()
                    .tabItem {
                        Label("Photos", systemImage: "photo.fill")
                    }
                    .tag(1)
                
                CollectionsView()
                    .tabItem {
                        Label("Collections", systemImage: "folder.fill")
                    }
                    .tag(2)
            }
            
            // Floating + button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    Button(action: {
                        showingCameraMode = true
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
            ChatView(showingCameraMode: $showingCameraMode)
                .environmentObject(firebaseManager)
        }
        .onChange(of: showingCameraMode) { _, shouldShow in
            if shouldShow {
                // Open chat view with camera mode enabled
                showingChat = true
            }
        }
    }
}

// Separate TasksTabView to organize the tasks UI
struct TasksTabView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var viewModel = TasksViewModel()
    @State private var showingTaskDetail = false
    @State private var selectedTask: UserTask?
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                } else if !viewModel.tasks.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.tasks.filter { $0.status == .pending }) { task in
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
            if let userId = firebaseManager.currentUser?.uid {
                viewModel.startListening(userId: userId)
            }
        }
        .onDisappear {
            viewModel.stopListening()
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
                    
                    if !task.description.isEmpty {
                        Text(task.description)
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
                
                if !task.description.isEmpty {
                    Text(task.description)
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
