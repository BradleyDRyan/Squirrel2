//
//  IntentRouter.swift
//  Squirrel2
//
//  Routes user input to appropriate handler based on intent
//

import Foundation

// Intent classification result
struct IntentResult: Codable {
    enum Intent: String, Codable {
        case command  // Task creation, reminders
        case question // Needs conversation
    }
    
    let intent: Intent
    let task: TaskExtraction?
    
    struct TaskExtraction: Codable {
        let title: String
        let dueDate: String?
        let priority: String?
    }
}

// Intent Router using GPT-4o-mini
@MainActor
class IntentRouter: ObservableObject {
    private var apiKey: String = ""
    
    func initialize(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func classifyIntent(_ utterance: String) async throws -> IntentResult {
        guard !apiKey.isEmpty else {
            throw IntentRouterError.noApiKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "system",
                    "content": """
                    Classify if the user input is a COMMAND (task/reminder) or QUESTION.
                    
                    COMMAND examples:
                    - "Remind me to call mom"
                    - "Add milk to my shopping list"
                    - "Create a task for the meeting tomorrow"
                    
                    QUESTION examples:
                    - "What's the weather?"
                    - "How many cups in an ounce?"
                    - "What time is it?"
                    
                    For commands, extract task details.
                    
                    Return JSON: {"intent": "command" or "question", "task": null or {"title": "...", "dueDate": null, "priority": null}}
                    """
                ],
                [
                    "role": "user",
                    "content": utterance
                ]
            ],
            "temperature": 0.1,
            "max_tokens": 100
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw IntentRouterError.apiError
        }
        
        // Parse response
        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw IntentRouterError.noContent
        }
        
        // Parse the JSON content
        let intentResult = try JSONDecoder().decode(IntentResult.self, from: Data(content.utf8))
        
        print("🎯 Intent: \(intentResult.intent)")
        return intentResult
    }
}

enum IntentRouterError: Error {
    case noApiKey
    case apiError
    case noContent
}