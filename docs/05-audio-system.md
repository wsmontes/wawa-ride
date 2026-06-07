# WAWA Ride — Sistema de Áudio (v2)

> **Zero servidor. Áudio sempre P2P: MCSession stream (voz ao vivo) ou MeshPayload (assíncrono).**
> Codec Opus em software. Sem WebRTC, sem TURN/STUN.

---

## 1. Arquitetura de Áudio

```
┌─────────────────────────────────────────────────────────┐
│                    AudioManager                          │
│  (orquestrador — decide o que falar, como e quando)     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │VoiceAssistant│  │VoiceCommand  │  │VoiceService  │  │
│  │(TTS Output)  │  │Listener      │  │(WalkieTalkie │  │
│  │              │  │(Speech Input)│  │ + Async Msg) │  │
│  │AVSpeechSynth │  │SFSpeechRecog │  │Opus Codec +  │  │
│  │              │  │              │  │MC Stream +   │  │
│  │              │  │              │  │Mesh Payload  │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                  │          │
│         └─────────────────┼──────────────────┘          │
│                           │                             │
│                  ┌────────▼────────┐                    │
│                  │ AVAudioSession  │                    │
│                  └────────┬────────┘                    │
│                           │                             │
│            ┌──────────────┼──────────────┐              │
│            ▼              ▼              ▼              │
│       [Speaker]    [Bluetooth]    [Intercom]            │
│                    (headset)      (Cardo/Sena)          │
└─────────────────────────────────────────────────────────┘
```

---

## 2. VoiceAssistant — TTS (App → Piloto)

Mantido da v1. Ver `05-audio-system.md` v1 para detalhes.

**Catálogo expandido (v2):**

```swift
// Novos alertas pra salas e mensagens
extension VoiceAssistant {

    static func newMessage(name: String, room: String) -> VoiceAlert {
        VoiceAlert(
            text: "Nova mensagem de \(name) na sala \(room)",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 10,
            dedupKey: "msg_\(name)_\(room)"
        )
    }

    static func roomCreated(name: String, by: String) -> VoiceAlert {
        VoiceAlert(
            text: "Sala \(name) criada por \(by)",
            priority: .background,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 5,
            dedupKey: "room_created_\(name)"
        )
    }

    static func reconnected(pendingMessages: Int) -> VoiceAlert {
        VoiceAlert(
            text: pendingMessages > 0
                ? "Conexão restaurada. \(pendingMessages) mensagens pendentes."
                : "Conexão restaurada.",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 30,
            dedupKey: "reconnected"
        )
    }

    static func offline(duration: Int) -> VoiceAlert {
        // duration em minutos
        VoiceAlert(
            text: duration == 1
                ? "Sem conexão há 1 minuto"
                : "Sem conexão há \(duration) minutos",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 120,  // Não enche o saco
            dedupKey: "offline_\(duration)"
        )
    }

    static func routeImported(name: String, waypoints: Int) -> VoiceAlert {
        VoiceAlert(
            text: "Rota \(name) importada com \(waypoints) pontos",
            priority: .normal,
            canInterrupt: false,
            repeatCount: 1,
            minInterval: 5,
            dedupKey: "route_imported"
        )
    }
}
```

---

## 3. VoiceCommandListener — Comandos de Voz

Mantido da v1. Comandos expandidos:

```swift
enum VoiceCommand: String, CaseIterable {
    // Perigos (mantidos da v1)
    case markRadar, markPothole, markPolice, markOil, markAnimal, markAccident

    // Salas (novos)
    case createRoom      = "criar sala"
    case listRooms       = "listar salas"
    case switchRoom      = "trocar para sala"     // + nome da sala

    // Mensagens (novos)
    case sendMessage     = "mandar mensagem"      // + "pra [sala]"
    case sendMessageTo   = "mandar mensagem para" // + nome do rider
    case playMessages    = "tocar mensagens"

    // Voz ao vivo (mantidos + expandidos)
    case startTalking    = "falar com o grupo"
    case stopTalking     = "parar de falar"
    case talkInRoom      = "falar na sala"         // + nome da sala

    // Status (mantidos)
    case groupStatus, whereIsLeader, whereIsSweeper, nextStop, howFar

    // SOS (mantidos)
    case needHelp, imOk

    // Rota (novos)
    case startRecording  = "gravar rota"
    case stopRecording   = "parar gravação"
    case saveRoute       = "salvar rota"
}
```

