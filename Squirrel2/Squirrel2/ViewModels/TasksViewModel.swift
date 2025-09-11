//
//  TasksViewModel.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class TasksViewModel: ObservableObject {
    @Published var tasks: [UserTask] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private var tasksListener: ListenerRegistration?
    private let db = Firestore.firestore()
    
    func startListening(userId: String) {
        print("[TasksViewModel] Starting tasks listener for user: \(userId)")
        
        // Remove any existing listener
        stopListening()
        
        // Note: Using Firestore snapshot listeners for real-time updates (read-only)
        // All write operations should still go through the backend API
        tasksListener = db.collection("tasks")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[TasksViewModel] Error listening to tasks: \(error)")
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("[TasksViewModel] No documents in snapshot")
                    Task { @MainActor in
                        self.tasks = []
                        self.isLoading = false
                    }
                    return
                }
                
                print("[TasksViewModel] Received \(documents.count) tasks from snapshot")
                
                let newTasks = documents.compactMap { document -> UserTask? in
                    let data = document.data()
                    guard let title = data["title"] as? String,
                          let statusString = data["status"] as? String,
                          let userId = data["userId"] as? String else {
                        print("[TasksViewModel] Missing required fields in document: \(document.documentID)")
                        return nil
                    }
                    
                    return UserTask(
                        id: document.documentID,
                        userId: userId,
                        spaceIds: data["spaceIds"] as? [String] ?? [],
                        conversationId: data["conversationId"] as? String,
                        title: title,
                        description: data["description"] as? String ?? "",
                        status: UserTask.TaskStatus(rawValue: statusString) ?? .pending,
                        priority: UserTask.TaskPriority(rawValue: data["priority"] as? String ?? "medium") ?? .medium,
                        dueDate: (data["dueDate"] as? Timestamp)?.dateValue(),
                        completedAt: (data["completedAt"] as? Timestamp)?.dateValue(),
                        tags: data["tags"] as? [String] ?? [],
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                        metadata: data["metadata"] as? [String: String]
                    )
                }
                
                Task { @MainActor in
                    self.tasks = newTasks
                    self.isLoading = false
                    self.errorMessage = nil
                    print("[TasksViewModel] Updated tasks list with \(self.tasks.count) items")
                }
            }
    }
    
    func stopListening() {
        tasksListener?.remove()
        tasksListener = nil
    }
    
    deinit {
        stopListening()
    }
}