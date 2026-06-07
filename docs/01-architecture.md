# WAWA Ride — Arquitetura do Sistema (v2)

**Versão:** 0.2 — MVP Zero-Server
**Plataforma:** iOS 17+
**Linguagem:** Swift 5.9+
**Dependência externa:** Nenhuma. O app funciona completamente offline, P2P.

---

## 1. Princípio fundamental

> O WAWA Ride não depende de servidor, internet, login, ou qualquer infraestrutura externa para funcionar. Toda comunicação é P2P via MultipeerConnectivity. Se houver internet, ela é usada como acelerador (relay de pacotes), nunca como requisito.

```
┌────────────────────────────────────────────────────────────┐
│                    WAWA Ride — Zero Server                  │
│                                                             │
│   SEM:  Firebase  •  Auth  •  TURN  •  STUN  •  API REST   │
│   TEM:  MultipeerConnectivity  •  SQLite local  •  MapKit  │
│                                                             │
│   Internet (se disponível): acelera o mesh (WiFi relay)     │
│   Internet (se indisponível): app funciona 100% normal      │
└────────────────────────────────────────────────────────────┘
```

---

## 2. Stack tecnológica (v2)

| Componente | Tecnologia | Por que |
|-----------|-----------|---------|
| UI | SwiftUI + UIKit | SwiftUI pra telas, UIKit pro MKMapView |
| Mapa | MapKit nativo | Gratuito, cache offline, sem limite |
| GPS | CoreLocation | Melhor stack iOS, background mode aprovado |
| **Transporte (único)** | **MultipeerConnectivity** | BLE + WiFi Direct + WiFi infra. Tudo P2P. |
| TTS | AVSpeechSynthesizer | Nativo, pt-BR, zero dependência |
| Comandos de voz | SFSpeechRecognizer | On-device, offline, pt-BR |
| Voz ao vivo (P2P) | MCSession streams | Direto entre peers, codec Opus |
| Voz assíncrona | MeshPayload de áudio | Grava → Opus → envia via mesh → toca |
| Armazenamento | SQLite (GRDB.swift) | Rotas, salas, mensagens, histórico |
| Mapas offline | MapKit cache | Download de região antes do passeio |

**Dependências SPM:**
```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "6.0"),
    // Só GRDB. Nada de Firebase, nada de WebRTC.
]
```

---

## 3. Estrutura de diretórios

```
wawa-ride/
├── App/
│   ├── WAWARideApp.swift
│   ├── AppDelegate.swift
│   └── Info.plist
│
├── Models/
│   ├── RiderProfile.swift        # Perfil local
│   ├── Ride.swift                # Passeio
│   ├── Room.swift                # Sala de comunicação
│   ├── VoiceMessage.swift        # Mensagem de áudio assíncrona
│   ├── Route.swift               # Rota (waypoints + track)
│   ├── RouteWaypoint.swift       # Ponto de rota planejado
│   ├── HazardAlert.swift         # Alerta de perigo
│   ├── MeshPayload.swift         # Payload P2P
│   └── RideSummary.swift         # Resumo pós-passeio
│
├── Services/
│   ├── Location/
│   │   └── LocationService.swift        # CoreLocation tracking
│   │
│   ├── Mesh/
│   │   ├── MeshService.swift            # Orquestrador P2P
│   │   ├── MeshAdvertiser.swift         # Anuncia (BLE)
│   │   ├── MeshBrowser.swift            # Descobre (BLE)
│   │   ├── MeshSession.swift            # MCSession, conexões
│   │   ├── MeshRelay.swift              # Store-and-forward, TTL
│   │   └── MeshDedup.swift             # Dedup de mensagens
│   │
│   ├── Audio/
│   │   ├── VoiceAssistant.swift         # TTS — app fala
│   │   ├── VoiceCommandListener.swift  # Comandos de voz
│   │   ├── VoiceChatService.swift       # Voz ao vivo (MCSession stream)
│   │   └── VoiceMessageService.swift    # Áudio assíncrono (grava → envia)
│   │
│   ├── Route/
│   │   ├── RouteService.swift           # Criação, gravação, navegação
│   │   └── RouteNavigationEngine.swift   # "Curva em 200m", desvio da rota
│   │
│   └── Storage/
│       └── LocalStore.swift             # SQLite (GRDB) — tudo local
│
├── Rooms/
│   ├── RoomService.swift                # Criar/gerenciar salas
│   ├── RoomMemberService.swift          # Entrada/saída de salas
│   └── RoomMessageRouter.swift          # Roteamento de mensagens entre salas
│
├── Views/
│   ├── ProfileSetupView.swift
│   ├── JoinRideView.swift
│   ├── LiveMapView.swift               # Tela principal do mapa
│   ├── RouteCreationView.swift         # Criar/editar rota no mapa
│   ├── RoomListView.swift              # Lista de salas do passeio
│   ├── VoiceMessageView.swift          # Gravação/reprodução de áudio
│   ├── HazardMenuView.swift            # Menu radial de perigos
│   ├── PTTButton.swift                  # Push-to-talk
│   └── RideSummaryView.swift
│
├── ViewModels/ (MVVM, um por view)
│
├── Extensions/
│   ├── CLLocation+Extensions.swift
│   ├── MKMapView+Extensions.swift
│   └── AVAudioSession+Extensions.swift
│
└── Resources/
    └── Assets.xcassets
```

