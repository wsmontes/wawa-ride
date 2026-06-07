import Foundation
import AVFoundation
import UIKit

// MARK: - Voice Service (Walkie-Talkie + Async Voice Messages)

/// Unified voice communication service.
/// - Live: PTT via MCSession streams + Opus codec
/// - Async: Record → Compress → Send via mesh → Notify → Play

@MainActor
final class VoiceService: NSObject, ObservableObject {
    static let shared = VoiceService()

    private let codec = OpusCodec()
    private let mesh = MeshService.shared

    // Live voice
    private let audioEngine = AVAudioEngine()
    private var isPTTActive = false
    private var activeRoomId: String?
    private var outputStreams: [String: OutputStream] = [:]
    private var sequenceNumber: Int = 0

    // Recording (async messages)
    private var recordingBuffer = Data()
    private var isRecording = false
    private var recordingStartTime: Date?
    private var targetRoomId: String?

    // Playback
    private var audioPlayer: AVAudioPlayer?

    @Published var isSpeaking = false
    @Published var isRecordingMessage = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isPlaying = false

    private override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleVoiceStream(_:)),
            name: .meshVoiceStreamReceived, object: nil
        )
    }

    // MARK: - Live Voice (Walkie-Talkie)

    func startPTT(roomId: String) {
        guard !isPTTActive else { return }
        isPTTActive = true
        activeRoomId = roomId

        AudioSessionManager.shared.configure(for: .walkieTalkie)

        // Open streams to all connected peers
        for peer in mesh.connectedPeers {
            do {
                let streamKey = "\(peer.displayName)-\(roomId)"
                let stream = try mesh.startVoiceStream(to: peer, roomId: roomId)
                stream.delegate = self
                stream.schedule(in: .main, forMode: .default)
                stream.open()
                outputStreams[streamKey] = stream
            } catch {
                print("🎤 Voice stream error: \(error)")
            }
        }

        // Install mic tap
        installMicTap()

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSpeaking = true
    }

    func stopPTT() {
        guard isPTTActive else { return }
        isPTTActive = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Close streams
        for (_, stream) in outputStreams {
            stream.close()
        }
        outputStreams.removeAll()

        try? AVAudioSession.sharedInstance().setActive(false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isSpeaking = false
    }

    private func installMicTap() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 320, format: format) { [weak self] buffer, _ in
            guard let self, self.isPTTActive else { return }

            // Convert to 16kHz 16-bit mono
            guard let pcmData = self.convertTo16kHz(buffer) else { return }

            // Encode with Opus
            guard let opusFrame = self.codec.encode(pcmData: pcmData) else { return }

            // Send via streams (direct peers)
            self.sendViaStreams(opusFrame)

            // Send via mesh payload (relay for indirect peers)
            self.sendViaMesh(opusFrame)
        }

        audioEngine.prepare()
        try? audioEngine.start()
    }

    private func convertTo16kHz(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        return Data(bytes: channelData[0], count: frameLength * 2)
    }

    private func sendViaStreams(_ opusFrame: Data) {
        for (_, stream) in outputStreams where stream.streamStatus == .open {
            var length = UInt16(opusFrame.count).littleEndian
            let header = Data(bytes: &length, count: 2)
            let packet = header + opusFrame
            _ = packet.withUnsafeBytes {
                stream.write($0.bindMemory(to: UInt8.self).baseAddress!,
                            maxLength: packet.count)
            }
        }
    }

    private func sendViaMesh(_ opusFrame: Data) {
        guard let roomId = activeRoomId else { return }
        sequenceNumber += 1

        let voicePayload = VoiceLivePayload(
            roomId: roomId,
            sequence: sequenceNumber,
            durationMs: 20,
            audioData: opusFrame
        )

        guard let payloadData = try? JSONEncoder().encode(voicePayload) else { return }

        let meshPayload = MeshPayload(
            type: .voiceLive,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            roomId: roomId,
            ttl: 3,
            priority: .critical,
            payload: payloadData
        )

        TransportManager.shared.send(meshPayload)
    }

    // MARK: - Live Voice Reception

    @objc private func handleVoiceStream(_ notification: Notification) {
        guard let stream = notification.userInfo?["stream"] as? InputStream,
              let streamName = notification.userInfo?["streamName"] as? String
        else { return }

        // Read Opus frames from stream, decode, play
        stream.delegate = self
        stream.schedule(in: .main, forMode: .default)
        stream.open()
    }

    func handleVoiceLivePayload(_ payload: VoiceLivePayload) {
        guard let pcmData = codec.decode(compressedData: payload.audioData) else { return }
        playPCMData(pcmData)
    }

    // MARK: - Async Voice Message Recording

    func startRecording(roomId: String) {
        guard !isRecording else { return }
        isRecording = true
        isRecordingMessage = true
        targetRoomId = roomId
        recordingBuffer = Data()
        recordingStartTime = Date()

        AudioSessionManager.shared.configure(for: .recording)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 320, format: format) { [weak self] buffer, _ in
            guard let self, self.isRecording else { return }
            guard let pcmData = self.convertTo16kHz(buffer) else { return }
            self.recordingBuffer.append(pcmData)

            // Auto-stop at 60s
            if self.recordingDuration >= 60 {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }

        audioEngine.prepare()
        try? audioEngine.start()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func stopRecording() -> VoiceMessage? {
        guard isRecording, !recordingBuffer.isEmpty else {
            isRecording = false
            isRecordingMessage = false
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            return nil
        }

        isRecording = false
        isRecordingMessage = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        let duration = recordingDuration
        let roomId = targetRoomId ?? ""

        // Compress with Opus
        guard let compressed = codec.encode(pcmData: recordingBuffer) else { return nil }

        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? ""
        let rideId = AppState.shared.currentRideId ?? ""

        let message = VoiceMessage(
            id: UUID().uuidString,
            roomId: roomId,
            rideId: rideId,
            fromRiderId: myId,
            fromRiderName: myName,
            sentAt: Date(),
            duration: duration,
            audioData: compressed,
            deliveredTo: [myId],
            playedBy: []
        )

        // Save locally
        try? LocalStore.shared.saveVoiceMessage(message)

        // Send via mesh
        sendVoiceMessage(message)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return message
    }

    var currentRecordingDuration: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Async Voice Message Sending

    func sendVoiceMessage(_ message: VoiceMessage) {
        let voicePayload = VoiceMessagePayload(
            messageId: message.id,
            roomId: message.roomId,
            fromRiderId: message.fromRiderId,
            fromRiderName: message.fromRiderName,
            sentAt: message.sentAt,
            duration: message.duration,
            audioData: message.audioData
        )

        guard let payloadData = try? JSONEncoder().encode(voicePayload) else { return }

        let meshPayload = MeshPayload(
            id: message.id,
            type: .voiceMessage,
            senderId: message.fromRiderId,
            senderName: message.fromRiderName,
            rideId: message.rideId,
            roomId: message.roomId,
            timestamp: message.sentAt,
            ttl: 10,
            priority: .high,
            payload: payloadData
        )

        TransportManager.shared.send(meshPayload)
    }

    // MARK: - Async Voice Message Reception

    func handleVoiceMessagePayload(_ payload: VoiceMessagePayload) {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""

        let message = VoiceMessage(
            id: payload.messageId,
            roomId: payload.roomId,
            rideId: AppState.shared.currentRideId ?? "",
            fromRiderId: payload.fromRiderId,
            fromRiderName: payload.fromRiderName,
            sentAt: payload.sentAt,
            duration: payload.duration,
            audioData: payload.audioData,
            deliveredTo: [myId],
            playedBy: []
        )

        // Save locally
        try? LocalStore.shared.saveVoiceMessage(message)

        // Send delivery ack
        sendAck(messageId: message.id, type: .delivered)

        // Notify
        if AppState.shared.currentRoomId != message.roomId {
            let roomName = AppState.shared.roomName(for: message.roomId)
            VoiceAssistant.shared.speak(VoiceAssistant.newMessage(from: message.fromRiderName, room: roomName))
        }

        NotificationCenter.default.post(name: .newVoiceMessage, object: message)
    }

    func sendAck(messageId: String, type: AckType) {
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        let ack = VoiceMessageAckPayload(
            messageId: messageId,
            riderId: myId,
            type: type == .delivered ? .delivered : .played
        )

        guard let payloadData = try? JSONEncoder().encode(ack) else { return }

        let meshPayload = MeshPayload(
            type: .voiceMessageAck,
            senderId: myId,
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            roomId: nil,
            ttl: 5,
            priority: .normal,
            payload: payloadData
        )

        TransportManager.shared.send(meshPayload)
    }

    // MARK: - Playback

    func playMessage(_ message: VoiceMessage) {
        guard let pcmData = codec.decode(compressedData: message.audioData) else { return }

        AudioSessionManager.shared.configure(for: .playback)

        playPCMData(pcmData)

        // Mark as played
        var updated = message
        let myId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
        if !updated.playedBy.contains(myId) {
            updated.playedBy.append(myId)
            try? LocalStore.shared.saveVoiceMessage(updated)
            sendAck(messageId: message.id, type: .played)
        }
    }

    private func playPCMData(_ pcmData: Data) {
        do {
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
            )!

            let frameCount = pcmData.count / 2
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
            buffer.frameLength = buffer.frameCapacity

            pcmData.withUnsafeBytes { rawBuffer in
                guard let channelData = buffer.int16ChannelData else { return }
                memcpy(channelData[0], rawBuffer.baseAddress, pcmData.count)
            }

            // Write to temp file for AVAudioPlayer
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("wawa_playback.wav")
            try writeWAV(buffer: buffer, to: tempURL)
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("🔊 Playback error: \(error)")
        }
    }

    private func writeWAV(buffer: AVAudioPCMBuffer, to url: URL) throws {
        // WAV header + PCM data
        let data = NSMutableData()

        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        guard let channelData = buffer.int16ChannelData else { return }
        let pcmData = Data(bytes: channelData[0], count: Int(buffer.frameLength) * 2)

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        var fileSize = UInt32(36 + pcmData.count).littleEndian
        data.append(Data(bytes: &fileSize, count: 4))
        data.append("WAVE".data(using: .ascii)!)

        // fmt subchunk
        data.append("fmt ".data(using: .ascii)!)
        var fmtSize: UInt32 = 16
        data.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat: UInt16 = 1  // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var ch = channels
        data.append(Data(bytes: &ch, count: 2))
        var sr = sampleRate
        data.append(Data(bytes: &sr, count: 4))
        var br = byteRate
        data.append(Data(bytes: &br, count: 4))
        var ba = blockAlign
        data.append(Data(bytes: &ba, count: 2))
        var bps = bitsPerSample
        data.append(Data(bytes: &bps, count: 2))

        // data subchunk
        data.append("data".data(using: .ascii)!)
        var dataSize = UInt32(pcmData.count).littleEndian
        data.append(Data(bytes: &dataSize, count: 4))
        data.append(pcmData)

        try data.write(to: url)
    }
}

