# WAWA Ride — Sistema de Áudio

## 1. Arquitetura de Áudio

```
┌─────────────────────────────────────────────────────────┐
│                    AudioManager                          │
│  (orquestrador — decide o que falar e quando)           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐ │
│  │VoiceAssistant │  │VoiceCommand   │  │VoiceChat    │ │
│  │(TTS Output)   │  │Listener       │  │Service      │ │
│  │               │  │(Speech Input) │  │(WalkieTalkie)│ │
│  │AVSpeechSynth  │  │SFSpeechRecog  │  │WebRTC +     │ │
│  │               │  │               │  │MC Stream    │ │
│  └───────┬───────┘  └───────┬───────┘  └──────┬──────┘ │
│          │                  │                  │        │
│          └──────────────────┼──────────────────┘        │
│                             │                           │
│                    ┌────────▼────────┐                  │
│                    │ AVAudioSession  │                  │
│                    │ (route/mix/     │                  │
│                    │  category)      │                  │
│                    └────────┬────────┘                  │
│                             │                           │
│              ┌──────────────┼──────────────┐            │
│              ▼              ▼              ▼            │
│         [Speaker]    [Bluetooth]    [Intercom]          │
│                      (headset)      (Cardo/Sena)        │
└─────────────────────────────────────────────────────────┘
```

---

## 2. VoiceAssistant — TTS (App → Piloto)

### 2.1 Configuração

```swift
class VoiceAssistant: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceAssistant()
    let synthesizer = AVSpeechSynthesizer()

    private var alertQueue: [VoiceAlert] = []
    private var isSpeaking = false
    private var lastSpoken: [String: Date] = [:]  // dedup por chave

    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback = só saída de áudio (TTS não precisa de microfone)
        // .duckOthers = abaixa outras fontes (música, intercom) durante fala
        // .allowBluetooth = roteia pro headset/capacete
        // .interruptSpokenAudioAndMixWithOthers = interrompe outras falas mas mantém mix
        try? session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .allowBluetooth, .interruptSpokenAudioAndMixWithOthers]
        )
    }

    func voiceForPortuguese() -> AVSpeechSynthesisVoice {
        // Melhor voz em pt-BR disponível no dispositivo
        return AVSpeechSynthesisVoice(language: "pt-BR") ??
               AVSpeechSynthesisVoice(language: "pt-PT") ??
               AVSpeechSynthesisVoice()
    }
}
```

### 2.2 Fila de alertas com prioridade

```swift
    func speak(_ alert: VoiceAlert) {
        // Dedup: não fala a mesma coisa em intervalo curto
        let key = alert.dedupKey
        if let last = lastSpoken[key], Date().timeIntervalSince(last) < alert.minInterval {
            return
        }
        lastSpoken[key] = Date()

        // Alerta crítico interrompe qualquer fala
        if alert.priority == .critical && alert.canInterrupt && isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        }

        // Insere na fila na posição correta (ordenada por prioridade)
        let insertIndex = alertQueue.firstIndex { $0.priority < alert.priority }
                         ?? alertQueue.count
        alertQueue.insert(alert, at: insertIndex)

        if !isSpeaking {
            processNext()
        }
    }

    private func processNext() {
        guard !isSpeaking, let alert = alertQueue.first else { return }

        // Pula alertas expirados
        guard alert.isStillRelevant() else {
            alertQueue.removeFirst()
            processNext()
            return
        }

        alertQueue.removeFirst()
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: alert.text)
        utterance.voice = voiceForPortuguese()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85  // Mais lento pra moto
        utterance.volume = 1.0
        utterance.pitchMultiplier = 0.9  // Tom mais grave (fácil de ouvir com vento)
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.1

        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        // Repete o alerta se repeatCount > 1
        if let alert = currentAlert, alert.repeatCount > alert.timesSpoken + 1 {
            var repeated = alert
            repeated.timesSpoken += 1
            alertQueue.insert(repeated, at: 0)
        }
        processNext()
    }
```

### 2.3 Catálogo de alertas

