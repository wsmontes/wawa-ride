# WAWA Ride — Estratégia de Conectividade (v2)

> **Zero servidor. Tudo é P2P. Internet é acelerador, não requisito.**

## 1. Escada de degradação (v2)

```
NÍVEL 1 — FULL MESH (todos conectados via WiFi Direct ou BLE):
  ✅ Posições: < 1s
  ✅ Voz ao vivo: < 200ms
  ✅ Mensagens assíncronas: < 1s
  ✅ Rotas, salas, alertas: < 1s
  Experiência: PERFEITA. App funciona 100%.

NÍVEL 2 — MESH PARCIAL (alguns peers via BLE, outros via relay):
  ✅ Posições: 1-5s (depende de saltos de relay)
  ✅ Voz ao vivo: < 2s (relay)
  ✅ Mensagens assíncronas: 1-10s
  ✅ Tudo funciona, só mais lento.
  Experiência: BOA. Relay store-and-forward no fundo.

NÍVEL 3 — INTERNET DISPONÍVEL (WiFi infra relay do MC):
  ✅ MultipeerConnectivity automaticamente usa a internet como relay
  ✅ Se ambos têm internet: performance similar ao Full Mesh
  ✅ Se apenas um tem: conexão pode ser estabelecida via infra
  ✅ App NÃO precisa saber disso. MC resolve.
  Experiência: PERFEITA (transparente pro app).

NÍVEL 4 — TOTALMENTE OFFLINE (sem mesh, sem internet):
  ❌ Sem comunicação com outros riders
  ✅ GPS continua funcionando (localização própria)
  ✅ OfflineQueue acumula mensagens
  ✅ Rota continua sendo gravada localmente
  ✅ TTS e comandos de voz locais continuam
  Experiência: DEGRADADA. Mas o app não crasha. Retoma sozinho.

NÍVEL 5 — RECONEXÃO:
  ✅ OfflineQueue drena (prioridade: critical → high → normal → low)
  ✅ Estado completo é sincronizado
  ✅ TTS: "Conexão restaurada. 5 mensagens pendentes."
```

---

## 2. TransportManager (v2)

```swift
class TransportManager {
    static let shared = TransportManager()
    let mesh: MeshService            // ÚNICO transporte
    let queue: OfflineQueue          // SQLite
    let connectivity: ConnectivityMonitor

    // Como NÃO tem Firebase, o mesh É o transporte.
    // Internet acelera o mesh automaticamente (MC WiFi infra).

    func send(_ payload: MeshPayload) {
        let strategy = bestStrategy(for: payload.priority)

        switch strategy {
        case .meshDirect:
            // Envia diretamente pros peers conectados
            mesh.send(payload)

        case .meshWithQueue:
            // Envia + persiste pra garantir
            mesh.send(payload)
            queue.enqueue(payload)

        case .queueOnly:
            // Só persiste (offline total)
            queue.enqueue(payload)
        }
    }

    func bestStrategy(for priority: MeshPriority) -> TransportStrategy {
        let hasPeers = mesh.hasConnectedPeers

        switch priority {
        case .critical:
            // Crítico: mesh + fila sempre (redundância)
            return hasPeers ? .meshWithQueue : .queueOnly

        case .high:
            return hasPeers ? .meshWithQueue : .queueOnly

        case .normal:
            return hasPeers ? .meshDirect : .queueOnly

        case .low:
            // Baixa prioridade: só mesh direto, sem fila
            // (dados que envelhecem rápido, como posição antiga)
            return hasPeers ? .meshDirect : .none
        }
    }
}

enum TransportStrategy {
    case meshDirect      // Envia agora via mesh
    case meshWithQueue   // Envia + persiste em fila
    case queueOnly       // Só persiste (offline)
    case none            // Descarta (dados expirados/irrelevantes)
}
```

---

## 3. ConnectivityMonitor

```swift
import Network

class ConnectivityMonitor: ObservableObject {
    static let shared = ConnectivityMonitor()

    private let monitor = NWPathMonitor()
    @Published var hasInternet = false
    @Published var connectionType = "unknown"

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.hasInternet = path.status == .satisfied
                self?.connectionType = path.usesInterfaceType(.wifi) ? "wifi"
                    : path.usesInterfaceType(.cellular) ? "cellular"
                    : "other"

                // Notifica mudança
                // (MultipeerConnectivity já usa isso automaticamente)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.wawa.connectivity"))
    }
}
```

---

## 4. OfflineQueue (v2)

