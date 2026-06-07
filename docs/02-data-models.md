# WAWA Ride — Modelos de Dados (v2)

## 1. Perfil do Piloto (local, SQLite + cache em UserDefaults)

```swift
struct RiderProfile: Codable {
    let id: String              // UUID gerado no primeiro launch
    let name: String            // Nome ou apelido
    let bikeModel: String?      // Moto (opcional)
    let photoData: Data?        // Avatar (JPEG, máx 200KB)
    let defaultRole: RideRole   // .leader, .rider, .sweeper
    let createdAt: Date
}

enum RideRole: String, Codable, CaseIterable {
    case leader     // Cria passeios, controla a rota
    case rider      // Rider comum
    case sweeper    // Varredor (último da fila)
}
```

---

## 2. Passeio (local SQLite + transmitido via mesh)

```swift
struct Ride: Codable {
    let id: String              // UUID
    let name: String            // "Serra do Rio do Rastro"
    let leaderId: String        // RiderProfile.id
    let leaderName: String      // Desnormalizado
    let status: RideStatus
    let createdAt: Date
    let finishedAt: Date?
    var currentRouteId: String? // ID da rota ativa (se houver)
}

enum RideStatus: String, Codable {
    case active
    case paused     // Parada (posto, lanche)
    case finished
}
```

---

## 3. Sala (Room) — Comunicação

```swift
struct Room: Codable, Identifiable {
    let id: String              // UUID
    let rideId: String          // Passeio a que pertence
    let name: String            // "Geral", "Líder+Varredor", "Pedro+Ana"
    let createdBy: String       // RiderProfile.id de quem criou
    let creatorName: String     // Desnormalizado
    let createdAt: Date
    let type: RoomType
    let isPrivate: Bool
    var members: [String]       // RiderProfile.ids
    var isActive: Bool          // false = fechada
}

enum RoomType: String, Codable, CaseIterable {
    case general        // Automática, todos dentro, não sai, não fecha
    case voice          // Voz ao vivo entre membros
    case messaging      // Só mensagens de áudio assíncronas
    case direct         // Conversa privada entre 2 riders
}

// Sala padrão criada automaticamente com o passeio:
extension Room {
    static func generalRoom(rideId: String, leaderId: String, leaderName: String) -> Room {
        Room(
            id: "\(rideId)-general",
            rideId: rideId,
            name: "Geral",
            createdBy: leaderId,
            creatorName: leaderName,
            createdAt: Date(),
            type: .general,
            isPrivate: false,
            members: [leaderId],
            isActive: true
        )
    }

    static func alertsRoom(rideId: String) -> Room {
        Room(
            id: "\(rideId)-alerts",
            rideId: rideId,
            name: "Alertas",
            createdBy: "system",
            creatorName: "WAWA",
            createdAt: Date(),
            type: .messaging,
            isPrivate: false,
            members: [],  // Todos os riders do passeio
            isActive: true
        )
    }
}
```

---

## 4. Mensagem de Áudio Assíncrona

```swift
struct VoiceMessage: Codable, Identifiable {
    let id: String              // UUID
    let roomId: String          // Sala de destino
    let rideId: String          // Passeio
    let fromRiderId: String     // Quem enviou
    let fromRiderName: String   // Desnormalizado
    let sentAt: Date
    let duration: TimeInterval  // Segundos de áudio
    let audioData: Data         // Opus comprimido (~4KB/s)
    var deliveredTo: [String]   // RiderProfile.ids que já receberam
    var playedBy: [String]      // RiderProfile.ids que já ouviram
}

// Métricas típicas:
// 5s de áudio → ~20KB (Opus 32kbps)
// 30s de áudio → ~120KB
// 60s de áudio → ~240KB (máximo)
```

---

## 5. Rota

```swift
struct Route: Codable, Identifiable {
    let id: String              // UUID
    let name: String            // "Serra do Rio do Rastro — Trecho 1"
    let createdBy: String       // RiderProfile.id
    let createdAt: Date
    let source: RouteSource     // Como foi criada
    let waypoints: [RouteWaypoint]
    let simplifiedTrack: [RoutePoint]?  // Track simplificado (Ramer-Douglas-Peucker)
    let totalDistance: Double?  // Metros (calculado)
    let estimatedDuration: TimeInterval?  // Segundos (calculado)
    let elevationGain: Double?  // Metros (calculado)
    let tags: [String]          // "serra", "asfalto", "off-road"
}

struct RouteWaypoint: Codable, Identifiable {
    let id: String              // UUID
    let latitude: Double
    let longitude: Double
    let order: Int              // Sequência (0, 1, 2, ...)
    let name: String?           // "Posto Ipiranga", "Mirante"
    let type: WaypointType      // .start, .waypoint, .stop, .finish
    let isStop: Bool            // true = parada planejada
    let stopDuration: TimeInterval?  // Minutos estimados de parada
}

enum WaypointType: String, Codable {
    case start      // Ponto de partida
    case waypoint   // Ponto intermediário
    case stop       // Parada (posto, mirante, lanche)
    case finish     // Destino final
}

enum RouteSource: String, Codable {
    case recorded       // Gravada ao vivo (track do líder)
    case drawn         // Desenhada no mapa (waypoints manuais)
    case imported       // .GPX importado
    case shared         // Recebida de outro rider via mesh
}

struct RoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let order: Int
    let timestamp: Date?
    let speed: Double?       // km/h
    let altitude: Double?    // Metros
}
```

