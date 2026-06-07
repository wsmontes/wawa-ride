# WAWA Ride — Protocolo Mesh (P2P)

## 1. Visão geral do MultipeerConnectivity

O framework da Apple usado pelo AirDrop. Três componentes:

```
MultipeerConnectivity
├── MCPeerID            — Identidade do dispositivo (displayName = nome do rider)
├── MCSession           — Sessão de comunicação entre peers (até 8 conectados)
├── MCNearbyServiceAdvertiser  — Anuncia presença via BLE (peripheral)
└── MCNearbyServiceBrowser     — Descobre advertisers via BLE (central)
```

**Transportes que o MC usa automaticamente:**
1. **BLE** — Descoberta e handshake inicial (~50m)
2. **WiFi Direct (AWDL)** — Dados de alta velocidade (~200m com linha de visada)
3. **WiFi Infraestrutura** — Se ambos na mesma rede WiFi (~alcance da rede)
4. **Bluetooth Classic** — Fallback de banda média (~30m)

O MC escolhe o melhor transporte sozinho. Não controlamos. Isso é bom (otimizado pela Apple) e ruim (não podemos forçar WiFi Direct).

---

## 2. Fluxo de Descoberta e Conexão

```
LÍDER                               RIDER
  │                                   │
  ├─ startAdvertisingPeer()           │
  │  discoveryInfo: {                 │
  │    rideId: "abc123",              │
  │    leaderName: "Wagner",          │
  │    riderCount: "3",               │
  │    rideStatus: "active"           │
  │  }                                │
  │                                   │
  │                                   ├─ startBrowsingForPeers()
  │                                   │  (procura serviceType "wawa-ride")
  │                                   │
  │                                   ├─ found peer "Wagner" ◀── BLE
  │                                   │  discoveryInfo recebido
  │                                   │  UI: "Wagner — Serra do Rio do Rastro (3 riders)"
  │                                   │
  │                                   ├─ usuário aperta ENTRAR
  │                                   │
  │  ◀─── invitation from rider ────  │
  │  (MC auto-accept no MVP.         │
  │   Futuro: líder aprova.)         │
  │                                   │
  ├─ accept invitation ──────────────▶│
  │                                   │
  │  ◀════ CONNECTED ═══════════════▶│
  │                                   │
  ├─ envia RideInfo completo          │
  │  (rota atual, riders, alertas)   │
  │                                   │
  │                                   ├─ recebe estado completo
  │                                   │  atualiza mapa
  │                                   │
  │                                   ├─ envia joinRequest
  │                                   │
  ├─ broadcast: "Pedro entrou" ──────▶│
  │                                   │
  └───────────────────────────────────┘
```

---

## 3. Service Type e Discovery Info

```swift
// Constante do app
static let serviceType = "wawa-ride"  // Máx 15 chars, só letras, números e hífens

// Discovery info (dicionário String:String, máx 256 bytes total)
struct MeshDiscoveryInfo {
    let rideId: String          // "abc123"
    let leaderName: String      // "Wagner"
    let riderCount: String      // "3"
    let rideStatus: String      // "active" | "paused"
    let version: String         // "1" (versão do protocolo)

    var dictionary: [String: String] {
        [
            "rideId": rideId,
            "leaderName": leaderName,
            "riderCount": riderCount,
            "rideStatus": rideStatus,
            "version": version
        ]
    }

    static func from(_ dict: [String: String]?) -> MeshDiscoveryInfo? {
        guard let dict,
              let rideId = dict["rideId"],
              let leaderName = dict["leaderName"],
              let riderCount = dict["riderCount"],
              let rideStatus = dict["rideStatus"],
              let version = dict["version"]
        else { return nil }
        return MeshDiscoveryInfo(rideId: rideId, leaderName: leaderName,
                                  riderCount: riderCount, rideStatus: rideStatus,
                                  version: version)
    }
}
```

---

## 4. Protocolo de Comunicação

### 4.1 Formato da mensagem (envelope)

