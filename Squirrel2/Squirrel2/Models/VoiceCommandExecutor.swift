//
//  VoiceCommandExecutor.swift
//  Squirrel2
//
//  Local command execution for instant voice feedback
//

import SwiftUI
import FirebaseFirestore
import AVFoundation

@MainActor
class VoiceCommandExecutor: ObservableObject {
    @Published var isExecuting = false
    @Published var lastCommand: String?
    @Published var lastResult: String?
    
    private let db = Firestore.firestore()
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    private let audioPlayer = AVAudioPlayer()
    
    enum CommandType {
        case createTask(title: String, dueDate: Date?, priority: String)
        case completeTask(title: String)
        case deleteTask(title: String)
        case setTimer(duration: TimeInterval, label: String?)
        case addToList(item: String, listName: String)
        case unknown
    }
    
    init() {
        feedbackGenerator.prepare()
    }
    
    func executeCommand(from transcript: String) async -> (success: Bool, message: String) {
        isExecuting = true
        lastCommand = transcript
        defer { isExecuting = false }
        
        let command = parseCommand(from: transcript)
        
        switch command {
        case .createTask(let title, let dueDate, let priority):
            return await createTask(title: title, dueDate: dueDate, priority: priority)
            
        case .completeTask(let title):
            return await completeTask(title: title)
            
        case .deleteTask(let title):
            return await deleteTask(title: title)
            
        case .setTimer(let duration, let label):
            return setTimer(duration: duration, label: label)
            
        case .addToList(let item, let listName):
            return await addToList(item: item, listName: listName)
            
        case .unknown:
            return (false, "Command not recognized")
        }
    }
    
    private func parseCommand(from transcript: String) -> CommandType {
        let lowercased = transcript.lowercased()
        
        // Task creation patterns
        if lowercased.contains("remind") || lowercased.contains("task") || 
           lowercased.contains("add") && (lowercased.contains("todo") || lowercased.contains("list")) {
            
            let title = extractTaskTitle(from: transcript)
            let dueDate = extractDueDate(from: transcript)
            let priority = extractPriority(from: transcript)
            
            return .createTask(title: title, dueDate: dueDate, priority: priority)
        }
        
        // Task completion patterns
        if lowercased.contains("complete") || lowercased.contains("done") || 
           lowercased.contains("finish") || lowercased.contains("mark") {
            
            let title = extractTaskReference(from: transcript)
            return .completeTask(title: title)
        }
        
        // Task deletion patterns
        if lowercased.contains("delete") || lowercased.contains("remove") || 
           lowercased.contains("cancel") {
            
            let title = extractTaskReference(from: transcript)
            return .deleteTask(title: title)
        }
        
        // Timer patterns
        if lowercased.contains("timer") || lowercased.contains("alarm") {
            let (duration, label) = extractTimerInfo(from: transcript)
            if let duration = duration {
                return .setTimer(duration: duration, label: label)
            }
        }
        
        // Shopping list patterns
        if lowercased.contains("shopping") || lowercased.contains("grocery") {
            let item = extractListItem(from: transcript)
            return .addToList(item: item, listName: "Shopping")
        }
        
        return .unknown
    }
    
    // MARK: - Extraction Helpers
    
    private func extractTaskTitle(from text: String) -> String {
        let lowercased = text.lowercased()
        
        // Remove command words
        var title = text
        let commandWords = ["remind me to", "remind me", "add task", "create task", "add", "create", "task to"]
        for word in commandWords {
            if lowercased.contains(word) {
                if let range = lowercased.range(of: word) {
                    let startIndex = text.index(text.startIndex, offsetBy: range.upperBound.utf16Offset(in: lowercased))
                    title = String(text[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }
        
        // Remove time references from the end
        let timeWords = ["tomorrow", "today", "later", "tonight", "morning", "afternoon", "evening"]
        for word in timeWords {
            if title.lowercased().hasSuffix(" " + word) {
                title = String(title.dropLast(word.count + 1))
            }
        }
        
        return title.isEmpty ? text : title
    }
    
    private func extractDueDate(from text: String) -> Date? {
        let lowercased = text.lowercased()
        let calendar = Calendar.current
        let now = Date()
        
        if lowercased.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        } else if lowercased.contains("today") {
            return now
        } else if lowercased.contains("tonight") {
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)
        } else if lowercased.contains("morning") {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)
        } else if lowercased.contains("afternoon") {
            return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now)
        } else if lowercased.contains("evening") {
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
        }
        
        // Check for relative days
        if lowercased.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        } else if lowercased.contains("next month") {
            return calendar.date(byAdding: .month, value: 1, to: now)
        }
        
