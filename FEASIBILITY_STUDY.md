# Wawa Ride — Estudo de Viabilidade Técnica

**Data:** 2026-06-14
**Objetivo:** MVP para grupo de motociclistas se verem no mesmo mapa, com pareamento Bluetooth persistente e comunicação P2P via internet sem servidor.

---

## 1. Requisitos

| # | Requisito | Prioridade |
|---|-----------|-----------|
| R1 | Grupo de motociclistas se veem no mesmo mapa | MVP |
| R2 | Pareamento via Bluetooth com memória (persistente) | MVP |
| R3 | Comunicação via internet sem servidor após pareamento | MVP |
| R4 | Compartilhamento de localização em tempo real | MVP |

---

## 2. Análise de Viabilidade por Componente

### 2.1 Pareamento Bluetooth com Memória

**Tecnologia candidata: MultipeerConnectivity (Apple Native)**

| Aspecto | Avaliação |
|---------|-----------|
| Descoberta de peers | ✅ `MCNearbyServiceBrowser` / `MCNearbyServiceAdvertiser` — funciona via BLE + WiFi |
| Persistência do peer | ✅ `MCPeerID` pode ser serializado com `NSKeyedArchiver` e salvo em `UserDefaults` |
| Reconexão automática | ✅ PeerIDs persistentes permitem reconexão sem re-pareamento |
| Segurança | ✅ `MCEncryptionRequired` — criptografia obrigatória na conexão |
| Alcance | Bluetooth ~30m (pareamento inicial apenas) |

**Conclusão: ✅ TOTALMENTE VIÁVEL**

O MultipeerConnectivity foi projetado exatamente para este cenário. O peerID arquivado em `UserDefaults` garante que o app "lembre" dos dispositivos pareados entre sessões.

### 2.2 Comunicação P2P via Internet sem Servidor

**Este é o componente crítico. Vamos analisar cada alternativa.**

#### Alternativa A: WebRTC com STUN público (sem TURN)

| Cenário | Taxa de Sucesso |
|---------|----------------|
| Mesma rede WiFi | ~100% |
| WiFi ↔ WiFi (redes diferentes) | ~80% |
| 4G/5G ↔ 4G/5G (mesma operadora) | ~70-80% |
| 4G/5G ↔ 4G/5G (operadoras diferentes) | ~50-60% |
| CGNAT (symmetric NAT) | ~0-5% |

**Problema:** ~20-30% dos pares de motociclistas em 4G/5G **não vão conseguir se conectar** via STUN-only. Em CGNAT (comum em operadoras brasileiras como Claro, TIM, Vivo), a taxa de falha pode ser muito maior.

#### Alternativa B: WebRTC com STUN + TURN público gratuito

| Servidor TURN gratuito | Limites |
|------------------------|---------|
| `openrelay.metered.ca` | 500MB/mês, 50 conexões simultâneas |
| `turn.cloudflare.com` (via Cloudflare Calls) | Rate limit generoso |
| `numb.viagenie.ca` | Cadastro gratuito, limites baixos |

**Conclusão:** Tecnicamente viável para MVP com grupo pequeno (~5-10 motociclistas). Para produção, seria necessário um TURN server próprio (~$5-10/mês).

#### Alternativa C: Holepunch / Pear Runtime (HyperDHT + Hyperswarm)

**O que é:** Stack P2P completo — DHT distribuída para descoberta + UDP hole punching para conexão direta. Usado pelo app **WhereFam** (vencedor do Global Pears Hackathon, 2025).

| Aspecto | Avaliação |
|---------|-----------|
| NAT traversal | ✅ UDP hole punching via HyperDHT — **não precisa de STUN/TURN** |
| Servidor | ✅ Zero — DHT pública para descoberta |
| iOS | ⚠️ Requer Bare Runtime (JavaScript) embutido no app Swift |
| Complexidade | 🔴 Alta — integração Swift↔JavaScript, runtime adicional |
| Maturidade | 🟡 WhereFam provou o conceito, mas é um hackathon project |