---

## 4. VoiceService — Walkie-Talkie + Áudio Assíncrono

### 4.1 Visão geral

```
VOICE SERVICE — Dois modos de comunicação por voz:

MODO 1: Voz ao vivo (Walkie-Talkie)
  - PTT (push-to-talk): aperta pra falar, solta pra ouvir
  - Transporte: MCSession stream direto (P2P)
  - Codec: Opus 32kbps, chunks de 20ms
  - Latência: < 200ms (P2P direto), < 2s (relay mesh)
  - Uso: conversa em tempo real

MODO 2: Mensagem de voz assíncrona
  - Grava → comprime → envia → notifica → toca
  - Transporte: MeshPayload (store-and-forward)
  - Codec: Opus 32kbps, arquivo completo
  - Latência: < 1s (P2P direto), minutos/horas (offline)
  - Uso: deixar recado, comunicação não-urgente
```

### 4.2 Codec Opus (software)

```swift
// Libopus compilada estaticamente no app
// Configuração:

struct OpusConfig {
    static let sampleRate: Int32 = 16000      // 16kHz (voz)
    static let channels: Int32 = 1             // Mono
    static let bitrate: Int32 = 32000          // 32kbps
    static let frameSize: Int32 = 320          // 20ms @ 16kHz = 320 samples
    static let maxPacketSize = 4000            // ~4KB max por pacote

    // Compressão típica:
    // 1s de áudio PCM 16kHz 16-bit = 32KB
    // 1s de áudio Opus 32kbps = 4KB
    // Compressão: ~8x (excelente pra voz)
}

class OpusCodec {
    private var encoder: OpaquePointer?
    private var decoder: OpaquePointer?

    func setup() {
        var err: Int32 = 0
        encoder = opus_encoder_create(
            OpusConfig.sampleRate,
            OpusConfig.channels,
            OPUS_APPLICATION_VOIP,  // Otimizado pra voz
            &err
        )
        opus_encoder_ctl(encoder, OPUS_SET_BITRATE(OpusConfig.bitrate))
        opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(5))  // Baixa complexidade = menos CPU
        opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE))

        decoder = opus_decoder_create(OpusConfig.sampleRate, OpusConfig.channels, &err)
    }

    func encode(_ pcm: Data) -> Data? {
        // PCM 16-bit → Opus frame
        var opusData = Data(count: OpusConfig.maxPacketSize)
        let len = opusData.withUnsafeMutableBytes { dst in
            pcm.withUnsafeBytes { src in
                opus_encode(encoder,
                    src.bindMemory(to: opus_int16.self).baseAddress,
                    OpusConfig.frameSize,
                    dst.bindMemory(to: UInt8.self).baseAddress,
                    opus_int32(OpusConfig.maxPacketSize))
            }
        }
        guard len > 0 else { return nil }
        return opusData.prefix(Int(len))
    }

    func decode(_ opus: Data) -> Data? {
        // Opus frame → PCM 16-bit
        var pcm = Data(count: OpusConfig.frameSize * 2)  // 16-bit = 2 bytes/sample
        let len = pcm.withUnsafeMutableBytes { dst in
            opus.withUnsafeBytes { src in
                opus_decode(decoder,
                    src.bindMemory(to: UInt8.self).baseAddress,
                    opus_int32(opus.count),
                    dst.bindMemory(to: opus_int16.self).baseAddress,
                    OpusConfig.frameSize,
                    0)  // 0 = no FEC
            }
        }
        guard len > 0 else { return nil }
        return pcm.prefix(Int(len) * 2)
    }
}
```

