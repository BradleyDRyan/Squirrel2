import Foundation
import SwiftUI

struct UserTask: Identifiable, Codable {
    let id: String
    let userId: String
    var spaceIds: [String]
    let conversationId: String?
    var title: String
    var description: String
    var status: TaskStatus
    var priority: TaskPriority
    var dueDate: Date?
    var completedAt: Date?
    var tags: [String]
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    enum TaskStatus: String, Codable, CaseIterable {
        case pending = "pending"
        case inProgress = "in_progress"
        case completed = "completed"
        case cancelled = "cancelled"
    }
    
    enum TaskPriority: String, Codable, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case urgent = "urgent"
        
        var sortOrder: Int {
            switch self {
            case .urgent: return 0
            case .high: return 1
            case .medium: return 2
            case .low: return 3
            }
        }
        
        var displayName: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .urgent: return "Urgent"
            }
        }
        
        var color: Color {
            switch self {
            case .low: return .gray
            case .medium: return .blue
            case .high: return .orange
            case .urgent: return .red
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, userId, spaceIds, conversationId, title, description
        case status, priority, dueDate, completedAt, tags
        case createdAt, updatedAt, metadata
    }
    
    init(id: String,
         userId: String,
         spaceIds: [String],
         conversationId: String?,
         title: String,
         description: String,
         status: TaskStatus,
         priority: TaskPriority,
         dueDate: Date?,
         completedAt: Date?,
         tags: [String],
         createdAt: Date,
         updatedAt: Date,
         metadata: [String: String]?) {
        self.id = id
        self.userId = userId
        self.spaceIds = spaceIds
        self.conversationId = conversationId
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        spaceIds = try container.decode([String].self, forKey: .spaceIds)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        status = try container.decode(TaskStatus.self, forKey: .status)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(spaceIds, forKey: .spaceIds)
        try container.encodeIfPresent(conversationId, forKey: .conversationId)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(tags, forKey: .tags)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    var isOverdue: Bool {
        guard let dueDate = dueDate, status != .completed else { return false }
        return Date() > dueDate
    }
}

extension UserTask: Hashable {
    static func == (lhs: UserTask, rhs: UserTask) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
