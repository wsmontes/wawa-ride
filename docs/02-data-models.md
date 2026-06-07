# WAWA Ride — Modelos de Dados

## 1. Perfil do Piloto (local, UserDefaults)

```swift
struct RiderProfile: Codable {
    let id: String              // UUID gerado no primeiro launch
    let name: String            // Nome ou apelido (ex: "Wagner")
    let bikeModel: String?      // Modelo da moto (ex: "BMW R1250GS")
    let photoData: Data?        // Foto (JPEG comprimido, máx 200KB)
    let defaultRole: RideRole   // .leader ou .rider (padrão escolhido no setup)
    let createdAt: Date
}

enum RideRole: String, Codable {
    case leader                 // Líder — cria passeios
    case rider                  // Rider comum
    case sweeper                // Varredor — último da fila (definido durante o passeio)
}
```

Armazenamento: `UserDefaults` como JSON. Tamanho total < 5KB (sem foto) ou ~200KB (com foto).

---

## 2. Passeio (Firestore + Local)

### 2.1 Documento principal — `rides/{rideId}`

```swift
// Subcoleção: rides/{rideId}/info — documento único
struct RideInfo: Codable {
    let rideId: String          // UUID
    let name: String            // Nome do passeio (ex: "Serra do Rio do Rastro")
    let leaderId: String        // ID do líder (RiderProfile.id)
    let leaderName: String      // Nome do líder (desnormalizado pra mostrar no join)
    let status: RideStatus      // .active, .paused, .finished
    let createdAt: Date         // Timestamp de criação
    let finishedAt: Date?       // Quando foi encerrado
    let totalRiders: Int        // Contador (atualizado a cada join/leave)
    let currentRoute: [RoutePoint]? // Rota completa (atualizada ao final ou snapshot periódico)
}

enum RideStatus: String, Codable {
    case active                 // Passeio em andamento
    case paused                 // Parada rápida (posto, lanche)
    case finished               // Encerrado
}
```

### 2.2 Rider dentro do passeio — `rides/{rideId}/riders/{riderId}`

```swift
struct RideParticipant: Codable {
    let riderId: String         // = RiderProfile.id
    let name: String            // Nome do rider
    let bikeModel: String?      // Moto
    let role: RideRole          // .leader, .rider, .sweeper
    let isConnected: Bool       // true = online agora (tem heartbeat recente)
    let lastSeen: Date          // Último heartbeat recebido

    // Posição (atualizada a cada 1-3s)
    var latitude: Double
    var longitude: Double
    var speed: Double           // km/h
    var heading: Double         // 0-360 graus
    var altitude: Double?       // Metros
    var locationTimestamp: Date

    // Status
    var isMoving: Bool          // speed > 5 km/h
    var batteryLevel: Float?    // 0.0-1.0 (opcional, pra líder saber quem vai ficar sem bateria)
}
```

### 2.3 Alerta de perigo — `rides/{rideId}/alerts/{alertId}`

```swift
struct HazardAlert: Codable, Identifiable {
    let id: String              // UUID
    let type: HazardType
    let latitude: Double
    let longitude: Double
    let reportedBy: String      // Nome de quem reportou
    let reportedById: String    // ID de quem reportou
    let createdAt: Date
    let expiresAt: Date         // Data de expiração automática
    let confirmedBy: [String]   // Lista de nomes que confirmaram
    let clearedBy: [String]     // Lista de nomes que limparam ("já passou")
    let isActive: Bool          // Ainda está ativo?

    // Computado
    var isExpired: Bool { Date() > expiresAt }
    var confidence: Int { 1 + confirmedBy.count - clearedBy.count }
}

enum HazardType: String, Codable, CaseIterable {
    case radar          // Radar fixo/móvel — expira em 30 min
    case pothole        // Buraco na pista — expira em 30 min
    case police         // Polícia/Blitz — expira em 15 min
    case oil            // Óleo na pista — expira em 60 min
    case animal         // Animal na pista — expira em 15 min
    case gravel         // Cascalho solto — expira em 30 min
    case accident       // Acidente — expira em 60 min
    case other          // Outro — expira em 15 min

    var ttlMinutes: Int {
        switch self {
        case .radar: 30
        case .pothole: 30
        case .police: 15
        case .oil: 60
        case .animal: 15
        case .gravel: 30
        case .accident: 60
        case .other: 15
        }
    }
}
```

### 2.4 Rota — array de pontos

```swift
struct RoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let order: Int              // Sequência (0, 1, 2, ...)
    let timestamp: Date
    let speed: Double           // Velocidade no ponto (útil pra cor da polyline)
}

// Simplificação da rota (algoritmo de Ramer-Douglas-Peucker)
// tolerância: 5m (pontos com desvio < 5m da reta são removidos)
```

---

## 3. Payload do Mesh P2P