Toda mensagem no mesh é um `MeshPayload` serializado como JSON, enviado via `MCSession.send(_:toPeers:with:)`.

```swift
// Envelope comum a todas as mensagens
{
    "id": "uuid-v4",
    "type": "locationUpdate",       // MeshPayloadType
    "senderId": "rider-uuid",
    "senderName": "Wagner",
    "rideId": "abc123",
    "timestamp": 1718234567.890,    // Unix timestamp com ms
    "ttl": 5,                       // Saltos restantes
    "priority": 2,                  // MeshPriority.rawValue
    "payload": "{...}"              // JSON string do payload específico
}
```

### 4.2 Tipos de mensagem e seus payloads

#### locationUpdate (priority: normal, ttl: 3)
```json
{
    "lat": -28.123456,
    "lng": -49.456789,
    "speed": 72.5,
    "heading": 145.2,
    "altitude": 1280.0
}
```
Frequência: 1-3s. TTL baixo porque localização envelhece rápido.

#### hazardAlert (priority: critical, ttl: 10)
```json
{
    "alertId": "uuid",
    "type": "radar",
    "lat": -28.123456,
    "lng": -49.456789,
    "expiresAt": 1718234567.890
}
```
TTL alto: alertas precisam se espalhar por todo o pelotão.

#### hazardConfirm / hazardClear (priority: high, ttl: 8)
```json
{
    "alertId": "uuid",
    "riderName": "Pedro"
}
```

#### routeBatch (priority: low, ttl: 5)
```json
{
    "points": [
        {"lat": -28.123, "lng": -49.456, "order": 42, "timestamp": 1718234567.890, "speed": 72.5},
        {"lat": -28.124, "lng": -49.458, "order": 43, "timestamp": 1718234568.890, "speed": 73.0}
    ],
    "batchStart": 42,
    "batchEnd": 43
}
```
Enviado em lotes de 50 pontos pra ser eficiente. Baixa prioridade — pode chegar com atraso.

#### statusChange (priority: high, ttl: 7)
```json
{
    "status": "stopped",        // "stopped" | "moving" | "need_help" | "ok"
    "lat": -28.123456,
    "lng": -49.456789
}
```

#### heartbeat (priority: normal, ttl: 1)
```json
{
    "batteryLevel": 0.75,
    "isMoving": true
}
```
Frequência: a cada 30s. TTL 1 = não retransmite.

#### voiceData (priority: high, ttl: 3)
```json
{
    "chunk": "<base64-encoded-opus-audio>",
    "sequence": 42,
    "duration_ms": 200
}
```
Chunks de 200ms de áudio Opus. TTL baixo — áudio em tempo real não pode ter latência.

#### joinRequest / joinAccept (priority: high, ttl: 3)
```json
{
    "riderId": "uuid",
    "riderName": "Pedro",
    "bikeModel": "BMW R1250GS",
    "role": "rider"
}
```

#### sosAlert (priority: critical, ttl: 15)
```json
{
    "lat": -28.123456,
    "lng": -49.456789,
    "reason": "accident",
    "batteryLevel": 0.35
}
```
TTL máximo: SOS precisa chegar em TODO MUNDO.

---

## 5. Retransmissão Store-and-Forward

```
Cenário: 5 motos em fila, Líder perdeu conexão com Varredor
(mas cada um está conectado ao vizinho)

[L] ←→ [R2] ←→ [R3] ←→ [R4] ←→ [V]

L envia localização (ttl=3):
  L → R2 (ttl=3)
  R2 processa localização, atualiza mapa
  R2 → R3 (ttl=2)  // retransmite com TTL-1
  R3 processa, atualiza mapa
  R3 → R4 (ttl=1)
  R4 processa, atualiza mapa
  R4 → V (ttl=0)
  V processa (ttl=0, não retransmite mais)
```

### Algoritmo de retransmissão

