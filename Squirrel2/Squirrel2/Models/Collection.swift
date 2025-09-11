//
//  Collection.swift
//  Squirrel2
//

import Foundation

struct Collection: Identifiable, Codable {
    let id: String
    let userId: String
    let name: String
    let instructions: String  // AI guidance for what belongs in this collection
    let icon: String
    let color: String
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