---

## 6. Rider no Passeio

```swift
struct RideParticipant: Codable {
    let riderId: String
    let name: String
    let bikeModel: String?
    let role: RideRole
    var isConnected: Bool           // Tem heartbeat recente?
    var lastSeen: Date              // Último heartbeat

    // Posição atual
    var latitude: Double
    var longitude: Double
    var speed: Double               // km/h
    var heading: Double             // 0-360
    var altitude: Double?
    var locationTimestamp: Date

    var isMoving: Bool              // speed > 5 km/h
    var batteryLevel: Float?        // 0.0-1.0
    var offlineSince: Date?         // nil = online. Se offline, quando começou

    // Salas em que está
    var activeRooms: [String]       // Room.ids
}
```

---

## 7. Alerta de Perigo

```swift
struct HazardAlert: Codable, Identifiable {
    let id: String              // UUID
    let type: HazardType
    let latitude: Double
    let longitude: Double
    let reportedBy: String      // Nome
    let reportedById: String    // RiderProfile.id
    let createdAt: Date
    let expiresAt: Date         // Expiração automática
    var confirmedBy: [String]   // Names que confirmaram
    var clearedBy: [String]     // Names que limparam ("já passou")
    var isActive: Bool { !isExpired && confirmedBy.count >= clearedBy.count }

    var isExpired: Bool { Date() > expiresAt }
    var confidence: Int { 1 + confirmedBy.count - clearedBy.count }
}

enum HazardType: String, Codable, CaseIterable {
    case radar, pothole, police, oil, animal, gravel, accident, other

    var ttlMinutes: Int {
        switch self {
        case .radar: 30; case .pothole: 30; case .police: 15
        case .oil: 60; case .animal: 15; case .gravel: 30
        case .accident: 60; case .other: 15
        }
    }

    var voiceDescription: String {
        switch self {
        case .radar: "Radar"; case .pothole: "Buraco na pista"
        case .police: "Polícia"; case .oil: "Óleo na pista"
        case .animal: "Animal na pista"; case .gravel: "Cascalho solto"
        case .accident: "Acidente"; case .other: "Perigo"
        }
    }
}
```

---

## 8. Payload Mesh (envelope P2P)

```swift
struct MeshPayload: Codable {
    let id: String              // UUID (dedup)
    let type: MeshPayloadType
    let senderId: String
    let senderName: String
    let rideId: String
    let roomId: String?         // nil = mensagem do passeio. String = mensagem de sala
    let timestamp: Date
    var ttl: Int                // Saltos restantes
    let priority: MeshPriority
    let payload: Data           // JSON do payload específico
}

enum MeshPayloadType: String, Codable {
    // Posição
    case locationUpdate

    // Rota
    case routeCreated           // Nova rota compartilhada
    case routeWaypoint          // Waypoint individual
    case routeBatch             // Vários pontos de rota
    case routeShared            // Rota completa compartilhada entre riders

    // Sala
    case roomCreated            // Nova sala
    case roomClosed             // Sala fechada
    case roomJoin               // Rider entrou na sala
    case roomLeave              // Rider saiu da sala

    // Áudio
    case voiceLive              // Chunk de voz ao vivo (stream)
    case voiceMessage           // Mensagem de áudio assíncrona
    case voiceMessageAck        // Confirmação de entrega

    // Perigos
    case hazardAlert
    case hazardConfirm
    case hazardClear

    // Status
    case statusChange           // "Parei", "Preciso de ajuda", "Seguindo"
    case heartbeat
    case sosAlert
    case sosCancel

    // Passeio
    case rideInfo               // Metadados do passeio
    case joinRequest            // Entrar no passeio
    case joinAccept
    case leaveNotification
    case rideEnded
}

enum MeshPriority: Int, Codable, Comparable {
    case critical = 0   // SOS, voz ao vivo, alerta de perigo
    case high = 1       // Status, sala criar/fechar, voice message
    case normal = 2     // Posição, heartbeat, join/leave sala
    case low = 3        // Rota batch, rota compartilhada

    static func < (lhs: MeshPriority, rhs: MeshPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

---

## 9. Payloads específicos

```swift
// Posição
struct LocationPayload: Codable {
    let lat: Double; let lng: Double
    let speed: Double; let heading: Double
    let altitude: Double?
    let batteryLevel: Float?
}

// Rota completa (compartilhamento)
struct RoutePayload: Codable {
    let routeId: String
    let routeName: String
    let source: RouteSource
    let waypoints: [CodableWaypoint]
    let totalDistance: Double?
}

struct CodableWaypoint: Codable {
    let lat: Double; let lng: Double; let order: Int
    let name: String?; let isStop: Bool
}

// Sala
struct RoomPayload: Codable {
    let room: Room              // Room completa
}

