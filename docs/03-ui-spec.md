# WAWA Ride — Especificação de UI/UX (v2)

## Telas do MVP (5 telas + modais)

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Tela 1  │───▶│  Tela 2  │───▶│  Tela 3  │───▶│  Tela 4  │───▶│  Tela 5  │
│  Perfil  │    │ Criar/   │    │ Mapa ao  │    │  Salas   │    │ Resumo   │
│  Setup   │    │ Entrar   │    │ Vivo      │    │          │    │ Pós-Ride │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
  1º uso só      Pré-passeio     Durante o       Durante o       Pós-passeio
                                 passeio         passeio
                                              (acessível do mapa)
```

---

## TELA 1 — Perfil do Piloto

Igual v1. Sem alterações significativas.
(Ver 03-ui-spec.md v1 — mantido igual)

---

## TELA 2 — Criar / Entrar no Passeio

Igual v1 em estrutura. Uma adição: **roteamento**.

### Nova opção no "Criar Passeio" (líder):

```
┌──────────────────────────────────────┐
│                                      │
│       🏍️  CRIAR PASSEIO             │
│                                      │
│   Nome do passeio:                   │
│   ┌──────────────────────────┐      │
│   │ Serra do Rio do Rastro   │      │
│   └──────────────────────────┘      │
│                                      │
│   Rota:                             │
│   ○ Sem rota (modo livre)           │
│   ● Carregar rota salva         ▸   │
│   ○ Desenhar rota no mapa       ▸   │
│                                      │
│   ┌────────────────────────────┐    │
│   │       CRIAR PASSEIO        │    │
│   └────────────────────────────┘    │
└──────────────────────────────────────┘
```

---

## TELA 3 — Mapa ao Vivo (a tela principal)

### Layout atualizado com botão de salas

```
┌──────────────────────────────────────┐
│ ═══════════  Status Bar  ═══════════ │
│ ┌──────────────────────────────────┐ │
│ │ Serra do Rio do Rastro  🟢4  🏠 │ │  ← 🏠 = acesso às salas
│ └──────────────────────────────────┘ │
│                                      │
│              ┌──────┐                │
│              │  🟢  │                │
│              │Líder │                │
│              └──────┘                │
│                                      │
│   ──────── Rota ────────────────     │
│                                      │
│              ┌──────┐    ┌──────┐    │
│              │  🔵  │    │  🔵  │    │
│              │Pedro │    │ Ana  │    │
│              └──────┘    └──────┘    │
│                                      │
│                         ┌──────┐     │
│                         │  🟡  │     │
│                         │João  │     │
│                         └──────┘     │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │  72 km/h  ●  320m até curva    │ │
│ └──────────────────────────────────┘ │
│                                      │
│ ┌──────────┬──────────┬──────────┐  │
│ │ ⚠️ Perigo│ 🎤 FALAR │ 🏠 Salas │  │  ← Botão de salas adicionado
│ └──────────┴──────────┴──────────┘  │
└──────────────────────────────────────┘
```

### Indicadores no mapa (v2)

```
🟢 Líder      — Laranja, estrela/coroa
🔵 Rider       — Azul, seta com heading
🟡 Varredor   — Amarelo, escudo
🔴 SOS/Pane   — Vermelho pulsante
⚫ Offline     — Cinza, opacidade 50%, "?" no centro
📍 Waypoint    — Bandeira (parada planejada)
⚠️ Perigo      — Ícone específico (radar, buraco, etc.)
```

### Indicador de sala com atividade

```
🏠 Salas           — Normal
🏠🔊 Salas         — Alguém falando na Geral
🏠🔵 Salas         — Mensagem nova em alguma sala
🏠🔴 Salas         — SOS ou alerta crítico
```

---

## TELA 4 — Salas (nova)

### Lista de salas (já especificada em 07-rooms-channels.md)

### Criação de sala (modal)

```
┌──────────────────────────────────────┐
│  Cancelar        Nova Sala    Criar  │
│                                      │
│   Tipo:                              │
│   ● 🎙️ Voz ao vivo (walkie-talkie)  │
│   ○ 💬 Só mensagens de voz          │
│                                      │
│   Nome da sala:                      │
│   ┌──────────────────────────┐      │
│   │ Líder+Varredor           │      │
│   └──────────────────────────┘      │
│                                      │
│   Privacidade:                       │
│   ● 🔒 Privada (só membros veem)    │
│   ○ 🔓 Pública (todos veem)         │
│                                      │
│   Membros:                           │
│   ☑️ Wagner (líder)                  │
│   ☑️ João (varredor)                │
│   ☐ Pedro                           │
│   ☐ Ana                             │
│                                      │
└──────────────────────────────────────┘
```

### Dentro de uma sala (timeline de áudio)

(Já especificada em 07-rooms-channels.md, seção 6.2)

---

## TELA 5 — Resumo Pós-Passeio

Igual v1. Adição de:
- Botão "Salvar rota" (se o passeio teve rota)
- Botão "Exportar .GPX" → Share Sheet
- Estatísticas das salas: "3 salas, 12 mensagens de voz"

---

## Criação de Rota (modal no mapa)

```
┌──────────────────────────────────────┐
│  Cancelar      Criar Rota     Salvar │
│                                      │
│   Modo:                              │
│   ● Desenhar (colocar waypoints)    │
│   ○ Importar .GPX                   │
│                                      │
│   ┌────────────────────────────────┐ │
│   │                                │ │
│   │         [MAPA]                 │ │
│   │                                │ │
│   │   📍 Start                     │ │
│   │       │                        │ │
│   │       │ (polyline preview)     │ │
│   │       │                        │ │
│   │   🛑 Posto Ipiranga            │ │
│   │       │                        │ │
│   │       │                        │ │
│   │   🏁 Mirante                   │ │
│   │                                │ │
│   └────────────────────────────────┘ │
│                                      │
│   Long press no mapa: adiciona waypoint
│   Drag no waypoint: reposiciona
│   Tap no waypoint: editar nome, tipo
│                                      │
│   ┌──────────┐  ┌────────────────┐  │
│   │ + Waypoint│  │ Desfazer último│  │
│   └──────────┘  └────────────────┘  │
└──────────────────────────────────────┘
```

---

## Menu de Perigo Radial (v2 — ícones maiores)

```
          🐂 Animal
    🛢️ Óleo       👮 Polícia
         ╲    │    ╱
    🕳️ Buraco ─ ⊕ ─ 📡 Radar
         ╱         ╲
   🪨 Cascalho    🚧 Acidente
                   ⚙️ Outro