```swift
// MARK: - Fábrica de Alertas

extension VoiceAssistant {

    // Navegação
    static func turnApproaching(direction: String, distance: Int, severity: String) -> VoiceAlert {
        VoiceAlert(
            text: "\(severity) \(direction) em \(distance) metros",
            priority: .high,
            canInterrupt: true,
            repeatCount: 1,
            minInterval: 8,
            dedupKey: "turn_\(direction)_\(distance)"
        )
    }

    // Entrada/saída de riders
    static func riderJoined(_ name: String) -> VoiceAlert {
        VoiceAlert(
            text: "\(name) entrou no passeio",
            priority: .background,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 5,
            dedupKey: "join_\(name)"
        )
    }

    static func riderLeft(_ name: String) -> VoiceAlert {
        VoiceAlert(
            text: "\(name) saiu do passeio",
            priority: .background,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 5,
            dedupKey: "leave_\(name)"
        )
    }

    // Distância do grupo
    static func riderFallingBehind(_ name: String, distance: Int) -> VoiceAlert {
        VoiceAlert(
            text: "\(name) está \(distance) metros atrás",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 30,
            dedupKey: "behind_\(name)"
        )
    }

    static func riderFarBehind(_ name: String, distanceKm: Int) -> VoiceAlert {
        VoiceAlert(
            text: "Atenção: \(name) está a \(distanceKm) quilômetros atrás",
            priority: .high,
            canInterrupt: true,
            repeatCount: 1,
            minInterval: 60,
            dedupKey: "far_\(name)"
        )
    }

    // Desvio da rota
    static func offRoute(distance: Int) -> VoiceAlert {
        VoiceAlert(
            text: "Você está \(distance) metros fora da rota",
            priority: .high,
            canInterrupt: true,
            repeatCount: 1,
            minInterval: 15,
            dedupKey: "offroute"
        )
    }

    static func backOnRoute() -> VoiceAlert {
        VoiceAlert(
            text: "Você voltou para a rota",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 30,
            dedupKey: "onroute"
        )
    }

    // Líder parou
    static func leaderStopped() -> VoiceAlert {
        VoiceAlert(
            text: "O líder parou",
            priority: .high,
            canInterrupt: true,
            repeatCount: 1,
            minInterval: 10,
            dedupKey: "leader_stopped"
        )
    }

    // Perigos
    static func hazardNearby(type: HazardType, distance: Int) -> VoiceAlert {
        VoiceAlert(
            text: "Atenção: \(type.voiceDescription) em \(distance) metros",
            priority: .critical,
            canInterrupt: true,
            repeatCount: 2,
            minInterval: 5,
            dedupKey: "hazard_\(type.rawValue)_\(distance)"
        )
    }

    static func hazardMarked(type: HazardType) -> VoiceAlert {
        VoiceAlert(
            text: "\(type.voiceDescription) marcado. Grupo será alertado.",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 2,
            dedupKey: "marked_\(type.rawValue)"
        )
    }

    // SOS
    static func sosReceived(name: String, reason: String?) -> VoiceAlert {
        let reasonText = reason ?? "motivo não informado"
        return VoiceAlert(
            text: "Atenção! \(name) precisa de ajuda. \(reasonText).",
            priority: .critical,
            canInterrupt: true,
            repeatCount: 3,
            minInterval: 8,
            dedupKey: "sos_\(name)"
        )
    }

    // Status do grupo
    static func groupStatus(online: Int, total: Int) -> VoiceAlert {
        VoiceAlert(
            text: "\(online) de \(total) riders conectados",
            priority: .background,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 60,
            dedupKey: "status"
        )
    }

    // Varredor
    static func sweeperAllClear() -> VoiceAlert {
        VoiceAlert(
            text: "Varredor confirma: todos juntos",
            priority: .background,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 120,
            dedupKey: "sweeper_ok"
        )
    }

    // Parada
    static func stopApproaching(name: String, distanceKm: Int) -> VoiceAlert {
        VoiceAlert(
            text: "Próxima parada: \(name) em \(distanceKm) quilômetros",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 120,
            dedupKey: "stop_\(name)"
        )
    }

    // Passeio
    static func rideStarted() -> VoiceAlert {
        VoiceAlert(
            text: "Passeio criado. Aguardando riders.",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 5,
            dedupKey: "ride_start"
        )
    }

    static func rideEnded() -> VoiceAlert {
        VoiceAlert(
            text: "Passeio encerrado.",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 5,
            dedupKey: "ride_end"
        )
    }
}
```

### 2.4 HazardType — descrições em voz

```swift
extension HazardType {
    var voiceDescription: String {
        switch self {
        case .radar:    return "Radar"
        case .pothole:  return "Buraco na pista"
        case .police:   return "Polícia"
        case .oil:      return "Óleo na pista"
        case .animal:   return "Animal na pista"
        case .gravel:   return "Cascalho solto"
        case .accident: return "Acidente"
        case .other:    return "Perigo"
        }
    }
}
```

