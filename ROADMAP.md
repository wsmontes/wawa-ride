# Wawa Ride v2 — Roadmap de Implementação

**Última atualização:** 2026-06-15  
**Branch:** `v2/mesh-maplibre-ferrostar`  
**Meta:** Primeiro teste de campo com 3 iPhones em 4 semanas.

---

## Fase 1: Fundação (Semanas 1-2)

> **Objetivo:** 3 iPhones trocando localização via BLE mesh, visíveis no mapa.

### Sprint 1.1 — BLE Mesh Funcional (5 dias)

| # | Tarefa | Arquivo(s) | Critério de Aceite |
|---|--------|------------|-------------------|
| 1 | Corrigir imports CoreBluetoothMock (verificar API real: CBMCentralManager vs CBCentralManager) | `MeshBLEService.swift` | Compila no Xcode 16 |
| 2 | Testar dual-role BLE (advertising + scanning) com 2 iPhones | `MeshBLEService.swift` | iPhone A vê iPhone B e vice-versa |
| 3 | Enviar/receber `CompactLocation` (12 bytes) entre 2 devices | `CompactLocation.swift`, `BinaryCodec.swift` | Lat/lon aparecem corretos no receptor |
| 4 | Validar dedup: mesmo pacote recebido 2x não processa 2x | `MessageDeduplicator.swift` | Test unitário passa + verificação com 3 phones |
| 5 | Validar relay multi-hop: A→B→C (TTL decrement) | `MeshBLEService.swift` | C recebe pacote originado em A, TTL=3 (original 5, -1 por hop) |
| 6 | Implementar MockBLEBus (padrão BitChat) para testes em CI | `Tests/WawaMeshTests/` | Topologia linear A-B-C testada sem hardware |
| 7 | Adicionar fragmentação real com delay 30ms entre chunks | `MeshBLEService.swift` | Payload de 1KB chega completo via BLE |

**Dependências a resolver:**
- [ ] Verificar se `CoreBluetoothMock` v0.17 compila com Swift 6 / Xcode 16
- [ ] Confirmar UUIDs de serviço/característica não conflitam com outros apps

### Sprint 1.2 — Mapa + Pairing (5 dias)

| # | Tarefa | Arquivo(s) | Critério de Aceite |
|---|--------|------------|-------------------|
| 8 | Resolver Package.swift (verificar conflitos SPM entre MapLibre SwiftUI-DSL e Ferrostar) | `Package.swift` | `swift package resolve` sem erro |
| 9 | Gerar PMTiles para São Paulo metro (~50-100MB) via Planetiler | externo (CLI) | Arquivo `.pmtiles` com roads/landuse visíveis |
| 10 | Carregar PMTiles local no MapLibre (`pmtiles://file:///...`) | `OfflineTileManager.swift`, `RideMapView.swift` | Mapa renderiza offline (modo avião) |
| 11 | Exibir rider pins no mapa com posição real (CoreLocation) | `RideMapView.swift`, `RiderBadge` | Meu ponto aparece, pulsa, segue meu GPS |
| 12 | Exibir riders remotos recebidos via mesh | `RideSession.swift` | 2 phones: cada um vê o outro no mapa |
| 13 | PIN pairing flow completo (criar + entrar + validar) | `RootView.swift`, `RideSession.swift` | Leader cria PIN → follower digita → ambos no mapa |
| 14 | Stale rider visual (cinza após 15s, remove após 120s) | `RideSession.swift`, `RiderBadge` | Desligar BLE de um phone → pin fica cinza → some |

**Entregável Fase 1:** App funcional rodando em 3 iPhones. Riders se veem no mapa via BLE mesh. PIN pairing. Mapa offline (PMTiles SP).

---

## Fase 2: Estabilidade + Dados (Semanas 3-4)

> **Objetivo:** Ride sobrevive a desconexões, persiste dados, importa rotas.

### Sprint 2.1 — Persistência + Sync (5 dias)

