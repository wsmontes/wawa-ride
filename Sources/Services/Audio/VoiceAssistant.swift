import Foundation
import AVFoundation
import UIKit

// MARK: - Voice Assistant (TTS)

/// App-to-rider speech. Manages a priority queue of VoiceAlerts,
/// speaks them via AVSpeechSynthesizer, and handles interruptions,
/// ducking, and Bluetooth/helmet audio routing.

@MainActor
final class VoiceAssistant: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceAssistant()

    private let synthesizer = AVSpeechSynthesizer()
    private var alertQueue: [VoiceAlert] = []
    private var isSpeaking = false
    private var lastSpoken: [String: Date] = [:]
    private var currentAlert: VoiceAlert?

    @Published var isMuted = false

    private override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
    }

    // MARK: - Audio Session

    func setupAudioSession() {
        guard !AudioSessionManager.shared.hasIntercom() else {
            // Intercom detected — configure for coexistence
            AudioSessionManager.shared.configure(for: .ttsOnly)
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .allowBluetooth, .interruptSpokenAudioAndMixWithOthers]
        )
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Speak

    func speak(_ alert: VoiceAlert) {
        guard !isMuted else { return }

        // Dedup: don't repeat same alert within minInterval
        if let last = lastSpoken[alert.dedupKey],
           Date().timeIntervalSince(last) < alert.minInterval {
            return
        }
        lastSpoken[alert.dedupKey] = Date()

        // Critical alerts interrupt current speech
        if alert.priority == .critical && alert.canInterrupt && isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        }

        // Insert sorted by priority (highest first)
        let insertIndex = alertQueue.firstIndex { $0.priority < alert.priority } ?? alertQueue.count
        alertQueue.insert(alert, at: insertIndex)

        if !isSpeaking {
            processNext()
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        alertQueue.removeAll()
        isSpeaking = false
    }

    // MARK: - Queue Processing

    private func processNext() {
        guard !isSpeaking, !alertQueue.isEmpty else { return }

        // Skip expired alerts
        while let alert = alertQueue.first, !alert.isStillRelevant() {
            alertQueue.removeFirst()
        }
        guard let alert = alertQueue.first else { return }

        alertQueue.removeFirst()
        currentAlert = alert
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: alert.text)
        utterance.voice = Self.portugueseVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.volume = 1.0
        utterance.pitchMultiplier = 0.9  // Deeper tone — easier to hear with wind
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.1

        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false

        // Repeat if needed
        if let alert = currentAlert, alert.timesSpoken + 1 < alert.repeatCount {
            var repeated = alert
            repeated.timesSpoken += 1
            repeated.spokenAt = Date()
            alertQueue.insert(repeated, at: 0)
        }

        currentAlert = nil
        processNext()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        currentAlert = nil
        processNext()
    }

    // MARK: - Helpers

    static func portugueseVoice() -> AVSpeechSynthesisVoice {
        AVSpeechSynthesisVoice(language: "pt-BR")
            ?? AVSpeechSynthesisVoice(language: "pt-PT")
            ?? AVSpeechSynthesisVoice()
    }
}

// MARK: - Audio Session Manager

final class AudioSessionManager {
    static let shared = AudioSessionManager()

    enum Scenario {
        case ttsOnly
        case voiceCommand
        case walkieTalkie
        case recording
        case playback
    }

    func configure(for scenario: Scenario) {
        let session = AVAudioSession.sharedInstance()

        switch scenario {
        case .ttsOnly:
            try? session.setCategory(.playback, mode: .spokenAudio,
                                     options: [.duckOthers, .allowBluetooth])

        case .voiceCommand:
            try? session.setCategory(.playAndRecord, mode: .default,
                                     options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker])

        case .walkieTalkie:
            try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                     options: [.allowBluetooth, .defaultToSpeaker])

        case .recording:
            try? session.setCategory(.record, mode: .default,
                                     options: [.allowBluetooth])

        case .playback:
            try? session.setCategory(.playback, mode: .default,
                                     options: [.allowBluetooth])
        }

        try? session.setActive(true)
    }

    func hasIntercom() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        return route.outputs.contains { output in
            output.portType == .bluetoothHFP &&
            ["cardo", "sena", "intercom", "packtalk", "freecom", "spirit", "bold"]
                .contains { output.portName.lowercased().contains($0) }
        }
    }
}

// MARK: - Voice Alert Catalog (Factory)

extension VoiceAssistant {

    // MARK: Ride Events

    static func rideStarted() -> VoiceAlert {
        VoiceAlert(text: "Passeio criado. Aguardando riders.", priority: .normal,
                   dedupKey: "ride_start")
    }

    static func rideEnded() -> VoiceAlert {
        VoiceAlert(text: "Passeio encerrado.", priority: .normal,
                   dedupKey: "ride_end")
    }

    static func routeImported(name: String, waypoints: Int) -> VoiceAlert {
        VoiceAlert(text: "Rota \(name) importada com \(waypoints) pontos.",
                   priority: .normal, dedupKey: "route_imported")
    }

    static func riderJoined(_ name: String) -> VoiceAlert {
        VoiceAlert(text: "\(name) entrou no passeio.", priority: .background,
                   dedupKey: "join_\(name)")
    }

