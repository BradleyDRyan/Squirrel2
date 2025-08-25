import Foundation

struct Thought: Identifiable, Codable {
    let id: String
    let userId: String
    var spaceIds: [String]
    let conversationId: String?
    var content: String
    var type: ThoughtType
    var category: ThoughtCategory
    var tags: [String]
    var insights: [String]
    var linkedThoughts: [String]
    var isPrivate: Bool
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    enum ThoughtType: String, Codable, CaseIterable {
        case reflection = "reflection"
        case idea = "idea"
        case question = "question"
        case insight = "insight"
        case observation = "observation"
    }
    
    enum ThoughtCategory: String, Codable, CaseIterable {
        case general = "general"
        case personal = "personal"
        case work = "work"
        case creative = "creative"
        case philosophical = "philosophical"
        case relationships = "relationships"
        case goals = "goals"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, userId, spaceIds, conversationId, content
        case type, category, tags, insights, linkedThoughts
        case isPrivate, createdAt, updatedAt, metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        spaceIds = try container.decode([String].self, forKey: .spaceIds)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(ThoughtType.self, forKey: .type)
        category = try container.decode(ThoughtCategory.self, forKey: .category)
        tags = try container.decode([String].self, forKey: .tags)
        insights = try container.decode([String].self, forKey: .insights)
        linkedThoughts = try container.decode([String].self, forKey: .linkedThoughts)
        isPrivate = try container.decode(Bool.self, forKey: .isPrivate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(spaceIds, forKey: .spaceIds)
        try container.encodeIfPresent(conversationId, forKey: .conversationId)
        try container.encode(content, forKey: .content)
        try container.encode(type, forKey: .type)
        try container.encode(category, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(insights, forKey: .insights)
        try container.encode(linkedThoughts, forKey: .linkedThoughts)
        try container.encode(isPrivate, forKey: .isPrivate)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    var typeIcon: String {
        switch type {
        case .reflection: return "💭"
        case .idea: return "💡"
        case .question: return "❓"
        case .insight: return "✨"
        case .observation: return "👁"
        }
    }
}

extension Thought: Hashable {
    static func == (lhs: Thought, rhs: Thought) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}