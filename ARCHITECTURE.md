# Wawa Ride v2 — Proposta de Arquitetura

**Data:** 2026-06-15  
**Branch:** `v2/mesh-maplibre-ferrostar` em `wsmontes/wawa-ride`  
**Objetivo:** App iOS para grupos de motociclistas se localizarem em tempo real, com comunicação off-grid via malha BLE e navegação offline.

---

## 1. Visão Geral

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WAWA RIDE v2 — STACK COMPLETA                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        APRESENTAÇÃO (SwiftUI)                        │    │
│  │                                                                       │    │
│  │   StartView → PairingView → RideMapView → [NavigationView fase 2]    │    │
│  │                                                                       │    │
│  │   MapLibre SwiftUI-DSL    Ferrostar UI (fase 2)    RiderBadge        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     DOMÍNIO (ViewModels / Coordenadores)             │    │
│  │                                                                       │    │
│  │   RideSession (orquestrador principal)                                │    │
│  │   GroupNavigationCoordinator (líder + seguidores)                     │    │
│  │   RouteCorridor (alerta de desvio via Turf)                           │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        SERVIÇOS                                       │    │
│  │                                                                       │    │
│  │   TransportCoordinator        SmartLocationTracker   RouteService     │    │
│  │   (dual: MC + BLE mesh)       (GPS adaptativo)       (Valhalla API)  │    │
│  │                                                                       │    │
│  │   AppDatabase (GRDB)          RideSyncDocument        MapMatching     │    │
│  │   (fila offline + histórico)  (Automerge CRDT)        (Meili snap)   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        TRANSPORTE                                     │    │
│  │                                                                       │    │
│  │   MultipeerKit              MeshBLEService            [Nostr fase 3] │    │
│  │   (Wi-Fi Direct, foreground (CoreBluetooth, background  (relay       │    │
│  │    Codable, rápido)          multi-hop TTL=5, 12B)      fallback)    │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        DADOS OFFLINE                                   │    │
│  │                                                                       │    │
│  │   PMTiles (basemap regional)   SQLite/GRDB (estado)   Automerge (sync)│    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Módulos SPM

| Módulo | Responsabilidade | Dependências Externas |
|--------|-----------------|----------------------|
| **WawaMesh** | Transporte dual (BLE mesh + MultipeerKit), pacotes binários, fragmentação, dedup | MultipeerKit, SwiftProtobuf, CoreBluetoothMock |
| **WawaMap** | Mapa MapLibre, annotations de riders, tiles offline, corridor check | MapLibreSwiftUI (swiftui-dsl), Turf |
| **WawaNavigation** | Roteamento Valhalla, map matching, navegação Ferrostar, coordenação de grupo | FerrostarCore, FerrostarSwiftUI, FerrostarMapLibreUI |
| **WawaPersistence** | SQLite (GRDB) para fila offline + histórico, Automerge CRDT para sync | GRDB, Automerge |
| **WawaRideApp** | App entry point, views SwiftUI, RideSession orchestrator, location tracker | Todos os módulos acima |

---

## 3. Dependências Externas

