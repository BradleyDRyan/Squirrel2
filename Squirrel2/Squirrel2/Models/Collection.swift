//
//  Collection.swift
//  Squirrel2
//

import Foundation
import FirebaseFirestore

struct Collection: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let name: String
    let description: String
    let icon: String
    let color: String
    let rules: CollectionRules?
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
    let examples: [String]
    let description: String
}

struct CollectionStats: Codable {
    let entryCount: Int
    let lastEntryAt: Date?
}

// Entry model is defined in Entry.swift