```swift
func handleReceivedPayload(_ data: Data, from peerID: MCPeerID) {
    guard var payload = decode(data) else { return }

    // 1. Dedup: já processei essa mensagem?
    guard !processedMessageIds.contains(payload.id) else { return }
    processedMessageIds.insert(payload.id)

    // 2. Processa localmente
    processPayload(payload)

    // 3. Retransmite se ainda tem TTL
    payload.ttl -= 1
    guard payload.ttl > 0 else { return }

    // 4. Retransmite para todos EXCETO quem mandou
    let forwardTo = session.connectedPeers.filter { $0 != peerID }
    guard !forwardTo.isEmpty else { return }

    let json = encode(payload)
    try? session.send(json, toPeers: forwardTo, with: .reliable)
}
```

### Dedup Set

```swift
// Anel circular de últimos 1000 message IDs processados
// Mensagens expiram do set após 5 minutos
class MessageDedup {
    private var processed: [String: Date] = [:]
    private let maxSize = 1000
    private let ttl: TimeInterval = 300 // 5 min

    func hasSeen(_ id: String) -> Bool {
        cleanup()
        return processed[id] != nil
    }

    func markSeen(_ id: String) {
        cleanup()
        processed[id] = Date()
        if processed.count > maxSize {
            // Remove os mais antigos
            let sorted = processed.sorted { $0.value < $1.value }
            for (key, _) in sorted.prefix(maxSize / 2) {
                processed.removeValue(forKey: key)
            }
        }
    }

    private func cleanup() {
        let cutoff = Date().addingTimeInterval(-ttl)
        processed = processed.filter { $0.value > cutoff }
    }
}
```

---

## 6. Gerenciamento da Sessão Mesh

### Estados da conexão

```
                    ┌──────────────┐
          ┌────────▶│  CONNECTED   │────────┐
          │         └──────────────┘        │
          │           │          │           │
     invite          │      disconnect    disconnect
     accepted    connected   (graceful)   (timeout)
          │           │          │           │
          │    ┌──────▼──────┐   │           │
          └────│ CONNECTING  │   │           │
               └──────┬──────┘   │           │
                      │          │           │
                 timeout    ┌───▼───────────▼──┐
                 (30s)      │   NOT CONNECTED   │
                            └───────────────────┘
```

### Reconexão automática

```swift
func session(_ session: MCSession, peer peerID: MCPeerID,
             didChange state: MCSessionState) {
    switch state {
    case .notConnected:
        // Tenta reconectar automaticamente por 3 minutos
        // com backoff exponencial: 2s, 4s, 8s, 16s, 32s, 64s
        scheduleReconnect(peer: peerID)

    case .connecting:
        // Timeout de 30s pra conectar
        startConnectTimeout(peer: peerID)

    case .connected:
        cancelReconnect(peer: peerID)
        cancelTimeout(peer: peerID)
        // Drena fila offline pra esse peer
        offlineQueue.drain(to: peerID)
        // Pede estado completo
        requestFullState(from: peerID)
    @unknown default: break
    }
}
```

### Limites da sessão

- Máximo de **8 peers conectados simultaneamente** no MCSession (limite da Apple)
- **Solução para grupos > 8:** Subgrupos interconectados via store-and-forward
  - Cada peer mantém conexão com até 7 vizinhos mais próximos
  - Mensagens com TTL > 0 alcançam todo mundo via retransmissão
  - Na prática, 20 riders com 7 conexões cada cobre qualquer topologia
- O MC lida com `MCSessionSendDataMode.reliable` — garante entrega, ordenação, sem duplicatas

---

## 7. Voz via Mesh (Walkie-Talkie P2P)

Quando não tem 4G, o walkie-talkie funciona via stream do MCSession:

