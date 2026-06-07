# WAWA Ride — Especificação de UI/UX

## Telas do MVP (4 telas)

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Tela 1  │───▶│  Tela 2  │───▶│  Tela 3  │───▶│  Tela 4  │
│  Perfil  │    │ Criar/   │    │ Mapa ao  │    │ Resumo   │
│  Setup   │    │ Entrar   │    │ Vivo      │    │ Pós-Ride │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
  1º uso só      Pré-passeio     Durante o       Pós-passeio
                                 passeio
```

---

## TELA 1 — Perfil do Piloto

**Quando aparece:** Primeiro launch do app. Depois, acessível via ícone ⚙️ no canto do mapa.

**Objetivo:** Coletar o mínimo de informação pra identificar o piloto no grupo.

```
┌──────────────────────────────────────┐
│                                      │
│            WAWA Ride                 │
│                                      │
│         ┌────────────────┐          │
│         │                │          │
│         │   📷 Adicionar │          │
│         │     Foto       │          │
│         │   (opcional)   │          │
│         │                │          │
│         └────────────────┘          │
│                                      │
│   ┌──────────────────────────┐      │
│   │ Nome ou apelido          │      │
│   │ [ Wagner            ]    │      │
│   └──────────────────────────┘      │
│                                      │
│   ┌──────────────────────────┐      │
│   │ Moto (opcional)          │      │
│   │ [ BMW R1250GS       ]    │      │
│   └──────────────────────────┘      │
│                                      │
│   ○ Sou Líder                       │
│   ● Sou Rider                       │
│   ○ Sou Varredor                    │
│                                      │
│                                      │
│   ┌──────────────────────────┐      │
│   │     SALVAR E CONTINUAR   │      │
│   └──────────────────────────┘      │
│                                      │
└──────────────────────────────────────┘
```

**Estados:**
- Primeiro uso: campos vazios
- Edição: preenchido com dados existentes
- Validação: nome é obrigatório (min 2 caracteres)

**Comportamento:**
- Foto: abre câmera ou galeria (opcional)
- Role: radio buttons. Default = "Sou Rider"
- "Salvar" → salva em UserDefaults → vai pra Tela 2
- Se pular foto, usa avatar com iniciais (ex: "W" em círculo laranja)
- Swipe pra fechar se for edição (acessada pelo mapa)

---

## TELA 2 — Criar / Entrar no Passeio

**Quando aparece:** Após perfil (ou quando o app abre sem passeio ativo).

**Objetivo:** Criar um passeio (líder) ou descobrir e entrar em um existente (rider).

### Estado Inicial (sem passeios por perto)

```
┌──────────────────────────────────────┐
│                                      │
│          🌄  WAWA Ride               │
│                                      │
│                                      │
│   ┌──────────────────────────────┐  │
│   │                              │  │
│   │    Procurando passeios       │  │
│   │    próximos...               │  │
│   │                              │  │
│   │         ⚪ ⚪ ⚪             │  │
│   │                              │  │
│   └──────────────────────────────┘  │
│                                      │
│                                      │
│              ── OU ──                │
│                                      │
│   ┌──────────────────────────────┐  │
│   │                              │  │
│   │     🏍️  CRIAR PASSEIO       │  │
│   │                              │  │
│   └──────────────────────────────┘  │
│                                      │
└──────────────────────────────────────┘
```

### Estado com passeio detectado

```
┌──────────────────────────────────────┐
│                                      │
│       🏍️  Passeio encontrado!       │
│                                      │
│   ┌────────────────────────────────┐ │
│   │                                │ │
│   │  Serra do Rio do Rastro        │ │
│   │  Líder: Wagner                 │ │
│   │  🟢 4 riders no grupo          │ │
│   │                                │ │
│   │  ┌──────────────────────────┐ │ │
│   │  │                          │ │ │
│   │  │      ENTRAR NO PASSEIO   │ │ │
│   │  │                          │ │ │
│   │  └──────────────────────────┘ │ │
│   │                                │ │
│   └────────────────────────────────┘ │
│                                      │
│   Outros passeios próximos:          │
│   ○ Passeio do Marcão (2 riders)    │
│                                      │
│              ── OU ──                │
│                                      │
│        🏍️  CRIAR MEU PASSEIO        │
│                                      │
└──────────────────────────────────────┘
```

### Fluxo: Criar Passeio (líder)

```
1. Líder aperta "CRIAR PASSEIO"
2. Modal: "Nome do passeio" (campo de texto, placeholder: "Serra do Rio do Rastro")
3. Líder digita nome (SÓ esse campo — zero fricção)
4. Aperta "CRIAR"
5. App inicia:
   - Anuncia passeio via BLE (MeshAdvertiser)
   - Cria documento no Firestore (se tiver 4G)
   - Abre Tela 3 (Mapa ao Vivo)