struct RoomMembershipPayload: Codable {
    let roomId: String
    let riderId: String
    let riderName: String
}

// Mensagem de voz assíncrona
struct VoiceMessagePayload: Codable {
    let messageId: String
    let roomId: String
    let fromRiderId: String
    let fromRiderName: String
    let sentAt: Date
    let duration: TimeInterval
    let audioData: Data         // Opus comprimido
    // Métricas típicas:
    // 5s: ~20KB | 30s: ~120KB | 60s: ~240KB
}

// SOS
struct SOSPayload: Codable {
    let lat: Double; let lng: Double
    let reason: String?         // "Acidente", "Pane", "Sem combustível"
    let batteryLevel: Float?
}

// Status
struct StatusPayload: Codable {
    let status: String          // "stopped", "moving", "need_help", "ok"
    let lat: Double; let lng: Double
}
```

---

## 10. Fila Offline (SQLite)

```sql
CREATE TABLE offline_queue (
    id TEXT PRIMARY KEY,
    ride_id TEXT NOT NULL,
    room_id TEXT,
    type TEXT NOT NULL,           -- MeshPayloadType
    priority INTEGER NOT NULL,
    payload_json TEXT NOT NULL,   -- MeshPayload completo serializado
    created_at REAL NOT NULL,
    expires_at REAL NOT NULL,
    ttl INTEGER NOT NULL DEFAULT 3,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 10,
    persist_until_ack INTEGER DEFAULT 0,  -- BOOL: críticos = 1
    last_error TEXT,
    last_retry_at REAL
);

CREATE INDEX idx_queue_fetch
    ON offline_queue(persist_until_ack DESC, priority ASC, created_at ASC);
CREATE INDEX idx_queue_expiry ON offline_queue(expires_at);
```

---

## 11. Armazenamento local (SQLite)

```sql
-- Passeios
CREATE TABLE rides (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    leader_id TEXT NOT NULL,
    leader_name TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at REAL NOT NULL,
    finished_at REAL,
    current_route_id TEXT
);

-- Rotas salvas
CREATE TABLE routes (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at REAL NOT NULL,
    source TEXT NOT NULL,
    waypoints_json TEXT NOT NULL,  -- [CodableWaypoint] serializado
    track_json TEXT,               -- [RoutePoint] serializado (track completo)
    simplified_track_json TEXT,    -- [RoutePoint] serializado (simplificado)
    total_distance REAL,
    estimated_duration REAL,
    elevation_gain REAL,
    tags TEXT                      -- JSON array de strings
);

-- Salas (do passeio atual — volátil)
CREATE TABLE rooms (
    id TEXT PRIMARY KEY,
    ride_id TEXT NOT NULL,
    name TEXT NOT NULL,
    created_by TEXT NOT NULL,
    creator_name TEXT NOT NULL,
    created_at REAL NOT NULL,
    type TEXT NOT NULL,
    is_private INTEGER NOT NULL,
    members_json TEXT NOT NULL,    -- [String] rider ids
    is_active INTEGER NOT NULL DEFAULT 1
);

-- Mensagens de voz (cache local)
CREATE TABLE voice_messages (
    id TEXT PRIMARY KEY,
    room_id TEXT NOT NULL,
    ride_id TEXT NOT NULL,
    from_rider_id TEXT NOT NULL,
    from_rider_name TEXT NOT NULL,
    sent_at REAL NOT NULL,
    duration REAL NOT NULL,
    audio_data BLOB NOT NULL,
    played INTEGER NOT NULL DEFAULT 0
);

-- Histórico de passeios (resumo)
CREATE TABLE ride_summaries (
    ride_id TEXT PRIMARY KEY,
    ride_name TEXT NOT NULL,
    started_at REAL NOT NULL,
    finished_at REAL NOT NULL,
    total_distance REAL,
    total_duration REAL,
    max_altitude REAL,
    avg_speed REAL,
    rider_count INTEGER,
    stop_count INTEGER,
    alert_count INTEGER,
    route_id TEXT,
    stats_json TEXT               -- Estatísticas detalhadas
);

-- Dedup de mensagens mesh
CREATE TABLE mesh_dedup (
    message_id TEXT PRIMARY KEY,
    received_at REAL NOT NULL
);
-- Cleanup: DELETE WHERE received_at < now - 300 (5 min)
```

---

## 12. Resumo das diferenças v1 → v2

```
REMOVIDO (Firebase):         ADICIONADO (local/mesh):
  rides/{id}/info/    →       rides (SQLite, local)
  rides/{id}/riders/  →       RideParticipant em memória + mesh
  rides/{id}/alerts/  →       HazardAlert em memória + mesh
  rides/{id}/route/   →       routes (SQLite, local)
  rides/{id}/signaling/→      N/A (sem WebRTC)

NOVOS:
  rooms (SQLite)              — Salas de comunicação
  voice_messages (SQLite)     — Mensagens de áudio assíncronas
  mesh_dedup (SQLite)         — Dedup de mensagens P2P
  routes (SQLite ampliado)     — Waypoints, tags, source, track
```
