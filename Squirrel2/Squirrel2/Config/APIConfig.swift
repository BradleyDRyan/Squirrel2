//
//  APIConfig.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import Foundation
import FirebaseAuth

struct APIConfig {
    // IMPORTANT: Replace this with your actual OpenAI API key
    // Get one from: https://platform.openai.com/api-keys
    private static let OPENAI_API_KEY = "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"
    
    private static var cachedKey: String?
    
    static var openAIKey: String {
        // Check UserDefaults first for a saved key
        if let savedKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey"), !savedKey.isEmpty {
            return savedKey
        }
        
        // Return cached key if available
        if let key = cachedKey {
            return key
        }
        
        // Return the hardcoded key
        return OPENAI_API_KEY
    }
    
    // Method to save API key
    static func saveOpenAIKey(_ key: String) {
        cachedKey = key
        UserDefaults.standard.set(key, forKey: "OpenAIAPIKey")
    }
    
    // Method to check if API key is configured
    static var isOpenAIKeyConfigured: Bool {
        let key = openAIKey
        return !key.isEmpty && key != "YOUR_OPENAI_API_KEY_HERE" && (key.hasPrefix("sk-") || key.hasPrefix("sk-proj-"))
    }
    
    // Simplified method that doesn't require backend
    static func getLocalAPIKey() async throws -> String {
        guard isOpenAIKeyConfigured else {
            throw NSError(domain: "APIConfig", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI API key not configured. Please add your key in APIConfig.swift"
            ])
        }
        return openAIKey
    }
    
    // Keep the backend method but make it optional
    static func fetchAPIKeyFromBackend() async throws -> String {
        // For now, just return the local key since backend is not available
        return try await getLocalAPIKey()
    }
}

struct APIKeyResponse: Codable {
    let success: Bool
    let apiKey: String?
    let error: String?
}
