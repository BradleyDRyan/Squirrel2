//
//  VoiceWebRTCClient.swift
//  Squirrel2
//
//  WebRTC client for OpenAI Realtime API voice communication
//

import Foundation
import AVFoundation
import Combine
// Note: Add WebRTC package via SPM: https://github.com/stasel/WebRTC
import WebRTC

@MainActor
class VoiceWebRTCClient: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var error: String?
    
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?
    private var factory: RTCPeerConnectionFactory?
    
    private let messageSubject = PassthroughSubject<[String: Any], Never>()
    
    var messagePublisher: AnyPublisher<[String: Any], Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    override init() {
        super.init()
        setupWebRTC()
    }
    
    private func setupWebRTC() {
        // Initialize WebRTC
        RTCInitializeSSL()
        
        // Create peer connection factory
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }
    
    func connect(token: String, sessionId: String) async throws {
        isConnecting = true
        error = nil
        
        do {
            // Configure ICE servers
            let config = RTCConfiguration()
            config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
            config.sdpSemantics = .unifiedPlan
            config.continualGatheringPolicy = .gatherContinually
            
            // Create peer connection
            guard let factory = factory else {
                throw VoiceWebRTCError.factoryNotInitialized
            }
            
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
            )
            
            peerConnection = factory.peerConnection(
                with: config,
                constraints: constraints,
                delegate: self
            )
            
            guard let pc = peerConnection else {
                throw VoiceWebRTCError.peerConnectionFailed
            }
            
            // Create data channel for events
            let dataChannelConfig = RTCDataChannelConfiguration()
            dataChannelConfig.isOrdered = true
            dataChannel = pc.dataChannel(
                forLabel: "oai-events",
                configuration: dataChannelConfig
            )
            dataChannel?.delegate = self
            
            // Add local audio track
            let audioConstraints = RTCMediaConstraints(
                mandatoryConstraints: ["googEchoCancellation": "true",
                                      "googAutoGainControl": "true",
                                      "googNoiseSuppression": "true"],
                optionalConstraints: nil
            )
            
            let audioSource = factory.audioSource(with: audioConstraints)
            localAudioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
            
            if let audioTrack = localAudioTrack {
                pc.add(audioTrack, streamIds: ["stream0"])
            }
            
            // Create offer
            let offerConstraints = RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "true"],
                optionalConstraints: nil
            )
            
            let offer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
                pc.offer(for: offerConstraints) { sdp, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let sdp = sdp {
                        continuation.resume(returning: sdp)
                    } else {
                        continuation.resume(throwing: VoiceWebRTCError.offerCreationFailed)
                    }
                }
            }
            
            // Set local description
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pc.setLocalDescription(offer) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            
            // Send offer to OpenAI using latest API
            // The model is already configured when we get the ephemeral token
            guard let url = URL(string: "https://api.openai.com/v1/realtime") else {
                throw VoiceWebRTCError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
            request.httpBody = offer.sdp.data(using: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VoiceWebRTCError.sdpExchangeFailed
            }
            
            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                print("SDP exchange failed with status: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("Error: \(errorText)")
                }
                throw VoiceWebRTCError.sdpExchangeFailed
            }
            
            guard let answerSdp = String(data: data, encoding: .utf8) else {
                throw VoiceWebRTCError.invalidAnswer
            }
            
            // Set remote description
            let answer = RTCSessionDescription(type: .answer, sdp: answerSdp)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pc.setRemoteDescription(answer) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            
            isConnecting = false
            isConnected = true
            
        } catch {
            isConnecting = false
            self.error = error.localizedDescription
            throw error
        }
    }
    
    func sendMessage(_ message: [String: Any]) {
        guard let dataChannel = dataChannel,
              dataChannel.readyState == .open else {
            print("Data channel not ready")
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let buffer = RTCDataBuffer(data: data, isBinary: false)
            dataChannel.sendData(buffer)
        } catch {
            print("Failed to send message: \(error)")
        }
    }
    
    func disconnect() {
        dataChannel?.close()
        dataChannel = nil
        
        localAudioTrack?.isEnabled = false
        localAudioTrack = nil
        
        peerConnection?.close()
        peerConnection = nil
        
        isConnected = false
        error = nil
    }
    
    deinit {
        Task { @MainActor in
            disconnect()
        }
        RTCCleanupSSL()
    }
}

// MARK: - RTCPeerConnectionDelegate

extension VoiceWebRTCClient: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling state: \(stateChanged)")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("Stream added: \(stream.streamId)")
        
        // Handle remote audio
        if let audioTrack = stream.audioTracks.first {
            audioTrack.isEnabled = true
        }
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("Stream removed: \(stream.streamId)")
    }
    
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Negotiation needed")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("ICE connection state: \(newState)")
        
        Task { @MainActor in
            switch newState {
            case .connected, .completed:
                self.isConnected = true
            case .disconnected, .failed, .closed:
                self.isConnected = false
            default:
                break
            }
        }
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE gathering state: \(newState)")
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // ICE candidates are handled automatically with trickle ICE
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Handle removed candidates if needed
    }
    
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened: \(dataChannel.label)")
    }
}

// MARK: - RTCDataChannelDelegate

extension VoiceWebRTCClient: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("Data channel state: \(dataChannel.readyState)")
        
        Task { @MainActor in
            if dataChannel.readyState == .open {
                print("Data channel ready for messages")
            }
        }
    }
    
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let data = buffer.data as Data? else { return }
        
        // Handle both text and binary data
        if let jsonString = String(data: data, encoding: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            Task { @MainActor in
                self.messageSubject.send(json)
            }
        }
    }
}

// MARK: - Errors

enum VoiceWebRTCError: LocalizedError {
    case factoryNotInitialized
    case peerConnectionFailed
    case offerCreationFailed
    case invalidURL
    case sdpExchangeFailed
    case invalidAnswer
    
    var errorDescription: String? {
        switch self {
        case .factoryNotInitialized:
            return "WebRTC factory not initialized"
        case .peerConnectionFailed:
            return "Failed to create peer connection"
        case .offerCreationFailed:
            return "Failed to create WebRTC offer"
        case .invalidURL:
            return "Invalid OpenAI API URL"
        case .sdpExchangeFailed:
            return "Failed to exchange SDP with server"
        case .invalidAnswer:
            return "Invalid SDP answer from server"
        }
    }
}
