# WAWA Ride — Descrição Completa do App

**Plataforma:** iOS 17+  
**Linguagem:** Swift 5.9+ (SwiftUI + UIKit)  
**Build atual:** `b17335f` (15 tarefas single-iPhone concluídas)

---

## 1. O que é

WAWA Ride é um app iOS para motociclistas que combina **navegação completa** (como Apple Maps/Google Maps) com **comunicação em grupo P2P** (walkie-talkie, mesh offline, localização ao vivo). O diferencial: funciona **sem internet e sem servidor** — toda comunicação entre riders é P2P via Bluetooth e WiFi Direct usando MultipeerConnectivity (o mesmo framework do AirDrop).

Zero login. Zero servidor. Zero taxa.

---

## 2. Arquitetura Técnica

### Stack
```
UI:         SwiftUI (telas) + UIKit (MKMapView)
Mapa:       MapKit nativo (gratuito, sem limite de MAU)
GPS:        CoreLocation (background, adaptive rate)
Transporte: MultipeerConnectivity (BLE discovery + WiFi Direct + WiFi Infra relay)
Voz live:   MCSession streams + codec Opus (placeholder AAC no MVP)
Voz async:  MeshPayload (store-and-forward via mesh P2P)
TTS:        AVSpeechSynthesizer (voz pt-BR)
Comandos:   SFSpeechRecognizer (on-device, offline)
Storage:    SQLite via GRDB.swift (rotas, histórico, fila offline)
Build:      Xcode 26.5 + xcodegen + SPM (GRDB.swift apenas)
```

### Princípio Zero-Server
```
SEM: Firebase, AWS, WebRTC, TURN/STUN, autenticação, login
TEM: MultipeerConnectivity (BLE + WiFi Direct), SQLite local, MapKit

Funcionamento offline:
[Líder] ←BLE (50m)→ [Rider 2] ←BLE→ [Rider 3] ←BLE→ [Varredor]
   Dados trafegam P2P com store-and-forward (TTL de saltos)
   Internet WiFi: acelera o mesh automaticamente (relay IP)
```

---

## 3. Funcionalidades Completas

### 3.1 App de Mapas e Navegação (nível Apple Maps/Google Maps)

**Busca:**
- Autocomplete em tempo real com resultados filtrados por proximidade (MKLocalSearchCompleter)
- Categorias rápidas: Posto, Restaurante, Café, Hotel, Supermercado, Oficina, Hospital, Estacionamento
- Histórico das últimas 10 buscas
- Ícones coloridos por categoria (⛽ laranja, 🍽️ vermelho, 🏨 roxo)
- Distância estimada em cada resultado
- Resultados com match em negrito no texto buscado

**PlaceCard (bottom sheet estilo Apple Maps):**
- Nome, endereço, distância do local
- Telefone com botão "Ligar" (se MKMapItem tem)
- Website com botão "Site" (se MKMapItem tem)
- Botão "Traçar Rota" com tempo estimado
- Abrir no Apple Maps, Google Maps (se instalado), Waze (se instalado)
- Copiar coordenadas

**Direções:**
- MKDirections: rotas por estradas reais (não linhas retas)
- Múltiplas rotas alternativas (2-3) com seleção visual
- Preview de polyline no mapa (azul tracejada)
- Zoom automático para mostrar rota completa
- Step list antes de iniciar (primeiros 3 passos, expansível "Ver todos")
- ETA e distância por rota
- Transição PlaceCard → Directions sem flicker (single sheet, conteúdo anima)

**Navegação Turn-by-Turn:**
- NavigationHUD verde no topo com instrução atual + seta
- Distância até próxima manobra
- TTS: instruções de voz em pt-BR (AVSpeechSynthesizer)
- Rerouting automático ao desviar > 50m da rota
- Auto-pause: para em semáforo/posto > 30s → pausa automática
- Auto-resume: acelera > 3 km/h → retoma automaticamente
- Indicador de chegada: "🎉 Você chegou!" quando < 50m do destino
- Resumo pós-navegação: distância, tempo, velocidade média
- Step list completa durante navegação (passos numerados, atual destacado)
- Botão overview: zoom out para ver rota completa
- Mute/unmute do TTS durante navegação

**Controles do Mapa:**
- Tipos de mapa: Standard, Satellite, Hybrid, Muted (botão flutuante)
- Trânsito em tempo real
- Bússola, escala, botão de centralizar
- 3D/Pitch habilitado
- Long press: soltar pin → PlaceCard
- Tap em lugar vazio: fecha PlaceCard (não fecha Directions)
- Modo escuro forçado (melhor visibilidade no sol)
- Mapa sempre acessível, mesmo sem passeio ativo

### 3.2 Criação e Gestão de Rotas

**Criar Rota:**
- Long press no mapa para adicionar waypoints
- Busca para adicionar waypoints por nome/endereço
- Preview da rota com MKDirections (linha azul tracejada)
- Alternativas de rota selecionáveis
- Ida e volta: toggle adiciona retorno ao ponto inicial
- Salvar com nome