6. TTS: "Passeio criado. Aguardando riders."
```

### Fluxo: Entrar no Passeio (rider)

```
1. Rider vê passeio na lista de descobertos
2. Aperta "ENTRAR NO PASSEIO"
3. App conecta via MultipeerConnectivity
4. Se tem 4G: também registra no Firestore
5. Abre Tela 3 (Mapa ao Vivo)
6. TTS: "Você entrou no passeio. [N] riders no grupo."
7. TTS para todos (broadcast): "[Nome] entrou no passeio."
```

### Estados de erro / edge cases

| Situação | UI |
|----------|----|
| Bluetooth desligado | "Ligue o Bluetooth para descobrir passeios próximos" + botão "Abrir Ajustes" |
| Localização negada | "WAWA Ride precisa da sua localização" + botão "Abrir Ajustes" |
| Passeio cheio (20+ riders) | "Passeio lotado. Máximo de 20 riders." |
| Líder já saiu (fora de alcance BLE) | Não mostra o passeio (só aparece se está no range) |
| Já está em um passeio | "Você já está em um passeio. Sair do atual?" |

---

## TELA 3 — Mapa ao Vivo (A TELA PRINCIPAL)

**Quando aparece:** Durante o passeio ativo. É onde o piloto passa 99% do tempo.

**Objetivo:** Mostrar posição de todos, rota, alertas. Ser minimamente interativa. Máximo de informação com mínimo de distração.

### Layout completo

```
┌──────────────────────────────────────┐
│ ═══════════  Status Bar  ═══════════ │
│ ┌──────────────────────────────────┐ │  ← Faixa superior (40pt)
│ │ Serra do Rio do Rastro  🟢4  ⚫⚫ │ │  Nome do passeio + riders online
│ └──────────────────────────────────┘ │    + conectividade
│                                      │
│                                      │
│                                      │
│              ┌──────┐                │
│              │  🟢  │                │  ← Pin do líder (Wagner)
│              │ Líder│                │
│              └──────┘                │
│                                      │
│   ──────── Rota do líder ────────    │  ← Polyline (track do líder)
│                                      │
│              ┌──────┐                │
│        ┌─────│  🔵  │                │  ← Pin do rider (heading indica direção)
│        │     │Pedro │                │
│        │     └──────┘                │
│  ⚠️Radar│                           │  ← Alerta de perigo no mapa
│                                      │
│                    ┌──────┐          │
│                    │  🔵  │          │
│              ┌─────│ Ana  │          │  ← Cada rider com nome
│              │     └──────┘          │
│        ⚠️Buraco                     │
│                                      │
│                         ┌──────┐     │
│                         │  🟡  │     │
│                         │João  │     │  ← Varredor (último)
│                         └──────┘     │
│                                      │
│                                      │
│ ┌──────────────────────────────────┐ │  ← Faixa inferior de status
│ │  72 km/h  ●  320m até curva    │ │  Velocidade + próxima info
│ └──────────────────────────────────┘ │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │  ⚠️ Radar  │  🎤 FALAR  │  ⏸️   │ │  ← Botões de ação
│ └──────────────────────────────────┘ │     (tamanho grande, 60pt altura)
└──────────────────────────────────────┘
```

### Elementos do mapa

**Pins dos riders:**
```
🟢 Líder      — Cor laranja/âmbar, ícone de estrela ou coroa
🔵 Rider       — Cor azul, círculo com seta indicando heading
🟡 Varredor   — Cor amarela, ícone de escudo
🔴 SOS/Pane   — Cor vermelha, pulsando, ícone de alerta
⚫ Parado      — Pin maior, pulsando suavemente (speed < 5 km/h por > 30s)
```

- Cada pin mostra: nome + velocidade (callout ao tocar)
- Seta do pin ROTACIONA conforme heading (direção real da moto)
- Velocidade é refletida na cor da borda: verde (>0), vermelho (>120), etc.

**Rota do líder:**
- Polyline roxa/laranja no mapa
- Largura: 3pt
- Animação: a rota "cresce" conform o líder avança (últimos 200m com gradiente)
- Modo improviso: rastro sendo construído ao vivo

**Alertas de perigo:**
- Ícone específico por tipo: ⚠️ radar, 🕳️ buraco, 👮 polícia, 🛢️ óleo, 🐂 animal
- Aparecem no mapa com fade-in
- Expiração visual: opacidade diminui conforme se aproxima do `expiresAt`
- Ao tocar: mostra callout com "Reportado por [nome] há [X]min — Confirmar / Limpar"

**Indicador de desvio da rota:**
- Bolinha verde/amarela/vermelha no canto superior direito
  - 🟢 Na rota (< 20m de desvio)
  - 🟡 Desviando (20-50m)
  - 🔴 Fora da rota (> 50m)

### Controles (faixa inferior)

**Botões de ação (sempre visíveis, mesmo com luva):**

| Botão | Tamanho | Ação | Feedback |
|-------|---------|------|----------|
| ⚠️ Perigo | 30% largura | Abre menu radial com opções de perigo | TTS: "Marcar qual perigo?" + menu com ícones grandes |
| 🎤 FALAR | 40% largura | Push-to-talk (segura pra falar) | Vibração leve ao ativar + indicador "🎤 Aberto" |
| ⏸️ Parar | 30% largura | Pausa/retoma tracking (pro posto, lanche) | TTS: "Tracking pausado" / "Tracking retomado" |

**Faixa de status (acima dos botões):**
- Velocidade atual (km/h)
- Próxima informação relevante:
  - "320m até curva" (se tem rota)
  - "Posto em 5km" (se parada planejada próxima)
  - "Pedro 500m atrás" (se rider distante)
  - "⚠️ Radar em 300m" (se alerta próximo, piscando)

### Comportamento

**Toques no mapa:**
- Pinch to zoom: normal
- Um toque em pin de rider: mostra callout (nome, velocidade, distância até ele)
- Um toque em alerta: mostra callout com opções "Confirmar" / "Limpar"
- Dois toques: centraliza no líder
- Long press em ponto do mapa: opção "Marcar perigo aqui"

**Orientação do mapa:**
- Default: `MKMapView.userTrackingMode = .followWithHeading` (mapa gira conforme direção)
- Modo "visão geral": pinça pra dar zoom out, vê todo o grupo
- Botão de bússola no canto: alterna entre .followWithHeading e .none

**Quando o app está em background:**
- Tela desliga (normal, economia de bateria)
- TTS continua funcionando (alertas)
- Ao acordar: mapa já está atualizado com últimas posições
- Indicador de background no Dynamic Island (iOS): "📍 WAWA Ride — 4 riders"

### Estados do mapa

**Estado: Conectado (4G ou Mesh)**
- Todos os pins atualizados em tempo real
- Rota do líder crescendo
- Indicador de conectividade: 🟢 (canto superior)

**Estado: Mesh only (sem 4G)**
- Pins atualizados via P2P
- Pode ter latência maior (2-10s)
- Indicador: 🔵 Mesh (canto superior)

**Estado: Totalmente offline**
- Últimos pins congelados (com opacidade reduzida)
- Indicador: 🔴 Offline (canto superior) + timestamp "Última atualização: 2min"
- Fila offline acumulando (será drenada quando reconectar)

**Estado: Rider perdido**
- Pin do rider fica cinza com "?"
- Após 5min sem sinal: TTS "Pedro está sem sinal há 5 minutos"
- Após 15min: pin removido do mapa (mas rider ainda está no grupo)

---

## TELA 4 — Resumo Pós-Passeio

**Quando aparece:** Após o líder encerrar o passeio (ou rider sair).

**Objetivo:** Mostrar stats do passeio, compartilhar, salvar.

```
┌──────────────────────────────────────┐
│                                      │
│      🏍️  PASSEIO ENCERRADO          │
│                                      │
│      Serra do Rio do Rastro          │
│      15 de Junho de 2026             │
│                                      │
│   ┌──────────────────────────────┐   │
│   │                              │   │
│   │    ──────── Route Map ────   │   │  ← Miniatura da rota
│   │     (snapshot do mapa)       │   │
│   │                              │   │
│   └──────────────────────────────┘   │
│                                      │
│   ┌──────────┬──────────┬─────────┐  │
│   │  128 km  │  3h 45m  │  1.280m │  │
│   │Distância │  Tempo   │  Altit. │  │
│   │          │          │   máx   │  │
│   ├──────────┼──────────┼─────────┤  │
│   │  68 km/h │   4 🛑   │   8 🚨  │  │
│   │  Vel.    │ Paradas  │ Alertas │  │
│   │  média   │          │         │  │
│   └──────────┴──────────┴─────────┘  │
│                                      │
│   Riders:                            │
│   🟢 Wagner (líder)                  │
│   🔵 Pedro                          │
│   🔵 Ana                            │
│   🟡 João (varredor)                │
│                                      │
│   ┌──────────────────────────────┐   │
│   │   📤 Compartilhar Resumo     │   │
│   └──────────────────────────────┘   │
│   ┌──────────────────────────────┐   │
│   │   🗺️  Exportar .GPX          │   │  ← Pós-MVP na real, mas botão já fica
│   └──────────────────────────────┘   │
│   ┌──────────────────────────────┐   │
│   │   ✅  VOLTAR AO INÍCIO       │   │
│   └──────────────────────────────┘   │
│                                      │
└──────────────────────────────────────┘
```

---

## Menu de Perigo (modal radial)

Quando o piloto aperta ⚠️ no mapa:

```
          🐂 Animal
    🛢️ Óleo       👮 Polícia
         ╲    │    ╱
    🕳️ Buraco ─ ⊕ ─ 📡 Radar
         ╱         ╲
   🪨 Cascalho    🚧 Acidente
                   ⚙️ Outro