---

## 4. Como tudo funciona sem servidor

### 4.1 Descoberta → Conexão → Comunicação

```
LÍDER                                RIDER
  │                                    │
  │ 1. Cria Ride + Sala "Geral"        │
  │    Anuncia via BLE:                │
  │    rideId, nome, líder, salas      │
  │                                    │
  │                                    │ 2. Abre app, detecta anúncio
  │                                    │    Vê: "Wagner — Serra (3 riders)"
  │                                    │
  │                                    │ 3. Aperta ENTRAR
  │                                    │
  │ 4. MCSession estabelecida          │
  │    ◄════ P2P CONNECTED ════►      │
  │                                    │
  │ 5. Envia estado completo:          │
  │    - Rota atual                    │
  │    - Posições de todos             │
  │    - Lista de salas                │
  │    - Alertas ativos                │
  │                                    │
  │                                    │ 6. Recebe estado → atualiza mapa
  │                                    │    Entra automaticamente na "Geral"
  │                                    │    Vê outras salas disponíveis
  │                                    │
  │ 7. Broadcast: "Pedro entrou"       │
  │    (TTS em todos os dispositivos)  │
  └────────────────────────────────────┘
```

### 4.2 Internet como acelerador

```
SEM INTERNET:
  [L] ←──BLE/WiFi Direct──→ [R2] ←──BLE/WiFi Direct──→ [R3]
   │                                                      │
   └── Dados trafegam exclusivamente via mesh P2P ────────┘
   Alcance: ~50m (BLE) a ~200m (WiFi Direct, linha de visada)
   Fora de alcance: store-and-forward (R2 carrega de L pra R3)

COM INTERNET (alguns ou todos):
  [L] ←──WiFi infra──→ 🌐 Internet 🌐 ←──WiFi infra──→ [R3]
   │                                                      │
   └── MultipeerConnectivity usa WiFi infra automaticamente ─┘
   Alcance: ILIMITADO (enquanto ambos tiverem internet)
   Mas: NÃO usa servidor externo. É P2P sobre IP.
   Isso é automático no MultipeerConnectivity. Zero config.
```

### 4.3 Persistência: tudo local

```
O QUE É SALVO (SQLite local):
  ✅ Perfil do piloto
  ✅ Histórico de passeios (resumo, stats, rota)
  ✅ Rotas salvas (criadas ou recebidas)
  ✅ Salas e mensagens do passeio atual
  ✅ Fila offline para retransmissão

O QUE NÃO É SALVO:
  ❌ Nada em servidor. Zero. Não existe servidor.

COMPARTILHAR ROTA:
  - Exportar .GPX → Share Sheet (AirDrop, WhatsApp, etc)
  - Enviar via mesh pra outro rider (durante o passeio)
  - Rider pode importar .GPX de outros apps
```

---

## 5. Arquitetura de Salas (Rooms)

### 5.1 Conceito

```
PASSEIO "Serra do Rio do Rastro"
│
├── 🏠 Geral (automática, todos)
│   ├── Voz ao vivo (walkie-talkie do grupo)
│   └── Mensagens de áudio assíncronas
│
├── 🔒 Líder+Varredor (criada pelo líder)
│   ├── Membros: Wagner, João
│   └── Coordenação de paradas, ritmo
│
├── 💬 Pedro+Ana (criada pelo Pedro)
│   ├── Membros: Pedro, Ana
│   └── Conversa privada entre os dois
│
└── 📍 Alertas (automática, todos, só leitura)
    └── Notificações de perigo, SOS, status
```

### 5.2 Modelo de Sala

