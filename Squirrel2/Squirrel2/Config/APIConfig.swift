//
//  APIConfig.swift
//  Squirrel2
//
//  API configuration structures
//

import Foundation

// Response structure for API key fetching
struct APIKeyResponse: Codable {
    let success: Bool
    let apiKey: String?
    let error: String?
}
