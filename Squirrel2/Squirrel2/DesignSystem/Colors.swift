//
//  Colors.swift
//  Squirrel2
//
//  Design System - Color Palette
//

import SwiftUI

extension Color {
    // Primary brand colors
    static let squirrelPrimary = Color(hex: "A96D2F") // Warm brown accent
    static let squirrelSecondary = Color(hex: "EE7733") // Warm orange
    static let squirrelAccent = Color(red: 0.800, green: 0.600, blue: 0.400) // Warm beige
    static let squirrelWarmGray = Color(red: 0.733, green: 0.700, blue: 0.667) // Warm gray
    
    // Background colors
    static let primaryBackground = Color.white // Primary white background (#FFF)
    static let groupedBackground = Color(hex: "F9F9F8") // Light gray grouped background
    static let squirrelBackground = Color(hex: "FFFBF5") // Warm white
    static let squirrelWarmBackground = Color(hex: "FFFBF5") // Warm white (alias for VoiceModeView)
    static let squirrelSurfaceBackground = Color(hex: "F2EBDB") // Warm gray surface
    static let squirrelWarmGrayBackground = Color(hex: "F2EBDB") // Warm gray (alias for VoiceModeView)
    
    // Text colors
    static let squirrelTextPrimary = Color.primary
    static let squirrelTextSecondary = Color.secondary
    
    // Message bubble colors
    static let userMessageBackground = Color(hex: "FFFBF5")
    static let assistantMessageBackground = Color.clear
    
    // UI element colors
    static let squirrelDivider = Color.secondary.opacity(0.3)
    static let squirrelShadow = Color.black.opacity(0.08)
    
    // Hex color initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