```swift
struct MeshPayload: Codable {
    let id: String              // UUID único (pra dedup)
    let type: MeshPayloadType
    let senderId: String        // RiderProfile.id de quem originou
    let senderName: String      // Nome (desnormalizado)
    let rideId: String          // Passeio a que pertence
    let timestamp: Date
    var ttl: Int                // Saltos restantes (decrementa a cada retransmissão)
    let priority: MeshPriority
    let payload: Data           // JSON do payload específico do tipo
}

enum MeshPayloadType: String, Codable {
    case locationUpdate     // Posição GPS
    case hazardAlert        // Novo alerta de perigo
    case hazardConfirm      // Confirmação de alerta
    case hazardClear        // Limpeza de alerta
    case routePoint         // Um ponto da rota do líder
    case routeBatch         // Vários pontos da rota (para sync eficiente)
    case statusChange       // "Parei", "Preciso de ajuda", "Seguindo"
    case heartbeat          // "Ainda estou aqui" (mantém conexão viva)
    case voiceData          // Chunk de áudio do walkie-talkie (se for via mesh)
    case rideInfo           // Metadados do passeio (nome, líder, status)
    case joinRequest        // Rider pedindo pra entrar
    case joinAccept         // Líder aceitando entrada
    case leaveNotification  // Rider saindo do passeio
    case sosAlert           // SOS — rider precisa de ajuda
}

enum MeshPriority: Int, Codable, Comparable {
    case critical = 0   // SOS, alerta de perigo → transmite IMEDIATAMENTE
    case high = 1       // Status change, join/leave
    case normal = 2     // Posição GPS, heartbeat
    case low = 3        // Route batch (pode chegar com atraso)

    static func < (lhs: MeshPriority, rhs: MeshPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

### Payloads específicos (JSON dentro de `MeshPayload.payload`)

```swift
// Location Update
struct LocationPayload: Codable {
    let lat: Double
    let lng: Double
    let speed: Double       // km/h
    let heading: Double     // 0-360
    let altitude: Double?
}

// Hazard Alert
struct HazardAlertPayload: Codable {
    let alertId: String
    let type: String        // HazardType.rawValue
    let lat: Double
    let lng: Double
    let expiresAt: Date
}

// SOS
struct SOSPayload: Codable {
    let lat: Double
    let lng: Double
    let reason: String?     // "Acidente", "Pane", "Sem combustível"
    let batteryLevel: Float?
}
```

---

## 4. Modelo de Alertas de Voz (TTS)

```swift
struct VoiceAlert: Codable {
    let text: String                    // Texto a ser falado
    let priority: VoiceAlertPriority
    let canInterrupt: Bool              // Pode interromper fala atual?
    let repeatCount: Int                // Quantas vezes repetir
    let minInterval: TimeInterval       // Intervalo mínimo entre repetições
    let spokenAt: Date?                 // Última vez que foi falado
}

enum VoiceAlertPriority: Int, Codable, Comparable {
    case background = 0   // "Todos juntos", "Pedro entrou"
    case normal = 1       // Status, posição
    case high = 2         // Fora da rota, líder parou
    case critical = 3     // Perigo, SOS

    static func < (lhs: VoiceAlertPriority, rhs: VoiceAlertPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

---

## 5. Estrutura do Firestore

```
rides/                               # Coleção principal
  {rideId}/
    info/                            # Documento único com RideInfo
      rideId, name, leaderId, leaderName, status, createdAt, finishedAt, totalRiders

    riders/                          # Subcoleção
      {riderId}/                     # Documento = RideParticipant
        riderId, name, bikeModel, role, isConnected, lastSeen,
        latitude, longitude, speed, heading, altitude, locationTimestamp,
        isMoving, batteryLevel

    alerts/                          # Subcoleção
      {alertId}/                     # Documento = HazardAlert
        id, type, latitude, longitude, reportedBy, reportedById,
        createdAt, expiresAt, confirmedBy, clearedBy, isActive

    route/                           # Subcoleção (coleção porque pode ser grande)
      {pointIndex}/                  # Documento = RoutePoint
        latitude, longitude, order, timestamp, speed
```

### Índices compostos necessários (Firestore)

```
rides/{rideId}/riders:
  - locationTimestamp DESC          (pra query "últimas posições")

rides/{rideId}/alerts:
  - isActive == true, expiresAt ASC (pra query "alertas ativos não expirados")
  - createdAt DESC                  (pra timeline de alertas)

rides/{rideId}/route:
  - order ASC                       (pra ler a rota em sequência)
```

### Regras de segurança Firestore (MVP — sem auth)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /rides/{rideId} {
      // MVP: qualquer um pode ler/escrever se souber o rideId
      // (rideId é UUID v4, efetivamente unguessable)
      // FUTURO: validar com Firebase Auth + lista de riders autorizados
      allow read, write: if true;
    }
  }
}
```

---

## 6. Offline Queue (SQLite via GRDB)

```sql
CREATE TABLE offline_queue (
    id TEXT PRIMARY KEY,            -- UUID
    payload_json TEXT NOT NULL,      -- MeshPayload serializado
    priority INTEGER NOT NULL,       -- MeshPriority.rawValue
    created_at INTEGER NOT NULL,     -- Unix timestamp
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 10,
    last_error TEXT
);

CREATE INDEX idx_queue_priority ON offline_queue(priority, created_at);
```

Regras da fila:
- Máximo 1000 mensagens. Se exceder, remove as de menor prioridade primeiro.
- Mensagens expiram: critical = 1h, high = 30min, normal = 10min, low = 5min
- Ao reconectar (4G ou mesh), drena na ordem de prioridade
- Dedup: se chega um payload com mesmo `id`, ignora (já foi processado)

---

## 7. Armazenamento Local (UserDefaults + SQLite)

| Dado | Local | Tamanho estimado |
|------|-------|-----------------|
| RiderProfile | UserDefaults (JSON) | < 200KB |
| Último RideSummary | UserDefaults (JSON) | < 5KB |
| Fila offline | SQLite (GRDB) | < 10MB |
| Cache de rotas finalizadas | SQLite (GRDB) | < 50MB (10 passeios) |
| Preferências (voz, unidades) | UserDefaults | < 1KB |