### 4.3 Voz ao vivo (Walkie-Talkie via MCSession Stream)

```swift
class VoiceChatService: NSObject {
    static let shared = VoiceChatService()
    private let codec = OpusCodec()

    // Streams ativos: key = "peerId-roomId"
    private var outputStreams: [String: OutputStream] = [:]

    // Microfone
    private let audioEngine = AVAudioEngine()
    private var isPTTActive = false
    private var activeRoomId: String = "general"

    func startPTT(roomId: String) {
        activeRoomId = roomId
        isPTTActive = true

        // 1. Configura sessão de áudio pra gravação
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                 options: [.allowBluetooth, .defaultToSpeaker])
        try? session.setActive(true)

        // 2. Abre streams pra todos os peers conectados
        for peer in MeshService.shared.session.connectedPeers {
            let streamKey = "\(peer.displayName)-\(roomId)"
            let stream = try! MeshService.shared.session.startStream(
                withName: "wawa-voice-\(roomId)", toPeer: peer
            )
            stream.delegate = self
            stream.schedule(in: .main, forMode: .default)
            stream.open()
            outputStreams[streamKey] = stream
        }

        // 3. Instala tap no microfone
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)  // 44.1kHz ou 48kHz
        // Converter pra 16kHz mono
        let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        // Precisa de converter se o formato do mic for diferente
        let converter = AVAudioConverter(from: format, to: desiredFormat)

        inputNode.installTap(onBus: 0, bufferSize: 320, format: format) { [weak self] buffer, _ in
            guard let self, self.isPTTActive else { return }

            // Converte pra 16kHz 16-bit mono
            guard let converted = self.convert(buffer, with: converter, to: desiredFormat) else { return }

            // Opus encode
            guard let opusFrame = self.codec.encode(converted) else { return }

            // Envia via stream (peers diretos)
            self.broadcastOpusFrame(opusFrame, roomId: roomId)

            // Envia via mesh payload (peers indiretos, com relay)
            self.broadcastOpusViaMesh(opusFrame, roomId: roomId)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        // Feedback tátil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func stopPTT() {
        isPTTActive = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Fecha streams
        for (_, stream) in outputStreams {
            stream.close()
        }
        outputStreams.removeAll()

        // Restaura sessão de áudio
        try? AVAudioSession.sharedInstance().setActive(false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func broadcastOpusFrame(_ frame: Data, roomId: String) {
        for (key, stream) in outputStreams where key.hasSuffix("-\(roomId)") {
            var length = UInt16(frame.count).littleEndian
            let header = Data(bytes: &length, count: 2)
            let packet = header + frame
            _ = packet.withUnsafeBytes {
                stream.write($0.bindMemory(to: UInt8.self).baseAddress!,
                            maxLength: packet.count)
            }
        }
    }

    private var sequenceNumber: Int = 0

    private func broadcastOpusViaMesh(_ frame: Data, roomId: String) {
        sequenceNumber += 1
        let payload = VoiceLivePayload(
            roomId: roomId,
            sequence: sequenceNumber,
            durationMs: 20,
            audioData: frame
        )
        let meshPayload = MeshPayload(
            type: .voiceLive,
            priority: .critical,
            ttl: 3,
            roomId: roomId,
            payload: payload
        )
        MeshService.shared.send(meshPayload)
    }

    // Recebendo áudio de streams
    func stream(_ stream: InputStream, handle eventCode: Stream.Event) {
        guard eventCode == .hasBytesAvailable else { return }
        // Lê [2 bytes length][N bytes opus] → decode → play
        // (Implementação de leitura do stream, decode, e playback via AudioUnit)
    }
}
```

