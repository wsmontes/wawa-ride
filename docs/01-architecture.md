# WAWA Ride — Arquitetura do Sistema

**Versão:** 0.1 — MVP
**Plataforma:** iOS 17+
**Linguagem:** Swift 5.9+
**UI:** SwiftUI (telas) + UIKit (MKMapView via UIViewRepresentable)

---

## 1. Visão geral

```
┌─────────────────────────────────────────────────────────────┐
│                        WAWA Ride                            │
├─────────────────────────────────────────────────────────────┤
│  Camada UI (SwiftUI)                                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ Profile  │ │  Join    │ │   Map    │ │  Ride Over   │  │
│  │  Setup   │ │  Ride    │ │  Live    │ │   Summary    │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Camada de Serviços                                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │Location  │ │  Mesh    │ │  Cloud   │ │    Audio     │  │
│  │Service   │ │ Service  │ │ Service  │ │   Service    │  │
│  │          │ │          │ │          │ │              │  │
│  │CoreLoc   │ │Multipeer │ │Firebase  │ │TTS+Voice+   │  │
│  │          │ │Connect.  │ │Firestore │ │WebRTC       │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Camada de Transporte                                       │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              HybridTransportManager                   │  │
│  │                                                      │  │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────────┐     │  │
│  │  │ Firebase │   │  Mesh    │   │   Offline    │     │  │
│  │  │ (4G)     │   │  (P2P)   │   │   Queue      │     │  │
│  │  │          │   │          │   │   (SQLite)   │     │  │
│  │  └──────────┘   └──────────┘   └──────────────┘     │  │
│  └──────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Camada de Dados                                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                   │
│  │ UserDef  │ │ SQLite   │ │ Firestore│                   │
│  │(profile) │ │(offline) │ │ (cloud) │                   │
│  └──────────┘ └──────────┘ └──────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Stack tecnológica e justificativas

| Componente | Tecnologia | Justificativa |
|-----------|-----------|---------------|
| UI Framework | SwiftUI + UIKit | SwiftUI pra telas simples (perfil, join, resumo). UIKit (MKMapView) pro mapa — SwiftUI Map não suporta annotations customizados com rotação (heading) e overlays complexos de forma estável. |
| Mapa | MapKit nativo | Gratuito até volumes enormes. Suporte nativo a cache offline, overlays, annotations customizados. Sem limite de MAU. |
| GPS | CoreLocation | Precisão configurável, background mode aprovado pra navegação, activity type `.otherNavigation` otimiza pra veículo. |
| Mesh P2P | MultipeerConnectivity | Apple nativo. Combina BLE discovery + WiFi Direct + infra WiFi automaticamente. Criptografia ponta-a-ponta. Mesmo stack do AirDrop. |
| Cloud Sync | Firebase Firestore | Snapshots em tempo real (< 1s). SDK iOS maduro. Offline persistence nativo. Escala a 10k writes/s. Setup em horas. |
| TTS | AVSpeechSynthesizer | Nativo, vozes em pt-BR, ducking de áudio, sem dependências. |
| Comandos de Voz | SFSpeechRecognizer | On-device (funciona offline), pt-BR suportado, sem custo. |
| Voice Chat (4G) | GoogleWebRTC | Codec Opus otimizado pra voz (aguenta 100-200kbps). ICE/STUN/TURN pra furar NAT. Padrão da indústria. |
| Voice Chat (P2P) | MultipeerConnectivity stream | Quando sem 4G, voz vai direto via WiFi Direct/Bluetooth entre os peers conectados no mesh. |
| Armazenamento Local | UserDefaults + SQLite (GRDB) | UserDefaults pra perfil (poucos KB). SQLite via GRDB.swift pra fila offline, cache de rotas, histórico de passeios. |
| Build | Xcode 16 + SPM | Firebase, GoogleWebRTC, GRDB como Swift Packages. Zero CocoaPods. |

---

## 3. Estrutura de diretórios

```
wawa-ride/
├── App/
│   ├── WAWARideApp.swift           # @main entry point
│   ├── AppDelegate.swift            # Firebase, audio session, background tasks
│   └── Info.plist                   # Background modes, BLE, mic permissions
│
├── Models/
│   ├── RiderProfile.swift           # Perfil local do piloto
│   ├── Ride.swift                   # Passeio (id, líder, status, riders)
│   ├── RideParticipant.swift        # Rider dentro de um passeio (posição, papel)
│   ├── RoutePoint.swift             # Ponto da rota (lat, lng, timestamp, ordem)
│   ├── HazardAlert.swift            # Alerta de perigo (tipo, coordenada, autor)
│   ├── MeshPayload.swift            # Payload que trafega no mesh P2P
│   ├── VoiceAlert.swift             # Alerta de voz (texto, prioridade, repetições)
│   └── RideSummary.swift            # Resumo pós-passeio
│
├── Services/
│   ├── Location/
│   │   └── LocationService.swift    # CoreLocation: tracking, background, adaptive rate
│   │
│   ├── Mesh/
│   │   ├── MeshService.swift        # MultipeerConnectivity: discovery, session, state
│   │   ├── MeshAdvertiser.swift     # Anuncia presença do passeio via BLE
│   │   ├── MeshBrowser.swift        # Procura passeios próximos via BLE
│   │   └── MeshProtocol.swift       # Serialização, TTL, retransmissão, prioridade
│   │
│   ├── Cloud/
│   │   ├── FirebaseService.swift    # Init, Auth (future), configuração
│   │   └── RideSyncService.swift    # Firestore: ler/escrever posições, rota, alertas
│   │
│   ├── Transport/
│   │   ├── TransportManager.swift   # Orquestra Firebase vs Mesh vs Queue
│   │   └── OfflineQueue.swift       # Fila persistente (SQLite) quando offline
│   │
│   ├── Audio/
│   │   ├── VoiceAssistant.swift     # TTS: fila de alertas, prioridade, ducking
│   │   ├── VoiceCommandListener.swift  # SFSpeechRecognizer: "Ok moto" + comandos
│   │   └── VoiceChatService.swift   # WebRTC + MCSession stream para walkie-talkie
│   │
│   └── Route/
│       └── RouteService.swift       # Grava rastro do líder, simplifica polyline
│
├── Views/
│   ├── ProfileSetupView.swift       # Tela 1: perfil (primeiro uso)
│   ├── JoinRideView.swift           # Tela 2: criar/entrar no passeio
│   ├── LiveMapView.swift            # Tela 3: mapa ao vivo (a principal)
│   ├── LiveMapUIKit.swift           # UIViewRepresentable wrapper pro MKMapView
│   ├── RiderAnnotation.swift        # MKAnnotation customizado (pin + heading)
│   ├── RiderAnnotationView.swift    # MKAnnotationView (renderização do pin)
│   ├── HazardCalloutView.swift      # Popup de alerta de perigo
│   ├── PTTButton.swift              # Botão push-to-talk (gigante)
│   └── RideSummaryView.swift        # Tela 4: resumo pós-passeio
│
├── ViewModels/
│   ├── ProfileViewModel.swift       # Lógica do perfil
│   ├── JoinRideViewModel.swift      # Lógica de descoberta/entrada
│   ├── LiveMapViewModel.swift       # Estado do mapa, riders, rota, alertas
│   └── RideSummaryViewModel.swift   # Cálculo de stats pós-passeio
│
├── Extensions/
│   ├── CLLocation+Extensions.swift
│   ├── MKMapView+Extensions.swift
│   ├── Color+WAWA.swift
│   └── View+WAWA.swift
│
└── Resources/
    ├── Assets.xcassets              # Pins, ícones, cores
    └── MotoSounds/                  # Sons de alerta (opcional, além do TTS)