Cada ícone: 70x70pt (maior que v1 pra luva grossa)
Área de toque efetiva: 80x80pt (com padding invisível)
```

---

## Push-to-Talk (v2 — com indicador de sala)

```
Estado NORMAL:
┌────────────────────────────┐
│      🎤  FALAR             │  ← Fala na sala ativa (padrão: Geral)
│      (Geral)               │
└────────────────────────────┘

Estado PRESSIONADO:
┌────────────────────────────┐
│   🎤  FALANDO NA GERAL     │  ← Fundo verde
└────────────────────────────┘

Estado SALA PRIVADA ATIVA:
┌────────────────────────────┐
│   🎤  FALAR                │
│   (Líder+Varredor)         │  ← Mostra qual sala
└────────────────────────────┘
```

---

## Gravação de Mensagem de Voz (UI)

```
DENTRO DE UMA SALA:

┌──────────────────────────────────────┐
│  [...]                              │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  🎙️ GRAVANDO...    0:15       │  │  ← Enquanto grava
│  │  ┌──────────────────────────┐  │  │
│  │  │ ████████░░░░░░░░░░░░░░░ │  │  │  ← Barra de progresso
│  │  └──────────────────────────┘  │  │
│  │  Solte para enviar             │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  Cancelar                      │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘

MODO MOTO (gravação por comando de voz):
  "Ok moto, mandar mensagem pra Geral"
  → App vibra, começa a gravar
  → "Ok moto, enviar" ou silêncio por 3s → envia
  → "Ok moto, cancelar" → cancela

PLAYBACK DE MENSAGEM RECEBIDA:
┌──────────────────────┐
│ ▶️ 0:12              │  ← Toca pra ouvir
└──────────────────────┘
  Barra de progresso circular durante playback
  Velocidade: 1x (normal). Futuro: 1.5x, 2x.
```

---

## Design System (v2 — reforçado pra moto)

### Regras de toque (v2)
- Tamanho mínimo de alvo: **70x70pt** (acima dos 60pt da v1)
- Espaçamento entre botões: mínimo 24pt
- **Zero gestos complexos.** Nada de swipe, pinch complexo, multi-touch
- Pinch to zoom: OK (já é natural no mapa)
- Long press: só pra adicionar waypoint (rota) e marcar perigo (mapa)
- Todo botão tem feedback tátil (UIImpactFeedbackGenerator)
- Todo botão tem área de toque estendida (padding invisível de 10pt)

### Cores (v2)
```
WAWA Orange (primária)     #FF6B00  — Botões, líder, destaque
WAWA Blue (rider)          #007AFF  — Pins de rider comum
WAWA Yellow (varredor)     #FFD60A  — Pin do varredor
WAWA Red (perigo/SOS)      #FF3B30  — Alertas críticos, badge
WAWA Green (ok/rota)       #34C759  — Status: na rota, conectado
WAWA Grey (offline)        #8E8E93  — Desconectado, dados antigos
WAWA Purple (rota)         #AF52DE  — Polyline da rota
Map Background             #1C1C1E  — Fundo escuro (modo escuro forçado)
Room Badge Blue            #5AC8FA  — Badge de nova mensagem
```

### Áudio feedback (TTS) para ações da UI

| Ação | TTS |
|------|-----|
| Passeio criado | "Passeio criado. Aguardando riders." |
| Rider entrou | "[Nome] entrou no passeio." |
| Sala criada | "Sala [nome] criada." |
| Mensagem enviada | (som de "whoosh", sem fala) |
| Mensagem recebida | "Nova mensagem de [nome] na sala [sala]." (só se não estiver vendo a sala) |
| Perigo marcado | "[Tipo] marcado. Grupo alertado." |
| SOS recebido | "Atenção! [Nome] precisa de ajuda." (repete 3x) |
| Rota salva | "Rota salva com [N] waypoints." |
| Offline | "Sem conexão. Dados serão sincronizados quando possível." |
| Reconectado | "Conexão restaurada. [N] mensagens pendentes." |
