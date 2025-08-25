//
//  ContentView.swift
//  Squirrel2
//
//  Created by Bradley Ryan on 8/25/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @State private var showingChat = false
    @State private var showingPhoneAuth = false
    @State private var showingAPISettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Logo
                Image(systemName: "leaf.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.squirrelPrimary)
                    .padding(.top, 60)
                
                // Title
                VStack(spacing: 8) {
                    Text("Squirrel 2.0")
                        .font(.squirrelLargeTitle)
                        .foregroundColor(.squirrelTextPrimary)
                    
                    Text(firebaseManager.isAuthenticated ? "Welcome back!" : "Your AI companion")
                        .font(.squirrelSubheadline)
                        .foregroundColor(.squirrelTextSecondary)
                }
                
                Spacer()
                
                // Auth status and actions
                VStack(spacing: 20) {
                    if firebaseManager.isAuthenticated {
                        // Authenticated state
                        VStack(spacing: 16) {
                            if let phoneNumber = firebaseManager.currentUser?.phoneNumber {
                                HStack {
                                    Image(systemName: "phone.circle.fill")
                                        .foregroundColor(.squirrelPrimary.opacity(0.8))
                                    Text(phoneNumber)
                                        .font(.squirrelFootnote)
                                        .foregroundColor(.squirrelTextSecondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.squirrelSurfaceBackground)
                                .cornerRadius(20)
                            }
                            
                            Button(action: { showingChat = true }) {
                                HStack {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                    Text("Open Chat")
                                        .font(.squirrelButtonPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.squirrelPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 24)
                            
                            Button(action: {
                                try? firebaseManager.signOut()
                            }) {
                                Text("Sign Out")
                                    .font(.squirrelButtonSecondary)
                                    .foregroundColor(.squirrelTextSecondary)
                            }
                        }
                    } else {
                        // Not authenticated state
                        VStack(spacing: 16) {
                            Text("Sign in to get started")
                                .font(.squirrelCallout)
                                .foregroundColor(.squirrelTextSecondary)
                            
                            Button(action: { showingPhoneAuth = true }) {
                                HStack {
                                    Image(systemName: "phone.fill")
                                    Text("Sign in with Phone")
                                        .font(.squirrelButtonPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.squirrelPrimary)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.squirrelBackground)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAPISettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.squirrelPrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingChat) {
            ChatView()
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showingPhoneAuth) {
            PhoneAuthView()
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showingAPISettings) {
            APISettingsView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(FirebaseManager.shared)
}