```swift
struct Room: Codable {
    let id: String              // UUID
    let rideId: String
    let name: String            // "Geral", "Líder+Varredor", "Pedro+Ana"
    let createdBy: String       // RiderProfile.id
    let createdAt: Date
    let type: RoomType
    let members: [String]       // RiderProfile.ids
    let isPrivate: Bool         // false = visível pra todos, qualquer um entra
                                // true = só membros veem/entram
}

enum RoomType: String, Codable {
    case general        // Sala automática do passeio. Todos dentro. Não sai.
    case voice          // Sala de voz ao vivo (walkie-talkie privado)
    case messaging      // Sala de mensagens de áudio assíncronas
    case alerts         // Alertas do sistema (perigo, SOS) — automática
    case direct         // Conversa direta entre 2 riders
}
```

### 5.3 Ciclo de vida da sala

```
CRIAR (qualquer rider):
  1. Rider aperta "+" na lista de salas
  2. Escolhe nome + membros (da lista de riders do passeio)
  3. App cria Room → envia via mesh (priority: high, TTL: 10)
  4. Membros recebem → sala aparece na lista com badge "Nova"
  5. Não-membros não veem (se isPrivate = true)

ENTRAR (sala pública):
  1. Rider vê sala na lista → aperta → entra
  2. App envia joinRoom via mesh
  3. Membro收到 → rider aparece na lista de membros

SAIR (sala não-Geral):
  1. Rider aperta "Sair da sala"
  2. App envia leaveRoom via mesh
  3. Se sala ficou vazia → removida (quem criou pode recriar)

FECHAR (criador):
  1. Criador aperta "Fechar sala"
  2. App envia roomClosed via mesh
  3. Sala desaparece pra todos
```

### 5.4 Áudio em salas

```
SALA "GERAL" (voz ao vivo):
  - Walkie-talkie: PTT aberto → áudio vai pra todos no passeio
  - Transporte: MCSession stream (prioridade máxima)
  - Fora de alcance: chunks de áudio via mesh relay (TTL alto)

SALA PRIVADA (voz ao vivo):
  - Walkie-talkie: PTT aberto → áudio só vai pros membros da sala
  - Transporte: MCSession stream direto pros membros
  - Membros fora de alcance: relay via mesh

MENSAGEM DE ÁUDIO ASSÍNCRONA (qualquer sala):
  - Grava → Comprime Opus → MeshPayload → transmite oportunístico
  - Receptor: notificação + badge na sala
  - Funciona offline: armazena e entrega quando o mesh alcançar
```

---

## 6. Arquitetura de Rotas

### 6.1 Modos de criação

```
MODO 1 — GRAVAR (ao vivo, MVP primário):
  Líder inicia gravação → cada ponto vira waypoint → polyline no mapa
  Pausar/retomar (parada pra lanche)
  Encerrar → simplificar (Ramer-Douglas-Peucker) → salvar

MODO 2 — DESENHAR (planejado, MVP):
  Líder coloca waypoints no mapa antes do passeio
  Long press no mapa → "Adicionar waypoint"
  Drag pra ajustar posição
  App calcula polyline entre waypoints (seguindo estradas? ou reta?)

MODO 3 — IMPORTAR (MVP):
  Abrir .GPX de outros apps (Rever, Calimoto, etc)
  Parse XML → extrai waypoints/track → importa como rota
```

### 6.2 Navegação

```
MODOS DE NAVEGAÇÃO:

  1. SEGUIR O LÍDER (default, MVP primário):
     - Rota = rastro ao vivo do líder
     - TTS: "Líder virou à direita na próxima" (baseado no track)
     - Indicador de desvio: 🟢🟡🔴 (distância da rota do líder)

  2. SEGUIR ROTA PLANEJADA:
     - Rota pré-definida carregada no mapa
     - TTS: "Curva à direita em 200m" (calculado pela geometria da rota)
     - Independe da posição do líder (útil se líder está longe)

  3. MODO LIVRE:
     - Sem rota ativa. Só vê pins dos riders no mapa.
     - Útil pra trechos urbanos, volta pra casa.

NAVEGAÇÃO POR APROXIMAÇÃO:
  - O app NÃO faz turn-by-turn tradicional (não tem dados de estrada)
  - O app detecta CURVAS na polyline e alerta com antecedência
  - Algoritmo: analisa ângulo entre segmentos consecutivos da rota
    • Ângulo < 15°: reta — sem alerta
    • Ângulo 15-45°: "Curva suave à direita em 200m"
    • Ângulo 45-90°: "Curva acentuada à direita em 150m"
    • Ângulo > 90°: "Curva fechada à direita em 100m"
  - Distância do alerta é proporcional à velocidade atual
```

### 6.3 Compartilhamento de rota

