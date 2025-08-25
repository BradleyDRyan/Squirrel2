//
//  APISettingsView.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import SwiftUI

struct APISettingsView: View {
    @State private var apiKey = ""
    @State private var showingKey = false
    @State private var keyIsSaved = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("OpenAI API Key", systemImage: "key.fill")
                            .font(.squirrelHeadline)
                            .foregroundColor(.squirrelPrimary)
                        
                        Text("Required for voice AI conversations")
                            .font(.squirrelFootnote)
                            .foregroundColor(.squirrelTextSecondary)
                    }
                    
                    HStack {
                        if showingKey {
                            TextField("sk-...", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        Button(action: { showingKey.toggle() }) {
                            Image(systemName: showingKey ? "eye.slash" : "eye")
                                .foregroundColor(.squirrelTextSecondary)
                        }
                    }
                    
                    Button(action: saveAPIKey) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save API Key")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.squirrelPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(apiKey.isEmpty)
                    
                    if keyIsSaved {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key saved successfully")
                                .font(.squirrelFootnote)
                                .foregroundColor(.green)
                        }
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Get your API key from:")
                            .font(.squirrelFootnote)
                        Link("platform.openai.com/api-keys", 
                             destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.squirrelFootnote)
                        
                        Text("Your API key is stored securely on this device and never sent to our servers.")
                            .font(.squirrelFootnote)
                            .foregroundColor(.squirrelTextSecondary)
                            .padding(.top, 4)
                    }
                }
                
                Section("Current Status") {
                    HStack {
                        Text("API Key Status")
                        Spacer()
                        if APIConfig.isOpenAIKeyConfigured {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.squirrelFootnote)
                        } else {
                            Label("Not Configured", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.squirrelFootnote)
                        }
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
        .onAppear {
            // Load existing key if available (masked for security)
            if APIConfig.isOpenAIKeyConfigured {
                apiKey = String(repeating: "•", count: 20) + "..."
            }
        }
    }
    
    private func saveAPIKey() {
        guard !apiKey.isEmpty && !apiKey.contains("•") else { return }
        
        APIConfig.saveOpenAIKey(apiKey)
        
        withAnimation {
            keyIsSaved = true
        }
        
        // Hide success message after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                keyIsSaved = false
            }
        }
    }
}

#Preview {
    APISettingsView()
}
