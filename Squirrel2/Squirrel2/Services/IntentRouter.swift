//
//  IntentRouter.swift
//  Squirrel2
//
//  Pre-router using Chat Completions API with structured outputs
//  Classifies user input as command vs question BEFORE Realtime API
//

import Foundation

// MARK: - Structured Output Models

struct IntentResult: Codable {
    enum Intent: String, Codable {
        case command  // Task creation, reminders
        case question // Needs verbal response
    }
    
    let intent: Intent
    let task: TaskExtraction?
    
    struct TaskExtraction: Codable {
        let title: String
        let dueDate: String? // Natural language like "tomorrow at 3pm"
        let priority: String?
    }
}

// MARK: - Intent Router

@MainActor
class IntentRouter: ObservableObject {
    private var apiKey: String = ""
    
    init() {}
    
    func initialize(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func classifyIntent(_ utterance: String) async throws -> IntentResult {
        guard !apiKey.isEmpty else {
            print("❌ No API key available for intent router")
            throw IntentRouterError.noApiKey
        }
        
        print("🔍 Classifying: \"\(utterance)\"")
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use structured outputs with strict JSON schema
        let payload: [String: Any] = [
            "model": "gpt-4o-mini", // Fast, cheap model for classification
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are a classifier that determines if user input is a COMMAND (task/reminder) or QUESTION.
                    
                    COMMAND examples:
                    - "Remind me to call mom"
                    - "Add milk to my shopping list"
                    - "Create a task for the meeting tomorrow"
                    - "I need to pay bills"
                    
                    QUESTION examples:
                    - "What's on my task list?"
                    - "What did you just do?"
                    - "How are you?"
                    - "What time is it?"
                    
                    If it's a command, extract the task details.
                    """
                ],
                [
                    "role": "user",
                    "content": utterance
                ]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "intent_classification",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "intent": [
                                "type": "string",
                                "enum": ["command", "question"]
                            ],
                            "task": [
                                "type": ["object", "null"],
                                "properties": [
                                    "title": ["type": "string"],
                                    "dueDate": ["type": ["string", "null"]],
                                    "priority": ["type": ["string", "null"]]
                                ],
                                "required": ["title", "dueDate", "priority"],
                                "additionalProperties": false
                            ]
                        ],
                        "required": ["intent", "task"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "temperature": 0.1, // Low temperature for consistent classification
            "max_tokens": 100
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw IntentRouterError.apiError
        }
        
        if httpResponse.statusCode != 200 {
            print("❌ API Error - Status: \(httpResponse.statusCode)")
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("   Error details: \(errorData)")
            }
            throw IntentRouterError.apiError
        }
        
        // Parse OpenAI response
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
        
        print("🎯 Intent Classification: \(intentResult.intent)")
        if let task = intentResult.task {
            print("   📝 Task: \(task.title)")
        }
        
        return intentResult
    }
}

// MARK: - Error Types

enum IntentRouterError: Error {
    case noApiKey
    case apiError
    case noContent
    case invalidJSON
}