```

---

## 4. Fluxo de dados — onde cada dado trafega

```
DADO                     FIREBASE         MESH P2P        OFFLINE QUEUE
─────────────────────────────────────────────────────────────────────────
Posição GPS (1-3s)       ✅ Primário      ✅ Fallback      ✅ Se ambos off
Rota do líder            ✅ Primário      ✅ Trechos       ✅ Full path
Alertas de perigo        ✅ Primário      ✅ Imediato      ✅ Até expirar
Entrada/saída de rider   ✅ Evento        ✅ Descoberta    —
Voz walkie-talkie        ✅ WebRTC (4G)   ✅ Stream direto —
Alertas TTS              — (local)        —               —
Comandos de voz          — (local)        —               —
Resumo do passeio        ✅ Final         —               ✅ Local
```

---

## 5. Serviços — ciclo de vida e dependências

```
App Launch
  │
  ├─► FirebaseService.configure()
  │     └─► Firestore settings (offline persistence)
  │
  ├─► LocationService.shared.requestPermission()
  │     └─► Always Authorization (background)
  │
  ├─► VoiceAssistant.shared.setupAudioSession()
  │     └─► .playback, duckOthers, allowBluetooth
  │
  └─► VoiceCommandListener.shared.prepare()
        └─► SFSpeechRecognizer.requestAuthorization()

