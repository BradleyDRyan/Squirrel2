//
//  ContentView.swift
//  Squirrel2
//
//  Created by Bradley Ryan on 8/25/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var authService = AuthService.shared
    @State private var showingChat = false
    @State private var showingPhoneAuth = false
    @State private var isSigningIn = false
    
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
                    
                    Text(firebaseManager.isAuthenticated ? "Welcome!" : "Your AI companion")
                        .font(.squirrelSubheadline)
                        .foregroundColor(.squirrelTextSecondary)
                }
                
                Spacer()
                
                // Auth status and actions
                VStack(spacing: 20) {
                    if isSigningIn {
                        // Loading state
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Setting up your account...")
                                .font(.squirrelCallout)
                                .foregroundColor(.squirrelTextSecondary)
                        }
                    } else if firebaseManager.isAuthenticated {
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
                            
                            Button(action: { 
                                showingChat = true
                            }) {
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
                        // Not authenticated state - will auto sign in
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Preparing your experience...")
                                .font(.squirrelCallout)
                                .foregroundColor(.squirrelTextSecondary)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.squirrelBackground)
            // Settings button removed - API key is managed by backend
        }
        .sheet(isPresented: $showingChat) {
            ChatView()
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showingPhoneAuth) {
            PhoneAuthView()
                .environmentObject(firebaseManager)
        }
        .onAppear {
            // Automatically sign in anonymously if not authenticated
            if !firebaseManager.isAuthenticated && !isSigningIn {
                Task {
                    isSigningIn = true
                    do {
                        try await authService.signInAnonymously()
                        
                        // Wait for FirebaseManager's auth state to be updated via listener
                        var retries = 0
                        while firebaseManager.currentUser == nil && retries < 20 {
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            retries += 1
                        }
                        
                        // Pre-fetch the OpenAI API key after authentication is confirmed
                        if let user = firebaseManager.currentUser {
                            print("🔑 Pre-fetching API key for user: \(user.uid)")
                            do {
                                _ = try await APIConfig.fetchAPIKeyFromBackend()
                                print("✅ API key pre-loaded successfully")
                            } catch {
                                print("⚠️ Failed to pre-fetch API key: \(error)")
                                // Not critical - will retry when needed
                            }
                        } else {
                            print("⚠️ Auth completed but FirebaseManager.currentUser not available after \(retries) retries")
                        }
                        
                        isSigningIn = false
                    } catch {
                        print("❌ Failed to sign in: \(error)")
                        isSigningIn = false
                        // Retry after a delay
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        if !firebaseManager.isAuthenticated {
                            try? await authService.signInAnonymously()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(FirebaseManager.shared)
}
