//
//  Collection.swift
//  Squirrel2
//

import Foundation

struct Collection: Identifiable, Codable {
    let id: String
    let userId: String
    let name: String
    let description: String
    let icon: String
    let color: String
    let rules: CollectionRules?
    let entryFormat: EntryFormat?  // Defines structure for entries in this collection
    let template: CollectionTemplate?  // Legacy - will phase out
    let settings: CollectionSettings?
    let stats: CollectionStats
    let createdAt: Date
    let updatedAt: Date
    let metadata: [String: String]?
    
    var entryCount: Int {
        return stats.entryCount
    }
}

struct CollectionRules: Codable {
    let keywords: [String]
    let patterns: [String]
    let examples: [[String: String]]
    let description: String
}

struct CollectionTemplate: Codable {
    let fields: [String]
    let prompts: [String]
}

struct CollectionSettings: Codable {
    let isPublic: Bool
    let allowComments: Bool
    let defaultTags: [String]
}

struct CollectionStats: Codable {
    let entryCount: Int
    let lastEntryAt: Date?
}

// Entry model is defined in Entry.swift