| # | Tarefa | Arquivo(s) | Critério de Aceite |
|---|--------|------------|-------------------|
| 15 | GRDB: offline queue funcional (enqueue quando sem peers, dequeue ao reconectar) | `AppDatabase.swift`, `TransportCoordinator` | Packets enfileirados são enviados ao reconectar |
| 16 | GRDB: ride history (start/end, duração, distância calculada) | `AppDatabase.swift`, `RideSession.swift` | Histórico mostra passeios anteriores |
| 17 | Automerge: sync ao reconectar (gerar/receber sync messages via MultipeerKit) | `RideSyncDocument.swift`, `TransportCoordinator` | Rider volta de túnel → posições convergem |
| 18 | MultipeerKit foreground: location sharing via Codable path | `MultipeerTransport.swift` | Riders no mesmo WiFi trocam posição sem BLE |
| 19 | Dual transport: MC + BLE simultâneo, dedup entre ambos | `TransportCoordinator`, `RideSession.swift` | Receber pelo 2 canais não duplica rider no mapa |
| 20 | State restoration BLE: app relançado após background kill reconecta | `MeshBLEService.swift` | Matar app via Xcode → peripheral volta → app reconecta |

### Sprint 2.2 — Rotas + Alertas (5 dias)

| # | Tarefa | Arquivo(s) | Critério de Aceite |
|---|--------|------------|-------------------|
| 21 | GPX import: CoreGPX parser, mostrar rota importada como polyline | novo `GPXImporter.swift` | Importar GPX via share sheet → rota aparece no mapa |
| 22 | Route corridor: alertar quando rider sai da rota (Turf.swift) | `RouteCorridor.swift`, `RideSession.swift` | Rider >100m da rota → pin fica vermelho + haptic |
| 23 | Route sharing via mesh: leader broadcast `.routeShare` packet | `RideSession.swift` | Leader importa GPX → followers veem a rota no mapa |
| 24 | Leader trail: polyline crescendo ao vivo (coordenadas acumuladas) | `RideMapView.swift` | Linha azul atrás do líder cresce em tempo real |
| 25 | Speed HUD: velocidade real do GPS no overlay | `RootView.swift` (RidingOverlay) | km/h atualiza em tempo real |
| 26 | Waypoint sharing: leader marca ponto no mapa → broadcast para grupo | novo `WaypointManager.swift` | Líder toca mapa → pin compartilhado aparece em todos |

**Entregável Fase 2:** Ride funciona com reconnection graceful. Rotas GPX importáveis. Alertas de desvio. Trail do líder ao vivo. Waypoints compartilhados.

---

## Fase 3: Navegação + Fallback (Semanas 5-7)

> **Objetivo:** Turn-by-turn via Valhalla, Nostr fallback para internet.

### Sprint 3.1 — Valhalla + Ferrostar (7 dias)

| # | Tarefa | Arquivo(s) | Critério de Aceite |
|---|--------|------------|-------------------|
| 27 | Deploy Valhalla Docker com tiles Brasil sudeste | `Server/docker-compose.yml` | `curl /route` retorna JSON válido |
| 28 | Ferrostar integration: request route via WellKnownRouteProvider.valhalla | `RouteService.swift` | Rota calculada entre 2 pontos exibida no mapa |
| 29 | Turn-by-turn UI: DynamicallyOrientingNavigationView do Ferrostar | novo `NavigationView.swift` | Instruções de curva + voz (pt-BR) |
| 30 | Map matching: snap trail do líder via /trace_route (Meili) | `MapMatchingService.swift`, `GroupNavigationCoordinator` | Trail ruidoso → polyline limpa na estrada |
| 31 | Motorcycle costing: `use_trails=0.7`, `use_highways=0.3` | `RouteService.swift` | Rota prefere estradas secundárias/trilhas |
| 32 | Route deviation custom detector (100m threshold) | `RouteService.swift` | Navegar → sair da rota → "recalculando" ou alerta |

### Sprint 3.2 — Nostr Fallback (5 dias)

