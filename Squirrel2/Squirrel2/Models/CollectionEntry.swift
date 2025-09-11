//
//  CollectionEntry.swift
//  Squirrel2
//
//  Join table between Entry and Collection with formatted data
//

import Foundation

struct CollectionEntry: Identifiable, Codable {
    let id: String
    let entryId: String  // Reference to raw Entry
    let collectionId: String  // Reference to Collection
    let userId: String
    var formattedData: [String: Any]  // Extracted/formatted fields based on collection's format
    var userOverrides: [String: Any]?  // Manual edits that override AI extraction
    let createdAt: Date
    var lastProcessedAt: Date  // When the formatting was last applied
    var metadata: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id, entryId, collectionId, userId
        case formattedData, userOverrides
        case createdAt, lastProcessedAt, metadata
    }
    
    // Custom decoding to handle Any types
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        entryId = try container.decode(String.self, forKey: .entryId)
        collectionId = try container.decode(String.self, forKey: .collectionId)
        userId = try container.decode(String.self, forKey: .userId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastProcessedAt = try container.decode(Date.self, forKey: .lastProcessedAt)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
        
        // Skip formattedData and userOverrides as they have mixed types
        formattedData = [:]
        userOverrides = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(entryId, forKey: .entryId)
        try container.encode(collectionId, forKey: .collectionId)
        try container.encode(userId, forKey: .userId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastProcessedAt, forKey: .lastProcessedAt)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        // Skip encoding formattedData and userOverrides due to Any type
    }
    
    // Get merged data (formatted + overrides)
    var displayData: [String: Any] {
        var merged = formattedData
        if let overrides = userOverrides {
            for (key, value) in overrides {
                merged[key] = value
            }
        }
        return merged
    }
    
    // Check if reprocessing is needed
    func needsReprocessing(collectionUpdatedAt: Date) -> Bool {
        return lastProcessedAt < collectionUpdatedAt
    }
}

extension CollectionEntry: Hashable {
    static func == (lhs: CollectionEntry, rhs: CollectionEntry) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}