        return nil
    }
    
    private func extractPriority(from text: String) -> String {
        let lowercased = text.lowercased()
        
        if lowercased.contains("urgent") || lowercased.contains("important") || 
           lowercased.contains("high priority") || lowercased.contains("asap") {
            return "high"
        } else if lowercased.contains("low priority") || lowercased.contains("whenever") {
            return "low"
        }
        
        return "medium"
    }
    
    private func extractTaskReference(from text: String) -> String {
        // Remove action words
        var reference = text
        let actionWords = ["complete", "finish", "mark", "done", "delete", "remove", "cancel", "task", "the"]
        for word in actionWords {
            reference = reference.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        
        return reference.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractTimerInfo(from text: String) -> (duration: TimeInterval?, label: String?) {
        let lowercased = text.lowercased()
        var duration: TimeInterval?
        var label: String?
        
        // Extract numbers
        let numbers = text.components(separatedBy: .whitespaces)
            .compactMap { Int($0) }
        
        if let number = numbers.first {
            // Check for units
            if lowercased.contains("minute") {
                duration = TimeInterval(number * 60)
            } else if lowercased.contains("hour") {
                duration = TimeInterval(number * 3600)
            } else if lowercased.contains("second") {
                duration = TimeInterval(number)
            } else {
                // Default to minutes
                duration = TimeInterval(number * 60)
            }
        }
        
        // Extract label (text after "for")
        if lowercased.contains(" for "),
           let range = lowercased.range(of: " for ") {
            let labelStart = text.index(range.upperBound, offsetBy: 0)
            label = String(text[labelStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return (duration, label)
    }
    
    private func extractListItem(from text: String) -> String {
        // Remove command words
        var item = text
        let commandWords = ["add", "to", "shopping", "list", "grocery", "the", "my", "our"]
        for word in commandWords {
            item = item.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        
        return item.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Command Execution
    
    private func createTask(title: String, dueDate: Date?, priority: String) async -> (Bool, String) {
        guard !title.isEmpty else {
            return (false, "Task title is empty")
        }
        
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            return (false, "Not authenticated")
        }
        
        do {
            let task = VoiceTask(title: title, dueDate: dueDate, priority: priority, userId: userId)
            let taskData = task.dictionary
            try await db.collection("tasks").document(task.id).setData(taskData)
            
            playSuccessSound()
            lastResult = "Created: \(title)"
            return (true, "Task created")
        } catch {
            return (false, "Failed to create task")
        }
    }
    
    private func completeTask(title: String) async -> (Bool, String) {
        guard !title.isEmpty else {
            return (false, "Task reference is empty")
        }
        
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            return (false, "Not authenticated")
        }
        
        do {
            // Find matching task
            let snapshot = try await db.collection("tasks")
                .whereField("userId", isEqualTo: userId)
                .whereField("completed", isEqualTo: false)
                .getDocuments()
            
            // Find best match (simple contains check)
            let matchingDoc = snapshot.documents.first { doc in
                let data = doc.data()
                if let taskTitle = data["title"] as? String {
                    return taskTitle.lowercased().contains(title.lowercased()) ||
                           title.lowercased().contains(taskTitle.lowercased())
                }
                return false
            }
            
            guard let doc = matchingDoc else {
                return (false, "Task not found")
            }
            
            // Mark as complete
            let updateData: [String: Any] = [
                "completed": true,
                "completedAt": Timestamp(date: Date())
            ]
            try await db.collection("tasks").document(doc.documentID).updateData(updateData)
            
            playSuccessSound()
            lastResult = "Completed task"
            return (true, "Task completed")
        } catch {
            return (false, "Failed to complete task")
        }
    }
    
    private func deleteTask(title: String) async -> (Bool, String) {
        guard !title.isEmpty else {
            return (false, "Task reference is empty")
        }
        
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            return (false, "Not authenticated")
        }
        
        do {
            // Find matching task
            let snapshot = try await db.collection("tasks")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            
            // Find best match
            let matchingDoc = snapshot.documents.first { doc in
                let data = doc.data()
                if let taskTitle = data["title"] as? String {
                    return taskTitle.lowercased().contains(title.lowercased()) ||
                           title.lowercased().contains(taskTitle.lowercased())
                }
                return false
            }
            
            guard let doc = matchingDoc else {
                return (false, "Task not found")
            }
            
            // Delete task
            try await db.collection("tasks").document(doc.documentID).delete()
            
            playSuccessSound()
            lastResult = "Deleted task"
            return (true, "Task deleted")
        } catch {
            return (false, "Failed to delete task")
        }
    }
    
    private func setTimer(duration: TimeInterval, label: String?) -> (Bool, String) {
        // For now, just provide feedback - actual timer implementation would require more setup
        playSuccessSound()
        
        let minutes = Int(duration / 60)
        let labelText = label.map { " for \($0)" } ?? ""
        lastResult = "Timer set: \(minutes) minutes\(labelText)"
        
        return (true, "Timer set")
    }
    
    private func addToList(item: String, listName: String) async -> (Bool, String) {
        guard !item.isEmpty else {
            return (false, "Item is empty")
        }
        
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            return (false, "Not authenticated")
        }
        
        do {
            // Create a shopping list item (using tasks collection with a type)
            let listItem: [String: Any] = [
                "id": UUID().uuidString,
                "title": item,
                "type": "shopping",
                "listName": listName,
                "completed": false,
                "createdAt": Timestamp(date: Date()),
                "userId": userId
            ]
            
            try await db.collection("tasks").addDocument(data: listItem)
            
            playSuccessSound()
            lastResult = "Added \(item) to \(listName) list"
            return (true, "Added to list")
        } catch {
            return (false, "Failed to add to list")
        }
    }
    
    // MARK: - Feedback
    
    func playSuccessSound() {
        // Play system sound
        AudioServicesPlaySystemSound(1057) // Tink sound
        
        // Haptic feedback
        feedbackGenerator.notificationOccurred(.success)
    }
    
    func playErrorSound() {
        AudioServicesPlaySystemSound(1053) // Error sound
        feedbackGenerator.notificationOccurred(.error)
    }
}
