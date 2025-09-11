//
//  AppConfig.swift
//  Squirrel2
//
//  Centralized configuration for all app settings
//

import Foundation

struct AppConfig {
    // MARK: - API Configuration
    
    /// The base URL for the backend API
    static var baseURL: String {
        // Using the squirrel2 Vercel project
        return "https://squirrel2.vercel.app"
    }
    
    /// Full API base URL with /api path
    static var apiBaseURL: String {
        return "\(baseURL)/api"
    }
    
    /// Auth endpoints base URL
    static var authBaseURL: String {
        return "\(baseURL)/auth"
    }
    
    // MARK: - Feature Flags
    
    /// Enable debug logging
    static var debugLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - App Info
    
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    // MARK: - Timeouts
    
    static let requestTimeout: TimeInterval = 30.0
    static let uploadTimeout: TimeInterval = 60.0
    
    // MARK: - Methods
    
    /// Print current configuration (for debugging)
    static func printConfiguration() {
        if debugLoggingEnabled {
            print("=== App Configuration ===")
            print("Base URL: \(baseURL)")
            print("API Base URL: \(apiBaseURL)")
            print("Auth Base URL: \(authBaseURL)")
            print("App Version: \(appVersion)")
            print("Build Number: \(buildNumber)")
            print("========================")
        }
    }
}