import Foundation

struct Message: Identifiable, Codable {
    let id: String
    let conversationId: String
    let userId: String
    var content: String
    var type: MessageType
    var attachments: [String]
    let createdAt: Date
    var editedAt: Date?
    var metadata: [String: String]?
    
    enum MessageType: String, Codable {
        case text = "text"
        case image = "image"
        case voice = "voice"
        case system = "system"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, conversationId, userId, content, type
        case attachments, createdAt, editedAt, metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        userId = try container.decode(String.self, forKey: .userId)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(MessageType.self, forKey: .type)
        attachments = try container.decode([String].self, forKey: .attachments)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(userId, forKey: .userId)
        try container.encode(content, forKey: .content)
        try container.encode(type, forKey: .type)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(editedAt, forKey: .editedAt)
    }
}

extension Message: Hashable {
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}