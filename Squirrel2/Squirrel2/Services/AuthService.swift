import Foundation
import FirebaseAuth

// Auth errors
enum AuthError: LocalizedError {
    case invalidURL
    case serverError
    case sendCodeFailed
    case verifyCodeFailed
    case missingSessionId
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .serverError:
            return "Server error occurred"
        case .sendCodeFailed:
            return "Failed to send verification code"
        case .verifyCodeFailed:
            return "Invalid verification code"
        case .missingSessionId:
            return "Session expired. Please request a new code"
        }
    }
}

// User model for frontend
struct User: Codable {
    let uid: String
    let phoneNumber: String?
    let email: String?
    let displayName: String?
}

class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var sessionId: String?
    @Published var authToken: String?
    
    private let baseURL: String
    
    init() {
        #if DEBUG
        self.baseURL = "http://localhost:3000"
        #else
        self.baseURL = "https://your-production-url.com"
        #endif
        
        // Check for stored auth token on init
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            self.authToken = token
            self.isAuthenticated = true
            // Optionally validate token with backend
        }
    }
    
    // Send verification code via backend
    func sendVerificationCode(to phoneNumber: String) async throws {
        guard let url = URL(string: "\(baseURL)/auth/phone/send-code") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["phoneNumber": phoneNumber]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
        
        let result = try JSONDecoder().decode(SendCodeResponse.self, from: data)
        
        if result.success {
            self.sessionId = result.sessionId
        } else {
            throw AuthError.sendCodeFailed
        }
    }
    
    // Verify code via backend
    func verifyCode(_ code: String) async throws {
        guard let sessionId = sessionId else {
            throw AuthError.missingSessionId
        }
        
        guard let url = URL(string: "\(baseURL)/auth/phone/verify-code") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "sessionId": sessionId,
            "code": code
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
        
        let result = try JSONDecoder().decode(VerifyCodeResponse.self, from: data)
        
        if result.success, let customToken = result.customToken {
            // Sign in to Firebase with the custom token from backend
            let authResult = try await Auth.auth().signIn(withCustomToken: customToken)
            
            // Store the auth token
            self.authToken = customToken
            UserDefaults.standard.set(customToken, forKey: "authToken")
            
            // Update user state
            self.currentUser = User(
                uid: authResult.user.uid,
                phoneNumber: result.phoneNumber ?? authResult.user.phoneNumber,
                email: authResult.user.email,
                displayName: authResult.user.displayName
            )
            
            self.isAuthenticated = true
            self.sessionId = nil
            
            // FirebaseManager will automatically detect the auth state change
            // via its auth state listener
        } else {
            throw AuthError.verifyCodeFailed
        }
    }
    
    // Resend code via backend
    func resendCode() async throws {
        guard let sessionId = sessionId else {
            throw AuthError.missingSessionId
        }
        
        guard let url = URL(string: "\(baseURL)/auth/phone/resend-code") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["sessionId": sessionId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.serverError
        }
    }
    
    func signOut() {
        // Clear auth token
        authToken = nil
        UserDefaults.standard.removeObject(forKey: "authToken")
        
        // Clear user state
        currentUser = nil
        isAuthenticated = false
        sessionId = nil
    }
}

// Response models
struct SendCodeResponse: Codable {
    let success: Bool
    let sessionId: String?
    let message: String?
}

struct VerifyCodeResponse: Codable {
    let success: Bool
    let uid: String?
    let customToken: String?
    let phoneNumber: String?
    let isNewUser: Bool?
}