**Editar Waypoints:**
- Lista de todos os pontos com ícones (📌 passagem, 🛑 parada)
- Swipe para deletar ponto específico
- Drag para reordenar
- Editar nome do ponto
- Toggle "Parada" (posto, descanso) vs "Passagem"
- Desfazer último ponto

**Importar Rotas:**
- .GPX de outros apps (Rever, Calimoto, Scenic, etc.)
- .KML do Google Maps
- Detecção automática de formato
- "Abrir com..." → WAWA Ride aparece como opção no iOS
- Import via Files app (fileImporter)
- geo: URI (abrir coordenadas de links, Safari, etc.)

**Exportar Rotas:**
- .GPX via Share Sheet (AirDrop, WhatsApp, Files, etc.)
- Abrir rota completa no Apple Maps (com waypoints)
- Abrir rota no Google Maps (com waypoints intermediários)
- Abrir rota no Waze (destino final)
- Compartilhar via mesh P2P (durante passeio)
- Duplicar rota na biblioteca

**Biblioteca de Rotas:**
- Lista de todas as rotas salvas
- Ordenar por data, nome ou distância
- Swipe para deletar (com confirmação)
- Swipe para renomear
- Duplicar rota
- Ver detalhes: waypoints, distância, origem
- Gráfico de elevação (barras laranjas, max/min/ganho)

### 3.3 Track Recording (Gravação ao Vivo)

- Botão 🔴 Record no canto do mapa
- Barra de stats ao vivo: distância, tempo, velocidade média
- Pausar/retomar gravação
- Parar → alert para nomear e salvar como rota
- Track points coletados via GPS com altitude
- Salvo automaticamente na biblioteca de rotas

### 3.4 Passeios e Grupo (Rider App Layer)

**Criar Passeio:**
- Tela dedicada: nome do passeio + selecionar rota salva (opcional)
- Anuncia via BLE para riders próximos
- Salas de comunicação criadas automaticamente (Geral + Alertas)
- GPS tracking inicia automaticamente

**Entrar em Passeio:**
- BLE scanning passivo — banner aparece se detectar passeio próximo
- "ENTRAR" com um toque
- Conexão P2P via MultipeerConnectivity
- Estado completo sincronizado (rota, riders, alertas, salas)

**Rider HUD (durante o passeio):**
- Botão Perigo: menu radial com ícones (Radar, Buraco, Polícia, Óleo, Animal, Acidente)
- Botão FALAR: Push-to-talk walkie-talkie (segura pra falar)
- Indicador PTT: glow verde pulsante na borda da tela + haptic feedback
- Botão Salas: acesso às salas de comunicação
- Status: velocidade + riders conectados
- Botão Encerrar Passeio

**Salas de Comunicação (estilo Discord):**
- Geral: automática, todos dentro, walkie-talkie do grupo
- Alertas: automática, notificações do sistema
- Criar salas privadas: qualquer rider pode criar
- Salas de voz (walkie-talkie privado) ou mensagens
- Mensagens de áudio assíncronas: grava → comprime → mesh → notifica → toca
- Timeline de mensagens por sala
- Badge de mensagens não lidas

**No mapa durante passeio:**
- Pins de todos os riders com:
  - Cor por função: 🟠 Líder, 🔵 Rider, 🟡 Varredor
  - Rotação conforme heading (direção da moto)
  - Iniciais do nome no centro
  - Tamanho maior para líder
  - Indicador de online/offline
- Alertas de perigo no mapa (ícones por tipo)
- Rota do líder como polyline

### 3.5 Áudio e Voz

**TTS (App → Piloto):**
- AVSpeechSynthesizer com voz pt-BR
- Fila de alertas com prioridade (crítico > alto > normal > background)
- Ducking: abaixa música/intercom durante fala
- Alerta crítico interrompe fala atual
- Dedup: não repete mesma frase em intervalo curto
- Mute/unmute visível no mapa e na navegação

**Comandos de Voz (Piloto → App):**
- SFSpeechRecognizer on-device (funciona offline)
- Gatilho: "Ok moto"
- Comandos: marcar radar, marcar buraco, status do grupo, falar com grupo, preciso de ajuda, etc.

**Walkie-Talkie (Piloto ↔ Pilotos):**
- Push-to-talk: botão grande na tela (dedicado para luva)
- Codec Opus 32kbps (placeholder AAC no MVP)
- Transporte: MCSession stream (P2P direto) + mesh relay
- Funciona em salas privadas (só membros ouvem)
- Glow visual + haptic feedback quando ativo

**Mensagens de Voz Assíncronas:**
- Grava → comprime → envia via mesh (store-and-forward)
- Funciona offline: armazena e entrega quando reconectar
- Notificação na sala de destino
- Playback com indicador de progresso
- Confirmação de entrega e leitura

### 3.6 Perfil e Preferências

- Nome/apelido, foto (PhotosPicker), modelo da moto
- Função padrão: Líder, Rider, ou Varredor
- Onboarding rápido (opcional, pode pular)
- Perfil editável a qualquer momento via aba Perfil

### 3.7 Histórico e Estatísticas

