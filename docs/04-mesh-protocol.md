# WAWA Ride — Protocolo Mesh P2P (v2)

> **Zero servidor. Toda comunicação é P2P via MultipeerConnectivity.**
> Internet, se disponível, acelera o mesh (WiFi infra relay). Mas não é necessária.

## 1. MultipeerConnectivity

Três componentes (Apple nativos, usados pelo AirDrop):

```
MCPeerID            — Identidade: "Pedro (iPhone 15 Pro)"
MCSession           — Sessão P2P (até 8 peers conectados simultaneamente)
MCNearbyServiceAdvertiser  — Anuncia via BLE (peripheral)
MCNearbyServiceBrowser     — Descobre via BLE (central)
```

Transportes automáticos: BLE (~50m) → WiFi Direct/AWDL (~200m) → WiFi Infra (~ilimitado com internet)

---

## 2. Descoberta e Conexão

### 2.1 Service Type

```swift
static let serviceType = "wawa-ride"  // Máx 15 chars
```

### 2.2 Discovery Info

```swift
struct MeshDiscoveryInfo {
    let rideId: String          // UUID do passeio
    let rideName: String        // "Serra do Rio do Rastro"
    let leaderName: String      // "Wagner"
    let riderCount: String      // "4"
    let rideStatus: String      // "active"
    let roomCount: String       // "3" (quantas salas existem)
    let version: String         // "2" (versão do protocolo)

    var dictionary: [String: String] {
        [
            "v": version, "rid": rideId, "rn": rideName,
            "ln": leaderName, "rc": riderCount, "rs": rideStatus,
            "rmc": roomCount
        ]
        // Nomes curtos pra caber em 256 bytes (limite do MC)
    }
}
```

### 2.3 Fluxo completo

```
LÍDER                                    RIDER
  │                                        │
  ├─ startAdvertisingPeer(discoveryInfo)   │
  │  BLE: "wawa-ride" + info              │
  │                                        │
  │                                        ├─ startBrowsingForPeers()
  │                                        │  BLE scan: "wawa-ride"
  │                                        │
  │                                        ├─ found: "Wagner — Serra (4 riders)"
  │                                        │
  │                                        ├─ usuário aperta ENTRAR
  │                                        │
  │  ◀── invitation (MC auto-accept) ────  │
  │                                        │
  │  ═══════ MCSession CONNECTED ═══════  │
  │                                        │
  ├─ envia estado completo:               │
  │  - Ride info                           │
  │  - Lista de salas (Rooms)              │
  │  - Posições de todos os riders        │
  │  - Rota ativa (se houver)             │
  │  - Alertas ativos                      │
  │                                        │
  │                                        ├─ recebe → atualiza mapa + salas
  │                                        ├─ joinRequest enviado
  │                                        │
  ├─ broadcast: roomJoin (Geral)          │
  │  TTS todos: "Pedro entrou"            │
  │                                        │
  └────────────────────────────────────────┘
```

---

## 3. Envelope de Mensagem (MeshPayload)

```swift
{
    "id": "uuid-v4",              // Dedup
    "type": "locationUpdate",     // MeshPayloadType
    "senderId": "rider-uuid",
    "senderName": "Pedro",
    "rideId": "abc123",
    "roomId": null,               // null = passeio, string = sala
    "timestamp": 1718234567.890,
    "ttl": 5,                     // Saltos restantes
    "priority": 2,                // 0=critical, 1=high, 2=normal, 3=low
    "payload": "{...}"            // JSON do payload específico
}
```

---

## 4. Payloads por tipo

### 4.1 locationUpdate (priority: normal, ttl: 3)
```json
{
    "lat": -28.123456, "lng": -49.456789,
    "speed": 72.5, "heading": 145.2,
    "altitude": 1280.0, "batteryLevel": 0.75
}
```

### 4.2 routeCreated (priority: low, ttl: 8)
```json
{
    "routeId": "uuid",
    "routeName": "Serra — Trecho 1",
    "source": "drawn",
    "waypoints": [
        {"lat": -28.1, "lng": -49.4, "order": 0, "name": "Início", "isStop": false},
        {"lat": -28.2, "lng": -49.5, "order": 1, "name": "Posto", "isStop": true}
    ],
    "totalDistance": 128000.0
}
```

