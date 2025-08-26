import Foundation
import Combine

class APIService: ObservableObject {
    static let shared = APIService()
    
    private let baseURL: String
    private let session = URLSession.shared
    private var authToken: String?
    
    init() {
        // Using centralized configuration
        self.baseURL = AppConfig.apiBaseURL
    }
    
    func setAuthToken(_ token: String) {
        self.authToken = token
    }
    
    private func createRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = body
        return request
    }
    
    private func handleResponse<T: Decodable>(_ data: Data, _ response: URLResponse?, _ error: Error?, type: T.Type) async throws -> T {
        if let error = error {
            throw APIError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    func fetchSpaces() async throws -> [Space] {
        let url = URL(string: "\(baseURL)/spaces")!
        let request = createRequest(url: url)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: [Space].self)
    }
    
    func createSpace(_ space: Space) async throws -> Space {
        let url = URL(string: "\(baseURL)/spaces")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(space)
        let request = createRequest(url: url, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: Space.self)
    }
    
    func fetchConversations(spaceId: String? = nil) async throws -> [Conversation] {
        var urlString = "\(baseURL)/conversations"
        if let spaceId = spaceId {
            urlString += "?spaceId=\(spaceId)"
        }
        let url = URL(string: urlString)!
        let request = createRequest(url: url)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: [Conversation].self)
    }
    
    func createConversation(_ conversation: Conversation) async throws -> Conversation {
        let url = URL(string: "\(baseURL)/conversations")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(conversation)
        let request = createRequest(url: url, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: Conversation.self)
    }
    
    func fetchMessages(conversationId: String) async throws -> [Message] {
        let url = URL(string: "\(baseURL)/conversations/\(conversationId)/messages")!
        let request = createRequest(url: url)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: [Message].self)
    }
    
    func sendMessage(_ message: Message) async throws -> Message {
        let url = URL(string: "\(baseURL)/messages")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(message)
        let request = createRequest(url: url, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: Message.self)
    }
    
    func fetchTasks(spaceId: String? = nil, status: UserTask.TaskStatus? = nil) async throws -> [UserTask] {
        var urlComponents = URLComponents(string: "\(baseURL)/tasks")!
        var queryItems: [URLQueryItem] = []
        
        if let spaceId = spaceId {
            queryItems.append(URLQueryItem(name: "spaceId", value: spaceId))
        }
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        
        let request = createRequest(url: urlComponents.url!)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: [UserTask].self)
    }
    
    func createTask(_ task: UserTask) async throws -> UserTask {
        let url = URL(string: "\(baseURL)/tasks")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(task)
        let request = createRequest(url: url, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: UserTask.self)
    }
    
    func completeTask(_ taskId: String) async throws -> UserTask {
        let url = URL(string: "\(baseURL)/tasks/\(taskId)/complete")!
        let request = createRequest(url: url, method: "POST")
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: UserTask.self)
    }
    
    func fetchEntries(spaceId: String? = nil, type: Entry.EntryType? = nil) async throws -> [Entry] {
        var urlComponents = URLComponents(string: "\(baseURL)/entries")!
        var queryItems: [URLQueryItem] = []
        
        if let spaceId = spaceId {
            queryItems.append(URLQueryItem(name: "spaceId", value: spaceId))
        }
        if let type = type {
            queryItems.append(URLQueryItem(name: "type", value: type.rawValue))
        }
        
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        
        let request = createRequest(url: urlComponents.url!)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: [Entry].self)
    }
    
    func createEntry(_ entry: Entry) async throws -> Entry {
        let url = URL(string: "\(baseURL)/entries")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(entry)
        let request = createRequest(url: url, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: Entry.self)
    }
    
    func fetchThoughts(spaceId: String? = nil, category: Thought.ThoughtCategory? = nil) async throws -> [Thought] {
        var urlComponents = URLComponents(string: "\(baseURL)/thoughts")!
        var queryItems: [URLQueryItem] = []
        
        if let spaceId = spaceId {
            queryItems.append(URLQueryItem(name: "spaceId", value: spaceId))
        }
        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        
        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }
        
        let request = createRequest(url: urlComponents.url!)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: [Thought].self)
    }
    
    func createThought(_ thought: Thought) async throws -> Thought {
        let url = URL(string: "\(baseURL)/thoughts")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(thought)
        let request = createRequest(url: url, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: Thought.self)
    }
    
    func linkThoughts(_ thoughtId: String, to linkedThoughtId: String) async throws -> Thought {
        let url = URL(string: "\(baseURL)/thoughts/\(thoughtId)/link")!
        let body = try JSONSerialization.data(withJSONObject: ["thoughtId": linkedThoughtId])
        let request = createRequest(url: url, method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try await handleResponse(data, response, nil, type: Thought.self)
    }
}

enum APIError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}