Ride Start (líder aperta "Criar Passeio")
  │
  ├─► MeshAdvertiser.start(rideId:)
  │     └─► BLE advertising com discoveryInfo (rideId, líder, N riders)
  │
  ├─► RideSyncService.createRide(profile:)
  │     └─► Firestore: rides/{rideId}/info + riders/{leaderId}
  │
  ├─► LocationService.startTracking()
  │     └─► Config: .otherNavigation, distanceFilter: 5m, background: true
  │
  ├─► RouteService.startRecording()
  │     └─► Array<RoutePoint> com simplificação em tempo real
  │
  └─► VoiceAssistant.speak(.rideStarted)

Ride Join (rider vê passeio, aperta "Entrar")
  │
  ├─► MeshBrowser detected → user taps join
  │
  ├─► MeshBrowser.invite(peerID)
  │     └─► MCSession connect + send join request
  │
  ├─► RideSyncService.joinRide(rideId, profile:)
  │     └─► Firestore: rides/{rideId}/riders/{riderId}
  │
  ├─► LocationService.startTracking()
  │
  └─► VoiceAssistant.speak(.riderJoined(name))

Ride Live (durante o passeio)
  │
  ├─► [Loop 1-3s]: LocationService → TransportManager.send(location)
  │     ├─► has4G? → Firestore .setData()
  │     └─► !has4G? → MeshService.send() + OfflineQueue.enqueue()
  │
  ├─► [Listener]: RideSyncService.observeRiders() → LiveMapViewModel
  │     └─► Firestore .addSnapshotListener ou MeshService.onReceive()
  │
  ├─► [Listener]: RideSyncService.observeAlerts() → LiveMapViewModel + VoiceAssistant
  │
  └─► [Evento]: Rider marca alerta → TransportManager.send(alert)
        ├─► has4G? → Firestore + Mesh (redundante)
        └─► !has4G? → Mesh (crítico, TTL=10) + OfflineQueue

Ride End (líder aperta "Encerrar")
  │
  ├─► RideSyncService.endRide(rideId)
  │     └─► Firestore: status = "finished", timestamp
  │
  ├─► MeshAdvertiser.stop()
  ├─► LocationService.stopTracking()
  ├─► RouteService.stopRecording() → simplifica → salva local
  │
  └─► Calcula RideSummary → mostra tela 4
```

---

## 6. Permissões necessárias (Info.plist)

```xml
<!-- Localização -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>WAWA Ride mostra sua localização no mapa do passeio, mesmo com o app em segundo plano.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>WAWA Ride mostra sua localização no mapa do passeio.</string>

<!-- Background modes -->
<key>UIBackgroundModes</key>
<array>
    <string>location</string>       <!-- GPS em background -->
    <string>bluetooth-central</string>   <!-- BLE scanning em bg -->
    <string>bluetooth-peripheral</string> <!-- BLE advertising em bg -->
    <string>audio</string>           <!-- TTS e voz em bg -->
