import Foundation
import Combine

// MARK: - Message Types

enum VoiceClientMessageType: String, Codable {
    case sessionConfig = "session.config"
    case audioAppend = "audio.append"
    case audioCommit = "audio.commit"
    case textSend = "text.send"
    case interrupt = "interrupt"
    case responseCreate = "response.create"
    case ping = "ping"
}

enum VoiceServerMessageType: String, Codable {
    case status = "status"
    case transcript = "transcript"
    case audio = "audio"
    case text = "text"
    case function = "function"
    case error = "error"
    case pong = "pong"
}

struct VoiceClientMessage: Encodable {
    let type: VoiceClientMessageType
    let data: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case type, data
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let data = data {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            try container.encode(jsonData, forKey: .data)
        }
    }
}

struct VoiceServerMessage: Decodable {
    let type: VoiceServerMessageType
    let data: [String: Any]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(VoiceServerMessageType.self, forKey: .type)
        
        if let dataValue = try? container.decode(Data.self, forKey: .data) {
            data = try? JSONSerialization.jsonObject(with: dataValue) as? [String: Any]
        } else {
            data = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, data
    }
}

// MARK: - WebSocket Client

@MainActor
class VoiceWebSocketClient: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isListening = false
    @Published var connectionError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?
    private let messageSubject = PassthroughSubject<VoiceServerMessage, Never>()
    
    var messagePublisher: AnyPublisher<VoiceServerMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }
    
    func connect(websocketUrl: String) async throws {
        guard let url = URL(string: websocketUrl) else {
            throw VoiceWebSocketError.invalidURL
        }
        
        disconnect()
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Start ping timer
        startPingTimer()
        
        // Wait for connection confirmation
        try await waitForConnection()
    }
    
    private func waitForConnection() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            
            // Set a timeout
            Task {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                cancellable?.cancel()
                if !isConnected {
                    continuation.resume(throwing: VoiceWebSocketError.connectionTimeout)
                }
            }
            
            // Listen for connection status
            cancellable = messagePublisher
                .first { message in
                    if message.type == .status,
                       let connected = message.data?["connected"] as? Bool {
                        return connected
                    }
                    return false
                }
                .sink { [weak self] _ in
                    self?.isConnected = true
                    continuation.resume()
                }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    
                    // Continue receiving messages
                    self.receiveMessage()
                    
                case .failure(let error):
                    print("WebSocket receive error: \(error)")
                    self.handleDisconnection(error: error)
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let message = try JSONDecoder().decode(VoiceServerMessage.self, from: data)
            
            // Update state based on message type
            switch message.type {
            case .status:
                if let data = message.data {
                    if let connected = data["connected"] as? Bool {
                        isConnected = connected
                    }
                    if let listening = data["listening"] as? Bool {
                        isListening = listening
                    }
                    if let speechStarted = data["speechStarted"] as? Bool, speechStarted {
                        isListening = true
                    }
                    if let speechStopped = data["speechStopped"] as? Bool, speechStopped {
                        isListening = false
                    }
                }
                
            case .error:
                if let errorMessage = message.data?["message"] as? String {
                    connectionError = errorMessage
                    print("Voice WebSocket error: \(errorMessage)")
                }
                
            case .pong:
                // Pong received, connection is alive
                break
                
            default:
                break
            }
            
            // Publish message for subscribers
            messageSubject.send(message)
            
        } catch {
            print("Failed to decode WebSocket message: \(error)")
        }
    }
    
    func send(_ message: VoiceClientMessage) async throws {
        guard let webSocketTask = webSocketTask else {
            throw VoiceWebSocketError.notConnected
        }
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let string = String(data: data, encoding: .utf8)!
        
        try await webSocketTask.send(.string(string))
    }
    
    func sendAudio(_ audioData: Data) async throws {
        let base64Audio = audioData.base64EncodedString()
        let message = VoiceClientMessage(
            type: .audioAppend,
            data: ["audio": base64Audio]
        )
        try await send(message)
    }
    
    func commitAudio() async throws {
        let message = VoiceClientMessage(type: .audioCommit, data: nil)
        try await send(message)
    }
    
    func sendText(_ text: String) async throws {
        let message = VoiceClientMessage(
            type: .textSend,
            data: ["text": text]
        )
        try await send(message)
    }
    
    func interrupt() async throws {
        let message = VoiceClientMessage(type: .interrupt, data: nil)
        try await send(message)
    }
    
    func configureSession(conversationId: String, history: [ChatMessage], voice: String = "shimmer") async throws {
        let historyData = history.map { message in
            [
                "content": message.content,
                "isFromUser": message.isFromUser
            ]
        }
        
        let message = VoiceClientMessage(
            type: .sessionConfig,
            data: [
                "conversationId": conversationId,
                "history": historyData,
                "voice": voice,
                "temperature": 0.6
            ]
        )
        
        try await send(message)
    }
    
    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                do {
                    let message = VoiceClientMessage(type: .ping, data: nil)
                    try await self.send(message)
                } catch {
                    print("Ping failed: \(error)")
                }
            }
        }
    }
    
    private func handleDisconnection(error: Error? = nil) {
        isConnected = false
        isListening = false
        
        if let error = error {
            connectionError = error.localizedDescription
        }
        
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        handleDisconnection()
    }
    
    deinit {
        Task { @MainActor in
            disconnect()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension VoiceWebSocketClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket connection opened")
    }
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket connection closed: \(closeCode)")
        Task { @MainActor in
            handleDisconnection()
        }
    }
}

// MARK: - Errors

enum VoiceWebSocketError: LocalizedError {
    case invalidURL
    case notConnected
    case connectionTimeout
    case encodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .notConnected:
            return "WebSocket is not connected"
        case .connectionTimeout:
            return "Connection timed out"
        case .encodingError:
            return "Failed to encode message"
        }
    }
}