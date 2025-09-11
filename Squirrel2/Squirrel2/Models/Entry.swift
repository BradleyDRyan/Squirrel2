import Foundation

struct Entry: Identifiable, Codable {
    let id: String
    let userId: String
    var collectionIds: [String]  // Many-to-many relationship
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
        case photo = "photo"
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
        case id, userId, collectionId, collectionIds, spaceIds, conversationId, title, content
        case type, mood, tags, attachments, location, weather
        case createdAt, updatedAt, metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        // Handle both old single collectionId and new collectionIds array
        if let singleId = try container.decodeIfPresent(String.self, forKey: .collectionId) {
            collectionIds = [singleId]
        } else {
            collectionIds = try container.decodeIfPresent([String].self, forKey: .collectionIds) ?? []
        }
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
        try container.encode(collectionIds, forKey: .collectionIds)
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
    
    // Helper properties for photos
    var isPhoto: Bool {
        return type == .photo
    }
    
    var hasImage: Bool {
        return metadata?["hasImage"] == "true"
    }
    
    var imageDataString: String? {
        return metadata?["imageData"]
    }
    
    // Initialize with proper defaults
    init(id: String = UUID().uuidString,
         userId: String,
         collectionIds: [String],
         spaceIds: [String],
         conversationId: String? = nil,
         title: String,
         content: String,
         type: EntryType,
         mood: Mood? = nil,
         tags: [String] = [],
         attachments: [String] = [],
         location: Location? = nil,
         weather: Weather? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         metadata: [String: String]? = nil) {
        self.id = id
        self.userId = userId
        self.collectionIds = collectionIds
        self.spaceIds = spaceIds
        self.conversationId = conversationId
        self.title = title
        self.content = content
        self.type = type
        self.mood = mood
        self.tags = tags
        self.attachments = attachments
        self.location = location
        self.weather = weather
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
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
