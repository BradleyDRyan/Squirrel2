//
//  IntentClassifier.swift
//  Squirrel2
//
//  Quick intent classification for voice input
//

import Foundation

struct IntentClassifier {
    
    enum UserIntent: String {
        case command = "command"  // Task creation, reminders, etc.
        case question = "question"  // Needs verbal response
        case greeting = "greeting"  // Social interaction
    }
    
    struct Classification {
        let intent: UserIntent
        let confidence: Double
        let shouldSpeak: Bool
    }
    
    // Lightweight classification based on patterns
    static func classifyIntent(_ input: String) -> Classification {
        let lowercased = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Command patterns (should be silent)
        let commandPatterns = [
            "remind me",
            "create a task",
            "add a task",
            "make a reminder",
            "schedule",
            "add to my list",
            "put on my list",
            "don't forget",
            "i need to",
            "task:",
            "todo:",
            "remember to",
            "note that",
            "save that"
        ]
        
        // Question patterns (needs response)
        let questionPatterns = [
            "what",
            "when",
            "where", 
            "why",
            "how",
            "who",
            "is it",
            "are you",
            "can you",
            "could you explain",
            "tell me",
            "do you",
            "did you",
            "did that work",
            "was that",
            "show me my tasks",
            "list my",
            "what's on my"
        ]
        
        // Greeting patterns (optional response)
        let greetingPatterns = [
            "hello",
            "hi",
            "hey",
            "good morning",
            "good afternoon",
            "good evening",
            "goodbye",
            "bye",
            "thanks",
            "thank you"
        ]
        
        // Check for command patterns
        for pattern in commandPatterns {
            if lowercased.contains(pattern) {
                return Classification(
                    intent: .command,
                    confidence: 0.9,
                    shouldSpeak: false
                )
            }
        }
        
        // Check for question patterns  
        for pattern in questionPatterns {
            if lowercased.starts(with: pattern) || lowercased.contains("?") {
                return Classification(
                    intent: .question,
                    confidence: 0.85,
                    shouldSpeak: true
                )
            }
        }
        
        // Check for greetings
        for pattern in greetingPatterns {
            if lowercased.contains(pattern) {
                return Classification(
                    intent: .greeting,
                    confidence: 0.8,
                    shouldSpeak: true
                )
            }
        }
        
        // Default to command if short and imperative
        if lowercased.split(separator: " ").count <= 5 {
            return Classification(
                intent: .command,
                confidence: 0.6,
                shouldSpeak: false
            )
        }
        
        // Default to question for longer inputs
        return Classification(
            intent: .question,
            confidence: 0.5,
            shouldSpeak: true
        )
    }
    
    // Quick check if we should generate audio
    static func shouldGenerateAudio(for input: String) -> Bool {
        return classifyIntent(input).shouldSpeak
    }
}