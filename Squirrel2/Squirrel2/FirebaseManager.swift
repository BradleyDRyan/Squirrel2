//
//  FirebaseManager.swift
//  Squirrel2
//
//  Firebase integration manager with phone authentication
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import SwiftUI

class FirebaseManager: NSObject, ObservableObject {
    static let shared = FirebaseManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: FirebaseAuth.User?
    @Published var verificationID: String?
    @Published var openAIKey: String?
    
    private var auth: Auth?
    private var firestore: Firestore?
    private var storage: Storage?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    override init() {
        super.init()
        setupFirebase()
    }
    
    private func setupFirebase() {
        // Firebase should already be configured in the App init
        guard let app = FirebaseApp.app() else {
            print("❌ ERROR: Firebase not configured. Please check GoogleService-Info.plist and app initialization")
            return
        }
        
        print("✅ Firebase configured successfully")
        print("📱 App Name: \(app.name)")
        print("🔑 Project ID: \(app.options.projectID ?? "nil")")
        print("📦 Bundle ID: \(app.options.bundleID)")
        print("🔗 API Key: \(app.options.apiKey ?? "nil")")
        
        self.auth = Auth.auth()
        self.firestore = Firestore.firestore()
        self.storage = Storage.storage()
        
        print("✅ Auth initialized: \(auth != nil)")
        print("✅ Firestore initialized: \(firestore != nil)")
        print("✅ Storage initialized: \(storage != nil)")
        
        // Configure auth settings
        configureAuthSettings()
        
        // Listen for auth state changes
        if let auth = auth {
            authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
                DispatchQueue.main.async {
                    self?.currentUser = user
                    self?.isAuthenticated = user != nil
                    
                    // Fetch API key when user is authenticated (including anonymous)
                    if user != nil {
                        Task {
                            await self?.fetchOpenAIKey()
                        }
                    }
                }
            }
        }
        
        // Sign in anonymously on first launch if no user
        Task {
            if auth?.currentUser == nil {
                do {
                    try await self.signInAnonymously()
                    print("✅ Signed in anonymously")
                } catch {
                    print("❌ Anonymous sign in failed: \(error)")
                }
            }
        }
    }
    
    private func configureAuthSettings() {
        guard let auth = auth else { return }
        
        // Use test phone numbers in debug mode
        #if DEBUG
        auth.settings?.isAppVerificationDisabledForTesting = true
        #endif
        
        // Set language code
        auth.languageCode = Locale.current.language.languageCode?.identifier
    }
    
    // Sign in anonymously
    func signInAnonymously() async throws {
        guard let auth = auth else {
            throw FirebaseError.firebaseNotConfigured
        }
        
        let result = try await auth.signInAnonymously()
        print("✅ Anonymous auth successful: \(result.user.uid)")
    }
    
    // Send verification code to phone number
    @MainActor
    func sendVerificationCode(to phoneNumber: String) async throws {
        // Ensure Firebase is configured
        guard FirebaseApp.app() != nil else {
            print("ERROR: FirebaseApp.app() is nil")
            throw FirebaseError.firebaseNotConfigured
        }
        
        // Ensure we have auth configured
        guard let auth = auth else {
            print("ERROR: Auth instance is nil")
            throw FirebaseError.firebaseNotConfigured
        }
        
        print("Attempting to send verification to: \(phoneNumber)")
        print("Auth instance: \(auth)")
        print("FirebaseApp: \(String(describing: FirebaseApp.app()))")
        
        // Use completion handler version which is more stable
        return try await withCheckedThrowingContinuation { continuation in
            PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { verificationID, error in
                if let error = error {
                    print("Phone auth error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else if let verificationID = verificationID {
                    self.verificationID = verificationID
                    print("Verification code sent successfully, ID: \(verificationID)")
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: FirebaseError.missingVerificationID)
                }
            }
        }
    }
    
    // Verify the SMS code
    func verifyCode(_ code: String) async throws {
        guard let auth = auth else {
            throw FirebaseError.firebaseNotConfigured
        }
        
        guard let verificationID = verificationID else {
            throw FirebaseError.missingVerificationID
        }
        
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        
        try await auth.signIn(with: credential)
    }
    
    func signOut() throws {
        guard let auth = auth else {
            throw FirebaseError.firebaseNotConfigured
        }
        try auth.signOut()
        verificationID = nil
    }
    
    func fetchUserData(userId: String) async throws -> [String: Any]? {
        guard let firestore = firestore else {
            throw FirebaseError.firebaseNotConfigured
        }
        let document = try await firestore.collection("users").document(userId).getDocument()
        return document.data()
    }
    
    func updateUserData(userId: String, data: [String: Any]) async throws {
        guard let firestore = firestore else {
            throw FirebaseError.firebaseNotConfigured
        }
        try await firestore.collection("users").document(userId).setData(data, merge: true)
    }
    
    deinit {
        if let authStateListener = authStateListener {
            auth?.removeStateDidChangeListener(authStateListener)
        }
    }
}

enum FirebaseError: LocalizedError {
    case missingVerificationID
    case firebaseNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .missingVerificationID:
            return "Verification ID is missing. Please request a new code."
        case .firebaseNotConfigured:
            return "Firebase is not properly configured. Please restart the app."
        }
    }
}

// MARK: - API Key Management
extension FirebaseManager {
    @MainActor
    func fetchOpenAIKey() async {
        guard let user = currentUser else {
            print("❌ No user to fetch API key for")
            return
        }
        
        do {
            // Get auth token
            let token = try await user.getIDToken()
            
            // Fetch from backend
            let url = URL(string: "\(AppConfig.apiBaseURL)/config/openai-key")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ Failed to fetch API key - HTTP status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            
            let keyResponse = try JSONDecoder().decode(APIKeyResponse.self, from: data)
            if let apiKey = keyResponse.apiKey {
                self.openAIKey = apiKey
                print("✅ Fetched OpenAI API key from backend (user: \(user.isAnonymous ? "anonymous" : "authenticated"))")
            } else {
                print("❌ No API key in response: \(keyResponse.error ?? "unknown error")")
            }
        } catch {
            print("❌ Error fetching API key: \(error)")
        }
    }
}
