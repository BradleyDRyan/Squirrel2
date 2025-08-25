import Foundation
import SwiftUI

struct Space: Identifiable, Codable {
    let id: String
    let userId: String
    var name: String
    var description: String
    var color: String
    var icon: String?
    var isDefault: Bool
    var isArchived: Bool
    var settings: [String: String]?
    var stats: SpaceStats
    let createdAt: Date
    var updatedAt: Date
    var metadata: [String: String]?
    
    struct SpaceStats: Codable, Hashable {
        var conversationCount: Int
        var taskCount: Int
        var entryCount: Int
        var thoughtCount: Int
    }
    
    enum CodingKeys: String, CodingKey {
        case id, userId, name, description, color, icon
        case isDefault, isArchived, settings, stats
        case createdAt, updatedAt, metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        color = try container.decode(String.self, forKey: .color)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        stats = try container.decode(SpaceStats.self, forKey: .stats)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(stats, forKey: .stats)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    var colorValue: Color {
        Color(hex: color)
    }
}

extension Space: Hashable {
    static func == (lhs: Space, rhs: Space) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}