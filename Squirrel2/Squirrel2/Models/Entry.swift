import Foundation

struct Entry: Identifiable, Codable {
    let id: String
    let userId: String
    let collectionId: String?
    var spaceIds: [String]
    let conversationId: String?
    var title: String
    var content: String
    var type: EntryType
    var mood: Mood?
    var tags: [String]
    var attachments: [String]
    var location: Location?
    var weather: Weather?
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    enum EntryType: String, Codable, CaseIterable {
        case journal = "journal"
        case note = "note"
        case reflection = "reflection"
        case gratitude = "gratitude"
        case dream = "dream"
    }
    
    enum Mood: String, Codable, CaseIterable {
        case happy = "happy"
        case sad = "sad"
        case excited = "excited"
        case anxious = "anxious"
        case calm = "calm"
        case frustrated = "frustrated"
        case grateful = "grateful"
        case neutral = "neutral"
    }
    
    struct Location: Codable, Hashable {
        let name: String
        let latitude: Double?
        let longitude: Double?
    }
    
    struct Weather: Codable, Hashable {
        let temperature: Double?
        let condition: String?
        let humidity: Double?
    }
    
    enum CodingKeys: String, CodingKey {
        case id, userId, collectionId, spaceIds, conversationId, title, content
        case type, mood, tags, attachments, location, weather
        case createdAt, updatedAt, metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId)
        spaceIds = try container.decode([String].self, forKey: .spaceIds)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(EntryType.self, forKey: .type)
        mood = try container.decodeIfPresent(Mood.self, forKey: .mood)
        tags = try container.decode([String].self, forKey: .tags)
        attachments = try container.decode([String].self, forKey: .attachments)
        location = try container.decodeIfPresent(Location.self, forKey: .location)
        weather = try container.decodeIfPresent(Weather.self, forKey: .weather)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Skip metadata since it can have mixed types
        metadata = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(collectionId, forKey: .collectionId)
        try container.encode(spaceIds, forKey: .spaceIds)
        try container.encodeIfPresent(conversationId, forKey: .conversationId)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(mood, forKey: .mood)
        try container.encode(tags, forKey: .tags)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(weather, forKey: .weather)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
    
    var moodEmoji: String? {
        guard let mood = mood else { return nil }
        switch mood {
        case .happy: return "😊"
        case .sad: return "😢"
        case .excited: return "🎉"
        case .anxious: return "😰"
        case .calm: return "😌"
        case .frustrated: return "😤"
        case .grateful: return "🙏"
        case .neutral: return "😐"
        }
    }
}

extension Entry: Hashable {
    static func == (lhs: Entry, rhs: Entry) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
