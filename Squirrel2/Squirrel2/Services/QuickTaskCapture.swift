//
//  QuickTaskCapture.swift
//  Squirrel2
//
//  Lightweight task capture using Whisper API instead of Realtime
//

import Foundation

@MainActor
class QuickTaskCapture: ObservableObject {
    
    private var apiKey = ""
    private let functionHandler = RealtimeFunctionHandler()
    
    func initialize(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // Process audio using Whisper API (much cheaper than Realtime)
    func transcribeAudio(_ audioData: Data) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct WhisperResponse: Codable {
            let text: String
        }
        
        let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return response.text
    }
    
    // Create task directly without any voice feedback
    func createTaskFromTranscript(_ transcript: String) async {
        print("📝 Creating task from: \(transcript)")
        
        // Simple extraction - just use the transcript as the title
        let args: [String: Any] = [
            "title": transcript,
            "priority": "medium"
        ]
        
        let argsJSON = try? JSONSerialization.data(withJSONObject: args)
        let argsString = argsJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        _ = await functionHandler.handleFunctionCall(
            name: "create_task",
            arguments: argsString
        )
        
        print("✅ Task created silently")
    }
}