```
FUNCIONAMENTO:

Enfileirar:
  1. Serializa MeshPayload → JSON
  2. Insere no SQLite
  3. Máximo 1000 mensagens. Se exceder:
     - Remove 100 mensagens mais antigas de menor prioridade
  4. Mensagens críticas (SOS, hazard): flag persist_until_ack = true
     (NUNCA são removidas automaticamente)

Desenfileirar (quando mesh reconecta):
  1. Ordena: persist_until_ack DESC, priority ASC, created_at ASC
  2. Envia em lotes de 30 (não sobrecarrega o MC)
  3. Sucesso → remove. Falha → retry_count++, backoff.
  4. Máximo de retries: 10 (critical), 5 (high), 3 (normal), 1 (low)

Expirar (background timer a cada 60s):
  - Mensagens expiram por idade:
    critical: 1h, high: 30min, normal: 10min, low: 5min
  - Mensagens expiram por TTL (saltos) também:
    critical: 15, high: 8, normal: 5, low: 3
  - Expiradas → removidas da fila

ESTRATÉGIA DE DRENAGEM:
  - Quando mesh reconecta: drena IMEDIATAMENTE
  - Lotes pequenos (30) pra manter latência boa de voz
  - Intervalo entre lotes: 200ms
  - Voz ao vivo SEMPRE tem prioridade sobre drenagem
```

---

## 5. Cenários de falha (v2)

```
CENÁRIO 1: Líder e rider em alcance BLE, sem internet
  → Perfeito. Mesh direto. Latência < 200ms.

CENÁRIO 2: Grupo espalhado (L ↔ R2 ↔ R3 ↔ V), sem internet
  → Mesh store-and-forward. Latência 1-5s por salto.
  → Funciona. Só perde qualidade de voz ao vivo.

CENÁRIO 3: Líder e rider longe, ambos COM internet
  → MC automaticamente usa WiFi infra como relay.
  → Latência similar a P2P direto (< 500ms).
  → Transparente pro app.

CENÁRIO 4: Rider offline total (sem mesh, sem internet)
  → OfflineQueue acumula tudo.
  → GPS continua.
  → TTS avisa: "Sem conexão há 1 minuto" (depois 2, 5, 10...)
  → Quando reconectar: drena fila, sincroniza estado.

CENÁRIO 5: Líder cria sala privada, rider offline
  → Sala criada no mesh local.
  → roomCreated fica na OfflineQueue do líder.
  → Quando rider reconectar: recebe a sala (ainda ativa? sim → aparece).

CENÁRIO 6: Grupo se divide em duas ilhas
  → Ilha A e Ilha B operam independentes.
  → Cada ilha tem visão parcial (só vê riders na sua ilha).
  → Quando ilhas se aproximam: mesh reconecta, sincroniza estado completo.
  → Merge: timestamp mais recente ganha (LWW).
```

---

## 6. Adaptive GPS Rate (v2)

```swift
func calculateInterval(
    speed: Double,
    headingDelta: Double,
    offRouteDistance: Double,
    batteryLevel: Float,
    hasMeshPeers: Bool
) -> TimeInterval {
    guard hasMeshPeers else {
        // Offline total: grava localmente a cada 5s (pra rota)
        return 5.0
    }

    var interval: TimeInterval = 3.0  // Default

    if headingDelta > 10 { interval = 1.0 }
    else if headingDelta > 5 { interval = 1.5 }

    if speed > 80 { interval = min(interval, 2.0) }
    if offRouteDistance > 20 { interval = min(interval, 1.0) }
    if speed < 5 { interval = max(interval, 10.0) }
    if batteryLevel < 0.2 { interval *= 2.0 }

    return interval
}
```

---

## 7. Background e Persistência

Mesma estratégia da v1: location + BLE + audio background modes.  
A diferença é que **não tem Firebase listener** — toda sincronização passa pelo mesh.

```
APP EM BACKGROUND:
  - MC mantém BLE advertising + browsing (bg modes)
  - Conexões existentes MANTIDAS
  - OfflineQueue continua acumulando se necessário

APP SUSPENSO (iOS kill):
  - Ao acordar (location update ou BGTaskScheduler):
    1. Reativa MC (advertising + browsing)
    2. Tenta reconectar a peers conhecidos
    3. Se reconectar: drena OfflineQueue
    4. Se não: continua acumulando
```

---

## 8. Resumo — o que mudou da v1 pra v2

```
REMOVIDO:
  ❌ Firebase Firestore
  ❌ GoogleWebRTC
  ❌ Servidor TURN/STUN
  ❌ Signaling via Firestore
  ❌ Cloud sync
  ❌ Autenticação

ADICIONADO:
  ✅ MC Streams pra voz ao vivo (substitui WebRTC)
  ✅ Opus codec em software
  ✅ OfflineQueue mais robusto (única persistência de mensagens)
  ✅ TransportManager simplificado (só mesh)
  ✅ Relay via WiFi infra (automático, via MC)

MANTIDO:
  ✅ MultipeerConnectivity
  ✅ Store-and-forward com TTL
  ✅ Dedup
  ✅ Adaptive GPS
  ✅ Background BLE + location
```
