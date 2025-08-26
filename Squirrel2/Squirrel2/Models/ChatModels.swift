//
//  ChatModels.swift
//  Squirrel2
//
//  Chat data models
//

import Foundation
import FirebaseFirestore

enum MessageSource: String, Codable {
    case text = "text"
    case voice = "voice"
}

struct ChatMessage: Identifiable, Codable {
    let id: String
    let content: String
    let isFromUser: Bool
    let timestamp: Date
    let conversationId: String
    let source: MessageSource
    let voiceTranscript: String? // For voice messages, store the original transcript
    
    init(id: String = UUID().uuidString,
         content: String,
         isFromUser: Bool,
         timestamp: Date = Date(),
         conversationId: String,
         source: MessageSource = .text,
         voiceTranscript: String? = nil) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.conversationId = conversationId
        self.source = source
        self.voiceTranscript = voiceTranscript
    }
}

struct ChatConversation: Identifiable, Codable {
    let id: String
    var title: String
    var lastMessageAt: Date
    let createdAt: Date
    let userId: String
    
    init(id: String = UUID().uuidString,
         title: String = "New Chat",
         lastMessageAt: Date = Date(),
         createdAt: Date = Date(),
         userId: String) {
        self.id = id
        self.title = title
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.userId = userId
    }
}