### 4.3 routeBatch (priority: low, ttl: 5)
```json
{
    "routeId": "uuid",
    "points": [
        {"lat": -28.123, "lng": -49.456, "order": 42, "speed": 72.5, "altitude": 1280.0}
        // Lotes de 50 pontos
    ],
    "batchStart": 42,
    "batchEnd": 91
}
```

### 4.4 routeShared (priority: low, ttl: 8)
Rota completa compartilhada entre riders (mesmo schema de routeCreated).

### 4.5 roomCreated (priority: high, ttl: 10)
```json
{
    "room": {
        "id": "uuid",
        "rideId": "abc123",
        "name": "Líder+Varredor",
        "createdBy": "rider-uuid",
        "creatorName": "Wagner",
        "createdAt": 1718234567.890,
        "type": "voice",
        "isPrivate": true,
        "members": ["uuid-wagner", "uuid-joao"],
        "isActive": true
    }
}
```

### 4.6 roomClosed / roomJoin / roomLeave (priority: high, ttl: 8)
```json
{
    "roomId": "uuid",
    "riderId": "uuid",
    "riderName": "João"
}
```

### 4.7 voiceLive — chunk de voz ao vivo (priority: critical, ttl: 3)
```json
{
    "roomId": "uuid",           // Sala de destino
    "sequence": 142,            // Número de sequência (detectar falta)
    "duration_ms": 20,          // Duração do chunk
    "audioData": "<base64-opus>" // Frame Opus (~80 bytes pra 20ms)
}
```

### 4.8 voiceMessage — áudio assíncrono (priority: high, ttl: 10)
```json
{
    "messageId": "uuid",
    "roomId": "uuid",
    "fromRiderId": "uuid",
    "fromRiderName": "Pedro",
    "sentAt": 1718234567.890,
    "duration": 12.5,
    "audioData": "<base64-opus>"  // ~50KB pra 12.5s
}
```

### 4.9 voiceMessageAck (priority: normal, ttl: 5)
```json
{
    "messageId": "uuid",
    "deliveredTo": "uuid",
    "playedBy": ["uuid"]
}
```

### 4.10 hazardAlert (priority: critical, ttl: 10)
```json
{
    "alertId": "uuid",
    "type": "radar",
    "lat": -28.123456, "lng": -49.456789,
    "reportedBy": "Pedro", "reportedById": "uuid",
    "createdAt": 1718234567.890,
    "expiresAt": 1718236367.890
}
```

### 4.11 sosAlert (priority: critical, ttl: 15)
```json
{
    "lat": -28.123456, "lng": -49.456789,
    "reason": "Acidente",
    "batteryLevel": 0.35
}
```

### 4.12 statusChange (priority: high, ttl: 7)
```json
{
    "status": "stopped",   // "stopped", "moving", "need_help", "ok"
    "lat": -28.123456, "lng": -49.456789
}
```

### 4.13 heartbeat (priority: normal, ttl: 1)
```json
{
    "batteryLevel": 0.75,
    "isMoving": true,
    "activeRoom": "room-id"  // Sala que o rider está "ativo" (vendo/ouvindo)
}
```

### 4.14 rideEnded (priority: high, ttl: 10)
```json
{
    "rideId": "abc123",
    "finishedAt": 1718234567.890
}
```

---

## 5. Store-and-Forward Retransmissão

```
Cenário: 5 motos em fila, só vizinhos conectados

[L] ←→ [R2] ←→ [R3] ←→ [R4] ←→ [V]

L envia hazardAlert (ttl=10, critical):
  L → R2 (ttl=10)
  R2 processa → retransmite → R3 (ttl=9)
  R3 processa → retransmite → R4 (ttl=8)
  R4 processa → retransmite → V (ttl=7)
  V processa → sem mais peers → para
```

### Algoritmo

```swift
func handleReceived(_ data: Data, from peerID: MCPeerID) {
    guard var payload = decode(data) else { return }

    // 1. Dedup
    guard !dedup.hasSeen(payload.id) else { return }
    dedup.markSeen(payload.id)

    // 2. Processa localmente
    processPayload(payload)

    // 3. Retransmite se TTL > 0
    payload.ttl -= 1
    guard payload.ttl > 0 else { return }

    // 4. Forward pra todos EXCETO origem
    let forwardTo = session.connectedPeers.filter { $0 != peerID }
    guard !forwardTo.isEmpty else { return }

    let json = encode(payload)
    try? session.send(json, toPeers: forwardTo, with: .reliable)
}
```

---

