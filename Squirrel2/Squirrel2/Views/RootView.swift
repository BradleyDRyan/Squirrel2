//
//  RootView.swift
//  Squirrel2
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @StateObject private var authService = AuthService.shared
    @State private var isSigningIn = false
    
    var body: some View {
        if isSigningIn {
            // Loading state
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Setting up your account...")
                    .font(.squirrelCallout)
                    .foregroundColor(.squirrelTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.squirrelBackground)
        } else if firebaseManager.isAuthenticated {
            // Show main app with tabs
            MainTabView()
                .environmentObject(firebaseManager)
        } else {
            // Not authenticated - auto sign in
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Preparing your experience...")
                    .font(.squirrelCallout)
                    .foregroundColor(.squirrelTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.squirrelBackground)
            .onAppear {
                // Automatically sign in anonymously if not authenticated
                if !firebaseManager.isAuthenticated && !isSigningIn {
                    Task {
                        isSigningIn = true
                        do {
                            try await authService.signInAnonymously()
                            
                            // Wait for FirebaseManager's auth state to be updated
                            var retries = 0
                            while firebaseManager.currentUser == nil && retries < 20 {
                                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                retries += 1
                            }
                            
                            // Wait for API key to be fetched
                            if firebaseManager.currentUser != nil {
                                print("✅ User authenticated: \(firebaseManager.currentUser!.uid)")
                                
                                // Wait for API key
                                var keyRetries = 0
                                while firebaseManager.openAIKey == nil && keyRetries < 30 {
                                    try? await Task.sleep(nanoseconds: 100_000_000)
                                    keyRetries += 1
                                }
                                
                                if firebaseManager.openAIKey != nil {
                                    print("✅ API key ready")
                                } else {
                                    print("⚠️ API key not available after \(keyRetries) retries")
                                }
                            }
                        } catch {
                            print("❌ Failed to sign in: \(error)")
                        }
                        isSigningIn = false
                    }
                }
            }
        }
    }
}