```
DURANTE O PASSEIO:
  - Líder compartilha rota → enviada via mesh pra todos
  - Rider pode "salvar rota" → guarda localmente pra usar depois
  - Rota é transmitida como RoutePayload (sequência de waypoints)

PÓS-PASSEIO:
  - Exportar .GPX → Share Sheet nativo (AirDrop, WhatsApp, Files, etc)
  - Enviar via mesh pra outro rider (se ainda conectados)
  - Salvar na biblioteca de rotas local

IMPORTAR:
  - "Abrir com..." de outros apps → WAWA Ride importa .GPX
  - Receber de outro rider via mesh → salva na biblioteca
  - A biblioteca de rotas é local (SQLite)
```

---

## 7. Fluxo de dados completo

### 7.1 O que trafega no mesh P2P

```
┌─────────────────────┬──────────┬──────────┬──────────────────────┐
│        Dado         │ Frequência│ Prioridade│        TTL          │
├─────────────────────┼──────────┼──────────┼──────────────────────┤
│ Posição GPS         │  1-3s    │ normal   │ 3 (envelhece rápido) │
│ Rota do líder       │  batch   │ low      │ 8 (atraso ok)        │
│ Alerta de perigo    │  evento  │ critical │ 10 (todos precisam)  │
│ SOS                 │  evento  │ critical │ 15 (máximo alcance)  │
│ Status (parou/anda) │  evento  │ high     │ 7                    │
│ Heartbeat            │  15-30s  │ normal   │ 1 (não retransmite) │
│ Sala — criar         │  evento  │ high     │ 10                   │
│ Sala — fechar        │  evento  │ high     │ 10                   │
│ Sala — membro entrou │  evento  │ normal   │ 5                    │
│ Mensagem áudio async │  evento  │ high     │ 10                   │
│ Voz ao vivo (stream) │  chunks  │ critical │ 3                    │
│ Rota compartilhada   │  evento  │ low      │ 8                    │
└─────────────────────┴──────────┴──────────┴──────────────────────┘
```

### 7.2 Cadeia de responsabilidade

```
Rider aperta PTT na sala "Geral":
  1. VoiceChatService.openChannel(room: "Geral")
  2. AudioSession configure(.walkieTalkie)
  3. Microfone: PCM 16kHz → Opus encode (32kbps)
  4. Chunks de 20ms → MeshPayload(type: voiceLive, roomId: "Geral")
  5. MeshService.send(payload, priority: .critical, ttl: 3)
  6. Peers conectados: MCSession stream direto
  7. Peers NÃO conectados: relay via store-and-forward (se houver caminho)
  8. Receptor: Opus decode → alto-falante/headset
  9. Se intercom detectado: NÃO toca voz do app (respeita intercom)

Rider envia mensagem de áudio na sala "Pedro+Ana":
  1. Rider aperta 🎙️ gravar → grava até soltar (máx 60s)
  2. Comprime: PCM → Opus (~40KB pra 10s)
  3. Cria VoiceMessage(id, roomId, from, timestamp, audioData)
  4. Envia via mesh: priority high, TTL 10
  5. Se offline: fica no OfflineQueue → transmite quando reconectar
  6. Destinatário: notificação na sala → badge "1"
  7. Destinatário aperta play → Opus decode → toca
```

---

## 8. Permissões necessárias (Info.plist)

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>WAWA Ride mostra sua posição no mapa do passeio, mesmo em segundo plano.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>WAWA Ride mostra sua posição no mapa do passeio.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
    <string>audio</string>
</array>

<key>NSMicrophoneUsageDescription</key>
<string>WAWA Ride usa o microfone para walkie-talkie, mensagens de voz e comandos de voz.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>WAWA Ride reconhece comandos de voz como "Ok moto, marcar radar".</string>

<key>NSBluetoothAlwaysUsageDescription</key>
<string>WAWA Ride usa Bluetooth para descobrir riders próximos sem precisar de internet.</string>
```

---

## 9. Resumo: o que mudou da v1 pra v2

| Aspecto | v1 | v2 |
|---------|----|----|
| Servidor | Firebase Firestore | **Nenhum** |
| Transporte primário | Firestore (4G) | **Mesh P2P** |
| Voice chat ao vivo | WebRTC + TURN | **MCSession stream** |
| Dependências | Firebase, WebRTC, GRDB | **Só GRDB** |
| Salas | Não tinha | **Sistema completo tipo Discord** |
| Mensagem de áudio | Não documentado | **Async completo: grava → Opus → mesh** |
| Rota | Só rastro ao vivo | **Criação, navegação, compartilhamento** |
| Persistência | Firestore + SQLite | **SQLite local apenas** |