| # | Pacote | Versão | Licença | Stars | Papel |
|---|--------|--------|---------|-------|-------|
| 1 | [maplibre/swiftui-dsl](https://github.com/maplibre/swiftui-dsl) | ≥0.25.0 | BSD-3 | 105 | Mapa vetorial SwiftUI declarativo, PMTiles offline, CarPlay |
| 2 | [stadiamaps/ferrostar](https://github.com/stadiamaps/ferrostar) | ≥0.51.0 | BSD-2 | 600+ | Turn-by-turn navigation, Valhalla adapter, deviation detection |
| 3 | [groue/GRDB.swift](https://github.com/groue/GRDB.swift) | ≥7.11.0 | MIT | 8.5k | SQLite com WAL, queries reativas, migrações |
| 4 | [automerge/automerge-swift](https://github.com/automerge/automerge-swift) | ≥0.5.0 | MIT | 317 | CRDT sync ao reconectar (bloom-filter delta protocol) |
| 5 | [insidegui/MultipeerKit](https://github.com/insidegui/MultipeerKit) | ≥0.4.0 | BSD-2 | 1.1k | Wi-Fi Direct foreground (Codable, targeted send, SwiftUI) |
| 6 | [apple/swift-protobuf](https://github.com/apple/swift-protobuf) | ≥1.28.0 | Apache-2 | 4.3k | Location payload 12 bytes (sfixed32 lat/lon × 1e7) |
| 7 | [mapbox/turf-swift](https://github.com/mapbox/turf-swift) | ≥4.0.0 | ISC | 268 | Geospatial: distância ponto-a-linha, corredor de rota |
| 8 | [NordicSemiconductor/IOS-CoreBluetooth-Mock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock) | ≥0.17.0 | BSD-3 | — | BLE no Simulator (dev/test sem hardware físico) |

**Todas as licenças são permissivas.** Nenhuma GPL ou viral. Compatíveis com app proprietário.

---

## 4. Projetos de Referência (Código Estudado)

### 4.1 Transporte BLE Mesh

| Projeto | Licença | Stars | O que extraímos |
|---------|---------|-------|-----------------|
| [permissionlesstech/bitchat](https://github.com/permissionlesstech/bitchat) | Unlicense | 26k | Protocolo binário (16B header), dual Central+Peripheral, TTL flood, fragmentação 469B, dedup LRU (1000/300s), source routing v2, GCS gossip sync |
| [zssz/BerkananSDK](https://github.com/zssz/BerkananSDK) | MIT | 218 | Padrão connectionless GATT write (validação de que flooding BLE funciona no iOS) |
| [insidegui/MultipeerKit](https://github.com/insidegui/MultipeerKit) | BSD-2 | 1.1k | API Codable para MultipeerConnectivity, targeted send, SwiftUI integration |
| [DP-3T/dp3t-sdk-ios](https://github.com/DP-3T/dp3t-sdk-ios) | MPL-2 | — | Limitações reais de BLE background no iOS, state restoration pattern |

### 4.2 Mapas e Tiles Offline

| Projeto | Licença | Stars | O que extraímos |
|---------|---------|-------|-----------------|
| [protomaps/PMTiles](https://github.com/protomaps/PMTiles) | BSD-3 | 2.9k | Formato de arquivo único para tiles (10-15% menor que MBTiles, lido por MapLibre) |
| [onthegomap/planetiler](https://github.com/onthegomap/planetiler) | Apache-2 | 2.1k | Gerador de tiles vetoriais do OSM → .pmtiles (um comando por região) |
| [felt/tippecanoe](https://github.com/felt/tippecanoe) | BSD-2 | 1.5k | Conversão de GeoJSON custom (rotas Wawa) → .pmtiles overlay |
| [protomaps/basemaps](https://github.com/protomaps/basemaps) | ODbL | — | Basemaps vetoriais pré-gerados (cobertura global, download diário) |
| [protomaps/go-pmtiles](https://github.com/protomaps/go-pmtiles) | BSD-3 | — | CLI para extrair sub-regiões: `pmtiles extract --bbox` |

### 4.3 Navegação e Roteamento

| Projeto | Licença | Stars | O que extraímos |
|---------|---------|-------|-----------------|
| [stadiamaps/ferrostar](https://github.com/stadiamaps/ferrostar) | BSD-2 | 600+ | SDK navegação: Valhalla adapter, StepAdvanceCondition, route deviation, SwiftUI views, CarPlay |
| [valhalla/valhalla](https://github.com/valhalla/valhalla) | MIT | 8k | Motor de rotas: /route (OSRM format), /trace_route (map matching), motorcycle costing (beta) |
| [mapbox/turf-swift](https://github.com/mapbox/turf-swift) | ISC | 268 | `closestCoordinate(to:)` para route corridor deviation check |

### 4.4 Sincronização e Persistência

| Projeto | Licença | Stars | O que extraímos |
|---------|---------|-------|-----------------|
| [automerge/automerge](https://github.com/automerge/automerge) | MIT | 6.3k | CRDT sync protocol (paper arXiv:2012.00472), bloom-filter delta exchange |
| [automerge/automerge-swift](https://github.com/automerge/automerge-swift) | MIT | 317 | Bindings Swift nativos (wraps Rust core via C FFI) |
| [groue/GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | 8.5k | DatabasePool WAL, ValueObservation reativo, migrations |
| [owntracks/ios](https://github.com/owntracks/ios) | MIT | 418 | Padrão de tracking: GPS só quando há movimento, fila offline, broadcast throttle |

### 4.5 Criptografia (Fase 2)

| Projeto | Licença | Stars | O que usaremos |
|---------|---------|-------|----------------|
| [openmls/openmls](https://github.com/openmls/openmls) | MIT | 961 | MLS (RFC 9420) para grupos com forward secrecy |
| [rust-nostr/nostr-sdk-swift](https://github.com/rust-nostr/nostr-sdk-swift) | MIT | — | NIP-44 (ECDH secp256k1 + ChaCha20) para mensagens 1:1 |
| [chinedufn/swift-bridge](https://github.com/chinedufn/swift-bridge) | MIT/Apache | 1.1k | FFI Rust↔Swift (alternativa: UniFFI usado por nostr-sdk) |

### 4.6 Formação de Grupo (Padrões Estudados)

| Projeto | Licença | Stars | Padrão extraído |
|---------|---------|-------|-----------------|
| [berty/berty](https://github.com/berty/berty) | Apache-2 | 9.2k | Wesh protocol: identidade 3 camadas, grupos sem servidor, multi-transport (BLE+mDNS+Internet), OrbitDB CRDT sync |
| [chatmail/core](https://github.com/chatmail/core) (Delta Chat) | MPL-2 | 7k+ | SecureJoin: QR com fingerprint + challenge + AUTH → grupo offline |
| [TryQuiet/quiet](https://github.com/TryQuiet/quiet) | GPL-3 | 2.6k | Comunidades offline via Tor + X.509 certs assinados pelo owner |

### 4.7 GPX e Geoespacial (Fase 2)

| Projeto | Licença | Stars | Uso |
|---------|---------|-------|-----|
| [vincentneo/CoreGPX](https://github.com/vincentneo/CoreGPX) | MIT | 294 | Parser GPX v1.1 puro Swift (import/export rotas) |
| [merlos/iOS-Open-GPX-Tracker](https://github.com/merlos/iOS-Open-GPX-Tracker) | GPL-3 | 699 | Referência de UX para gravação/exportação de trilhas |

### 4.8 Voice PTT (Fase 4)

| Projeto | Licença | Stars | Uso |
|---------|---------|-------|-----|
| [alta/swift-opus](https://github.com/alta/swift-opus) | BSD-3 | 121 | Codec Opus (8-12 kbps mono narrowband) para walkie-talkie |

### 4.9 Testes de Mesh

| Projeto | Licença | Stars | Uso |
|---------|---------|-------|-----|
| [NordicSemiconductor/IOS-CoreBluetooth-Mock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock) | BSD-3 | — | BLE no Simulator via `CBM` prefix classes |
| permissionlesstech/bitchat (testes) | Unlicense | 26k | Padrão MockBLEBus: virtual network topology + synchronous flooding para testes determinísticos |

---

## 5. Protocolo de Rede (WawaMesh)

### 5.1 Wire Format (derivado do BitChat BinaryProtocol v2)

```
Header (16 bytes, big-endian):
┌─────────┬──────┬─────┬──────────────────────┬───────┬──────────────┐
│ Version │ Type │ TTL │    Timestamp (8B)     │ Flags │ PayloadLen(4)│
│   1B    │  1B  │ 1B  │ ms since epoch        │  1B   │              │
└─────────┴──────┴─────┴──────────────────────┴───────┴──────────────┘

Flags bitmask:
  0x01 = hasRecipient (unicast)
  0x02 = hasSignature (Ed25519, 64B)
  0x04 = isCompressed (zlib)
  0x08 = hasRoute (source routing)

Variable (after header):
  [SenderID: 8B] (always present)
  [RecipientID: 8B]?        ← if 0x01
  [Route: count+hops]?      ← if 0x08
  [Payload: var]
  [Signature: 64B]?         ← if 0x02
```

### 5.2 Location Payload (CompactLocation, 12 bytes)

```
[lat_i: sfixed32 × 1e7] [lon_i: sfixed32 × 1e7] [heading: uint16] [speed: uint16 dm/s]
         4 bytes                  4 bytes              2 bytes          2 bytes
```

Precisão: ~1.1 cm (lat/lon), 1° (heading), 0.1 m/s (speed). Nunca fragmenta no BLE.

### 5.3 Flooding e Dedup

| Parâmetro | Valor | Referência |
|-----------|-------|-----------|
| TTL default | 5 hops | BitChat usa 7; reduzimos para grupos de 5-7 riders |
| Dedup cache | 1000 entries, 300s TTL | BitChat `messageDedupMaxCount/Age` |
| Dedup key | `"{senderHex}-{timestamp}-{type}"` | BitChat BLEReceivePipeline |
| Fragment size | 469 bytes | BitChat `bleDefaultFragmentSize` |
| Fragment spacing | 30 ms | BitChat recomendação (buffer overflow prevention) |
| Max connections | 6 simultâneas | BitChat `bleMaxCentralLinks` |

### 5.4 Transporte Dual

```
┌────────────────────────────────────────────────────────────────┐
│  GPS Update (1 Hz)                                              │
│                                                                  │
│  ┌──────────────────────────┐  ┌──────────────────────────────┐│
│  │ MultipeerKit (foreground) │  │ BLE Mesh (background)         ││
│  │ • Wi-Fi Direct            │  │ • CoreBluetooth               ││
│  │ • Codable LocationPayload │  │ • CompactLocation 12B         ││
│  │ • 1 hop, Mbps throughput  │  │ • Multi-hop TTL=5, Kbps       ││
│  │ • Morre em background     │  │ • State restoration relaunch  ││
│  └──────────────────────────┘  └──────────────────────────────┘│
│                                                                  │
│  Dedup no receptor: MeshPacket.messageID garante                 │
│  processamento único mesmo recebendo por ambos canais.           │
└────────────────────────────────────────────────────────────────┘
```

---

## 6. Mapa e Tiles Offline

### 6.1 Pipeline de Geração

```bash
# 1. Gerar basemap regional a partir do OSM
planetiler --area=brazil --output=brazil-sudeste.pmtiles

# 2. Extrair sub-região (e.g., só SP metro)
pmtiles extract brazil-sudeste.pmtiles sp-metro.pmtiles \
  --bbox=-47.0,-24.0,-45.5,-23.0 --maxzoom=14

# 3. Gerar overlay de rotas customizadas
tippecanoe -zg -o wawa-routes.pmtiles routes.geojson

# 4. Empacotar no app ou disponibilizar para download
```

### 6.2 Renderização no iOS

- **Motor:** MapLibre Native (via `maplibre/swiftui-dsl`)
- **Fonte:** `pmtiles://file:///path/to/basemap.pmtiles` no style.json
- **Layers:** Riders (circle layer data-driven), Route (line layer), Waypoints (symbol layer)
- **Offline:** Arquivo PMTiles é self-contained — não precisa de servidor de tiles
- **OSM Attribution:** `© OpenStreetMap contributors` no mapa (ODbL requirement)

### 6.3 Estimativas de Tamanho

| Região | Zoom | Tamanho PMTiles |
|--------|------|-----------------|
| Brasil inteiro | z0-z14 | ~2-4 GB |
| Estado de SP | z0-z14 | ~200-500 MB |
| Cidade (SP metro) | z0-z14 | ~50-150 MB |
| Corredor de rota | z10-z14 | ~5-20 MB |

---

## 7. Navegação (Fase 2)

### 7.1 Stack

```
iOS App (Ferrostar SDK)
    │
    │ HTTP POST (format=osrm, banner_instructions=true)
    ▼
Valhalla Server (Docker)
    │
    │ Endpoints: /route, /trace_route, /isochrone
    ▼
Tiles Valhalla (gerados por Mjolnir a partir do OSM)
```

### 7.2 Configuração Ferrostar para Motociclismo

| Parâmetro | Valor | Justificativa |
|-----------|-------|---------------|
| waypointAdvance | 100m | Grupo espalhado (não é carro seguindo GPS exato) |
| stepAdvance (entry) | 50m | GPS impreciso em trilhas/matas |
| stepAdvance (exit) | 30m | Tolerância para saída tardia |
| routeDeviation | 100m | Estradas não-mapeadas, atalhos |
| minimumHorizontalAccuracy | 50m | Aceitar GPS degradado |
| profile | motorcycle | Valhalla costing: `use_trails=0.7, use_highways=0.3` |

### 7.3 Map Matching (Meili)

Valhalla's `/trace_route` endpoint snapa coordenadas GPS ruidosas para a malha viária:
- Input: array de lat/lon (do mesh, com 5-50m de erro)
- Output: polyline limpa + maneuvers + distância/duração
- Uso: reconstruir trilha do líder a partir de location updates recebidos via mesh

---

## 8. Sincronização Offline (Automerge CRDT)

### 8.1 Problema

Riders perdem conectividade BLE (túnel, distância, bateria). Quando reconectam, suas visões de estado divergem. Precisamos reconciliar sem conflitos.

### 8.2 Solução: Automerge Sync Protocol

```
Rider A (offline 2 min)         Rider B (offline 2 min)
    │                                │
    │  Atualiza posição local        │  Atualiza posição local
    │  (CRDT Document)               │  (CRDT Document)
    │                                │
    └──────── reconectam ────────────┘
    │                                │
    │  A envia: heads + bloom filter │
    │◄──────────────────────────────►│  B envia: heads + bloom filter
    │                                │
    │  B identifica deltas de A      │  A identifica deltas de B
    │  e envia changes faltantes     │  e envia changes faltantes
    │                                │
    │  CRDT merge (determinístico)   │  CRDT merge (determinístico)
    │                                │
    ▼  Estado convergido (2-4 msgs)  ▼  Estado convergido
```

### 8.3 Modelo de Dados

```
Automerge Document {
  riders: Map<PeerID, {
    lat: F64,
    lon: F64,
    hdg: F64?,
    spd: F64?,
    ts: F64
  }>
}
```

---

## 9. Persistência Local (GRDB)

### 9.1 Tabelas

| Tabela | Propósito |
|--------|-----------|
| `ride` | Histórico de passeios (startedAt, endedAt, isLeader) |
| `pendingPacket` | Fila store-and-forward (data blob, retryCount) |
| `waypoint` | Pontos de interesse compartilhados (lat, lon, nome) |

### 9.2 Patterns

- **DatabasePool** (WAL mode): writer não bloqueia readers
- **ValueObservation**: UI reativa quando fila muda (fase 2)
- **Migrations**: schema versionado para upgrades safe

---

## 10. Formação de Grupo

### 10.1 MVP (PIN via BLE)

```
Líder                              Seguidor
  │                                    │
  │  Gera PIN 4 dígitos               │
  │  Inicia BLE advertising            │
  │                                    │
  │◄───── BLE discovery ──────────────│
  │                                    │
  │  Mostra PIN na tela                │  Digita PIN do líder
  │                                    │
  │  Broadcast .groupControl           │  Recebe, valida PIN
  │  payload: "JOIN:1234"              │  Aceita no grupo
  │                                    │
  │  Inicia passeio                    │  Segue no mapa
```

### 10.2 Fase 2 (QR + Shared Secret)

Inspirado em Delta Chat SecureJoin + Berty Wesh:
```swift
struct GroupInvite: Codable {
    let groupId: String          // UUID
    let groupName: String        // "Passeio Serra do Rio"
    let secret: Data             // 32 bytes (symmetric key)
    let creatorPublicKey: Data   // Ed25519
}
// Serializado → base64 → QR code ("ridegroup://...")
```

---

## 11. Decisões de Produto (MVP)

| Decisão | Escolha | Justificativa |
|---------|---------|---------------|
| Líder | Quem cria a sessão | Simples, pode trocar depois |
| Entrada no grupo | PIN 4 dígitos via BLE | Não precisa internet |
| Tamanho do grupo | 5-7 dispositivos | Limite prático de BLE (6 conexões) |
| Criptografia | Nenhuma no MVP | Cleartext para validar mesh primeiro |
| Rider stale | Cinza após 15s, remove após 120s | Feedback visual sem poluir mapa |
| Tile format | PMTiles (arquivo local) | Zero servidor, MapLibre lê direto |
| Roteamento | Fase 2 (Valhalla Docker) | MVP valida mesh sem dependência de servidor |
| Nostr fallback | Fase 3 | Relays públicos quando internet disponível |
| Voice PTT | Fase 4 | MultipeerKit + Opus (8-12 kbps) |

---

## 12. Riscos Técnicos

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| BLE background iOS limitado | Mesh para em background | State restoration + MultipeerKit foreground como canal primário |
| PMTiles grande demais | App Store reject (>200MB) | Recorte por corredor de rota (5-20MB), download on-demand |
| Ferrostar beta instável | Crashes | Pinar versão exata, contribuir fixes upstream |
| GPS impreciso em matas | Alertas falsos de desvio | Threshold alto (100m), custom deviation detector |
| BLE max 6 conexões | Grupo >7 não conecta direto | Multi-hop relay (TTL=5) cobre isso — peers intermediários retransmitem |
| Automerge bindings Swift imaturos | API pode mudar | Abstrair atrás de `RideSyncDocument` (nosso wrapper) |

---

## 13. Roadmap

### Sprint 1 (2 semanas): Mesh + Mapa
- [ ] BLE dual-role service (advertising + scanning)
- [ ] CompactLocation encoding (12 bytes)
- [ ] MultipeerKit como transporte foreground
- [ ] MapLibre com PMTiles local (basemap SP metro)
- [ ] PIN pairing flow
- [ ] Teste de bancada: 3 iPhones trocando localização

### Sprint 2 (2 semanas): Persistência + Estabilidade
- [ ] GRDB offline queue (store-and-forward)
- [ ] Automerge sync ao reconectar
- [ ] Route corridor check (Turf-Swift)
- [ ] Stale rider visual (cinza + remoção)
- [ ] GPX import (CoreGPX) para rotas pré-definidas
- [ ] Testes virtuais com MockBLEBus (padrão BitChat)

### Sprint 3 (2 semanas): Navegação
- [ ] Deploy Valhalla Docker (tiles Brasil sudeste)
- [ ] Ferrostar integration (RouteService + NavigationView)
- [ ] Map matching para trilha do líder (Meili)
- [ ] Nostr fallback transport (relays públicos)
- [ ] NIP-65 relay list management

### Sprint 4 (2 semanas): Polish + Extras
- [ ] CarPlay (FerrostarCarPlayUI)
- [ ] Voice PTT (swift-opus + MultipeerKit)
- [ ] QR code group invite (substituir PIN)
- [ ] Testes de campo extensivos (grupo de 5-7, trilha real)

### Fase 2 (após validação): Criptografia
- [ ] OpenMLS grupos (forward secrecy)
- [ ] NIP-44 mensagens 1:1 (nostr-sdk-swift)
- [ ] NIP-ee (MLS over Nostr) para grupos E2E
- [ ] Noise_XX handshake no BLE mesh

---

## 14. Licenças

| Componente | Licença | Obrigação |
|-----------|---------|-----------|
| MapLibre | BSD-2 | Manter copyright notice |
| Ferrostar | BSD-2 | Manter copyright notice |
| GRDB | MIT | Manter copyright notice |
| Automerge | MIT | Manter copyright notice |
| MultipeerKit | BSD-2 | Manter copyright notice |
| SwiftProtobuf | Apache-2 | Manter notice + NOTICE file |
| Turf-Swift | ISC | Manter copyright notice |
| CoreBluetoothMock | BSD-3 | Manter copyright notice |
| BitChat (protocolo) | Unlicense | Nenhuma (domínio público) |
| Valhalla | MIT | Manter copyright notice |
| PMTiles | BSD-3 | Manter copyright notice |
| OpenStreetMap data | ODbL | "© OpenStreetMap contributors" visível na UI |

**Nenhuma dependência GPL.** Meshtastic (GPL) e OwnTracks (EPL) são referências de UX apenas — nenhum código foi copiado.

---

## 15. Estrutura de Arquivos

```
wawa-ride/
├── Package.swift                           ← 8 dependências SPM
├── project.yml                             ← XcodeGen (iOS 16+, Swift 6)
├── THIRD_PARTY_LICENSES.md
├── Sources/
│   ├── WawaMesh/
│   │   ├── MeshConfig.swift                ← Constantes (TTL, MTU, dedup, timeouts)
│   │   ├── Transport.swift                 ← TransportCoordinator (dual BLE+MC)
│   │   ├── Packet/
│   │   │   ├── MeshPacket.swift            ← Struct + PacketType enum
│   │   │   ├── BinaryCodec.swift           ← Encode/decode 16B header
│   │   │   ├── CompactLocation.swift       ← 12-byte GPS encoding
│   │   │   ├── FragmentCodec.swift         ← Fragment/reassemble >469B
│   │   │   └── LocationPayload.swift       ← JSON-compatible model (MC path)
│   │   ├── BLE/
│   │   │   └── MeshBLEService.swift        ← Dual Central+Peripheral, relay, dedup
│   │   ├── Multipeer/
│   │   │   └── MultipeerTransport.swift    ← MultipeerKit wrapper (Codable)
│   │   ├── Dedup/
│   │   │   └── MessageDeduplicator.swift   ← LRU cache (1000/300s)
│   │   └── Extensions/
│   │       └── Data+Hex.swift
│   ├── WawaMap/
│   │   ├── RideMapView.swift               ← MapLibre SwiftUI-DSL + RiderBadge
│   │   ├── OfflineTileManager.swift        ← PMTiles management + style.json gen
│   │   └── RouteCorridor.swift             ← Turf point-to-line distance
│   ├── WawaNavigation/
│   │   ├── RouteService.swift              ← Ferrostar + Valhalla adapter
│   │   ├── MapMatchingService.swift        ← Valhalla /trace_route (Meili)
│   │   └── GroupNavigationCoordinator.swift ← Leader trail + route sharing
│   ├── WawaPersistence/
│   │   ├── AppDatabase.swift               ← GRDB (ride history, offline queue)
│   │   └── RideSyncDocument.swift          ← Automerge CRDT (rider state sync)
│   └── WawaRideApp/
│       ├── WawaRideApp.swift               ← @main entry point
│       ├── ViewModels/
│       │   └── RideSession.swift           ← Orchestrator (wires all services)
│       ├── Services/
│       │   └── SmartLocationTracker.swift   ← Adaptive GPS (OwnTracks pattern)
│       ├── Views/
│       │   ├── RootView.swift              ← idle → pairing → riding
│       │   └── PairingView.swift           ← PIN display + entry
│       └── Resources/
│           ├── Info.plist                   ← BLE + location background modes
│           ├── WawaRide.entitlements
│           └── Assets.xcassets/
├── Tests/
│   └── WawaMeshTests/
│       └── BinaryCodecTests.swift          ← Codec + dedup + fragment + CompactLocation
└── Server/
    └── docker-compose.yml                  ← Valhalla (fase 2)
```

---

## 16. Referências Bibliográficas

1. BitChat WHITEPAPER — protocolo mesh BLE + Nostr: https://github.com/permissionlesstech/bitchat
2. Automerge Sync Protocol — arXiv:2012.00472: https://arxiv.org/abs/2012.00472
3. MLS (RFC 9420) — Message Layer Security: https://www.rfc-editor.org/rfc/rfc9420
4. NIP-44 — Nostr encrypted DMs: https://github.com/nostr-protocol/nips/blob/master/44.md
5. NIP-65 — Relay list metadata: https://github.com/nostr-protocol/nips/blob/master/65.md
6. Valhalla API — turn-by-turn: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/
7. Valhalla Meili — map matching: https://valhalla.github.io/valhalla/api/map-matching/api-reference/
8. Ferrostar Book — navigation SDK: https://stadiamaps.github.io/ferrostar/
9. MapLibre Style Spec: https://maplibre.org/maplibre-style-spec/
10. PMTiles Spec: https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md
11. Protomaps Basemaps: https://docs.protomaps.com/basemaps/downloads
12. Berty Protocol — Wesh groups: https://berty.tech/docs/protocol/
13. Delta Chat SecureJoin: https://securejoin.readthedocs.io/
14. Apple CoreBluetooth Background: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
15. DP-3T iOS BLE findings: https://github.com/DP-3T/dp3t-sdk-ios
16. Meshtastic Protobufs (position encoding): https://github.com/meshtastic/protobufs
17. GRDB documentation: https://swiftpackageindex.com/groue/GRDB.swift/documentation
18. OwnTracks iOS: https://github.com/owntracks/ios
