# WAWA Ride — Estratégia de Conectividade

## 1. O problema fundamental

Motos andam em lugares sem sinal. Ponto. Qualquer app de navegação em grupo que dependa exclusivamente de 4G vai falhar nos momentos mais importantes (serra, montanha, estrada rural).

A estratégia de conectividade do WAWA Ride é uma **escada de degradação controlada**:

```
TODAS AS CAMADAS DISPONÍVEIS:
  4G + Mesh + Queue   →  melhor experiência (redundante, baixa latência)

UMA CAMADA CAI:
  4G + Queue          →  4G voltou, drenando fila acumulada
  Mesh + Queue        →  sem 4G, P2P funcionando

TUDO OFFLINE:
  Queue               →  acumulando, nada transmite
                           Rider vê: últimos dados (opacidade reduzida)
                           TTS: "Sem sinal há 2 minutos"
                           Quando reconectar → drena fila por prioridade

RECONEXÃO:
  Queue drena         →  critical primeiro, depois high, normal, low
  Firebase sync       →  sobrescreve com dados mais recentes
  Conflito            →  timestamp mais recente ganha (last-write-wins)
```

---

## 2. TransportManager — o cérebro

```swift
class TransportManager {
    static let shared = TransportManager()

    let cloud: RideSyncService       // Firestore
    let mesh: MeshService            // MultipeerConnectivity
    let queue: OfflineQueue          // SQLite
    let connectivity: ConnectivityMonitor  // NWPathMonitor

    func send(location: LocationPayload) {
        let payload = MeshPayload(
            type: .locationUpdate,
            priority: .normal,
            ttl: 3,
            payload: location
        )

        send(payload, via: bestTransport(for: .normal))
    }

    func send(hazard: HazardAlertPayload) {
        let payload = MeshPayload(
            type: .hazardAlert,
            priority: .critical,
            ttl: 10,
            payload: hazard
        )

        // Crítico: tenta TODOS os canais simultaneamente
        send(payload, via: .all)
        queue.enqueue(payload)  // Garantia extra: escreve no disco
    }

    func send(_ payload: MeshPayload, via strategy: TransportStrategy) {
        switch strategy {
        case .cloudOnly:
            cloud.send(payload)

        case .meshOnly:
            mesh.send(payload)

        case .cloudPreferred:
            if connectivity.hasInternet {
                cloud.send(payload)
            } else {
                mesh.send(payload)
                queue.enqueue(payload)
            }

        case .meshPreferred:
            // Mesh tem latência menor quando disponível
            if mesh.hasConnectedPeers {
                mesh.send(payload)
                cloud.send(payload)  // Backup assíncrono
            } else if connectivity.hasInternet {
                cloud.send(payload)
            } else {
                queue.enqueue(payload)
            }

        case .all:
            // Crítico: dispara em todos os canais
            if connectivity.hasInternet { cloud.send(payload) }
            if mesh.hasConnectedPeers { mesh.send(payload) }
            queue.enqueue(payload)  // Sempre persiste crítico
        }
    }

    func bestTransport(for priority: MeshPriority) -> TransportStrategy {
        switch priority {
        case .critical:  return .all
        case .high:      return connectivity.hasInternet ? .cloudPreferred : .meshPreferred
        case .normal:    return connectivity.hasInternet ? .cloudOnly : .meshOnly
        case .low:       return .cloudOnly  // Só transmite se tiver 4G
        }
    }
}

enum TransportStrategy {
    case cloudOnly
    case meshOnly
    case cloudPreferred
    case meshPreferred
    case all
}
```

---

## 3. ConnectivityMonitor — detecção de estado

```swift
import Network

class ConnectivityMonitor: ObservableObject {
    static let shared = ConnectivityMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.wawa.connectivity")

    @Published var hasInternet = false
    @Published var connectionType: ConnectionType = .unknown
    @Published var isExpensive = false       // Cellular (não WiFi)
    @Published var isConstrained = false     // Low Data Mode

    enum ConnectionType {
        case wifi, cellular, wired, other, unknown
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.hasInternet = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained

                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .wired
                } else {
                    self?.connectionType = .other
                }

                // Notifica TransportManager pra reavaliar estratégia
                TransportManager.shared.onConnectivityChanged()
            }
        }
        monitor.start(queue: queue)
    }
}
```

