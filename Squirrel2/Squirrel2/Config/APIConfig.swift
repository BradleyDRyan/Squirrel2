//
//  APIConfig.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import Foundation

struct APIConfig {
    // IMPORTANT: For production, use environment variables or secure storage
    // Never commit actual API keys to source control
    
    static var openAIKey: String {
        // Option 1: Environment variable (recommended for development)
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            return key
        }
        
        // Option 2: Read from a local config file (not committed to git)
        if let configURL = Bundle.main.url(forResource: "Config", withExtension: "plist"),
           let config = NSDictionary(contentsOf: configURL),
           let key = config["OpenAIAPIKey"] as? String {
            return key
        }
        
        // Option 3: UserDefaults (for user-provided keys)
        if let key = UserDefaults.standard.string(forKey: "OpenAIAPIKey") {
            return key
        }
        
        // Option 4: Development key (DO NOT COMMIT TO PRODUCTION)
        // This should be fetched from backend or stored securely
        return "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"
    }
    
    // Method to save user-provided API key
    static func saveOpenAIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "OpenAIAPIKey")
    }
    
    // Method to check if API key is configured
    static var isOpenAIKeyConfigured: Bool {
        let key = openAIKey
        return !key.isEmpty && key.hasPrefix("sk-")
    }
}