</array>

<!-- Microfone -->
<key>NSMicrophoneUsageDescription</key>
<string>WAWA Ride usa o microfone para comandos de voz e walkie-talkie com o grupo.</string>

<!-- Speech recognition -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>WAWA Ride reconhece comandos de voz como "Ok moto, marcar radar" durante o passeio.</string>

<!-- Bluetooth -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>WAWA Ride usa Bluetooth para descobrir riders próximos e manter o grupo conectado mesmo sem internet.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>WAWA Ride anuncia a presença do passeio via Bluetooth para outros riders entrarem.</string>
```

---

## 7. Sessão de áudio — coexistência com intercom

O app NUNCA deve bloquear o áudio do intercomunicador (Cardo/Sena). A estratégia:

```
Cenário COM intercom (Cardo/Sena conectado via Bluetooth HFP):
  - AudioSession: .playback, .duckOthers
  - TTS: abaixa o intercom durante a fala, depois volta
  - Walkie-talkie via app: NÃO abre (o intercom já faz isso)
  - Comandos de voz: microfone do intercom via .allowBluetooth

Cenário SEM intercom (áudio vai pro alto-falante ou headset Bluetooth comum):
  - AudioSession: .playAndRecord, .allowBluetooth
  - TTS: fala normalmente
  - Walkie-talkie: usa microfone do headset
  - Comandos de voz: microfone do headset
```

Detecção de intercom:
```swift
// Heurística: se tem dispositivo Bluetooth HFP conectado com nome
// contendo "Cardo", "Sena", "Intercom", etc → assumir intercom
let route = AVAudioSession.sharedInstance().currentRoute
let hasIntercom = route.outputs.contains {
    $0.portType == .bluetoothHFP &&
    ["cardo", "sena", "intercom", "packtalk", "freecom"]
        .contains { $0.portName.lowercased().contains($0) }
}
```

---

## 8. Background & Bateria — estratégia de sobrevivência

```
ESTADO                          GPS     BLE     TTS     CONSUMO ESTIMADO
─────────────────────────────────────────────────────────────────────────
App ativo, tela ligada          1s      1s      Sim     ~8%/hora
App ativo, tela desligada       3s      3s      Sim     ~5%/hora
App em background (movendo)     5s      5s      Sim     ~3%/hora
App em background (parado)      30s     10s     Não     ~1%/hora
App suspenso (iOS kill)         —       —       —       0% (mas sem tracking)
```

Para evitar kill do iOS em background:
- `allowsBackgroundLocationUpdates = true`
- `showsBackgroundLocationIndicator = true` (requerido pela Apple)
- Conexão BLE ativa com outro peer (iOS não mata apps com BLE connection ativa)
- `BGTaskScheduler` como último recurso (acorda a cada ~15 min pra verificar estado)

---

## 9. Segurança

| Aspecto | Solução MVP |
|---------|------------|
| Dados em trânsito (Firebase) | TLS (padrão Firebase) |
| Dados em trânsito (Mesh) | Criptografia nativa do MultipeerConnectivity |
| Acesso não autorizado ao passeio | Só entra quem está em alcance BLE (~50m) + aprovação tácita (líder pode expulsar via toque) |
| Localização de riders | Só visível dentro do grupo do passeio. Dados não persistem no servidor após encerrar. |
| Auth | MVP não tem. Futuro: Sign in with Apple. |

---

## 10. Dependências (Swift Package Manager)

```swift
// Package.swift ou Xcode SPM
dependencies: [
    .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.0"),
    .package(url: "https://github.com/stasel/WebRTC", from: "125.0"),  // GoogleWebRTC pre-built
    .package(url: "https://github.com/groue/GRDB.swift", from: "6.0"),
]
```

Targets:
- FirebaseFirestore (cloud sync + offline persistence)
- GoogleWebRTC (voice chat)
- GRDB (offline queue e cache local)