---

## 4. OfflineQueue — o último recurso

### 4.1 Funcionamento

```
ENFILEIRAR:
  1. Serializa MeshPayload → JSON
  2. Insere no SQLite com prioridade + timestamp
  3. Se queue.count > 1000:
     - Remove 100 mensagens de menor prioridade mais antigas
  4. Se mensagem crítica: marca flag `persist_until_ack = true`

DESENFILEIRAR (quando reconectar):
  1. Ordena por: (flag persist_until_ack DESC, priority ASC, created_at ASC)
  2. Envia em lotes de 20 (não sobrecarrega o canal)
  3. Se sucesso: remove da fila
  4. Se falha: incrementa retry_count, agenda retry com backoff
  5. Se retry_count > max_retries: descarta (muito antiga)

EXPIRAR (background):
  - Timer a cada 60s
  - Remove mensagens expiradas por idade:
    critical: 1h, high: 30min, normal: 10min, low: 5min
  - Remove mensagens expiradas por TTL:
    critical: 15 saltos, high: 8, normal: 5, low: 3
    (TTL ainda importa mesmo offline — quando drenar, pode ser o último salto)
```

### 4.2 Esquema SQLite

```sql
CREATE TABLE offline_queue (
    id TEXT PRIMARY KEY,
    ride_id TEXT NOT NULL,
    type TEXT NOT NULL,           -- MeshPayloadType
    priority INTEGER NOT NULL,     -- 0=critical, 1=high, 2=normal, 3=low
    payload_json TEXT NOT NULL,
    created_at REAL NOT NULL,     -- CFAbsoluteTime (segundos desde 2001)
    expires_at REAL NOT NULL,
    ttl INTEGER NOT NULL DEFAULT 3,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 10,
    persist_until_ack INTEGER DEFAULT 0,  -- BOOL
    last_error TEXT,
    last_retry_at REAL
);

CREATE INDEX idx_queue_fetch
    ON offline_queue(persist_until_ack DESC, priority ASC, created_at ASC);

CREATE INDEX idx_queue_expiry
    ON offline_queue(expires_at);
```

---

## 5. Estratégia de Sincronização — Resolução de Conflitos

### 5.1 Modelo Last-Write-Wins (LWW)

```
Conflito típico:
  Rider A envia posição {lat: -28.1, lng: -49.4, ts: 10:00:05} via mesh
  Rider B recebe posição de A indiretamente, tenta sincronizar com Firebase
  Firebase já tem {lat: -28.0, lng: -49.3, ts: 10:00:02} (atrasado)

Resolução:
  Timestamp mais recente ganha.
  Firebase sobrescreve com ts: 10:00:05.
  Mesh payload com ts mais novo sobrescreve estado local.
```

### 5.2 Regras de merge por tipo de dado

```
POSIÇÃO GPS:
  - LWW por locationTimestamp
  - Se diferença < 1s: usa a que veio do mesh (latência menor)

ROTA DO LÍDER:
  - Append-only. Cada RoutePoint tem `order` monotônico.
  - Ao receber batch, insere pontos com order > último conhecido.
  - Não sobrescreve, não deleta.

ALERTAS DE PERIGO:
  - Criar: se alertId não existe localmente, cria.
  - Confirmar: append no array confirmedBy (sem duplicatas).
  - Limpar: append no array clearedBy (sem duplicatas).
  - Estado final: isActive = true se (confirmedBy.count > clearedBy.count) E não expirado.
  - Merges são CRDT-like (add-only sets).

STATUS DE RIDER:
  - LWW por locationTimestamp
  - Exceção: SOS é sticky. Se rider enviou SOS, mantém até cancelar explicitamente.
  - isConnected: qualquer heartbeat nos últimos 60s = true.
```

---

## 6. Heartbeat e Detecção de Ausência