---

## 3. VoiceCommandListener — Comandos de Voz (Piloto → App)

### 3.1 Configuração

```swift
import Speech

class VoiceCommandListener: ObservableObject {
    static let shared = VoiceCommandListener()

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    @Published var isListening = false
    @Published var lastCommand: VoiceCommand?

    // Gatilho: "Ok moto"
    private let triggerPhrase = "ok moto"
    private var triggerDetected = false
    private var commandBuffer = ""

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
```

### 3.2 Comandos suportados

```swift
enum VoiceCommand: String, CaseIterable {
    // Marcação de perigos
    case markRadar      = "marcar radar"
    case markPothole    = "marcar buraco"
    case markPolice     = "marcar polícia"
    case markOil        = "marcar óleo"
    case markAnimal     = "marcar animal"
    case markAccident   = "marcar acidente"

    // Status
    case groupStatus    = "status do grupo"
    case whereIsLeader  = "onde está o líder"
    case whereIsSweeper = "onde está o varredor"

    // Comunicação
    case startTalking   = "falar com o grupo"     // Abre canal de voz
    case stopTalking    = "parar de falar"        // Fecha canal

    // Navegação
    case nextStop       = "próxima parada"
    case howFar         = "quanto falta"

    // SOS
    case needHelp       = "preciso de ajuda"
    case imOk           = "estou bem"

    var requiresTrigger: Bool {
        true  // Todos requerem "Ok moto" antes
    }
}
```

### 3.3 Loop de reconhecimento

```swift
    func startListening() throws {
        guard recognizer?.isAvailable == true else {
            throw VoiceCommandError.recognizerUnavailable
        }

        // Configura sessão de áudio pra gravação
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.allowBluetooth, .mixWithOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Cria request de reconhecimento
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        request?.taskHint = .search

        // Instala tap no microfone
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024,
                             format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Inicia task de reconhecimento
        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self, let result = result else { return }

            let text = result.bestTranscription.formattedString.lowercased()

            if result.isFinal {
                self.processUtterance(text)
            }
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

    private func processUtterance(_ text: String) {
        guard text.contains(triggerPhrase) else { return }

        // Extrai comando após "ok moto"
        let parts = text.components(separatedBy: triggerPhrase)
        guard parts.count > 1 else { return }

        let commandText = parts.last!.trimmingCharacters(in: .whitespacesAndNewlines)

        for command in VoiceCommand.allCases {
            if commandText.contains(command.rawValue) {
                DispatchQueue.main.async {
                    self.lastCommand = command
                    self.execute(command)
                }
                return
            }
        }

        // Comando não reconhecido
        VoiceAssistant.shared.speak(VoiceAlert(
            text: "Não entendi. Tente: marcar radar, status do grupo, ou falar com o grupo.",
            priority: .normal, canInterrupt: true, repeatCount: 1, minInterval: 5,
            dedupKey: "unknown_command"
        ))
    }

    private func execute(_ command: VoiceCommand) {
        switch command {
        case .markRadar:
            HazardService.shared.markHazard(.radar)
        case .markPothole:
            HazardService.shared.markHazard(.pothole)
        case .markPolice:
            HazardService.shared.markHazard(.police)
        case .markOil:
            HazardService.shared.markHazard(.oil)
        case .markAnimal:
            HazardService.shared.markHazard(.animal)
        case .markAccident:
            HazardService.shared.markHazard(.accident)
        case .groupStatus:
            let status = RideService.shared.currentGroupStatus()
            VoiceAssistant.shared.speak(.groupStatus(online: status.online, total: status.total))
        case .startTalking:
            VoiceChatService.shared.openChannel()
        case .stopTalking:
            VoiceChatService.shared.closeChannel()
        case .needHelp:
            SOSService.shared.triggerSOS()
        case .imOk:
            SOSService.shared.cancelSOS()
        case .nextStop, .howFar, .whereIsLeader, .whereIsSweeper:
            // Implementação futura (MVP pode não ter)
            break
        }
    }
}
```

### 3.4 Estratégia de reconhecimento contínuo

