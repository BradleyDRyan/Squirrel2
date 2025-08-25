//
//  ChatInputBar.swift
//  Squirrel2
//
//  Chat input bar component
//

import SwiftUI

struct ChatInputBar: View {
    @Binding var messageText: String
    let isLoading: Bool
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.squirrelDivider)
            
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .font(.squirrelChatInput)
                    .lineLimit(1...4)
                    .textFieldStyle(PlainTextFieldStyle())
                    .disabled(isLoading)
                
                sendButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.squirrelBackground)
        }
    }
    
    @ViewBuilder
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(buttonColor)
                .background(Circle().fill(Color.white))
        }
        .disabled(shouldDisableButton)
        .animation(.easeInOut(duration: 0.2), value: messageText.isEmpty)
    }
    
    private var shouldDisableButton: Bool {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
    }
    
    private var buttonColor: Color {
        shouldDisableButton ? Color.gray.opacity(0.5) : Color.squirrelPrimary
    }
}
