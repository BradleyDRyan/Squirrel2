//
//  RealtimeFunctions.swift
//  Squirrel2
//
//  Function definitions and handlers for OpenAI Realtime API
//

import Foundation
import OpenAIRealtime
import FirebaseFirestore

// MARK: - Function Definitions

import OpenAIRealtime

struct RealtimeFunctions {
    
    // Define the available functions for the Realtime API (for JSON serialization)
    static let availableFunctionsJSON: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "create_task",
                "description": "Create a new task or reminder for the user",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "The title or description of the task"
                        ],
                        "dueDate": [
                            "type": "string",
                            "description": "Optional due date/time for the task in ISO format"
                        ],
                        "priority": [
                            "type": "string",
                            "enum": ["low", "medium", "high"],
                            "description": "Priority level of the task"
                        ]
                    ],
                    "required": ["title"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "list_tasks",
                "description": "List all tasks or reminders",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "filter": [
                            "type": "string",
                            "enum": ["all", "pending", "completed", "today"],
                            "description": "Filter tasks by status or timeframe"
                        ]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "complete_task",
                "description": "Mark a task as completed",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "taskId": [
                            "type": "string",
                            "description": "The ID of the task to complete"
                        ],
                        "taskTitle": [
                            "type": "string",
                            "description": "Alternative: the title of the task to complete if ID is not available"
                        ]
                    ]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "delete_task",
                "description": "Delete a task or reminder",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "taskId": [
                            "type": "string",
                            "description": "The ID of the task to delete"
                        ],
                        "taskTitle": [
                            "type": "string",
                            "description": "Alternative: the title of the task to delete if ID is not available"
                        ]
                    ]
                ]
            ]
        ]
    ]
    
    // Define the available functions as dictionary for now
    // We'll need to convert this to Session.Tool format
    static let availableFunctions: [[String: Any]] = [
        [
            "type": "function",
            "name": "create_task",
            "description": "Create a new task or reminder for the user",
            "parameters": [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "The title or description of the task"
                    ]
                ],
                "required": ["title"]
            ]
        ]
    ]
}

// MARK: - Task Model

struct VoiceTask: Codable {
    let id: String
    let title: String
    let dueDate: Date?
    let priority: String
    let completed: Bool
    let createdAt: Date
    let userId: String
    
    init(title: String, dueDate: Date? = nil, priority: String = "medium", userId: String) {
        self.id = UUID().uuidString
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.completed = false
        self.createdAt = Date()
        self.userId = userId
    }
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "priority": priority,
            "completed": completed,
            "createdAt": Timestamp(date: createdAt),
            "userId": userId
        ]
        
        if let dueDate = dueDate {
            dict["dueDate"] = Timestamp(date: dueDate)
        }
        
        return dict
    }
}

// MARK: - Function Handler

@MainActor
class RealtimeFunctionHandler: ObservableObject {
    private let db = Firestore.firestore()
    @Published var lastExecutedFunction: String?
    @Published var lastFunctionResult: String?
    
    // Handle function calls from the Realtime API
    func handleFunctionCall(name: String, arguments: String) async -> String {
        print("🔧 Handling function call: \(name)")
        print("📝 Arguments: \(arguments)")
        
        // Get the current user (including anonymous users)
        guard let user = FirebaseManager.shared.currentUser else {
            print("❌ No Firebase user found (not even anonymous)")
            print("   Auth state: \(FirebaseManager.shared.isAuthenticated)")
            return createErrorResponse("User not authenticated - please restart the app")
        }
        
        let userId = user.uid
        let isAnonymous = user.isAnonymous
        print("✅ User found: \(userId) (anonymous: \(isAnonymous))")
        
        // Try to fix truncated JSON by closing it
        var fixedArguments = arguments
        if !arguments.contains("}") && arguments.contains("{") {
            // JSON is truncated, try to close it
            fixedArguments = arguments + "\"}"
            print("🔧 Fixed truncated JSON: \(fixedArguments)")
        }
        
        // Parse the arguments JSON
        guard let argumentsData = fixedArguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
            // If JSON parsing fails, try to extract the value manually
            if name == "create_task" {
                // Try to extract task description from partial JSON
                if let range = arguments.range(of: "\":\""),
                   let endRange = arguments.range(of: "\"", options: [], range: range.upperBound..<arguments.endIndex) {
                    let taskDescription = String(arguments[range.upperBound..<endRange.lowerBound])
                    print("📝 Extracted task: \(taskDescription)")
                    return await createTask(args: ["title": taskDescription], userId: userId)
                }
            }
            return createErrorResponse("Invalid arguments")
        }
        
