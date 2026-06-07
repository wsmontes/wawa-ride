import Foundation
import Speech
import AVFoundation

// MARK: - Voice Command Listener

/// On-device speech recognition (SFSpeechRecognizer).
/// Listens for "Ok moto" trigger phrase followed by a command.
/// Works offline (on-device recognition).

@MainActor
final class VoiceCommandListener: ObservableObject {
    static let shared = VoiceCommandListener()

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    @Published var isListening = false
    @Published var isAuthorized = false

    private let triggerPhrase = "ok moto"
    private var lastCommand: VoiceCommand?
    private var commandCallback: ((VoiceCommand) -> Void)?

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        isAuthorized = status == .authorized
        return isAuthorized
    }

    // MARK: - Listening

    func startListening(callback: @escaping (VoiceCommand) -> Void) throws {
        guard recognizer?.isAvailable == true else {
            throw VoiceCommandError.recognizerUnavailable
        }
        guard isAuthorized else {
            throw VoiceCommandError.notAuthorized
        }

        self.commandCallback = callback

        AudioSessionManager.shared.configure(for: .voiceCommand)

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        request?.taskHint = .search

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self, let result = result, result.isFinal else { return }
            let text = result.bestTranscription.formattedString.lowercased()
            self.processUtterance(text)
        }

        isListening = true
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        isListening = false
    }

    // MARK: - Processing

    private func processUtterance(_ text: String) {
        guard text.contains(triggerPhrase) else { return }

        let parts = text.components(separatedBy: triggerPhrase)
        guard parts.count > 1 else { return }

        let commandText = parts.last!.trimmingCharacters(in: .whitespacesAndNewlines)

        for command in VoiceCommand.allCases {
            if commandText.contains(command.rawValue) {
                self.lastCommand = command
                self.commandCallback?(command)
                return
            }
        }

        // Unknown command
        VoiceAssistant.shared.speak(VoiceAlert(
            text: "Não entendi. Tente: marcar radar, status do grupo, ou falar com o grupo.",
            priority: .normal, canInterrupt: true, dedupKey: "unknown_command"
        ))
    }
}

// MARK: - Voice Command Enum

enum VoiceCommand: String, CaseIterable {
    case markRadar      = "marcar radar"
    case markPothole    = "marcar buraco"
    case markPolice     = "marcar polícia"
    case markOil        = "marcar óleo"
    case markAnimal     = "marcar animal"
    case markAccident   = "marcar acidente"
    case groupStatus    = "status do grupo"
    case whereIsLeader  = "onde está o líder"
    case whereIsSweeper = "onde está o varredor"
    case startTalking   = "falar com o grupo"
    case stopTalking    = "parar de falar"
    case talkInRoom     = "falar na sala"
    case nextStop       = "próxima parada"
    case howFar         = "quanto falta"
    case needHelp       = "preciso de ajuda"
    case imOk           = "estou bem"
    case createRoom     = "criar sala"
    case listRooms      = "listar salas"
    case sendMessage    = "mandar mensagem"
    case startRecording = "gravar rota"
    case stopRecording  = "parar gravação"
}

enum VoiceCommandError: Error {
    case recognizerUnavailable
    case notAuthorized
}