Cada ícone: 60x60pt, fácil de acertar com luva
Centro: botão ✕ para fechar
Background: blur + escuro (semibold)

Toque em um ícone → fecha o menu → confirma com TTS → alerta enviado
TTS: "Radar marcado. Grupo será alertado."
```

---

## Push-to-Talk (botão 🎤 FALAR)

```
Estado NORMAL (não pressionado):
┌────────────────────────────┐
│      🎤  FALAR             │  ← Texto cinza, botão com fundo escuro
└────────────────────────────┘

Estado PRESSIONADO (segurando):
┌────────────────────────────┐
│   🎤  FALANDO...           │  ← Texto verde, botão com fundo verde claro
└────────────────────────────┘   Vibração tátil ao ativar
                                  Áudio transmitindo

Estado BLOQUEADO (trava o PTT aberto — dois toques):
┌────────────────────────────┐
│   🎤  CANAL ABERTO         │  ← Texto vermelho piscando
└────────────────────────────┘   Modo mãos-livres (útil em retas longas)
                                  Dois toques de novo = fecha
```

---

## Design System do MVP

### Cores
```
WAWA Orange (primária)     #FF6B00  — Botões, líder, destaque
WAWA Blue (rider)          #007AFF  — Pins de rider comum
WAWA Yellow (varredor)     #FFD60A  — Pin do varredor
WAWA Red (perigo/SOS)      #FF3B30  — Alertas críticos
WAWA Green (ok/rota)       #34C759  — Status: na rota, conectado
WAWA Grey (offline)        #8E8E93  — Desconectado, dados antigos
Map Background             #1C1C1E  — Fundo escuro (modo escuro forçado no mapa)
```

### Tipografia
```
Display (nome do passeio):  SF Display Bold, 28pt
Headline (títulos):         SF Display Semibold, 20pt
Body (labels, status):      SF Pro Text Regular, 16pt
Caption (velocidade pin):   SF Pro Text Bold, 12pt
Botões:                     SF Pro Text Semibold, 18pt
```

### Regras de toque
- Tamanho mínimo de alvo: 60x60pt (acima do mínimo da Apple de 44pt — moto + luva)
- Espaçamento entre botões: mínimo 20pt
- Feedback tátil em TODA ação (UIImpactFeedbackGenerator)
- Sem gestos complexos: zero swipe actions no mapa, zero long press obrigatório
- Long press existe como atalho, mas toda ação tem botão dedicado

### Modo escuro forçado
- App sempre em dark mode durante o passeio (melhor visibilidade no sol)
- Só a tela de perfil pode usar light mode
- Mapa: `MKMapView` com `overrideUserInterfaceStyle = .dark`