```
FREQUÊNCIA DE HEARTBEAT:
  - 4G disponível: a cada 30s (Firestore write)
  - Só mesh: a cada 15s (BLE beacon)
  - Totalmente offline: não envia, mas armazena último estado

DETECÇÃO DE RIDER PERDIDO:
  0-30s:    Rider está online (último heartbeat recente)
  30-60s:   Rider está "lento" (pin fica amarelo)
  60-120s:  Rider está "ausente" (pin fica cinza)
  2-5min:   TTS: "Pedro está sem sinal há 2 minutos"
  5-15min:  Pin com opacidade 50%, congelado na última posição
  >15min:   Pin removido do mapa (rider considerado offline)
            MAS: rider ainda está no grupo (pode reaparecer)
            TTS: "Pedro está offline há 15 minutos"

RIDER RECONECTA:
  - Envia estado completo (posição atual + fila drenada)
  - Firebase sync sobrescreve estado
  - Pin volta ao normal
  - TTS: "Pedro reconectou"
```

---

## 7. Cenários de falha e recuperação

```
CENÁRIO 1: Líder perde 4G (serra, 15 minutos)
  - Mesh continua funcionando (se riders no alcance)
  - Rota do líder continua via mesh (store-and-forward)
  - Firebase fica desatualizado até 4G voltar
  - Quando 4G volta: drena rota completa + posições acumuladas
  - Riders fora do alcance do mesh (usando 4G): veem último estado
    congelado até líder reconectar ao Firebase

CENÁRIO 2: Rider fica totalmente offline (sem 4G + sem mesh)
  - Última posição congelada pros outros (opacidade reduzindo)
  - OfflineQueue acumula localmente
  - Quando reconectar (4G ou mesh):
    → Drena fila por prioridade
    → Sincroniza estado completo (posição atual + rota perdida + alertas)
    → Recebe tudo que perdeu (rota do líder, posições de outros, alertas)

CENÁRIO 3: Grupo inteiro offline
  - Se estão em alcance BLE (grupo compacto): mesh funciona, todos se veem
  - Se estão espalhados (>50m entre alguns): apenas vizinhos se veem
  - Store-and-forward propaga dados entre subgrupos
  - Quando primeiro rider pega 4G: Firestore sync dispara
  - Esse rider vira "ponte" — recebe do Firestore e propaga no mesh

CENÁRIO 4: Grupo se divide (ex: líder para, varredor continua)
  - Mesh mantém conexão entre subgrupos se alguém no meio fizer ponte
  - Se distância > 200m entre subgrupos: mesh quebra em duas ilhas
  - Cada ilha opera independente (vê os riders na sua ilha)
  - Quando ilhas se aproximam: mesh reconecta, sincroniza
  - Firebase (se algum rider de cada ilha tiver 4G): mantém visão global
```

---

## 8. Adaptive GPS Rate

```swift
class AdaptiveLocationRate {
    // Fatores que aumentam a frequência (mais updates):
    // - Curva (heading change > 10°/s)
    // - Velocidade alta (> 80 km/h)
    // - Rider está desviando da rota (> 20m)

    // Fatores que diminuem a frequência (menos updates):
    // - Reta (heading change < 3°/s)
    // - Parado (speed < 5 km/h)
    // - Bateria baixa (< 20%)
    // - Sem 4G + sem mesh (offline total — não adianta enviar)

    func calculateInterval(
        speed: Double,
        headingDelta: Double,
        offRouteDistance: Double,
        batteryLevel: Float,
        hasConnectivity: Bool
    ) -> TimeInterval {
        guard hasConnectivity else { return 30 }  // Offline total: 30s

        var interval: TimeInterval = 3.0  // Default

        // Curva: 1s
        if headingDelta > 10 { interval = 1.0 }
        else if headingDelta > 5 { interval = 1.5 }

        // Velocidade alta: 2s
        if speed > 80 { interval = min(interval, 2.0) }

        // Desviando da rota: 1s
        if offRouteDistance > 20 { interval = min(interval, 1.0) }

        // Parado há > 30s: 10s
        if speed < 5 { interval = max(interval, 10.0) }

        // Bateria baixa: dobra intervalo
        if batteryLevel < 0.2 { interval *= 2.0 }

        return interval
    }
}
```

