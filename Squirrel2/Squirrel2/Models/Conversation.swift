import Foundation

struct Conversation: Identifiable, Codable {
    let id: String
    let userId: String
    var spaceIds: [String]
    var title: String
    var lastMessage: String?
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id, userId, spaceIds, title, lastMessage
        case createdAt, updatedAt, metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        spaceIds = try container.decode([String].self, forKey: .spaceIds)
        title = try container.decode(String.self, forKey: .title)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(spaceIds, forKey: .spaceIds)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension Conversation: Hashable {
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