- Resumo pós-passeio com dados REAIS:
  - Distância percorrida (do track GPS)
  - Tempo total (startedAt → finishedAt)
  - Velocidade média (calculada)
  - Altitude máxima (max dos track points)
  - Número de paradas (waypoints isStop)
  - Riders participantes
- Histórico de passeios na aba Passeios
- Card de resumo com animação ao encerrar

### 3.8 Permission Handling

- GPS negado → banner vermelho "GPS desativado" + botão Ajustes
- Microfone negado → alerta ao tentar PTT + botão Ajustes
- Bluetooth desligado → feedback no JoinView

### 3.9 Acessibilidade

- VoiceOver labels em todos os botões críticos
- Labels contextuais (ex: "Parar de falar" vs "Falar no grupo")
- Hints para interações gestuais (PTT)

---

## 4. Arquitetura de Código

```
wawa-ride/
├── Models/           (7 arquivos: RiderProfile, Ride, Room, Route, HazardAlert, MeshPayload, VoiceAlert)
├── Services/
│   ├── Map/          (SearchService, DirectionsService, NavigationEngine)
│   ├── Route/        (RouteService, GPXParser, KMLParser, HazardService, RoomService)
│   ├── Mesh/         (MeshService, MeshAdvertiser, MeshBrowser, MeshRelay)
│   ├── Audio/        (VoiceAssistant, VoiceCommandListener, VoiceService, OpusCodec)
│   ├── Location/     (LocationService)
│   ├── Storage/      (LocalStore - SQLite/GRDB)
│   └── Transport/    (TransportManager, ConnectivityMonitor)
├── Views/            (UnifiedMapView, SearchBarView, PlaceCardView, DirectionsPreviewView,
│                      RouteCreatorView, CreateRideView, RoutesLibraryView, RidesListView,
│                      HazardMenuView, RoomListView, ProfileSetupView, JoinRideView, RideActiveView)
├── ViewModels/       (LiveMapViewModel, ProfileViewModel, etc.)
├── Extensions/       (MapAppsExporter)
└── App/              (WAWARideApp, AppState, ContentView)
```

**Total: ~40 arquivos Swift, ~7000 linhas de código.**

---

## 5. Estado Atual

### ✅ Construído e Funcional
- App de mapas completo (busca, direções, navegação)
- Criação/edição/import/export de rotas
- Gravação de track ao vivo
- PlaceCard + Directions flow polido
- UI unificada (UnifiedMapView com overlays)
- Estrutura P2P completa (código pronto, não testado com 2 dispositivos)
- Áudio/TTS/Comandos de voz (código pronto)
- Salas de comunicação (código pronto)
- Todas as 15 tarefas single-iPhone concluídas

### ❌ NÃO testado/validado
- Descoberta BLE entre 2 iPhones reais
- Mesh P2P: conexão, pins no mapa, walkie-talkie
- Mensagens de áudio via mesh
- Alertas de perigo via mesh
- Bateria em uso real (4h de passeio)
- TTS com vento/capacete
- Background GPS (iOS mata após 30min?)
- Opus codec real (placeholder AAC = 8x maior)

---

## 6. Público-Alvo

- Motociclistas organizados em grupos (motoclubes, amigos)
- Líderes de passeio que precisam navegar e comunicar com o grupo
- Riders que fazem passeios em áreas sem cobertura de celular (serra, montanha)
- Pilotos que usam apps como Rever, Calimoto, Scenic e querem comunicação em grupo
- Mercado primário: Brasil (app em pt-BR, otimizado para dinâmica de motoclube)

---

## 7. Diferenciais vs Concorrentes

| Feature | Rever/Calimoto | WAWA Ride |
|---------|---------------|-----------|
| Navegação turn-by-turn | ✅ | ✅ |
| Rotas offline | ✅ | ✅ (cache MapKit) |
| Gravação de track | ✅ | ✅ |
| Compartilhar rota | ✅ (.GPX) | ✅ (.GPX + KML) |
| Ver riders no mapa | ❌ | ✅ (P2P) |
| Walkie-talkie | ❌ | ✅ (P2P sem internet) |
| Alertas de perigo | ❌ | ✅ (P2P) |
| Funciona sem celular | ❌ | ✅ (mesh BLE/WiFi Direct) |
| Zero servidor/login | ❌ | ✅ |
| Salas tipo Discord | ❌ | ✅ |
| Preço | $$ (assinatura) | A definir |

---

## 8. O Que Falta Para Produção

1. **Validar P2P com 2+ iPhones** — a premissa central do app
2. **Integrar libopus real** — codec placeholder 8x maior que necessário
3. **Teste de bateria** — 4h de GPS + BLE + áudio
4. **Teste de áudio na moto** — TTS audível com vento e capacete?
5. **Teste de background** — iOS mata o app em passeios longos?
6. **App Store Connect** — provisioning, screenshots, descrição
7. **Ícone do app** — assets visuais
8. **Onboarding UX** — primeira experiência do usuário
9. **Analytics de uso** — opcional, mas útil para iterar
10. **Android** — MultipeerConnectivity é Apple-only. Cross-platform precisaria Google Nearby Connections
