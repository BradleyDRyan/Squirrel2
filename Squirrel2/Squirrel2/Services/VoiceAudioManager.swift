import Foundation
import AVFoundation
import AVFAudio
import Combine

@MainActor
class VoiceAudioManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var audioLevel: Float = 0.0
    @Published var error: String?
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioPlayer: AVAudioPlayer?
    private var audioQueue = DispatchQueue(label: "voice.audio.queue")
    private var audioBuffer = Data()
    private var playbackQueue: [Data] = []
    private var isProcessingPlayback = false
    
    // Audio format: PCM16, 24kHz, mono
    private let sampleRate: Double = 24000
    private let channelCount: AVAudioChannelCount = 1
    
    // Callback for audio data
    var onAudioData: ((Data) -> Void)?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
            self.error = "Failed to setup audio: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Recording
    
    func startRecording() throws {
        guard !isRecording else { return }
        
        // Request microphone permission
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if !granted {
                        self?.error = "Microphone permission denied"
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if !granted {
                        self?.error = "Microphone permission denied"
                    }
                }
            }
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw VoiceAudioError.engineInitializationFailed
        }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            throw VoiceAudioError.inputNodeUnavailable
        }
        
        // Configure audio format for 24kHz PCM16 mono
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!
        
        // Get the input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Convert to target format if needed
            if let pcmBuffer = self.convertBuffer(buffer, to: recordingFormat) {
                // Extract audio level for visualization
                self.updateAudioLevel(from: pcmBuffer)
                
                // Convert to Data and send
                if let data = self.pcmBufferToData(pcmBuffer) {
                    self.onAudioData?(data)
                }
            }
        }
        
        // Start the audio engine
        try audioEngine.start()
        isRecording = true
        error = nil
        
        print("🎤 Recording started")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        isRecording = false
        audioLevel = 0.0
        
        print("🎤 Recording stopped")
    }
    
    // MARK: - Playback
    
    func playAudioData(_ base64String: String) {
        guard let data = Data(base64Encoded: base64String) else {
            print("Failed to decode base64 audio")
            return
        }
        
        // Add to playback queue
        Task { @MainActor [weak self] in
            self?.playbackQueue.append(data)
            self?.processPlaybackQueue()
        }
    }
    
    private func processPlaybackQueue() {
        guard !isProcessingPlayback, !playbackQueue.isEmpty else { return }
        
        isProcessingPlayback = true
        let data = playbackQueue.removeFirst()
        
        Task { @MainActor in
            await playPCMData(data)
            
            self.isProcessingPlayback = false
            self.processPlaybackQueue()
        }
    }
    
    private func playPCMData(_ data: Data) async {
        // Convert PCM16 data to WAV format for playback
        guard let wavData = createWAVData(from: data) else {
            print("Failed to create WAV data")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
            
            // Wait for playback to complete
            await withCheckedContinuation { continuation in
                // Store continuation for delegate callback
                playbackContinuation = continuation
            }
        } catch {
            print("Failed to play audio: \(error)")
            self.error = "Playback failed: \(error.localizedDescription)"
        }
    }
    
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackQueue.removeAll()
        playbackContinuation?.resume()
        playbackContinuation = nil
    }
    
    // MARK: - Audio Processing Helpers
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return nil
        }
        
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        ) else {
            return nil
        }
        
        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if let error = error {
            print("Conversion error: \(error)")
            return nil
        }
        
        return convertedBuffer
    }
    
    private func pcmBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else { return nil }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        var data = Data()
        data.reserveCapacity(frameLength * channelCount * 2) // 2 bytes per sample
        
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                withUnsafeBytes(of: sample.littleEndian) { bytes in
                    data.append(contentsOf: bytes)
                }
            }
        }
        
        return data
    }
    
    private func createWAVData(from pcmData: Data) -> Data? {
        let sampleRate: UInt32 = UInt32(self.sampleRate)
        let channelCount: UInt16 = UInt16(self.channelCount)
        let bitsPerSample: UInt16 = 16
        
        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample) / 8
        let blockAlign = channelCount * bitsPerSample / 8
        
        var wavData = Data()
        
        // RIFF header
        wavData.append(contentsOf: "RIFF".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(36 + pcmData.count).littleEndian) { Array($0) })
        wavData.append(contentsOf: "WAVE".data(using: .ascii)!)
        
        // Format chunk
        wavData.append(contentsOf: "fmt ".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: channelCount.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // Data chunk
        wavData.append(contentsOf: "data".data(using: .ascii)!)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(pcmData.count).littleEndian) { Array($0) })
        wavData.append(pcmData)
        
        return wavData
    }
    
    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else { return }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        var sum: Float = 0
        var count = 0
        
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = Float(channelData[channel][frame]) / Float(Int16.max)
                sum += abs(sample)
                count += 1
            }
        }
        
        let average = count > 0 ? sum / Float(count) : 0
        
        Task { @MainActor in
            // Smooth the audio level
            self.audioLevel = (self.audioLevel * 0.8) + (average * 0.2)
        }
    }
    
    func cleanup() {
        stopRecording()
        stopPlayback()
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceAudioManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            playbackContinuation?.resume()
            playbackContinuation = nil
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.error = "Audio decode error: \(error.localizedDescription)"
            }
            isPlaying = false
            playbackContinuation?.resume()
            playbackContinuation = nil
        }
    }
}

// MARK: - Errors

enum VoiceAudioError: LocalizedError {
    case engineInitializationFailed
    case inputNodeUnavailable
    case formatConversionFailed
    case playbackFailed
    
    var errorDescription: String? {
        switch self {
        case .engineInitializationFailed:
            return "Failed to initialize audio engine"
        case .inputNodeUnavailable:
            return "Audio input is not available"
        case .formatConversionFailed:
            return "Failed to convert audio format"
        case .playbackFailed:
            return "Failed to play audio"
        }
    }
}