**Projeto referência:** [`jj10133/WhereFam-iOS`](https://github.com/jj10133/WhereFam-iOS) — app de compartilhamento de localização P2P para famílias, sem servidor, usando Holepunch.

#### Alternativa D: CloudKit como Relay "grátis"

| Aspecto | Avaliação |
|---------|-----------|
| Custo | $0 — 40 req/s, 5GB storage grátis |
| Servidor | Zero manutenção — infraestrutura Apple |
| Latência | Alta (~2-5s) — inadequada para tempo real |
| Dependência | Apple-only, requer iCloud |

**Conclusão:** Funciona como fallback, mas a latência é alta demais para localização em tempo real.

#### Alternativa E: Apple Push Notification como Signaling

| Aspecto | Avaliação |
|---------|-----------|
| Custo | $0 — APNs é gratuito |
| Servidor | Zero — Apple gerencia |
| Latência | Média (~500ms-2s) |
| Taxa | Limitada, não foi feita para dados em tempo real |

**Conclusão:** Útil como canal de signaling para WebRTC, mas não para dados contínuos de localização.

### 2.3 Matriz de Decisão

| Critério | WebRTC STUN-only | WebRTC + TURN free | Holepunch | CloudKit | MC + APNs |
|----------|:---:|:---:|:---:|:---:|:---:|
| Zero servidor | 🟢 | 🟡 (TURN free) | 🟢 | 🟡 (Apple) | 🟡 (Apple) |
| Confiabilidade 4G | 🔴 70% | 🟢 99% | 🟢 ~90% | 🟢 100% | 🟢 100% |
| Complexidade | 🟢 Baixa | 🟢 Baixa | 🔴 Alta | 🟡 Média | 🟡 Média |
| Latência | 🟢 <100ms | 🟢 <200ms | 🟢 <100ms | 🔴 2-5s | 🔴 1-2s |
| Swift nativo | 🟢 | 🟢 | 🔴 (JS runtime) | 🟢 | 🟢 |
| Motor até 10 peers | 🟢 | 🟢 | 🟢 | 🟡 | 🟡 |
| Escala produção | 🔴 | 🟡 | 🟢 | 🟡 | 🔴 |

---

## 3. Arquitetura Recomendada para o MVP

```
┌─────────────────────────────────────────────────────────────────┐
│                    ARQUITETURA Wawa Ride MVP                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FASE 1: PAREAMENTO (Bluetooth)                                  │
│  ┌──────────┐    BLE/WiFi-P2P    ┌──────────┐                   │
│  │ iPhone A │◄──────────────────►│ iPhone B │                   │
│  │ Moto 1   │  MultipeerConn     │ Moto 2   │                   │
│  └──────────┘                    └──────────┘                   │
│       │                                │                         │
│       │  Troca de:                     │                         │
│       │  - PeerIdentity (persistente)  │                         │
│       │  - WebRTC signaling info       │                         │
│       │  - Chave de grupo (UUID)       │                         │
│       ▼                                ▼                         │
│                                                                  │
│  FASE 2: COMUNICAÇÃO (Internet P2P)                              │
│  ┌──────────┐    WebRTC DataCh    ┌──────────┐                   │
│  │ iPhone A │◄──────────────────►│ iPhone B │                   │
│  │          │   STUN público      │          │                   │
│  └──────────┘   + TURN free       └──────────┘                   │
│       │           (fallback)           │                         │
│       │                                │                         │
│       │  Dados via DataChannel:        │                         │
│       │  - Coordenadas GPS (30Hz)      │                         │
│       │  - Velocidade / direção        │                         │
│       │  - Status do motociclista      │                         │
│       ▼                                ▼                         │
│                                                                  │
│  FASE 3: MAPA COMPARTILHADO                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ MapKit + Annotations em tempo real                        │   │
│  │ Cada peer = um MKAnnotation atualizado via WebRTC         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Stack Tecnológica

| Camada | Tecnologia | Justificativa |
|--------|-----------|---------------|
| Pareamento inicial | `MultipeerConnectivity` | Apple nativo, BLE + WiFi, persistente |
| Identidade persistente | `MCPeerID` + `NSKeyedArchiver` + `UserDefaults` | Documentado pela Apple |
| Comunicação internet | `WebRTC` (GoogleWebRTC via SPM) | Padrão da indústria, DataChannel nativo |
| Signaling | Troca de SDP/ICE via `MultipeerConnectivity` | Paper Hiroshima U. — zero servidor |
| STUN | `stun.l.google.com:19302` | Gratuito, público |
| TURN fallback | `openrelay.metered.ca` | Gratuito para MVP |
| Localização | `CoreLocation` | Apple nativo, 10-30Hz |
| Mapa | `MapKit` (iOS 18+) | Apple nativo, zero custo |
| Persistência local | `SwiftData` ou `UserDefaults` | Grupo, peers, rotas |

---

## 4. Projetos GitHub Relevantes

### 4.1 Referências Diretas

| Projeto | ⭐ | Tech Stack | O que aproveitar |
|---------|---|-----------|------------------|
| [**swift-libp2p/ChatAppExample-iOS**](https://github.com/swift-libp2p/ChatAppExample-iOS) | ~70 | Swift, libp2p, mDNS, Noise | Chat P2P sem servidor — <40MB RAM. Código de descoberta e conexão. |
| [**jj10133/WhereFam-iOS**](https://github.com/jj10133/WhereFam-iOS) | ~10 | Swift + Holepunch (Bare JS) | Localização P2P sem servidor — prova de conceito funcional. |
| [**maxxfrazer/MultipeerHelper**](https://github.com/maxxfrazer/MultipeerHelper) | ~300 | Swift, MultipeerConnectivity | Wrapper limpo para MC com RealityKit. Código de conexão P2P local. |
| [**scacap/mobile.multipeerkit**](https://github.com/scacap/mobile.multipeerkit) | — | Swift/Kotlin, MC | MultipeerConnectivity cross-platform (Apple-only na prática). |

### 4.2 Referências Indiretas (Componentes que Precisamos)

| Projeto | ⭐ | Tech Stack | O que aproveitar |
|---------|---|-----------|------------------|
| [**TICESoftware/tice-ios**](https://github.com/TICESoftware/tice-ios) | ~200 | Swift, MVVM, E2E | App de localização em tempo real com grupos — arquitetura MVVM, UI. |
| [**ZzhangYH/Find-Nearby**](https://github.com/ZzhangYH/Find-Nearby) | — | Swift, MultipeerConnectivity | Chat/discovery com MC — código de descoberta de peers. |
| [**swift-libp2p/swift-libp2p**](https://github.com/swift-libp2p/swift-libp2p) | ~69 | Swift, libp2p, SwiftNIO | Stack P2P completo em Swift nativo — PubSub, DHT, mDNS. |
| [**LemonSpike/MultipeerConnect-Swift**](https://github.com/LemonSpike/MultipeerConnect-Swift) | — | Swift, MC | Exemplo MC com arquitetura client-server local. |

### 4.3 O que Extrair de Cada Um

```
ChatAppExample-iOS
├── Descoberta de peers (mDNS/Bonjour)
├── Conexão P2P sem servidor
└── Padrão de integração libp2p com SwiftUI

WhereFam-iOS
├── Modelo de grupo (shared key/topic)
├── NAT traversal sem STUN/TURN (HyperDHT)
├── MapLibre + tiles P2P offline
└── Arquitetura iOS + P2P runtime

MultipeerHelper
├── Wrapper limpo para MCSession
├── Gerenciamento de convites/invites
└── Padrão de reconexão

TICE
├── MVVM para app de localização
├── UI de grupo/mapa
├── E2E encryption
└── Gerenciamento de permissões de localização
```

---

## 5. Análise de Riscos

### Risco 1: NAT Traversal em 4G/5G — 🔴 ALTO

**Problema:** ~20-30% dos pares falham no STUN-only. Motociclistas em movimento trocam de torres constantemente, agravando o problema.

**Mitigação MVP:** TURN público gratuito como fallback.
**Mitigação produção:** TURN server próprio (~$5/mês) OU migrar para Holepunch.

### Risco 2: Topologia Mesh com Múltiplos Peers — 🟡 MÉDIO

**Problema:** Com N motociclistas, são N×(N-1)/2 conexões WebRTC. Com 10 motos = 45 conexões.

**Mitigação:** Topologia star — 1 líder faz relay para todos. Com 10 motos = 9 conexões.

### Risco 3: Background Mode iOS — 🟡 MÉDIO

**Problema:** iOS suspende apps em background. Localização em tempo real precisa de `location` background mode.

**Mitigação:** `CLLocationManager.allowsBackgroundLocationUpdates = true` + `location` UIBackgroundMode. Aprovado pela Apple para apps de navegação.

### Risco 4: Bateria — 🟡 MÉDIO

**Problema:** GPS + WebRTC + tela ligada = consumo alto.

**Mitigação:** Throttle de localização quando em grupo (5-10Hz em vez de 30Hz), DataChannel binary mode (protobuf compacto).

---

## 6. Viabilidade Temporal (MVP)

| Fase | Dias estimados | Entregável |
|------|:---:|---|
| Setup do projeto | 1 | Xcode project, SPM deps, estrutura |
| MultipeerConnectivity (pareamento) | 2 | Discovery, pairing, persistência |
| WebRTC integration | 3 | DataChannel, STUN/TURN, signaling via MC |
| CoreLocation + transmissão | 1 | GPS → protobuf → DataChannel |
| MapKit + annotations | 2 | Mapa, annotations em tempo real, cards |
| UI básica | 2 | Grupo, pareamento, mapa |
| Testes + debug | 2 | Testes de campo (2-3 iPhones) |
| **Total MVP** | **13 dias** | App funcional com 2-3 motociclistas |

---

## 7. Perguntas em Aberto

1. **TURN server no MVP:** Usar `openrelay.metered.ca` (500MB grátis) ou já provisionar um coturn em VPS ($5/mês)?

2. **Topologia:** Star (líder faz relay) ou mesh (todos→todos)? Mesh é mais resiliente mas escala mal. Star é mais simples.

3. **Identidade do motociclista:** Só device name? Ou perfil com nome/foto? (MVP vs v2)

4. **Grupo:** Como formar o grupo? QR code? Código numérico? Convite via MultipeerConnectivity?

5. **Fallback offline:** Se internet cair, o MultipeerConnectivity continua funcionando em alcance (~100m). Implementar failover automático?

---

## 8. Conclusão

### ✅ O MVP é VIÁVEL com as seguintes condições:

1. **Pareamento Bluetooth:** MultipeerConnectivity + `NSKeyedArchiver` — **100% viável, baixa complexidade.**

2. **Comunicação internet sem servidor:** WebRTC com STUN público cobre **70-80% dos casos**. Para os 20-30% restantes, usar TURN gratuito como fallback. **VIÁVEL para MVP, requer TURN próprio para produção.**

3. **Localização em tempo real:** CoreLocation + WebRTC DataChannel — **100% viável, tecnologia madura.**

4. **Alternativa zero-servidor real:** Holepunch/Pear Runtime (WhereFam) — **tecnicamente superior** (NAT traversal próprio, zero servidor), mas complexidade de integração Swift↔JavaScript é **alta**. Recomendado para v2.

### Recomendação Final

**MVP: WebRTC + STUN público + TURN gratuito como fallback.**
- Zero infraestrutura para desenvolver
- Cobre a grande maioria dos cenários reais
- Caminho mais curto para validar com usuários
- Migração para Holepunch ou TURN próprio na v2 se necessário
