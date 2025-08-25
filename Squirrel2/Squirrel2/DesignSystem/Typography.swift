//
//  Typography.swift
//  Squirrel2
//
//  Design System - Typography
//

import SwiftUI

extension Font {
    // Headings
    static let squirrelLargeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let squirrelTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let squirrelTitle2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let squirrelTitle3 = Font.system(size: 20, weight: .semibold, design: .rounded)
    
    // Body text
    static let squirrelHeadline = Font.system(size: 17, weight: .semibold, design: .default)
    static let squirrelBody = Font.system(size: 17, weight: .regular, design: .default)
    static let squirrelCallout = Font.system(size: 16, weight: .regular, design: .default)
    static let squirrelSubheadline = Font.system(size: 15, weight: .regular, design: .default)
    static let squirrelFootnote = Font.system(size: 13, weight: .regular, design: .default)
    
    // Chat specific
    static let squirrelChatMessage = Font.system(size: 16, weight: .regular, design: .default)
    static let squirrelChatTimestamp = Font.system(size: 11, weight: .regular, design: .default)
    static let squirrelChatInput = Font.system(size: 17, weight: .regular, design: .default)
    
    // Buttons
    static let squirrelButtonPrimary = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let squirrelButtonSecondary = Font.system(size: 14, weight: .medium, design: .rounded)
}

// Text style modifiers
struct MessageTextStyle: ViewModifier {
    let isFromUser: Bool
    
    func body(content: Content) -> some View {
        content
            .font(.squirrelChatMessage)
            .foregroundColor(isFromUser ? .squirrelTextPrimary : .squirrelTextPrimary)
    }
}

struct TimestampTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.squirrelChatTimestamp)
            .foregroundColor(.squirrelTextSecondary.opacity(0.6))
    }
}

extension View {
    func messageStyle(isFromUser: Bool) -> some View {
        modifier(MessageTextStyle(isFromUser: isFromUser))
    }
    
    func timestampStyle() -> some View {
        modifier(TimestampTextStyle())
    }
}