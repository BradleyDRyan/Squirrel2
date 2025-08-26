//
//  ChatAIManager.swift
//  Squirrel2
//
//  Created by Claude on 8/25/25.
//

import SwiftUI
import Combine

@MainActor
class ChatAIManager: ObservableObject {
    @Published var isLoadingKey = false
    @Published var error: String?
    
    init() {}
    
    func streamMessageWithHistory(_ message: String, history: [ChatMessage], onChunk: @escaping (String) -> Void) async throws {
        // Get auth token
        guard let user = FirebaseManager.shared.currentUser,
              let token = try? await user.getIDToken() else {
            throw ChatAIError.authenticationFailed
        }
        
        let url = URL(string: "\(AppConfig.apiBaseURL)/ai/chat/stream")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build messages array in OpenAI format
        var messages = [ChatCompletionMessage(role: "system", content: "You are Squirrel, a helpful AI assistant. Be concise and friendly.")]
        
        for historyMessage in history.suffix(10) {
            messages.append(ChatCompletionMessage(
                role: historyMessage.isFromUser ? "user" : "assistant",
                content: historyMessage.content
            ))
        }
        
        messages.append(ChatCompletionMessage(role: "user", content: message))
        
        let requestBody: [String: Any] = ["messages": messages.map { ["role": $0.role, "content": $0.content] }]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ChatAIError.requestFailed(statusCode: httpResponse.statusCode)
        }
        
        // Parse SSE stream
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                guard let data = jsonString.data(using: String.Encoding.utf8) else { continue }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String {
                        
                        switch type {
                        case "content":
                            if let content = json["content"] as? String {
                                await MainActor.run {
                                    onChunk(content)
                                }
                            }
                        case "done":
                            return
                        case "error":
                            if let error = json["error"] as? String {
                                throw ChatAIError.requestFailed(statusCode: 500)
                            }
                        default:
                            break
                        }
                    }
                } catch {
                    print("Error parsing SSE data: \(error)")
                }
            }
        }
    }
}

enum ChatAIError: LocalizedError {
    case apiKeyMissing
    case authenticationFailed
    case invalidResponse
    case requestFailed(statusCode: Int)
    case noResponse
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "OpenAI API key is missing"
        case .authenticationFailed:
            return "Authentication failed. Please check your API key."
        case .invalidResponse:
            return "Invalid response from server"
        case .requestFailed(let statusCode):
            return "Request failed with status code: \(statusCode)"
        case .noResponse:
            return "No response content received"
        }
    }
}

// MARK: - API Models

struct ChatCompletionMessage: Codable {
    let role: String
    let content: String
}