| # | Tarefa | Arquivo(s) | Critério de Aceite |
|---|--------|------------|-------------------|
| 33 | WebSocket Nostr client (connect, subscribe, publish) | novo `NostrClient.swift` | Conecta em relay público, recebe events |
| 34 | Publish location via Nostr (NIP-78 app data + geohash tag) | novo `NostrTransport.swift` | Posição publicada visível em outro client Nostr |
| 35 | Subscribe geohash channel (riders no mesmo geohash recebem) | `NostrTransport.swift` | 2 phones sem BLE trocam posição via relay |
| 36 | NIP-65 relay list (2 write + 2 read, failover automático) | `NostrClient.swift` | Relay 1 offline → fallback para relay 2 transparente |
| 37 | Transport priority: BLE > MultipeerKit > Nostr > queue | `TransportCoordinator.swift` | Com internet: Nostr ativo. Sem: BLE/MC only |

**Entregável Fase 3:** Navegação turn-by-turn funcional. Riders podem se comunicar via internet (Nostr) quando fora de alcance BLE. Stack completa MVP.

---

## Fase 4: Polish + Voice (Semanas 8-10)

> **Objetivo:** Produto testável com grupo real. Voice PTT. CarPlay.

### Sprint 4.1 — Voice PTT (7 dias)

| # | Tarefa | Arquivo(s) | Critério de Aceite |
|---|--------|------------|-------------------|
| 38 | Adicionar swift-opus como dependência | `Package.swift` | Compila |
| 39 | Audio capture pipeline: AVAudioEngine → Opus encode (8kHz mono) | novo `AudioPipeline.swift` | Gravação → data comprimida |
| 40 | PTT transmit via MultipeerKit (stream audio chunks) | `MultipeerTransport.swift` | Pressionar botão → áudio chega no peer |
| 41 | Playback pipeline: Opus decode → AVAudioPlayerNode | `AudioPipeline.swift` | Ouvir voz do peer automaticamente |
| 42 | PTT UI: big button, haptic on press/release | `RootView.swift` | Botão aparece durante ride, feedback claro |
| 43 | Indicador "quem está falando" (Live Activity, fase futura) | UI overlay | Nome do falante aparece na tela |

### Sprint 4.2 — CarPlay + QR + Polish (7 dias)

| # | Tarefa | Arquivo(s) | Critério de Aceite |
|---|--------|------------|-------------------|
| 44 | CarPlay scene delegate (FerrostarCarPlayUI) | novo `CarPlayDelegate.swift` | Mapa + turn-by-turn no display CarPlay |
| 45 | Solicitar entitlement `com.apple.developer.carplay-maps` | Apple Developer Portal | Aprovado pela Apple |
| 46 | QR code group invite (substituir PIN por QR para fase 2) | novo `QRInvite.swift`, usar CodeScanner | Scan QR → join instantâneo |
| 47 | GPX export: salvar ride como GPX para compartilhar | novo `GPXExporter.swift` | Compartilhar via share sheet após ride |
| 48 | Ride summary screen (pós-ride: mapa, distância, duração, riders) | novo `RideSummaryView.swift` | Ao encerrar, mostra resumo |
| 49 | App icon + launch screen | `Assets.xcassets` | Identidade visual |
| 50 | TestFlight beta deploy | Xcode Cloud / manual | Link de teste distribuído para grupo piloto |

**Entregável Fase 4:** App com voice PTT, CarPlay, QR invite, GPX export. Pronto para TestFlight.

---

## Fase 5: Segurança + Escala (Semanas 11-14)

> **Objetivo:** Criptografia E2E, grupos maiores, preparação App Store.

| # | Tarefa | Critério de Aceite |
|---|--------|--------------------|
| 51 | NIP-44 encryption para mensagens 1:1 (nostr-sdk-swift) | Mensagens Nostr ilegíveis sem chave |
| 52 | OpenMLS grupo (via UniFFI/swift-bridge) | Criar grupo MLS → encrypt → decrypt funciona |
| 53 | Noise_XX handshake no BLE mesh (lazy, on-demand) | Pacotes BLE encriptados após handshake |
| 54 | Group key rotation (new member join / member leave) | Novo membro → rekey → antigo não lê futuro |
| 55 | GCS filter gossip sync (BitChat pattern) | Peers sincronizam "o que tenho" eficientemente |
| 56 | Source routing v2 (directed messages sem flood) | Mensagem privada → roteada sem broadcast |
| 57 | Testes com 10+ devices | Mesh estável com 10 phones durante 2h |
| 58 | Privacy review (metadados, logs, permissões) | Audit completo documentado |
| 59 | App Store review prep (screenshots, descrição, privacy policy) | Submission kit pronto |
| 60 | App Store submit | Aprovado |