```
MVP: Push-to-listen (não escuta o tempo todo)

Opção A (MVP): Botão "🎤 Comando" na tela do mapa
  - Piloto aperta → app escuta por 5 segundos → processa
  - Menos gasto de bateria
  - Menos falsos positivos

Opção B (desejável): Escuta contínua com gatilho "Ok moto"
  - App mantém SFSpeechRecognizer rodando
  - Só processa quando detecta "Ok moto"
  - Gasta mais bateria (CPU + microfone)
  - Pode ter falsos positivos com vento/escapamento

Recomendação: MVP começa com Opção A (mais simples, mais confiável)
             Evolui pra Opção B quando testarmos o reconhecimento real na moto
```

---

## 4. VoiceChatService — Walkie-Talkie (Piloto ↔ Pilotos)

### 4.1 Arquitetura de dois caminhos

```
TEM 4G?
  ├─ SIM → WebRTC (GoogleWebRTC)
  │         - Codec Opus (32 kbps, otimizado pra voz)
  │         - ICE/STUN/TURN pra furar NAT
  │         - Servidor de sinalização: Firebase Firestore
  │
  └─ NÃO → MCSession Stream (MultipeerConnectivity)
            - Áudio comprimido (Opus em software)
            - Stream direto entre peers conectados
            - Latência menor (sem round-trip ao servidor)
            - Mas só alcança peers diretamente conectados (TTL 3 pra repassar)
```

### 4.2 WebRTC (caminho com 4G)

```swift
import WebRTC

class VoiceChatService: NSObject, RTCPeerConnectionDelegate {
    static let shared = VoiceChatService()

    private let factory = RTCPeerConnectionFactory()
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var localAudioTrack: RTCAudioTrack?
    private var localAudioSource: RTCAudioSource?

    // Configuração ICE
    private let iceServers = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
        // TURN server público do Google (MVP).
        // Futuro: servidor TURN próprio pra produção.
        RTCIceServer(urlStrings: ["turn:freeturn.net:3478"],
                     username: "free", credential: "free")
    ]

    func setupLocalAudio() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        localAudioSource = factory.audioSource(with: constraints)
        localAudioTrack = factory.audioTrack(with: localAudioSource!, trackId: "wawa-audio")
    }

    func createConnection(for riderId: String) -> RTCPeerConnection {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.continualGatheringPolicy = .gatherContinually
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true"
            ],
            optionalConstraints: nil
        )

        let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        pc.add(localAudioTrack!, streamIds: ["wawa-stream"])
        peerConnections[riderId] = pc
        return pc
    }

    // Sinalização via Firestore
    func sendOffer(to riderId: String) {
        let pc = peerConnections[riderId] ?? createConnection(for: riderId)

        pc.offer(for: RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"],
                                           optionalConstraints: nil)) { sdp, error in
            guard let sdp else { return }
            pc.setLocalDescription(sdp) { _ in
                // Envia SDP via Firestore
                SignalingService.shared.send(sdp: sdp, to: riderId, type: .offer)
            }
        }
    }

    // Áudio remoto — roteado pro alto-falante/headset
    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didAdd stream: RTCMediaStream) {
        if let audioTrack = stream.audioTracks.first {
            // O áudio toca automaticamente (WebRTC gerencia a saída)
            print("🎤 Recebendo áudio de \(stream.streamId)")
        }
    }

    // Push-to-talk: ativa/desativa track de áudio local
    func startSpeaking() {
        localAudioTrack?.isEnabled = true
        // Vibração tátil pra confirmar
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func stopSpeaking() {
        localAudioTrack?.isEnabled = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
```

### 4.3 Sinalização via Firestore

```swift
// Estrutura no Firestore pra sinalização WebRTC
// rides/{rideId}/signaling/{riderId}/

struct SignalingMessage: Codable {
    let from: String            // riderId
    let to: String              // riderId (ou "*" pra broadcast)
    let type: SignalingType     // .offer, .answer, .iceCandidate
    let sdp: String?            // SDP (offer/answer)
    let candidate: String?      // ICE candidate
    let sdpMid: String?         // ICE candidate mid
    let sdpMLineIndex: Int32?   // ICE candidate mline index
    let timestamp: Date
}

enum SignalingType: String, Codable {
    case offer, answer, iceCandidate
}
```

### 4.4 Modo simplificado (MVP)

No MVP, o voice chat pode ser simplificado:

```
EM VEZ DE WebRTC complexo (N conexões peer-to-peer, cada rider ↔ cada rider):

MVP: Áudio em broadcast via Firestore
  1. Rider aperta PTT
  2. App grava áudio (máx 15 segundos)
  3. Comprime com Opus → ~40KB pra 15s
  4. Upload pro Firestore Storage ou como documento
  5. Outros riders recebem via listener → tocam automaticamente

  Isso é um "voice message" estilo WhatsApp, não walkie-talkie em tempo real.
  Latência: 1-3 segundos. Aceitável pra MVP.

MVP+: Walkie-talkie em tempo real via MCSession stream (sem 4G)
  - Quando riders estão no mesh P2P, voz é transmitida em streaming
  - Latência < 200ms
  - Funciona mesmo sem 4G
  - Mas só alcança peers diretamente conectados
```

---

## 5. Gerenciamento da Sessão de Áudio

### 5.1 Cenários e configurações

```swift
class AudioSessionManager {
    static let shared = AudioSessionManager()

    enum Scenario {
        case ttsOnly             // Só TTS, sem microfone
        case ttsAndVoiceCommands // TTS + comandos de voz
        case walkieTalkie        // Walkie-talkie ativo
        case intercomDetected    // Cardo/Sena conectado
    }

    var currentScenario: Scenario = .ttsOnly

    func configure(for scenario: Scenario) {
        let session = AVAudioSession.sharedInstance()

        switch scenario {
        case .ttsOnly:
            // NÃO bloqueia intercom, NÃO pega microfone
            try? session.setCategory(.playback, mode: .spokenAudio,
                                     options: [.duckOthers, .allowBluetooth])

        case .ttsAndVoiceCommands:
            // Precisa de microfone pra comandos de voz
            try? session.setCategory(.playAndRecord, mode: .default,
                                     options: [.allowBluetooth, .mixWithOthers,
                                               .defaultToSpeaker])

        case .walkieTalkie:
            // Walkie-talkie ativo — microfone + saída
            try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                     options: [.allowBluetooth,
                                               .defaultToSpeaker])

        case .intercomDetected:
            // Cardo/Sena presente — app NÃO compete
            // Só TTS, sem microfone, ducking
            try? session.setCategory(.playback, mode: .spokenAudio,
                                     options: [.duckOthers, .allowBluetooth])
        }

        try? session.setActive(true)
        currentScenario = scenario
    }

    func detectIntercom() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        return route.outputs.contains { output in
            output.portType == .bluetoothHFP &&
            ["cardo", "sena", "intercom", "packtalk",
             "freecom", "spirit", "bold"].contains {
                output.portName.lowercased().contains($0)
            }
        }
    }
}
```

### 5.2 Prioridade entre fontes de áudio

```
Quando duas coisas querem falar ao mesmo tempo:

1. SOS / Alerta crítico          → Interrompe TUDO
2. Alerta de perigo próximo       → Interrompe TTS normal e walkie
3. Walkie-talkie (áudio chegando) → Abaixa TTS normal (ducking)
4. TTS normal (status, posição)  → Fala quando canal livre
5. Walkie-talkie (PTT ativado)   → Captura microfone
6. Comando de voz                → Captura microfone
```

---

## 6. Codec de Áudio — Opus

Por que Opus:
- Otimizado pra voz (não música)
- Funciona de 6 kbps até 510 kbps
- Baixíssima latência (5ms de frame)
- Resiste a perda de pacotes (PLC — Packet Loss Concealment)
- Royalty-free, open source

```swift
// Configuração típica pra walkie-talkie:
// Sample rate: 16000 Hz (voz, suficiente)
// Bitrate: 32000 bps (qualidade de chamada telefônica)
// Frame size: 20ms
// Complexidade: 5 (baixa = menos CPU = menos bateria)

// No iOS, usar Opus via AudioUnit ou biblioteca C (libopus)
// GoogleWebRTC já inclui Opus internamente
```

---

## 7. Testes de áudio (a fazer)

```
Cenários de teste:
  1. TTS com vento a 80 km/h — dá pra ouvir?
  2. TTS com capacete fechado + protetor auricular
  3. Comandos de voz com vento + escapamento — reconhece?
  4. Comandos de voz com sotaque regional — testar com vários riders
  5. Walkie-talkie 4G: latência e qualidade
  6. Walkie-talkie mesh P2P: latência entre motos a 50m
  7. Coexistência com intercom Cardo/Sena (se disponível)
  8. Bateria: consumo com microfone + TTS contínuo por 4h
```