        switch name {
        case "create_task":
            return await createTask(args: args, userId: userId)
            
        case "list_tasks":
            return await listTasks(args: args, userId: userId)
            
        case "complete_task":
            return await completeTask(args: args, userId: userId)
            
        case "delete_task":
            return await deleteTask(args: args, userId: userId)
            
        default:
            return createErrorResponse("Unknown function: \(name)")
        }
    }
    
    // MARK: - Function Implementations
    
    private func createTask(args: [String: Any], userId: String) async -> String {
        // Handle different argument formats
        let title = args["title"] as? String ?? 
                   args["task description"] as? String ?? 
                   args["description"] as? String
        
        guard let title = title, !title.isEmpty else {
            return createErrorResponse("Task title is required")
        }
        
        let priority = args["priority"] as? String ?? "medium"
        let dueDate = args["dueDate"] as? String
        
        // Create request body matching UserTask model
        var requestBody: [String: Any] = [
            "title": title,
            "content": title,  // UserTask model uses content field
            "status": "pending",
            "priority": priority
        ]
        
        if let dueDate = dueDate {
            requestBody["dueDate"] = dueDate
        }
        
        // Try to call backend API, but fall back to Firestore if it fails
        do {
            // First try backend if user is authenticated
            if let user = FirebaseManager.shared.currentUser,
               let token = try? await user.getIDToken(),
               let url = URL(string: "\(AppConfig.apiBaseURL)/tasks") {
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    if let responseData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        lastExecutedFunction = "create_task"
                        lastFunctionResult = "Created task: \(title)"
                        
                        return createSuccessResponse([
                            "message": "Task created successfully",
                            "taskId": responseData["id"] as? String ?? UUID().uuidString,
                            "title": title
                        ])
                    }
                }
            }
            
            // Fall back to direct Firestore write
            let task = VoiceTask(title: title, dueDate: nil, priority: priority, userId: userId)
            try await db.collection("tasks").document(task.id).setData(task.dictionary)
            
            lastExecutedFunction = "create_task"
            lastFunctionResult = "Created task: \(title)"
            
            return createSuccessResponse([
                "message": "Task created successfully",
                "taskId": task.id,
                "title": title
            ])
        } catch {
            print("❌ Error creating task: \(error)")
            return createErrorResponse("Failed to create task: \(error.localizedDescription)")
        }
    }
    
    private func listTasks(args: [String: Any], userId: String) async -> String {
        let filter = args["filter"] as? String ?? "all"
        
        do {
            var query: Query = db.collection("tasks").whereField("userId", isEqualTo: userId)
            
            // Apply filters
            switch filter {
            case "pending":
                query = query.whereField("completed", isEqualTo: false)
            case "completed":
                query = query.whereField("completed", isEqualTo: true)
            case "today":
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: Date())
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                query = query.whereField("dueDate", isGreaterThanOrEqualTo: startOfDay)
                           .whereField("dueDate", isLessThan: endOfDay)
            default:
                break // "all" - no additional filter
            }
            
            let snapshot = try await query.getDocuments()
            
            let tasks = snapshot.documents.compactMap { doc -> [String: Any]? in
                let data = doc.data()
                return [
                    "id": data["id"] as? String ?? doc.documentID,
                    "title": data["title"] as? String ?? "",
                    "completed": data["completed"] as? Bool ?? false,
                    "priority": data["priority"] as? String ?? "medium"
                ]
            }
            
            lastExecutedFunction = "list_tasks"
            lastFunctionResult = "Found \(tasks.count) tasks"
            
            return createSuccessResponse([
                "tasks": tasks,
                "count": tasks.count
            ])
        } catch {
            return createErrorResponse("Failed to list tasks: \(error.localizedDescription)")
        }
    }
    
    private func completeTask(args: [String: Any], userId: String) async -> String {
        var taskId: String? = args["taskId"] as? String
        let taskTitle = args["taskTitle"] as? String
        
        do {
            // If no ID provided, try to find by title
            if taskId == nil, let title = taskTitle {
                let snapshot = try await db.collection("tasks")
                    .whereField("userId", isEqualTo: userId)
                    .whereField("title", isEqualTo: title)
                    .whereField("completed", isEqualTo: false)
                    .limit(to: 1)
                    .getDocuments()
                
                taskId = snapshot.documents.first?.documentID
            }
            
            guard let finalTaskId = taskId else {
                return createErrorResponse("Task not found")
            }
            
            let updateData: [String: Any] = [
                "completed": true,
                "completedAt": Timestamp(date: Date())
            ]
            try await db.collection("tasks").document(finalTaskId).updateData(updateData)
            
            lastExecutedFunction = "complete_task"
            lastFunctionResult = "Completed task"
            
            return createSuccessResponse([
                "message": "Task marked as completed",
                "taskId": finalTaskId
            ])
        } catch {
            return createErrorResponse("Failed to complete task: \(error.localizedDescription)")
        }
    }
    
    private func deleteTask(args: [String: Any], userId: String) async -> String {
        var taskId: String? = args["taskId"] as? String
        let taskTitle = args["taskTitle"] as? String
        
        do {
            // If no ID provided, try to find by title
            if taskId == nil, let title = taskTitle {
                let snapshot = try await db.collection("tasks")
                    .whereField("userId", isEqualTo: userId)
                    .whereField("title", isEqualTo: title)
                    .limit(to: 1)
                    .getDocuments()
                
                taskId = snapshot.documents.first?.documentID
            }
            
            guard let finalTaskId = taskId else {
                return createErrorResponse("Task not found")
            }
            
            try await db.collection("tasks").document(finalTaskId).delete()
            
            lastExecutedFunction = "delete_task"
            lastFunctionResult = "Deleted task"
            
            return createSuccessResponse([
                "message": "Task deleted successfully",
                "taskId": finalTaskId
            ])
        } catch {
            return createErrorResponse("Failed to delete task: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func createSuccessResponse(_ data: [String: Any]) -> String {
        let response: [String: Any] = ["success": true, "data": data]
        if let jsonData = try? JSONSerialization.data(withJSONObject: response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{\"success\": true}"
    }
    
    private func createErrorResponse(_ message: String) -> String {
        let response: [String: Any] = ["success": false, "error": message]
        if let jsonData = try? JSONSerialization.data(withJSONObject: response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{\"success\": false, \"error\": \"Unknown error\"}"
    }
}