---

## Métricas de Sucesso por Fase

| Fase | KPI | Meta |
|------|-----|------|
| 1 | BLE mesh estável entre 3 phones | 0 crashes em 30 min |
| 2 | Reconnection sem perda de dados | <5s para reaparecer no mapa |
| 3 | Rota calculada em | <3s (Valhalla local Docker) |
| 4 | Voice latência PTT | <500ms (MultipeerKit LAN) |
| 5 | Grupo de 10 riders | Todos visíveis durante ride de 2h |

---

## Dependências Externas por Fase

| Fase | Novas Dependências |
|------|-------------------|
| 1 | CoreBluetoothMock (já adicionada), swift-protobuf (já), MapLibre SwiftUI-DSL (já) |
| 2 | CoreGPX (MIT), Turf-Swift (já adicionada) |
| 3 | Ferrostar (já adicionada), Valhalla Docker |
| 4 | swift-opus (BSD-3), CodeScanner (MIT) |
| 5 | nostr-sdk-swift (MIT), OpenMLS via UniFFI |

---

## Riscos por Fase

| Fase | Risco | Mitigação |
|------|-------|-----------|
| 1 | BLE background não funciona entre 2 phones background | Garantir que riders mantêm app foreground (screen on, handlebar mount) |
| 1 | PMTiles não carrega no MapLibre iOS | Fallback: MBTiles via SQLite (suporte nativo confirmado) |
| 2 | Automerge-swift API incompatível com nosso código | Abstrair atrás de RideSyncDocument (já feito) |
| 3 | Ferrostar 0.51 não existe ou API mudou | Verificar releases reais; ajustar import |
| 3 | Valhalla Docker lento para tile build do Brasil | Usar recorte menor (só SP metro) para dev |
| 4 | Apple nega CarPlay entitlement | Submeter justificativa como app de navegação |
| 5 | OpenMLS FFI complexo demais para Swift | Usar NIP-44 (1:1) como fallback; MLS grupo adia |

---

## Timeline Visual

```
Semana:  1    2    3    4    5    6    7    8    9    10   11   12   13   14
         ├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
Fase 1:  [████████████████████]
         BLE mesh    Mapa+Pairing
         3 phones    PMTiles offline
                                    
Fase 2:            [████████████████████]
                   GRDB         Rotas GPX
                   Automerge    Alertas
                                         
Fase 3:                      [██████████████████████████]
                             Valhalla     Nostr
                             Ferrostar    Fallback

Fase 4:                                        [██████████████████████]
                                               Voice PTT   CarPlay
                                               QR invite   Polish

Fase 5:                                                          [████████████████]
                                                                 Crypto    App Store
                                                                 Scale     Submit

Milestones:
  ▲ Sem 2: Primeiro teste de campo (3 phones, BLE mesh + mapa)
  ▲ Sem 4: Ride completo com reconnection + rotas
  ▲ Sem 7: Stack MVP completa (mesh + nav + nostr)
  ▲ Sem 10: TestFlight beta
  ▲ Sem 14: App Store submission
```

---

## Checklist Pré-Teste de Campo (Fim da Fase 1)

- [ ] 3 iPhones com app instalado (Xcode direct install)
- [ ] PMTiles da região de teste carregado no bundle
- [ ] BLE permissions granted em todos os devices
- [ ] Location always authorized
- [ ] Verificar que mapa renderiza offline (modo avião)
- [ ] Verificar que PIN pairing funciona (criar + entrar)
- [ ] Verificar que riders se veem no mapa
- [ ] Verificar que relay funciona (A→B→C: C vê A sem estar conectado direto)
- [ ] Verificar que stale visual funciona (desligar BLE de 1 → fica cinza)
- [ ] Levar powerbank (GPS + BLE = consumo alto)
- [ ] Definir rota curta (15-20 min) para teste controlado