## 6. Voz ao Vivo via MCSession Stream

```swift
// Voz via stream (caminho direto, menor latência)
func startVoiceStream(to peerID: MCPeerID, roomId: String) -> OutputStream {
    let streamName = "wawa-voice-\(roomId)"
    let stream = try! session.startStream(withName: streamName, toPeer: peerID)
    stream.delegate = self
    stream.schedule(in: .main, forMode: .default)
    stream.open()
    return stream
}

// Formato dos dados no stream:
// [2 bytes length (UInt16 little-endian)][N bytes Opus frame]
// Cada frame: 20ms de áudio, ~80 bytes (32kbps)

// Fallback (peers não diretamente conectados):
// Chunks de áudio como MeshPayload voiceLive com TTL 3
// Latência maior, mas alcança via store-and-forward
```

---

## 7. Deduplicação

```swift
class MeshDedup {
    // Anel circular em memória + SQLite pra persistir entre reinícios
    private var recent: [String: Date] = [:]
    private let maxRecent = 2000
    private let ttl: TimeInterval = 300 // 5 minutos

    func hasSeen(_ id: String) -> Bool {
        if recent[id] != nil { return true }
        // Check SQLite (sobrevive a reinício do app)
        return LocalStore.shared.hasMeshMessage(id)
    }

    func markSeen(_ id: String) {
        recent[id] = Date()
        LocalStore.shared.insertMeshMessage(id)
        // Evict old entries
        if recent.count > maxRecent {
            let sorted = recent.sorted { $0.value < $1.value }
            for (key, _) in sorted.prefix(maxRecent / 2) {
                recent.removeValue(forKey: key)
            }
        }
    }
}
```

---

## 8. Voz Assíncrona — Transmissão Oportunística

```
A voiceMessage é uma mensagem completa (não streaming).
Estratégia de transmissão oportunística:

TEM MESH (peers conectados):
  → Envia direto pros peers (se destinatários no alcance)
  → Peers retransmitem se TTL > 0

TEM INTERNET (WiFi infra relay do MC):
  → MultipeerConnectivity automaticamente usa WiFi infra
  → Se ambos têm internet: mensagem chega via relay IP (latência < 1s)
  → Se só remetente tem internet: MC tenta relay via infra

TUDO OFFLINE:
  → OfflineQueue persiste no SQLite
  → Quando reconectar (mesh ou internet): drena

ACKNOWLEDGMENT:
  → Destinatário recebe → envia voiceMessageAck (delivered)
  → Destinatário ouve → envia voiceMessageAck (played)
  → Remetente vê: ✓ (enviado) → ✓✓ (entregue) → ✓✓ (azul = ouvido)
```

---

## 9. Sessão Mesh — Limites e Estratégia

```
LIMITES DO MULTIPEERCONNECTIVITY:
  - Máx 8 peers conectados simultaneamente por MCSession
  - Solução: cada peer conecta com até 7 vizinhos mais próximos
  - Mensagens com TTL > 0 alcançam todos via retransmissão
  - Na prática, 20 riders com 7 conexões cada = mesh denso e resiliente

ESTRATÉGIA DE CONEXÃO:
  - Priorizar peers com melhor qualidade de sinal
  - Manter 1-2 conexões "de longo alcance" (WiFi Direct)
  - O resto: conexões BLE com vizinhos próximos
  - Se peer cai: reconexão automática com backoff exponencial

RECONEXÃO:
  - Backoff: 2s, 4s, 8s, 16s, 32s, 64s (máx)
  - Após 3 minutos sem sucesso: peer considerado "fora de alcance"
  - Se peer reaparece (BLE discovery): zera backoff, conecta imediatamente
```

---

## 10. Segurança no Mesh

| Camada | Proteção |
|--------|----------|
| Descoberta | Service type "wawa-ride" público. Discovery info legível por qualquer app com mesmo service. |
| Conexão | `encryptionPreference = .required` — criptografia ponta-a-ponta em todas as conexões. |
| Integridade | `sendMode = .reliable` — TCP-like, garante entrega sem corrupção. |
| Identidade | `MCPeerID.displayName` pode ser forjado. MVP confia (proximidade física = autorização). |
| Replay | Dedup por message ID + TTL previne loops de retransmissão. |
| Privacidade | Salas privadas: payload NÃO é criptografado adicionalmente, mas só membros recebem. Se um peer malicioso retransmitir, membros ignoram (não são destinatários). |
