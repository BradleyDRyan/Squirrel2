//
//  APISettingsView.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import SwiftUI

struct APISettingsView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("API Key Status") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("OpenAI API Key", systemImage: "key.fill")
                            .font(.squirrelHeadline)
                            .foregroundColor(.squirrelPrimary)
                        
                        HStack {
                            Text("Status:")
                                .font(.squirrelCallout)
                            Spacer()
                            if firebaseManager.openAIKey != nil {
                                Label("Configured", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.squirrelFootnote)
                            } else {
                                Label("Loading...", systemImage: "arrow.clockwise.circle")
                                    .foregroundColor(.orange)
                                    .font(.squirrelFootnote)
                            }
                        }
                        
                        Text("API key is managed automatically by the backend")
                            .font(.squirrelFootnote)
                            .foregroundColor(.squirrelTextSecondary)
                    }
                }
                
                Section("About Voice AI") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice AI uses OpenAI's Realtime API to enable natural voice conversations.")
                            .font(.squirrelBody)
                        
                        Text("Features:")
                            .font(.squirrelCallout)
                            .fontWeight(.semibold)
                            .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Real-time voice conversations", systemImage: "mic.fill")
                            Label("Natural language understanding", systemImage: "brain")
                            Label("Contextual responses", systemImage: "bubble.left.and.bubble.right.fill")
                            Label("Multi-turn conversations", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .font(.squirrelFootnote)
                        .foregroundColor(.squirrelTextSecondary)
                    }
                }
            }
            .navigationTitle("Voice AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    APISettingsView()
        .environmentObject(FirebaseManager.shared)
}
