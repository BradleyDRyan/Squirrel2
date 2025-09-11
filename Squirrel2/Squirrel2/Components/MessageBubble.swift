//
//  MessageBubble.swift
//  Squirrel2
//
//  Message bubble component for chat
//

import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromUser {
                Spacer(minLength: 50)
                userMessage
            } else {
                assistantMessagear
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var userMessage: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                if message.source == .voice {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                }
                Text(message.content)
                    .messageStyle(isFromUser: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.userMessageBackground)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 4,
                topTrailingRadius: 20
            ))
            .shadow(color: .squirrelShadow, radius: 4, x: 0, y: 2)
            
            Text(formattedTime)
                .timestampStyle()
                .padding(.trailing, 4)
        }
    }
    
    @ViewBuilder
    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                if message.source == .voice {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundColor(.squirrelTextSecondary)
                }
                Text(message.content)
                    .messageStyle(isFromUser: false)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Text(formattedTime)
                .timestampStyle()
        }
    }
}