    static func riderLeft(_ name: String) -> VoiceAlert {
        VoiceAlert(text: "\(name) saiu do passeio.", priority: .background,
                   dedupKey: "leave_\(name)")
    }

    // MARK: Position & Distance

    static func riderBehind(_ name: String, distance: Int) -> VoiceAlert {
        VoiceAlert(text: "\(name) está \(distance) metros atrás.", priority: .normal,
                   minInterval: 30, dedupKey: "behind_\(name)")
    }

    static func riderFarBehind(_ name: String, km: Int) -> VoiceAlert {
        VoiceAlert(text: "Atenção: \(name) está a \(km) quilômetros atrás.",
                   priority: .high, canInterrupt: true, minInterval: 60,
                   dedupKey: "far_\(name)")
    }

    // MARK: Route

    static func offRoute(_ distance: Int) -> VoiceAlert {
        VoiceAlert(text: "Você está \(distance) metros fora da rota.",
                   priority: .high, canInterrupt: true, minInterval: 15,
                   dedupKey: "offroute")
    }

    static func backOnRoute() -> VoiceAlert {
        VoiceAlert(text: "Você voltou para a rota.", priority: .normal,
                   minInterval: 30, dedupKey: "onroute")
    }

    static func turnApproaching(direction: String, distance: Int, severity: String) -> VoiceAlert {
        VoiceAlert(text: "\(severity) \(direction) em \(distance) metros.",
                   priority: .high, canInterrupt: true, minInterval: 8,
                   dedupKey: "turn_\(direction)_\(distance)")
    }

    // MARK: Hazards

    static func hazardNearby(type: HazardType, distance: Int) -> VoiceAlert {
        VoiceAlert(
            text: "Atenção: \(type.voiceDescription) em \(distance) metros.",
            priority: .critical, canInterrupt: true, repeatCount: 2,
            minInterval: 5, dedupKey: "hazard_\(type.rawValue)_\(distance)"
        )
    }

    static func hazardMarked(type: HazardType) -> VoiceAlert {
        VoiceAlert(
            text: "\(type.voiceDescription) marcado. Grupo alertado.",
            priority: .normal, minInterval: 2,
            dedupKey: "marked_\(type.rawValue)"
        )
    }

    // MARK: SOS

    static func sosReceived(name: String, reason: String?) -> VoiceAlert {
        let reasonText = reason ?? "motivo não informado"
        return VoiceAlert(
            text: "Atenção! \(name) precisa de ajuda. \(reasonText).",
            priority: .critical, canInterrupt: true, repeatCount: 3,
            minInterval: 8, dedupKey: "sos_\(name)"
        )
    }

    // MARK: Connectivity

    static func offline(duration: Int) -> VoiceAlert {
        VoiceAlert(
            text: duration == 1 ? "Sem conexão há 1 minuto." : "Sem conexão há \(duration) minutos.",
            priority: .normal, minInterval: 120, dedupKey: "offline_\(duration)"
        )
    }

    static func reconnected(pendingMessages: Int) -> VoiceAlert {
        VoiceAlert(
            text: pendingMessages > 0
                ? "Conexão restaurada. \(pendingMessages) mensagens pendentes."
                : "Conexão restaurada.",
            priority: .normal, minInterval: 30, dedupKey: "reconnected"
        )
    }

    // MARK: Rooms

    static func roomCreated(name: String, by: String) -> VoiceAlert {
        VoiceAlert(text: "Sala \(name) criada por \(by).", priority: .background,
                   dedupKey: "room_created_\(name)")
    }

    static func newMessage(from name: String, room: String) -> VoiceAlert {
        VoiceAlert(text: "Nova mensagem de \(name) na sala \(room).",
                   priority: .normal, minInterval: 10,
                   dedupKey: "msg_\(name)_\(room)")
    }

    // MARK: Status

    static func groupStatus(online: Int, total: Int) -> VoiceAlert {
        VoiceAlert(text: "\(online) de \(total) riders conectados.",
                   priority: .background, minInterval: 60, dedupKey: "status")
    }

    static func leaderStopped() -> VoiceAlert {
        VoiceAlert(text: "O líder parou.", priority: .high, canInterrupt: true,
                   minInterval: 10, dedupKey: "leader_stopped")
    }

    static func sweeperAllClear() -> VoiceAlert {
        VoiceAlert(text: "Varredor: todos juntos.", priority: .background,
                   minInterval: 120, dedupKey: "sweeper_ok")
    }

    static func stopApproaching(name: String, km: Int) -> VoiceAlert {
        VoiceAlert(text: "Próxima parada: \(name) em \(km) quilômetros.",
                   priority: .normal, minInterval: 120, dedupKey: "stop_\(name)")
    }
}

extension HazardType {
    var voiceDescription: String {
        switch self {
        case .radar: return "Radar"
        case .pothole: return "Buraco na pista"
        case .police: return "Polícia"
        case .oil: return "Óleo na pista"
        case .animal: return "Animal na pista"
        case .gravel: return "Cascalho solto"
        case .accident: return "Acidente"
        case .other: return "Perigo"
        }
    }
}
