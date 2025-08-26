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
        // Using centralized configuration
        self.baseURL = AppConfig.baseURL
        
        // Check for stored auth token on init
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            Task { @MainActor in
                self.authToken = token
                self.isAuthenticated = true
            }
            // Optionally validate token with backend
        }
    }
    
    // Anonymous sign in
    func signInAnonymously() async throws {
        print("👤 Signing in anonymously...")
        
        do {
            let authResult = try await Auth.auth().signInAnonymously()
            print("✅ Anonymous sign in successful: \(authResult.user.uid)")
            
            // Update user state on main thread
            await MainActor.run {
                self.currentUser = User(
                    uid: authResult.user.uid,
                    phoneNumber: nil,
                    email: nil,
                    displayName: "Anonymous User"
                )
                self.isAuthenticated = true
                self.authToken = authResult.user.uid
            }
            
            // Store the anonymous auth state
            UserDefaults.standard.set(authResult.user.uid, forKey: "authToken")
            UserDefaults.standard.set(true, forKey: "isAnonymous")
            
        } catch {
            print("❌ Anonymous sign in failed: \(error)")
            throw error
        }
    }
    
    // Upgrade anonymous user to phone auth
    func upgradeAnonymousToPhone(phoneNumber: String) async throws {
        // This will link the anonymous account to a phone number
        // Implementation for later
        print("🔄 Upgrading anonymous user to phone auth...")
    }
    
    // Send verification code via backend
    func sendVerificationCode(to phoneNumber: String) async throws {
        let urlString = "\(AppConfig.authBaseURL)/phone/send-code"
        print("📞 Attempting to send code to: \(phoneNumber)")
        print("🔗 Full URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["phoneNumber": phoneNumber]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("📤 Request body: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "nil")")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Response status: \(httpResponse.statusCode)")
                print("📥 Response headers: \(httpResponse.allHeaderFields)")
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
            print("📥 Response body: \(responseString)")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw AuthError.serverError
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ HTTP Error: \(httpResponse.statusCode)")
                // Try to parse error message from response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorData["error"] as? String {
                    throw NSError(domain: "AuthService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                }
                throw AuthError.serverError
            }
            
            let result = try JSONDecoder().decode(SendCodeResponse.self, from: data)
            
            if result.success {
                print("✅ Code sent successfully, sessionId: \(result.sessionId ?? "nil")")
                await MainActor.run {
                    self.sessionId = result.sessionId
                }
            } else {
                print("❌ Server returned success=false: \(result.message ?? "No message")")
                throw AuthError.sendCodeFailed
            }
        } catch {
            print("❌ Network error: \(error.localizedDescription)")
            print("❌ Full error: \(error)")
            throw error
        }
    }
    
    // Verify code via backend
    func verifyCode(_ code: String) async throws {
        guard let sessionId = sessionId else {
            print("❌ No session ID available")
            throw AuthError.missingSessionId
        }
        
        let urlString = "\(AppConfig.authBaseURL)/phone/verify-code"
        print("🔐 Verifying code: \(code)")
        print("🔗 Full URL: \(urlString)")
        print("📝 Session ID: \(sessionId)")
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
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
        
        print("📤 Request body: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "nil")")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Response status: \(httpResponse.statusCode)")
                print("📥 Response headers: \(httpResponse.allHeaderFields)")
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
            print("📥 Response body: \(responseString)")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw AuthError.serverError
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ HTTP Error: \(httpResponse.statusCode)")
                // Try to parse error message from response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorData["error"] as? String {
                    throw NSError(domain: "AuthService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                }
                throw AuthError.serverError
            }
            
            let result = try JSONDecoder().decode(VerifyCodeResponse.self, from: data)
            
            if result.success, let customToken = result.customToken {
                print("✅ Verification successful, got custom token")
                // Sign in to Firebase with the custom token from backend
                let authResult = try await Auth.auth().signIn(withCustomToken: customToken)
            
            // Store the auth token
            UserDefaults.standard.set(customToken, forKey: "authToken")
            
            // Update user state on main thread
            await MainActor.run {
                self.authToken = customToken
                self.currentUser = User(
                    uid: authResult.user.uid,
                    phoneNumber: result.phoneNumber ?? authResult.user.phoneNumber,
                    email: authResult.user.email,
                    displayName: authResult.user.displayName
                )
                
                self.isAuthenticated = true
                self.sessionId = nil
            }
            
                // FirebaseManager will automatically detect the auth state change
                // via its auth state listener
            } else {
                print("❌ Verification failed: \(result)")
                throw AuthError.verifyCodeFailed
            }
        } catch {
            print("❌ Verify error: \(error.localizedDescription)")
            print("❌ Full error: \(error)")
            throw error
        }
    }
    
    // Resend code via backend
    func resendCode() async throws {
        guard let sessionId = sessionId else {
            throw AuthError.missingSessionId
        }
        
        guard let url = URL(string: "\(AppConfig.authBaseURL)/phone/resend-code") else {
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
        UserDefaults.standard.removeObject(forKey: "authToken")
        
        // Clear user state on main thread
        Task { @MainActor in
            authToken = nil
            currentUser = nil
            isAuthenticated = false
            sessionId = nil
        }
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