// MARK: - Stream Delegate

extension VoiceService: StreamDelegate {
    func stream(_ stream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let inputStream = stream as? InputStream else { return }

            // Read [2 bytes length][N bytes opus frame]
            var lengthBuffer = [UInt8](repeating: 0, count: 2)
            let lenRead = inputStream.read(&lengthBuffer, maxLength: 2)
            guard lenRead == 2 else { return }

            let frameLength = Int(UInt16(littleEndian: Data(lengthBuffer).withUnsafeBytes { $0.load(as: UInt16.self) }))

            var frameBuffer = [UInt8](repeating: 0, count: frameLength)
            let frameRead = inputStream.read(&frameBuffer, maxLength: frameLength)
            guard frameRead == frameLength else { return }

            let opusFrame = Data(frameBuffer)

            // Decode and play
            Task { @MainActor in
                if let pcmData = self.codec.decode(compressedData: opusFrame) {
                    self.playPCMData(pcmData)
                }
            }

        case .endEncountered:
            stream.close()

        case .errorOccurred:
            print("🔊 Voice stream error")
            stream.close()

        default:
            break
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newVoiceMessage = Notification.Name("newVoiceMessage")
    static let voiceMessagePlayed = Notification.Name("voiceMessagePlayed")
}

typealias AckType = VoiceMessageAckPayload.AckType