### 4.4 Mensagem de voz assíncrona

```swift
class VoiceMessageService {
    static let shared = VoiceMessageService()
    private let codec = OpusCodec()
    private var recordingBuffer: Data = Data()
    private var isRecording = false
    private var recordingStartTime: Date?

    // MARK: - Gravação

    func startRecording() {
        recordingBuffer = Data()
        isRecording = true
        recordingStartTime = Date()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default,
                                 options: [.allowBluetooth])
        try? session.setActive(true)

        // Mesma lógica de tap do microfone, mas acumula em buffer
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16000,
            channels: 1, interleaved: true
        )!
        let converter = AVAudioConverter(from: format, to: desiredFormat)

        inputNode.installTap(onBus: 0, bufferSize: 320, format: format) { [weak self] buffer, _ in
            guard let self, self.isRecording else { return }
            guard let converted = self.convert(buffer, with: converter, to: desiredFormat) else { return }

            self.recordingBuffer.append(converted)

            // Limite de 60 segundos
            if self.recordingDuration > 60 {
                self.stopRecording()
            }
        }

        audioEngine.prepare()
        try? audioEngine.start()
    }

    func stopRecording() -> VoiceMessage? {
        guard isRecording, !recordingBuffer.isEmpty else { return nil }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        let duration = recordingDuration

        // Comprime todo o buffer de uma vez com Opus
        guard let opusData = codec.encode(recordingBuffer) else { return nil }

        let message = VoiceMessage(
            id: UUID().uuidString,
            roomId: currentRoomId,
            rideId: currentRideId,
            fromRiderId: profile.id,
            fromRiderName: profile.name,
            sentAt: Date(),
            duration: duration,
            audioData: opusData,
            deliveredTo: [],
            playedBy: []
        )

        // Salva localmente
        LocalStore.shared.saveVoiceMessage(message)

        // Envia via mesh (oportunístico)
        send(message)

        return message
    }

    var recordingDuration: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Envio

    func send(_ message: VoiceMessage) {
        let payload = VoiceMessagePayload(
            messageId: message.id,
            roomId: message.roomId,
            fromRiderId: message.fromRiderId,
            fromRiderName: message.fromRiderName,
            sentAt: message.sentAt,
            duration: message.duration,
            audioData: message.audioData
        )

        let meshPayload = MeshPayload(
            id: message.id,
            type: .voiceMessage,
            senderId: profile.id,
            senderName: profile.name,
            rideId: currentRideId,
            roomId: message.roomId,
            timestamp: Date(),
            ttl: 10,
            priority: .high,
            payload: try! JSONEncoder().encode(payload)
        )

        MeshService.shared.send(meshPayload)
        OfflineQueue.shared.enqueue(meshPayload)
    }

    // MARK: - Recebimento

    func handleIncoming(_ payload: VoiceMessagePayload) {
        // Salva localmente
        let message = VoiceMessage(
            id: payload.messageId,
            roomId: payload.roomId,
            rideId: currentRideId,
            fromRiderId: payload.fromRiderId,
            fromRiderName: payload.fromRiderName,
            sentAt: payload.sentAt,
            duration: payload.duration,
            audioData: payload.audioData,
            deliveredTo: [profile.id],
            playedBy: []
        )
        LocalStore.shared.saveVoiceMessage(message)

        // Envia ack de entrega
        sendAck(messageId: message.id, type: .delivered)

        // Notifica (UI + TTS se não estiver vendo a sala)
        if currentRoomId != message.roomId {
            VoiceAssistant.shared.speak(.newMessage(
                name: message.fromRiderName,
                room: roomName(for: message.roomId)
            ))
        }

        // Atualiza badge na UI
        NotificationCenter.default.post(name: .newVoiceMessage, object: message)
    }

    // MARK: - Playback

    func play(_ message: VoiceMessage) {
        guard let pcmData = codec.decode(message.audioData) else { return }

        // Toca via AudioUnit ou AVAudioPlayer
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default,
                                 options: [.allowBluetooth])

        // Playback do PCM data
        // (Usar AVAudioPlayer com WAV header, ou AudioUnit pra mais controle)

        // Marca como tocado
        LocalStore.shared.markVoiceMessagePlayed(message.id)
        sendAck(messageId: message.id, type: .played)
    }

    func sendAck(messageId: String, type: AckType) {
        let ack = VoiceMessageAckPayload(
            messageId: messageId,
            riderId: profile.id,
            type: type
        )
        let meshPayload = MeshPayload(
            type: .voiceMessageAck,
            priority: .normal,
            ttl: 5,
            payload: try! JSONEncoder().encode(ack)
        )
        MeshService.shared.send(meshPayload)
    }
}

enum AckType: String, Codable {
    case delivered, played
}
```

