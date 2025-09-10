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
    let template: CollectionTemplate?
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
    let examples: [RuleExample]
    let description: String
}

struct RuleExample: Codable {
    let entry: String
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