```swift
// Abre stream de áudio para um peer
func startVoiceStream(to peerID: MCPeerID) -> OutputStream {
    let stream = try! session.startStream(
        withName: "wawa-voice",
        toPeer: peerID
    )
    stream.delegate = self
    stream.schedule(in: .main, forMode: .default)
    stream.open()
    return stream
}

// Envia chunks de áudio Opus comprimido (~32 kbps)
func sendVoiceChunk(_ data: Data, to stream: OutputStream) {
    // Formato: [2 bytes length][N bytes opus frame]
    var length = UInt16(data.count).littleEndian
    let header = Data(bytes: &length, count: 2)
    let frame = header + data
    _ = frame.withUnsafeBytes {
        stream.write($0.bindMemory(to: UInt8.self).baseAddress!,
                     maxLength: frame.count)
    }
}
```

**Nota:** Voz via mesh é uma otimização. No MVP, se o voice chat via MCSession stream for complexo, podemos usar chunks de voz como mensagens normais (tipo voiceData) com latência um pouco maior. O WebRTC com 4G é o caminho primário pra voz.

---

## 8. Background e Persistência do Mesh

```
APP EM FOREGROUND:
  - BLE advertising + browsing ativos e rápidos
  - WiFi Direct ativo
  - Conexões mantidas ativamente

APP EM BACKGROUND (com location updates ativo):
  - BLE advertising CONTINUA (bluetooth-peripheral background mode)
  - BLE browsing CONTINUA (bluetooth-central background mode)
  - MAS: intervalo de advertising/browsing aumenta (~1-5s)
  - Conexões existentes MANTIDAS (iOS não mata app com BLE connection ativa)

APP SUSPENSO (iOS matou por memória/bateria):
  - BLE advertising MORRE
  - BGTaskScheduler tenta acordar a cada ~15 min
  - Ao acordar: reativa BLE, anuncia de novo, tenta reconectar
  - Ao receber localização (location delegate): BGTaskScheduler agenda wakeup

ESTRATÉGIA ANTI-KILL:
  - Manter pelo menos 1 conexão BLE ativa com outro rider
  - Ter location updates em background (allowsBackgroundLocationUpdates)
  - Ter áudio ativo (TTS alerts frequentes)
  - iOS prioriza apps com: BLE connection + location + audio
```

---

## 9. Segurança no Mesh

| Camada | Proteção |
|--------|----------|
| Descoberta | Service type "wawa-ride" é público. Qualquer app pode anunciar/browsar. Mas discoveryInfo é lido só por quem tem o mesmo service type. |
| Conexão | `encryptionPreference = .required` — MCSession criptografa toda comunicação ponta-a-ponta. |
| Identidade | `MCPeerID.displayName` — pode ser forjado. No MVP, confiamos (grupo por proximidade física). |
| Integridade | `MCSessionSendDataMode.reliable` garante entrega sem corrupção. |
| Replay | Dedup por message ID + TTL previne loops. |
| Expiração | Mensagens expiram por TTL (saltos) e timestamp (idade). |

Para o MVP, o modelo de segurança é **"proximidade física = autorização"**. Se você está a 50m do grupo, você é do grupo. Isso cobre 99% dos casos reais.

---

## 10. Testes de Alcance Real (a fazer)

Antes de codar o mesh, precisamos de dados reais:

```
Cenários de teste (2 iPhones, 2 motos):
  1. Estacionados, linha de visada, variando distância (10m, 30m, 50m, 100m, 200m)
  2. Em movimento, mesma direção, distância fixa 50m
  3. Em movimento, direções opostas (se cruzam a 80 km/h cada)
  4. Com obstáculo (curva de serra, morro entre as motos)
  5. Com celular no bolso do motociclista (pior caso pra sinal)
  6. Com celular no suporte do guidão (melhor caso)

Métricas:
  - Tempo de descoberta BLE (até aparecer na lista)
  - Tempo de conexão (até session state = .connected)
  - Latência de ida e volta (RTT) de uma mensagem
  - Throughput máximo (MB/s) — relevante pra voz
  - Estabilidade da conexão (quedas por minuto)
```

Resultados desses testes vão ditar ajustes nos TTLs, timeouts e estratégia de reconexão.