### 4.5 Gerenciamento da Sessão de Áudio

```swift
class AudioSessionManager {
    static let shared = AudioSessionManager()

    enum Scenario {
        case ttsOnly             // Só TTS
        case voiceCommand        // TTS + reconhecimento de voz
        case walkieTalkie        // PTT ativo (playAndRecord)
        case recording           // Gravando mensagem (record)
        case playback            // Tocando mensagem (playback)
        case intercomDetected    // Cardo/Sena presente
    }

    func configure(for scenario: Scenario) {
        let session = AVAudioSession.sharedInstance()

        switch scenario {
        case .ttsOnly:
            try? session.setCategory(.playback, mode: .spokenAudio,
                                     options: [.duckOthers, .allowBluetooth])

        case .voiceCommand:
            try? session.setCategory(.playAndRecord, mode: .default,
                                     options: [.allowBluetooth, .mixWithOthers,
                                               .defaultToSpeaker])

        case .walkieTalkie:
            try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                     options: [.allowBluetooth,
                                               .defaultToSpeaker])

        case .recording:
            try? session.setCategory(.record, mode: .default,
                                     options: [.allowBluetooth])

        case .playback:
            try? session.setCategory(.playback, mode: .default,
                                     options: [.allowBluetooth])

        case .intercomDetected:
            try? session.setCategory(.playback, mode: .spokenAudio,
                                     options: [.duckOthers, .allowBluetooth])
        }

        try? session.setActive(true)
    }
}
```

---

## 5. Prioridade entre fontes de áudio

```
Quando múltiplas coisas querem falar:

1. SOS / Alerta crítico          → Interrompe TUDO, repete 3x
2. Walkie-talkie (voz chegando)  → Abaixa TTS (ducking)
3. Mensagem de voz recebida      → Só notifica (TTS), não toca automaticamente
4. TTS normal                    → Fala quando canal livre
5. Walkie-talkie (PTT ativado)   → Captura microfone, prioridade máxima
6. Comando de voz                → Captura microfone
7. Gravação de mensagem          → Captura microfone (mas PTT interrompe)
```

---

## 6. Métricas de áudio

```
VOZ AO VIVO (Walkie-Talkie):
  - Sample rate: 16kHz mono
  - Codec: Opus 32kbps
  - Frame: 20ms → ~80 bytes por frame
  - Latência P2P direto: < 200ms
  - Latência mesh relay (3 hops): < 2s
  - Banda necessária: ~4 KB/s (32 kbps + overhead)

MENSAGEM DE VOZ:
  - Sample rate: 16kHz mono
  - Codec: Opus 32kbps
  - Arquivo completo (não streaming)
  - 5s de áudio → ~20KB
  - 30s de áudio → ~120KB
  - 60s de áudio → ~240KB (máximo)

COMPARAÇÃO:
  Walkie-Talkie: latência importa mais que qualidade
  Mensagem: qualidade importa mais que latência
  Ambos usam mesmo codec (Opus) — simplifica o stack
```