---

## 9. Background e Persistência

### 9.1 Estados do app e impacto na conectividade

```
FOREGROUND ATIVO (tela ligada):
  ✅ GPS: 1-3s (adaptive)
  ✅ BLE: advertising + browsing ativos
  ✅ WiFi Direct: ativo (se peers)
  ✅ Firebase: listener ativo
  ✅ TTS: ativo

FOREGROUND INATIVO (tela desligada, app ainda ativo):
  ✅ GPS: 3-5s
  ✅ BLE: advertising + browsing (intervalo maior)
  ✅ Firebase: listener ativo
  ✅ TTS: ativo

BACKGROUND (app em segundo plano, location + BLE bg modes):
  ✅ GPS: 5-30s (iOS controla, mas .otherNavigation ajuda)
  ✅ BLE: advertising (periférico) + scanning (central) em background
  ⚠️ WiFi Direct: PODE cair (iOS pode desligar WiFi em bg)
  ⚠️ Firebase: listener PODE ser throttled pelo iOS
  ✅ TTS: ativo (audio bg mode)

SUSPENDED (iOS matou o app):
  ❌ Tudo offline
  ⚠️ BGTaskScheduler: acorda a cada ~15 min
  ⚠️ Location region monitoring: acorda se mover > 500m
```

### 9.2 Estratégia anti-kill

```swift
// Táticas pra iOS NÃO matar o app durante o passeio:
class AppKeepAlive {
    // 1. Conexão BLE ativa — iOS nunca mata app com BLE connection
    //    (ter pelo menos 1 peer conectado é a MELHOR defesa)
    func maintainBLEConnection() {
        // MultipeerConnectivity mantém isso automaticamente
        // Se tiver 0 peers, aumenta advertising intensity
    }

    // 2. Audio background mode — TTS frequente mantém app "vivo"
    func schedulePeriodicTTS() {
        // A cada ~5 minutos, fala algo leve se nada foi falado
        // "Todos conectados" (baixo volume) — suficiente pra iOS ver
        // que o app está "em uso" de áudio
    }

    // 3. beginBackgroundTask — 30 segundos extras pra salvar estado
    func onAppWillResignActive() {
        var taskId = UIApplication.shared.beginBackgroundTask {
            // Salva estado crítico (última posição, fila, etc)
            self.saveState()
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }

    // 4. BGTaskScheduler — último recurso
    func scheduleWakeup() {
        let request = BGAppRefreshTaskRequest(identifier: "com.wawa.keepalive")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
    }
}
```

---

## 10. Métricas de conectividade a monitorar

Durante o MVP, coletar (localmente, sem analytics server):

```
POR PASSEIO:
  - % tempo com 4G disponível
  - % tempo com mesh P2P ativo (peers conectados)
  - % tempo totalmente offline
  - Número de quedas de 4G
  - Número de desconexões do mesh
  - Tamanho médio da fila offline
  - Tempo máximo offline consecutivo
  - Latência média das mensagens (por canal)

Esses dados vão guiar ajustes nos TTLs, timeouts, e frequências.
```

---

## 11. Resumo: modos de operação

```
┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
│   Modo   │   4G     │   Mesh   │  Queue   │Latência  │Exp. visual│
├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤
│ Full     │    ✅    │    ✅    │  Vazia   │  < 1s    │ 🟢 Tudo  │
│ Cloud    │    ✅    │    ❌    │  Vazia   │  < 1s    │ 🟢 Tudo  │
│ Mesh     │    ❌    │    ✅    │  Drenando│  1-5s    │ 🔵 Mesh  │
│ Isolado  │    ❌    │    ❌    │  Enchendo│   ∞      │ 🔴 Off   │
│ Drenando │ Voltou  │    —     │  Drenando│  1-30s   │ 🟡 Sync  │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
```
